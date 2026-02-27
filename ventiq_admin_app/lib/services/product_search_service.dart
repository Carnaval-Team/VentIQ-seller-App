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
    int? supplierId, // Nuevo parámetro para filtrar por proveedor
  }) async {
    try {
      print('🔍 Buscando productos: query="$searchQuery", page=$page, type=$searchType, requireInventory=$requireInventory, locationId=$locationId, supplierId=$supplierId');
      
      if (requireInventory) {
        // Para operaciones que requieren inventario existente (extracciones, transferencias)
        return await _searchProductsWithInventory(searchQuery, page, pageSize, searchType, locationId, supplierId);
      } else {
        // Para operaciones que no requieren inventario (recepciones, productos generales)
        return await _searchAllProducts(searchQuery, page, pageSize, searchType, supplierId);
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
    int? supplierId,
  ) async {
    print('\n📦 USANDO RPC: fn_listar_inventario_productos_paged2_with_supplier');
    print('   ├─ Razón: requireInventory=true (operación requiere inventario existente)');
    print('   ├─ searchQuery: $searchQuery');
    print('   ├─ page: $page, pageSize: $pageSize');
    print('   ├─ locationId: $locationId');
    print('   ├─ supplierId: $supplierId');
    print('   └─ Casos de uso: Extracciones, Transferencias, Operaciones con inventario');
    
    // Usar función RPC con soporte para filtrado por proveedor
    final response = await _supabase.rpc('fn_listar_inventario_productos_paged2_grouped', params: {
      'p_pagina': page,
      'p_limite': pageSize,
      'p_id_tienda': await _getUserStoreId(),
      'p_id_almacen': null,
      'p_id_ubicacion': locationId,
      'p_id_producto': null,
      'p_id_variante': null,
      'p_id_opcion_variante': null,
      'p_id_presentacion': null,
      'p_id_categoria': null,
      'p_id_subcategoria': null,
      'p_origen_cambio': null,
      'p_es_vendible': true,
      'p_es_inventariable': null,
      'p_clasificacion_abc': null,
      'p_mostrar_sin_stock': true,
      'p_con_stock_minimo': null,
      'p_busqueda': searchQuery,
    });
    
    print('   📡 Respuesta RPC tipo: ${response.runtimeType}');
    print('   📡 Respuesta RPC: $response');
    
    // La función retorna una lista de registros
    List<Map<String, dynamic>> products = [];
    
    if (response is List) {
      products = List<Map<String, dynamic>>.from(response);
      print('✅ Respuesta es List con ${products.length} elementos');
      if (products.isNotEmpty) {
        print('📋 Primer producto: ${products.first.keys.toList()}');
      }
    } else if (response is Map) {
      // Si es un mapa único, convertir a lista
      products = [Map<String, dynamic>.from(response)];
      print('✅ Respuesta es Map, convertida a lista con 1 elemento');
      print('📋 Campos del mapa: ${response.keys.toList()}');
    } else {
      print('❌ Respuesta inesperada: ${response.runtimeType}');
      return ProductSearchResult.empty();
    }
    
    // Filtrar por tipo de producto si es necesario
    final filteredProducts = _filterByProductType(products, searchType);
    
    // Agrupar productos duplicados por ID
    // final uniqueProducts = _groupDuplicateProducts(filteredProducts);
    
    print('✅ Productos2 encontrados: ${filteredProducts.length} (${filteredProducts.length} registros originales)');
    
    return ProductSearchResult(
      products: filteredProducts,
      totalCount: filteredProducts.length, // Aproximado, la función no retorna count total
      currentPage: page,
      pageSize: pageSize,
      hasNextPage: filteredProducts.length == pageSize,
      hasPreviousPage: page > 1,
    );
  }

  static Future<ProductSearchResult> _searchAllProducts(
    String? searchQuery,
    int page,
    int pageSize,
    ProductSearchType searchType,
    int? supplierId,
  ) async {
    // Para búsqueda con texto, necesitamos cargar todo y filtrar (limitación de la función RPC)
    if (searchQuery != null && searchQuery.isNotEmpty) {
      print('\n📦 USANDO RPC: get_productos_completos_by_tienda_with_supplier (CON FILTRO DE TEXTO)');
      print('   ├─ Razón: requireInventory=false + searchQuery no vacío');
      print('   ├─ searchQuery: "$searchQuery"');
      print('   ├─ supplierId: $supplierId');
      print('   └─ Casos de uso: Búsqueda de productos por nombre/SKU/descripción');
      return await _searchAllProductsWithTextFilter(searchQuery, page, pageSize, searchType, supplierId);
    }
    
    print('\n📦 USANDO RPC: get_productos_completos_by_tienda_with_supplier (SIN FILTRO DE TEXTO)');
    print('   ├─ Razón: requireInventory=false + searchQuery vacío');
    print('   ├─ page: $page, pageSize: $pageSize');
    print('   ├─ supplierId: $supplierId');
    print('   └─ Casos de uso: Recepciones, Búsqueda general de productos');
    
    // Para búsqueda sin texto, podemos simular paginación más eficiente
    final response = await _supabase.rpc('get_productos_completos_by_tienda_optimized_provider', params: {
      'id_tienda_param': await _getUserStoreId(),
      'id_categoria_param': null,
      'solo_disponibles_param': false,
      'id_proveedor_param': supplierId,
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
    
    print('   ✅ Productos encontrados (sin filtro de texto): ${paginatedProducts.length}/${filteredProducts.length}');
    
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
    int? supplierId,
  ) async {
    print('   📡 Ejecutando búsqueda con filtro de texto: "$searchQuery"');
    
    // Para búsqueda con texto, cargamos todo y filtramos (limitación actual)
    final response = await _supabase.rpc('get_productos_completos_by_tienda_optimized_provider', params: {
      'id_tienda_param': await _getUserStoreId(),
      'id_categoria_param': null,
      'solo_disponibles_param': false,
      'id_proveedor_param': supplierId,
    });
    
    if (response == null) {
      return ProductSearchResult.empty();
    }
    
    final productosData = response['productos'] as List<dynamic>? ?? [];
    List<Map<String, dynamic>> products = List<Map<String, dynamic>>.from(productosData);
    print('   Productos Encontrados: $products');
    
    // Aplicar filtro de búsqueda por texto
    final productosAntesDelFiltro = products.length;
    products = products.where((product) {
      final denominacion = (product['denominacion'] ?? '').toString().toLowerCase();
      final sku = (product['sku'] ?? '').toString().toLowerCase();
      final nombreProducto = (product['nombre_producto'] ?? '').toString().toLowerCase();
      final descripcion = (product['descripcion'] ?? '').toString().toLowerCase();
      final query = searchQuery.toLowerCase();
      
      return denominacion.contains(query) || 
             sku.contains(query) || 
             nombreProducto.contains(query) ||
             descripcion.contains(query);
    }).toList();
    
    print('   🔎 Filtro de texto aplicado: $productosAntesDelFiltro → ${products.length} productos');
    
    // Filtrar por tipo de producto
    final filteredProducts = _filterByProductType(products, searchType);
    
    // Aplicar paginación
    final startIndex = (page - 1) * pageSize;
    final endIndex = startIndex + pageSize;
    final paginatedProducts = filteredProducts.skip(startIndex).take(pageSize).toList();
    
    print('   ✅ Productos encontrados (con filtro de texto): ${paginatedProducts.length}/${filteredProducts.length}');
    
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
    if (searchType == null || searchType == ProductSearchType.all || searchType == ProductSearchType.withStock) {
      return products;
    }

    if (searchType == ProductSearchType.elaborated) {
      final filtered = products.where((product) {
        final esElaborado = _getFieldValue(product, ['es_elaborado'], false);
        return esElaborado == true;
      }).toList();
      print('🔍 Filtrados por elaborado: ${filtered.length}/${products.length}');
      return filtered;
    } else if (searchType == ProductSearchType.simple) {
      final filtered = products.where((product) {
        final esElaborado = _getFieldValue(product, ['es_elaborado'], false);
        return esElaborado == false;
      }).toList();
      print('🔍 Filtrados por simple: ${filtered.length}/${products.length}');
      return filtered;
    } else {
      return products;
    }
  }

  /// Obtiene un valor de un mapa buscando en múltiples claves posibles
  static dynamic _getFieldValue(Map<String, dynamic> map, List<String> possibleKeys, [dynamic defaultValue]) {
    for (final key in possibleKeys) {
      if (map.containsKey(key)) {
        return map[key];
      }
    }
    return defaultValue;
  }

  static List<Map<String, dynamic>> _groupDuplicateProducts(List<Map<String, dynamic>> products) {
    if (products.isEmpty) return products;
    
    final Map<dynamic, Map<String, dynamic>> groupedProducts = {};
    
    for (final product in products) {
      // Obtener el ID del producto - acepta 'id_producto' o 'id'
      final productId = _getFieldValue(product, ['id_producto', 'id']);
      
      if (productId == null) {
        print('⚠️ Producto sin ID: ${product.keys.toList()}');
        continue;
      }
      
      if (groupedProducts.containsKey(productId)) {
        // Producto ya existe, consolidar información de stock
        final existing = groupedProducts[productId]!;
        
        // Sumar stocks disponibles - acepta 'stock_disponible' o 'cantidad_final'
        final existingStock = (_getFieldValue(existing, ['stock_disponible', 'cantidad_final']) as num?)?.toDouble() ?? 0.0;
        final currentStock = (_getFieldValue(product, ['stock_disponible', 'cantidad_final']) as num?)?.toDouble() ?? 0.0;
        existing['stock_disponible'] = existingStock + currentStock;
        
        // Sumar stocks reservados
        final existingReserved = (_getFieldValue(existing, ['stock_reservado']) as num?)?.toDouble() ?? 0.0;
        final currentReserved = (_getFieldValue(product, ['stock_reservado']) as num?)?.toDouble() ?? 0.0;
        existing['stock_reservado'] = existingReserved + currentReserved;
        
        // Sumar stocks actuales (si existe este campo)
        final existingActual = (_getFieldValue(existing, ['stock_actual']) as num?)?.toDouble() ?? 0.0;
        final currentActual = (_getFieldValue(product, ['stock_actual']) as num?)?.toDouble() ?? 0.0;
        if (existingActual > 0 || currentActual > 0) {
          existing['stock_actual'] = existingActual + currentActual;
        }
        
        print('✅ Producto agrupado: $productId (stock consolidado)');
      } else {
        // Primer registro de este producto
        groupedProducts[productId] = Map<String, dynamic>.from(product);
        print('✅ Producto agregado: $productId');
      }
    }
    
    print('📊 Productos agrupados: ${groupedProducts.length}/${products.length}');
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
