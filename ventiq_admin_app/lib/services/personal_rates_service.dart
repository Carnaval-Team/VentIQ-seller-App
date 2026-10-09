import 'package:supabase_flutter/supabase_flutter.dart';

class PersonalRatesService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  static const int cupId = 1;

  /// Obtiene todas las monedas activas.
  static Future<List<Map<String, dynamic>>> getCurrencies() async {
    final response = await _supabase
        .from('tipos_moneda')
        .select('id, denominacion, simbolo, nombre_corto, pais, activo')
        .eq('activo', true)
        .order('denominacion');
    return List<Map<String, dynamic>>.from(response);
  }

  /// Obtiene las tasas activas hacia CUP (destino = 1).
  static Future<List<Map<String, dynamic>>> getRatesToCup(int storeId) async {
    final response = await _supabase
        .from('tasa_cambio_extraoficial')
        .select('''
          id,
          id_moneda_origen,
          id_moneda_destino,
          valor_cambio,
          usar_precio_toque,
          created_at,
          moneda_origen: id_moneda_origen (
            id,
            denominacion,
            simbolo,
            nombre_corto,
            pais
          )
          ''')
        .eq('id_moneda_destino', cupId)
        .eq('id_tienda', storeId)
        .eq('activo', true)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  /// Ids de moneda origen que ya tienen una tasa activa hacia CUP en la tienda.
  static Future<Set<int>> getActiveOriginCurrencyIds(int storeId) async {
    final response = await _supabase
        .from('tasa_cambio_extraoficial')
        .select('id_moneda_origen')
        .eq('id_tienda', storeId)
        .eq('id_moneda_destino', cupId)
        .eq('activo', true);
    return response
        .map((row) => (row['id_moneda_origen'] as num).toInt())
        .toSet();
  }

  /// Busca la tasa activa del par en la tienda (si existe).
  static Future<Map<String, dynamic>?> findActiveRate({
    required int storeId,
    required int monedaOrigenId,
    int monedaDestinoId = cupId,
  }) async {
    final response = await _supabase
        .from('tasa_cambio_extraoficial')
        .select('id, id_moneda_origen, valor_cambio, usar_precio_toque, created_at')
        .eq('id_tienda', storeId)
        .eq('id_moneda_origen', monedaOrigenId)
        .eq('id_moneda_destino', monedaDestinoId)
        .eq('activo', true)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (response == null) return null;
    return Map<String, dynamic>.from(response);
  }

  /// Desactiva todas las tasas activas del par (tienda + origen → destino).
  static Future<void> _deactivateActivePair({
    required int storeId,
    required int monedaOrigenId,
    int monedaDestinoId = cupId,
    int? exceptId,
  }) async {
    var query = _supabase
        .from('tasa_cambio_extraoficial')
        .update({'activo': false})
        .eq('id_tienda', storeId)
        .eq('id_moneda_origen', monedaOrigenId)
        .eq('id_moneda_destino', monedaDestinoId)
        .eq('activo', true);

    if (exceptId != null) {
      query = query.neq('id', exceptId);
    }

    await query;
  }

  /// Crea una tasa nueva. Falla si ya hay una activa para el mismo par.
  static Future<void> createRate({
    required int storeId,
    required int monedaOrigenId,
    required double valorCambio,
    bool usarPrecioToque = false,
  }) async {
    final existing = await findActiveRate(
      storeId: storeId,
      monedaOrigenId: monedaOrigenId,
    );
    if (existing != null) {
      throw StateError(
        'Ya existe una tasa activa para este par de monedas. '
        'Edita la existente o desactívala antes de crear otra.',
      );
    }

    await _supabase.from('tasa_cambio_extraoficial').insert({
      'id_moneda_origen': monedaOrigenId,
      'id_moneda_destino': cupId,
      'valor_cambio': valorCambio,
      'usar_precio_toque': usarPrecioToque,
      'activo': true,
      'id_tienda': storeId,
    });
  }

  /// "Editar" = versionar: desactiva la tasa anterior e inserta un registro nuevo
  /// para que los triggers de recalculo de precios se disparen (INSERT).
  static Future<void> replaceRate({
    required int previousRateId,
    required int storeId,
    required int monedaOrigenId,
    required double valorCambio,
    bool usarPrecioToque = false,
  }) async {
    // Si cambió el par, no permitir chocar con otra tasa activa distinta.
    final existing = await findActiveRate(
      storeId: storeId,
      monedaOrigenId: monedaOrigenId,
    );
    if (existing != null && (existing['id'] as num).toInt() != previousRateId) {
      throw StateError(
        'Ya existe otra tasa activa para este par de monedas. '
        'Desactívala antes de cambiar a esa moneda.',
      );
    }

    // Desactivar la anterior (y cualquier activo residual del par).
    await _supabase
        .from('tasa_cambio_extraoficial')
        .update({'activo': false})
        .eq('id', previousRateId);

    await _deactivateActivePair(
      storeId: storeId,
      monedaOrigenId: monedaOrigenId,
    );

    await _supabase.from('tasa_cambio_extraoficial').insert({
      'id_moneda_origen': monedaOrigenId,
      'id_moneda_destino': cupId,
      'valor_cambio': valorCambio,
      'usar_precio_toque': usarPrecioToque,
      'activo': true,
      'id_tienda': storeId,
    });
  }

  /// Desactiva una tasa (soft delete).
  static Future<void> deactivateRate(int id) async {
    await _supabase
        .from('tasa_cambio_extraoficial')
        .update({'activo': false})
        .eq('id', id);
  }
}
