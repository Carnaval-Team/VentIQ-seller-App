import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/plan_servicio.dart';
import 'auth_service.dart';

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
      final res = await _supabase.schema(_schema).rpc(
        'admin_get_plan_servicios',
        params: {'p_id_local_servicio': idLocalServicio},
      );
      
      final json = res as Map<String, dynamic>;
      if (json['ok'] != true) {
        throw Exception(json['error'] ?? 'Error al obtener planes de servicio');
      }
      
      final data = json['data'] as List;
      return data.map((e) => PlanServicio.fromJson(e as Map<String, dynamic>)).toList();
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
      final res = await _supabase.schema(_schema).rpc(
        'admin_create_plan_servicio',
        params: {
          'p_id_local_servicio': idLocalServicio,
          'p_fecha': fecha?.toIso8601String().substring(0, 10),
          'p_cantidad': cantidad,
        },
      );
      
      final json = res as Map<String, dynamic>;
      if (json['ok'] != true) {
        throw Exception(json['error'] ?? 'Error al crear plan de servicio');
      }
      
      return PlanServicio.fromJson(json['data'] as Map<String, dynamic>);
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
      final res = await _supabase.schema(_schema).rpc(
        'admin_update_plan_servicio',
        params: {
          'p_id': id,
          'p_fecha': fecha?.toIso8601String().substring(0, 10),
          'p_cantidad': cantidad,
        },
      );
      
      final json = res as Map<String, dynamic>;
      if (json['ok'] != true) {
        throw Exception(json['error'] ?? 'Error al actualizar plan de servicio');
      }
      
      return PlanServicio.fromJson(json['data'] as Map<String, dynamic>);
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
      final res = await _supabase.schema(_schema).rpc(
        'admin_existe_plan_fecha',
        params: {
          'p_id_local_servicio': idLocalServicio,
          'p_fecha': fecha.toIso8601String().substring(0, 10),
          if (excludeId != null) 'p_exclude_id': excludeId,
        },
      );
      
      final json = res as Map<String, dynamic>;
      if (json['ok'] != true) {
        throw Exception(json['error'] ?? 'Error al verificar existencia de plan');
      }
      
      return json['existe'] as bool;
    } catch (e) {
      throw handleSchemaPermissionError(Exception(e.toString()));
    }
  }

  static Future<void> delete(int id) async {
    try {
      final res = await _supabase.schema(_schema).rpc(
        'admin_delete_plan_servicio',
        params: {'p_id': id},
      );
      
      final json = res as Map<String, dynamic>;
      if (json['ok'] != true) {
        throw Exception(json['error'] ?? 'Error al eliminar plan de servicio');
      }
    } catch (e) {
      throw handleSchemaPermissionError(Exception(e.toString()));
    }
  }
}
