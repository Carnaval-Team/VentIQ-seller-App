class Product {
  final String id;
  final String name;
  final String denominacion;
  final String? denominacionCorta;
  final String description;
  final String? descripcionCorta;
  final String categoryId;
  final String categoryName;
  final String brand;
  final String sku;
  final String barcode;
  final String? codigoBarras;
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
  final bool esComprable;
  final bool esInventariable;
  final bool esPorLotes;
  final double precioVenta;
  final int stockDisponible;
  final bool tieneStock;
  final List<Map<String, dynamic>> subcategorias;
  final List<Map<String, dynamic>> presentaciones;
  final List<Map<String, dynamic>> multimedias;
  final List<String> etiquetas;
  final List<Map<String, dynamic>> inventario;
  final List<Map<String, dynamic>> variantesDisponibles;
  final bool esOferta;
  final double precioOferta;
  final DateTime? fechaInicioOferta;
  final DateTime? fechaFinOferta;
  final int stockMinimo;
  final int stockMaximo;
  final int diasAlertCaducidad;
  final String? unidadMedida;
  final String? tipoProducto;
  final String? tipoInventario;

  // Campos para productos elaborados
  final bool esElaborado;
  final List<ProductIngredient> ingredientes;
  final double? costoProduccion;

  Product({
    required this.id,
    required this.name,
    required this.denominacion,
    this.denominacionCorta,
    required this.description,
    this.descripcionCorta,
    required this.categoryId,
    required this.categoryName,
    required this.brand,
    required this.sku,
    required this.barcode,
    this.codigoBarras,
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
    this.esComprable = true,
    this.esInventariable = true,
    this.esPorLotes = false,
    this.precioVenta = 0.0,
    this.stockDisponible = 0,
    this.tieneStock = false,
    this.subcategorias = const [],
    this.presentaciones = const [],
    this.multimedias = const [],
    this.etiquetas = const [],
    this.inventario = const [],
    this.variantesDisponibles = const [],
    this.esOferta = false,
    this.precioOferta = 0.0,
    this.fechaInicioOferta,
    this.fechaFinOferta,
    this.stockMinimo = 0,
    this.stockMaximo = 0,
    this.diasAlertCaducidad = 0,
    this.unidadMedida,
    this.tipoProducto,
    this.tipoInventario,
    // Campos para productos elaborados
    this.esElaborado = false,
    this.ingredientes = const [],
    this.costoProduccion,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      denominacion: json['denominacion'] ?? '',
      denominacionCorta: json['denominacionCorta'],
      description: json['description'] ?? '',
      descripcionCorta: json['descripcionCorta'],
      categoryId: json['categoryId'] ?? '',
      categoryName: json['categoryName'] ?? '',
      brand: json['brand'] ?? '',
      sku: json['sku'] ?? '',
      barcode: json['barcode'] ?? '',
      codigoBarras: json['codigoBarras'],
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
      esComprable: json['esComprable'] ?? true,
      esInventariable: json['esInventariable'] ?? true,
      esPorLotes: json['esPorLotes'] ?? false,
      precioVenta: json['precioVenta'] ?? 0.0,
      stockDisponible: json['stockDisponible'] ?? 0,
      tieneStock: json['tieneStock'] ?? false,
      subcategorias: (json['subcategorias'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [],
      presentaciones: (json['presentaciones'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [],
      multimedias: (json['multimedias'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [],
      etiquetas: (json['etiquetas'] as List<dynamic>?)?.cast<String>() ?? [],
      inventario: (json['inventario'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [],
      variantesDisponibles: (json['variantesDisponibles'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [],
      esOferta: json['esOferta'] ?? false,
      precioOferta: json['precioOferta'] ?? 0.0,
      fechaInicioOferta: json['fechaInicioOferta'] != null ? DateTime.parse(json['fechaInicioOferta']) : null,
      fechaFinOferta: json['fechaFinOferta'] != null ? DateTime.parse(json['fechaFinOferta']) : null,
      stockMinimo: json['stockMinimo'] ?? 0,
      stockMaximo: json['stockMaximo'] ?? 0,
      diasAlertCaducidad: json['diasAlertCaducidad'] ?? 0,
      unidadMedida: json['unidadMedida'],
      tipoProducto: json['tipoProducto'],
      tipoInventario: json['tipoInventario'],
      // Campos para productos elaborados
      esElaborado: json['esElaborado'] ?? false,
      ingredientes: (json['ingredientes'] as List<dynamic>?)?.map((i) => ProductIngredient.fromJson(i)).toList() ?? [],
      costoProduccion: json['costoProduccion'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'denominacion': denominacion,
      'denominacionCorta': denominacionCorta,
      'description': description,
      'descripcionCorta': descripcionCorta,
      'categoryId': categoryId,
      'categoryName': categoryName,
      'brand': brand,
      'sku': sku,
      'barcode': barcode,
      'codigoBarras': codigoBarras,
      'basePrice': basePrice,
      'imageUrl': imageUrl,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'variants': variants.map((v) => v.toJson()).toList(),
      'esVendible': esVendible,
      'esComprable': esComprable,
      'esInventariable': esInventariable,
      'esPorLotes': esPorLotes,
      'precioVenta': precioVenta,
      'stockDisponible': stockDisponible,
      'esOferta': esOferta,
      'precioOferta': precioOferta,
      'fechaInicioOferta': fechaInicioOferta?.toIso8601String(),
      'fechaFinOferta': fechaFinOferta?.toIso8601String(),
      'stockMinimo': stockMinimo,
      'stockMaximo': stockMaximo,
      'diasAlertCaducidad': diasAlertCaducidad,
      'unidadMedida': unidadMedida,
      'tipoProducto': tipoProducto,
      'tipoInventario': tipoInventario,
      'esElaborado': esElaborado,
      'ingredientes': ingredientes.map((i) => i.toJson()).toList(),
      'costoProduccion': costoProduccion,
    };
  }

  /// Calcula el costo de producción basado en los ingredientes
  double calcularCostoProduccion() {
    if (!esElaborado || ingredientes.isEmpty) return 0.0;
    
    return ingredientes.fold(0.0, (total, ingrediente) {
      return total + (ingrediente.cantidadNecesaria * ingrediente.costoUnitario);
    });
  }

  /// Verifica si hay suficientes ingredientes en stock para producir una cantidad específica
  bool verificarDisponibilidadIngredientes(double cantidadAProducir) {
    if (!esElaborado || ingredientes.isEmpty) return true;
    
    for (final ingrediente in ingredientes) {
      final cantidadRequerida = ingrediente.cantidadNecesaria * cantidadAProducir;
      if (ingrediente.stockDisponible < cantidadRequerida) {
        return false;
      }
    }
    return true;
  }

  /// Obtiene la lista de ingredientes faltantes para producir una cantidad específica
  List<ProductIngredient> obtenerIngredientesFaltantes(double cantidadAProcir) {
    if (!esElaborado || ingredientes.isEmpty) return [];
    
    final faltantes = <ProductIngredient>[];
    for (final ingrediente in ingredientes) {
      final cantidadRequerida = ingrediente.cantidadNecesaria * cantidadAProcir;
      if (ingrediente.stockDisponible < cantidadRequerida) {
        faltantes.add(ingrediente);
      }
    }
    return faltantes;
  }

  /// Crea una copia del producto con nuevos valores
  Product copyWith({
    String? id,
    String? name,
    String? denominacion,
    String? denominacionCorta,
    String? description,
    String? descripcionCorta,
    String? categoryId,
    String? categoryName,
    String? brand,
    String? sku,
    String? barcode,
    String? codigoBarras,
    double? basePrice,
    String? imageUrl,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<ProductVariant>? variants,
    String? nombreComercial,
    String? um,
    bool? esRefrigerado,
    bool? esFragil,
    bool? esPeligroso,
    bool? esVendible,
    bool? esComprable,
    bool? esInventariable,
    bool? esPorLotes,
    double? precioVenta,
    int? stockDisponible,
    bool? tieneStock,
    List<Map<String, dynamic>>? subcategorias,
    List<Map<String, dynamic>>? presentaciones,
    List<Map<String, dynamic>>? multimedias,
    List<String>? etiquetas,
    List<Map<String, dynamic>>? inventario,
    List<Map<String, dynamic>>? variantesDisponibles,
    bool? esOferta,
    double? precioOferta,
    DateTime? fechaInicioOferta,
    DateTime? fechaFinOferta,
    int? stockMinimo,
    int? stockMaximo,
    int? diasAlertCaducidad,
    String? unidadMedida,
    String? tipoProducto,
    String? tipoInventario,
    bool? esElaborado,
    List<ProductIngredient>? ingredientes,
    double? costoProduccion,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      denominacion: denominacion ?? this.denominacion,
      denominacionCorta: denominacionCorta ?? this.denominacionCorta,
      description: description ?? this.description,
      descripcionCorta: descripcionCorta ?? this.descripcionCorta,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      brand: brand ?? this.brand,
      sku: sku ?? this.sku,
      barcode: barcode ?? this.barcode,
      codigoBarras: codigoBarras ?? this.codigoBarras,
      basePrice: basePrice ?? this.basePrice,
      imageUrl: imageUrl ?? this.imageUrl,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      variants: variants ?? this.variants,
      nombreComercial: nombreComercial ?? this.nombreComercial,
      um: um ?? this.um,
      esRefrigerado: esRefrigerado ?? this.esRefrigerado,
      esFragil: esFragil ?? this.esFragil,
      esPeligroso: esPeligroso ?? this.esPeligroso,
      esVendible: esVendible ?? this.esVendible,
      esComprable: esComprable ?? this.esComprable,
      esInventariable: esInventariable ?? this.esInventariable,
      esPorLotes: esPorLotes ?? this.esPorLotes,
      precioVenta: precioVenta ?? this.precioVenta,
      stockDisponible: stockDisponible ?? this.stockDisponible,
      tieneStock: tieneStock ?? this.tieneStock,
      subcategorias: subcategorias ?? this.subcategorias,
      presentaciones: presentaciones ?? this.presentaciones,
      multimedias: multimedias ?? this.multimedias,
      etiquetas: etiquetas ?? this.etiquetas,
      inventario: inventario ?? this.inventario,
      variantesDisponibles: variantesDisponibles ?? this.variantesDisponibles,
      esOferta: esOferta ?? this.esOferta,
      precioOferta: precioOferta ?? this.precioOferta,
      fechaInicioOferta: fechaInicioOferta ?? this.fechaInicioOferta,
      fechaFinOferta: fechaFinOferta ?? this.fechaFinOferta,
      stockMinimo: stockMinimo ?? this.stockMinimo,
      stockMaximo: stockMaximo ?? this.stockMaximo,
      diasAlertCaducidad: diasAlertCaducidad ?? this.diasAlertCaducidad,
      unidadMedida: unidadMedida ?? this.unidadMedida,
      tipoProducto: tipoProducto ?? this.tipoProducto,
      tipoInventario: tipoInventario ?? this.tipoInventario,
      esElaborado: esElaborado ?? this.esElaborado,
      ingredientes: ingredientes ?? this.ingredientes,
      costoProduccion: costoProduccion ?? this.costoProduccion,
    );
  }
}

class ProductVariant {
  final String id;
  final String productId;
  final String name;
  final String presentation; // Ej: "500ml", "1kg", "Unidad"
  final String description; 
  final double price;
  final String sku;
  final String barcode;
  final bool isActive;

  ProductVariant({
    required this.id,
    required this.productId,
    required this.name,
    required this.presentation,
    this.description = '', 
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
      description: json['description'] ?? '', 
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
      'description': description, 
      'price': price,
      'sku': sku,
      'barcode': barcode,
      'isActive': isActive,
    };
  }
}

class ProductIngredient {
  final String id;
  final String idProductoElaborado;
  final String idIngrediente;
  final String nombreIngrediente;
  final String denominacionIngrediente;
  final double cantidadNecesaria;
  final String unidadMedida;
  final double costoUnitario;
  final int stockDisponible;
  final String? imagenIngrediente;

  ProductIngredient({
    required this.id,
    required this.idProductoElaborado,
    required this.idIngrediente,
    required this.nombreIngrediente,
    required this.denominacionIngrediente,
    required this.cantidadNecesaria,
    required this.unidadMedida,
    required this.costoUnitario,
    required this.stockDisponible,
    this.imagenIngrediente,
  });

  /// Calcula el costo total de este ingrediente
  double get costoTotal => cantidadNecesaria * costoUnitario;

  /// Verifica si hay suficiente stock para la cantidad necesaria
  bool get tieneStockSuficiente => stockDisponible >= cantidadNecesaria;

  /// Calcula cuántas unidades del producto elaborado se pueden hacer con el stock disponible
  double get unidadesPosibles => stockDisponible / cantidadNecesaria;

  factory ProductIngredient.fromJson(Map<String, dynamic> json) {
    return ProductIngredient(
      id: json['id']?.toString() ?? '',
      idProductoElaborado: json['id_producto_elaborado']?.toString() ?? '',
      idIngrediente: json['id_ingrediente']?.toString() ?? '',
      nombreIngrediente: json['nombre_ingrediente'] ?? json['denominacion'] ?? '',
      denominacionIngrediente: json['denominacion_ingrediente'] ?? json['denominacion'] ?? '',
      cantidadNecesaria: (json['cantidad_necesaria'] ?? 0.0).toDouble(),
      unidadMedida: json['unidad_medida'] ?? 'und',
      costoUnitario: (json['costo_unitario'] ?? 0.0).toDouble(),
      stockDisponible: json['stock_disponible'] ?? 0,
      imagenIngrediente: json['imagen_ingrediente'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'id_producto_elaborado': idProductoElaborado,
      'id_ingrediente': idIngrediente,
      'nombre_ingrediente': nombreIngrediente,
      'denominacion_ingrediente': denominacionIngrediente,
      'cantidad_necesaria': cantidadNecesaria,
      'unidad_medida': unidadMedida,
      'costo_unitario': costoUnitario,
      'stock_disponible': stockDisponible,
      'imagen_ingrediente': imagenIngrediente,
    };
  }

  /// Crea una copia con nuevos valores
  ProductIngredient copyWith({
    String? id,
    String? idProductoElaborado,
    String? idIngrediente,
    String? nombreIngrediente,
    String? denominacionIngrediente,
    double? cantidadNecesaria,
    String? unidadMedida,
    double? costoUnitario,
    int? stockDisponible,
    String? imagenIngrediente,
  }) {
    return ProductIngredient(
      id: id ?? this.id,
      idProductoElaborado: idProductoElaborado ?? this.idProductoElaborado,
      idIngrediente: idIngrediente ?? this.idIngrediente,
      nombreIngrediente: nombreIngrediente ?? this.nombreIngrediente,
      denominacionIngrediente: denominacionIngrediente ?? this.denominacionIngrediente,
      cantidadNecesaria: cantidadNecesaria ?? this.cantidadNecesaria,
      unidadMedida: unidadMedida ?? this.unidadMedida,
      costoUnitario: costoUnitario ?? this.costoUnitario,
      stockDisponible: stockDisponible ?? this.stockDisponible,
      imagenIngrediente: imagenIngrediente ?? this.imagenIngrediente,
    );
  }
}
