class SupplierPaymentSummary {
  final int id;
  final String name;
  final String? logo;
  final String? banner;
  final String? ubicacion;
  final double? contacto;
  final String? direccion;
  final String? categoria;
  final bool status;
  final double totalCup;
  final double totalUsd;
  final double totalEuro;
  final double totalCash; // New: Total amount paid in cash
  final double totalTransfer; // New: Total amount paid via transfer
  final int totalOrders;
  List<OrderPaymentDetail>? orders; // Loaded on demand

  SupplierPaymentSummary({
    required this.id,
    required this.name,
    this.logo,
    this.banner,
    this.ubicacion,
    this.contacto,
    this.direccion,
    this.categoria,
    required this.status,
    required this.totalCup,
    required this.totalUsd,
    required this.totalEuro,
    required this.totalCash,
    required this.totalTransfer,
    required this.totalOrders,
    this.orders,
  });

  factory SupplierPaymentSummary.fromJson(Map<String, dynamic> json) {
    return SupplierPaymentSummary(
      id: json['proveedor_id'] as int,
      name: json['proveedor_name'] as String? ?? 'Sin nombre',
      logo: json['logo'] as String?,
      banner: json['banner'] as String?,
      ubicacion: json['ubicacion'] as String?,
      contacto:
          json['contacto'] != null
              ? (json['contacto'] as num).toDouble()
              : null,
      direccion: json['direccion'] as String?,
      categoria: json['categoria'] as String?,
      status: json['status'] as bool? ?? true,
      totalCup: (json['total_cup'] as num?)?.toDouble() ?? 0.0,
      totalUsd: (json['total_usd'] as num?)?.toDouble() ?? 0.0,
      totalEuro: (json['total_euro'] as num?)?.toDouble() ?? 0.0,
      totalCash: (json['total_cash'] as num?)?.toDouble() ?? 0.0,
      totalTransfer: (json['total_transfer'] as num?)?.toDouble() ?? 0.0,
      totalOrders: json['total_orders'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'proveedor_id': id,
      'proveedor_name': name,
      'logo': logo,
      'banner': banner,
      'ubicacion': ubicacion,
      'contacto': contacto,
      'direccion': direccion,
      'categoria': categoria,
      'status': status,
      'total_cup': totalCup,
      'total_usd': totalUsd,
      'total_euro': totalEuro,
      'total_cash': totalCash,
      'total_transfer': totalTransfer,
      'total_orders': totalOrders,
    };
  }
}

class OrderPaymentDetail {
  final int orderId;
  final DateTime createdAt;
  final double total;
  final bool isTransfer; // True if transfer, False if cash
  final List<ProductPaymentDetail> products;

  OrderPaymentDetail({
    required this.orderId,
    required this.createdAt,
    required this.total,
    required this.isTransfer,
    required this.products,
  });

  double get discountAmount => isTransfer ? total * 0.15 : total * 0.05;
  double get totalToPay => total - discountAmount;
}

class ProductPaymentDetail {
  final int productId;
  final String productName;
  final String? productImage;
  final int quantity;
  final double price;
  final double subtotal;

  ProductPaymentDetail({
    required this.productId,
    required this.productName,
    this.productImage,
    required this.quantity,
    required this.price,
    required this.subtotal,
  });

  factory ProductPaymentDetail.fromJson(Map<String, dynamic> json) {
    return ProductPaymentDetail(
      productId: json['product_id'] as int,
      productName: json['product_name'] as String? ?? 'Sin nombre',
      productImage: json['product_image'] as String?,
      quantity: json['quantity'] as int? ?? 0,
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      'product_name': productName,
      'product_image': productImage,
      'quantity': quantity,
      'price': price,
      'subtotal': subtotal,
    };
  }
}

class PaymentStats {
  final double totalCup;
  final double totalUsd;
  final double totalEuro;
  final int totalSuppliers;
  final double averagePerSupplier;
  final List<SupplierPaymentSummary> topSuppliers;

  PaymentStats({
    required this.totalCup,
    required this.totalUsd,
    required this.totalEuro,
    required this.totalSuppliers,
    required this.averagePerSupplier,
    required this.topSuppliers,
  });

  factory PaymentStats.fromSuppliers(List<SupplierPaymentSummary> suppliers) {
    final totalCup = suppliers.fold<double>(
      0.0,
      (sum, supplier) => sum + supplier.totalCup,
    );
    final totalUsd = suppliers.fold<double>(
      0.0,
      (sum, supplier) => sum + supplier.totalUsd,
    );
    final totalEuro = suppliers.fold<double>(
      0.0,
      (sum, supplier) => sum + supplier.totalEuro,
    );

    final topSuppliers = [...suppliers]
      ..sort((a, b) => b.totalCup.compareTo(a.totalCup));

    return PaymentStats(
      totalCup: totalCup,
      totalUsd: totalUsd,
      totalEuro: totalEuro,
      totalSuppliers: suppliers.length,
      averagePerSupplier:
          suppliers.isNotEmpty ? totalCup / suppliers.length : 0.0,
      topSuppliers: topSuppliers.take(10).toList(),
    );
  }
}
