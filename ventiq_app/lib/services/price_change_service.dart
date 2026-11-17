import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/uuid_generator.dart';
import 'user_preferences_service.dart';

bool _rpcAusente(Object error, String functionName) {
  final text = error.toString().toLowerCase();
  if (text.contains('42501') ||
      text.contains('insufficient_privilege') ||
      text.contains('permission denied') ||
      text.contains('acceso denegado')) {
    return false;
  }
  final fn = functionName.toLowerCase();
  return text.contains('pgrst202') ||
      text.contains('could not find the function') ||
      text.contains('schema cache') ||
      (text.contains('does not exist') && text.contains(fn));
}

class PriceChangeService {
  static final PriceChangeService _instance = PriceChangeService._internal();

  factory PriceChangeService() => _instance;

  PriceChangeService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final UserPreferencesService _userPreferencesService =
      UserPreferencesService();

  Future<void> logPriceChange({
    required int productId,
    int? variantId,
    required double originalPrice,
    required double resultPrice,
    required String tipo,
  }) async {
    if (originalPrice == resultPrice) return;

    try {
      final userUuid = await _userPreferencesService.getUserId();
      final idTpv = await _userPreferencesService.getIdTpv();

      if (userUuid == null || idTpv == null) {
        debugPrint(
          '⚠️ No se pudo registrar cambio de precio (uuid/id_tpv faltante).',
        );
        return;
      }

      final montoDescontado = originalPrice - resultPrice;

      final payload = {
        'id_producto': productId,
        'id_variante': variantId,
        'id_usuario': userUuid,
        'id_tpv': idTpv,
        'precio_anterior': originalPrice,
        'precio_nuevo': resultPrice,
        'motivo': tipo,
        'monto_descontado': montoDescontado,
      }..removeWhere((key, value) => value == null);

      try {
        await _supabase.rpc(
          'fn_m01_registrar_cambio_precio',
          params: {
            'p_client_uuid': UuidGenerator.v4(),
            'p_id_producto': productId,
            'p_id_variante': variantId,
            'p_precio_anterior': originalPrice,
            'p_precio_nuevo': resultPrice,
            'p_motivo': tipo,
            'p_id_tpv': idTpv,
          },
        );
      } catch (e) {
        if (!_rpcAusente(e, 'fn_m01_registrar_cambio_precio')) rethrow;
        await _supabase.from('app_dat_cambio_precio').insert(payload);
      }
    } catch (e) {
      debugPrint('❌ Error registrando cambio de precio: $e');
    }
  }
}
