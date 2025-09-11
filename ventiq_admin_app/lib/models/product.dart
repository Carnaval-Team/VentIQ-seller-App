class Product {
  final String id;
  final String name;
  final String description;
  final String categoryId;
  final String categoryName;
  final String brand;
  final String sku;
  final String barcode;
  final double basePrice;
  final String imageUrl;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ProductVariant> variants;
  
  // Nuevos campos de la API optimizada
  final String? nombreComercial;
  final String? um; // Unidad de medida
  final bool esRefrigerado;
  final bool esFragil;
  final bool esPeligroso;
  final bool esVendible;
  final int stockDisponible;
  final bool tieneStock;
  final List<Map<String, dynamic>> subcategorias;
  final List<Map<String, dynamic>> presentaciones;
  final List<Map<String, dynamic>> multimedias;
  final List<String> etiquetas;
  final List<Map<String, dynamic>> inventario;
  final List<Map<String, dynamic>> variantesDisponibles;

  Product({
    required this.id,
    required this.name,
    required this.description,
    required this.categoryId,
    required this.categoryName,
    required this.brand,
    required this.sku,
    required this.barcode,
    required this.basePrice,
    required this.imageUrl,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
    this.variants = const [],
    // Nuevos campos opcionales con valores por defecto
    this.nombreComercial,
    this.um,
    this.esRefrigerado = false,
    this.esFragil = false,
    this.esPeligroso = false,
    this.esVendible = true,
    this.stockDisponible = 0,
    this.tieneStock = false,
    this.subcategorias = const [],
    this.presentaciones = const [],
    this.multimedias = const [],
    this.etiquetas = const [],
    this.inventario = const [],
    this.variantesDisponibles = const [],
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      categoryId: json['categoryId'] ?? '',
      categoryName: json['categoryName'] ?? '',
      brand: json['brand'] ?? '',
      sku: json['sku'] ?? '',
      barcode: json['barcode'] ?? '',
      basePrice: (json['basePrice'] ?? json['baseprice'] ?? 0.0).toDouble(),
      imageUrl: json['imageUrl'] ?? '',
      isActive: json['isActive'] ?? true,
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      updatedAt: DateTime.parse(json['updatedAt'] ?? DateTime.now().toIso8601String()),
      variants: (json['variants'] as List<dynamic>?)
          ?.map((v) => ProductVariant.fromJson(v))
          .toList() ?? [],
      // Nuevos campos de la API
      nombreComercial: json['nombreComercial'],
      um: json['um'],
      esRefrigerado: json['esRefrigerado'] ?? false,
      esFragil: json['esFragil'] ?? false,
      esPeligroso: json['esPeligroso'] ?? false,
      esVendible: json['esVendible'] ?? true,
      stockDisponible: json['stockDisponible'] ?? 0,
      tieneStock: json['tieneStock'] ?? false,
      subcategorias: (json['subcategorias'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [],
      presentaciones: (json['presentaciones'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [],
      multimedias: (json['multimedias'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [],
      etiquetas: (json['etiquetas'] as List<dynamic>?)?.cast<String>() ?? [],
      inventario: (json['inventario'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [],
      variantesDisponibles: (json['variantesDisponibles'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'categoryId': categoryId,
      'categoryName': categoryName,
      'brand': brand,
      'sku': sku,
      'barcode': barcode,
      'basePrice': basePrice,
      'imageUrl': imageUrl,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'variants': variants.map((v) => v.toJson()).toList(),
    };
  }
}

class ProductVariant {
  final String id;
  final String productId;
  final String name;
  final String presentation; // Ej: "500ml", "1kg", "Unidad"
  final double price;
  final String sku;
  final String barcode;
  final bool isActive;

  ProductVariant({
    required this.id,
    required this.productId,
    required this.name,
    required this.presentation,
    required this.price,
    required this.sku,
    required this.barcode,
    this.isActive = true,
  });

  factory ProductVariant.fromJson(Map<String, dynamic> json) {
    return ProductVariant(
      id: json['id'] ?? '',
      productId: json['productId'] ?? '',
      name: json['name'] ?? '',
      presentation: json['presentation'] ?? '',
      price: (json['price'] ?? 0.0).toDouble(),
      sku: json['sku'] ?? '',
      barcode: json['barcode'] ?? '',
      isActive: json['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'productId': productId,
      'name': name,
      'presentation': presentation,
      'price': price,
      'sku': sku,
      'barcode': barcode,
      'isActive': isActive,
    };
  }
}
