import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/plan_servicio.dart';

class PlanServicioService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _schema = 'flow';

  static Future<List<PlanServicio>> getByLocalServicio(
      int idLocalServicio) async {
    final res = await _supabase
        .schema(_schema)
        .from('plan_servicios')
        .select()
        .eq('id_local_servicio', idLocalServicio)
        .order('fecha');
    return (res as List).map((e) => PlanServicio.fromJson(e)).toList();
  }

  static Future<PlanServicio> create({
    required int idLocalServicio,
    DateTime? fecha,
    required int cantidad,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .from('plan_servicios')
        .insert({
          'id_local_servicio': idLocalServicio,
          'fecha': fecha?.toIso8601String(),
          'cantidad': cantidad,
          'agendados': 0,
        })
        .select()
        .single();
    return PlanServicio.fromJson(res);
  }

  static Future<PlanServicio> update({
    required int id,
    DateTime? fecha,
    required int cantidad,
  }) async {
    final res = await _supabase
        .schema(_schema)
        .from('plan_servicios')
        .update({
          'fecha': fecha?.toIso8601String(),
          'cantidad': cantidad,
        })
        .eq('id', id)
        .select()
        .single();
    return PlanServicio.fromJson(res);
  }

  /// Devuelve true si ya existe un plan para ese local-servicio en esa fecha.
  /// Compara solo la parte de fecha (sin hora).
  static Future<bool> existePlanParaFecha({
    required int idLocalServicio,
    required DateTime fecha,
    int? excludeId,
  }) async {
    final desde = DateTime(fecha.year, fecha.month, fecha.day);
    final hasta = DateTime(fecha.year, fecha.month, fecha.day, 23, 59, 59);
    var query = _supabase
        .schema(_schema)
        .from('plan_servicios')
        .select('id')
        .eq('id_local_servicio', idLocalServicio)
        .gte('fecha', desde.toIso8601String())
        .lte('fecha', hasta.toIso8601String());
    final res = await query;
    final list = res as List;
    if (excludeId != null) {
      return list.any((e) => (e['id'] as num).toInt() != excludeId);
    }
    return list.isNotEmpty;
  }

  static Future<void> delete(int id) async {
    await _supabase
        .schema(_schema)
        .from('plan_servicios')
        .delete()
        .eq('id', id);
  }
}
