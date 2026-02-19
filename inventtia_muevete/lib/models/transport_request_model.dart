enum TipoVehiculo { moto, auto, microbus }

enum EstadoSolicitud { pendiente, aceptada, cancelada, expirada }

class TransportRequestModel {
  final int? id;
  final String? userId;
  final double? latOrigen;
  final double? lonOrigen;
  final double? latDestino;
  final double? lonDestino;
  final TipoVehiculo? tipoVehiculo;
  final double? precioOferta;
  final EstadoSolicitud? estado;
  final String? direccionOrigen;
  final String? direccionDestino;
  final double? distanciaKm;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  TransportRequestModel({
    this.id,
    this.userId,
    this.latOrigen,
    this.lonOrigen,
    this.latDestino,
    this.lonDestino,
    this.tipoVehiculo,
    this.precioOferta,
    this.estado,
    this.direccionOrigen,
    this.direccionDestino,
    this.distanciaKm,
    this.createdAt,
    this.expiresAt,
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
      tipoVehiculo: json['tipo_vehiculo'] != null
          ? TipoVehiculo.values.firstWhere(
              (e) => e.name == json['tipo_vehiculo'],
              orElse: () => TipoVehiculo.auto,
            )
          : null,
      precioOferta: json['precio_oferta'] != null
          ? (json['precio_oferta'] as num).toDouble()
          : null,
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
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'lat_origen': latOrigen,
      'lon_origen': lonOrigen,
      'lat_destino': latDestino,
      'lon_destino': lonDestino,
      'tipo_vehiculo': tipoVehiculo?.name,
      'precio_oferta': precioOferta,
      'estado': estado?.name,
      'direccion_origen': direccionOrigen,
      'direccion_destino': direccionDestino,
      'distancia_km': distanciaKm,
      'expires_at': expiresAt?.toIso8601String(),
    };
  }

  TransportRequestModel copyWith({
    int? id,
    String? userId,
    double? latOrigen,
    double? lonOrigen,
    double? latDestino,
    double? lonDestino,
    TipoVehiculo? tipoVehiculo,
    double? precioOferta,
    EstadoSolicitud? estado,
    String? direccionOrigen,
    String? direccionDestino,
    double? distanciaKm,
    DateTime? createdAt,
    DateTime? expiresAt,
  }) {
    return TransportRequestModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      latOrigen: latOrigen ?? this.latOrigen,
      lonOrigen: lonOrigen ?? this.lonOrigen,
      latDestino: latDestino ?? this.latDestino,
      lonDestino: lonDestino ?? this.lonDestino,
      tipoVehiculo: tipoVehiculo ?? this.tipoVehiculo,
      precioOferta: precioOferta ?? this.precioOferta,
      estado: estado ?? this.estado,
      direccionOrigen: direccionOrigen ?? this.direccionOrigen,
      direccionDestino: direccionDestino ?? this.direccionDestino,
      distanciaKm: distanciaKm ?? this.distanciaKm,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }
}
