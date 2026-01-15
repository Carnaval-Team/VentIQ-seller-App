import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_preferences_service.dart';

class CurrencyService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  static const int _cupId = 1;
  static const int _usdId = 2;

  static Future<Map<String, dynamic>?> _getUsdToCupStoreRateConfig(
    int storeId,
  ) async {
    try {
      final response =
          await _supabase
              .from('tasa_cambio_extraoficial')
              .select('valor_cambio, usar_precio_toque, created_at')
              .eq('id_tienda', storeId)
              .eq('activo', true)
              .eq('id_moneda_origen', _usdId)
              .eq('id_moneda_destino', _cupId)
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle();

      if (response == null) return null;
      return Map<String, dynamic>.from(response);
    } catch (e) {
      print('❌ Error fetching custom USD→CUP config: $e');
      return null;
    }
  }

  /// Gets current exchange rates from database
  static Future<List<Map<String, dynamic>>>
  getCurrentRatesFromDatabase() async {
    try {
      final response = await _supabase
          .from('tasas_conversion')
          .select('moneda_origen, moneda_destino, tasa, fecha_actualizacion')
          .order('fecha_actualizacion', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error fetching rates from database: $e');
      return [];
    }
  }

  /// Gets USD rate specifically
  static Future<double> getUsdRate() async {
    final userPreferencesService = UserPreferencesService();

    try {
      try {
        final isOfflineModeEnabled =
            await userPreferencesService.isOfflineModeEnabled();
        if (isOfflineModeEnabled) {
          final cached = await userPreferencesService.getCambioCupUsd();
          print(
            '🔌 Modo offline activado - Usando tipo de cambio desde cache: $cached',
          );
          return cached;
        }
      } catch (e) {
        print('❌ Error verificando modo offline: $e');
      }

      try {
        final storeId = await userPreferencesService.getIdTienda();
        if (storeId != null) {
          final config = await _getUsdToCupStoreRateConfig(storeId);
          if (config != null && config['usar_precio_toque'] != true) {
            final valorCambio = (config['valor_cambio'] as num?)?.toDouble();
            if (valorCambio != null && valorCambio > 0) {
              await userPreferencesService.saveCambioCupUsd(valorCambio);
              print(
                '💱 Tipo de cambio USD→CUP custom aplicado para tienda $storeId: $valorCambio',
              );
              return valorCambio;
            }
          }
        }
      } catch (e) {
        print('❌ Error verificando tasa custom por tienda: $e');
      }

      final rates = await getCurrentRatesFromDatabase();

      // Find USD rate where moneda_origen = 'USD'
      final usdRateData = rates.firstWhere(
        (rate) =>
            rate['moneda_origen'] == 'USD' &&
            (rate['moneda_destino'] == 'CUP' || rate['moneda_destino'] == null),
        orElse: () => <String, dynamic>{},
      );

      double usdRate;
      if (usdRateData.isNotEmpty) {
        usdRate = (usdRateData['tasa'] as num?)?.toDouble() ?? 420.0;
      } else {
        print('⚠️ No USD rate found in database, using cached/default');
        usdRate = await userPreferencesService.getCambioCupUsd();
      }

      // Guardar el tipo de cambio en el store
      try {
        await userPreferencesService.saveCambioCupUsd(usdRate);
        print('💱 Tipo de cambio USD guardado en store: $usdRate');
      } catch (e) {
        print('❌ Error guardando tipo de cambio en store: $e');
      }

      return usdRate;
    } catch (e) {
      print('❌ Error loading USD rate: $e');
      return await userPreferencesService.getCambioCupUsd();
    }
  }
}
