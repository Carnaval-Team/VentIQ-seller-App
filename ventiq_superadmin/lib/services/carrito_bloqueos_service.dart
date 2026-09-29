import 'package:supabase_flutter/supabase_flutter.dart';

/// Servicio de soporte para el control anti-abuso del carrito de Carnaval.
///
/// Lee la vista `carnavalapp.v_carrito_abuso_soporte` (una fila por
/// usuario+producto con métricas de eliminaciones y estado de bloqueo) y
/// permite desbloquear manualmente vía `carnavalapp.fn_desbloquear_carrito`.
class CarritoBloqueosService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Trae todas las incidencias detectadas por el anti-abuso del carrito.
  ///
  /// Cada registro incluye datos del usuario, del producto, cuántas veces
  /// eliminó el producto, si incidió (>2), si es reincidente y el estado de
  /// bloqueo actual (`sin_bloqueo`, `bloqueado_temporal`,
  /// `bloqueado_permanente`, `bloqueo_expirado`).
  static Future<List<Map<String, dynamic>>> getIncidencias() async {
    try {
      final response = await _supabase
          .schema('carnavalapp')
          .from('v_carrito_abuso_soporte')
          .select()
          .order('ultima_eliminacion', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error getIncidencias: $e');
      return [];
    }
  }

  /// Desbloquea un producto para un usuario. Elimina el bloqueo y (por defecto)
  /// limpia las eliminaciones recientes para que el patrón no se re-dispare.
  static Future<Map<String, dynamic>> desbloquear({
    required int userId,
    required int idProducto,
    bool limpiarHistorial = true,
  }) async {
    try {
      final response = await _supabase.schema('carnavalapp').rpc(
        'fn_desbloquear_carrito',
        params: {
          'p_user_id': userId,
          'p_id_producto': idProducto,
          'p_limpiar_historial': limpiarHistorial,
        },
      );
      return Map<String, dynamic>.from(response as Map);
    } catch (e) {
      print('❌ Error desbloquear: $e');
      return {'desbloqueado': false, 'error': e.toString()};
    }
  }
}
