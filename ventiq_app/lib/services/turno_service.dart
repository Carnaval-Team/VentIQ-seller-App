import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_preferences_service.dart';

class TurnoService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static final UserPreferencesService _userPrefs = UserPreferencesService();

  static Future<Map<String, dynamic>?> getResumenTurnoKPI() async {
    try {
      // Get current date range (today from 00:00:00 to 23:59:59)
      final now = DateTime.now();
      final fechaDesde = DateTime(now.year, now.month, now.day, 0, 0, 0);
      final fechaHasta = DateTime(now.year, now.month, now.day, 23, 59, 59);
      
      // Get TPV and seller IDs from preferences
      final workerProfile = await _userPrefs.getWorkerProfile();
      final idTpv = workerProfile['idTpv'];
      final idSeller = await _userPrefs.getIdSeller();
      
      print('🔍 Calling fn_resumen_turno_kpi with:');
      print('  - Fecha desde: $fechaDesde');
      print('  - Fecha hasta: $fechaHasta');
      print('  - ID TPV: $idTpv');
      print('  - ID Vendedor: $idSeller');

      final response = await _supabase.rpc('fn_resumen_turno_kpi', params: {
        'p_fecha_desde': fechaDesde.toIso8601String(),
        'p_fecha_hasta': fechaHasta.toIso8601String(),
        'p_id_tpv': idTpv,
        'p_id_vendedor': idSeller,
      });

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
      
      final response = await _supabase.rpc('fn_cerrar_turno_tpv', params: {
        'p_efectivo_real': efectivoReal,
        'p_id_tpv': idTpv,
        'p_observaciones': observaciones,
        'p_productos': productos,
        'p_usuario': userUuid,
      });
      
      print('✅ fn_cerrar_turno_tpv response: $response');
      return response == true;
      
    } catch (e) {
      print('❌ Error in cerrarTurno: $e');
      return false;
    }
  }
}
