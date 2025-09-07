import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_preferences_service.dart';
import '../models/expense.dart';

class TurnoService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static final UserPreferencesService _userPrefs = UserPreferencesService();

  static Future<Map<String, dynamic>?> getResumenTurnoKPI() async {
    try {
      // Get TPV and seller IDs from preferences
      final workerProfile = await _userPrefs.getWorkerProfile();
      final idTpv = workerProfile['idTpv'];
      final idSeller = await _userPrefs.getIdSeller();

      print('🔍 Calling fn_resumen_turno_kpi with:');
      print('  - ID TPV: $idTpv');
      print('  - ID Vendedor: $idSeller');

      final response = await _supabase.rpc(
        'fn_resumen_turno_kpi',
        params: {
          'p_id_tpv': idTpv,
          'p_id_vendedor': idSeller},
      );

      print('📊 RPC Response: $response');

      if (response != null && response is List && response.isNotEmpty) {
        return response.first as Map<String, dynamic>;
      }

      return null;
    } catch (e) {
      print('❌ Error getting turno KPI: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getResumenTurnoPorId(int idTurno) async {
    try {
      print('🔍 Calling fn_resumen_turno_por_id with ID: $idTurno');

      final response = await _supabase.rpc(
        'fn_resumen_turno_por_id',
        params: {'p_turno_id': idTurno},
      );

      print('📊 RPC Response: $response');

      if (response != null && response is List && response.isNotEmpty) {
        return response.first as Map<String, dynamic>;
      }

      return null;
    } catch (e) {
      print('❌ Error getting turno summary by ID: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getTurnoAbierto() async {
    try {
      final workerProfile = await _userPrefs.getWorkerProfile();
      final idTpv = workerProfile['idTpv'];

      if (idTpv == null) {
        print('❌ Missing TPV ID');
        return null;
      }

      print('🔍 Searching for open shift with TPV ID: $idTpv');

      final response = await _supabase
          .from('app_dat_caja_turno')
          .select('*')
          .eq('id_tpv', idTpv)
          .eq('estado', 1)
          .order('fecha_apertura', ascending: false)
          .limit(1);

      print('📊 Open shift query response: $response');

      if (response.isNotEmpty) {
        final turno = response.first as Map<String, dynamic>;
        print('✅ Found open shift: ${turno['id']}');
        return turno;
      }

      print('⚠️ No open shift found');
      return null;
    } catch (e) {
      print('❌ Error getting open shift: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>> registrarEgresoParcial({
    required int idTurno,
    required double montoEntrega,
    required String motivoEntrega,
    required String nombreAutoriza,
    required String nombreRecibe,
  }) async {
    try {
      print('🔄 Calling registrar_egreso_parcial with:');
      print('  - ID Turno: $idTurno');
      print('  - Monto: $montoEntrega');
      print('  - Motivo: $motivoEntrega');
      print('  - Autoriza: $nombreAutoriza');
      print('  - Recibe: $nombreRecibe');

      final response = await _supabase.rpc(
        'registrar_egreso_parcial',
        params: {
          'p_id_turno': idTurno,
          'p_monto_entrega': montoEntrega,
          'p_motivo_entrega': motivoEntrega,
          'p_nombre_autoriza': nombreAutoriza,
          'p_nombre_recibe': nombreRecibe,
        },
      );

      print('✅ registrar_egreso_parcial response: $response');

      if (response != null && response is Map<String, dynamic>) {
        return response;
      }

      return {
        'success': false,
        'message': 'Respuesta inválida del servidor',
        'egreso_id': null,
      };
    } catch (e) {
      print('❌ Error in registrarEgresoParcial: $e');
      return {
        'success': false,
        'message': 'Error al registrar el egreso: $e',
        'egreso_id': null,
      };
    }
  }

  static Future<bool> cerrarTurno({
    required double efectivoReal,
    required List<Map<String, dynamic>> productos,
    String? observaciones,
  }) async {
    try {
      // Get user UUID and TPV ID
      final userUuid = await _userPrefs.getUserId();
      final workerProfile = await _userPrefs.getWorkerProfile();
      final idTpv = workerProfile['idTpv'];

      if (userUuid == null || idTpv == null) {
        print('❌ Missing user UUID or TPV ID');
        return false;
      }

      print('🔄 Calling fn_cerrar_turno_tpv with:');
      print('  - Efectivo real: $efectivoReal');
      print('  - TPV ID: $idTpv');
      print('  - Usuario: $userUuid');
      print('  - Productos: ${productos.length} items');

      final response = await _supabase.rpc(
        'fn_cerrar_turno_tpv',
        params: {
          'p_efectivo_real': efectivoReal,
          'p_id_tpv': idTpv,
          'p_observaciones': observaciones,
          'p_productos': productos,
          'p_usuario': userUuid,
        },
      );

      print('✅ fn_cerrar_turno_tpv response: $response');
      return response == true;
    } catch (e) {
      print('❌ Error in cerrarTurno: $e');
      return false;
    }
  }

  static Future<List<Expense>> getEgresosPorTurno(int idTurno) async {
    try {
      print('🔍 Calling egresos_por_turno_especifico with ID: $idTurno');

      final response = await _supabase.rpc(
        'egresos_por_turno',
        params: {'p_id_turno': idTurno},
      );

      print('📊 Expenses RPC Response: $response');

      if (response != null && response is List) {
        return response
            .map<Expense>(
              (expense) => Expense.fromJson(expense as Map<String, dynamic>),
            )
            .toList();
      }

      return [];
    } catch (e) {
      print('❌ Error getting expenses for shift: $e');
      return [];
    }
  }

  static Future<List<Expense>> getEgresosForCurrentShift() async {
    try {
      // Get current open shift
      final turnoAbierto = await getTurnoAbierto();

      if (turnoAbierto == null) {
        print('⚠️ No open shift found for expenses');
        return [];
      }

      final idTurno = turnoAbierto['id'] as int;
      return await getEgresosPorTurno(idTurno);
    } catch (e) {
      print('❌ Error getting expenses for current shift: $e');
      return [];
    }
  }
}
