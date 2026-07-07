class InventarioMovimiento {
  final int idInventario;
  final int idProducto;
  final String productoNombre;
  final String sku;
  final int idAlmacen;
  final String almacenNombre;
  final int? idUbicacion;
  final String zonaNombre;
  final double cantidadFinal;
  final double cantidadInicial;
  final double variacion;
  final String direccion; // 'subio' | 'bajo' | 'sin_cambio'
  final int origenCambio;
  final DateTime ultimaFecha;
  final int totalCount;

  InventarioMovimiento({
    required this.idInventario,
    required this.idProducto,
    required this.productoNombre,
    required this.sku,
    required this.idAlmacen,
    required this.almacenNombre,
    required this.idUbicacion,
    required this.zonaNombre,
    required this.cantidadFinal,
    required this.cantidadInicial,
    required this.variacion,
    required this.direccion,
    required this.origenCambio,
    required this.ultimaFecha,
    required this.totalCount,
  });

  bool get subio => direccion == 'subio';
  bool get bajo => direccion == 'bajo';

  String get clave =>
      '$idProducto-${idUbicacion ?? 0}'; // identidad estable para animar

  factory InventarioMovimiento.fromJson(Map<String, dynamic> j) {
    double _d(dynamic v) =>
        v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
    return InventarioMovimiento(
      idInventario: (j['id_inventario'] as num).toInt(),
      idProducto: (j['id_producto'] as num).toInt(),
      productoNombre: (j['producto_nombre'] ?? '').toString(),
      sku: (j['sku'] ?? '').toString(),
      idAlmacen: (j['id_almacen'] as num).toInt(),
      almacenNombre: (j['almacen_nombre'] ?? '').toString(),
      idUbicacion: j['id_ubicacion'] == null
          ? null
          : (j['id_ubicacion'] as num).toInt(),
      zonaNombre: (j['zona_nombre'] ?? '').toString(),
      cantidadFinal: _d(j['cantidad_final']),
      cantidadInicial: _d(j['cantidad_inicial']),
      variacion: _d(j['variacion']),
      direccion: (j['direccion'] ?? 'sin_cambio').toString(),
      origenCambio: (j['origen_cambio'] as num?)?.toInt() ?? 0,
      ultimaFecha: DateTime.parse(j['ultima_fecha'].toString()),
      totalCount: (j['total_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class HistorialProductoDia {
  final int idInventario;
  final DateTime fecha;
  final double cantidadInicial;
  final double cantidadFinal;
  final double variacion;
  final String direccion;
  final int origenCambio;
  final int idUbicacion;
  final String zonaNombre;
  final String almacenNombre;

  HistorialProductoDia({
    required this.idInventario,
    required this.fecha,
    required this.cantidadInicial,
    required this.cantidadFinal,
    required this.variacion,
    required this.direccion,
    required this.origenCambio,
    required this.idUbicacion,
    required this.zonaNombre,
    required this.almacenNombre,
  });

  factory HistorialProductoDia.fromJson(Map<String, dynamic> j) {
    double _d(dynamic v) =>
        v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
    return HistorialProductoDia(
      idInventario: (j['id_inventario'] as num).toInt(),
      fecha: DateTime.parse(j['fecha'].toString()),
      cantidadInicial: _d(j['cantidad_inicial']),
      cantidadFinal: _d(j['cantidad_final']),
      variacion: _d(j['variacion']),
      direccion: (j['direccion'] ?? 'sin_cambio').toString(),
      origenCambio: (j['origen_cambio'] as num?)?.toInt() ?? 0,
      idUbicacion: (j['id_ubicacion'] as num).toInt(),
      zonaNombre: (j['zona_nombre'] ?? '').toString(),
      almacenNombre: (j['almacen_nombre'] ?? '').toString(),
    );
  }
}

class OperacionTR {
  final int idOperacion;
  final String tipoOperacion;
  final int idTienda;
  final String tiendaNombre;
  final String usuarioNombre;
  final int estado;
  final String estadoNombre;
  final DateTime createdAt;
  final double total;
  final int cantidadItems;
  final String observaciones;
  final int totalCount;

  OperacionTR({
    required this.idOperacion,
    required this.tipoOperacion,
    required this.idTienda,
    required this.tiendaNombre,
    required this.usuarioNombre,
    required this.estado,
    required this.estadoNombre,
    required this.createdAt,
    required this.total,
    required this.cantidadItems,
    required this.observaciones,
    required this.totalCount,
  });

  String get clave => 'op-$idOperacion';

  factory OperacionTR.fromJson(Map<String, dynamic> j) {
    double _d(dynamic v) =>
        v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
    return OperacionTR(
      idOperacion: (j['id_operacion'] as num).toInt(),
      tipoOperacion: (j['tipo_operacion'] ?? '').toString(),
      idTienda: (j['id_tienda'] as num).toInt(),
      tiendaNombre: (j['tienda_nombre'] ?? '').toString(),
      usuarioNombre: (j['usuario_nombre'] ?? '').toString(),
      estado: (j['estado'] as num?)?.toInt() ?? 0,
      estadoNombre: (j['estado_nombre'] ?? '').toString(),
      createdAt: DateTime.parse(j['created_at'].toString()),
      total: _d(j['total']),
      cantidadItems: (j['cantidad_items'] as num?)?.toInt() ?? 0,
      observaciones: (j['observaciones'] ?? '').toString(),
      totalCount: (j['total_count'] as num?)?.toInt() ?? 0,
    );
  }
}
