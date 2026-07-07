enum WapiDestinatarioTipo { numero, grupo }

extension WapiDestinatarioTipoX on WapiDestinatarioTipo {
  String get apiValue =>
      this == WapiDestinatarioTipo.numero ? 'numero' : 'grupo';

  String get label =>
      this == WapiDestinatarioTipo.numero ? 'Número' : 'Grupo';

  static WapiDestinatarioTipo fromString(String s) =>
      s == 'grupo' ? WapiDestinatarioTipo.grupo : WapiDestinatarioTipo.numero;
}

class WapiDestinatario {
  final int id;
  final int idTienda;
  final int? idSesion;
  final WapiDestinatarioTipo tipo;
  final String chatId;
  final String? etiqueta;
  final DateTime createdAt;

  WapiDestinatario({
    required this.id,
    required this.idTienda,
    this.idSesion,
    required this.tipo,
    required this.chatId,
    this.etiqueta,
    required this.createdAt,
  });

  factory WapiDestinatario.fromJson(Map<String, dynamic> j) {
    return WapiDestinatario(
      id: (j['id'] as num).toInt(),
      idTienda: (j['id_tienda'] as num).toInt(),
      idSesion: (j['id_sesion'] as num?)?.toInt(),
      tipo: WapiDestinatarioTipoX.fromString((j['tipo'] ?? 'numero') as String),
      chatId: (j['chat_id'] ?? '') as String,
      etiqueta: j['etiqueta'] as String?,
      createdAt: DateTime.tryParse(j['created_at'] ?? '') ?? DateTime.now(),
    );
  }

  /// Convierte un número de teléfono limpio (sólo dígitos, sin +) a formato WAPI.
  static String numeroToChatId(String numero) {
    final clean = numero.replaceAll(RegExp(r'\D'), '');
    return '$clean@c.us';
  }
}
