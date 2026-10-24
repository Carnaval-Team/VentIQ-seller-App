import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Una reseña de servicio: fila de `flow.resena`.
///
/// El autor llega ya abreviado desde el RPC ("Ana R."): el apellido completo, el
/// CI y el teléfono nunca salen de la base. Es una decisión del servidor, no del
/// cliente, para que cambiarla no obligue a publicar una versión nueva.
class Resena {
  const Resena({
    required this.id,
    required this.puntuacion,
    this.idAgenda,
    this.comentario,
    this.autor = 'Cliente',
    this.createdAt,
    this.idLocalServicio,
    this.servicio,
    this.local,
    this.esMia = false,
  });

  final int id;

  /// 1 a 5.
  final int puntuacion;

  /// Reserva que la respalda. Necesario para editar: `publicar_resena` se ancla
  /// en `id_agenda`, no en el id de la reseña.
  final int? idAgenda;

  final String? comentario;

  /// "Ana R." o "Cliente" si el autor no tiene perfil.
  final String autor;

  final DateTime? createdAt;

  final int? idLocalServicio;

  /// Solo en el feed del Home.
  final String? servicio;
  final String? local;

  final bool esMia;

  bool get tieneComentario =>
      comentario != null && comentario!.trim().isNotEmpty;

  factory Resena.fromJson(Map<String, dynamic> json) => Resena(
    id: (json['id'] as num).toInt(),
    puntuacion: (json['puntuacion'] as num).toInt(),
    idAgenda: (json['id_agenda'] as num?)?.toInt(),
    comentario: json['comentario'] as String?,
    autor: json['autor'] as String? ?? 'Cliente',
    createdAt: json['created_at'] != null
        ? DateTime.tryParse(json['created_at'] as String)
        : null,
    idLocalServicio: (json['id_local_servicio'] as num?)?.toInt(),
    servicio: json['servicio'] as String?,
    local: json['local'] as String?,
    esMia: json['es_mia'] as bool? ?? false,
  );
}

/// Resumen de valoraciones de un servicio.
class ResumenResenas {
  const ResumenResenas({
    required this.total,
    required this.promedio,
    this.distribucion = const <int, int>{},
  });

  final int total;
  final double promedio;

  /// Estrellas (1..5) → cuántas reseñas.
  final Map<int, int> distribucion;

  bool get hayDatos => total > 0;

  static const ResumenResenas vacio = ResumenResenas(total: 0, promedio: 0);

  factory ResumenResenas.fromJson(Map<String, dynamic>? json) {
    if (json == null) return vacio;
    // `as Map<String, dynamic>?` es un cast estricto y revienta si el mapa
    // viene como `Map<dynamic, dynamic>` (pasa con jsonb anidado según cómo lo
    // construya el driver). Se convierte explícitamente.
    final estrellasRaw = json['estrellas'];
    final estrellas = estrellasRaw is Map
        ? Map<String, dynamic>.from(estrellasRaw)
        : const <String, dynamic>{};
    return ResumenResenas(
      total: (json['total'] as num?)?.toInt() ?? 0,
      promedio: (json['promedio'] as num?)?.toDouble() ?? 0,
      distribucion: {
        for (var i = 1; i <= 5; i++)
          i: ((estrellas['$i'] as num?)?.toInt() ?? 0),
      },
    );
  }
}

/// Lo que devuelve `flow.resenas_de_servicio` para un servicio.
class ResenasDeServicio {
  const ResenasDeServicio({
    required this.resumen,
    required this.items,
    this.miResena,
    this.agendaResenable,
  });

  final ResumenResenas resumen;
  final List<Resena> items;

  /// La reseña del usuario actual, si ya opinó.
  final Resena? miResena;

  /// Reserva completada propia que todavía no reseñó.
  ///
  /// Es lo que permite mostrar el formulario **solo** cuando guardar va a
  /// funcionar, en vez de ofrecerlo siempre y fallar al pulsar.
  final ({int idAgenda, DateTime? atendido})? agendaResenable;

