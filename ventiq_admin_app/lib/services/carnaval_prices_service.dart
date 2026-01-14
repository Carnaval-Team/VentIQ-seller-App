import 'package:supabase_flutter/supabase_flutter.dart';

class CarnavalPricesService {
  final SupabaseClient _supabase = Supabase.instance.client;

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

    if (response == null) {
      return {'items': <Map<String, dynamic>>[], 'total': 0};
    }

    final data = List<Map<String, dynamic>>.from(response as List);
    final total = data.isNotEmpty ? (data.first['total_count'] ?? 0) as int : 0;

    return {'items': data, 'total': total};
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
