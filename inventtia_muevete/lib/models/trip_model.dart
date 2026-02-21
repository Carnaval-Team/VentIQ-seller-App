class TripModel {
  final int? id;
  final DateTime? createdAt;
  final int? driverId;
  final String? user;
  final bool? estado;
  final bool? visto;
  final String? userDisplay;
  final bool? completado;
  final String? latitudCliente;
  final String? longitudCliente;
  final String? telefono;

  TripModel({
    this.id,
    this.createdAt,
    this.driverId,
    this.user,
    this.estado,
    this.visto,
    this.userDisplay,
    this.completado,
    this.latitudCliente,
    this.longitudCliente,
    this.telefono,
  });

  factory TripModel.fromJson(Map<String, dynamic> json) {
    return TripModel(
      id: json['id'] as int?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      driverId: json['driver_id'] as int?,
      user: json['user'] as String?,
      estado: json['estado'] as bool?,
      visto: json['visto'] as bool?,
      userDisplay: json['user_display'] as String?,
      completado: json['completado'] as bool?,
      latitudCliente: json['latitud_cliente'] as String?,
      longitudCliente: json['longitud_cliente'] as String?,
      telefono: json['telefono'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'driver_id': driverId,
      'user': user,
      'estado': estado,
      'visto': visto,
      'user_display': userDisplay,
      'completado': completado,
      'latitud_cliente': latitudCliente,
      'longitud_cliente': longitudCliente,
      'telefono': telefono,
    };
  }

  TripModel copyWith({
    int? id,
    DateTime? createdAt,
    int? driverId,
    String? user,
    bool? estado,
    bool? visto,
    String? userDisplay,
    bool? completado,
    String? latitudCliente,
    String? longitudCliente,
    String? telefono,
  }) {
    return TripModel(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      driverId: driverId ?? this.driverId,
      user: user ?? this.user,
      estado: estado ?? this.estado,
      visto: visto ?? this.visto,
      userDisplay: userDisplay ?? this.userDisplay,
      completado: completado ?? this.completado,
      latitudCliente: latitudCliente ?? this.latitudCliente,
      longitudCliente: longitudCliente ?? this.longitudCliente,
      telefono: telefono ?? this.telefono,
    );
  }
}
