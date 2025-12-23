import 'package:supabase_flutter/supabase_flutter.dart';

/// Servicio para obtener detalles de productos del marketplace
class ProductDetailService {
  static final ProductDetailService _instance =
      ProductDetailService._internal();
  factory ProductDetailService() => _instance;
  ProductDetailService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;

  /// Obtiene los detalles completos de un producto
  ///
  /// Usa el RPC get_productos_marketplace para obtener el producto con sus presentaciones
  /// y calcula el rating promedio
  Future<Map<String, dynamic>> getProductDetail(int productId) async {
    try {
      print('🔍 Obteniendo detalles del producto ID: $productId');

      // Obtener producto usando el RPC get_detalle_producto_marketplace
      final response = await _supabase.rpc(
        'get_detalle_producto_marketplace',
        params: {'id_producto_param': productId},
      );

      if (response == null) {
        throw Exception('No se recibieron datos del producto');
      }

      // La respuesta es un objeto con 'producto' e 'inventario'
      final responseMap = response as Map<String, dynamic>;
      final product = responseMap['producto'] as Map<String, dynamic>;
      final inventario = responseMap['inventario'] as List<dynamic>? ?? [];

      // 🚨 FIX: Si el RPC no devuelve 'id_tienda', lo buscamos manualmente
      if (product['id_tienda'] == null) {
        try {
          final productData = await _supabase
              .from('app_dat_producto')
              .select('id_tienda')
              .eq('id', productId)
              .single();
          product['id_tienda'] = productData['id_tienda'];
          print('🔄 ID Tienda recuperado manualmente: ${product['id_tienda']}');
        } catch (e) {
          print('⚠️ No se pudo recuperar id_tienda: $e');
        }
      }

      print('📦 Producto encontrado: ${product['denominacion']}');
      print('📦 Inventario: ${inventario.length} items');

      // Obtener rating del producto
      final rating = await _getProductRating(productId);

      // Transformar respuesta
      return _transformToMarketplaceProduct(product, inventario, rating);
    } catch (e, stackTrace) {
      print('❌ Error obteniendo detalles del producto: $e');
      print('📍 Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Obtiene el rating promedio y total de ratings de un producto
  Future<Map<String, dynamic>> _getProductRating(int productId) async {
    try {
      final response = await _supabase
          .from('app_dat_producto_rating')
          .select('rating')
          .eq('id_producto', productId);

      if (response.isEmpty) {
        return {'rating_promedio': 0.0, 'total_ratings': 0};
      }

      final ratings = List<Map<String, dynamic>>.from(response);
      final totalRatings = ratings.length;
      final sumRatings = ratings.fold<double>(
        0.0,
        (sum, r) => sum + ((r['rating'] as num?)?.toDouble() ?? 0.0),
      );
      final avgRating = totalRatings > 0 ? sumRatings / totalRatings : 0.0;

      print('⭐ Rating: $avgRating ($totalRatings ratings)');

      return {'rating_promedio': avgRating, 'total_ratings': totalRatings};
    } catch (e) {
      print('⚠️ Error obteniendo rating: $e');
      return {'rating_promedio': 0.0, 'total_ratings': 0};
    }
  }

  /// Transforma la respuesta del RPC usando las presentaciones del producto
  Map<String, dynamic> _transformToMarketplaceProduct(
    Map<String, dynamic> product,
    List<dynamic> inventario,
    Map<String, dynamic> rating,
  ) {
    print('📦 PRODUCTO COMPLETO:');
    print(product);
    print('─' * 80);

    // Información básica del producto
    final id = product['id'] as int;
    final denominacion = product['denominacion'] as String? ?? 'Sin nombre';
    final descripcion = product['descripcion'] as String?;
    final precioActual = (product['precio_actual'] as num?)?.toDouble() ?? 0.0;
    final esRefrigerado = product['es_refrigerado'] as bool? ?? false;
    final esFragil = product['es_fragil'] as bool? ?? false;

    // Calcular stock total desde el inventario
    final stockTotal = inventario.fold<int>(0, (sum, item) {
      final cantidad = (item['cantidad_disponible'] as num?)?.toInt() ?? 0;
      return sum + cantidad;
    });

    print('📦 Stock total calculado: $stockTotal');

    // Categoría
    final categoria = product['categoria'] as Map<String, dynamic>?;
    final categoryName =
        categoria?['denominacion'] as String? ?? 'Sin categoría';

    // Imagen del producto
    String? imageUrl;
    final multimedias = product['multimedias'];
    if (multimedias != null && multimedias is List && multimedias.isNotEmpty) {
      final firstMedia = multimedias[0];
      if (firstMedia is Map && firstMedia['url'] != null) {
        imageUrl = firstMedia['url'];
      }
    }

    // Fallback a foto si no hay multimedias
    if (imageUrl == null) {
      final foto = product['foto'];
      if (foto != null && foto.toString().isNotEmpty) {
        imageUrl = foto;
      }
    }

    // Obtener presentaciones del producto
    final presentacionesList =
        product['presentaciones'] as List<dynamic>? ?? [];

    print('📋 PRESENTACIONES DEL PRODUCTO:');
    print('Total: ${presentacionesList.length}');
    for (var p in presentacionesList) {
      print('  - ${p}');
    }

    // Crear variantes a partir de las presentaciones
    final List<Map<String, dynamic>> variants = [];

    for (var presentacion in presentacionesList) {
      final presentacionMap = presentacion as Map<String, dynamic>;
      final presentacionId = presentacionMap['id'] as int;
      final presentacionNombre =
          presentacionMap['presentacion'] as String? ?? 'Presentación';
      final cantidad = (presentacionMap['cantidad'] as num?)?.toDouble() ?? 1.0;
      final esBase = presentacionMap['es_base'] as bool? ?? false;
      final skuCodigo = presentacionMap['sku_codigo'] as String?;

      // Calcular precio por presentación (precio base * cantidad)
      final precioPresentacion = precioActual * cantidad;

      // Descripción de la presentación
      String descripcion = '';
      if (cantidad > 1) {
        descripcion = 'Presentación de ${cantidad.toStringAsFixed(0)} unidades';
      }

      variants.add({
        'id': presentacionId.toString(),
        'nombre': presentacionNombre,
        'descripcion': descripcion.isNotEmpty ? descripcion : null,
        'precio': precioPresentacion,
        'cantidad_total':
            stockTotal, // Todo el stock disponible para cada presentación
        'id_presentacion': presentacionId,
        'presentacion_nombre': presentacionNombre,
        'presentacion_cantidad': cantidad,
        'es_base': esBase,
        'sku_codigo': skuCodigo,
      });
    }

    // Ordenar: presentaciones base primero
    variants.sort((a, b) {
      final baseCompare = (b['es_base'] as bool ? 1 : 0).compareTo(
        a['es_base'] as bool ? 1 : 0,
      );
      if (baseCompare != 0) return baseCompare;
      return (a['nombre'] as String).compareTo(b['nombre'] as String);
    });

    print('\n✅ PRODUCTO TRANSFORMADO:');
    print('  - Nombre: $denominacion');
    print('  - Presentaciones: ${variants.length}');
    print('  - Stock total: $stockTotal');
    print(
      '  - Rating: ${rating['rating_promedio']} (${rating['total_ratings']} ratings)',
    );
    print('\n📋 PRESENTACIONES FINALES:');
    for (var v in variants) {
      print(
        '  - ${v['nombre']} | Precio: ${v['precio']} | Stock: ${v['cantidad_total']} | Base: ${v['es_base']}',
      );
    }
    print('═' * 80);

    // ID de la tienda
    final storeId = product['id_tienda'] as int?;

    return {
      'id': id,
      'id_tienda': storeId, // Agregado
      'denominacion': denominacion,
      'nombre_comercial': product['nombre_comercial'],
      'sku': product['sku'],
      'descripcion': descripcion,
      'imagen': imageUrl,
      'precio': precioActual,
      'cantidad_total': stockTotal,
      'categoria': categoryName,
      'es_refrigerado': esRefrigerado,
      'es_fragil': esFragil,
      'es_peligroso': product['es_peligroso'] ?? false,
      'es_elaborado': product['es_elaborado'] ?? false,
      'codigo_barras': product['codigo_barras'],
      'um': product['um'],
      'subcategorias': product['subcategorias'],
      'multimedias': product['multimedias'],
      'etiquetas': product['etiquetas'],
      'variantes': variants,
      'rating_promedio': rating['rating_promedio'],
      'total_ratings': rating['total_ratings'],
    };
  }
}
