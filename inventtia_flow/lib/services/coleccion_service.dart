import 'package:supabase_flutter/supabase_flutter.dart';

/// Colección temática del Home (`flow.coleccion`).
///
/// Una colección es una lista **curada y ordenada** de servicios que cruza
/// entidades: "Pack Novia" puede mezclar servicios de tres negocios distintos.
/// Por eso las cura el **superadmin** desde `ventiq_superadmin`, igual que las
/// campañas patrocinadas, y no el admin de cada entidad.
///
/// **Una colección nunca cambia el precio.** Solo agrupa. Los descuentos son
/// `flow.promocion` (ver [HomeFeatures.ofertasRelampago]).
///
/// Nota de arquitectura: [servicios] trae los `id_local_servicio` para que el
/// Home pueda filtrar **en memoria** sobre el catálogo ya cacheado, exactamente
/// como hace con las categorías. No hay una petición por colección.
class Coleccion {
  const Coleccion({
    required this.id,
    required this.titulo,
    this.subtitulo,
    this.icono,
    this.colorInicio,
    this.colorFin,
    this.orden = 0,
    this.hasta,
    this.totalServicios = 0,
    this.servicios = const <int>[],
  });

  /// `flow.coleccion.id`.
  final int id;

  final String titulo;
  final String? subtitulo;

  /// Emoji o glifo corto que pinta la tarjeta.
  final String? icono;

  /// Colores de la tarjeta en `#RRGGBB`. Si faltan, se usa el degradado por
  /// defecto del tema.
  final String? colorInicio;
  final String? colorFin;

  /// Menor = va antes. El orden ya viene resuelto del servidor.
  final int orden;

  /// Fin de vigencia. `null` = sin caducidad.
  final DateTime? hasta;

  /// Cuántos servicios componen la colección.
  final int totalServicios;

  /// `flow.local_servicio.id` de los servicios curados, **en el orden elegido**.
  ///
  /// Es lo que usa el Home para filtrar el feed. Puede estar vacío si el
  /// superadmin todavía no añadió servicios: en ese caso la colección no llega
  /// al cliente (`colecciones_activas()` las excluye).
  final List<int> servicios;

  bool get tieneServicios => servicios.isNotEmpty;

  /// Texto de la tarjeta: "1 servicio" / "12 servicios".
  String get etiquetaServicios => totalServicios == 1
      ? '1 servicio'
      : '$totalServicios servicios';

  /// Subtítulo para la tarjeta, o el recuento si no hay subtítulo.
  String get subtituloORecuento {
    final s = subtitulo?.trim();
    return (s != null && s.isNotEmpty) ? s : etiquetaServicios;
  }

  factory Coleccion.fromJson(Map<String, dynamic> json) {
    final crudos = json['servicios'];
    return Coleccion(
      id: (json['id'] as num).toInt(),
      titulo: json['titulo'] as String? ?? '',
      subtitulo: json['subtitulo'] as String?,
      icono: json['icono'] as String?,
      colorInicio: json['color_inicio'] as String?,
      colorFin: json['color_fin'] as String?,
      orden: (json['orden'] as num?)?.toInt() ?? 0,
      hasta: _fecha(json['hasta']),
      totalServicios: (json['total_servicios'] as num?)?.toInt() ?? 0,
      // `jsonb_agg` de enteros llega como List<dynamic> de num.
      servicios: crudos is List
          ? crudos.whereType<num>().map((e) => e.toInt()).toList()
          : const <int>[],
    );
  }

  static DateTime? _fecha(dynamic v) =>
      v is String ? DateTime.tryParse(v) : null;
}

/// Lectura de las colecciones temáticas vigentes.
class ColeccionService {
  const ColeccionService._();

  static const String _schema = 'flow';

  /// Colecciones activas, dentro de fecha y **con al menos un servicio**, ya
  /// ordenadas por `orden`.
  ///
  /// Devuelve lista vacía si la migración `30_colecciones.sql` no está aplicada,
  /// si no hay sesión o si el superadmin no ha curado ninguna. Es deliberado:
  /// el Home debe seguir funcionando sin la sección, en vez de romperse o
  /// pintar tarjetas inventadas (que es lo que hacía antes con "Pack Novia").
  ///
  /// El RPC está concedido a `authenticated`, no a `anon`.
  static Future<List<Coleccion>> activas() async {
    try {
      final res = await Supabase.instance.client
          .schema(_schema)
          .rpc('colecciones_activas');

      // `colecciones_activas()` devuelve `jsonb` construido con `jsonb_agg`,
      // así que llega como lista. Si llegara un objeto suelto, se descarta.
      if (res is! List) return const <Coleccion>[];
      return res
          .whereType<Map>()
          .map((e) => Coleccion.fromJson(Map<String, dynamic>.from(e)))
          // El RPC ya excluye las vacías; esto es una red de seguridad por si la
          // forma del JSON cambia y `servicios` no parsea.
          .where((c) => c.tieneServicios)
          .toList();
    } catch (_) {
      return const <Coleccion>[];
    }
  }
}
