import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/plan_servicio.dart';

class PlanServicioService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _schema = 'flow';

  /// Handle schema permission errors with user-friendly messages
  static Exception handleSchemaPermissionError(Exception e) {
    if (e.toString().contains('permission denied') || e.toString().contains('42501')) {
      return Exception(
        'ERROR DE PERMISOS DE BASE DE DATOS\n\n'
        'No se puede acceder al esquema "flow" de la base de datos.\n\n'
        'SOLUCIÓN:\n'
        '1. Ve al panel de Supabase > SQL Editor\n'
        '2. Ejecuta los siguientes comandos:\n\n'
        'GRANT USAGE ON SCHEMA flow TO authenticated;\n'
        'GRANT USAGE ON SCHEMA flow TO anon;\n'
        'GRANT ALL ON ALL TABLES IN SCHEMA flow TO authenticated;\n'
        'GRANT ALL ON ALL TABLES IN SCHEMA flow TO anon;\n'
        'GRANT ALL ON ALL SEQUENCES IN SCHEMA flow TO authenticated;\n'
        'GRANT ALL ON ALL SEQUENCES IN SCHEMA flow TO anon;\n\n'
        'Error original: ${e.toString()}'
      );
    }
    return e;
  }

  static Future<List<PlanServicio>> getByLocalServicio(
      int idLocalServicio) async {
    try {
      final res = await _supabase
          .schema(_schema)
          .from('plan_servicios')
          .select()
          .eq('id_local_servicio', idLocalServicio)
          .order('fecha');
      return (res as List).map((e) => PlanServicio.fromJson(e)).toList();
    } catch (e) {
      throw handleSchemaPermissionError(Exception(e.toString()));
    }
  }

  static Future<PlanServicio> create({
    required int idLocalServicio,
    DateTime? fecha,
    required int cantidad,
  }) async {
    try {
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
    } catch (e) {
      throw handleSchemaPermissionError(Exception(e.toString()));
    }
  }

  static Future<PlanServicio> update({
    required int id,
    DateTime? fecha,
    required int cantidad,
  }) async {
    try {
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
    } catch (e) {
      throw handleSchemaPermissionError(Exception(e.toString()));
    }
  }

  /// Devuelve true si ya existe un plan para ese local-servicio en esa fecha.
  /// Compara solo la parte de fecha (sin hora).
  static Future<bool> existePlanParaFecha({
    required int idLocalServicio,
    required DateTime fecha,
    int? excludeId,
  }) async {
    try {
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
    } catch (e) {
      throw handleSchemaPermissionError(Exception(e.toString()));
    }
  }

  static Future<void> delete(int id) async {
    try {
      await _supabase
          .schema(_schema)
          .from('plan_servicios')
          .delete()
          .eq('id', id);
    } catch (e) {
      throw handleSchemaPermissionError(Exception(e.toString()));
    }
  }
}
