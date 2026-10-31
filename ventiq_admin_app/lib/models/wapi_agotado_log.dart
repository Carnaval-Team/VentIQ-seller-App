/// Estado de un aviso de agotado en el historial (`app_wapi_agotado_log`).
/// El CHECK de la tabla admite pendiente/enviado/fallido/omitido: `omitido`
/// es el que usa el backend cuando no pudo ni intentarlo (p. ej. faltan
/// secretos en Vault), para no dejarlo eternamente "pendiente".
enum WapiAgotadoEstado { pendiente, enviado, fallido, omitido }

extension WapiAgotadoEstadoX on WapiAgotadoEstado {
  String get apiValue {
    switch (this) {
      case WapiAgotadoEstado.pendiente:
        return 'pendiente';
      case WapiAgotadoEstado.enviado:
        return 'enviado';
      case WapiAgotadoEstado.fallido:
        return 'fallido';
      case WapiAgotadoEstado.omitido:
        return 'omitido';
    }
  }

  String get label {
    switch (this) {
      case WapiAgotadoEstado.pendiente:
        return 'Pendiente';
      case WapiAgotadoEstado.enviado:
        return 'Enviado';
      case WapiAgotadoEstado.fallido:
        return 'Fallido';
      case WapiAgotadoEstado.omitido:
        return 'Omitido';
    }
  }

  static WapiAgotadoEstado fromString(String? s) {
    switch ((s ?? '').toLowerCase()) {
      case 'enviado':
        return WapiAgotadoEstado.enviado;
      case 'fallido':
        return WapiAgotadoEstado.fallido;
      case 'omitido':
        return WapiAgotadoEstado.omitido;
      default:
        return WapiAgotadoEstado.pendiente;
    }
  }
}

/// Una fila del historial de avisos de agotado: a quién se le avisó de qué
/// producto y cómo terminó.
class WapiAgotadoLog {
  final int id;
  final int idTienda;
  final int? idProducto;
  final String chatId;
  final int? idDestinatario;
  final WapiAgotadoEstado estado;
  final String? errorCode;
  final String? errorMessage;
  final String? mensajeId;
  final DateTime? sentAt;
  final DateTime? createdAt;

  const WapiAgotadoLog({
    required this.id,
    required this.idTienda,
    this.idProducto,
    required this.chatId,
    this.idDestinatario,
    required this.estado,
    this.errorCode,
    this.errorMessage,
    this.mensajeId,
    this.sentAt,
    this.createdAt,
  });

  factory WapiAgotadoLog.fromJson(Map<String, dynamic> j) {
    return WapiAgotadoLog(
      id: (j['id'] as num?)?.toInt() ?? 0,
      idTienda: (j['id_tienda'] as num?)?.toInt() ?? 0,
      idProducto: (j['id_producto'] as num?)?.toInt(),
      chatId: (j['chat_id'] ?? '') as String,
      idDestinatario: (j['id_destinatario'] as num?)?.toInt(),
      estado: WapiAgotadoEstadoX.fromString(j['estado'] as String?),
      errorCode: j['error_code'] as String?,
      errorMessage: j['error_message'] as String?,
      mensajeId: j['mensaje_id'] as String?,
      sentAt: j['sent_at'] != null
          ? DateTime.tryParse('${j['sent_at']}')
          : null,
      createdAt: j['created_at'] != null
          ? DateTime.tryParse('${j['created_at']}')
          : null,
    );
  }
}
