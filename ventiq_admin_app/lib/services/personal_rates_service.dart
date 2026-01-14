import 'package:supabase_flutter/supabase_flutter.dart';

class PersonalRatesService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Obtiene todas las monedas activas.
  static Future<List<Map<String, dynamic>>> getCurrencies() async {
    final response = await _supabase
        .from('tipos_moneda')
        .select('id, denominacion, simbolo, nombre_corto, pais, activo')
        .eq('activo', true)
        .order('denominacion');
    return List<Map<String, dynamic>>.from(response);
  }

  /// Obtiene las tasas configuradas hacia CUP (id destino = 1).
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
        .eq('id_moneda_destino', 1) // CUP
        .eq('id_tienda', storeId)
        .eq('activo', true)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  /// Crea o actualiza una tasa (origen -> CUP).
  static Future<void> upsertRate({
    int? id,
    required int storeId,
    required int monedaOrigenId,
    required double valorCambio,
    bool usarPrecioToque = false,
  }) async {
    final payload = {
      'id_moneda_origen': monedaOrigenId,
      'id_moneda_destino': 1, // CUP fijo
      'valor_cambio': valorCambio,
      'usar_precio_toque': usarPrecioToque,
      'activo': true,
      'id_tienda': storeId,
    };

    if (id != null) {
      await _supabase
          .from('tasa_cambio_extraoficial')
          .update(payload)
          .eq('id', id);
    } else {
      await _supabase.from('tasa_cambio_extraoficial').insert(payload);
    }
  }

  /// Desactiva una tasa (soft delete).
  static Future<void> deactivateRate(int id) async {
    await _supabase
        .from('tasa_cambio_extraoficial')
        .update({'activo': false})
        .eq('id', id);
  }
}
