import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/plan_config.dart';
import '../models/plan_dia.dart';

/// Configuración recurrente de planificación (flow.plan_config) y generación
/// de los plan_servicios de un mes en lote.
class PlanConfigService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _schema = 'flow';

  /// Devuelve la config guardada para el local_servicio, o null si no hay.
  static Future<PlanConfig?> obtenerConfig({
    required String uuidUsuario,
    required int idLocalServicio,
  }) async {
    final res = await _supabase.schema(_schema).rpc(
      'admin_obtener_config_plan',
      params: {
        'p_uuid_usuario': uuidUsuario,
        'p_id_local_servicio': idLocalServicio,
      },
    );
    if (res == null) return null;
    return PlanConfig.fromJson(res as Map<String, dynamic>);
  }

  /// Guarda (upsert) la config recurrente. Devuelve la config persistida.
  static Future<void> guardarConfig({
    required String uuidUsuario,
    required int idLocalServicio,
    required PlanConfig config,
  }) async {
    final res = await _supabase.schema(_schema).rpc(
      'admin_guardar_config_plan',
      params: {
        'p_uuid_usuario': uuidUsuario,
        'p_id_local_servicio': idLocalServicio,
        'p_config': config.toConfigJson(),
        'p_activo': config.activo,
      },
    );
    final json = res as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudo guardar la configuración');
    }
  }

  /// Genera los plan_servicios del mes a partir de la config guardada.
  /// Devuelve el resumen { creados, actualizados, omitidos, dias_sin_cupo }.
  static Future<({int creados, int actualizados, int diasSinCupo})>
      generarPlanMensual({
    required String uuidUsuario,
    required int idLocalServicio,
    required int anio,
    required int mes,
  }) async {
    final res = await _supabase.schema(_schema).rpc(
      'admin_generar_plan_mensual',
      params: {
        'p_uuid_usuario': uuidUsuario,
        'p_id_local_servicio': idLocalServicio,
        'p_anio': anio,
        'p_mes': mes,
      },
    );
    final json = res as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudieron generar los planes');
    }
    return (
      creados: (json['creados'] as num?)?.toInt() ?? 0,
      actualizados: (json['actualizados'] as num?)?.toInt() ?? 0,
      diasSinCupo: (json['dias_sin_cupo'] as num?)?.toInt() ?? 0,
    );
  }

  /// Planifica UN día concreto.
  ///  • Servicios CON recursos: [capsPorRecurso] = { id_recurso: cantidad }.
  ///  • Servicios SIN recursos: usa [cantidad].
  static Future<void> planificarDia({
    required String uuidUsuario,
    required int idLocalServicio,
    required DateTime fecha,
    Map<int, int>? capsPorRecurso,
    int? cantidad,
  }) async {
    final res = await _supabase.schema(_schema).rpc(
      'admin_planificar_dia',
      params: {
        'p_uuid_usuario': uuidUsuario,
        'p_id_local_servicio': idLocalServicio,
        'p_fecha': fecha.toIso8601String().substring(0, 10),
        if (capsPorRecurso != null)
          'p_caps': {
            for (final e in capsPorRecurso.entries) e.key.toString(): e.value,
          },
        if (cantidad != null) 'p_cantidad': cantidad,
      },
    );
    final json = res as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudo planificar el día');
    }
  }

  /// Resumen de capacidad por día para pintar el calendario del admin,
  /// unificado para servicios con y sin recursos. Devuelve la lista de días
  /// (cada uno con totales y, si aplica, detalle por recurso).
  static Future<List<PlanDia>> getPlanDias({
    required String uuidUsuario,
    required int idLocalServicio,
    DateTime? desde,
    DateTime? hasta,
  }) async {
    final res = await _supabase.schema(_schema).rpc(
      'admin_get_plan_dias',
      params: {
        'p_uuid_usuario': uuidUsuario,
        'p_id_local_servicio': idLocalServicio,
        if (desde != null) 'p_desde': desde.toIso8601String().substring(0, 10),
        if (hasta != null) 'p_hasta': hasta.toIso8601String().substring(0, 10),
      },
    );
    final json = res as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'No se pudo obtener la planificación');
    }
    final dias = (json['dias'] as List?) ?? const [];
    return dias
        .map((e) => PlanDia.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
