class Product {
  final int id;
  final String denominacion;
  final String? descripcion;
  final String? foto;
  final double precio;
  final int cantidad;
  final bool esRefrigerado;
  final bool esFragil;
  final bool esPeligroso;
  final bool esVendible;
  final bool esComprable;
  final bool esInventariable;
  final bool esPorLotes;
  final String categoria;
  final List<ProductVariant> variantes;

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
    required this.categoria,
    this.variantes = const [],
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
      categoria: json['categoria'] ?? '',
      variantes: (json['variantes'] as List<dynamic>?)
          ?.map((v) => ProductVariant.fromJson(v))
          .toList() ?? [],
    );
  }
}

class ProductVariant {
  final int id;
  final String nombre;
  final double precio;
  final int cantidad;
  final String? descripcion;

  ProductVariant({
    required this.id,
    required this.nombre,
    required this.precio,
    required this.cantidad,
    this.descripcion,
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
}
