import 'package:supabase_flutter/supabase_flutter.dart';

/// Campaña patrocinada del Home (`flow.campana`).
///
/// Las cura el **superadmin** desde la app `ventiq_superadmin`. El cliente solo
/// las lee: este archivo no tiene ninguna operación de escritura.
///
/// **Una campaña nunca cambia el precio.** Solo decide qué se destaca. Los
/// descuentos son otra cosa (`flow.promocion`, `PromocionService`), y se aplican
/// dentro de `cotizar_reserva` en el servidor.
class CampanaPatrocinada {
  const CampanaPatrocinada({
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
    this.prioridad = 0,
    this.hasta,
    this.local,
    this.servicio,
    this.entidad,
    this.idLocal,
    this.localFoto,
    this.localDescripcion,
    this.localDireccion,
    this.localProvincia,
    this.localPais,
    this.localHorarioAtencion,
    this.localHorarioDetalle,
    this.localCoordenadas,
    this.idEntidadReal,
    this.entidadTelefono,
    this.entidadDireccion,
  });

  final int id;
  final String titulo;
  final String? subtitulo;
  final String? descripcion;

  /// Alcance. Una campaña de entidad no trae `idLocalServicio`, así que no se
  /// puede abrir desde el carrusel: para esas se destaca la entidad.
  final int? idLocalServicio;
  final int? idEntidad;

  final String? colorInicio;
  final String? colorFin;
  final String? icono;
  final String? imageUrl;

  /// Mayor = va antes en la rotación. El orden ya viene resuelto del servidor.
  final int prioridad;

  final DateTime? hasta;

  /// Resueltos por el RPC, para no cruzar nada en el cliente.
  final String? local;
  final String? servicio;
  final String? entidad;

  /// `flow.app_dat_locales.id` del local destacado. `null` en una campaña de
  /// entidad (no apunta a un establecimiento concreto).
  final int? idLocal;

  /// Imagen del LOCAL, no la de la campaña ([imageUrl]). Es la que se pinta de
  /// fondo en la tarjeta del Home y en la cabecera de la vista de marketing.
  /// Llega desde la migración `49_campanas_datos_local.sql`; si no está
  /// aplicada, es `null` y se cae a [imageUrl].
  final String? localFoto;
  final String? localDescripcion;
  final String? localDireccion;
  final String? localProvincia;
  final String? localPais;
  final String? localHorarioAtencion;
  final Map<String, dynamic>? localHorarioDetalle;
  final Map<String, dynamic>? localCoordenadas;

  /// Entidad real del destino: la del local si lo hay, si no la de la campaña.
  final int? idEntidadReal;
  final String? entidadTelefono;
  final String? entidadDireccion;

  /// Imagen de cabecera: la del local manda sobre la de la campaña.
  String? get imagenPrincipal =>
      (localFoto?.trim().isNotEmpty ?? false) ? localFoto : imageUrl;

  bool get esDeLocal => (local?.trim().isNotEmpty ?? false);

  /// Ubicación legible del local, sin duplicados ni comas sueltas.
  String? get ubicacionLocal {
    final partes = <String>[
      if (localProvincia != null && localProvincia!.trim().isNotEmpty)
        localProvincia!.trim(),
      if (localPais != null && localPais!.trim().isNotEmpty) localPais!.trim(),
    ];
    return partes.isEmpty ? null : partes.join(', ');
  }

  bool get tieneImagen => imageUrl != null && imageUrl!.trim().isNotEmpty;

  /// `true` si se puede abrir el detalle de un servicio concreto.
  bool get esDeServicio => idLocalServicio != null;

  /// Texto que se pinta bajo el título si la campaña no trae subtítulo.
  String get subtituloONombre => (subtitulo?.trim().isNotEmpty ?? false)
      ? subtitulo!.trim()
      : [servicio, local].whereType<String>().join(' · ');

  factory CampanaPatrocinada.fromJson(Map<String, dynamic> json) {
    return CampanaPatrocinada(
      id: (json['id'] as num).toInt(),
      titulo: json['titulo'] as String? ?? '',
      subtitulo: json['subtitulo'] as String?,
      descripcion: json['descripcion'] as String?,
      idLocalServicio: (json['id_local_servicio'] as num?)?.toInt(),
      idEntidad: (json['id_entidad'] as num?)?.toInt(),
      colorInicio: json['color_inicio'] as String?,
      colorFin: json['color_fin'] as String?,
      icono: json['icono'] as String?,
      imageUrl: json['image_url'] as String?,
      prioridad: (json['prioridad'] as num?)?.toInt() ?? 0,
      hasta: _fecha(json['hasta']),
      local: json['local'] as String?,
      servicio: json['servicio'] as String?,
      entidad: json['entidad'] as String?,
      idLocal: (json['id_local'] as num?)?.toInt(),
      localFoto: json['local_foto'] as String?,
      localDescripcion: json['local_descripcion'] as String?,
      localDireccion: json['local_direccion'] as String?,
      localProvincia: json['local_provincia'] as String?,
      localPais: json['local_pais'] as String?,
      localHorarioAtencion: json['local_horario_atencion'] as String?,
      localHorarioDetalle: json['local_horario_detalle'] as Map<String, dynamic>?,
      localCoordenadas: json['local_coordenadas'] as Map<String, dynamic>?,
      idEntidadReal: (json['id_entidad_real'] as num?)?.toInt(),
      entidadTelefono: json['entidad_telefono'] as String?,
      entidadDireccion: json['entidad_direccion'] as String?,
    );
  }

  static DateTime? _fecha(dynamic v) =>
      v is String ? DateTime.tryParse(v) : null;
}

/// Lectura de las campañas patrocinadas vigentes.
class CampanaService {
  const CampanaService._();

  static const String _schema = 'flow';

  /// Campañas activas y dentro de fecha, ya ordenadas por prioridad.
  ///
  /// Devuelve lista vacía si la migración `28_patrocinados.sql` no está aplicada
  /// o si no hay sesión. Es deliberado: el Home debe seguir funcionando sin la
  /// sección de patrocinados en vez de romperse o inventar tarjetas.
  ///
  /// Nota: el RPC está concedido a `authenticated`, no a `anon`, porque el
  /// espacio patrocinado es contenido para usuarios con sesión.
  static Future<List<CampanaPatrocinada>> activas() async {
    try {
      final res = await Supabase.instance.client
          .schema(_schema)
          .rpc('campanas_activas');

      // `campanas_activas()` devuelve `jsonb` construido con `jsonb_agg`, así
      // que llega como lista. Si llegara un objeto suelto, se descarta.
      if (res is! List) return const [];
      return res
          .whereType<Map>()
          .map((e) => CampanaPatrocinada.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
