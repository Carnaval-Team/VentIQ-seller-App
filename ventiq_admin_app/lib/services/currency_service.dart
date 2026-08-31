import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/currency_rate.dart';
import 'store_service.dart';

class CurrencyService {
  static const String _apiUrl = 'https://tasas.eltoque.com/v1/trmi';
  static const String _apiToken =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJmcmVzaCI6ZmFsc2UsImlhdCI6MTc1ODA0NDg1NSwianRpIjoiOWRlMmE2MjgtNzZhZC00ZTAyLTk3ZjctNTJlN2U0NjhmODdkIiwidHlwZSI6ImFjY2VzcyIsInN1YiI6IjY4YzQzZDg0MGU1NmM1MDMzZDQ0Nzc4MSIsIm5iZiI6MTc1ODA0NDg1NSwiZXhwIjoxNzg5NTgwODU1fQ.L4DayrQx1LGWOEFMSG6SWdAneKwNkW5F9PiwAc8Ine0';
  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _savedRatesKey = 'saved_exchange_rates';

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

  static Future<CurrencyRatesResponse> _applyUsdToCupStoreOverride(
    CurrencyRatesResponse baseRates,
  ) async {
    try {
      final storeId = await StoreService.getCurrentStoreId();
      if (storeId == null) return baseRates;

      final config = await _getUsdToCupStoreRateConfig(storeId);
      if (config == null) return baseRates;

      if (config['usar_precio_toque'] == true) return baseRates;

      final valorCambio = (config['valor_cambio'] as num?)?.toDouble();
      if (valorCambio == null || valorCambio <= 0) return baseRates;

      return CurrencyRatesResponse(
        usd: CurrencyRate(
          currency: 'USD',
          value: valorCambio,
          lastUpdate: baseRates.lastUpdate,
          timestamp: baseRates.timestamp,
        ),
        eur: baseRates.eur,
        mlc: baseRates.mlc,
        lastUpdate: baseRates.lastUpdate,
        timestamp: baseRates.timestamp,
      );
    } catch (e) {
      print('❌ Error applying custom USD→CUP override: $e');
      return baseRates;
    }
  }

  static Future<double> getEffectiveUsdToCupRate() async {
    try {
      final storeId = await StoreService.getCurrentStoreId();
      if (storeId != null) {
        final config = await _getUsdToCupStoreRateConfig(storeId);
        if (config != null && config['usar_precio_toque'] != true) {
          final valorCambio = (config['valor_cambio'] as num?)?.toDouble();
          if (valorCambio != null && valorCambio > 0) return valorCambio;
        }
      }

      final rates = await getCurrentRatesFromDatabase();
      final usdRateData = rates.firstWhere(
        (rate) =>
            rate['moneda_origen'] == 'USD' &&
            (rate['moneda_destino'] == 'CUP' || rate['moneda_destino'] == null),
        orElse: () => <String, dynamic>{},
      );
      final dbRate = (usdRateData['tasa'] as num?)?.toDouble();
      if (dbRate != null && dbRate > 0) return dbRate;
    } catch (e) {
      print('❌ Error getting effective USD→CUP rate: $e');
    }

    final fallbackRates = await fetchExchangeRates();
    return fallbackRates.usd.value;
  }

  /// Líneas temporales de tasas USD→CUP para resolver tasas históricas.
  static Future<
      ({
        List<Map<String, dynamic>> storeRates,
        List<Map<String, dynamic>> globalRates,
      })> loadUsdToCupRateTimelines() async {
    try {
      final storeId = await StoreService.getCurrentStoreId();
      List<Map<String, dynamic>> storeRates = [];
      if (storeId != null) {
        final response = await _supabase
            .from('tasa_cambio_extraoficial')
            .select('valor_cambio, usar_precio_toque, created_at')
            .eq('id_tienda', storeId)
            .eq('id_moneda_origen', _usdId)
            .eq('id_moneda_destino', _cupId)
            .order('created_at', ascending: true);
        storeRates = List<Map<String, dynamic>>.from(response);
      }

      final globalResponse = await _supabase
          .from('tasas_conversion')
          .select('tasa, fecha_actualizacion')
          .eq('moneda_origen', 'USD')
          .eq('moneda_destino', 'CUP')
          .order('fecha_actualizacion', ascending: true);
      final globalRates = List<Map<String, dynamic>>.from(globalResponse);

      return (storeRates: storeRates, globalRates: globalRates);
    } catch (e) {
      print('❌ Error loading USD→CUP rate timelines: $e');
      return (
        storeRates: <Map<String, dynamic>>[],
        globalRates: <Map<String, dynamic>>[],
      );
    }
  }

