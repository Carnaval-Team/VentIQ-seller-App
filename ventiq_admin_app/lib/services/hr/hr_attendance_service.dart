import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/hr/hr_attendance.dart';

class HRAttendanceService {
  static final _supabase = Supabase.instance.client;

  /// Verificar si el usuario actual es HR
  static Future<bool> checkIsHRUser(String userUuid, int storeId) async {
    try {
      print('🔍 Verificando si usuario es HR: $userUuid en tienda $storeId');
      final response = await _supabase.rpc(
        'fn_check_is_hr_user',
        params: {
          'p_user_uuid': userUuid,
          'p_id_tienda': storeId,
        },
      );

      if (response['success'] == true) {
        final isHR = response['is_hr'] as bool? ?? false;
        print('${isHR ? "✅" : "❌"} Usuario HR: $isHR');
        return isHR;
      }
      return false;
    } catch (e) {
      print('❌ Error verificando usuario HR: $e');
      return false;
    }
  }

  /// Obtener trabajadores disponibles para fichar entrada
  static Future<List<HRAttendance>> getWorkersForCheckin(int storeId) async {
    try {
      print('🔍 Obteniendo trabajadores para check-in, tienda: $storeId');
      final response = await _supabase.rpc(
        'fn_hr_workers_for_checkin',
        params: {'p_id_tienda': storeId},
      );

      if (response['success'] == true) {
        final List<dynamic> data = response['data'] as List<dynamic>;
        print('📋 ${data.length} trabajadores disponibles para check-in');
        return data
            .map((w) => HRAttendance.fromJson(w as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      print('❌ Error obteniendo trabajadores para check-in: $e');
      throw Exception('Error al cargar trabajadores: $e');
    }
  }

  /// Obtener trabajadores que estan trabajando actualmente
  static Future<List<HRAttendance>> getWorkersCurrentlyWorking(int storeId) async {
    try {
      print('🔍 Obteniendo trabajadores trabajando, tienda: $storeId');
      final response = await _supabase.rpc(
        'fn_hr_workers_currently_working',
        params: {'p_id_tienda': storeId},
      );

      if (response['success'] == true) {
        final List<dynamic> data = response['data'] as List<dynamic>;
        print('📋 ${data.length} trabajadores trabajando actualmente');
        return data
            .map((w) => HRAttendance.fromJson(w as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      print('❌ Error obteniendo trabajadores trabajando: $e');
      throw Exception('Error al cargar trabajadores: $e');
    }
  }

  /// Registrar entrada de un trabajador
  static Future<bool> registerCheckin({
    required int storeId,
    required int workerId,
    required DateTime horaEntrada,
    required String registradoPor,
  }) async {
    try {
      print('📝 Registrando entrada: trabajador $workerId en tienda $storeId');
      final response = await _supabase.rpc(
        'fn_hr_register_checkin',
        params: {
          'p_id_tienda': storeId,
          'p_id_trabajador': workerId,
          'p_hora_entrada': horaEntrada.toIso8601String(),
          'p_registrado_por': registradoPor,
        },
      );

      if (response['success'] == true) {
        print('✅ Entrada registrada: ${response['message']}');
        return true;
      } else {
        print('❌ Error: ${response['message']}');
        throw Exception(response['message'] ?? 'Error al registrar entrada');
      }
    } catch (e) {
      print('❌ Error registrando entrada: $e');
      rethrow;
    }
  }

  /// Obtener historial de asistencia por período (todos los registros, abiertos y cerrados)
  static Future<List<HRAttendance>> getAttendanceHistory(
    int storeId, {
    required DateTime fechaDesde,
    required DateTime fechaHasta,
  }) async {
    try {
      print('📋 Obteniendo historial de asistencia, tienda: $storeId');
      final response = await _supabase.rpc(
        'fn_hr_attendance_history',
        params: {
          'p_id_tienda': storeId,
          'p_fecha_desde': fechaDesde.toIso8601String().split('T')[0],
          'p_fecha_hasta': fechaHasta.toIso8601String().split('T')[0],
        },
      );

      if (response['success'] == true) {
        final List<dynamic> data = response['data'] as List<dynamic>;
        print('📋 ${data.length} registros en historial');
        return data
            .map((w) => HRAttendance.fromJson(w as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      print('❌ Error obteniendo historial: $e');
      throw Exception('Error al cargar historial: $e');
    }
  }

  /// Eliminar un día de trabajo (registro de asistencia)
  static Future<bool> deleteAttendance({
    required int asistenciaId,
    required String eliminadoPor,
    required int storeId,
  }) async {
    try {
      print('🗑️ Eliminando registro de asistencia id=$asistenciaId');
      final response = await _supabase.rpc(
        'fn_hr_delete_attendance',
        params: {
          'p_asistencia_id': asistenciaId,
          'p_eliminado_por': eliminadoPor,
          'p_id_tienda': storeId,
        },
      );

      if (response['success'] == true) {
        print('✅ Registro eliminado: ${response['message']}');
        return true;
      } else {
        print('❌ Error: ${response['message']}');
        throw Exception(response['message'] ?? 'Error al eliminar registro');
      }
    } catch (e) {
      print('❌ Error eliminando registro de asistencia: $e');
      rethrow;
    }
  }

  /// Firmar salida en lote
  static Future<int> batchCheckout({
    required List<int> asistenciaIds,
    required DateTime horaSalida,
    required List<bool> aplicaPago,
    required String cerradoPor,
  }) async {
    try {
      print('📝 Firmando salida en lote: ${asistenciaIds.length} registros');
      final response = await _supabase.rpc(
        'fn_hr_batch_checkout',
        params: {
          'p_asistencia_ids': asistenciaIds,
          'p_hora_salida': horaSalida.toIso8601String(),
          'p_aplica_pago': aplicaPago,
          'p_cerrado_por': cerradoPor,
        },
      );

      if (response['success'] == true) {
        final count = response['count'] as int? ?? 0;
        print('✅ ${response['message']}');
        return count;
      } else {
        throw Exception(response['message'] ?? 'Error al firmar salidas');
      }
    } catch (e) {
      print('❌ Error firmando salida en lote: $e');
      rethrow;
    }
  }
}
