import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';
import 'user_preferences_service.dart';
import 'supabase_retry_helper.dart';
import 'offline_database_service.dart';

class ProductService {
  static final ProductService _instance = ProductService._internal();
  factory ProductService() => _instance;
  ProductService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final UserPreferencesService _preferencesService = UserPreferencesService();

  /// Fetch products by category from Supabase and group them by subcategory.
  /// [forceLocal]: UI full-offline / offline debe forzar SQLite aunque el flag
  /// `offline_mode` esté temporalmente en false durante un sync explícito.
  Future<Map<String, List<Product>>> getProductsByCategory(
    int categoryId, {
    bool forceLocal = false,
  }) async {
    final useLocal =
        forceLocal || await _preferencesService.isOfflineModeEnabled();
    if (useLocal) {
      return _getProductsByCategoryLocal(categoryId);
    }

    try {
      // Get store ID from preferences
      final workerProfile = await _preferencesService.getWorkerProfile();
      final idTienda = workerProfile['idTienda'] as int?;
      final idTpv = workerProfile['idTpv'] as int?;

      if (idTienda == null) {
        throw Exception(
          'No se encontró el ID de la tienda en las preferencias',
        );
      }

      debugPrint(
        '🏪 Obteniendo productos para categoría ID: $categoryId, tienda ID: $idTienda tpv: $idTpv',
      );

      // Call the RPC function to get products by category
      final response = await withNetworkRetry(
        () => _supabase.rpc(
          'get_productos_by_categoria_tpv_search_meta',
          params: {
            'id_categoria_param': categoryId,
            'id_tienda_param': idTienda,
            'id_tpv_param': idTpv,
            'solo_disponibles_param': false,
            'text_search': null,
          },
        ),
        description: 'Cargar productos por categoría',
      );

      if (response == null) {
        throw Exception('No se recibieron datos de productos');
      }

      // Catálogo dual: a los productos de barra se suman los platos de las
      // cocinas ligadas a este TPV. Un plato que se cocina en la "Cocina
      // caliente" no tiene inventario en el almacén de la barra, así que la
      // consulta de arriba no lo ve.
      final productosCocina = await _fetchProductosCocina(
        categoryId: categoryId,
        idTienda: idTienda,
        idTpv: idTpv,
      );

      final List<dynamic> todos = [...response, ...productosCocina];

      debugPrint(
        '📦 Respuesta de productos: ${response.length} de barra + '
        '${productosCocina.length} de cocina = ${todos.length}',
      );

      // Check if response is empty
      if (todos.isEmpty) {
        debugPrint('📭 No hay productos en esta categoría');
        throw Exception('No hay productos disponibles en esta categoría');
      }

      debugPrint('🔍 Estructura de respuesta: ${todos[0]}');

      // Group products by subcategory_nombre
      final Map<String, List<Product>> productsBySubcategory = {};

      for (final item in todos) {
        final productData = item as Map<String, dynamic>;
        debugPrint('📝 Procesando producto: ${productData['denominacion']}');

        // Extract subcategory name
        final subcategoryName =
            productData['subcategoria_nombre'] as String? ?? 'Sin subcategoría';

        // Convert Supabase response to Product model
        final product = _convertSupabaseToProduct(productData);

        // Group by subcategory
        if (!productsBySubcategory.containsKey(subcategoryName)) {
          productsBySubcategory[subcategoryName] = [];
        }
        productsBySubcategory[subcategoryName]!.add(product);
      }

      debugPrint('✅ Productos agrupados por subcategoría:');
      productsBySubcategory.forEach((subcategory, products) {
        debugPrint('   📂 $subcategory: ${products.length} productos');
      });

      return productsBySubcategory;
    } catch (e, stackTrace) {
      debugPrint('❌ Error obteniendo productos: $e');
      debugPrint('❌ Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Productos de una categoría desde SQLite (sin cargar todo el catálogo).
  Future<Map<String, List<Product>>> _getProductsByCategoryLocal(
    int categoryId,
  ) async {
    final rows = await OfflineDatabaseService().getProductsByCategory(
      categoryId.toString(),
    );

    if (rows.isEmpty) {
      // Fallback: mapa completo por si category_id no coincide en filas antiguas
      final offlineData = await _preferencesService.getOfflineData();
      final productsData = offlineData?['products'];
      if (productsData is Map) {
        final categoryProducts = productsData[categoryId.toString()];
        if (categoryProducts is List && categoryProducts.isNotEmpty) {
          return _groupOfflineProductMaps(
            categoryProducts
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList(),
          );
        }
      }
      debugPrint(
        '⚠️ No hay productos locales para categoría $categoryId',
      );
      return {};
    }

    return _groupOfflineProductMaps(rows);
  }

  Map<String, List<Product>> _groupOfflineProductMaps(
    List<Map<String, dynamic>> categoryProducts,
  ) {
    final products = <String, List<Product>>{};
    for (final prodData in categoryProducts) {
      final subcategory = prodData['subcategoria'] as String? ?? 'General';
      final product = Product(
        id: (prodData['id'] as num?)?.toInt() ?? 0,
        denominacion: prodData['denominacion'] as String? ?? 'Sin nombre',
        descripcion: prodData['descripcion'] as String?,
        sku: prodData['sku'] as String?,
        foto: prodData['foto'] as String?,
        precio: (prodData['precio'] as num?)?.toDouble() ?? 0.0,
        cantidad: prodData['cantidad'] as num? ?? 0,
        categoria: prodData['categoria'] as String? ?? '',
        esRefrigerado: false,
        esFragil: false,
        esPeligroso: false,
        esVendible: true,
        esComprable: true,
        esInventariable: true,
        esPorLotes: false,
        esElaborado: false,
        esServicio: false,
        variantes: [],
      );
      products.putIfAbsent(subcategory, () => []).add(product);
    }
    return products;
  }

  /// Global product search by text (denominacion/descripcion) with optional category filter.
  Future<List<Product>> searchProducts({
    required String query,
    int? categoryId,
    bool soloDisponibles = false,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    try {
      final workerProfile = await _preferencesService.getWorkerProfile();
      final idTienda = workerProfile['idTienda'] as int?;
      final idTpv = workerProfile['idTpv'] as int?;

      if (idTienda == null || idTpv == null) {
        throw Exception('No se encontraron IDs de tienda/TPV en preferencias');
      }

      debugPrint(
        '🔎 Buscando productos: "$trimmed" tienda: $idTienda tpv: $idTpv cat: $categoryId',
      );

      final response = await withNetworkRetry(
        () => _supabase.rpc(
          'get_productos_by_categoria_tpv_search_meta',
          params: {
            'id_categoria_param': categoryId,
            'id_tienda_param': idTienda,
            'id_tpv_param': idTpv,
            'solo_disponibles_param': soloDisponibles,
            'text_search': trimmed,
          },
        ),
        description: 'Buscar productos',
      );

      if (response == null) return [];

      // Catálogo dual también en la búsqueda: si el vendedor busca "bistec"
      // debe encontrarlo aunque se cocine en otra estación.
      final productosCocina = await _fetchProductosCocina(
        categoryId: categoryId,
        idTienda: idTienda,
        idTpv: idTpv,
        textSearch: trimmed,
        soloDisponibles: soloDisponibles,
      );

      final results =
          [...(response as List), ...productosCocina]
              .map(
                (item) =>
                    _convertSupabaseToProduct(item as Map<String, dynamic>),
              )
              .toList();

      debugPrint('✅ Resultados búsqueda: ${results.length}');
      return results;
    } catch (e, stack) {
      debugPrint('❌ Error en búsqueda global: $e');
      debugPrint('❌ Stack trace: $stack');
      rethrow;
    }
  }

  /// Platos que este TPV puede vender por vía de cocina.
  ///
  /// Llama a `fn_productos_cocina_tpv`, que devuelve las mismas columnas que el
  /// catálogo de barra para poder concatenar sin transformar nada. Ya excluye
  /// los productos con stock en el almacén del TPV, así que no hay duplicados.
  ///
  /// Ante cualquier error devuelve lista vacía en lugar de propagar: si la
  /// tienda no usa cocinas o el `09` todavía no está aplicado, el catálogo de
  /// barra debe seguir funcionando igual.
  Future<List<dynamic>> _fetchProductosCocina({
    required int? categoryId,
    required int idTienda,
    required int? idTpv,
    String? textSearch,
    bool soloDisponibles = false,
  }) async {
    if (idTpv == null) return const [];

    try {
      final response = await _supabase.rpc(
        'fn_productos_cocina_tpv',
        params: {
          'id_categoria_param': categoryId,
          'id_tienda_param': idTienda,
          'id_tpv_param': idTpv,
          'text_search': textSearch,
          'solo_disponibles_param': soloDisponibles,
        },
      );

      if (response is List) return response;
      return const [];
    } catch (e) {
      debugPrint('⚠️ Catálogo de cocina no disponible: $e');
      return const [];
    }
  }

  /// Convert Supabase product response to Product model
  Product _convertSupabaseToProduct(Map<String, dynamic> data) {
    final metadata = data['metadata'] as Map<String, dynamic>?;

    return Product(
      id: data['id_producto'] as int? ?? 0,
      denominacion: data['denominacion'] as String? ?? 'Sin nombre',
      descripcion: data['descripcion'] as String?,
      sku: data['sku'] as String?,
      foto:
          data['imagen'] ??
          _generateProductImage(data['denominacion'] as String? ?? 'producto'),
      precio: (data['precio_venta'] as num?)?.toDouble() ?? 0.0,
      cantidad:
          data['tiene_stock']
              ? (data['stock_disponible'] as num?) ?? 0
              : 0, // Preserve original type (int or double)
      esRefrigerado: data['es_refrigerado'] as bool? ?? false,
      esFragil: data['es_fragil'] as bool? ?? false,
      esPeligroso: false, // Default value
      esVendible: data['es_vendible'] as bool? ?? true,
      esComprable: true, // Default value
      esInventariable: true, // Default value
      esPorLotes: false, // Default value
      esElaborado:
          (metadata != null && metadata['es_elaborado'] != null)
              ? metadata['es_elaborado'] as bool
              : data['es_elaborado'] as bool? ?? false,
      esServicio:
          (metadata != null && metadata['es_servicio'] != null)
              ? metadata['es_servicio'] as bool
              : data['es_servicio'] as bool? ?? false,
      esPaquete:
          (metadata != null && metadata['es_paquete'] != null)
              ? metadata['es_paquete'] as bool
              : data['es_paquete'] as bool? ?? false,
      categoria: data['categoria_nombre'] as String? ?? 'Sin categoría',
      variantes: [], // Empty variants for now
      reservadoCarnaval:
          (metadata != null && metadata['reservado_carnaval'] != null)
              ? metadata['reservado_carnaval'] as num
              : 0,
      // Datos de cocina: solo vienen de fn_productos_cocina_tpv. Un producto
      // de barra los deja en null y se comporta igual que siempre.
      idCocina: (metadata?['id_cocina'] as num?)?.toInt(),
      cocina: metadata?['cocina'] as String?,
      idAlmacenCocina: (metadata?['id_almacen_cocina'] as num?)?.toInt(),
      impresoraCocina: metadata?['impresora'] as String?,
      modoElaboracion: metadata?['modo_elaboracion'] as String?,
      ilimitado: metadata?['ilimitado'] as bool? ?? false,
    );
  }

  /// Generate a random product image from Unsplash based on product name
  String _generateProductImage(String productName) {
    // Create a hash from the product name for consistency
    final hash = productName.toLowerCase().hashCode.abs();
    final imageId = 300 + (hash % 700); // Range from 300 to 999

    return 'https://images.unsplash.com/photo-${imageId.toString().padLeft(10, '0')}?w=300&h=300&fit=crop&auto=format&q=80&ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxwaG90by1wYWdlfHx8fGVufDB8fHx8fA%3D%3D';
  }
}
