/// Configuración de los AVISOS AUTOMÁTICOS DE AGOTADO.
///
/// Cuando un producto llega a stock 0, el backend (`wapi-notify-agotado`)
/// avisa a los grupos elegidos aquí, con la plantilla y los delays
/// configurados. Esta clase es sólo el espejo de la fila de
/// `app_wapi_agotado_config`; los destinatarios viven en el join
/// `app_wapi_agotado_destinatario`.
class WapiAgotadoConfig {
  final int id;
  final int idTienda;
  final int? idSesion;
  final bool activo;
  final String plantilla;
  final int delayMinSeconds;
  final int delayMaxSeconds;
  final int cooldownMinutos;
  final List<int> destinatarioIds;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const WapiAgotadoConfig({
    required this.id,
    required this.idTienda,
    this.idSesion,
    this.activo = false,
    required this.plantilla,
    this.delayMinSeconds = 5,
    this.delayMaxSeconds = 10,
    this.cooldownMinutos = 60,
    this.destinatarioIds = const [],
    this.createdAt,
    this.updatedAt,
  });

  /// Plantilla que se propone la primera vez. Los placeholders entre llaves
  /// los sustituye el backend al enviar (ver [WapiAgotadoPlantilla]).
  static const String plantillaDefault =
      '🔔 ¡Atención!\n'
      '{producto} se quedó sin stock.\n'
      'Te avisamos apenas vuelva a estar disponible en {tienda}.';

  factory WapiAgotadoConfig.fromJson(
    Map<String, dynamic> j, {
    List<int>? destinatarioIds,
  }) {
    return WapiAgotadoConfig(
      id: (j['id'] as num?)?.toInt() ?? 0,
      idTienda: (j['id_tienda'] as num?)?.toInt() ?? 0,
      idSesion: (j['id_sesion'] as num?)?.toInt(),
      activo: (j['activo'] as bool?) ?? false,
      plantilla: (j['plantilla'] as String?)?.trim().isNotEmpty == true
          ? (j['plantilla'] as String)
          : plantillaDefault,
      delayMinSeconds: (j['delay_min_seconds'] as num?)?.toInt() ?? 5,
      delayMaxSeconds: (j['delay_max_seconds'] as num?)?.toInt() ?? 10,
      cooldownMinutos: (j['cooldown_minutos'] as num?)?.toInt() ?? 60,
      destinatarioIds: destinatarioIds ?? const [],
      createdAt: j['created_at'] != null
          ? DateTime.tryParse('${j['created_at']}')
          : null,
      updatedAt: j['updated_at'] != null
          ? DateTime.tryParse('${j['updated_at']}')
          : null,
    );
  }

  WapiAgotadoConfig copyWith({
    int? id,
    int? idSesion,
    bool? activo,
    String? plantilla,
    int? delayMinSeconds,
    int? delayMaxSeconds,
    int? cooldownMinutos,
    List<int>? destinatarioIds,
  }) {
    return WapiAgotadoConfig(
      id: id ?? this.id,
      idTienda: idTienda,
      idSesion: idSesion ?? this.idSesion,
      activo: activo ?? this.activo,
      plantilla: plantilla ?? this.plantilla,
      delayMinSeconds: delayMinSeconds ?? this.delayMinSeconds,
      delayMaxSeconds: delayMaxSeconds ?? this.delayMaxSeconds,
      cooldownMinutos: cooldownMinutos ?? this.cooldownMinutos,
      destinatarioIds: destinatarioIds ?? this.destinatarioIds,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Campos que el servicio escribe en `app_wapi_agotado_config`.
  Map<String, dynamic> toDbMap() => {
    'id_tienda': idTienda,
    'id_sesion': idSesion,
    'activo': activo,
    'plantilla': plantilla,
    'delay_min_seconds': delayMinSeconds,
    'delay_max_seconds': delayMaxSeconds,
    'cooldown_minutos': cooldownMinutos,
  };

  bool get tieneDestinatarios => destinatarioIds.isNotEmpty;

  /// Un aviso sólo puede salir si está activo y tiene a quién avisar.
  bool get operativa => activo && tieneDestinatarios;
}

/// Placeholders soportados por la plantilla del aviso de agotado.
///
/// Vive en el modelo (y no en la pantalla) para poder probarlo sin Flutter:
/// el reemplazo lo hace el backend, aquí sólo lo previsualizamos y avisamos
/// de los tokens que nunca se sustituirán.
class WapiAgotadoPlantilla {
  WapiAgotadoPlantilla._();

  /// token → descripción para el usuario.
  static const Map<String, String> placeholders = {
    '{producto}': 'Nombre del producto',
    '{precio}': 'Precio de venta',
    '{stock}': 'Stock actual (normalmente 0)',
    '{categoria}': 'Categoría del producto',
    '{tienda}': 'Nombre de tu tienda',
  };

  /// Valores de ejemplo para la vista previa.
  static const Map<String, String> ejemplo = {
    '{producto}': 'Café molido 250 g',
    '{precio}': '12.50',
    '{stock}': '0',
    '{categoria}': 'Cafetería',
    '{tienda}': 'Mi tienda',
  };

  // Admite dígitos: `{precio2}` es un typo que queremos que el usuario vea,
  // no un token válido que se cuele en el mensaje.
  static final RegExp _token = RegExp(r'\{([a-zA-Z0-9_]+)\}');

  /// Sustituye los placeholders conocidos que estén en [valores]. Los tokens
  /// desconocidos o sin valor se dejan tal cual: el texto nunca se rompe.
  static String render(String plantilla, Map<String, String> valores) {
    var salida = plantilla;
    for (final entry in valores.entries) {
      salida = salida.replaceAll(entry.key, entry.value);
    }
    return salida;
  }

  /// Tokens `{...}` de la plantilla que el backend NO sustituye (typos como
  /// `{produto}`). Se avisa al usuario en vez de enviar el aviso con las
  /// llaves literales dentro.
  static List<String> tokensDesconocidos(String plantilla) {
    final vistos = <String>{};
    for (final m in _token.allMatches(plantilla)) {
      final token = m.group(0)!;
      if (!placeholders.containsKey(token)) vistos.add(token);
    }
    final lista = vistos.toList()..sort();
    return lista;
  }
}
