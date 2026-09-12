import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CarnavalStoreProductsService {
  static final _supabase = Supabase.instance.client;

  /// Obtiene las tiendas que tienen vinculado un id de tienda carnaval.
  static Future<List<Map<String, dynamic>>> getStores() async {
    try {
      final response = await _supabase
          .from('app_dat_tienda')
          .select('id, denominacion, id_tienda_carnaval')
          .order('denominacion');
      return List<Map<String, dynamic>>.from(response)
          .where((s) => s['id_tienda_carnaval'] != null)
          .toList();
    } catch (e) {
      debugPrint('❌ Error obteniendo tiendas: $e');
      return [];
    }
  }

  /// Obtiene las categorías activas de Carnaval.
  static Future<List<Map<String, dynamic>>> getCategories() async {
    try {
      final response = await _supabase
          .schema('carnavalapp')
          .from('Categorias')
          .select('id, name, icon')
          .eq('status', true)
          .order('orden', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ Error obteniendo categorías: $e');
      return [];
    }
  }

  /// Obtiene los productos publicados de una tienda en Carnaval.
  static Future<Map<String, dynamic>> getProducts({
    required int carnavalStoreId,
    int? categoryId,
    String search = '',
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      var query = _supabase
          .schema('carnavalapp')
          .from('Productos')
          .select(
            'id, name, price, precio_descuento, stock, image, status, category_id, Categorias!inner(id, name), proveedor!inner(id, name)',
          )
          .eq('proveedor', carnavalStoreId);

      if (categoryId != null) {
        query = query.eq('category_id', categoryId);
      }

      if (search.trim().isNotEmpty) {
        query = query.ilike('name', '%${search.trim()}%');
      }

      final total = (await query.count(CountOption.exact)).count;

      final response = await query.order('name').range(offset, offset + limit - 1);
      final items = List<Map<String, dynamic>>.from(response);

      return {'items': items, 'total': total};
    } catch (e) {
      debugPrint('❌ Error obteniendo productos: $e');
      return {'items': <Map<String, dynamic>>[], 'total': 0};
    }
  }
}
