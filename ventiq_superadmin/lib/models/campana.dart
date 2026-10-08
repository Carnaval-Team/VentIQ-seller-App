/// CampaÃ±a patrocinada del Home: fila de `flow.campana`.
///
/// A diferencia de una promociÃ³n (que descuenta precio y la crea el admin de la
/// entidad), una campaÃ±a es **contenido de plataforma**: destaca un servicio o
/// una entidad en el Home y la cura el superadmin. **Nunca afecta al importe**
/// que paga el cliente.
class Campana {
  const Campana({
    required this.id,
    required this.titulo,
    this.subtitulo,
    this.descripcion,
    this.idLocalServicio,
    this.idEntidad,
    this.colorInicio,
    this.colorFin,
    this.icono,
    this.imageUrl,
    this.desde,
    this.hasta,
    this.prioridad = 0,
    this.activo = true,
    this.local,
    this.servicio,
    this.entidad,
  });

  final int id;
  final String titulo;
  final String? subtitulo;
  final String? descripcion;

  /// Alcance: un local-servicio concreto o toda una entidad. Exactamente uno.
  final int? idLocalServicio;
  final int? idEntidad;

  final String? colorInicio;
  final String? colorFin;
  final String? icono;
  final String? imageUrl;

  final DateTime? desde;
  final DateTime? hasta;

  /// Mayor = aparece antes en la rotaciÃ³n del Home.
  final int prioridad;

  final bool activo;

  /// Resueltos por el RPC, para pintar sin otra consulta.
  final String? local;
  final String? servicio;
  final String? entidad;

  bool get esDeEntidad => idEntidad != null;
  bool get tieneImagen => imageUrl != null && imageUrl!.trim().isNotEmpty;

  /// QuÃ© destaca, en una lÃ­nea, para el listado del superadmin.
  String get destino {
    if (esDeEntidad) return entidad ?? 'Entidad #$idEntidad';
    final partes = <String>[
      if (servicio != null) servicio!,
      if (local != null) local!,
    ];
    return partes.isEmpty ? 'Servicio #$idLocalServicio' : partes.join(' Â· ');
  }

  /// `true` si estÃ¡ activa y dentro de su ventana de vigencia.
  bool get vigente {
    if (!activo) return false;
    final ahora = DateTime.now();
    if (desde != null && ahora.isBefore(desde!)) return false;
    // `hasta` es exclusivo: una campaÃ±a que termina a las 00:00 ya no aplica.
    if (hasta != null && !ahora.isBefore(hasta!)) return false;
    return true;
  }

  factory Campana.fromJson(Map<String, dynamic> json) => Campana(
    id: (json['id'] as num).toInt(),
    titulo: json['titulo'] as String? ?? 'CampaÃ±a',
    subtitulo: json['subtitulo'] as String?,
    descripcion: json['descripcion'] as String?,
    idLocalServicio: (json['id_local_servicio'] as num?)?.toInt(),
    idEntidad: (json['id_entidad'] as num?)?.toInt(),
    colorInicio: json['color_inicio'] as String?,
    colorFin: json['color_fin'] as String?,
    icono: json['icono'] as String?,
    imageUrl: json['image_url'] as String?,
    desde: _fecha(json['desde']),
    hasta: _fecha(json['hasta']),
    prioridad: (json['prioridad'] as num?)?.toInt() ?? 0,
    activo: json['activo'] as bool? ?? true,
    local: json['local'] as String?,
    servicio: json['servicio'] as String?,
    entidad: json['entidad'] as String?,
  );

  static DateTime? _fecha(dynamic v) =>
      v is String ? DateTime.tryParse(v) : null;
}
