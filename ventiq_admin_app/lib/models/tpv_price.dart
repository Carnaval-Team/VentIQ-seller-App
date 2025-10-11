/// Modelo para precios diferenciados por TPV
class TpvPrice {
  final int id;
  final int idProducto;
  final int idTpv;
  final double precioVentaCup;
  final DateTime fechaDesde;
  final DateTime? fechaHasta;
  final bool esActivo;
  final DateTime? deletedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Campos relacionados (para consultas con JOIN)
  final String? productoNombre;
  final String? productoSku;
  final String? tpvNombre;
  final String? tiendaNombre;

  const TpvPrice({
    required this.id,
    required this.idProducto,
    required this.idTpv,
    required this.precioVentaCup,
    required this.fechaDesde,
    this.fechaHasta,
    required this.esActivo,
    this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
    this.productoNombre,
    this.productoSku,
    this.tpvNombre,
    this.tiendaNombre,
  });

  /// Crea una instancia desde JSON de la base de datos
  factory TpvPrice.fromJson(Map<String, dynamic> json) {
    return TpvPrice(
      id: json['id'] as int,
      idProducto: json['id_producto'] as int,
      idTpv: json['id_tpv'] as int,
      precioVentaCup: (json['precio_venta_cup'] as num).toDouble(),
      fechaDesde: DateTime.parse(json['fecha_desde']),
      fechaHasta: json['fecha_hasta'] != null 
          ? DateTime.parse(json['fecha_hasta']) 
          : null,
      esActivo: json['es_activo'] as bool,
      deletedAt: json['deleted_at'] != null 
          ? DateTime.parse(json['deleted_at']) 
          : null,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      // Campos relacionados (opcionales)
      productoNombre: json['producto_nombre']?.toString(),
      productoSku: json['producto_sku']?.toString(),
      tpvNombre: json['tpv_nombre']?.toString(),
      tiendaNombre: json['tienda_nombre']?.toString(),
    );
  }

  /// Convierte a JSON para inserción en base de datos
  Map<String, dynamic> toJson() {
    return {
      'id_producto': idProducto,
      'id_tpv': idTpv,
      'precio_venta_cup': precioVentaCup,
      'fecha_desde': fechaDesde.toIso8601String().split('T')[0],
      'fecha_hasta': fechaHasta?.toIso8601String().split('T')[0],
      'es_activo': esActivo,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  /// Convierte a JSON para actualización (sin campos auto-generados)
  Map<String, dynamic> toUpdateJson() {
    final data = <String, dynamic>{
      'precio_venta_cup': precioVentaCup,
      'es_activo': esActivo,
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (fechaHasta != null) {
      data['fecha_hasta'] = fechaHasta!.toIso8601String().split('T')[0];
    }

    return data;
  }

  /// Crea una copia con campos modificados
  TpvPrice copyWith({
    int? id,
    int? idProducto,
    int? idTpv,
    double? precioVentaCup,
    DateTime? fechaDesde,
    DateTime? fechaHasta,
    bool? esActivo,
    DateTime? deletedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? productoNombre,
    String? productoSku,
    String? tpvNombre,
    String? tiendaNombre,
  }) {
    return TpvPrice(
      id: id ?? this.id,
      idProducto: idProducto ?? this.idProducto,
      idTpv: idTpv ?? this.idTpv,
      precioVentaCup: precioVentaCup ?? this.precioVentaCup,
      fechaDesde: fechaDesde ?? this.fechaDesde,
      fechaHasta: fechaHasta ?? this.fechaHasta,
      esActivo: esActivo ?? this.esActivo,
      deletedAt: deletedAt ?? this.deletedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      productoNombre: productoNombre ?? this.productoNombre,
      productoSku: productoSku ?? this.productoSku,
      tpvNombre: tpvNombre ?? this.tpvNombre,
      tiendaNombre: tiendaNombre ?? this.tiendaNombre,
    );
  }

  /// Verifica si el precio está activo en una fecha específica
  bool isActiveOn(DateTime date) {
    if (!esActivo || deletedAt != null) return false;
    
    if (date.isBefore(fechaDesde)) return false;
    
    if (fechaHasta != null && date.isAfter(fechaHasta!)) return false;
    
    return true;
  }

  /// Verifica si el precio está eliminado (soft delete)
  bool get isDeleted => deletedAt != null;

  /// Verifica si el precio está vigente hoy
  bool get isCurrentlyActive => isActiveOn(DateTime.now());

  /// Obtiene el estado del precio como string
  String get statusText {
    if (isDeleted) return 'Eliminado';
    if (!esActivo) return 'Inactivo';
    if (!isCurrentlyActive) return 'Vencido';
    return 'Activo';
  }

  /// Obtiene el color del estado para la UI
  String get statusColor {
    if (isDeleted) return 'red';
    if (!esActivo) return 'orange';
    if (!isCurrentlyActive) return 'yellow';
    return 'green';
  }

  @override
  String toString() {
    return 'TpvPrice(id: $id, producto: $idProducto, tpv: $idTpv, '
           'precio: \$${precioVentaCup.toStringAsFixed(2)}, '
           'activo: $esActivo, eliminado: $isDeleted)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TpvPrice &&
        other.id == id &&
        other.idProducto == idProducto &&
        other.idTpv == idTpv &&
        other.precioVentaCup == precioVentaCup;
  }

  @override
  int get hashCode {
    return Object.hash(id, idProducto, idTpv, precioVentaCup);
  }
}

/// Clase auxiliar para datos de importación masiva
class TpvPriceImportData {
  final int idProducto;
  final int idTpv;
  final double precioVentaCup;
  final DateTime? fechaDesde;
  final DateTime? fechaHasta;
  final bool esActivo;

  const TpvPriceImportData({
    required this.idProducto,
    required this.idTpv,
    required this.precioVentaCup,
    this.fechaDesde,
    this.fechaHasta,
    this.esActivo = true,
  });

  /// Crea desde datos de Excel/CSV
  factory TpvPriceImportData.fromExcel(Map<String, dynamic> row) {
    return TpvPriceImportData(
      idProducto: int.parse(row['id_producto'].toString()),
      idTpv: int.parse(row['id_tpv'].toString()),
      precioVentaCup: double.parse(row['precio_venta_cup'].toString()),
      fechaDesde: row['fecha_desde'] != null 
          ? DateTime.parse(row['fecha_desde'].toString())
          : null,
      fechaHasta: row['fecha_hasta'] != null 
          ? DateTime.parse(row['fecha_hasta'].toString())
          : null,
      esActivo: row['es_activo']?.toString().toLowerCase() != 'false',
    );
  }

  /// Convierte a JSON para inserción
  Map<String, dynamic> toJson() {
    return {
      'id_producto': idProducto,
      'id_tpv': idTpv,
      'precio_venta_cup': precioVentaCup,
      'fecha_desde': (fechaDesde ?? DateTime.now()).toIso8601String().split('T')[0],
      'fecha_hasta': fechaHasta?.toIso8601String().split('T')[0],
      'es_activo': esActivo,
    };
  }
}
