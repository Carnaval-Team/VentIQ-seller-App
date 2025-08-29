import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'dart:io';
import '../models/product.dart';
import 'user_preferences_service.dart';

class ProductService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Obtiene productos completos por tienda usando la función RPC optimizada
  static Future<List<Product>> getProductsByTienda({
    int? categoryId,
    bool soloDisponibles = false,
  }) async {
    try {
      // Obtener ID de tienda desde las preferencias del usuario
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();
      if (idTienda == null) {
        throw Exception('No se encontró ID de tienda en las preferencias del usuario');
      }

      print('🔍 Llamando RPC get_productos_completos_by_tienda_optimized');
      print('📍 Parámetros: idTienda=$idTienda, categoryId=$categoryId, soloDisponibles=$soloDisponibles');

      // Llamar a la función RPC optimizada
      final response = await _supabase.rpc(
        'get_productos_completos_by_tienda_optimized',
        params: {
          'id_tienda_param': idTienda,
          'id_categoria_param': categoryId,
          'solo_disponibles_param': soloDisponibles,
        },
      );

      print('📦 Respuesta RPC recibida: ${response.toString()}');

      // Save debug JSON to Documents folder
      await _saveDebugJson(response, 'productos_rpc_response');

      if (response == null) {
        print('⚠️ Respuesta nula de la función RPC');
        return [];
      }

      // Extraer la lista de productos del JSON de respuesta
      final productosData = response['productos'] as List<dynamic>? ?? [];
      print('📊 Total productos encontrados: ${productosData.length}');

      // Convertir cada producto del JSON al modelo Product
      final productos = productosData.map((productoJson) {
        return _convertToProduct(productoJson as Map<String, dynamic>);
      }).toList();

      print('✅ Productos convertidos exitosamente: ${productos.length}');
      return productos;

    } catch (e, stackTrace) {
      print('❌ Error en getProductsByTienda: $e');
      print('📍 StackTrace: $stackTrace');
      throw Exception('Error al obtener productos: $e');
    }
  }

  /// Inserta un producto completo con todas sus relaciones
  static Future<Map<String, dynamic>> insertProductoCompleto({
    required Map<String, dynamic> productoData,
    List<Map<String, dynamic>>? subcategoriasData,
    List<Map<String, dynamic>>? presentacionesData,
    List<Map<String, dynamic>>? multimediasData,
    List<Map<String, dynamic>>? etiquetasData,
    List<Map<String, dynamic>>? variantesData,
    List<Map<String, dynamic>>? preciosData,
  }) async {
    try {
      print('🔍 Insertando producto completo...');
      print('📦 Datos del producto: $productoData');

      final response = await _supabase.rpc(
        'insert_producto_completo',
        params: {
          'producto_data': productoData,
          'subcategorias_data': subcategoriasData,
          'presentaciones_data': presentacionesData,
          'multimedias_data': multimediasData,
          'etiquetas_data': etiquetasData,
          'variantes_data': variantesData,
          'precios_data': preciosData,
        },
      );

      print('📦 Respuesta RPC: $response');

      if (response == null) {
        throw Exception('Respuesta nula de la función RPC');
      }

      final result = response as Map<String, dynamic>;
      
      if (result['success'] == true) {
        print('✅ Producto insertado exitosamente');
        return result;
      } else {
        throw Exception(result['message'] ?? 'Error desconocido al insertar producto');
      }

    } catch (e, stackTrace) {
      print('❌ Error en insertProductoCompleto: $e');
      print('📍 StackTrace: $stackTrace');
      throw Exception('Error al insertar producto: $e');
    }
  }

  /// Obtiene subcategorías por categoría
  static Future<List<Map<String, dynamic>>> getSubcategorias(int categoryId) async {
    try {
      print('🔍 Obteniendo subcategorías para categoría: $categoryId');

      final response = await _supabase
          .from('app_dat_subcategorias')
          .select('id,denominacion')
          .eq('idcategoria', categoryId);

      print('📦 Subcategorías obtenidas: ${response.length}');
      return response;

    } catch (e) {
      print('❌ Error al obtener subcategorías: $e');
      throw Exception('Error al obtener subcategorías: $e');
    }
  }

  /// Obtiene presentaciones disponibles
  static Future<List<Map<String, dynamic>>> getPresentaciones() async {
    try {
      print('🔍 Obteniendo presentaciones disponibles');

      final response = await _supabase
          .from('app_nom_presentacion')
          .select('id,denominacion,descripcion');

      print('📦 Presentaciones obtenidas: ${response.length}');
      return response;

    } catch (e) {
      print('❌ Error al obtener presentaciones: $e');
      throw Exception('Error al obtener presentaciones: $e');
    }
  }

  /// Obtiene atributos con sus opciones
  static Future<List<Map<String, dynamic>>> getAtributos() async {
    try {
      print('🔍 Obteniendo atributos con opciones');

      final response = await _supabase
          .from('app_dat_atributos')
          .select('id,denominacion,label,app_dat_atributo_opcion(id,valor)');

      print('📦 Atributos obtenidos: ${response.length}');
      return response;

    } catch (e) {
      print('❌ Error al obtener atributos: $e');
      throw Exception('Error al obtener atributos: $e');
    }
  }

  /// Obtiene categorías disponibles para filtros
  static Future<List<Map<String, dynamic>>> getCategorias() async {
    try {
      // Obtener ID de tienda desde las preferencias del usuario
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();
      if (idTienda == null) {
        throw Exception('No se encontró ID de tienda en las preferencias del usuario');
      }

      print('🔍 Obteniendo categorías para tienda: $idTienda');

      final response = await _supabase
          .from('app_dat_categoria_tienda')
          .select('id_categoria, app_dat_categoria ( denominacion)')
          .eq('id_tienda', idTienda);

      print('📦 Categorías obtenidas: ${response.length}');

      return response.map((item) {
        final categoria = item['app_dat_categoria'] as Map<String, dynamic>;
        return {
          'id': item['id_categoria'],
          'denominacion': categoria['denominacion'],
        };
      }).toList();

    } catch (e) {
      print('❌ Error al obtener categorías: $e');
      throw Exception('Error al obtener categorías: $e');
    }
  }

  /// Convierte el JSON de la respuesta RPC al modelo Product
  static Product _convertToProduct(Map<String, dynamic> json) {
    try {
      // Extraer información de categoría
      final categoria = json['categoria'] as Map<String, dynamic>? ?? {};
      
      // Extraer subcategorías para el modelo Product
      final subcategorias = json['subcategorias'] as List<dynamic>? ?? [];

      // Extraer presentaciones para crear variantes
      final presentaciones = json['presentaciones'] as List<dynamic>? ?? [];
      final variants = presentaciones.map((pres) {
        final presMap = pres as Map<String, dynamic>;
        return ProductVariant(
          id: presMap['id']?.toString() ?? '',
          productId: json['id']?.toString() ?? '',
          name: presMap['presentacion'] ?? '',
          presentation: presMap['presentacion'] ?? '',
          price: (json['precio_venta'] ?? 0).toDouble(),
          sku: presMap['sku_codigo'] ?? '',
          barcode: json['codigo_barras'] ?? '',
          isActive: json['es_vendible'] ?? true,
        );
      }).toList();

      // Si no hay presentaciones, crear una variante base
      if (variants.isEmpty) {
        variants.add(ProductVariant(
          id: '${json['id']}_base',
          productId: json['id']?.toString() ?? '',
          name: 'Presentación base',
          presentation: json['um'] ?? 'Unidad',
          price: (json['precio_venta'] ?? 0).toDouble(),
          sku: json['sku'] ?? '',
          barcode: json['codigo_barras'] ?? '',
          isActive: json['es_vendible'] ?? true,
        ));
      }

      return Product(
        id: json['id']?.toString() ?? '',
        name: json['denominacion'] ?? '',
        description: json['descripcion'] ?? '',
        categoryId: categoria['id']?.toString() ?? '',
        categoryName: categoria['denominacion'] ?? '',
        brand: json['nombre_comercial'] ?? 'Sin marca',
        sku: json['sku'] ?? '',
        barcode: json['codigo_barras'] ?? '',
        basePrice: (json['precio_venta'] ?? 0).toDouble(),
        imageUrl: json['imagen'] ?? '',
        isActive: json['es_vendible'] ?? true,
        createdAt: DateTime.now(), // La API no retorna fecha de creación
        updatedAt: DateTime.now(), // La API no retorna fecha de actualización
        variants: variants,
        // Campos adicionales del RPC optimizado
        nombreComercial: json['nombre_comercial'] ?? '',
        um: json['um'],
        esRefrigerado: json['es_refrigerado'] ?? false,
        esFragil: json['es_fragil'] ?? false,
        esPeligroso: json['es_peligroso'] ?? false,
        esVendible: json['es_vendible'] ?? true,
        stockDisponible: json['stock_disponible'] ?? 0,
        tieneStock: (json['stock_disponible'] ?? 0) > 0,
        subcategorias: subcategorias.cast<Map<String, dynamic>>(),
        presentaciones: presentaciones.cast<Map<String, dynamic>>(),
        multimedias: (json['multimedias'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
        etiquetas: (json['etiquetas'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
        inventario: (json['inventario'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
      );

    } catch (e) {
      print('❌ Error al convertir producto: $e');
      print('📦 JSON problemático: $json');
      rethrow;
    }
  }

  /// Save debug JSON to Documents folder for debugging large RPC responses
  static Future<void> _saveDebugJson(dynamic data, String filename) async {
    try {
      // Get the Documents directory path
      final directory = Directory('/storage/emulated/0/Download');
      
      // Create Documents directory if it doesn't exist
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      // Create the file path
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${directory.path}/${filename}_$timestamp.json');

      // Convert data to pretty JSON
      final jsonString = const JsonEncoder.withIndent('  ').convert(data);

      // Write to file
      await file.writeAsString(jsonString);

      print('✅ Debug JSON guardado en: ${file.path}');
      print('📄 Tamaño del archivo: ${jsonString.length} caracteres');

    } catch (e) {
      print('❌ Error al guardar debug JSON: $e');
      // Don't throw error, just log it since this is debug functionality
    }
  }
}
