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
  final String? vehicleInfo; // categoria
  final String? driverPhone;
  final bool? driverKyc;
  final String? vehicleMarca;
  final String? vehicleModelo;
  final String? vehicleChapa;
  final String? vehicleColor;
  final int? tripCount; // completed trips
  final double? driverRating;

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
    this.driverPhone,
    this.driverKyc,
    this.vehicleMarca,
    this.vehicleModelo,
    this.vehicleChapa,
    this.vehicleColor,
    this.tripCount,
    this.driverRating,
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
      driverPhone: json['driver_phone'] as String?,
      driverKyc: json['driver_kyc'] as bool?,
      vehicleMarca: json['vehicle_marca'] as String?,
      vehicleModelo: json['vehicle_modelo'] as String?,
      vehicleChapa: json['vehicle_chapa'] as String?,
      vehicleColor: json['vehicle_color'] as String?,
      tripCount: json['trip_count'] as int?,
      driverRating: json['driver_rating'] != null
          ? (json['driver_rating'] as num).toDouble()
          : null,
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
    String? driverPhone,
    bool? driverKyc,
    String? vehicleMarca,
    String? vehicleModelo,
    String? vehicleChapa,
    String? vehicleColor,
    int? tripCount,
    double? driverRating,
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
      driverPhone: driverPhone ?? this.driverPhone,
      driverKyc: driverKyc ?? this.driverKyc,
      vehicleMarca: vehicleMarca ?? this.vehicleMarca,
      vehicleModelo: vehicleModelo ?? this.vehicleModelo,
      vehicleChapa: vehicleChapa ?? this.vehicleChapa,
      vehicleColor: vehicleColor ?? this.vehicleColor,
      tripCount: tripCount ?? this.tripCount,
      driverRating: driverRating ?? this.driverRating,
    );
  }
}
