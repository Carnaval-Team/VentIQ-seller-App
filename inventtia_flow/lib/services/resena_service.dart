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

  static const ResumenResenas vacio = ResumenResenas(
    total: 0,
    promedio: 0,
  );

  factory ResumenResenas.fromJson(Map<String, dynamic>? json) {
    if (json == null) return vacio;
    final estrellas = json['estrellas'] as Map<String, dynamic>? ?? const {};
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

    final agenda = json['agenda_resenable'] as Map<String, dynamic>?;
    final mias = json['mi_resena'] as Map<String, dynamic>?;
    final crudas = json['items'] as List? ?? const [];

    return ResenasDeServicio(
      resumen: ResumenResenas.fromJson(
        json['resumen'] as Map<String, dynamic>?,
      ),
      items: crudas
          .map((e) => Resena.fromJson(Map<String, dynamic>.from(e as Map)))
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
    if (res == null) return const [];
    final json = res as Map<String, dynamic>;
    if (json['ok'] != true) return const [];
    final lista = json['data'] as List? ?? const [];
    return lista
        .map((e) => Resena.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Agregado por servicio: `id_local_servicio → (total, promedio)`.
  ///
  /// Alimenta las estrellas del feed. Un servicio que no aparece **no tiene
  /// valoración**, y la tarjeta no debe inventársela.
  static Future<Map<int, ResumenResenas>> porServicio() async {
    final res = await _supabase
        .schema(_schema)
        .rpc('resenas_por_servicio');
    final filas = res as List? ?? const [];
    return {
      for (final f in filas)
        (f['id_local_servicio'] as num).toInt(): ResumenResenas(
          total: (f['total'] as num).toInt(),
          promedio: (f['promedio'] as num).toDouble(),
        ),
    };
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