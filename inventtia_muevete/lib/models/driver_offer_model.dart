enum EstadoOferta { pendiente, aceptada, rechazada }

class DriverOfferModel {
  final int? id;
  final int? solicitudId;
  final int? driverId;
  final double? precio;
  final int? tiempoEstimado;
  final EstadoOferta? estado;
  final String? mensaje;
  final DateTime? createdAt;

  // Optional join fields from related tables
  final String? driverName;
  final String? driverImage;
  final String? vehicleInfo;

  DriverOfferModel({
    this.id,
    this.solicitudId,
    this.driverId,
    this.precio,
    this.tiempoEstimado,
    this.estado,
    this.mensaje,
    this.createdAt,
    this.driverName,
    this.driverImage,
    this.vehicleInfo,
  });

  factory DriverOfferModel.fromJson(Map<String, dynamic> json) {
    return DriverOfferModel(
      id: json['id'] as int?,
      solicitudId: json['solicitud_id'] as int?,
      driverId: json['driver_id'] as int?,
      precio: json['precio'] != null
          ? (json['precio'] as num).toDouble()
          : null,
      tiempoEstimado: json['tiempo_estimado'] as int?,
      estado: json['estado'] != null
          ? EstadoOferta.values.firstWhere(
              (e) => e.name == json['estado'],
              orElse: () => EstadoOferta.pendiente,
            )
          : null,
      mensaje: json['mensaje'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      driverName: json['driver_name'] as String?,
      driverImage: json['driver_image'] as String?,
      vehicleInfo: json['vehicle_info'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'solicitud_id': solicitudId,
      'driver_id': driverId,
      'precio': precio,
      'tiempo_estimado': tiempoEstimado,
      'estado': estado?.name,
      'mensaje': mensaje,
    };
  }

  DriverOfferModel copyWith({
    int? id,
    int? solicitudId,
    int? driverId,
    double? precio,
    int? tiempoEstimado,
    EstadoOferta? estado,
    String? mensaje,
    DateTime? createdAt,
    String? driverName,
    String? driverImage,
    String? vehicleInfo,
  }) {
    return DriverOfferModel(
      id: id ?? this.id,
      solicitudId: solicitudId ?? this.solicitudId,
      driverId: driverId ?? this.driverId,
      precio: precio ?? this.precio,
      tiempoEstimado: tiempoEstimado ?? this.tiempoEstimado,
      estado: estado ?? this.estado,
      mensaje: mensaje ?? this.mensaje,
      createdAt: createdAt ?? this.createdAt,
      driverName: driverName ?? this.driverName,
      driverImage: driverImage ?? this.driverImage,
      vehicleInfo: vehicleInfo ?? this.vehicleInfo,
    );
  }
}
