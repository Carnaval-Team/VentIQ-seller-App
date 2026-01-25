import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_preferences_service.dart';

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

      await _supabase.from('app_dat_cambio_precio').insert(payload);
    } catch (e) {
      debugPrint('❌ Error registrando cambio de precio: $e');
    }
  }
}
