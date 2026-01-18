import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';
import 'user_preferences_service.dart';

class ProductService {
  static final ProductService _instance = ProductService._internal();
  factory ProductService() => _instance;
  ProductService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final UserPreferencesService _preferencesService = UserPreferencesService();

  /// Fetch products by category from Supabase and group them by subcategory
  Future<Map<String, List<Product>>> getProductsByCategory(
    int categoryId,
  ) async {
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
      final response = await _supabase.rpc(
        'get_productos_by_categoria_tpv_search_meta',
        params: {
          'id_categoria_param': categoryId,
          'id_tienda_param': idTienda,
          'id_tpv_param': idTpv,
          'solo_disponibles_param': false,
          'text_search': null,
        },
      );

      if (response == null) {
        throw Exception('No se recibieron datos de productos');
      }

      debugPrint(
        '📦 Respuesta de productos: ${response.length} productos encontrados',
      );

      // Check if response is empty
      if (response.isEmpty) {
        debugPrint('📭 No hay productos en esta categoría');
        throw Exception('No hay productos disponibles en esta categoría');
      }

      debugPrint('🔍 Estructura de respuesta: ${response[0]}');

      // Group products by subcategory_nombre
      final Map<String, List<Product>> productsBySubcategory = {};

      for (final item in response) {
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

      final response = await _supabase.rpc(
        'get_productos_by_categoria_tpv_search_meta',
        params: {
          'id_categoria_param': categoryId,
          'id_tienda_param': idTienda,
          'id_tpv_param': idTpv,
          'solo_disponibles_param': soloDisponibles,
          'text_search': trimmed,
        },
      );

      if (response == null) return [];

      final results =
          (response as List)
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

  /// Convert Supabase product response to Product model
  Product _convertSupabaseToProduct(Map<String, dynamic> data) {
    return Product(
      id: data['id_producto'] as int? ?? 0,
      denominacion: data['denominacion'] as String? ?? 'Sin nombre',
      descripcion: data['descripcion'] as String?,
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
          (data['metadata'] != null && data['metadata']['es_elaborado'] != null)
              ? data['metadata']['es_elaborado'] as bool
              : data['es_elaborado'] as bool? ?? false,
      esServicio:
          (data['metadata'] != null && data['metadata']['es_servicio'] != null)
              ? data['metadata']['es_servicio'] as bool
              : data['es_servicio'] as bool? ?? false,
      categoria: data['categoria_nombre'] as String? ?? 'Sin categoría',
      variantes: [], // Empty variants for now
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
