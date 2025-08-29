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
  Future<Map<String, List<Product>>> getProductsByCategory(int categoryId) async {
    try {
      // Get store ID from preferences
      final workerProfile = await _preferencesService.getWorkerProfile();
      final idTienda = workerProfile['idTienda'] as int?;
      
      if (idTienda == null) {
        throw Exception('No se encontró el ID de la tienda en las preferencias');
      }

      debugPrint('🏪 Obteniendo productos para categoría ID: $categoryId, tienda ID: $idTienda');

      // Call the RPC function to get products by category
      final response = await _supabase.rpc(
        'get_productos_by_categoria',
        params: {
          'id_categoria_param': categoryId,
          'id_tienda_param': idTienda,
        },
      );

      if (response == null) {
        throw Exception('No se recibieron datos de productos');
      }

      debugPrint('📦 Respuesta de productos: ${response.length} productos encontrados');
      debugPrint('🔍 Estructura de respuesta: ${response[0]}');

      // Group products by subcategory_nombre
      final Map<String, List<Product>> productsBySubcategory = {};
      
      for (final item in response) {
        final productData = item as Map<String, dynamic>;
        debugPrint('📝 Procesando producto: ${productData['denominacion']}');
        
        // Extract subcategory name
        final subcategoryName = productData['subcategoria_nombre'] as String? ?? 'Sin subcategoría';
        
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

    } catch (e) {
      debugPrint('❌ Error obteniendo productos: $e');
      rethrow;
    }
  }

  /// Convert Supabase product response to Product model
  Product _convertSupabaseToProduct(Map<String, dynamic> data) {
    return Product(
      id: data['id_producto'] as int? ?? 0,
      denominacion: data['denominacion'] as String? ?? 'Sin nombre',
      descripcion: data['descripcion'] as String?,
      foto: data['imagen'] ?? _generateProductImage(data['denominacion'] as String? ?? 'producto'),
      precio: (data['precio_venta'] as num?)?.toDouble() ?? 0.0,
      cantidad: data['tiene_stock'] ? data['stock_disponible']:0, // Default stock since it's not in the response
      esRefrigerado: data['es_refrigerado'] as bool? ?? false,
      esFragil: data['es_fragil'] as bool? ?? false,
      esPeligroso: false, // Default value
      esVendible: data['es_vendible'] as bool? ?? true,
      esComprable: true, // Default value
      esInventariable: true, // Default value
      esPorLotes: false, // Default value
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
