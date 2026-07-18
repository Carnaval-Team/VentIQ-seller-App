import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/recurso.dart';

/// CRUD de recursos / tramos / turnos de un local_servicio.
/// Envuelve las RPCs admin flow.admin_*_recurso / _tramo / _turno
/// (ver docs/flow_schema/rpc admin/25_admin_recursos.sql).
class RecursoService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _schema = 'flow';

  /// Lista los recursos del local_servicio con sus tramos y turnos anidados.
  static Future<List<Recurso>> listar({
    required String uuidUsuario,
    required int idLocalServicio,
  }) async {
    final res = await _supabase.schema(_schema).rpc(
      'admin_listar_recursos',
      params: {
        'p_uuid_usuario': uuidUsuario,
        'p_id_local_servicio': idLocalServicio,
      },
    );
    final json = res as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudieron listar los recursos');
    }
    final data = (json['data'] as List?) ?? const [];
    return data
        .map((e) => Recurso.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Recurso ──────────────────────────────────────────────────────────────

  /// Crea (id == null) o actualiza un recurso. Devuelve su id.
  static Future<int> guardarRecurso({
    required String uuidUsuario,
    required int idLocalServicio,
    required String nombre,
    int capacidad = 1,
    int orden = 0,
    bool activo = true,
    int? id,
  }) async {
    final res = await _supabase.schema(_schema).rpc(
      'admin_guardar_recurso',
      params: {
        'p_uuid_usuario': uuidUsuario,
        'p_id_local_servicio': idLocalServicio,
        'p_nombre': nombre,
        'p_capacidad': capacidad,
        'p_orden': orden,
        'p_activo': activo,
        'p_id': id,
      },
    );
    final json = res as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudo guardar el recurso');
    }
    return (json['id'] as num).toInt();
  }

  static Future<void> eliminarRecurso({
    required String uuidUsuario,
    required int id,
  }) async {
    final res = await _supabase.schema(_schema).rpc(
      'admin_eliminar_recurso',
      params: {'p_uuid_usuario': uuidUsuario, 'p_id': id},
    );
    final json = res as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudo eliminar el recurso');
    }
  }

  // ── Tramo ────────────────────────────────────────────────────────────────

  /// Crea (id == null) o actualiza un tramo. [capacidad] null = hereda recurso.
  static Future<int> guardarTramo({
    required String uuidUsuario,
    required int idRecurso,
    required String nombre,
    int? capacidad,
    int orden = 0,
    bool activo = true,
    int? id,
  }) async {
    final res = await _supabase.schema(_schema).rpc(
      'admin_guardar_tramo',
      params: {
        'p_uuid_usuario': uuidUsuario,
        'p_id_recurso': idRecurso,
        'p_nombre': nombre,
        'p_capacidad': capacidad,
        'p_orden': orden,
        'p_activo': activo,
        'p_id': id,
      },
    );
    final json = res as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudo guardar el tramo');
    }
    return (json['id'] as num).toInt();
  }

  static Future<void> eliminarTramo({
    required String uuidUsuario,
    required int id,
  }) async {
    final res = await _supabase.schema(_schema).rpc(
      'admin_eliminar_tramo',
      params: {'p_uuid_usuario': uuidUsuario, 'p_id': id},
    );
    final json = res as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudo eliminar el tramo');
    }
  }

  // ── Turno ────────────────────────────────────────────────────────────────

  /// Crea (id == null) o actualiza un turno. [tramosIds] reemplaza el set actual
  /// de tramos que el turno consume (deben pertenecer al mismo recurso).
  static Future<int> guardarTurno({
    required String uuidUsuario,
    required int idRecurso,
    required String nombre,
    required List<int> tramosIds,
    int orden = 0,
    bool activo = true,
    int? id,
  }) async {
    final res = await _supabase.schema(_schema).rpc(
      'admin_guardar_turno',
      params: {
        'p_uuid_usuario': uuidUsuario,
        'p_id_recurso': idRecurso,
        'p_nombre': nombre,
        'p_tramos': tramosIds,
        'p_orden': orden,
        'p_activo': activo,
        'p_id': id,
      },
    );
    final json = res as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudo guardar el turno');
    }
    return (json['id'] as num).toInt();
  }

  static Future<void> eliminarTurno({
    required String uuidUsuario,
    required int id,
  }) async {
    final res = await _supabase.schema(_schema).rpc(
      'admin_eliminar_turno',
      params: {'p_uuid_usuario': uuidUsuario, 'p_id': id},
    );
    final json = res as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudo eliminar el turno');
    }
  }
}
