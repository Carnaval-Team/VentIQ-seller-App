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
  final int totalOrders;
  List<ProductPaymentDetail>? products; // Loaded on demand

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
    required this.totalOrders,
    this.products,
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
      'total_orders': totalOrders,
    };
  }
}

class ProductPaymentDetail {
  final int productId;
  final String productName;
  final String? productImage;
  final int totalQuantity;
  final double totalCup;
  final double totalUsd;
  final double totalEuro;

  ProductPaymentDetail({
    required this.productId,
    required this.productName,
    this.productImage,
    required this.totalQuantity,
    required this.totalCup,
    required this.totalUsd,
    required this.totalEuro,
  });

  factory ProductPaymentDetail.fromJson(Map<String, dynamic> json) {
    return ProductPaymentDetail(
      productId: json['product_id'] as int,
      productName: json['product_name'] as String? ?? 'Sin nombre',
      productImage: json['product_image'] as String?,
      totalQuantity: json['total_quantity'] as int? ?? 0,
      totalCup: (json['total_cup'] as num?)?.toDouble() ?? 0.0,
      totalUsd: (json['total_usd'] as num?)?.toDouble() ?? 0.0,
      totalEuro: (json['total_euro'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      'product_name': productName,
      'product_image': productImage,
      'total_quantity': totalQuantity,
      'total_cup': totalCup,
      'total_usd': totalUsd,
      'total_euro': totalEuro,
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
