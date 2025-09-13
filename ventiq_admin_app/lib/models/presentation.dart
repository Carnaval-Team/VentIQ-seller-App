class Presentation {
  final int id;
  final String denominacion;
  final String? descripcion;
  final String skuCodigo;
  final DateTime createdAt;

  Presentation({
    required this.id,
    required this.denominacion,
    this.descripcion,
    required this.skuCodigo,
    required this.createdAt,
  });

  factory Presentation.fromJson(Map<String, dynamic> json) {
    return Presentation(
      id: json['id'] as int,
      denominacion: json['denominacion'] as String,
      descripcion: json['descripcion'] as String?,
      skuCodigo: json['sku_codigo'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'denominacion': denominacion,
      'descripcion': descripcion,
      'sku_codigo': skuCodigo,
      'created_at': createdAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'denominacion': denominacion,
      'descripcion': descripcion,
      'sku_codigo': skuCodigo,
    };
  }

  @override
  String toString() => denominacion;
}

class ProductPresentation {
  final int id;
  final int idProducto;
  final int idPresentacion;
  final double cantidad;
  final bool esBase;
  final DateTime createdAt;
  final Presentation? presentacion;

  ProductPresentation({
    required this.id,
    required this.idProducto,
    required this.idPresentacion,
    required this.cantidad,
    required this.esBase,
    required this.createdAt,
    this.presentacion,
  });

  factory ProductPresentation.fromJson(Map<String, dynamic> json) {
    return ProductPresentation(
      id: json['id'] as int,
      idProducto: json['id_producto'] as int,
      idPresentacion: json['id_presentacion'] as int,
      cantidad: (json['cantidad'] as num).toDouble(),
      esBase: json['es_base'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      presentacion: json['presentacion'] != null 
          ? Presentation.fromJson(json['presentacion'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'id_producto': idProducto,
      'id_presentacion': idPresentacion,
      'cantidad': cantidad,
      'es_base': esBase,
      'created_at': createdAt.toIso8601String(),
      if (presentacion != null) 'presentacion': presentacion!.toJson(),
    };
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'id_producto': idProducto,
      'id_presentacion': idPresentacion,
      'cantidad': cantidad,
      'es_base': esBase,
    };
  }

  String get displayText => presentacion != null 
      ? '${presentacion!.denominacion} (${cantidad.toStringAsFixed(cantidad.truncateToDouble() == cantidad ? 0 : 2)})'
      : 'Presentación ID: $idPresentacion';
}
