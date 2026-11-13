enum EstadoSolicitud { pendiente, aceptada, cancelada, expirada, completada }

/// Fila de `muevete.solicitudes_transporte`.
///
/// Flujo de precio fijo: el precio lo calcula la plataforma
/// (`precio_plataforma`, `precio_chofer`, `comision_pct`) y el cliente NUNCA
/// lo envía. [precioOferta] es un espejo legacy que la UI nueva no usa.
class TransportRequestModel {
  final int? id;
  final String? userId;
  final double? latOrigen;
  final double? lonOrigen;
  final double? latDestino;
  final double? lonDestino;
  final String? tipoVehiculo;
  final int? idTipoVehiculo;

  /// LEGACY: espejo de `precio_oferta`. No se usa en la UI nueva.
  final double? precioOferta;

  /// Precio final que paga el cliente (lo calcula la plataforma).
  final double? precioPlataforma;

  /// Neto que le toca al chofer.
  final double? precioChofer;

  /// Porcentaje y monto de comisión aplicados.
  final double? comisionPct;
  final double? comisionMonto;

  /// Zona tarifaria aplicada y modo (`fijo` / `fijo_mas_km` / `por_km`).
  final int? zonaId;
  final String? tarifaModo;

  /// Desglose tarifario completo (jsonb).
  final Map<String, dynamic>? tarifaDetalle;

  /// Chofer que tomó el viaje (null mientras está pendiente).
  final int? driverId;

  /// Pasajeros declarados por el cliente.
  final int? pasajeros;

  final EstadoSolicitud? estado;
  final String? direccionOrigen;
  final String? direccionDestino;
  final double? distanciaKm;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final String? metodoPago; // 'efectivo' o 'wallet'

  TransportRequestModel({
    this.id,
    this.userId,
    this.latOrigen,
    this.lonOrigen,
    this.latDestino,
    this.lonDestino,
    this.tipoVehiculo,
    this.idTipoVehiculo,
    this.precioOferta,
    this.precioPlataforma,
    this.precioChofer,
    this.comisionPct,
    this.comisionMonto,
    this.zonaId,
    this.tarifaModo,
    this.tarifaDetalle,
    this.driverId,
    this.pasajeros,
    this.estado,
    this.direccionOrigen,
    this.direccionDestino,
    this.distanciaKm,
    this.createdAt,
    this.expiresAt,
    this.metodoPago,
  });

  factory TransportRequestModel.fromJson(Map<String, dynamic> json) {
    return TransportRequestModel(
      id: json['id'] as int?,
      userId: json['user_id']?.toString(),
      latOrigen: json['lat_origen'] != null
          ? (json['lat_origen'] as num).toDouble()
          : null,
      lonOrigen: json['lon_origen'] != null
          ? (json['lon_origen'] as num).toDouble()
          : null,
      latDestino: json['lat_destino'] != null
          ? (json['lat_destino'] as num).toDouble()
          : null,
      lonDestino: json['lon_destino'] != null
          ? (json['lon_destino'] as num).toDouble()
          : null,
      tipoVehiculo: json['tipo_vehiculo'] as String?,
      idTipoVehiculo: json['id_tipo_vehiculo'] as int?,
      precioOferta: json['precio_oferta'] != null
          ? (json['precio_oferta'] as num).toDouble()
          : null,
      precioPlataforma: (json['precio_plataforma'] as num?)?.toDouble(),
      precioChofer: (json['precio_chofer'] as num?)?.toDouble(),
      comisionPct: (json['comision_pct'] as num?)?.toDouble(),
      comisionMonto: (json['comision_monto'] as num?)?.toDouble(),
      zonaId: (json['zona_id'] as num?)?.toInt(),
      tarifaModo: json['tarifa_modo'] as String?,
      tarifaDetalle: json['tarifa_detalle'] is Map
          ? Map<String, dynamic>.from(json['tarifa_detalle'] as Map)
          : null,
      driverId: (json['driver_id'] as num?)?.toInt(),
      pasajeros: (json['pasajeros'] as num?)?.toInt(),
      estado: json['estado'] != null
          ? EstadoSolicitud.values.firstWhere(
              (e) => e.name == json['estado'],
              orElse: () => EstadoSolicitud.pendiente,
            )
          : null,
      direccionOrigen: json['direccion_origen'] as String?,
      direccionDestino: json['direccion_destino'] as String?,
      distanciaKm: json['distancia_km'] != null
          ? (json['distancia_km'] as num).toDouble()
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
      metodoPago: json['metodo_pago'] as String?,
    );
  }

  /// Sólo para escrituras legacy. El flujo nuevo publica vía
  /// `fn_crear_solicitud`, que calcula el precio.
  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'lat_origen': latOrigen,
      'lon_origen': lonOrigen,
      'lat_destino': latDestino,
      'lon_destino': lonDestino,
      'tipo_vehiculo': tipoVehiculo,
      'id_tipo_vehiculo': idTipoVehiculo,
      'precio_oferta': precioOferta,
      'estado': estado?.name,
      'direccion_origen': direccionOrigen,
      'direccion_destino': direccionDestino,
      'distancia_km': distanciaKm,
      'expires_at': expiresAt?.toIso8601String(),
      if (metodoPago != null) 'metodo_pago': metodoPago,
    };
  }

  /// Precio a mostrar en la UI: el de plataforma, con el legacy como respaldo.
  double get precioMostrado => precioPlataforma ?? precioOferta ?? 0;

  bool get tieneChofer => driverId != null;

  TransportRequestModel copyWith({
    int? id,
    String? userId,
    double? latOrigen,
    double? lonOrigen,
    double? latDestino,
    double? lonDestino,
    String? tipoVehiculo,
    int? idTipoVehiculo,
    double? precioOferta,
    double? precioPlataforma,
    double? precioChofer,
    double? comisionPct,
    double? comisionMonto,
    int? zonaId,
    String? tarifaModo,
    Map<String, dynamic>? tarifaDetalle,
    int? driverId,
    int? pasajeros,
    EstadoSolicitud? estado,
    String? direccionOrigen,
    String? direccionDestino,
    double? distanciaKm,
    DateTime? createdAt,
    DateTime? expiresAt,
    String? metodoPago,
  }) {
    return TransportRequestModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      latOrigen: latOrigen ?? this.latOrigen,
      lonOrigen: lonOrigen ?? this.lonOrigen,
      latDestino: latDestino ?? this.latDestino,
      lonDestino: lonDestino ?? this.lonDestino,
      tipoVehiculo: tipoVehiculo ?? this.tipoVehiculo,
      idTipoVehiculo: idTipoVehiculo ?? this.idTipoVehiculo,
      precioOferta: precioOferta ?? this.precioOferta,
      precioPlataforma: precioPlataforma ?? this.precioPlataforma,
      precioChofer: precioChofer ?? this.precioChofer,
      comisionPct: comisionPct ?? this.comisionPct,
      comisionMonto: comisionMonto ?? this.comisionMonto,
      zonaId: zonaId ?? this.zonaId,
      tarifaModo: tarifaModo ?? this.tarifaModo,
      tarifaDetalle: tarifaDetalle ?? this.tarifaDetalle,
      driverId: driverId ?? this.driverId,
      pasajeros: pasajeros ?? this.pasajeros,
      estado: estado ?? this.estado,
      direccionOrigen: direccionOrigen ?? this.direccionOrigen,
      direccionDestino: direccionDestino ?? this.direccionDestino,
      distanciaKm: distanciaKm ?? this.distanciaKm,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      metodoPago: metodoPago ?? this.metodoPago,
    );
  }
}