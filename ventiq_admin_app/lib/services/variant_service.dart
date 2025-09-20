import '../models/variant.dart';
import '../models/product.dart';
import '../config/supabase_config.dart';
import '../services/user_preferences_service.dart';
import '../services/store_selector_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VariantService {
  static SupabaseClient get _supabase => Supabase.instance.client;
  static final _storeSelectorService = StoreSelectorService();

  // Get store ID helper method
  static Future<int?> _getStoreId() async {
    try {
      final storeId = _storeSelectorService.getSelectedStoreId();
      if (storeId != null) return storeId;
      
      // Initialize service if needed
      await _storeSelectorService.initialize();
      return _storeSelectorService.getSelectedStoreId();
    } catch (e) {
      print('Error getting store ID: $e');
      return null;
    }
  }

  static Future<List<Variant>> getVariants() async {
    try {
      final storeId = await _getStoreId();
      if (storeId == null) {
        return [];
      }

      // Use the correct RPC function that returns the proper structure
      final response = await _supabase.rpc('fn_listar_atributos_con_opciones', params: {
        'p_id_tienda': storeId,
      });

      if (response == null || response.isEmpty) {
        return [];
      }

      final List<dynamic> data = response as List<dynamic>;
      return data.map((item) => _parseVariantFromDatabase(item)).toList();
    } catch (e) {
      print('Error fetching variants from database: $e');
      return [];
    }
  }

  static Variant _parseVariantFromDatabase(Map<String, dynamic> data) {
    // Parse options from database format
    List<VariantOption> options = [];
    if (data['opciones'] != null) {
      final opcionesData = data['opciones'] as List<dynamic>;
      options = opcionesData.map((opcion) => VariantOption(
        id: opcion['id'] as int,
        idVariante: data['id'] as int,
        denominacion: opcion['valor'] ?? '',
        descripcion: null,
        valor: opcion['valor'] ?? '',
        color: null,
        imageUrl: null,
        createdAt: DateTime.tryParse(data['created_at'] ?? '') ?? DateTime.now(),
      )).toList();
    }

    return Variant(
      id: data['id'] as int,
      idSubCategoria: 0, // Not used in this context
      idAtributo: data['id'] as int,
      denominacion: data['denominacion'] ?? '',
      label: data['label'],
      descripcion: data['descripcion'],
      createdAt: DateTime.tryParse(data['created_at'] ?? '') ?? DateTime.now(),
      options: options,
    );
  }

  static Future<Variant> createVariant(Map<String, dynamic> variantData) async {
    try {
      final storeId = await _getStoreId();
      if (storeId == null) {
        throw Exception('No se encontró ID de tienda del usuario');
      }

      final userId = await UserPreferencesService().getUserId();
      if (userId == null) {
        throw Exception('No se encontró UUID del usuario');
      }

      final response = await _supabase.rpc('fn_crear_atributo', params: {
        'p_denominacion': variantData['denominacion'],
        'p_label': variantData['label'] ?? variantData['denominacion']?.toString().toLowerCase().replaceAll(' ', '_'),
        'p_descripcion': variantData['descripcion'],
        'p_uuid_usuario': userId,
      });

      if (response == null) {
        throw Exception('Error al crear la variante en la base de datos');
      }

      // Parse the response to get the created variant ID
      int createdId;
      if (response is Map<String, dynamic> && response['id'] != null) {
        createdId = response['id'] as int;
      } else if (response is int) {
        createdId = response;
      } else {
        // Fallback: generate a temporary ID
        createdId = DateTime.now().millisecondsSinceEpoch;
      }

      // Return created variant with proper types
      return Variant(
        id: createdId,
        idSubCategoria: 0, // Default value
        idAtributo: createdId, // Use the same ID for attribute
        denominacion: variantData['denominacion'],
        label: variantData['label'] ?? variantData['denominacion'], // Use denominacion as fallback if label not provided
        descripcion: variantData['descripcion'],
        options: [],
        createdAt: DateTime.now(),
      );
    } catch (e) {
      print('Error creating variant: $e');
      throw Exception('Error al crear variante: $e');
    }
  }

  static Future<bool> updateVariant(String id, Map<String, dynamic> variantData) async {
    try {
      final userId = await UserPreferencesService().getUserId();
      if (userId == null) {
        throw Exception('No se encontró UUID del usuario');
      }

      final response = await _supabase.rpc('fn_actualizar_atributo', params: {
        'p_id': int.parse(id),
        'p_denominacion': variantData['denominacion'],
        'p_label': variantData['label'] ?? variantData['denominacion']?.toString().toLowerCase().replaceAll(' ', '_'),
        'p_descripcion': variantData['descripcion'],
        'p_uuid_usuario': userId,
      });

      return response == true;
    } catch (e) {
      print('Error updating variant: $e');
      throw Exception('Error al actualizar variante: $e');
    }
  }

  static Future<bool> deleteVariant(int id) async {
    try {
      final userId = await UserPreferencesService().getUserId();
      if (userId == null) {
        throw Exception('No se encontró UUID del usuario');
      }

      final response = await _supabase.rpc('fn_eliminar_atributo', params: {
        'p_id': id,
        'p_uuid_usuario': userId,
      });

      return response == true;
    } catch (e) {
      print('Error deleting variant: $e');
      throw Exception('Error al eliminar variante: $e');
    }
  }

  static Future<VariantOption> createVariantOption(Map<String, dynamic> optionData) async {
    try {
      print(' [createVariantOption] Creating option: ${optionData['denominacion']} for attribute ${optionData['id_atributo']}');
      
      final storeId = await _getStoreId();
      if (storeId == null) {
        throw Exception('No se encontró ID de tienda del usuario');
      }

      final userId = await UserPreferencesService().getUserId();
      if (userId == null) {
        throw Exception('No se encontró UUID del usuario');
      }

      final response = await _supabase.rpc('fn_crear_opcion_atributo', params: {
        'p_id_atributo': optionData['id_atributo'],
        'p_valor': optionData['denominacion'], // Use denominacion as valor
        'p_sku_codigo': optionData['valor'] ?? optionData['denominacion'] ?? 'AUTO', // Use valor as sku_codigo, fallback to denominacion or AUTO
        'p_uuid_usuario': userId,
      });

      if (response == null) {
        throw Exception('Error al crear la opción en la base de datos');
      }

      // Parse the response to get the created option ID
      int createdId;
      if (response is Map<String, dynamic> && response['id'] != null) {
        createdId = response['id'] as int;
      } else if (response is int) {
        createdId = response;
      } else {
        createdId = DateTime.now().millisecondsSinceEpoch;
      }

      print(' [createVariantOption] Option created with ID: $createdId');

      return VariantOption(
        id: createdId,
        idVariante: optionData['id_atributo'],
        denominacion: optionData['denominacion'],
        valor: optionData['valor'] ?? '',
        createdAt: DateTime.now(),
      );
    } catch (e) {
      print(' [createVariantOption] Error: $e');
      throw Exception('Error al crear opción: $e');
    }
  }

  static Future<bool> updateVariantOption(String id, Map<String, dynamic> optionData) async {
    try {
      final userId = await UserPreferencesService().getUserId();
      if (userId == null) {
        throw Exception('No se encontró UUID del usuario');
      }

      final response = await _supabase.rpc('fn_actualizar_opcion_atributo', params: {
        'p_id': int.parse(id),
        'p_valor': optionData['denominacion'],
        'p_uuid_usuario': userId,
      });

      return response == true;
    } catch (e) {
      print('Error updating variant option: $e');
      throw Exception('Error al actualizar opción: $e');
    }
  }

  static Future<bool> deleteVariantOption(String id) async {
    try {
      final userId = await UserPreferencesService().getUserId();
      if (userId == null) {
        throw Exception('No se encontró UUID del usuario');
      }

      final response = await _supabase.rpc('fn_eliminar_opcion_atributo', params: {
        'p_id': int.parse(id),
        'p_uuid_usuario': userId,
      });

      return response == true;
    } catch (e) {
      print('Error deleting variant option: $e');
      throw Exception('Error al eliminar opción: $e');
    }
  }

  // Get products that use a specific variant
  static Future<List<Product>> getProductsByVariant(String variantId) async {
    try {
      print('=== getProductsByVariant DEBUG START ===');
      print('Input variantId: $variantId');
      
      final storeId = await _getStoreId();
      print('Retrieved storeId: $storeId');
      
      if (storeId == null) {
        print('ERROR: No store ID found for products by variant');
        return [];
      }

      final parsedVariantId = int.parse(variantId);
      print('Parsed variantId to int: $parsedVariantId');

      // Call RPC function to get products using this variant
      final response = await _supabase.rpc('fn_listar_productos_por_atributo', params: {
        'p_id_variante': parsedVariantId,
        'p_id_tienda': storeId,
      });

      if (response == null) {
        print('No response from RPC function');
        return [];
      }

      print('Raw response type: ${response.runtimeType}');
      print('Raw response: $response');

      List<dynamic> data;
      if (response is List) {
        data = response;
      } else if (response is Map) {
        data = [response];
      } else {
        print('Unexpected response type: ${response.runtimeType}');
        return [];
      }

      print('Processing ${data.length} items');

      final products = data.map((item) => _parseProductFromDatabase(item)).toList();
      
      print('Parsed ${products.length} products successfully');
      print('=== getProductsByVariant DEBUG END ===');
      
      return products;
    } catch (e) {
      print('=== getProductsByVariant ERROR ===');
      print('Error fetching products by variant: $e');
      print('Error type: ${e.runtimeType}');
      if (e is PostgrestException) {
        print('PostgrestException details:');
        print('  message: ${e.message}');
        print('  code: ${e.code}');
        print('  details: ${e.details}');
        print('  hint: ${e.hint}');
      }
      print('=== ERROR END ===');
      return [];
    }
  }

  // New method to get products by variant and subcategory
  static Future<List<Product>> getProductsByVariantAndSubcategory(int variantId, int subcategoryId) async {
    try {
      print('=== getProductsByVariantAndSubcategory DEBUG START ===');
      print('Input variantId: $variantId, subcategoryId: $subcategoryId');
      
      final storeId = await _getStoreId();
      if (storeId == null) {
        print('ERROR: No store ID found');
        return [];
      }

      // Get products that use this variant and belong to this subcategory
      final response = await _supabase.rpc('get_productos_completos_by_tienda_optimized', params: {
        'id_tienda_param': storeId,
        'id_categoria_param': null,
        'solo_disponibles_param': false,
      });

      if (response == null) {
        return [];
      }

      List<dynamic> data;
      if (response is List) {
        data = response;
      } else if (response is Map) {
        data = [response];
      } else {
        return [];
      }

      // Filter products that:
      // 1. Have the specific subcategory in their subcategorias array
      // 2. Have inventory/operations with the specific variant
      final filteredProducts = <Product>[];
      
      for (final item in data) {
        // Check if product has this subcategory
        final subcategorias = item['subcategorias'] as List<dynamic>? ?? [];
        final hasSubcategory = subcategorias.any((sub) => sub['id'] == subcategoryId);
        
        if (hasSubcategory) {
          // Check if product has inventory with this variant
          // This would require checking inventory records, for now we'll include all products with the subcategory
          filteredProducts.add(_parseProductFromDatabase(item));
        }
      }

      print('Found ${filteredProducts.length} products for variant $variantId and subcategory $subcategoryId');
      return filteredProducts;
    } catch (e) {
      print('Error fetching products by variant and subcategory: $e');
      return [];
    }
  }

  // Get product count for a specific variant
  static Future<int> getProductCountByVariant(String variantId) async {
    try {
      final products = await getProductsByVariant(variantId);
      return products.length;
    } catch (e) {
      print('Error getting product count by variant: $e');
      return 0;
    }
  }

  // Get product count by variant and subcategory
  static Future<int> getProductCountByVariantAndSubcategory(int variantId, int subcategoryId) async {
    try {
      final products = await getProductsByVariantAndSubcategory(variantId, subcategoryId);
      return products.length;
    } catch (e) {
      print('Error getting product count by variant and subcategory: $e');
      return 0;
    }
  }

  // Parse product from database response
  static Product _parseProductFromDatabase(Map<String, dynamic> data) {
    return Product(
      id: data['id'].toString(),
      name: data['denominacion'] ?? '',
      denominacion: data['denominacion'] ?? '',
      description: data['descripcion'] ?? '',
      categoryId: data['id_categoria']?.toString() ?? '',
      categoryName: data['categoria_nombre'] ?? '',
      brand: data['nombre_comercial'] ?? '',
      sku: data['sku'] ?? '',
      barcode: data['codigo_barras'] ?? '',
      basePrice: (data['precio_venta'] ?? 0.0).toDouble(),
      imageUrl: data['imagen'] ?? '',
      isActive: data['es_vendible'] ?? true,
      createdAt: DateTime.tryParse(data['created_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(data['created_at'] ?? '') ?? DateTime.now(),
      stockDisponible: data['stock_disponible'] ?? 0,
      precioVenta: (data['precio_venta'] ?? 0.0).toDouble(),
    );
  }

  // Get subcategories for dropdown selection
  static Future<List<Map<String, dynamic>>> getSubcategories() async {
    try {
      final storeId = await _getStoreId();
      if (storeId == null) {
        print('No store ID found for subcategories');
        return [];
      }

      // Use the product function to get subcategories since there's no direct subcategory RPC
      final response = await _supabase.rpc('get_productos_completos_by_tienda_optimized', params: {
        'id_tienda_param': storeId,
        'id_categoria_param': null,
        'solo_disponibles_param': false,
      });

      if (response == null) {
        return [];
      }

      // Handle both List and Map response types
      List<dynamic> data;
      if (response is List) {
        data = response;
      } else if (response is Map) {
        data = [response]; // Wrap single object in a list
      } else {
        print('Unexpected response type: ${response.runtimeType}');
        return [];
      }
      
      // Extract unique subcategories from products
      final Map<int, Map<String, dynamic>> subcategoriesMap = {};
      
      for (final item in data) {
        final subcategoryId = item['id_subcategoria'] as int?;
        final subcategoryName = item['subcategoria_nombre'] as String?;
        final categoryId = item['id_categoria'] as int?;
        final categoryName = item['categoria_nombre'] as String?;
        
        if (subcategoryId != null && subcategoryName != null) {
          subcategoriesMap[subcategoryId] = {
            'id': subcategoryId,
            'denominacion': subcategoryName,
            'categoria_nombre': categoryName ?? '',
            'id_categoria': categoryId,
          };
        }
      }
      
      return subcategoriesMap.values.toList();
    } catch (e) {
      print('Error fetching subcategories: $e');
      return [];
    }
  }

  // Get subcategories by category ID
  static Future<List<Map<String, dynamic>>> getSubcategoriesByCategory(int categoryId, {String? categoryName}) async {
    try {
      final storeId = await _getStoreId();
      if (storeId == null) {
        print('No store ID found for subcategories');
        return [];
      }

      // Direct query to get ALL subcategories for a category, not just those with products
      final response = await _supabase
          .from('app_dat_subcategorias')
          .select('id, denominacion, idcategoria')
          .eq('idcategoria', categoryId)
          .order('denominacion');

      if (response == null || response.isEmpty) {
        print('No subcategories found for category $categoryId');
        return [];
      }

      // Use provided categoryName if available, otherwise fetch it
      String finalCategoryName = categoryName ?? '';
      if (finalCategoryName.isEmpty) {
        final categoryResponse = await _supabase
            .from('app_dat_categoria')
            .select('denominacion')
            .eq('id', categoryId)
            .single();
        finalCategoryName = categoryResponse['denominacion'] ?? '';
      }

      return (response as List<dynamic>).map((item) => {
        'id': item['id'] as int,
        'denominacion': item['denominacion'] as String,
        'categoria_nombre': finalCategoryName,
        'id_categoria': categoryId,
      }).toList();
    } catch (e) {
      print('Error fetching subcategories by category: $e');
      return [];
    }
  }

  // Get subcategories associated with a specific variant
  static Future<List<Map<String, dynamic>>> getSubcategoriesByVariant(int variantId) async {
    try {
      print(' [getSubcategoriesByVariant] Starting for variantId: $variantId');
      
      final storeId = await _getStoreId();
      if (storeId == null) {
        print(' [getSubcategoriesByVariant] No store ID found for subcategories by variant');
        return [];
      }
      
      print(' [getSubcategoriesByVariant] Using storeId: $storeId');

      // First, get the variant to extract its idAtributo
      final variants = await getVariants();
      final variant = variants.firstWhere(
        (v) => v.id == variantId,
        orElse: () => throw Exception('Variant with ID $variantId not found')
      );

      final attributeId = variant.idAtributo;
      print(' [getSubcategoriesByVariant] Found variant with attributeId: $attributeId');

      // Call the SQL function to get subcategories for this attribute
      print(' [getSubcategoriesByVariant] Calling RPC fn_listar_subcategorias_por_atributo with p_id_atributo: $attributeId');
      
      final response = await _supabase.rpc('fn_listar_subcategorias_por_atributo', params: {
        'p_id_atributo': attributeId,
      });

      print(' [getSubcategoriesByVariant] Raw response: $response');
      print(' [getSubcategoriesByVariant] Response type: ${response.runtimeType}');

      if (response == null) {
        print(' [getSubcategoriesByVariant] Response is null');
        return [];
      }

      // Handle both List and Map response types
      List<dynamic> data;
      if (response is List) {
        data = response;
      } else if (response is Map) {
        data = [response]; // Wrap single object in a list
      } else {
        print(' [getSubcategoriesByVariant] Unexpected response type: ${response.runtimeType}');
        return [];
      }
      
      print(' [getSubcategoriesByVariant] Data length: ${data.length}');
      
      if (data.isNotEmpty) {
        print(' [getSubcategoriesByVariant] First item raw: ${data.first}');
      }
      
      // Return subcategories with category hierarchy information
      final result = data.map((item) {
       // print(' [getSubcategoriesByVariant] Processing item: $item');
        
        final subcategoryId = item['id_subcategoria'];
        final subcategoryName = item['denominacion_subcategoria'] ?? '';
        final categoryName = item['denominacion_categoria'] ?? '';
        final categoryId = item['id_categoria'];
        
       /* print(' [getSubcategoriesByVariant] Extracted values:');
        print('   - subcategoryId: $subcategoryId');
        print('   - subcategoryName: "$subcategoryName"');
        print('   - categoryName: "$categoryName"');
        print('   - categoryId: $categoryId');*/
        
        final processedItem = {
          'id': subcategoryId,
          'denominacion': subcategoryName,
          'categoria_nombre': categoryName,
          'id_categoria': categoryId,
          'hierarchy': '$categoryName > $subcategoryName',
        };
        
       // print(' [getSubcategoriesByVariant] Processed item: $processedItem');
        return processedItem;
      }).toList();
      
      print(' [getSubcategoriesByVariant] Final result: $result');
      return result;
    } catch (e) {
      print(' [getSubcategoriesByVariant] Error fetching subcategories by variant: $e');
      return [];
    }
  }

  // Create variant-subcategory relationship
  static Future<bool> createVariantSubcategoryRelation(int variantId, int subcategoryId) async {
    try {
      print(' [createVariantSubcategoryRelation] Creating relation: variantId=$variantId, subcategoryId=$subcategoryId');
      
      final storeId = await _getStoreId();
      if (storeId == null) {
        print(' [createVariantSubcategoryRelation] No store ID found');
        throw Exception('No se encontró ID de tienda del usuario');
      }

      // Insert directly into app_dat_variantes table
      // variantId is actually the attribute ID (id_atributo)
      final response = await _supabase
          .from('app_dat_variantes')
          .insert({
            'id_atributo': variantId,
            'id_sub_categoria': subcategoryId,
          })
          .select()
          .single();

      print(' [createVariantSubcategoryRelation] Relation created successfully: $response');
      return response != null;
    } catch (e) {
      print(' [createVariantSubcategoryRelation] Error: $e');
      return false;
    }
  }

  // Create variant record in app_dat_variantes table
  static Future<bool> createVariantRecord(int attributeId, int? subcategoryId) async {
    try {
      print(' [createVariantRecord] Creating variant record: attributeId=$attributeId, subcategoryId=$subcategoryId');
      
      final storeId = await _getStoreId();
      if (storeId == null) {
        print(' [createVariantRecord] No store ID found');
        throw Exception('No se encontró ID de tienda del usuario');
      }

      final userId = await UserPreferencesService().getUserId();
      if (userId == null) {
        throw Exception('No se encontró UUID del usuario');
      }

      // Create a record in app_dat_variantes table
      final response = await _supabase.rpc('fn_crear_variante', params: {
        'p_id_atributo': attributeId,
        'p_id_sub_categoria': subcategoryId,
        'p_uuid_usuario': userId,
      });

      print(' [createVariantRecord] Variant record created successfully');
      return response != null;
    } catch (e) {
      print(' [createVariantRecord] Error: $e');
      return false;
    }
  }

  // Get categories for dropdown selection
  static Future<List<Map<String, dynamic>>> getCategories() async {
    try {
      // Get all user stores instead of just the selected one
      await _storeSelectorService.initialize();
      final userStores = _storeSelectorService.userStores;
      
      if (userStores.isEmpty) {
        print('No stores found for user');
        return [];
      }

      print('Fetching categories from ${userStores.length} stores');
      
      // Collect categories from all user stores
      final Map<int, Map<String, dynamic>> allCategories = {};
      
      for (final store in userStores) {
        try {
          print('Fetching categories for store: ${store.denominacion} (ID: ${store.id})');
          
          final response = await _supabase.rpc('get_categorias_by_tienda', params: {
            'p_tienda_id': store.id,
          });

          if (response != null && response is List) {
            final List<dynamic> data = response;
            
            // Add categories to the map, avoiding duplicates by ID
            for (final item in data) {
              final categoryId = item['id'] as int;
              final categoryName = item['nombre'] ?? item['denominacion'] ?? '';
              final description = item['descripcion'] ?? '';
              
              // Only add if not already present, or if this version has more complete data
              if (!allCategories.containsKey(categoryId) || 
                  (allCategories[categoryId]!['denominacion'] as String).isEmpty) {
                allCategories[categoryId] = {
                  'id': categoryId,
                  'denominacion': categoryName,
                  'descripcion': description,
                  'store_name': store.denominacion, // Optional: track which store this came from
                };
              }
            }
            
            print('Added ${data.length} categories from store ${store.denominacion}');
          }
        } catch (storeError) {
          print('Error fetching categories from store ${store.denominacion}: $storeError');
          // Continue with other stores even if one fails
        }
      }
      
      final result = allCategories.values.toList();
      print('Total unique categories found: ${result.length}');
      
      return result;
    } catch (e) {
      print('Error fetching categories from all stores: $e');
      return [];
    }
  }

  // Remove variant-subcategory relationship with validation
  static Future<bool> removeVariantSubcategoryRelation(int variantId, int subcategoryId) async {
    try {
      // Get store ID for validation
      final storeId = await _getStoreId();
      if (storeId == null) {
        throw Exception('No se pudo obtener el ID de la tienda');
      }

      // Get the variant to extract its idAtributo
      final variants = await getVariants();
      final variant = variants.firstWhere(
        (v) => v.id == variantId,
        orElse: () => throw Exception('Variant with ID $variantId not found')
      );

      // Use the SQL function with idAtributo and subcategory ID
      final response = await _supabase.rpc('fn_eliminar_variante_subcategoria', params: {
        'p_id_atributo': variant.idAtributo,
        'p_id_subcategoria': subcategoryId,
      });
      
      if (response == true) {
        print('✅ Variant-subcategory relationship removed successfully: attribute ${variant.idAtributo}, subcategory $subcategoryId');
        return true;
      } else {
        throw Exception('La función de base de datos retornó un resultado inesperado');
      }
      
    } catch (e) {
      print('❌ Error removing variant-subcategory relation: $e');
      rethrow;
    }
  }
}
