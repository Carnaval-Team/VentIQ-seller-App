import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/currency_rate.dart';

class CurrencyService {
  static const String _apiUrl = 'https://eltoqueapi.netlify.app/consultar-precios';
  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Fetches current exchange rates from the API
  static Future<CurrencyRatesResponse> fetchExchangeRates() async {
    try {
      print('🌍 Fetching exchange rates from: $_apiUrl');
      
      final response = await http.get(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      print('📡 API Response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        print('✅ Exchange rates fetched successfully: $data');
        
        return CurrencyRatesResponse.fromJson(data);
      } else {
        print('❌ API request failed with status: ${response.statusCode}');
        print('Response body: ${response.body}');
        return CurrencyRatesResponse.defaultRates();
      }
    } catch (e) {
      print('❌ Error fetching exchange rates: $e');
      print('🔄 Using default rates as fallback');
      return CurrencyRatesResponse.defaultRates();
    }
  }

  /// Updates the tasas_conversion table in Supabase with new rates
  static Future<bool> updateExchangeRatesInDatabase(CurrencyRatesResponse rates) async {
    try {
      print('💾 Updating exchange rates in database...');
      
      // Update each currency rate in the database
      for (final rate in rates.rates) {
        await _updateCurrencyRate(rate);
      }
      
      print('✅ All exchange rates updated successfully in database');
      return true;
    } catch (e) {
      print('❌ Error updating exchange rates in database: $e');
      return false;
    }
  }

  /// Updates a single currency rate in the database
  static Future<void> _updateCurrencyRate(CurrencyRate rate) async {
    try {
      print('💱 Updating ${rate.currency} rate: ${rate.value}');
      
      // Update the rate where moneda_destino matches the currency
      await _supabase
          .from('tasas_conversion')
          .update({
            'tasa': rate.value,
            'fecha_actualizacion': DateTime.now().toIso8601String(),
          })
          .eq('moneda_origen', rate.currency);

      print('✅ ${rate.currency} rate updated successfully');
    } catch (e) {
      print('❌ Error updating ${rate.currency} rate: $e');
      rethrow;
    }
  }

  /// Fetches and updates exchange rates in one operation
  static Future<CurrencyRatesResponse> fetchAndUpdateExchangeRates() async {
    try {
      print('🔄 Starting exchange rates fetch and update process...');
      
      // Fetch latest rates from API
      final rates = await fetchExchangeRates();
      
      // Update database with new rates
      final updateSuccess = await updateExchangeRatesInDatabase(rates);
      
      if (updateSuccess) {
        print('✅ Exchange rates fetch and update completed successfully');
      } else {
        print('⚠️ Exchange rates fetched but database update failed');
      }
      
      return rates;
    } catch (e) {
      print('❌ Error in fetch and update process: $e');
      return CurrencyRatesResponse.defaultRates();
    }
  }

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

  /// Checks if rates need updating (older than 1 hour)
  static Future<bool> shouldUpdateRates() async {
    try {
      final rates = await getCurrentRatesFromDatabase();
      if (rates.isEmpty) return true;

      final lastUpdate = DateTime.parse(rates.first['fecha_actualizacion']);
      final hoursSinceUpdate = DateTime.now().difference(lastUpdate).inHours;
      
      return hoursSinceUpdate >= 1;
    } catch (e) {
      print('❌ Error checking if rates need update: $e');
      return true;
    }
  }
}
