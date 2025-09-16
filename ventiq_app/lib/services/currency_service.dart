import 'package:supabase_flutter/supabase_flutter.dart';

class CurrencyService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Gets current exchange rates from database
  static Future<List<Map<String, dynamic>>> getCurrentRatesFromDatabase() async {
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
    try {
      final rates = await getCurrentRatesFromDatabase();
      
      // Find USD rate where moneda_origen = 'USD'
      final usdRateData = rates.firstWhere(
        (rate) => rate['moneda_origen'] == 'USD',
        orElse: () => <String, dynamic>{},
      );
      
      if (usdRateData.isNotEmpty) {
        return (usdRateData['tasa'] as num?)?.toDouble() ?? 420.0;
      } else {
        print('⚠️ No USD rate found in database, using default');
        return 420.0; // Default fallback rate
      }
    } catch (e) {
      print('❌ Error loading USD rate: $e');
      return 420.0; // Default fallback rate
    }
  }
}
