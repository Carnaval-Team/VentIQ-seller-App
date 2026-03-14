class StopModel {
  final int? id;
  final int idViaje;
  final int driverId;
  final double latitud;
  final double longitud;
  final String? direccion;
  final int tiempoDetenido; // seconds
  final DateTime createdAt;
  final DateTime? salidaAt;

  const StopModel({
    this.id,
    required this.idViaje,
    required this.driverId,
    required this.latitud,
    required this.longitud,
    this.direccion,
    this.tiempoDetenido = 0,
    required this.createdAt,
    this.salidaAt,
  });

  factory StopModel.fromJson(Map<String, dynamic> json) {
    return StopModel(
      id: json['id'] as int?,
      idViaje: (json['id_viaje'] as num).toInt(),
      driverId: (json['driver_id'] as num).toInt(),
      latitud: (json['latitud'] as num).toDouble(),
      longitud: (json['longitud'] as num).toDouble(),
      direccion: json['direccion'] as String?,
      tiempoDetenido: (json['tiempo_detenido'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      salidaAt: json['salida_at'] != null
          ? DateTime.parse(json['salida_at'] as String)
          : null,
    );
  }

  bool get isActive => salidaAt == null;
}
