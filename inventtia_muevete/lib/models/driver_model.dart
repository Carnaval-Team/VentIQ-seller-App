class DriverModel {
  final int? id;
  final DateTime? createdAt;
  final String? name;
  final String? email;
  final String? telefono;
  final bool estado;
  final bool? kyc;
  final String? image;
  final int? vehiculo;
  final String? categoria;
  final String? circulacion;
  final String? carnet;
  final String? licencia;
  final bool? revisado;
  final String? motivo;
  final String? uuid;

  DriverModel({
    this.id,
    this.createdAt,
    this.name,
    this.email,
    this.telefono,
    this.estado = false,
    this.kyc,
    this.image,
    this.vehiculo,
    this.categoria,
    this.circulacion,
    this.carnet,
    this.licencia,
    this.revisado,
    this.motivo,
    this.uuid,
  });

  factory DriverModel.fromJson(Map<String, dynamic> json) {
    return DriverModel(
      id: json['id'] as int?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      name: json['name'] as String?,
      email: json['email'] as String?,
      telefono: json['telefono'] as String?,
      estado: json['estado'] as bool? ?? false,
      kyc: json['kyc'] as bool?,
      image: json['image'] as String?,
      vehiculo: json['vehiculo'] as int?,
      categoria: json['categoria'] as String?,
      circulacion: json['circulacion'] as String?,
      carnet: json['carnet'] as String?,
      licencia: json['licencia'] as String?,
      revisado: json['revisado'] as bool?,
      motivo: json['motivo'] as String?,
      uuid: json['uuid'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'email': email,
      'telefono': telefono,
      'estado': estado,
      'kyc': kyc,
      'image': image,
      'vehiculo': vehiculo,
      'categoria': categoria,
      'circulacion': circulacion,
      'carnet': carnet,
      'licencia': licencia,
      'revisado': revisado,
      'motivo': motivo,
      'uuid': uuid,
    };
  }

  DriverModel copyWith({
    int? id,
    DateTime? createdAt,
    String? name,
    String? email,
    String? telefono,
    bool? estado,
    bool? kyc,
    String? image,
    int? vehiculo,
    String? categoria,
    String? circulacion,
    String? carnet,
    String? licencia,
    bool? revisado,
    String? motivo,
    String? uuid,
  }) {
    return DriverModel(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      name: name ?? this.name,
      email: email ?? this.email,
      telefono: telefono ?? this.telefono,
      estado: estado ?? this.estado,
      kyc: kyc ?? this.kyc,
      image: image ?? this.image,
      vehiculo: vehiculo ?? this.vehiculo,
      categoria: categoria ?? this.categoria,
      circulacion: circulacion ?? this.circulacion,
      carnet: carnet ?? this.carnet,
      licencia: licencia ?? this.licencia,
      revisado: revisado ?? this.revisado,
      motivo: motivo ?? this.motivo,
      uuid: uuid ?? this.uuid,
    );
  }
}
