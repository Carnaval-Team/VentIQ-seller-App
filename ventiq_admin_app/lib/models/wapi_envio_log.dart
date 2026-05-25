enum WapiEnvioEstado { pendiente, enviado, fallido }

class WapiEnvioLog {
  final int id;
  final int idTienda;
  final int? idSesion;
  final int? idProgramacion;
  final int? idProducto;
  final String chatId;
  final String tipoEnvio; // 'manual' | 'programado'
  final WapiEnvioEstado estado;
  final String? mensajeId;
  final String? errorCode;
  final String? errorMessage;
  final DateTime? sentAt;
  final DateTime createdAt;

  WapiEnvioLog({
    required this.id,
    required this.idTienda,
    this.idSesion,
    this.idProgramacion,
    this.idProducto,
    required this.chatId,
    required this.tipoEnvio,
    required this.estado,
    this.mensajeId,
    this.errorCode,
    this.errorMessage,
    this.sentAt,
    required this.createdAt,
  });

  factory WapiEnvioLog.fromJson(Map<String, dynamic> j) {
    WapiEnvioEstado parseEstado(String s) {
      switch (s) {
        case 'enviado':
          return WapiEnvioEstado.enviado;
        case 'fallido':
          return WapiEnvioEstado.fallido;
        default:
          return WapiEnvioEstado.pendiente;
      }
    }

    return WapiEnvioLog(
      id: (j['id'] as num).toInt(),
      idTienda: (j['id_tienda'] as num).toInt(),
      idSesion: (j['id_sesion'] as num?)?.toInt(),
      idProgramacion: (j['id_programacion'] as num?)?.toInt(),
      idProducto: (j['id_producto'] as num?)?.toInt(),
      chatId: (j['chat_id'] ?? '') as String,
      tipoEnvio: (j['tipo_envio'] ?? 'manual') as String,
      estado: parseEstado((j['estado'] ?? 'pendiente') as String),
      mensajeId: j['mensaje_id'] as String?,
      errorCode: j['error_code'] as String?,
      errorMessage: j['error_message'] as String?,
      sentAt: j['sent_at'] != null ? DateTime.tryParse(j['sent_at']) : null,
      createdAt: DateTime.tryParse(j['created_at'] ?? '') ?? DateTime.now(),
    );
  }
}
