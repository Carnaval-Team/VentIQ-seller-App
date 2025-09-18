class Subcategory {
  final int id;
  final String denominacion;
  final String skuCodigo;
  final DateTime createdAt;
  final int totalProductos;
  final int idCategoria;

  const Subcategory({
    required this.id,
    required this.denominacion,
    required this.skuCodigo,
    required this.createdAt,
    required this.totalProductos,
    required this.idCategoria,
  });

  factory Subcategory.fromJson(Map<String, dynamic> json) {
    return Subcategory(
      id: json['id'] ?? 0,
      denominacion: json['denominacion'] ?? '',
      skuCodigo: json['sku_codigo'] ?? '',
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
      totalProductos: json['total_productos'] ?? 0,
      idCategoria: json['idcategoria'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'denominacion': denominacion,
      'sku_codigo': skuCodigo,
      'created_at': createdAt.toIso8601String(),
      'total_productos': totalProductos,
      'idcategoria': idCategoria,
    };
  }

  Subcategory copyWith({
    int? id,
    String? denominacion,
    String? skuCodigo,
    DateTime? createdAt,
    int? totalProductos,
    int? idCategoria,
  }) {
    return Subcategory(
      id: id ?? this.id,
      denominacion: denominacion ?? this.denominacion,
      skuCodigo: skuCodigo ?? this.skuCodigo,
      createdAt: createdAt ?? this.createdAt,
      totalProductos: totalProductos ?? this.totalProductos,
      idCategoria: idCategoria ?? this.idCategoria,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Subcategory && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Subcategory(id: $id, denominacion: $denominacion, skuCodigo: $skuCodigo, totalProductos: $totalProductos)';
  }
}
