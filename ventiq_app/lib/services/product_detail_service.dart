import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product.dart';

class ProductDetailService {
  static final ProductDetailService _instance = ProductDetailService._internal();
  factory ProductDetailService() => _instance;
  ProductDetailService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  /// Fetch detailed product information from Supabase
  Future<Product> getProductDetail(int productId) async {
    try {
      debugPrint('🔍 Obteniendo detalles del producto ID: $productId');

      final response = await _supabase.rpc(
        'get_detalle_producto',
        params: {
          'id_producto_param': productId,
        },
      );

      if (response == null) {
        throw Exception('No se recibieron datos del producto');
      }

      debugPrint('📦 Respuesta de detalles recibida');

      // Transform Supabase response to Product model
      return _transformToProduct(response);

    } catch (e,stackTrace) {
      debugPrint('❌ Error obteniendo detalles del producto: $e');
      debugPrint('📍 Stack trace completo:\n$stackTrace');
      rethrow;
    }
  }

  /// Transform Supabase response to Product model
  Product _transformToProduct(Map<String, dynamic> response) {
    final productData = response['producto'] as Map<String, dynamic>;
    final inventoryData = response['inventario'] as List<dynamic>? ?? [];
    print('elaborado: ${productData['es_elaborado']}');
    debugPrint('🔍 Transformando producto con ${inventoryData.length} items de inventario');

    // Extract basic product information
    final id = productData['id'] as int;
    final denominacion = productData['denominacion'] as String? ?? 'Sin nombre';
    final descripcion = productData['descripcion'] as String?;
    final precioActual = (productData['precio_actual'] as num?)?.toDouble() ?? 0.0;
    final esRefrigerado = productData['es_refrigerado'] as bool? ?? false;
    final esFragil = productData['es_fragil'] as bool? ?? false;
    final esPeligroso = productData['es_peligroso'] as bool? ?? false;
    final esElaborado = productData['es_elaborado'] as bool? ?? false;

    // Extract category information
    final categoria = productData['categoria'] as Map<String, dynamic>?;
    final categoryName = categoria?['denominacion'] as String? ?? 'Sin categoría';

    // Transform inventory data to variants
    final variants = _transformInventoryToVariants(inventoryData, precioActual);

    // Calculate total stock from all variants
    int totalStock = 0;
    Map<String, dynamic>? productInventoryMetadata;
    
    if (variants.isNotEmpty) {
      totalStock = variants.fold(0, (sum, variant) => sum + variant.cantidad.toInt());
    } else {
      // If no variants, use inventory data for the product itself
      if (inventoryData.isNotEmpty) {
        final firstInventory = inventoryData.first as Map<String, dynamic>;
        totalStock = (firstInventory['cantidad_disponible'] as num?)?.toInt() ?? 0;
        
        // Store inventory metadata for products without variants
        productInventoryMetadata = _extractInventoryMetadata(firstInventory);
        debugPrint('📦 Producto sin variantes - metadata: $productInventoryMetadata');
      } else {
        totalStock = 100; // Default stock
      }
    }

    // Generate product image URL from multimedias or fallback
    String? imageUrl;
    if (productData['multimedias'] != null && productData['multimedias'] is List) {
      final multimedias = productData['multimedias'] as List;
      if (multimedias.isNotEmpty) {
        final firstMedia = multimedias[0];
        if (firstMedia is Map && firstMedia['url'] != null) {
          imageUrl = firstMedia['url'];
        }
      }
    }
    
    // Fallback to foto field if multimedias is empty or null
    if (imageUrl == null && productData['foto'] != null && productData['foto'].toString().isNotEmpty) {
      imageUrl = productData['foto'];
    }
    
    // Final fallback to random image
    if (imageUrl == null) {
      final hash = denominacion.hashCode.abs();
      final imageId = 200 + (hash % 800); // Range 200-999
      imageUrl = 'https://picsum.photos/id/$imageId/400/400';
    }

    return Product(
      id: id,
      denominacion: denominacion,
      descripcion: descripcion,
      foto: imageUrl,
      precio: precioActual,
      cantidad: totalStock,
      esRefrigerado: esRefrigerado,
      esFragil: esFragil,
      esPeligroso: esPeligroso,
      esVendible: true, // Default value
      esComprable: true, // Default value
      esInventariable: true, // Default value
      esPorLotes: false, // Default value
      esElaborado: productData['es_elaborado'] as bool? ?? false,
      categoria: categoryName,
      variantes: variants,
      inventoryMetadata: productInventoryMetadata,
    );
  }

