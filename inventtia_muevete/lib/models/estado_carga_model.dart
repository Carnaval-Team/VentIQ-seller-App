/// Representa un registro de la bitácora [app_dat_estado_carga].
/// Cada instancia es un cambio de estado realizado sobre una carga.
class EstadoCargaModel {
  final int id;
  final int cargaId;
  final String estadoCodigo;
  final String? estadoNombre;  // JOIN con app_nom_estado (si viene en la consulta)
  final String? usuarioUuid;
  final int? driverId;
  final String? motivo;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  const EstadoCargaModel({
    required this.id,
    required this.cargaId,
    required this.estadoCodigo,
    this.estadoNombre,
    this.usuarioUuid,
    this.driverId,
    this.motivo,
    this.metadata,
    required this.createdAt,
  });

  factory EstadoCargaModel.fromJson(Map<String, dynamic> json) {
    return EstadoCargaModel(
      id:           json['id'] as int,
      cargaId:      json['carga_id'] as int,
      estadoCodigo: json['estado_codigo'] as String,
      estadoNombre: json['estado_nombre'] as String?,
      usuarioUuid:  json['usuario_uuid'] as String?,
      driverId:     json['driver_id'] as int?,
      motivo:       json['motivo'] as String?,
      metadata:     json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toInsertJson() => {
        'carga_id':      cargaId,
        'estado_codigo': estadoCodigo,
        if (usuarioUuid != null) 'usuario_uuid': usuarioUuid,
        if (driverId != null)    'driver_id':    driverId,
        if (motivo != null)      'motivo':       motivo,
        if (metadata != null)    'metadata':     metadata,
      };
}

/// Representa una entrada del nomenclador [app_nom_estado].
class NomEstadoModel {
  final int id;
  final String codigo;
  final String nombre;
  final String? descripcion;
  final int orden;
  final bool activo;

  const NomEstadoModel({
    required this.id,
    required this.codigo,
    required this.nombre,
    this.descripcion,
    required this.orden,
    required this.activo,
  });

  factory NomEstadoModel.fromJson(Map<String, dynamic> json) {
    return NomEstadoModel(
      id:          json['id'] as int,
      codigo:      json['codigo'] as String,
      nombre:      json['nombre'] as String,
      descripcion: json['descripcion'] as String?,
      orden:       json['orden'] as int? ?? 0,
      activo:      json['activo'] as bool? ?? true,
    );
  }
}
