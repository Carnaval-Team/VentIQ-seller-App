enum NotificationType {
  nuevaSolicitud,
  nuevaOferta,
  ofertaAceptada,
  viajeIniciado,
  driverEsperando,
  viajeCompletado,
}

NotificationType notificationTypeFromString(String tipo) {
  switch (tipo) {
    case 'nueva_solicitud':
      return NotificationType.nuevaSolicitud;
    case 'nueva_oferta':
      return NotificationType.nuevaOferta;
    case 'oferta_aceptada':
      return NotificationType.ofertaAceptada;
    case 'viaje_iniciado':
      return NotificationType.viajeIniciado;
    case 'driver_esperando':
      return NotificationType.driverEsperando;
    case 'viaje_completado':
      return NotificationType.viajeCompletado;
    default:
      return NotificationType.nuevaSolicitud;
  }
}

String notificationTypeToString(NotificationType tipo) {
  switch (tipo) {
    case NotificationType.nuevaSolicitud:
      return 'nueva_solicitud';
    case NotificationType.nuevaOferta:
      return 'nueva_oferta';
    case NotificationType.ofertaAceptada:
      return 'oferta_aceptada';
    case NotificationType.viajeIniciado:
      return 'viaje_iniciado';
    case NotificationType.driverEsperando:
      return 'driver_esperando';
    case NotificationType.viajeCompletado:
      return 'viaje_completado';
  }
}

class NotificationModel {
  final int? id;
  final String userUuid;
  final NotificationType tipo;
  final String titulo;
  final String mensaje;
  final Map<String, dynamic> data;
  final bool leida;
  final DateTime? createdAt;

  NotificationModel({
    this.id,
    required this.userUuid,
    required this.tipo,
    required this.titulo,
    required this.mensaje,
    this.data = const {},
    this.leida = false,
    this.createdAt,
  });

  factory NotificationModel.fromMap(Map<String, dynamic> map) {
    return NotificationModel(
      id: map['id'] as int?,
      userUuid: map['user_uuid'] as String? ?? '',
      tipo: notificationTypeFromString(map['tipo'] as String? ?? ''),
      titulo: map['titulo'] as String? ?? '',
      mensaje: map['mensaje'] as String? ?? '',
      data: map['data'] as Map<String, dynamic>? ?? {},
      leida: map['leida'] as bool? ?? false,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'user_uuid': userUuid,
      'tipo': notificationTypeToString(tipo),
      'titulo': titulo,
      'mensaje': mensaje,
      'data': data,
      'leida': leida,
    };
  }
}
