class Entidad {
  final int id;
  final String denominacion;
  final String? direccion;
  final String? telefono;
  final String ownerUuid;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int horasAnticipacionCancelacion;

  const Entidad({
    required this.id,
    required this.denominacion,
    this.direccion,
    this.telefono,
    required this.ownerUuid,
    required this.createdAt,
    required this.updatedAt,
    this.horasAnticipacionCancelacion = 0,
  });

  factory Entidad.fromJson(Map<String, dynamic> json) => Entidad(
        id: (json['id'] as num).toInt(),
        denominacion: json['denominacion'] as String,
        direccion: json['direccion'] as String?,
        telefono: json['telefono'] as String?,
        ownerUuid: (json['owner_uuid'] as String?) ?? '',
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'] as String)
            : DateTime.now(),
        updatedAt: json['updated_at'] != null
            ? DateTime.parse(json['updated_at'] as String)
            : DateTime.now(),
        horasAnticipacionCancelacion:
            (json['horas_anticipacion_cancelacion'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'denominacion': denominacion,
        'direccion': direccion,
        'telefono': telefono,
        'owner_uuid': ownerUuid,
        'horas_anticipacion_cancelacion': horasAnticipacionCancelacion,
      };

  Entidad copyWith({
    String? denominacion,
    String? direccion,
    String? telefono,
    int? horasAnticipacionCancelacion,
  }) =>
      Entidad(
        id: id,
        denominacion: denominacion ?? this.denominacion,
        direccion: direccion ?? this.direccion,
        telefono: telefono ?? this.telefono,
        ownerUuid: ownerUuid,
        createdAt: createdAt,
        updatedAt: updatedAt,
        horasAnticipacionCancelacion: horasAnticipacionCancelacion ??
            this.horasAnticipacionCancelacion,
      );

  bool isOwner(String uuid) => ownerUuid == uuid;

  /// True si la entidad permite que los clientes cancelen sus reservas.
  bool get permiteCancelacionCliente => horasAnticipacionCancelacion > 0;
}

class EntidadAdmin {
  final int id;
  final int idEntidad;
  final String uuidUsuario;
  final String asignadoPor;
  final DateTime createdAt;
  final String? email;

  const EntidadAdmin({
    required this.id,
    required this.idEntidad,
    required this.uuidUsuario,
    required this.asignadoPor,
    required this.createdAt,
    this.email,
  });

  factory EntidadAdmin.fromJson(Map<String, dynamic> json) => EntidadAdmin(
        id: json['id'] as int,
        idEntidad: json['id_entidad'] as int,
        uuidUsuario: json['uuid_usuario'] as String,
        asignadoPor: json['asignado_por'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        email: json['email'] as String?,
      );
}

class EntidadVendedor {
  final int id;
  final int idEntidad;
  final String uuidUsuario;
  final String asignadoPor;
  final DateTime createdAt;
  final String? email;

  const EntidadVendedor({
    required this.id,
    required this.idEntidad,
    required this.uuidUsuario,
    required this.asignadoPor,
    required this.createdAt,
    this.email,
  });

  factory EntidadVendedor.fromJson(Map<String, dynamic> json) =>
      EntidadVendedor(
        id: json['id'] as int,
        idEntidad: json['id_entidad'] as int,
        uuidUsuario: json['uuid_usuario'] as String,
        asignadoPor: json['asignado_por'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        email: json['email'] as String?,
      );
}
