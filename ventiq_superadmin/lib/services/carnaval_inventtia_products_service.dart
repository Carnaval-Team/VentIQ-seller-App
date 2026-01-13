import 'package:supabase_flutter/supabase_flutter.dart';

class CarnavalInventtiaProductsService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> getStores() async {
    final response = await _supabase
        .from('app_dat_tienda')
        .select('id, denominacion')
        .order('denominacion');

    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> getKpis({required int storeId}) async {
    final response = await _supabase.rpc(
      'fn_carnaval_inventtia_kpis',
      params: {'p_id_tienda': storeId},
    );

    if (response != null && (response as List).isNotEmpty) {
      return response.first as Map<String, dynamic>;
    }

    return {
      'total_productos_sincronizados': 0,
      'total_productos_precio_mal': 0,
      'total_productos_stock_diferente': 0,
    };
  }

  Future<Map<String, dynamic>> getStockPage({
    required int storeId,
    required int limit,
    required int offset,
    String search = '',
  }) async {
    final response = await _supabase.rpc(
      'fn_carnaval_inventtia_stock_page',
      params: {
        'p_id_tienda': storeId,
        'p_limit': limit,
        'p_offset': offset,
        'p_search': search,
      },
    );

    if (response == null)
      return {'items': <Map<String, dynamic>>[], 'total': 0};

    final data = List<Map<String, dynamic>>.from(response as List);
    final total = data.isNotEmpty ? (data.first['total_count'] ?? 0) as int : 0;

    return {'items': data, 'total': total};
  }

  Future<Map<String, dynamic>> getPricesPage({
    required int storeId,
    required int limit,
    required int offset,
    String search = '',
  }) async {
    final response = await _supabase.rpc(
      'fn_carnaval_inventtia_prices_page',
      params: {
        'p_id_tienda': storeId,
        'p_limit': limit,
        'p_offset': offset,
        'p_search': search,
      },
    );

    if (response == null)
      return {'items': <Map<String, dynamic>>[], 'total': 0};

    final data = List<Map<String, dynamic>>.from(response as List);
    final total = data.isNotEmpty ? (data.first['total_count'] ?? 0) as int : 0;

    return {'items': data, 'total': total};
  }

  Future<void> updateCarnavalStock({
    required int carnavalProductId,
    required int newStock,
  }) async {
    await _supabase.rpc(
      'fn_carnaval_update_product_stock',
      params: {
        'p_carnaval_product_id': carnavalProductId,
        'p_new_stock': newStock,
      },
    );
  }

  Future<void> updateCarnavalPrices({
    required int carnavalProductId,
    required double precioDescuento,
    required double price,
  }) async {
    await _supabase.rpc(
      'fn_carnaval_update_product_prices',
      params: {
        'p_carnaval_product_id': carnavalProductId,
        'p_precio_descuento': precioDescuento,
        'p_price': price,
      },
    );
  }
}
