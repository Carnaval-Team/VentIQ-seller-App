import 'package:supabase_flutter/supabase_flutter.dart';

class InteraccionesService {
  static final InteraccionesService _instance = InteraccionesService._internal();
  factory InteraccionesService() => _instance;
  InteraccionesService._internal();

  SupabaseClient get _supabase => Supabase.instance.client;

  // Obtener últimas 5 interacciones de la tienda
  Future<List<Map<String, dynamic>>> getUltimasInteraccionesTienda(int idTienda) async {
    try {
      print('📊 Obteniendo últimas interacciones de tienda: $idTienda');
      final response = await _supabase.rpc(
        'get_ultimas_interacciones_tienda',
        params: {'p_id_tienda': idTienda, 'p_limit': 5},
      ) as List<dynamic>;

      print('✅ Últimas interacciones de tienda obtenidas: ${response.length}');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error obteniendo últimas interacciones de tienda: $e');
      rethrow;
    }
  }

  // Obtener últimas 5 interacciones de productos
  Future<List<Map<String, dynamic>>> getUltimasInteraccionesProductos(int idTienda) async {
    try {
      print('📊 Obteniendo últimas interacciones de productos: $idTienda');
      final response = await _supabase.rpc(
        'get_ultimas_interacciones_productos',
        params: {'p_id_tienda': idTienda, 'p_limit': 5},
      ) as List<dynamic>;

      print('✅ Últimas interacciones de productos obtenidas: ${response.length}');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error obteniendo últimas interacciones de productos: $e');
      rethrow;
    }
  }

  // Obtener estadísticas de ratings de la tienda
  Future<Map<String, dynamic>> getEstadisticasTiendaRating(int idTienda) async {
    try {
      print('📊 Obteniendo estadísticas de tienda: $idTienda');
      final response = await _supabase.rpc(
        'get_estadisticas_tienda_rating',
        params: {'p_id_tienda': idTienda},
      ) as List<dynamic>;

      if (response.isEmpty) {
        return {
          'promedio_rating': 0.0,
          'cantidad_ratings': 0,
          'cantidad_5_estrellas': 0,
          'cantidad_4_estrellas': 0,
          'cantidad_3_estrellas': 0,
          'cantidad_2_estrellas': 0,
          'cantidad_1_estrella': 0,
        };
      }

      final data = Map<String, dynamic>.from(response[0]);
      // Asegurar que los valores nulos se conviertan a 0
      data['promedio_rating'] = (data['promedio_rating'] as num?)?.toDouble() ?? 0.0;
      data['cantidad_ratings'] = (data['cantidad_ratings'] as num?)?.toInt() ?? 0;
      data['cantidad_5_estrellas'] = (data['cantidad_5_estrellas'] as num?)?.toInt() ?? 0;
      data['cantidad_4_estrellas'] = (data['cantidad_4_estrellas'] as num?)?.toInt() ?? 0;
      data['cantidad_3_estrellas'] = (data['cantidad_3_estrellas'] as num?)?.toInt() ?? 0;
      data['cantidad_2_estrellas'] = (data['cantidad_2_estrellas'] as num?)?.toInt() ?? 0;
      data['cantidad_1_estrella'] = (data['cantidad_1_estrella'] as num?)?.toInt() ?? 0;

      print('✅ Estadísticas de tienda obtenidas');
      return data;
    } catch (e) {
      print('❌ Error obteniendo estadísticas de tienda: $e');
      rethrow;
    }
  }

  // Obtener estadísticas de ratings de todos los productos
  Future<Map<String, dynamic>> getEstadisticasProductosRating(int idTienda) async {
    try {
      print('📊 Obteniendo estadísticas de productos: $idTienda');
      final response = await _supabase.rpc(
        'get_estadisticas_productos_rating',
        params: {'p_id_tienda': idTienda},
      ) as List<dynamic>;

      if (response.isEmpty) {
        return {
          'promedio_rating': 0.0,
          'cantidad_ratings': 0,
          'cantidad_5_estrellas': 0,
          'cantidad_4_estrellas': 0,
          'cantidad_3_estrellas': 0,
          'cantidad_2_estrellas': 0,
          'cantidad_1_estrella': 0,
        };
      }

      final data = Map<String, dynamic>.from(response[0]);
      data['promedio_rating'] = (data['promedio_rating'] as num?)?.toDouble() ?? 0.0;
      data['cantidad_ratings'] = (data['cantidad_ratings'] as num?)?.toInt() ?? 0;
      data['cantidad_5_estrellas'] = (data['cantidad_5_estrellas'] as num?)?.toInt() ?? 0;
      data['cantidad_4_estrellas'] = (data['cantidad_4_estrellas'] as num?)?.toInt() ?? 0;
      data['cantidad_3_estrellas'] = (data['cantidad_3_estrellas'] as num?)?.toInt() ?? 0;
      data['cantidad_2_estrellas'] = (data['cantidad_2_estrellas'] as num?)?.toInt() ?? 0;
      data['cantidad_1_estrella'] = (data['cantidad_1_estrella'] as num?)?.toInt() ?? 0;

      print('✅ Estadísticas de productos obtenidas');
      return data;
    } catch (e) {
      print('❌ Error obteniendo estadísticas de productos: $e');
      rethrow;
    }
  }