  /// Transform inventory data to ProductVariant objects
  List<ProductVariant> _transformInventoryToVariants(List<dynamic> inventoryData, [double? productPrice]) {
    final List<ProductVariant> variants = [];
    
    for (int i = 0; i < inventoryData.length; i++) {
      final item = inventoryData[i] as Map<String, dynamic>;
      
      // Extract variant information
      final variante = item['variante'] as Map<String, dynamic>?;
      final presentacion = item['presentacion'] as Map<String, dynamic>?;
      final cantidadDisponible = (item['cantidad_disponible'] as num?)?.toInt() ?? 0;
      
      
      String variantName = 'Variante ${i + 1}';
      String variantDescription = '';
      
      if (variante != null) {
        final opcion = variante['opcion'] as Map<String, dynamic>?;
        final atributo = variante['atributo'] as Map<String, dynamic>?;
        
        if (opcion != null && atributo != null) {
          final valor = opcion['valor'] as String? ?? '';
          final label = atributo['label'] as String? ?? '';
          variantName = '$label: $valor';
          variantDescription = 'Variante de $label con valor $valor';
        }
      }
      
      if (presentacion != null) {
        final presentacionNombre = presentacion['denominacion'] as String? ?? '';
        final cantidad = (presentacion['cantidad'] as num?)?.toInt() ?? 1;
        if (presentacionNombre.isNotEmpty) {
          variantName += ' - $presentacionNombre';
          if (cantidad > 1) {
            variantDescription += ' (Presentación: $cantidad unidades)';
          }
        }
      }

      // Extract variant price or use product price as fallback
      double precio = productPrice ?? 0.0;
      
      // Try to get variant-specific price from the data
      if (item['precio'] != null) {
        precio = (item['precio'] as num).toDouble();
      } else if (variante != null && variante['precio'] != null) {
        precio = (variante['precio'] as num).toDouble();
      } else if (presentacion != null && presentacion['precio'] != null) {
        precio = (presentacion['precio'] as num).toDouble();
      }

      // Extract inventory metadata for this variant
      final variantInventoryMetadata = _extractInventoryMetadata(item);
      debugPrint('🔧 Variante ${i + 1} - metadata: $variantInventoryMetadata');
      
      variants.add(ProductVariant(
        id: i + 1, // Generate sequential IDs
        nombre: variantName,
        precio: precio,
        cantidad: cantidadDisponible,
        descripcion: variantDescription.isNotEmpty ? variantDescription : null,
        inventoryMetadata: variantInventoryMetadata,
      ));
    }
    
    return variants;
  }

  /// Extract inventory metadata from inventory item
  Map<String, dynamic> _extractInventoryMetadata(Map<String, dynamic> inventoryItem) {
    final variante = inventoryItem['variante'] as Map<String, dynamic>?;
    final presentacion = inventoryItem['presentacion'] as Map<String, dynamic>?;
    final ubicacion = inventoryItem['ubicacion'] as Map<String, dynamic>?;
    
    return {
      'id_inventario': inventoryItem['id_inventario'],
      'id_variante': variante?['id'],
      'id_opcion_variante': variante?['opcion']?['id'],
      'id_presentacion': presentacion?['id'],
      'id_ubicacion': ubicacion?['id'],
      'sku_producto': inventoryItem['sku_producto'],
      'sku_ubicacion': ubicacion?['sku_codigo'],
      'cantidad_disponible': inventoryItem['cantidad_disponible'],
      'ubicacion_nombre': ubicacion?['denominacion'],
      'almacen_nombre': ubicacion?['almacen']?['denominacion'],
    };
  }

  /// Verifica si un producto es elaborado
  Future<bool> isProductElaborated(int productId) async {
    try {
      debugPrint('🔍 Verificando si producto $productId es elaborado...');
      
      final response = await _supabase
          .from('app_dat_producto')
          .select('es_elaborado')
          .eq('id', productId)
          .single();
      
      final isElaborated = response['es_elaborado'] ?? false;
      debugPrint('🔍 Producto $productId - es_elaborado: $isElaborated');
      debugPrint('🔍 Respuesta completa: $response');
      
      return isElaborated;
    } catch (e) {
      debugPrint('❌ Error verificando si producto $productId es elaborado: $e');
      return false;
    }
  }

