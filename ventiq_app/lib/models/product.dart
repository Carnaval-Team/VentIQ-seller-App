class Product {
  final int id;
  final String denominacion;
  final String? descripcion;
  final String? foto;
  final double precio;
  final num cantidad;
  final bool esRefrigerado;
  final bool esFragil;
  final bool esPeligroso;
  final bool esVendible;
  final bool esComprable;
  final bool esInventariable;
  final bool esPorLotes;
  final bool esElaborado;
  final bool esServicio;
  final String categoria;
  final List<ProductVariant> variantes;
  final Map<String, dynamic>?
  inventoryMetadata; // Store inventory data for products without variants

  Product({
    required this.id,
    required this.denominacion,
    this.descripcion,
    this.foto,
    required this.precio,
    required this.cantidad,
    required this.esRefrigerado,
    required this.esFragil,
    required this.esPeligroso,
    required this.esVendible,
    required this.esComprable,
    required this.esInventariable,
    required this.esPorLotes,
    required this.esElaborado,
    required this.esServicio,
    required this.categoria,
    this.variantes = const [],
    this.inventoryMetadata,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'],
      denominacion: json['denominacion'],
      descripcion: json['descripcion'],
      foto: json['foto'],
      precio: json['precio']?.toDouble() ?? 0.0,
      cantidad: json['cantidad'] ?? 0,
      esRefrigerado: json['es_refrigerado'] ?? false,
      esFragil: json['es_fragil'] ?? false,
      esPeligroso: json['es_peligroso'] ?? false,
      esVendible: json['es_vendible'] ?? false,
      esComprable: json['es_comprable'] ?? false,
      esInventariable: json['es_inventariable'] ?? false,
      esPorLotes: json['es_por_lotes'] ?? false,
      esElaborado: json['es_elaborado'] ?? false,
      esServicio: json['es_servicio'] ?? false,
      categoria: json['categoria'] ?? '',
      variantes:
          (json['variantes'] as List<dynamic>?)
              ?.map((v) => ProductVariant.fromJson(v))
              .toList() ??
          [],
    );
  }

  /// Convertir Product a JSON para persistencia
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'denominacion': denominacion,
      'descripcion': descripcion,
      'foto': foto,
      'precio': precio,
      'cantidad': cantidad,
      'es_refrigerado': esRefrigerado,
      'es_fragil': esFragil,
      'es_peligroso': esPeligroso,
      'es_vendible': esVendible,
      'es_comprable': esComprable,
      'es_inventariable': esInventariable,
      'es_por_lotes': esPorLotes,
      'es_elaborado': esElaborado,
      'es_servicio': esServicio,
      'categoria': categoria,
      'variantes': variantes.map((v) => v.toJson()).toList(),
      'inventoryMetadata': inventoryMetadata,
    };
  }
}

class ProductVariant {
  final int id;
  final String nombre;
  final double precio;
  final num cantidad;
  final String? descripcion;
  final Map<String, dynamic>?
  inventoryMetadata; // Store inventory data for this specific variant

  ProductVariant({
    required this.id,
    required this.nombre,
    required this.precio,
    required this.cantidad,
    this.descripcion,
    this.inventoryMetadata,
  });

  factory ProductVariant.fromJson(Map<String, dynamic> json) {
    return ProductVariant(
      id: json['id'],
      nombre: json['nombre'],
      precio: json['precio']?.toDouble() ?? 0.0,
      cantidad: json['cantidad'] ?? 0,
      descripcion: json['descripcion'],
    );
  }

  /// Convertir ProductVariant a JSON para persistencia
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre': nombre,
      'precio': precio,
      'cantidad': cantidad,
      'descripcion': descripcion,
      'inventoryMetadata': inventoryMetadata,
    };
  }
}

class Presentation {
  final int id;
  final String denominacion;
  final String? descripcion;
  final String skuCodigo;
  final bool esFraccionable;

  Presentation({
    required this.id,
    required this.denominacion,
    this.descripcion,
    required this.skuCodigo,
    this.esFraccionable = false,
  });

  factory Presentation.fromJson(Map<String, dynamic> json) {
    return Presentation(
      id: json['id'],
      denominacion: json['denominacion'],
      descripcion: json['descripcion'],
      skuCodigo: json['sku_codigo'],
      esFraccionable: json['es_fraccionable'] ?? false,
    );
  }
}

class ProductPresentation {
  final int id;
  final int idProducto;
  final int idPresentacion;
  final double cantidad;
  final bool esBase;
  final Presentation presentacion;

  ProductPresentation({
    required this.id,
    required this.idProducto,
    required this.idPresentacion,
    required this.cantidad,
    required this.esBase,
    required this.presentacion,
  });

  factory ProductPresentation.fromJson(Map<String, dynamic> json) {
    return ProductPresentation(
      id: json['id'],
      idProducto: json['id_producto'],
      idPresentacion: json['id_presentacion'],
      cantidad: (json['cantidad'] as num).toDouble(),
      esBase: json['es_base'] ?? false,
      presentacion: Presentation.fromJson(json['presentacion']),
    );
  }
}
