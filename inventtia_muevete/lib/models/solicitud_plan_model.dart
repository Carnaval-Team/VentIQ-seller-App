class SolicitudPlanModel {
  final int id;
  final String usuarioUuid;
  final String planCodigo;
  // 'pendiente' | 'aprobada' | 'rechazada'
  final String estado;
  final String evidenciaUrl;
  final String? codigoTransferencia;
  final String? observaciones;
  final String? adminUuid;
  final DateTime createdAt;
  final DateTime? updatedAt;

  // Datos enriquecidos opcionales (JOIN)
  final String? usuarioNombre;
  final String? usuarioEmail;
  final String? planNombre;
  final double? planPrecio;

  const SolicitudPlanModel({
    required this.id,
    required this.usuarioUuid,
    required this.planCodigo,
    required this.estado,
    required this.evidenciaUrl,
    this.codigoTransferencia,
    this.observaciones,
    this.adminUuid,
    required this.createdAt,
    this.updatedAt,
    this.usuarioNombre,
    this.usuarioEmail,
    this.planNombre,
    this.planPrecio,
  });

  bool get isPendiente => estado == 'pendiente';
  bool get isAprobada => estado == 'aprobada';
  bool get isRechazada => estado == 'rechazada';

  String get estadoLabel {
    switch (estado) {
      case 'pendiente':
        return 'Pendiente';
      case 'aprobada':
        return 'Aprobada';
      case 'rechazada':
        return 'Rechazada';
      default:
        return estado;
    }
  }

  factory SolicitudPlanModel.fromJson(Map<String, dynamic> json) {
    return SolicitudPlanModel(
      id: json['id'] as int,
      usuarioUuid: json['usuario_uuid'] as String,
      planCodigo: json['plan_codigo'] as String,
      estado: json['estado'] as String? ?? 'pendiente',
      evidenciaUrl: json['evidencia_url'] as String? ?? '',
      codigoTransferencia: json['codigo_transferencia'] as String?,
      observaciones: json['observaciones'] as String?,
      adminUuid: json['admin_uuid'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
      usuarioNombre: json['usuario_nombre'] as String?,
      usuarioEmail: json['usuario_email'] as String?,
      planNombre: json['plan_nombre'] as String?,
      planPrecio: (json['plan_precio'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toInsertJson() => {
        'usuario_uuid': usuarioUuid,
        'plan_codigo': planCodigo,
        'estado': estado,
        'evidencia_url': evidenciaUrl,
        if (codigoTransferencia != null)
          'codigo_transferencia': codigoTransferencia,
        if (observaciones != null) 'observaciones': observaciones,
      };
}