  // Obtener interacciones de tienda con paginación
  Future<Map<String, dynamic>> getInteraccionesTiendaPaginado(
    int idTienda, {
    int page = 1,
    int pageSize = 10,
  }) async {
    try {
      print('📊 Obteniendo interacciones de tienda (página $page): $idTienda');
      final response = await _supabase.rpc(
        'get_interacciones_tienda_paginado',
        params: {
          'p_id_tienda': idTienda,
          'p_page': page,
          'p_page_size': pageSize,
        },
      ) as List<dynamic>;

      if (response.isEmpty) {
        return {
          'data': [],
          'total': 0,
          'page': page,
          'pageSize': pageSize,
        };
      }

      final totalCount = (response[0]['total_count'] as num).toInt();
      final data = response.map((item) {
        final map = Map<String, dynamic>.from(item);
        map.remove('total_count');
        return map;
      }).toList();

      print('✅ Interacciones de tienda obtenidas: ${data.length}/$totalCount');
      return {
        'data': data,
        'total': totalCount,
        'page': page,
        'pageSize': pageSize,
        'totalPages': (totalCount / pageSize).ceil(),
      };
    } catch (e) {
      print('❌ Error obteniendo interacciones de tienda: $e');
      rethrow;
    }
  }

  // Obtener interacciones de productos con paginación
  Future<Map<String, dynamic>> getInteraccionesProductosPaginado(
    int idTienda, {
    int page = 1,
    int pageSize = 10,
  }) async {
    try {
      print('📊 Obteniendo interacciones de productos (página $page): $idTienda');
      final response = await _supabase.rpc(
        'get_interacciones_productos_paginado',
        params: {
          'p_id_tienda': idTienda,
          'p_page': page,
          'p_page_size': pageSize,
        },
      ) as List<dynamic>;

      if (response.isEmpty) {
        return {
          'data': [],
          'total': 0,
          'page': page,
          'pageSize': pageSize,
        };
      }

      final totalCount = (response[0]['total_count'] as num).toInt();
      final data = response.map((item) {
        final map = Map<String, dynamic>.from(item);
        map.remove('total_count');
        return map;
      }).toList();

      print('✅ Interacciones de productos obtenidas: ${data.length}/$totalCount');
      return {
        'data': data,
        'total': totalCount,
        'page': page,
        'pageSize': pageSize,
        'totalPages': (totalCount / pageSize).ceil(),
      };
    } catch (e) {
      print('❌ Error obteniendo interacciones de productos: $e');
      rethrow;
    }
  }

  // Obtener ratings de un producto específico con paginación
  Future<Map<String, dynamic>> getRatingsProductoPaginado(
    int idProducto, {
    int page = 1,
    int pageSize = 10,
  }) async {
    try {
      print('📊 Obteniendo ratings del producto (página $page): $idProducto');
      final response = await _supabase.rpc(
        'get_ratings_producto_paginado',
        params: {
          'p_id_producto': idProducto,
          'p_page': page,
          'p_page_size': pageSize,
        },
      ) as List<dynamic>;

      if (response.isEmpty) {
        return {
          'data': [],
          'total': 0,
          'page': page,
          'pageSize': pageSize,
        };
      }

      final totalCount = (response[0]['total_count'] as num).toInt();
      final data = response.map((item) {
        final map = Map<String, dynamic>.from(item);
        map.remove('total_count');
        return map;
      }).toList();

      print('✅ Ratings del producto obtenidos: ${data.length}/$totalCount');
      return {
        'data': data,
        'total': totalCount,
        'page': page,
        'pageSize': pageSize,
        'totalPages': (totalCount / pageSize).ceil(),
      };
    } catch (e) {
      print('❌ Error obteniendo ratings del producto: $e');
      rethrow;
    }
  }

  // Obtener estadísticas de un producto específico
  Future<Map<String, dynamic>> getEstadisticasProductoRating(int idProducto) async {
    try {
      print('📊 Obteniendo estadísticas del producto: $idProducto');
      final response = await _supabase.rpc(
        'get_estadisticas_producto_rating',
        params: {'p_id_producto': idProducto},
      ) as List<dynamic>;

      if (response.isEmpty) {
        return {
          'promedio_rating': 0.0,
          'cantidad_ratings': 0,
          'cantidad_5_estrellas': 0,
          'cantidad_4_estrellas': 0,
          'cantidad_3_estrellas': 0,
          'cantidad_2_estrellas': 0,
          'cantidad_1_estrella': 0,
        };
      }

      final data = Map<String, dynamic>.from(response[0]);
      // Asegurar que los valores nulos se conviertan a 0
      data['promedio_rating'] = (data['promedio_rating'] as num?)?.toDouble() ?? 0.0;
      data['cantidad_ratings'] = (data['cantidad_ratings'] as num?)?.toInt() ?? 0;
      data['cantidad_5_estrellas'] = (data['cantidad_5_estrellas'] as num?)?.toInt() ?? 0;
      data['cantidad_4_estrellas'] = (data['cantidad_4_estrellas'] as num?)?.toInt() ?? 0;
      data['cantidad_3_estrellas'] = (data['cantidad_3_estrellas'] as num?)?.toInt() ?? 0;
      data['cantidad_2_estrellas'] = (data['cantidad_2_estrellas'] as num?)?.toInt() ?? 0;
      data['cantidad_1_estrella'] = (data['cantidad_1_estrella'] as num?)?.toInt() ?? 0;

      print('✅ Estadísticas del producto obtenidas');
      return data;
    } catch (e) {
      print('❌ Error obteniendo estadísticas del producto: $e');
      rethrow;
    }
  }

  // Obtener lista de productos para filtro
  Future<List<Map<String, dynamic>>> getProductosTiendaParaFiltro(int idTienda) async {
    try {
      print('📊 Obteniendo productos de tienda para filtro: $idTienda');
      final response = await _supabase.rpc(
        'get_productos_tienda_para_filtro',
        params: {'p_id_tienda': idTienda},
      ) as List<dynamic>;

      print('✅ Productos obtenidos: ${response.length}');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error obteniendo productos: $e');
      rethrow;
    }
  }
}