  /// Resuelve la tasa USD→CUP vigente en [at] usando historial de tienda o global.
  static double? resolveUsdToCupRateAt(
    DateTime at,
    ({
      List<Map<String, dynamic>> storeRates,
      List<Map<String, dynamic>> globalRates,
    }) timelines,
  ) {
    final target = at.toUtc();

    Map<String, dynamic>? latestStore;
    for (final row in timelines.storeRates) {
      final createdAt = DateTime.tryParse(row['created_at']?.toString() ?? '');
      if (createdAt == null || createdAt.isAfter(target)) continue;
      if (row['usar_precio_toque'] == true) continue;
      final rate = (row['valor_cambio'] as num?)?.toDouble();
      if (rate == null || rate <= 0) continue;
      latestStore = row;
    }
    if (latestStore != null) {
      return (latestStore['valor_cambio'] as num).toDouble();
    }

    Map<String, dynamic>? latestGlobal;
    for (final row in timelines.globalRates) {
      final fecha = DateTime.tryParse(
        row['fecha_actualizacion']?.toString() ?? '',
      );
      if (fecha == null || fecha.isAfter(target)) continue;
      final rate = (row['tasa'] as num?)?.toDouble();
      if (rate == null || rate <= 0) continue;
      latestGlobal = row;
    }
    if (latestGlobal != null) {
      return (latestGlobal['tasa'] as num).toDouble();
    }

    return null;
  }

  /// Verifica si CUP y USD coinciden con la tasa (tolerancia relativa 2%).
  static bool salePricesMatchAtRate({
    required double cup,
    required double usd,
    required double rate,
    double tolerance = 0.02,
  }) {
    if (rate <= 0 || usd <= 0) return false;
    final expectedCup = usd * rate;
    if (expectedCup <= 0) return false;
    return ((cup - expectedCup).abs() / expectedCup) <= tolerance;
  }

  static Future<List<Map<String, dynamic>>>
  getEffectiveRatesFromDatabase() async {
    final rates = await getCurrentRatesFromDatabase();
    try {
      final storeId = await StoreService.getCurrentStoreId();
      if (storeId == null) return rates;

      final config = await _getUsdToCupStoreRateConfig(storeId);
      if (config == null) return rates;
      if (config['usar_precio_toque'] == true) return rates;

      final valorCambio = (config['valor_cambio'] as num?)?.toDouble();
      if (valorCambio == null || valorCambio <= 0) return rates;

      final result = rates
          .map((r) => Map<String, dynamic>.from(r))
          .toList(growable: true);

      bool replaced = false;
      for (final r in result) {
        if (r['moneda_origen'] == 'USD' &&
            (r['moneda_destino'] == 'CUP' || r['moneda_destino'] == null)) {
          r['tasa'] = valorCambio;
          replaced = true;
          break;
        }
      }

      if (!replaced) {
        result.insert(0, {
          'moneda_origen': 'USD',
          'moneda_destino': 'CUP',
          'tasa': valorCambio,
          'fecha_actualizacion': DateTime.now().toIso8601String(),
        });
      }

      return result;
    } catch (e) {
      print('❌ Error building effective rates list: $e');
      return rates;
    }
  }

