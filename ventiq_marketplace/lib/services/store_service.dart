import 'package:supabase_flutter/supabase_flutter.dart';

/// Servicio para gestionar tiendas del marketplace
/// Usa funciones RPC optimizadas para reducir carga en BD
class StoreService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Obtener tiendas destacadas usando función RPC optimizada
  ///
  /// [limit] - Número máximo de tiendas a retornar (default: 10)
  Future<List<Map<String, dynamic>>> getFeaturedStores({int limit = 10}) async {
    try {
      print('🔍 Llamando RPC: fn_get_tiendas_destacadas');
      print('  - Límite: $limit');

      // Usar la función RPC optimizada que ya creamos
      final response = await _supabase.rpc(
        'fn_get_tiendas_destacadas',
        params: {'p_limit': limit},
      );

      if (response == null) {
        print('⚠️ Respuesta nula de la función RPC');
        return [];
      }

      final List<Map<String, dynamic>> stores = List<Map<String, dynamic>>.from(
        response as List,
      );

      print('✅ ${stores.length} tiendas obtenidas desde RPC');

      return stores;
    } catch (e) {
      print('❌ Error en RPC fn_get_tiendas_destacadas: $e');
      return [];
    }
  }

  /// Obtener todas las tiendas con ubicación válida para el mapa
  Future<List<Map<String, dynamic>>> getStoresWithLocation() async {
    try {
      print('🔍 Obteniendo tiendas con ubicación para el mapa...');

      final response = await _supabase
          .from('app_dat_tienda')
          .select('id, denominacion, ubicacion, imagen_url, direccion')
          .not('ubicacion', 'is', null);

      print('✅ ${response.length} tiendas con ubicación encontradas');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error obteniendo tiendas para el mapa: $e');
      return [];
    }
  }

  /// Obtener detalles de una tienda específica
  Future<Map<String, dynamic>?> getStoreDetails(int storeId) async {
    try {
      print('🔍 Obteniendo detalles de la tienda $storeId...');

      final response = await _supabase
          .from('app_dat_tienda')
          .select('*')
          .eq('id', storeId)
          .single();

      print('✅ Detalles de la tienda obtenidos');
      return response;
    } catch (e) {
      print('❌ Error obteniendo detalles de la tienda: $e');
      return null;
    }
  }

  /// Obtener productos de una tienda
  Future<List<Map<String, dynamic>>> getStoreProducts(
    int storeId, {
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      print('🔍 Obteniendo productos de la tienda $storeId...');

      final response = await _supabase
          .from('app_dat_producto')
          .select('''
            id,
            denominacion,
            descripcion,
            imagen,
            es_vendible,
            app_dat_precio_venta!left(
              precio_venta,
              precio_oferta,
              tiene_oferta
            )
          ''')
          .eq('id_tienda', storeId)
          .isFilter('deleted_at', null)
          .eq('es_vendible', true)
          .range(offset, offset + limit - 1);

      print('✅ ${response.length} productos obtenidos');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error obteniendo productos de la tienda: $e');
      return [];
    }
  }

  /// Obtener rating promedio de una tienda
  Future<Map<String, dynamic>> getStoreRating(int storeId) async {
    try {
      print('🔍 Obteniendo rating de la tienda $storeId...');

      final response = await _supabase
          .from('app_dat_tienda_rating')
          .select('rating')
          .eq('id_tienda', storeId);

      if (response.isEmpty) {
        return {'rating': 0.0, 'count': 0};
      }

      final ratings = List<Map<String, dynamic>>.from(response);
      final totalRating = ratings.fold<double>(
        0.0,
        (sum, item) => sum + (item['rating'] as num).toDouble(),
      );
      final avgRating = totalRating / ratings.length;

      print(
        '✅ Rating obtenido: ${avgRating.toStringAsFixed(1)} (${ratings.length} reviews)',
      );

      return {
        'rating': double.parse(avgRating.toStringAsFixed(1)),
        'count': ratings.length,
      };
    } catch (e) {
      print('❌ Error obteniendo rating de la tienda: $e');
      return {'rating': 0.0, 'count': 0};
    }
  }

  /// Buscar tiendas por texto
  Future<List<Map<String, dynamic>>> searchStores(
    String query, {
    int limit = 20,
  }) async {
    try {
      print('🔍 Buscando tiendas: "$query"...');

      final response = await _supabase
          .from('app_dat_tienda')
          .select('*')
          .or('denominacion.ilike.%$query%,ubicacion.ilike.%$query%')
          .limit(limit);

      print('✅ ${response.length} tiendas encontradas');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error buscando tiendas: $e');
      return [];
    }
  }

  /// Obtener categorías de productos de una tienda
  Future<List<Map<String, dynamic>>> getStoreCategories(int storeId) async {
    try {
      print('🔍 Obteniendo categorías de la tienda $storeId...');

      final response = await _supabase
          .from('app_dat_producto')
          .select('''
            app_dat_categoria!inner(
              id,
              denominacion,
              descripcion,
              image
            )
          ''')
          .eq('id_tienda', storeId)
          .isFilter('deleted_at', null);

      // Eliminar duplicados
      final categoriesMap = <int, Map<String, dynamic>>{};
      for (var item in response) {
        final category = item['app_dat_categoria'] as Map<String, dynamic>;
        final id = category['id'] as int;
        if (!categoriesMap.containsKey(id)) {
          categoriesMap[id] = category;
        }
      }

      final categories = categoriesMap.values.toList();
      print('✅ ${categories.length} categorías obtenidas');
      return categories;
    } catch (e) {
      print('❌ Error obteniendo categorías: $e');
      return [];
    }
  }

  /// Obtener estadísticas de una tienda
  Future<Map<String, dynamic>> getStoreStats(int storeId) async {
    try {
      print('🔍 Obteniendo estadísticas de la tienda $storeId...');

      // Contar productos
      final productsResponse = await _supabase
          .from('app_dat_producto')
          .select('id')
          .eq('id_tienda', storeId)
          .isFilter('deleted_at', null);

      final productsCount = productsResponse.length;

      // Obtener rating
      final rating = await getStoreRating(storeId);

      print('✅ Estadísticas obtenidas');
      return {
        'total_productos': productsCount,
        'rating_promedio': rating['rating'],
        'total_ratings': rating['count'],
      };
    } catch (e) {
      print('❌ Error obteniendo estadísticas: $e');
      return {'total_productos': 0, 'rating_promedio': 0.0, 'total_ratings': 0};
    }
  }
}
