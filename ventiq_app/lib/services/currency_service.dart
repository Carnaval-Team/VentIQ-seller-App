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
        final useLocal = await userPreferencesService.shouldUseLocalData();
        if (useLocal) {
          final cached = await userPreferencesService.getCambioCupUsd();
          print(
            '🔌 Offline/full-offline - Usando tipo de cambio desde cache: $cached',
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
        usdRate = (usdRateData['tasa'] as num?)?.toDouble() ?? 0.0;
      } else {
        print('⚠️ No USD rate found in database, using cached rate');
        usdRate = await userPreferencesService.getCambioCupUsd();
      }
      if (usdRate <= 0) {
        usdRate = await userPreferencesService.getCambioCupUsd();
      }
      if (usdRate <= 0) {
        print('⚠️ Sin tasa USD válida (ni DB ni cache)');
        return 0.0;
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

  /// Líneas temporales de tasas USD→CUP para resolver tasas históricas.
  ///
  /// Online: descarga y cachea. Offline: lee cache local.
  static Future<
      ({
        List<Map<String, dynamic>> storeRates,
        List<Map<String, dynamic>> globalRates,
      })> loadUsdToCupRateTimelines({bool forceRefresh = false}) async {
    final userPreferencesService = UserPreferencesService();

    try {
      final useLocal = !forceRefresh &&
          await userPreferencesService.shouldUseLocalData();
      if (useLocal) {
        final cached = await userPreferencesService.getUsdToCupRateTimelines();
        if (cached != null) {
          print('🔌 Offline - timelines USD→CUP desde cache');
          return cached;
        }
        print('⚠️ Offline sin timelines de tasa cacheados');
        return (
          storeRates: <Map<String, dynamic>>[],
          globalRates: <Map<String, dynamic>>[],
        );
      }

      final storeId = await userPreferencesService.getIdTienda();
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

      await userPreferencesService.saveUsdToCupRateTimelines(
        storeRates: storeRates,
        globalRates: globalRates,
      );

      return (storeRates: storeRates, globalRates: globalRates);
    } catch (e) {
      print('❌ Error loading USD→CUP rate timelines: $e');
      final cached = await userPreferencesService.getUsdToCupRateTimelines();
      if (cached != null) {
        print('💱 Usando timelines USD→CUP desde cache tras error de red');
        return cached;
      }
      return (
        storeRates: <Map<String, dynamic>>[],
        globalRates: <Map<String, dynamic>>[],
      );
    }
  }

  /// Descarga y cachea tasa actual + historial (para sync / prep offline).
  static Future<void> syncUsdRatesForOffline() async {
    try {
      await getUsdRate();
      await loadUsdToCupRateTimelines(forceRefresh: true);
      print('✅ Tasas USD→CUP sincronizadas para offline');
    } catch (e) {
      print('⚠️ Sync tasas USD→CUP (no bloqueante): $e');
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
      if (createdAt == null || createdAt.toUtc().isAfter(target)) continue;
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
      if (fecha == null || fecha.toUtc().isAfter(target)) continue;
      final rate = (row['tasa'] as num?)?.toDouble();
      if (rate == null || rate <= 0) continue;
      latestGlobal = row;
    }
    if (latestGlobal != null) {
      return (latestGlobal['tasa'] as num).toDouble();
    }

    return null;
  }

  // ==========================================================================
  // MULTIMONEDA (Fase 3 del plan)
  // ==========================================================================

  /// Tasa de un par cualquiera (origen → destino) para la tienda actual.
  ///
  /// Delega en `fn_tasa_cambio`, que es **la misma función que usa el servidor
  /// al registrar el cobro**. Así el importe que ve el cajero y el que guarda
  /// la base no pueden discrepar por resolver la tasa con reglas distintas.
  ///
  /// Precedencia en servidor: tasa de tienda → tasa global manual → automática
  /// («el toque»). Devuelve **0** si no hay ninguna.
  ///
  /// Offline: la única tasa cacheada es USD→CUP. Por eso, sin conexión solo se
  /// puede cobrar en CUP y USD; cualquier otra divisa exige conexión
  /// (decisión D2, hasta la Fase 4).
  static Future<double> getRate(String origen, String destino) async {
    final o = origen.trim().toUpperCase();
    final d = destino.trim().toUpperCase();
    if (o == d) return 1;
    if (o.isEmpty || d.isEmpty) return 0;

    try {
      final storeId = await UserPreferencesService().getIdTienda();
      final res = await _supabase.rpc(
        'fn_tasa_cambio',
        params: {
          'p_moneda_origen': o,
          'p_moneda_destino': d,
          if (storeId != null) 'p_id_tienda': storeId,
        },
      );
      final valor = res is num
          ? res.toDouble()
          : double.tryParse(res?.toString() ?? '');
      if (valor != null && valor > 0) return valor;
    } catch (e) {
      print('❌ getRate($o→$d): $e');
    }

    // Respaldo offline: la única tasa disponible sin red es USD→CUP.
    if (o == 'USD' && d == 'CUP') {
      return await UserPreferencesService().getCambioCupUsd();
    }
    return 0;
  }

  /// Monedas que acepta la tienda actual, ordenadas por `orden`.
  ///
  /// Devuelve `[{codigo, nombre, simbolo, decimales, orden}]`.
  /// Si la tienda no tiene configuración o falla la consulta, devuelve una
  /// lista vacía y el llamador decide el respaldo (CUP/USD).
  static Future<List<Map<String, dynamic>>> getMonedasTienda() async {
    try {
      final storeId = await UserPreferencesService().getIdTienda();
      if (storeId == null) return const [];

      final asignadas = await _supabase
          .from('app_dat_tienda_moneda')
          .select('moneda, activo, orden')
          .eq('id_tienda', storeId)
          .eq('activo', true)
          .order('orden');
      final filas = List<Map<String, dynamic>>.from(asignadas as List);
      if (filas.isEmpty) return const [];

      final catalogo = await _supabase
          .from('monedas')
          .select('codigo, nombre, simbolo, decimales')
          .eq('activo', true);
      final porCodigo = <String, Map<String, dynamic>>{};
      for (final c in List<Map<String, dynamic>>.from(catalogo as List)) {
        porCodigo[(c['codigo'] ?? '').toString().trim()] = c;
      }

      final salida = <Map<String, dynamic>>[];
      for (final a in filas) {
        final codigo = (a['moneda'] ?? '').toString().trim();
        final meta = porCodigo[codigo];
        // Moneda desactivada en el catálogo global: no se ofrece.
        if (meta == null) continue;
        salida.add({
          'codigo': codigo,
          'nombre': (meta['nombre'] ?? codigo).toString(),
          'simbolo': (meta['simbolo'] ?? '').toString(),
          'decimales': (meta['decimales'] as num?)?.toInt() ?? 2,
          'orden': (a['orden'] as num?)?.toInt() ?? 100,
        });
      }
      return salida;
    } catch (e) {
      print('❌ getMonedasTienda: $e');
      return const [];
    }
  }

  /// Tasas a CUP de todas las monedas aceptadas por la tienda.
  ///
  /// Ejemplo: `{'CUP': 1, 'USD': 900, 'EUR': 990}`.
  /// Las divisas sin tasa resoluble se **omiten**: el cobro en ellas queda
  /// bloqueado en la UI, que es la decisión B4 del plan.
  static Future<Map<String, double>> getRatesForStore() async {
    final monedas = await getMonedasTienda();
    final tasas = <String, double>{};
    for (final m in monedas) {
      final codigo = (m['codigo'] ?? '').toString().trim();
      if (codigo.isEmpty) continue;
      if (codigo == 'CUP') {
        tasas[codigo] = 1;
        continue;
      }
      final tasa = await getRate(codigo, 'CUP');
      if (tasa > 0) tasas[codigo] = tasa;
    }
    return tasas;
  }
}
