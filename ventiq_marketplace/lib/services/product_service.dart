import 'package:supabase_flutter/supabase_flutter.dart';

/// Servicio para gestionar productos del marketplace
/// Usa funciones RPC optimizadas para reducir carga en BD
class ProductService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Obtener productos más vendidos usando función RPC optimizada
  /// 
  /// [limit] - Número máximo de productos a retornar (default: 10)
  /// [categoryId] - ID de categoría para filtrar (opcional)
  Future<List<Map<String, dynamic>>> getMostSoldProducts({
    int limit = 10,
    int? categoryId,
  }) async {
    try {
      print('🔍 Llamando RPC: fn_get_productos_mas_vendidos');
      print('  - Límite: $limit');
      print('  - Categoría: ${categoryId ?? "Todas"}');

      // Usar la función RPC optimizada que ya creamos
      final response = await _supabase.rpc(
        'fn_get_productos_mas_vendidos',
        params: {
          'p_limit': limit,
          'p_id_categoria': categoryId,
        },
      );

      if (response == null) {
        print('⚠️ Respuesta nula de la función RPC');
        return [];
      }

      final List<Map<String, dynamic>> products = 
          List<Map<String, dynamic>>.from(response as List);

      print('✅ ${products.length} productos obtenidos desde RPC');
      
      return products;
    } catch (e) {
      print('❌ Error en RPC fn_get_productos_mas_vendidos: $e');
      return [];
    }
  }

  /// Obtener detalles de un producto específico
  Future<Map<String, dynamic>?> getProductDetails(int productId) async {
    try {
      print('🔍 Obteniendo detalles del producto $productId...');

      final response = await _supabase
          .from('app_dat_producto')
          .select('''
            id,
            denominacion,
            descripcion,
            imagen,
            es_vendible,
            id_tienda,
            app_dat_tienda!inner(
              id,
              denominacion,
              ubicacion
            )
          ''')
          .eq('id', productId)
          .eq('app_dat_producto.mostrar_en_catalogo', true)
          .isFilter('deleted_at', null)
          .single();

      print('✅ Detalles del producto obtenidos');
      return response;
    } catch (e) {
      print('❌ Error obteniendo detalles del producto: $e');
      return null;
    }
  }

  /// Obtener presentaciones de un producto
  Future<List<Map<String, dynamic>>> getProductPresentations(
    int productId,
  ) async {
    try {
      print('🔍 Obteniendo presentaciones del producto $productId...');

      final response = await _supabase
          .from('app_dat_producto_presentacion')
          .select('''
            id,
            id_producto,
            id_presentacion,
            cantidad,
            es_base,
            app_nom_presentacion!inner(
              id,
              denominacion,
              descripcion,
              sku_codigo
            )
          ''')
          .eq('id_producto', productId)
          .order('es_base', ascending: false);

      print('✅ ${response.length} presentaciones obtenidas');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error obteniendo presentaciones: $e');
      return [];
    }
  }

  /// Obtener precio de venta de un producto
  Future<Map<String, dynamic>?> getProductPrice(int productId) async {
    try {
      print('🔍 Obteniendo precio del producto $productId...');

      final response = await _supabase
          .from('app_dat_precio_venta')
          .select('*')
          .eq('id_producto', productId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response != null) {
        print('✅ Precio obtenido: \$${response['precio_venta']}');
      } else {
        print('⚠️ No se encontró precio para el producto');
      }

      return response;
    } catch (e) {
      print('❌ Error obteniendo precio: $e');
      return null;
    }
  }

  /// Obtener rating promedio de un producto
  Future<Map<String, dynamic>> getProductRating(int productId) async {
    try {
      print('🔍 Obteniendo rating del producto $productId...');

      final response = await _supabase
          .from('app_dat_producto_rating')
          .select('rating')
          .eq('id_producto', productId);

      if (response.isEmpty) {
        return {'rating': 0.0, 'count': 0};
      }

      final ratings = List<Map<String, dynamic>>.from(response);
      final totalRating = ratings.fold<double>(
        0.0,
        (sum, item) => sum + (item['rating'] as num).toDouble(),
      );
      final avgRating = totalRating / ratings.length;

      print('✅ Rating obtenido: ${avgRating.toStringAsFixed(1)} (${ratings.length} reviews)');

      return {
        'rating': double.parse(avgRating.toStringAsFixed(1)),
        'count': ratings.length,
      };
    } catch (e) {
      print('❌ Error obteniendo rating: $e');
      return {'rating': 0.0, 'count': 0};
    }
  }

  /// Buscar productos por texto
  Future<List<Map<String, dynamic>>> searchProducts(
    String query, {
    int limit = 20,
  }) async {
    try {
      print('🔍 Buscando productos: "$query"...');

      final response = await _supabase
          .from('app_dat_producto')
          .select('''
            id,
            denominacion,
            descripcion,
            imagen,
            app_dat_precio_venta!left(
              precio_venta,
              precio_oferta,
              tiene_oferta
            )
          ''')
          .ilike('denominacion', '%$query%')
          .isFilter('deleted_at', null)
          .eq('es_vendible', true)
          .limit(limit);

      print('✅ ${response.length} productos encontrados');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error buscando productos: $e');
      return [];
    }
  }

  /// Obtener stock disponible de un producto
  Future<int> getProductStock(int productId) async {
    try {
      print('🔍 Obteniendo stock del producto $productId...');

      final response = await _supabase
          .from('app_dat_inventario_productos')
          .select('cantidad_final')
          .eq('id_producto', productId)
          .gt('cantidad_final', 0);

      if (response.isEmpty) {
        print('⚠️ No hay stock disponible');
        return 0;
      }

      final stock = response.fold<int>(
        0,
        (sum, item) => sum + (item['cantidad_final'] as num).toInt(),
      );

      print('✅ Stock disponible: $stock unidades');
      return stock;
    } catch (e) {
      print('❌ Error obteniendo stock: $e');
      return 0;
    }
  }
}
