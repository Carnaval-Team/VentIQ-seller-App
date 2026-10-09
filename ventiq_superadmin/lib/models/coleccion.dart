/// Colección temática del Home: fila de `flow.coleccion`.
///
/// Una colección es una lista **curada y ordenada** de servicios que cruza
/// entidades: "Pack Novia" puede mezclar servicios de tres negocios distintos.
/// Por eso la cura el **superadmin**, igual que el espacio patrocinado, y no el
/// admin de cada entidad.
///
/// **Una colección nunca afecta al importe** que paga el cliente. Solo agrupa
/// servicios; los descuentos son `flow.promocion` y los crea el admin de la
/// entidad.
class Coleccion {
  const Coleccion({
    required this.id,
    required this.titulo,
    this.subtitulo,
    this.icono,
    this.colorInicio,
    this.colorFin,
    this.orden = 0,
    this.activo = true,
    this.desde,
    this.hasta,
    this.totalServicios = 0,
    this.servicios = const <int>[],
  });

  final int id;
  final String titulo;
  final String? subtitulo;

  /// Emoji o glifo corto de la tarjeta.
  final String? icono;

  /// Colores en `#RRGGBB`.
  final String? colorInicio;
  final String? colorFin;

  /// Menor = antes en el Home.
  final int orden;

  final bool activo;

  final DateTime? desde;
  final DateTime? hasta;

  /// Cuántos servicios componen la colección.
  final int totalServicios;

  /// `flow.local_servicio.id` de los servicios curados, en el orden guardado.
  final List<int> servicios;

  bool get tieneServicios => servicios.isNotEmpty;

  String get etiquetaServicios =>
      totalServicios == 1 ? '1 servicio' : '$totalServicios servicios';

  /// `true` si está activa y dentro de su ventana de vigencia.
  bool get vigente {
    if (!activo) return false;
    final ahora = DateTime.now();
    if (desde != null && ahora.isBefore(desde!)) return false;
    // `hasta` es exclusivo, igual que en el backend.
    if (hasta != null && !ahora.isBefore(hasta!)) return false;
    return true;
  }

  factory Coleccion.fromJson(Map<String, dynamic> json) {
    final crudos = json['servicios'];
    return Coleccion(
      id: (json['id'] as num).toInt(),
      titulo: json['titulo'] as String? ?? 'Colección',
      subtitulo: json['subtitulo'] as String?,
      icono: json['icono'] as String?,
      colorInicio: json['color_inicio'] as String?,
      colorFin: json['color_fin'] as String?,
      orden: (json['orden'] as num?)?.toInt() ?? 0,
      activo: json['activo'] as bool? ?? true,
      desde: _fecha(json['desde']),
      hasta: _fecha(json['hasta']),
      totalServicios: (json['total_servicios'] as num?)?.toInt() ?? 0,
      servicios: crudos is List
          ? crudos.whereType<num>().map((e) => e.toInt()).toList()
          : const <int>[],
    );
  }

  static DateTime? _fecha(dynamic v) =>
      v is String ? DateTime.tryParse(v) : null;
}
