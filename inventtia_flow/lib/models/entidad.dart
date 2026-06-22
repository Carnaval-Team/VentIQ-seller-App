class Entidad {
  final int id;
  final String denominacion;
  final String? direccion;
  final String? telefono;
  final String ownerUuid;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Entidad({
    required this.id,
    required this.denominacion,
    this.direccion,
    this.telefono,
    required this.ownerUuid,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Entidad.fromJson(Map<String, dynamic> json) => Entidad(
        id: json['id'] as int,
        denominacion: json['denominacion'] as String,
        direccion: json['direccion'] as String?,
        telefono: json['telefono'] as String?,
        ownerUuid: json['owner_uuid'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'denominacion': denominacion,
        'direccion': direccion,
        'telefono': telefono,
        'owner_uuid': ownerUuid,
      };

  Entidad copyWith({
    String? denominacion,
    String? direccion,
    String? telefono,
  }) =>
      Entidad(
        id: id,
        denominacion: denominacion ?? this.denominacion,
        direccion: direccion ?? this.direccion,
        telefono: telefono ?? this.telefono,
        ownerUuid: ownerUuid,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  bool isOwner(String uuid) => ownerUuid == uuid;
}

class EntidadAdmin {
  final int id;
  final int idEntidad;
  final String uuidUsuario;
  final String asignadoPor;
  final DateTime createdAt;

  const EntidadAdmin({
    required this.id,
    required this.idEntidad,
    required this.uuidUsuario,
    required this.asignadoPor,
    required this.createdAt,
  });

  factory EntidadAdmin.fromJson(Map<String, dynamic> json) => EntidadAdmin(
        id: json['id'] as int,
        idEntidad: json['id_entidad'] as int,
        uuidUsuario: json['uuid_usuario'] as String,
        asignadoPor: json['asignado_por'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
