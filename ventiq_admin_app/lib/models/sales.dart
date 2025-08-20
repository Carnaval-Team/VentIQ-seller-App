class Sale {
  final String id;
  final String orderId;
  final String customerId;
  final String customerName;
  final String tpvId;
  final String tpvName;
  final String sellerId;
  final String sellerName;
  final DateTime saleDate;
  final String paymentMethod;
  final double subtotal;
  final double discount;
  final double tax;
  final double total;
  final String status; // completada, cancelada, devuelta
  final List<SaleItem> items;

  Sale({
    required this.id,
    required this.orderId,
    required this.customerId,
    required this.customerName,
    required this.tpvId,
    required this.tpvName,
    required this.sellerId,
    required this.sellerName,
    required this.saleDate,
    required this.paymentMethod,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.status,
    this.items = const [],
  });

  factory Sale.fromJson(Map<String, dynamic> json) {
    return Sale(
      id: json['id'] ?? '',
      orderId: json['orderId'] ?? '',
      customerId: json['customerId'] ?? '',
      customerName: json['customerName'] ?? '',
      tpvId: json['tpvId'] ?? '',
      tpvName: json['tpvName'] ?? '',
      sellerId: json['sellerId'] ?? '',
      sellerName: json['sellerName'] ?? '',
      saleDate: DateTime.parse(json['saleDate'] ?? DateTime.now().toIso8601String()),
      paymentMethod: json['paymentMethod'] ?? '',
      subtotal: (json['subtotal'] ?? 0.0).toDouble(),
      discount: (json['discount'] ?? 0.0).toDouble(),
      tax: (json['tax'] ?? 0.0).toDouble(),
      total: (json['total'] ?? 0.0).toDouble(),
      status: json['status'] ?? 'completada',
      items: (json['items'] as List<dynamic>?)
          ?.map((i) => SaleItem.fromJson(i))
          .toList() ?? [],
    );
  }
}

class SaleItem {
  final String id;
  final String saleId;
  final String productId;
  final String variantId;
  final String productName;
  final String variantName;
  final int quantity;
  final double unitPrice;
  final double totalPrice;

  SaleItem({
    required this.id,
    required this.saleId,
    required this.productId,
    required this.variantId,
    required this.productName,
    required this.variantName,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
  });

  factory SaleItem.fromJson(Map<String, dynamic> json) {
    return SaleItem(
      id: json['id'] ?? '',
      saleId: json['saleId'] ?? '',
      productId: json['productId'] ?? '',
      variantId: json['variantId'] ?? '',
      productName: json['productName'] ?? '',
      variantName: json['variantName'] ?? '',
      quantity: json['quantity'] ?? 0,
      unitPrice: (json['unitPrice'] ?? 0.0).toDouble(),
      totalPrice: (json['totalPrice'] ?? 0.0).toDouble(),
    );
  }
}

class TPV {
  final String id;
  final String name;
  final String code;
  final String storeId;
  final String storeName;
  final String location;
  final bool isActive;
  final String status; // activo, inactivo, mantenimiento
  final DateTime lastActivity;
  final String? assignedUserId;
  final String? assignedUserName;

  TPV({
    required this.id,
    required this.name,
    required this.code,
    required this.storeId,
    required this.storeName,
    required this.location,
    this.isActive = true,
    required this.status,
    required this.lastActivity,
    this.assignedUserId,
    this.assignedUserName,
  });

  factory TPV.fromJson(Map<String, dynamic> json) {
    return TPV(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      code: json['code'] ?? '',
      storeId: json['storeId'] ?? '',
      storeName: json['storeName'] ?? '',
      location: json['location'] ?? '',
      isActive: json['isActive'] ?? true,
      status: json['status'] ?? 'activo',
      lastActivity: DateTime.parse(json['lastActivity'] ?? DateTime.now().toIso8601String()),
      assignedUserId: json['assignedUserId'],
      assignedUserName: json['assignedUserName'],
    );
  }
}
