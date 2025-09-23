import 'package:supabase_flutter/supabase_flutter.dart';
import 'currency_service.dart'; // Importar el servicio existente

/// Servicio para mostrar información de monedas en la UI
/// Extiende la funcionalidad del CurrencyService existente sin modificarlo
class CurrencyDisplayService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Obtiene todas las monedas activas para mostrar en dropdowns
  static Future<List<Map<String, dynamic>>>
  getActiveCurrenciesForDisplay() async {
    try {
      final response = await _supabase
          .from('monedas')
          .select('codigo, nombre, simbolo')
          .eq('activo', true)
          .order('codigo');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error obteniendo monedas para display: $e');
      // Fallback con monedas básicas
      return [
        {'codigo': 'USD', 'nombre': 'Dólar Estadounidense', 'simbolo': '\$'},
        {'codigo': 'CUP', 'nombre': 'Peso Cubano', 'simbolo': '\$'},
        {'codigo': 'EUR', 'nombre': 'Euro', 'simbolo': '€'},
      ];
    }
  }

  /// Obtiene la tasa de cambio más reciente entre dos monedas específicas
  static Future<double> getExchangeRateForDisplay(
    String fromCurrency,
    String toCurrency,
  ) async {
    try {
      if (fromCurrency == toCurrency) return 1.0;

      // Usar el método existente del CurrencyService
      final rates = await CurrencyService.getCurrentRatesFromDatabase();

      // Buscar tasa directa
      for (final rate in rates) {
        if (rate['moneda_origen'] == fromCurrency &&
            rate['moneda_destino'] == toCurrency) {
          return (rate['tasa'] as num).toDouble();
        }
      }

      // Buscar tasa inversa
      for (final rate in rates) {
        if (rate['moneda_origen'] == toCurrency &&
            rate['moneda_destino'] == fromCurrency) {
          final inverseTasa = (rate['tasa'] as num).toDouble();
          return inverseTasa > 0 ? 1.0 / inverseTasa : 1.0;
        }
      }

      return 1.0; // Sin conversión disponible
    } catch (e) {
      print('❌ Error obteniendo tasa de cambio para display: $e');
      return 1.0;
    }
  }

  /// Convierte un monto de una moneda a otra para mostrar en UI
  static Future<double> convertAmountForDisplay(
    double amount,
    String fromCurrency,
    String toCurrency,
  ) async {
    final rate = await getExchangeRateForDisplay(fromCurrency, toCurrency);
    return amount * rate;
  }

  /// Obtiene información completa de tasa de cambio con fecha para mostrar
  static Future<Map<String, dynamic>?> getExchangeRateInfoForDisplay(
    String fromCurrency,
    String toCurrency,
  ) async {
    try {
      if (fromCurrency == toCurrency) {
        return {
          'tasa': 1.0,
          'fecha_actualizacion': DateTime.now().toIso8601String(),
          'is_current': true,
        };
      }

      // Usar el método existente del CurrencyService
      final rates = await CurrencyService.getCurrentRatesFromDatabase();

      // Buscar tasa directa
      for (final rate in rates) {
        if (rate['moneda_origen'] == fromCurrency &&
            rate['moneda_destino'] == toCurrency) {
          final fechaActualizacion = DateTime.parse(
            rate['fecha_actualizacion'],
          );
          final isRecent =
              DateTime.now().difference(fechaActualizacion).inDays < 7;

          return {
            'tasa': (rate['tasa'] as num).toDouble(),
            'fecha_actualizacion': rate['fecha_actualizacion'],
            'is_current': isRecent,
          };
        }
      }

      // Buscar tasa inversa
      for (final rate in rates) {
        if (rate['moneda_origen'] == toCurrency &&
            rate['moneda_destino'] == fromCurrency) {
          final fechaActualizacion = DateTime.parse(
            rate['fecha_actualizacion'],
          );
          final isRecent =
              DateTime.now().difference(fechaActualizacion).inDays < 7;
          final inverseTasa = (rate['tasa'] as num).toDouble();

          return {
            'tasa': inverseTasa > 0 ? 1.0 / inverseTasa : 1.0,
            'fecha_actualizacion': rate['fecha_actualizacion'],
            'is_current': isRecent,
          };
        }
      }

      return null;
    } catch (e) {
      print('❌ Error obteniendo info de tasa para display: $e');
      return null;
    }
  }

  /// Formatea un monto con el símbolo de la moneda para mostrar
  static String formatAmountForDisplay(
    double amount,
    String currency, {
    int decimals = 2,
  }) {
    final formatted = amount.toStringAsFixed(decimals);

    switch (currency) {
      case 'USD':
        return '\$${formatted} USD';
      case 'CUP':
        return '\$${formatted} CUP';
      case 'EUR':
        return '€${formatted}';
      default:
        return '${formatted} ${currency}';
    }
  }

  /// Obtiene todas las tasas para mostrar en la pantalla de visualización
  static Future<List<Map<String, dynamic>>> getAllRatesForDisplay() async {
    try {
      // Usar el método existente del CurrencyService
      return await CurrencyService.getCurrentRatesFromDatabase();
    } catch (e) {
      print('❌ Error obteniendo todas las tasas para display: $e');
      return [];
    }
  }

  /// Verifica si una tasa está actualizada para mostrar indicadores visuales
  static bool isRateCurrentForDisplay(String fechaActualizacion) {
    try {
      final fecha = DateTime.parse(fechaActualizacion);
      final diferencia = DateTime.now().difference(fecha);
      return diferencia.inDays < 7; // Consideramos actual si es menor a 7 días
    } catch (e) {
      return false;
    }
  }

  /// Obtiene información de una moneda específica para mostrar
  static Future<Map<String, dynamic>?> getCurrencyInfoForDisplay(
    String currencyCode,
  ) async {
    try {
      final response =
          await _supabase
              .from('monedas')
              .select('codigo, nombre, simbolo, pais')
              .eq('codigo', currencyCode)
              .eq('activo', true)
              .single();

      return response;
    } catch (e) {
      print('❌ Error obteniendo info de moneda $currencyCode: $e');
      // Fallback básico
      switch (currencyCode) {
        case 'USD':
          return {
            'codigo': 'USD',
            'nombre': 'Dólar Estadounidense',
            'simbolo': '\$',
            'pais': 'Estados Unidos',
          };
        case 'CUP':
          return {
            'codigo': 'CUP',
            'nombre': 'Peso Cubano',
            'simbolo': '\$',
            'pais': 'Cuba',
          };
        case 'EUR':
          return {
            'codigo': 'EUR',
            'nombre': 'Euro',
            'simbolo': '€',
            'pais': 'Unión Europea',
          };
        default:
          return null;
      }
    }
  }

  /// Refresca las tasas usando el servicio existente (para botón de refresh)
  static Future<bool> refreshRatesForDisplay() async {
    try {
      // Usar el método existente del CurrencyService
      final response = await CurrencyService.fetchAndUpdateExchangeRates();
      return response.rates.isNotEmpty;
    } catch (e) {
      print('❌ Error refrescando tasas para display: $e');
      return false;
    }
  }

  /// Guarda tasa aplicada en recepción para historial
  static Future<bool> saveHistoricalExchangeRate(
    int receptionId,
    double appliedRate,
    String fromCurrency,
    String toCurrency,
  ) async {
    try {
      await _supabase
          .from('app_dat_operacion_recepcion')
          .update({
            'tasa_cambio_aplicada': appliedRate,
            'fecha_tasa_aplicada': DateTime.now().toIso8601String(),
          })
          .eq('id_operacion', receptionId);

      print(
        '✅ Tasa histórica guardada: $appliedRate $fromCurrency→$toCurrency para recepción $receptionId',
      );
      return true;
    } catch (e) {
      print('❌ Error guardando tasa histórica: $e');
      return false;
    }
  }
}
