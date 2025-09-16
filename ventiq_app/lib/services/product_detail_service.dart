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

    debugPrint('🔍 Transformando producto con ${inventoryData.length} items de inventario');

    // Extract basic product information
    final id = productData['id'] as int;
    final denominacion = productData['denominacion'] as String? ?? 'Sin nombre';
    final descripcion = productData['descripcion'] as String?;
    final precioActual = (productData['precio_actual'] as num?)?.toDouble() ?? 0.0;
    final esRefrigerado = productData['es_refrigerado'] as bool? ?? false;
    final esFragil = productData['es_fragil'] as bool? ?? false;
    final esPeligroso = productData['es_peligroso'] as bool? ?? false;

    // Extract category information
    final categoria = productData['categoria'] as Map<String, dynamic>?;
    final categoryName = categoria?['denominacion'] as String? ?? 'Sin categoría';

    // Transform inventory data to variants
    final variants = _transformInventoryToVariants(inventoryData, precioActual);

    // Calculate total stock from all variants
    int totalStock = 0;
    Map<String, dynamic>? productInventoryMetadata;
    
    if (variants.isNotEmpty) {
      totalStock = variants.fold(0, (sum, variant) => sum + variant.cantidad);
    } else {
      // If no variants, use inventory data for the product itself
      if (inventoryData.isNotEmpty) {
        final firstInventory = inventoryData.first as Map<String, dynamic>;
        totalStock = firstInventory['cantidad_disponible'] as int? ?? 0;
        
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
      final cantidadDisponible = item['cantidad_disponible'] as int? ?? 0;
      
      
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
}
