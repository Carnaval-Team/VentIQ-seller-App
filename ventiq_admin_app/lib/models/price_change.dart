/// Modelo para cambios de precio
class PriceChange {
  final int id;
  final int idProducto;
  final String nombreProducto;
  final String? skuProducto;
  final int? idVariante;
  final String? nombreVariante;
  final int idTpv;
  final String nombreTpv;
  final String idUsuario;
  final String? nombreUsuario;
  final double precioAnterior;
  final double precioNuevo;
  final String? motivo;
  final DateTime fechaCambio;
  final double? montoDescontado;

  const PriceChange({
    required this.id,
    required this.idProducto,
    required this.nombreProducto,
    this.skuProducto,
    this.idVariante,
    this.nombreVariante,
    required this.idTpv,
    required this.nombreTpv,
    required this.idUsuario,
    this.nombreUsuario,
    required this.precioAnterior,
    required this.precioNuevo,
    this.motivo,
    required this.fechaCambio,
    this.montoDescontado,
  });

  factory PriceChange.fromJson(Map<String, dynamic> json) {
    return PriceChange(
      id: json['id'] as int,
      idProducto: json['id_producto'] as int,
      nombreProducto: json['nombre_producto']?.toString() ?? 'Sin nombre',
      skuProducto: json['sku_producto']?.toString(),
      idVariante: json['id_variante'] as int?,
      nombreVariante: json['nombre_variante']?.toString(),
      idTpv: json['id_tpv'] as int,
      nombreTpv: json['nombre_tpv']?.toString() ?? 'Sin TPV',
      idUsuario: json['id_usuario']?.toString() ?? '',
      nombreUsuario: json['nombre_usuario']?.toString(),
      precioAnterior: (json['precio_anterior'] as num?)?.toDouble() ?? 0,
      precioNuevo: (json['precio_nuevo'] as num?)?.toDouble() ?? 0,
      motivo: json['motivo']?.toString(),
      fechaCambio: DateTime.parse(json['fecha_cambio'] as String),
      montoDescontado: (json['monto_descontado'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'id_producto': idProducto,
      'nombre_producto': nombreProducto,
      'sku_producto': skuProducto,
      'id_variante': idVariante,
      'nombre_variante': nombreVariante,
      'id_tpv': idTpv,
      'nombre_tpv': nombreTpv,
      'id_usuario': idUsuario,
      'nombre_usuario': nombreUsuario,
      'precio_anterior': precioAnterior,
      'precio_nuevo': precioNuevo,
      'motivo': motivo,
      'fecha_cambio': fechaCambio.toIso8601String(),
      'monto_descontado': montoDescontado,
    };
  }

  String get nombreProductoCompleto {
    if (nombreVariante == null || nombreVariante!.isEmpty) {
      return nombreProducto;
    }
    return '$nombreProducto - $nombreVariante';
  }

  String get nombreUsuarioDisplay {
    if (nombreUsuario == null || nombreUsuario!.trim().isEmpty) {
      return 'Usuario no disponible';
    }
    return nombreUsuario!;
  }

  double get diferenciaPrecio => precioNuevo - precioAnterior;

  double get diferenciaAbsoluta => diferenciaPrecio.abs();

  bool get esDescuento => diferenciaPrecio < 0;

  bool get esAumento => diferenciaPrecio > 0;
}

class PriceChangeResponse {
  final List<PriceChange> changes;
  final int totalCount;

  const PriceChangeResponse({required this.changes, required this.totalCount});

  factory PriceChangeResponse.empty() {
    return const PriceChangeResponse(changes: [], totalCount: 0);
  }
}
