class CarnavalPickupOrderQuantity {
  const CarnavalPickupOrderQuantity({
    required this.orderId,
    required this.quantity,
  });

  final int orderId;
  final double quantity;
}

class CarnavalPickupProduct {
  const CarnavalPickupProduct({
    required this.productId,
    required this.productName,
    required this.quantity,
    this.orders = const [],
  });

  final int productId;
  final String productName;
  final double quantity;
  final List<CarnavalPickupOrderQuantity> orders;
}

class CarnavalPickupProvider {
  const CarnavalPickupProvider({
    required this.providerId,
    required this.providerName,
    required this.products,
  });

  final int providerId;
  final String providerName;
  final List<CarnavalPickupProduct> products;
}

List<CarnavalPickupProvider> buildCarnavalPickupSummary(
  List<Map<String, dynamic>> details, {
  required int excludedProviderId,
}) {
  final providers = <int, _MutableProvider>{};

  for (final detail in details) {
    final product = detail['Productos'];
    if (product is! Map) continue;

    final orderId = (detail['order_id'] as num?)?.toInt();
    final productId = (product['id'] as num?)?.toInt();
    final providerId = (product['proveedor'] as num?)?.toInt();
    if (orderId == null ||
        productId == null ||
        providerId == null ||
        providerId == excludedProviderId) {
      continue;
    }

    final providerData = product['proveedores'];
    final providerName = providerData is Map
        ? providerData['name']?.toString().trim()
        : null;
    final quantity = (detail['quantity'] as num?)?.toDouble() ?? 0;
    final extra = (detail['extra'] as num?)?.toDouble() ?? 0;
    final totalQuantity = quantity + extra;
    if (totalQuantity <= 0) continue;

    final provider = providers.putIfAbsent(
      providerId,
      () => _MutableProvider(
        providerName?.isNotEmpty == true
            ? providerName!
            : 'Proveedor #$providerId',
      ),
    );
    final productName = product['name']?.toString().trim();
    final pickupProduct = provider.products.putIfAbsent(
      productId,
      () => _MutableProduct(
        productName?.isNotEmpty == true ? productName! : 'Producto #$productId',
      ),
    );
    pickupProduct.quantity += totalQuantity;
    pickupProduct.orders.update(
      orderId,
      (current) => current + totalQuantity,
      ifAbsent: () => totalQuantity,
    );
  }

  final result = providers.entries.map((entry) {
    final products = entry.value.products.entries.map((product) {
      final orders =
          product.value.orders.entries
              .map(
                (order) => CarnavalPickupOrderQuantity(
                  orderId: order.key,
                  quantity: order.value,
                ),
              )
              .toList()
            ..sort((a, b) => b.orderId.compareTo(a.orderId));
      return CarnavalPickupProduct(
        productId: product.key,
        productName: product.value.name,
        quantity: product.value.quantity,
        orders: orders,
      );
    }).toList()..sort((a, b) => a.productName.compareTo(b.productName));
    return CarnavalPickupProvider(
      providerId: entry.key,
      providerName: entry.value.name,
      products: products,
    );
  }).toList()..sort((a, b) => a.providerName.compareTo(b.providerName));

  return result;
}

List<Map<String, dynamic>> buildCarnavalPickupExportRows(
  List<CarnavalPickupProvider> summary,
) {
  return [
    for (final provider in summary)
      for (final product in provider.products)
        for (final order in product.orders)
          {
            'proveedor': provider.providerName,
            'orden': order.orderId,
            'producto': product.productName,
            'cantidad': order.quantity,
          },
  ];
}

class _MutableProvider {
  _MutableProvider(this.name);

  final String name;
  final Map<int, _MutableProduct> products = {};
}

class _MutableProduct {
  _MutableProduct(this.name);

  final String name;
  double quantity = 0;
  final Map<int, double> orders = {};
}