  /// Fetches current exchange rates from the ElToque API
  static Future<CurrencyRatesResponse> fetchExchangeRates() async {
    try {
      print('🌍 Starting exchange rates fetch process...');

      // Check if we have recent rates in storage (less than 1 hour old)
      final cachedRates = await _getCachedRatesIfRecent();
      if (cachedRates != null) {
        print('⚡ Using cached rates (less than 1 hour old)');
        return await _applyUsdToCupStoreOverride(cachedRates);
      }

      print('🌐 Fetching fresh rates from ElToque: $_apiUrl');

      final response = await http
          .get(
            Uri.parse(_apiUrl),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer $_apiToken',
            },
          )
          .timeout(const Duration(seconds: 10));

      print('📡 API Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        print('✅ Exchange rates fetched successfully from ElToque');
        print('📊 Raw API response: $data');

        final rates = _parseElToqueResponse(data);

        // Save rates to local storage for fallback
        await _saveRatesToStorage(rates);
        print('💾 Fresh rates saved to local storage');

        return await _applyUsdToCupStoreOverride(rates);
      } else {
        print(
          '❌ ElToque API request failed with status: ${response.statusCode}',
        );
        print('Response body: ${response.body}');
        return await _loadFallbackRates();
      }
    } catch (e) {
      print('❌ Error fetching exchange rates from ElToque: $e');
      print('🔄 Loading fallback rates...');
      return await _loadFallbackRates();
    }
  }

  /// Updates the tasas_conversion table in Supabase with new rates
  static Future<bool> updateExchangeRatesInDatabase(
    CurrencyRatesResponse rates,
  ) async {
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

  /// Parses the ElToque API response to CurrencyRatesResponse
  static CurrencyRatesResponse _parseElToqueResponse(
    Map<String, dynamic> data,
  ) {
    try {
      final tasas = data['tasas'] as Map<String, dynamic>;
      final date = data['date'] as String;
      final hour = data['hour'] as int;
      final minutes = data['minutes'] as int;
      final seconds = data['seconds'] as int;

      // Create timestamp from API response
      final timestamp = DateTime.parse(
        '$date ${hour.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
      );

      print('📅 ElToque timestamp: $timestamp');
      print('💱 Available rates: ${tasas.keys.toList()}');

      return CurrencyRatesResponse(
        usd: CurrencyRate(
          currency: 'USD',
          value:
              (tasas['USD'] as num?)?.toDouble() ??
              440.0, // Fallback if API doesn't have USD
          lastUpdate: timestamp,
          timestamp: timestamp,
        ),
        eur: CurrencyRate(
          currency: 'EUR',
          value:
              (tasas['ECU'] as num?)?.toDouble() ??
              495.0, // ElToque uses ECU for EUR, fallback if not available
          lastUpdate: timestamp,
          timestamp: timestamp,
        ),
        mlc: CurrencyRate(
          currency: 'MLC',
          value:
              (tasas['MLC'] as num?)?.toDouble() ??
              210.0, // Fallback if API doesn't have MLC
          lastUpdate: timestamp,
          timestamp: timestamp,
        ),
        lastUpdate: timestamp,
        timestamp: timestamp,
      );
    } catch (e) {
      print('❌ Error parsing ElToque response: $e');
      rethrow;
    }
  }

  /// Saves exchange rates to local storage for fallback
  static Future<void> _saveRatesToStorage(CurrencyRatesResponse rates) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ratesJson = {
        'usd': rates.usd.toJson(),
        'eur': rates.eur.toJson(),
        'mlc': rates.mlc.toJson(),
        'lastUpdate': rates.lastUpdate.toIso8601String(),
        'timestamp': rates.timestamp.toIso8601String(),
      };

      await prefs.setString(_savedRatesKey, json.encode(ratesJson));
      print('💾 Exchange rates saved to local storage');
    } catch (e) {
      print('❌ Error saving rates to storage: $e');
    }
  }

  /// Loads fallback rates from database first, then local storage, then default values
  static Future<CurrencyRatesResponse> _loadFallbackRates() async {
    try {
      // First, try to get rates from database
      print('🗄️ Attempting to load rates from database as fallback...');
      final dbRates = await _loadRatesFromDatabase();
      if (dbRates != null) {
        print('✅ Using rates from database as fallback');
        return await _applyUsdToCupStoreOverride(dbRates);
      }

      // If database fails, try local storage
      print('📱 Database fallback failed, trying local storage...');
      final prefs = await SharedPreferences.getInstance();
      final savedRatesString = prefs.getString(_savedRatesKey);

      if (savedRatesString != null) {
        print('📱 Loading saved rates from local storage');
        final savedRatesJson =
            json.decode(savedRatesString) as Map<String, dynamic>;

        final storedRates = CurrencyRatesResponse(
          usd: CurrencyRate.fromJson(savedRatesJson['usd']),
          eur: CurrencyRate.fromJson(savedRatesJson['eur']),
          mlc: CurrencyRate.fromJson(savedRatesJson['mlc']),
          lastUpdate: DateTime.parse(savedRatesJson['lastUpdate']),
          timestamp: DateTime.parse(savedRatesJson['timestamp']),
        );

        return await _applyUsdToCupStoreOverride(storedRates);
      } else {
        print('🔄 No saved rates found, using hardcoded default rates');
        return await _applyUsdToCupStoreOverride(
          CurrencyRatesResponse.defaultRates(),
        );
      }
    } catch (e) {
      print('❌ Error loading fallback rates: $e');
      print('🔄 Using hardcoded default rates as final fallback');
      return await _applyUsdToCupStoreOverride(
        CurrencyRatesResponse.defaultRates(),
      );
    }
  }

  /// Checks if cached rates are recent (less than 1 hour old) and returns them
  static Future<CurrencyRatesResponse?> _getCachedRatesIfRecent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedRatesString = prefs.getString(_savedRatesKey);

      if (savedRatesString == null) {
        print('📭 No cached rates found');
        return null;
      }

      final savedRatesJson =
          json.decode(savedRatesString) as Map<String, dynamic>;
      final lastUpdate = DateTime.parse(savedRatesJson['lastUpdate']);
      final now = DateTime.now();
      final hoursSinceUpdate = now.difference(lastUpdate).inHours;

      print('⏰ Last update: $lastUpdate');
      print('⏰ Hours since update: $hoursSinceUpdate');

      if (hoursSinceUpdate < 1) {
        print(
          '✅ Cached rates are recent (${hoursSinceUpdate}h old), using cached version',
        );
        return CurrencyRatesResponse(
          usd: CurrencyRate.fromJson(savedRatesJson['usd']),
          eur: CurrencyRate.fromJson(savedRatesJson['eur']),
          mlc: CurrencyRate.fromJson(savedRatesJson['mlc']),
          lastUpdate: DateTime.parse(savedRatesJson['lastUpdate']),
          timestamp: DateTime.parse(savedRatesJson['timestamp']),
        );
      } else {
        print('⏳ Cached rates are old (${hoursSinceUpdate}h), need fresh data');
        return null;
      }
    } catch (e) {
      print('❌ Error checking cached rates: $e');
      return null;
    }
  }

  /// Fetches and updates exchange rates in one operation
  static Future<CurrencyRatesResponse> fetchAndUpdateExchangeRates() async {
    try {
      print('🔄 Starting exchange rates fetch and update process...');

      // Fetch latest rates from API
      final rates = await fetchExchangeRates();

      bool shouldUpdateDatabase = true;
      try {
        final storeId = await StoreService.getCurrentStoreId();
        if (storeId != null) {
          final config = await _getUsdToCupStoreRateConfig(storeId);
          if (config != null && config['usar_precio_toque'] != true) {
            shouldUpdateDatabase = false;
            print(
              '⚠️ Custom USD→CUP rate active for store $storeId - skipping global tasas_conversion update',
            );
          }
        }
      } catch (e) {
        print('❌ Error checking custom rate before database update: $e');
      }

      if (shouldUpdateDatabase) {
        final updateSuccess = await updateExchangeRatesInDatabase(rates);

        if (updateSuccess) {
          print('✅ Exchange rates fetch and update completed successfully');
        } else {
          print('⚠️ Exchange rates fetched but database update failed');
        }
      } else {
        print(
          'ℹ️ Skipped tasas_conversion update due to custom rate configuration',
        );
      }

      return rates;
    } catch (e) {
      print('❌ Error in fetch and update process: $e');
      return await _loadFallbackRates();
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

  /// Loads rates from database and converts to CurrencyRatesResponse
  static Future<CurrencyRatesResponse?> _loadRatesFromDatabase() async {
    try {
      final rates = await getCurrentRatesFromDatabase();
      if (rates.isEmpty) {
        print('📭 No rates found in database');
        return null;
      }

      print('🗄️ Found ${rates.length} rates in database');

      // Find specific currency rates
      final usdRate = rates.firstWhere(
        (rate) => rate['moneda_origen'] == 'USD',
        orElse: () => <String, dynamic>{},
      );
      final eurRate = rates.firstWhere(
        (rate) => rate['moneda_origen'] == 'EUR',
        orElse: () => <String, dynamic>{},
      );
      final mlcRate = rates.firstWhere(
        (rate) => rate['moneda_origen'] == 'MLC',
        orElse: () => <String, dynamic>{},
      );

      // Get the most recent update time
      final lastUpdateStr = rates.first['fecha_actualizacion'] as String;
      final lastUpdate = DateTime.parse(lastUpdateStr);

      print('💱 Database rates found:');
      print('  - USD: ${usdRate.isNotEmpty ? usdRate['tasa'] : 'not found'}');
      print('  - EUR: ${eurRate.isNotEmpty ? eurRate['tasa'] : 'not found'}');
      print('  - MLC: ${mlcRate.isNotEmpty ? mlcRate['tasa'] : 'not found'}');
      print('  - Last update: $lastUpdate');

      return CurrencyRatesResponse(
        usd: CurrencyRate(
          currency: 'USD',
          value:
              usdRate.isNotEmpty ? (usdRate['tasa'] as num).toDouble() : 440.0,
          lastUpdate: lastUpdate,
          timestamp: lastUpdate,
        ),
        eur: CurrencyRate(
          currency: 'EUR',
          value:
              eurRate.isNotEmpty ? (eurRate['tasa'] as num).toDouble() : 495.0,
          lastUpdate: lastUpdate,
          timestamp: lastUpdate,
        ),
        mlc: CurrencyRate(
          currency: 'MLC',
          value:
              mlcRate.isNotEmpty ? (mlcRate['tasa'] as num).toDouble() : 210.0,
          lastUpdate: lastUpdate,
          timestamp: lastUpdate,
        ),
        lastUpdate: lastUpdate,
        timestamp: lastUpdate,
      );
    } catch (e) {
      print('❌ Error loading rates from database: $e');
      return null;
    }
  }
}
