import 'package:supabase_flutter/supabase_flutter.dart';

/// Servicio para gestionar productos del marketplace
class MarketplaceService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Obtiene productos del marketplace con filtros opcionales
  ///
  /// [idTienda] - ID de la tienda (opcional, null = todas las tiendas)
  /// [idCategoria] - ID de la categoría (opcional, null = todas las categorías)
  /// [soloDisponibles] - Si true, solo retorna productos con stock > 0
  /// [searchQuery] - Texto de búsqueda (búsqueda fonética en múltiples campos)
  /// [limit] - Cantidad máxima de productos a retornar (default: 50)
  /// [offset] - Cantidad de productos a saltar (para paginación)
  ///
  /// Retorna una lista de productos con metadatos extendidos incluyendo:
  /// - Información de la tienda
  /// - Rating promedio y total de ratings
  /// - Stock disponible de todos los almacenes
  /// - Presentaciones del producto
  Future<List<Map<String, dynamic>>> getProducts({
    int? idTienda,
    int? idCategoria,
    bool soloDisponibles = false,
    String? searchQuery,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      print('🔍 Obteniendo productos del marketplace...');
      print('  - ID Tienda: ${idTienda ?? "Todas"}');
      print('  - ID Categoría: ${idCategoria ?? "Todas"}');
      print('  - Solo Disponibles: $soloDisponibles');
      print('  - Búsqueda: ${searchQuery ?? "Sin filtro"}');
      print('  - Limit: $limit, Offset: $offset');

      final response = await _supabase.rpc(
        'get_productos_marketplace',
        params: {
          'id_tienda_param': idTienda,
          'id_categoria_param': idCategoria,
          'solo_disponibles_param': soloDisponibles,
          'search_query_param': searchQuery,
          'limit_param': limit,
          'offset_param': offset,
        },
      );

      final products = List<Map<String, dynamic>>.from(response);
      print('✅ ${products.length} productos obtenidos');

      return products;
    } catch (e) {
      print('❌ Error obteniendo productos del marketplace: $e');
      rethrow;
    }
  }

  /// Obtiene todos los productos de todas las tiendas
  Future<List<Map<String, dynamic>>> getAllProducts({
    bool soloDisponibles = true,
  }) async {
    return await getProducts(soloDisponibles: soloDisponibles);
  }

  /// Obtiene productos de una tienda específica
  Future<List<Map<String, dynamic>>> getProductsByStore(
    int storeId, {
    bool soloDisponibles = true,
  }) async {
    return await getProducts(
      idTienda: storeId,
      soloDisponibles: soloDisponibles,
    );
  }

  /// Obtiene productos de una categoría específica
  Future<List<Map<String, dynamic>>> getProductsByCategory(
    int categoryId, {
    bool soloDisponibles = true,
  }) async {
    return await getProducts(
      idCategoria: categoryId,
      soloDisponibles: soloDisponibles,
    );
  }

  /// Obtiene productos de una tienda y categoría específicas
  Future<List<Map<String, dynamic>>> getProductsByStoreAndCategory(
    int storeId,
    int categoryId, {
    bool soloDisponibles = true,
  }) async {
    return await getProducts(
      idTienda: storeId,
      idCategoria: categoryId,
      soloDisponibles: soloDisponibles,
    );
  }

  /// Obtiene productos con mejor rating
  ///
  /// [minRating] - Rating mínimo requerido (default: 4.0)
  /// [limit] - Cantidad máxima de productos a retornar (default: 10)
  Future<List<Map<String, dynamic>>> getTopRatedProducts({
    double minRating = 4.0,
    int limit = 10,
  }) async {
    try {
      print('⭐ Obteniendo productos mejor calificados...');
      print('  - Rating mínimo: $minRating');
      print('  - Límite: $limit');

      final products = await getProducts(soloDisponibles: true);

      // Filtrar por rating mínimo
      final filteredProducts = products.where((product) {
        final metadata = product['metadata'] as Map<String, dynamic>?;
        final rating = metadata?['rating_promedio'] ?? 0.0;
        return rating >= minRating;
      }).toList();

      // Ordenar por rating descendente
      filteredProducts.sort((a, b) {
        final metadataA = a['metadata'] as Map<String, dynamic>?;
        final metadataB = b['metadata'] as Map<String, dynamic>?;
        final ratingA = metadataA?['rating_promedio'] ?? 0.0;
        final ratingB = metadataB?['rating_promedio'] ?? 0.0;
        return ratingB.compareTo(ratingA);
      });

      final topProducts = filteredProducts.take(limit).toList();
      print('✅ ${topProducts.length} productos mejor calificados obtenidos');

      return topProducts;
    } catch (e) {
      print('❌ Error obteniendo productos mejor calificados: $e');
      rethrow;
    }
  }

  /// Busca productos por texto (búsqueda en servidor con normalización fonética)
  ///
  /// [searchText] - Texto a buscar (búsqueda fonética en múltiples campos)
  /// [idCategoria] - Categoría opcional para filtrar
  /// [limit] - Cantidad máxima de resultados (default: 100)
  Future<List<Map<String, dynamic>>> searchProducts(
    String searchText, {
    int? idCategoria,
    int limit = 100,
  }) async {
    try {
      print('🔎 Buscando productos: "$searchText"');

      // La búsqueda ahora se hace en el servidor con normalización fonética
      final products = await getProducts(
        idCategoria: idCategoria,
        soloDisponibles: true,
        searchQuery: searchText.trim(),
        limit: limit,
      );

      print('✅ ${products.length} productos encontrados');

      return products;
    } catch (e) {
      print('❌ Error buscando productos: $e');
      rethrow;
    }
  }

  /// Obtiene productos con bajo stock
  ///
  /// [maxStock] - Stock máximo para considerar "bajo" (default: 10)
  Future<List<Map<String, dynamic>>> getLowStockProducts({
    int maxStock = 10,
  }) async {
    try {
      print('📦 Obteniendo productos con bajo stock...');
      print('  - Stock máximo: $maxStock');

      final products = await getProducts(soloDisponibles: true);

      // Filtrar por stock bajo
      final lowStockProducts = products.where((product) {
        final stock = product['stock_disponible'] ?? 0;
        return stock > 0 && stock <= maxStock;
      }).toList();

      // Ordenar por stock ascendente
      lowStockProducts.sort((a, b) {
        final stockA = a['stock_disponible'] ?? 0;
        final stockB = b['stock_disponible'] ?? 0;
        return stockA.compareTo(stockB);
      });

      print('✅ ${lowStockProducts.length} productos con bajo stock');

      return lowStockProducts;
    } catch (e) {
      print('❌ Error obteniendo productos con bajo stock: $e');
      rethrow;
    }
  }

  /// Obtiene el estado de los TPVs de una tienda (abierto/cerrado)
  ///
  /// [storeId] - ID de la tienda
  ///
  /// Retorna una lista de TPVs con su estado:
  /// - id_tpv: ID del TPV
  /// - denominacion_tpv: Nombre del TPV
  /// - esta_abierto: true si tiene turno abierto, false si está cerrado
  /// - fecha_apertura: Fecha de apertura del último turno
  /// - fecha_cierre: Fecha de cierre del último turno (null si está abierto)
  Future<List<Map<String, dynamic>>> getStoreTPVsStatus(int storeId) async {
    try {
      print('🏪 Obteniendo estado de TPVs de tienda $storeId...');

      final response = await _supabase.rpc(
        'get_tienda_estado_tpvs',
        params: {'id_tienda_param': storeId},
      );

      final tpvs = List<Map<String, dynamic>>.from(response);

      final abiertos = tpvs.where((tpv) => tpv['esta_abierto'] == true).length;
      final cerrados = tpvs.length - abiertos;

      print('✅ ${tpvs.length} TPVs obtenidos');
      print('  - Abiertos: $abiertos');
      print('  - Cerrados: $cerrados');

      return tpvs;
    } catch (e) {
      print('❌ Error obteniendo estado de TPVs: $e');
      rethrow;
    }
  }

  /// Obtiene estadísticas de productos por tienda
  Future<Map<String, dynamic>> getStoreStatistics(int storeId) async {
    try {
      print('📊 Obteniendo estadísticas de tienda $storeId...');

      final products = await getProductsByStore(storeId);

      final totalProducts = products.length;
      final productsWithStock = products
          .where((p) => (p['tiene_stock'] ?? false))
          .length;
      final totalStock = products.fold<num>(
        0,
        (sum, p) => sum + (p['stock_disponible'] ?? 0),
      );

      final ratings = products
          .map((p) {
            final metadata = p['metadata'] as Map<String, dynamic>?;
            return metadata?['rating_promedio'] ?? 0.0;
          })
          .where((r) => r > 0)
          .toList();

      final averageRating = ratings.isEmpty
          ? 0.0
          : ratings.reduce((a, b) => a + b) / ratings.length;

      final stats = {
        'total_productos': totalProducts,
        'productos_con_stock': productsWithStock,
        'stock_total': totalStock,
        'rating_promedio_tienda': averageRating,
        'productos_calificados': ratings.length,
      };

      print('✅ Estadísticas obtenidas:');
      print('  - Total productos: $totalProducts');
      print('  - Con stock: $productsWithStock');
      print('  - Stock total: $totalStock');
      print('  - Rating promedio: ${averageRating.toStringAsFixed(1)}');

      return stats;
    } catch (e) {
      print('❌ Error obteniendo estadísticas: $e');
      rethrow;
    }
  }

  /// Obtiene productos recomendados basados en rating y stock
  Future<List<Map<String, dynamic>>> getRecommendedProducts({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      print('💡 Obteniendo productos recomendados...');

      print('  - Limit: $limit, Offset: $offset');

      final userId = _supabase.auth.currentUser?.id;

      final response = await _supabase.rpc(
        'fn_get_productos_recomendados_v2',
        params: {
          'id_usuario_param': userId,
          'limit_param': limit,
          'offset_param': offset,
        },
      );

      final products = List<Map<String, dynamic>>.from(response);
      print('✅ ${products.length} productos recomendados');
      return products;
    } catch (e) {
      print('❌ Error obteniendo productos recomendados: $e');
      rethrow;
    }
  }
}

/// Extensión para facilitar el acceso a metadatos
extension ProductMetadata on Map<String, dynamic> {
  /// Obtiene el metadata del producto
  Map<String, dynamic>? get metadata =>
      this['metadata'] as Map<String, dynamic>?;

  /// Obtiene el nombre de la tienda
  String get storeName => metadata?['denominacion_tienda'] ?? 'Sin tienda';

  /// Obtiene el ID de la tienda
  int? get storeId => metadata?['id_tienda'];

  /// Obtiene el rating promedio
  double get rating => (metadata?['rating_promedio'] ?? 0.0).toDouble();

  /// Obtiene el total de ratings
  int get totalRatings => metadata?['total_ratings'] ?? 0;

  /// Indica si es un producto elaborado
  bool get isElaborado => metadata?['es_elaborado'] ?? false;

  /// Indica si es un servicio
  bool get isServicio => metadata?['es_servicio'] ?? false;

  /// Indica si tiene stock disponible
  bool get hasStock => this['tiene_stock'] ?? false;

  /// Obtiene el stock disponible
  num get stockDisponible => this['stock_disponible'] ?? 0;
}