  bool get puedoResenar => agendaResenable != null;

  static const ResenasDeServicio vacio = ResenasDeServicio(
    resumen: ResumenResenas.vacio,
    items: <Resena>[],
  );

  factory ResenasDeServicio.fromJson(Map<String, dynamic>? json) {
    if (json == null || json['ok'] != true) return vacio;

    // Conversión explícita en vez de cast estricto: un jsonb anidado puede
    // llegar como Map<dynamic, dynamic> y `as Map<String, dynamic>?` lanzaría.
    final agendaRaw = json['agenda_resenable'];
    final agenda = agendaRaw is Map
        ? Map<String, dynamic>.from(agendaRaw)
        : null;
    final miasRaw = json['mi_resena'];
    final mias = miasRaw is Map ? Map<String, dynamic>.from(miasRaw) : null;
    final resumenRaw = json['resumen'];
    final crudas = json['items'] as List? ?? const [];

    return ResenasDeServicio(
      resumen: ResumenResenas.fromJson(
        resumenRaw is Map ? Map<String, dynamic>.from(resumenRaw) : null,
      ),
      items: crudas
          .whereType<Map>()
          .map((e) => Resena.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      miResena: mias == null ? null : Resena.fromJson(mias),
      agendaResenable: agenda == null
          ? null
          : (
              idAgenda: (agenda['id_agenda'] as num).toInt(),
              atendido: agenda['atendido'] != null
                  ? DateTime.tryParse(agenda['atendido'] as String)
                  : null,
            ),
    );
  }
}

/// Una reserva completada a la que todavía le falta su reseña.
///
/// Es lo que necesita el cartel que pide la opinión al cliente: de qué servicio
/// fue, dónde, cuándo, y con qué id de reserva publicarla (`publicar_resena` se
/// ancla en `id_agenda`, no en el servicio).
///
/// Sale de `flow.cliente_resenas_pendientes()` (migración 59).
class ResenaPendiente {
  const ResenaPendiente({
    required this.idAgenda,
    required this.idLocalServicio,
    required this.servicioNombre,
    required this.localNombre,
    this.servicioFoto,
    this.categoria,
    this.atendido,
  });

  final int idAgenda;
  final int idLocalServicio;
  final String servicioNombre;
  final String localNombre;

  /// Foto del servicio. `null` = el cartel pinta su respaldo degradado.
  final String? servicioFoto;

  /// Categoría o subcategoría del servicio, si el nomenclador la tiene.
  final String? categoria;

  /// Cuándo se atendió (`fecha_hora_atencion`, o la de la reserva si no hay).
  final DateTime? atendido;

  /// `"hoy"`, `"ayer"` o `"el 20/10/2026"`.
  ///
  /// [ahora] es inyectable para poder probar los tres casos sin depender del
  /// reloj.
  String etiquetaFecha({DateTime? ahora}) {
    final fecha = atendido;
    if (fecha == null) return '';
    final hoy = _dia(ahora ?? DateTime.now());
    final dia = _dia(fecha);
    final diferencia = dia.difference(hoy).inDays;
    if (diferencia == 0) return 'hoy';
    if (diferencia == -1) return 'ayer';
    if (diferencia > 0) return 'el ${_fechaCorta(fecha)}';
    if (diferencia >= -6) {
      return 'hace ${-diferencia} días';
    }
    return 'el ${_fechaCorta(fecha)}';
  }

  factory ResenaPendiente.fromJson(Map<String, dynamic> json) => ResenaPendiente(
    idAgenda: (json['id_agenda'] as num).toInt(),
    idLocalServicio: (json['id_local_servicio'] as num).toInt(),
    servicioNombre:
        (json['servicio'] as String?)?.trim().isNotEmpty == true
        ? (json['servicio'] as String).trim()
        : 'el servicio',
    localNombre: (json['local'] as String?)?.trim() ?? '',
    servicioFoto: (json['servicio_foto'] as String?)?.trim(),
    categoria: (json['categoria'] as String?)?.trim(),
    atendido: json['atendido'] != null
        ? DateTime.tryParse(json['atendido'] as String)
        : null,
  );

