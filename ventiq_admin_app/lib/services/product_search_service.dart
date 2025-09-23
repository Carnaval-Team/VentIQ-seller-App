import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/user_preferences_service.dart';

/// Servicio centralizado para búsqueda paginada de productos
class ProductSearchService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static const int defaultPageSize = 20;

  /// Busca productos con paginación básica
  static Future<ProductSearchResult> searchProducts({
    String? searchQuery,
    int page = 1,
    int pageSize = defaultPageSize,
    ProductSearchType searchType = ProductSearchType.all,
    bool requireInventory = false, // Nuevo parámetro para distinguir operaciones
    int? locationId, // Nuevo parámetro para filtrar por ubicación
  }) async {
    try {
      print('🔍 Buscando productos: query="$searchQuery", page=$page, type=$searchType, requireInventory=$requireInventory, locationId=$locationId');
      
      if (requireInventory) {
        // Para operaciones que requieren inventario existente (extracciones, transferencias)
        return await _searchProductsWithInventory(searchQuery, page, pageSize, searchType, locationId);
      } else {
        // Para operaciones que no requieren inventario (recepciones, productos generales)
        return await _searchAllProducts(searchQuery, page, pageSize, searchType);
      }
      
    } catch (e) {
      print('❌ Error en búsqueda de productos: $e');
      return ProductSearchResult.empty();
    }
  }

  static Future<ProductSearchResult> _searchProductsWithInventory(
    String? searchQuery,
    int page,
    int pageSize,
    ProductSearchType searchType,
    int? locationId,
  ) async {
    // Usar función RPC existente fn_listar_inventario_productos_paged
    final response = await _supabase.rpc('fn_listar_inventario_productos_paged', params: {
      'p_busqueda': searchQuery,
      'p_es_vendible': _getElaboradoFilter(searchType),
      'p_pagina': page,
      'p_limite': pageSize,
      'p_id_tienda': await _getUserStoreId(),
      'p_mostrar_sin_stock': true,
      'p_id_ubicacion': locationId, // Nuevo parámetro para filtrar por ubicación
      // Otros parámetros opcionales como null
      'p_clasificacion_abc': null,
      'p_con_stock_minimo': null,
      'p_es_inventariable': null,
      'p_id_almacen': null,
      'p_id_categoria': null,
      'p_id_opcion_variante': null,
      'p_id_presentacion': null,
      'p_id_producto': null,
      'p_id_proveedor': null,
      'p_id_subcategoria': null,
      'p_origen_cambio': null,
    });
    
    // La función retorna una estructura con productos y metadatos
    final data = response is List ? response : [response];
    final products = List<Map<String, dynamic>>.from(data);
    
    // Filtrar por tipo de producto si es necesario (ya que fn_listar_inventario_productos_paged no tiene filtro es_elaborado directo)
    final filteredProducts = _filterByProductType(products, searchType);
    
    // Agrupar productos duplicados por ID
    final uniqueProducts = _groupDuplicateProducts(filteredProducts);
    
    print('✅ Productos encontrados: ${uniqueProducts.length} (${filteredProducts.length} registros originales)');
    
    return ProductSearchResult(
      products: uniqueProducts,
      totalCount: uniqueProducts.length, // Aproximado, la función no retorna count total
      currentPage: page,
      pageSize: pageSize,
      hasNextPage: uniqueProducts.length == pageSize,
      hasPreviousPage: page > 1,
    );
  }

  static Future<ProductSearchResult> _searchAllProducts(
    String? searchQuery,
    int page,
    int pageSize,
    ProductSearchType searchType,
  ) async {
    // Para búsqueda con texto, necesitamos cargar todo y filtrar (limitación de la función RPC)
    if (searchQuery != null && searchQuery.isNotEmpty) {
      return await _searchAllProductsWithTextFilter(searchQuery, page, pageSize, searchType);
    }
    
    // Para búsqueda sin texto, podemos simular paginación más eficiente
    final response = await _supabase.rpc('get_productos_completos_by_tienda_optimized', params: {
      'id_tienda_param': await _getUserStoreId(),
      'id_categoria_param': null,
      'solo_disponibles_param': false,
    });
    
    if (response == null) {
      return ProductSearchResult.empty();
    }
    
    final productosData = response['productos'] as List<dynamic>? ?? [];
    List<Map<String, dynamic>> products = List<Map<String, dynamic>>.from(productosData);
    
    // Filtrar por tipo de producto
    final filteredProducts = _filterByProductType(products, searchType);
    
    // Aplicar paginación
    final startIndex = (page - 1) * pageSize;
    final endIndex = startIndex + pageSize;
    final paginatedProducts = filteredProducts.skip(startIndex).take(pageSize).toList();
    
    print('✅ Productos encontrados: ${paginatedProducts.length}/${filteredProducts.length}');
    
    return ProductSearchResult(
      products: paginatedProducts,
      totalCount: filteredProducts.length,
      currentPage: page,
      pageSize: pageSize,
      hasNextPage: endIndex < filteredProducts.length,
      hasPreviousPage: page > 1,
    );
  }

  static Future<ProductSearchResult> _searchAllProductsWithTextFilter(
    String searchQuery,
    int page,
    int pageSize,
    ProductSearchType searchType,
  ) async {
    // Para búsqueda con texto, cargamos todo y filtramos (limitación actual)
    final response = await _supabase.rpc('get_productos_completos_by_tienda_optimized', params: {
      'id_tienda_param': await _getUserStoreId(),
      'id_categoria_param': null,
      'solo_disponibles_param': false,
    });
    
    if (response == null) {
      return ProductSearchResult.empty();
    }
    
    final productosData = response['productos'] as List<dynamic>? ?? [];
    List<Map<String, dynamic>> products = List<Map<String, dynamic>>.from(productosData);
    
    // Aplicar filtro de búsqueda por texto
    products = products.where((product) {
      final denominacion = (product['denominacion'] ?? '').toString().toLowerCase();
      final sku = (product['sku'] ?? '').toString().toLowerCase();
      final nombreProducto = (product['nombre_producto'] ?? '').toString().toLowerCase();
      final query = searchQuery.toLowerCase();
      
      return denominacion.contains(query) || 
             sku.contains(query) || 
             nombreProducto.contains(query);
    }).toList();
    
    // Filtrar por tipo de producto
    final filteredProducts = _filterByProductType(products, searchType);
    
    // Aplicar paginación
    final startIndex = (page - 1) * pageSize;
    final endIndex = startIndex + pageSize;
    final paginatedProducts = filteredProducts.skip(startIndex).take(pageSize).toList();
    
    print('✅ Productos encontrados: ${paginatedProducts.length}/${filteredProducts.length}');
    
    return ProductSearchResult(
      products: paginatedProducts,
      totalCount: filteredProducts.length,
      currentPage: page,
      pageSize: pageSize,
      hasNextPage: endIndex < filteredProducts.length,
      hasPreviousPage: page > 1,
    );
  }

  static dynamic _getElaboradoFilter(ProductSearchType? searchType) {
    if (searchType == ProductSearchType.elaborated) {
      return true;
    } else if (searchType == ProductSearchType.simple) {
      return false;
    } else {
      return null;
    }
  }

  static List<Map<String, dynamic>> _filterByProductType(List<Map<String, dynamic>> products, ProductSearchType? searchType) {
    if (searchType == null) {
      return products;
    }

    if (searchType == ProductSearchType.elaborated) {
      return products.where((product) => product['es_elaborado'] == true).toList();
    } else if (searchType == ProductSearchType.simple) {
      return products.where((product) => product['es_elaborado'] == false).toList();
    } else {
      return products;
    }
  }

  static List<Map<String, dynamic>> _groupDuplicateProducts(List<Map<String, dynamic>> products) {
    if (products.isEmpty) return products;
    
    final Map<int, Map<String, dynamic>> groupedProducts = {};
    
    for (final product in products) {
      final productId = product['id'] as int?;
      if (productId == null) continue;
      
      if (groupedProducts.containsKey(productId)) {
        // Producto ya existe, consolidar información de stock
        final existing = groupedProducts[productId]!;
        
        // Sumar stocks disponibles
        final existingStock = (existing['stock_disponible'] as num?)?.toDouble() ?? 0.0;
        final currentStock = (product['stock_disponible'] as num?)?.toDouble() ?? 0.0;
        existing['stock_disponible'] = existingStock + currentStock;
        
        // Sumar stocks reservados
        final existingReserved = (existing['stock_reservado'] as num?)?.toDouble() ?? 0.0;
        final currentReserved = (product['stock_reservado'] as num?)?.toDouble() ?? 0.0;
        existing['stock_reservado'] = existingReserved + currentReserved;
        
        // Sumar stocks actuales
        final existingActual = (existing['stock_actual'] as num?)?.toDouble() ?? 0.0;
        final currentActual = (product['stock_actual'] as num?)?.toDouble() ?? 0.0;
        existing['stock_actual'] = existingActual + currentActual;
        
        // Mantener el resto de información del primer registro
      } else {
        // Primer registro de este producto
        groupedProducts[productId] = Map<String, dynamic>.from(product);
      }
    }
    
    return groupedProducts.values.toList();
  }

  static Future<int> _getUserStoreId() async {
    try {
      final userPrefs = UserPreferencesService();
      final storeId = await userPrefs.getIdTienda();
      if (storeId == null) {
        throw Exception('No se encontró ID de tienda para el usuario');
      }
      return storeId;
    } catch (e) {
      print('Error obteniendo ID de tienda: $e');
      throw Exception('Error obteniendo información de tienda: $e');
    }
  }
}

/// Tipos de búsqueda de productos
enum ProductSearchType {
  all,        // Todos los productos
  withStock,  // Productos con información de inventario
  elaborated, // Solo productos elaborados
  simple,     // Solo productos simples (no elaborados)
}

/// Resultado de búsqueda paginada
class ProductSearchResult {
  final List<Map<String, dynamic>> products;
  final int totalCount;
  final int currentPage;
  final int pageSize;
  final bool hasNextPage;
  final bool hasPreviousPage;
  
  ProductSearchResult({
    required this.products,
    required this.totalCount,
    required this.currentPage,
    required this.pageSize,
    required this.hasNextPage,
    required this.hasPreviousPage,
  });

  factory ProductSearchResult.empty() {
    return ProductSearchResult(
      products: [],
      totalCount: 0,
      currentPage: 1,
      pageSize: 0,
      hasNextPage: false,
      hasPreviousPage: false,
    );
  }
}