  /// Obtiene los ingredientes de un producto elaborado
  Future<List<Map<String, dynamic>>> getProductIngredients(int productId) async {
    try {
      debugPrint('🍽️ Obteniendo ingredientes para producto elaborado: $productId');

      final response = await _supabase
          .from('app_dat_producto_ingredientes')
          .select('''
            id,
            cantidad_necesaria,
            unidad_medida,
            app_dat_producto!app_dat_producto_ingredientes_ingrediente_fkey(
              id,
              denominacion,
              sku,
              imagen
            )
          ''')
          .eq('id_producto_elaborado', productId);

      if (response.isEmpty) {
        debugPrint('⚠️ No se encontraron ingredientes para el producto $productId');
        return [];
      }

      // Transform the response to match the expected format
      final ingredients = response.map((item) {
        final producto = item['app_dat_producto'] as Map<String, dynamic>? ?? {};
        return {
          'producto_id': producto['id'],
          'producto_nombre': producto['denominacion'] ?? 'Ingrediente desconocido',
          'cantidad_necesaria': item['cantidad_necesaria'] ?? 0,
          'unidad_medida': item['unidad_medida'] ?? '',
          'sku': producto['sku'] ?? '',
          'imagen': producto['imagen'],
        };
      }).toList();

      debugPrint('✅ Encontrados ${ingredients.length} ingredientes');
      
      return ingredients;
    } catch (e) {
      debugPrint('❌ Error obteniendo ingredientes del producto $productId: $e');
      return [];
    }
  }

  /// Muestra un diálogo con los ingredientes del producto elaborado
  static void showIngredientsPreview(BuildContext context, List<Map<String, dynamic>> ingredients, String productName) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.restaurant_menu,
                color: Colors.orange[600],
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ingredientes - $productName',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ingredients.isEmpty
                ? const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.info_outline, size: 48, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'No se encontraron ingredientes para este producto',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: ingredients.length,
                    itemBuilder: (context, index) {
                      final ingredient = ingredients[index];
                      final nombre = ingredient['producto_nombre'] ?? 'Ingrediente desconocido';
                      final cantidad = ingredient['cantidad_necesaria'] ?? 0;
                      final unidad = ingredient['unidad_medida'] ?? '';
                      
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.orange[100],
                            child: Icon(
                              Icons.inventory_2,
                              color: Colors.orange[600],
                              size: 20,
                            ),
                          ),
                          title: Text(
                            nombre,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          subtitle: Text(
                            'Cantidad: $cantidad $unidad',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  /// Obtener presentaciones de un producto específico
  Future<List<ProductPresentation>> getProductPresentations(int productId) async {
    try {
      debugPrint('🔍 Obteniendo presentaciones para producto ID: $productId');

      final response = await _supabase
          .from('app_dat_producto_presentacion')
          .select('''
            id,
            id_producto,
            id_presentacion,
            cantidad,
            es_base,
            presentacion:app_nom_presentacion!inner(
              id,
              denominacion,
              descripcion,
              sku_codigo
            )
          ''')
          .eq('id_producto', productId)
          .order('es_base', ascending: false); // Presentación base primero

      debugPrint('📦 Respuesta presentaciones: $response');

      if (response.isEmpty) {
        debugPrint('⚠️ No se encontraron presentaciones para el producto $productId');
        return [];
      }

      final presentations = response.map((item) {
        debugPrint('🔄 Procesando presentación: $item');
        return ProductPresentation.fromJson(item);
      }).toList();

      debugPrint('✅ Se cargaron ${presentations.length} presentaciones');
      for (var presentation in presentations) {
        debugPrint('📋 Presentación: ${presentation.presentacion.denominacion}, Cantidad: ${presentation.cantidad}, Es Base: ${presentation.esBase}');
      }

      return presentations;
    } catch (e, stackTrace) {
      debugPrint('❌ Error obteniendo presentaciones: $e');
      debugPrint('📍 Stack trace: $stackTrace');
      return [];
    }
  }
}