  static DateTime _dia(DateTime f) => DateTime(f.year, f.month, f.day);

  static String _fechaCorta(DateTime f) {
    final dia = f.day.toString().padLeft(2, '0');
    final mes = f.month.toString().padLeft(2, '0');
    return '$dia/$mes/${f.year}';
  }
}

/// Reseñas contra `flow.resena` y sus RPC.
class ResenaService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _schema = 'flow';

  /// Todo lo del detalle de un servicio (resumen + lista + mi reseña).
  static Future<ResenasDeServicio> deServicio(
    int idLocalServicio, {
    int limit = 20,
    int offset = 0,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .rpc(
          'resenas_de_servicio',
          params: {
            'p_id_local_servicio': idLocalServicio,
            'p_limit': limit,
            'p_offset': offset,
          },
        );
    return ResenasDeServicio.fromJson(
      res == null ? null : Map<String, dynamic>.from(res as Map),
    );
  }

  /// Feed corto para el Home. Devuelve `[]` si el RPC no está disponible.
  static Future<List<Resena>> recientes({int limit = 5}) async {
    final res = await _supabase
        .schema(_schema)
        .rpc('resenas_recientes', params: {'p_limit': limit});
    if (res is! Map) return const [];
    final json = Map<String, dynamic>.from(res);
    if (json['ok'] != true) return const [];
    final lista = json['data'];
    if (lista is! List) return const [];
    return lista
        .whereType<Map>()
        .map((e) => Resena.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Agregado por servicio: `id_local_servicio → (total, promedio)`.
  ///
  /// Alimenta las estrellas del feed. Un servicio que no aparece **no tiene
  /// valoración**, y la tarjeta no debe inventársela.
  static Future<Map<int, ResumenResenas>> porServicio() async {
    final res = await _supabase.schema(_schema).rpc('resenas_por_servicio');
    if (res is! List) return const {};
    return {
      for (final fila in res.whereType<Map>())
        (fila['id_local_servicio'] as num).toInt(): ResumenResenas(
          total: (fila['total'] as num).toInt(),
          promedio: (fila['promedio'] as num).toDouble(),
        ),
    };
  }

  /// Reservas completadas a las que les falta la reseña, la más reciente
  /// primero.
  ///
  /// Devuelve `[]` (sin lanzar) si la migración **59** todavía no está aplicada:
  /// el cliente no debe ver un error por no poder pedir una opinión.
  static Future<List<ResenaPendiente>> pendientes({int limite = 3}) async {
    try {
      final res = await _supabase
          .schema(_schema)
          .rpc('cliente_resenas_pendientes', params: {'p_limite': limite});
      if (res is! Map) return const [];
      final json = Map<String, dynamic>.from(res);
      if (json['ok'] != true) return const [];
      final lista = json['data'];
      if (lista is! List) return const [];
      return lista
          .whereType<Map>()
          .map((e) => ResenaPendiente.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      debugPrint('[flow] ResenaService.pendientes ERROR: $e');
      return const [];
    }
  }

  /// Publica (o actualiza) la reseña de una reserva completada propia.
  static Future<void> publicar({
    required String uuidUsuario,
    required int idAgenda,
    required int puntuacion,
    String? comentario,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .rpc(
          'publicar_resena',
          params: {
            'p_uuid_usuario': uuidUsuario,
            'p_id_agenda': idAgenda,
            'p_puntuacion': puntuacion,
            if (comentario != null && comentario.trim().isNotEmpty)
              'p_comentario': comentario.trim(),
          },
        );
    final json = res as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudo publicar la reseña');
    }
  }

  static Future<void> eliminar({
    required String uuidUsuario,
    required int idResena,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .rpc(
          'eliminar_mi_resena',
          params: {'p_uuid_usuario': uuidUsuario, 'p_id_resena': idResena},
        );
    final json = res as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudo eliminar la reseña');
    }
  }
}
