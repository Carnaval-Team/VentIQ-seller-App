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

  static Future<void> delete(int id) async {
    await _supabase
        .schema(_schema)
        .from('plan_servicios')
        .delete()
        .eq('id', id);
  }
}
