import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/hr/hr_dashboard_data.dart';

class HRDashboardService {
  static final _supabase = Supabase.instance.client;

  /// Obtener resumen del dashboard HR
  static Future<HRDashboardSummary> getDashboardSummary({
    required int storeId,
    required DateTime fechaDesde,
    required DateTime fechaHasta,
  }) async {
    try {
      print('📊 Obteniendo resumen HR: tienda $storeId, $fechaDesde - $fechaHasta');
      final response = await _supabase.rpc(
        'fn_hr_dashboard_summary',
        params: {
          'p_id_tienda': storeId,
          'p_fecha_desde': fechaDesde.toIso8601String().split('T')[0],
          'p_fecha_hasta': fechaHasta.toIso8601String().split('T')[0],
        },
      );

      if (response['success'] == true) {
        final data = response['data'] as Map<String, dynamic>;
        print('✅ Resumen HR cargado: ${data['total_registros']} registros');
        return HRDashboardSummary.fromJson(data);
      }
      throw Exception('Error al cargar resumen HR');
    } catch (e) {
      print('❌ Error obteniendo resumen HR: $e');
      rethrow;
    }
  }

  /// Obtener top trabajadores por pago
  static Future<List<HRTopWorker>> getTopWorkersByPay({
    required int storeId,
    required DateTime fechaDesde,
    required DateTime fechaHasta,
    int limit = 10,
  }) async {
    try {
      print('🏆 Obteniendo top trabajadores: tienda $storeId');
      final response = await _supabase.rpc(
        'fn_hr_top_workers_by_pay',
        params: {
          'p_id_tienda': storeId,
          'p_fecha_desde': fechaDesde.toIso8601String().split('T')[0],
          'p_fecha_hasta': fechaHasta.toIso8601String().split('T')[0],
          'p_limit': limit,
        },
      );

      if (response['success'] == true) {
        final List<dynamic> data = response['data'] as List<dynamic>;
        print('📋 ${data.length} top trabajadores cargados');
        return data
            .map((w) => HRTopWorker.fromJson(w as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      print('❌ Error obteniendo top trabajadores: $e');
      rethrow;
    }
  }
}
