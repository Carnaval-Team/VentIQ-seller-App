import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/product.dart';
import 'user_preferences_service.dart';
import 'store_selector_service.dart';
import 'restaurant_service.dart';

class ProductService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  // Getter público para acceder al cliente Supabase
  static SupabaseClient get supabase => _supabase;

  static StoreSelectorService? _storeSelectorService;

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
        throw Exception(
          'No se encontró ID de tienda en las preferencias del usuario',
        );
      }

      print('🔍 Llamando RPC get_productos_completos_by_tienda_optimized');
      print(
        '📍 Parámetros: idTienda=$idTienda, categoryId=$categoryId, soloDisponibles=$soloDisponibles',
      );

      // Llamar a la función RPC optimizada con variantes_disponibles
      final response = await _supabase.rpc(
        'get_productos_completos_by_tienda_optimized',
        params: {
          'id_tienda_param': idTienda,
          'id_categoria_param': categoryId,
          'solo_disponibles_param': soloDisponibles,
        },
      );

      print('📦 Respuesta RPC recibida: ${response.toString()}');
      if (response == null) {
        print('⚠️ Respuesta nula de la función RPC');
        return [];
      }

      // Extraer la lista de productos del JSON de respuesta
      final productosData = response['productos'] as List<dynamic>? ?? [];
      print('📊 Total productos encontrados: ${productosData.length}');

      // DEBUG: Verificar el primer producto para ver qué campos contiene
      if (productosData.isNotEmpty) {
        final primerProducto = productosData.first as Map<String, dynamic>;
        print('🔍 ===== ANÁLISIS DEL PRIMER PRODUCTO =====');
        print('🔍 Claves disponibles: ${primerProducto.keys.toList()}');
        print(
          '🔍 Campo es_elaborado existe: ${primerProducto.containsKey('es_elaborado')}',
        );
        print('🔍 Valor de es_elaborado: ${primerProducto['es_elaborado']}');
        print(
          '🔍 Tipo de es_elaborado: ${primerProducto['es_elaborado'].runtimeType}',
        );
        print('🔍 Denominación: ${primerProducto['denominacion']}');
        print('🔍 ID: ${primerProducto['id']}');
        print('=======================================');
      }

      // Convertir cada producto del JSON al modelo Product
      final productos =
          productosData.map((productoJson) {
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
        'insert_producto_completo_v2',
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
        throw Exception(
          result['message'] ?? 'Error desconocido al insertar producto',
        );
      }
    } catch (e, stackTrace) {
      print('❌ Error en insertProductoCompleto: $e');
      print('📍 StackTrace: $stackTrace');
      throw Exception('Error al insertar producto: $e');
    }
  }

  /// Obtiene subcategorías por categoría
  static Future<List<Map<String, dynamic>>> getSubcategorias(
    int categoryId,
  ) async {
    try {
      print('🔍 Obteniendo subcategorías para categoría: $categoryId');

      final response = await _supabase
          .from('app_dat_subcategorias')
          .select('id,denominacion')
          .eq('idcategoria', categoryId);

      print('📦 Subcategorías obtenidas: ${response.length}');
      return response;
    } catch (e, stackTrace) {
      print('❌ Error al obtener subcategorías: $e');
      print('📍 StackTrace: $stackTrace');
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
    } catch (e, stackTrace) {
      print('❌ Error al obtener presentaciones: $e');
      print('📍 StackTrace: $stackTrace');
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
    } catch (e, stackTrace) {
      print('❌ Error al obtener atributos: $e');
      print('📍 StackTrace: $stackTrace');
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
        throw Exception(
          'No se encontró ID de tienda en las preferencias del usuario',
        );
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
    } catch (e, stackTrace) {
      print('❌ Error al obtener categorías: $e');
      print('📍 StackTrace: $stackTrace');
      throw Exception('Error al obtener categorías: $e');
    }
  }

  /// Crea una nueva categoría para la tienda
  static Future<Map<String, dynamic>> createCategoria({
    required String denominacion,
    required String descripcion,
    String? skuCodigo,
  }) async {
    try {
      // Obtener ID de tienda desde las preferencias del usuario
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();
      if (idTienda == null) {
        throw Exception('No se encontró ID de tienda en las preferencias del usuario');
      }

      print('🏗️ Creando categoría: $denominacion para tienda: $idTienda');

      // Generar SKU código si no se proporciona
      final finalSkuCodigo = skuCodigo ?? _generateSkuFromName(denominacion);
      
      print('🏷️ SKU generado: $finalSkuCodigo');

      // Primero crear la categoría en app_dat_categoria
      final categoriaResponse = await _supabase
          .from('app_dat_categoria')
          .insert({
            'denominacion': denominacion,
            'descripcion': descripcion,
            'sku_codigo': finalSkuCodigo,
            'visible_vendedor': true, // Por defecto visible para vendedores
          })
          .select('id')
          .single();

      final categoriaId = categoriaResponse['id'];
      print('✅ Categoría creada con ID: $categoriaId');

      // Luego asociar la categoría con la tienda
      await _supabase
          .from('app_dat_categoria_tienda')
          .insert({
            'id_categoria': categoriaId,
            'id_tienda': idTienda,
          });

      print('✅ Categoría asociada a la tienda exitosamente');

      return {
        'success': true,
        'id': categoriaId,
        'denominacion': denominacion,
        'message': 'Categoría creada exitosamente',
      };
    } catch (e, stackTrace) {
      print('❌ Error al crear categoría: $e');
      print('📍 StackTrace: $stackTrace');
      throw Exception('Error al crear categoría: $e');
    }
  }

  /// Crea una nueva subcategoría para una categoría específica
  static Future<Map<String, dynamic>> createSubcategoria({
    required int idCategoria,
    required String denominacion,
  }) async {
    try {
      print('🏗️ Creando subcategoría: $denominacion para categoría: $idCategoria');

      final response = await _supabase
          .from('app_dat_subcategorias')
          .insert({
            'idcategoria': idCategoria, // Nombre correcto del campo según schema
            'denominacion': denominacion,
            'sku_codigo': _generateSkuFromName(denominacion), // Campo obligatorio
          })
          .select('id')
          .single();

      final subcategoriaId = response['id'];
      print('✅ Subcategoría creada con ID: $subcategoriaId');

      return {
        'success': true,
        'id': subcategoriaId,
        'denominacion': denominacion,
        'message': 'Subcategoría creada exitosamente',
      };
    } catch (e, stackTrace) {
      print('❌ Error al crear subcategoría: $e');
      print('📍 StackTrace: $stackTrace');
      throw Exception('Error al crear subcategoría: $e');
    }
  }

  /// Genera un SKU código basado en el nombre de la categoría
  static String _generateSkuFromName(String name) {
    // Limpiar el nombre: solo letras y números, convertir a mayúsculas
    final cleanName = name
        .replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), '') // Remover caracteres especiales
        .trim()
        .toUpperCase();
    
    // Tomar las primeras 3 letras de cada palabra, máximo 6 caracteres
    final words = cleanName.split(' ');
    String sku = '';
    
    for (final word in words) {
      if (word.isNotEmpty && sku.length < 6) {
        final letters = word.length >= 3 ? word.substring(0, 3) : word;
        sku += letters;
      }
    }
    
    // Si el SKU es muy corto, rellenar con el nombre completo
    if (sku.length < 3) {
      sku = cleanName.replaceAll(' ', '').substring(0, 
          cleanName.replaceAll(' ', '').length > 6 ? 6 : cleanName.replaceAll(' ', '').length);
    }
    
    // Agregar timestamp para unicidad
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString().substring(8);
    sku = '${sku.substring(0, sku.length > 4 ? 4 : sku.length)}$timestamp';
    
    return sku;
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
      final variants =
          presentaciones.map((pres) {
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
        variants.add(
          ProductVariant(
            id: '${json['id']}_base',
            productId: json['id']?.toString() ?? '',
            name: 'Presentación base',
            presentation: json['um'] ?? 'Unidad',
            price: (json['precio_venta'] ?? 0).toDouble(),
            sku: json['sku'] ?? '',
            barcode: json['codigo_barras'] ?? '',
            isActive: json['es_vendible'] ?? true,
          ),
        );
      }

      return Product(
        id: json['id']?.toString() ?? '',
        name: json['denominacion'] ?? '',
        denominacion: json['denominacion'] ?? '',
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
        esServicio: json['es_servicio'] ?? false,
        stockDisponible: json['stock_disponible'] ?? 0,
        tieneStock: (json['stock_disponible'] ?? 0) > 0,
        subcategorias: subcategorias.cast<Map<String, dynamic>>(),
        presentaciones: presentaciones.cast<Map<String, dynamic>>(),
        multimedias:
            (json['multimedias'] as List<dynamic>? ?? [])
                .cast<Map<String, dynamic>>(),
        etiquetas:
            (json['etiquetas'] as List<dynamic>? ?? [])
                .map((e) => e.toString())
                .toList(),
        inventario:
            (json['inventario'] as List<dynamic>? ?? [])
                .cast<Map<String, dynamic>>(),
        variantesDisponibles:
            (json['variantes_disponibles'] as List<dynamic>? ?? [])
                .cast<Map<String, dynamic>>(),
        esElaborado: json['es_elaborado'] ?? false,
        idProveedor: json['id_proveedor'],
        nombreProveedor: json['nombre_proveedor'] ?? (json['app_dat_proveedor'] as Map<String, dynamic>?)?['denominacion'],
      );

      // Log para verificar que el campo es_elaborado se lee correctamente del RPC
      // final esElaborado = json['es_elaborado'] ?? false;
      // if (esElaborado) {
      //   print('🍽️ Producto ELABORADO detectado - ID: ${json['id']}, Nombre: ${json['denominacion']}');
      // }
    } catch (e, stackTrace) {
      print('❌ Error al convertir producto: $e');
      print('📦 JSON problemático: $json');
      print('📍 StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Save debug JSON to Documents folder for debugging large RPC responses

  /// Elimina un producto completo y todos sus datos relacionados
  static Future<Map<String, dynamic>> deleteProductComplete(
    int productId,
  ) async {
    try {
      print('🗑️ Eliminando producto completo ID: $productId');

      final response = await _supabase.rpc(
        'eliminar_producto_completo',
        params: {'p_id_producto': productId},
      );

      print('📦 Respuesta eliminación: ${response.toString()}');

      if (response == null) {
        throw Exception('Respuesta nula del servidor');
      }

      // La función RPC retorna un JSON directamente
      final result = response as Map<String, dynamic>;

      if (result['success'] == true) {
        print('✅ Producto eliminado exitosamente');
        print(
          '📊 Registros eliminados: ${result['total_registros_eliminados']}',
        );
        print('📋 Tablas afectadas: ${result['tablas_afectadas']}');
      } else {
        print('❌ Error en eliminación: ${result['message']}');
      }

      return result;
    } catch (e, stackTrace) {
      print('❌ Error al eliminar producto: $e');
      print('📍 StackTrace: $stackTrace');
      return {
        'success': false,
        'message': 'Error al eliminar producto: $e',
        'producto_id': productId,
      };
    }
  }

  /// Obtiene las ubicaciones de stock para un producto específico
  static Future<List<Map<String, dynamic>>> getProductStockLocations(
    String productId,
  ) async {
    try {
      print('🔍 Obteniendo ubicaciones de stock para producto: $productId');

      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();
      if (idTienda == null) {
        throw Exception(
          'No se encontró ID de tienda en las preferencias del usuario',
        );
      }

      final response = await _supabase.rpc(
        'fn_listar_inventario_productos_paged2',
        params: {
          'p_id_tienda': idTienda,
          'p_id_producto': int.tryParse(productId),
          'p_mostrar_sin_stock': true,
          'p_limite': 50,
          'p_pagina': 1,
        },
      );

      if (response == null) return [];

      final List<dynamic> data = response as List<dynamic>;

      print('📊 Total registros recibidos    : ${data.length}');

      // ✅ CORRECCIÓN: Agrupar por ubicación para eliminar duplicados
      final Map<String, Map<String, dynamic>> ubicacionesAgrupadas = {};

      for (var item in data) {
        print('📊 Registros recibidos   qw: $item');
        final idUbicacion =
            item['id_ubicacion']?.toString() ??
            item['id_almacen']?.toString() ??
            '0';
        final nombreUbicacion =
            item['ubicacion']?.toString() ??
            item['almacen']?.toString() ??
            'Sin ubicación';
        final cantidad = (item['cantidad_final'] ?? 0).toDouble();
        final reservado = (item['stock_reservado'] ?? 0).toDouble();

        if (!ubicacionesAgrupadas.containsKey(idUbicacion)) {
          // Crear nueva entrada usando idUbicacion como clave del mapa principal
          ubicacionesAgrupadas[idUbicacion] = {
            'id_ubicacion': idUbicacion,
            'ubicacion': nombreUbicacion,
            'cantidad': cantidad,
            'reservado': reservado,
          };
        }
      }

      final ubicacionesUnicas = ubicacionesAgrupadas.values.toList();

      print(
        '📦 Ubicaciones únicas después de agrupar: ${ubicacionesUnicas.length}',
      );
      print('🔍 Ubicaciones encontradas:');
      for (var ub in ubicacionesUnicas) {
        print(
          '   - ${ub['ubicacion']}: ${ub['cantidad']} unidades (${ub['reservado']} reservadas)',
        );
      }

      return ubicacionesUnicas;
    } catch (e, stackTrace) {
      print('❌ Error al obtener ubicaciones de stock: $e');
      print('📍 StackTrace: $stackTrace');
      return [];
    }
  }

  /// Obtiene las operaciones de recepción para un producto específico con paginación
  static Future<Map<String, dynamic>> getProductReceptionOperations(
    String productId, {
    int page = 1,
    int limit = 5,
    String? operationIdFilter,
  }) async {
    try {
      print(
        '🔍 Obteniendo operaciones de recepción para producto: $productId (página: $page, límite: $limit)',
      );

      // Preparar parámetros para la nueva función RPC optimizada
      final Map<String, dynamic> params = {
        'p_id_producto': int.tryParse(productId),
        'p_limite': limit,
        'p_pagina': page,
      };

      // Agregar filtro de ID de operación si se proporciona
      if (operationIdFilter != null && operationIdFilter.isNotEmpty) {
        final operationId = int.tryParse(operationIdFilter);
        if (operationId != null) {
          params['p_id_operacion'] = operationId;
        } else {
          // Si no es un número válido, usar búsqueda general
          params['p_busqueda'] = operationIdFilter;
        }
      }

      final response = await _supabase.rpc(
        'fn_listar_operaciones_producto_especifico',
        params: params,
      );

      if (response == null) {
        return {
          'operations': <Map<String, dynamic>>[],
          'totalCount': 0,
          'currentPage': page,
          'totalPages': 0,
          'hasNextPage': false,
          'hasPreviousPage': false,
        };
      }

      final List<dynamic> data = response as List<dynamic>;

      // Procesar operaciones directamente (ya filtradas por la función SQL)
      List<Map<String, dynamic>> operations = [];
      int totalCount = 0;

      for (var operation in data) {
        // Obtener el total count del primer elemento
        if (totalCount == 0 && operation['total_count'] != null) {
          totalCount = operation['total_count'] as int;
        }

        operations.add({
          'id': operation['id'],
          'fecha': DateTime.parse(operation['created_at']),
          'cantidad': (operation['cantidad_producto'] ?? 0).toDouble(),
          'proveedor': operation['proveedor'] ?? 'No especificado',
          'documento': operation['documento'] ?? 'OP-${operation['id']}',
          'usuario': operation['usuario_email'] ?? 'Sistema',
          'estado': operation['estado_nombre'] ?? 'Completado',
          'total': (operation['importe_producto'] ?? 0).toDouble(),
        });
      }

      // Calcular información de paginación
      final totalPages = (totalCount / limit).ceil();
      final hasNextPage = page < totalPages;
      final hasPreviousPage = page > 1;

      return {
        'operations': operations,
        'totalCount': totalCount,
        'currentPage': page,
        'totalPages': totalPages,
        'hasNextPage': hasNextPage,
        'hasPreviousPage': hasPreviousPage,
      };
    } catch (e, stackTrace) {
      print('❌ Error al obtener operaciones de recepción: $e');
      print('📍 StackTrace: $stackTrace');
      return {
        'operations': <Map<String, dynamic>>[],
        'totalCount': 0,
        'currentPage': page,
        'totalPages': 0,
        'hasNextPage': false,
        'hasPreviousPage': false,
      };
    }
  }

  /// Obtiene el histórico de precios para un producto específico
  static Future<List<Map<String, dynamic>>> getProductPriceHistory(
    String productId,
  ) async {
    try {
      print('🔍 Obteniendo histórico de precios para producto: $productId');

      // Parse productId to int, return empty list if invalid
      final productIdInt = int.tryParse(productId);
      if (productIdInt == null) {
        print('❌ ID de producto inválido: $productId');
        return [];
      }

      final response = await _supabase
          .from('app_dat_precio_venta')
          .select('precio_venta_cup, fecha_desde, fecha_hasta')
          .eq('id_producto', productIdInt)
          .order('fecha_desde', ascending: false)
          .limit(30);

      if (response.isEmpty) return [];

      final priceHistory =
          response
              .map<Map<String, dynamic>>(
                (item) => {
                  'fecha': DateTime.parse(item['fecha_desde']),
                  'precio': (item['precio_venta_cup'] ?? 0.0).toDouble(),
                },
              )
              .toList();

      // ✅ CORRECCIÓN 3: Si solo hay 1 precio, agregar punto actual para mostrar línea
      if (priceHistory.length == 1) {
        print(
          '📊 Solo 1 precio encontrado, agregando punto actual para gráfico',
        );
        priceHistory.add({
          'fecha': DateTime.now(),
          'precio': priceHistory[0]['precio'], // Mismo precio
        });
      }

      return priceHistory;
    } catch (e, stackTrace) {
      print('❌ Error al obtener histórico de precios: $e');
      print('📍 StackTrace: $stackTrace');
      return [];
    }
  }

  /// Obtiene los precios promocionales activos para un producto
  static Future<List<Map<String, dynamic>>> getProductPromotionalPrices(
    String productId,
  ) async {
    try {
      print('🔍 Obteniendo precios promocionales para producto: $productId');

      final response = await _supabase.rpc(
        'fn_listar_promociones_producto',
        params: {'p_id_producto': int.tryParse(productId)},
      );

      print('📊 Respuesta de fn_listar_promociones_producto: $response');

      if (response == null) {
        print('⚠️ Response es null');
        return [];
      }

      final List<dynamic> data = response as List<dynamic>;
      print('📊 Total promociones recibidas: ${data.length}');

      if (data.isEmpty) {
        print('⚠️ No hay promociones para el producto $productId');
        return [];
      }

      // Debug: Mostrar estructura del primer elemento
      if (data.isNotEmpty) {
        print('🔍 Estructura del primer elemento:');
        print('   Keys: ${(data.first as Map).keys.toList()}');
        print('   Values: ${data.first}');
      }

      final promociones =
          data.map<Map<String, dynamic>>((promo) {
            // Convertir valores con logging detallado
            final nombre =
                promo['nombre']?.toString() ?? 'Promoción sin nombre';
            final precioBase = (promo['precio_base'] ?? 0.0).toDouble();
            final valorDescuento = (promo['valor_descuento'] ?? 0.0).toDouble();
            final esRecargo = promo['es_recargo'] == true;

            // ✅ CORRECCIÓN: estado es BOOLEAN, no int
            final estadoBool = promo['estado'] == true;

            // Fechas como strings ISO 8601
            final fechaInicio = promo['fecha_inicio']?.toString();
            final fechaFin = promo['fecha_fin']?.toString();

            print('📋 Procesando promoción: $nombre');
            print('   - Precio base: $precioBase');
            print('   - Descuento: $valorDescuento%');
            print('   - Es recargo: $esRecargo');
            print('   - Estado: $estadoBool');
            print('   - Vigencia: $fechaInicio → $fechaFin');

            final precioPromocional = _calculatePromotionalPrice(
              precioBase,
              valorDescuento,
              esRecargo,
            );

            final activa = _isPromotionActive(
              fechaInicio,
              fechaFin,
              estadoBool, // ✅ Pasar boolean directamente
            );

            print('   - Precio promocional: $precioPromocional');
            print('   - Activa: $activa');

            return {
              'promocion': nombre,
              'precio_original': precioBase,
              'precio_promocional': precioPromocional,
              'vigencia':
                  '${_formatDate(fechaInicio)} - ${_formatDate(fechaFin)}',
              'activa': activa,
            };
          }).toList();

      print('✅ Promociones procesadas: ${promociones.length}');
      return promociones;
    } catch (e, stackTrace) {
      print('❌ Error al obtener precios promocionales: $e');
      print('📍 StackTrace: $stackTrace');
      return [];
    }
  }

  /// Obtiene el histórico de stock para un producto específico
  static Future<List<Map<String, dynamic>>> getProductStockHistory(
    String productId,
    double stockActual,
  ) async {
    try {
      final response = await _supabase.rpc(
        'fn_listar_historial_inventario_producto_v2',
        params: {'p_id_producto': int.tryParse(productId), 'p_dias': 30},
      );

      if (response == null || response.isEmpty) {
        return [
          _createCurrentStockPoint(stockActual, 'Sin operaciones recientes'),
        ];
      }

      final List<dynamic> data = response as List<dynamic>;
      data.sort(
        (a, b) =>
            DateTime.parse(a['fecha']).compareTo(DateTime.parse(b['fecha'])),
      );

      List<Map<String, dynamic>> stockHistory = [];

      // Punto inicial
      if (data.isNotEmpty) {
        final primeraFecha = DateTime.parse(data.first['fecha']);
        stockHistory.add(
          _createStockPoint(
            primeraFecha.subtract(const Duration(days: 1)),
            0.0,
            0.0,
            'Inicial',
            'Stock inicial',
          ),
        );
      }

      // Procesar operaciones usando stock_final de BD
      for (var operation in data) {
        final fecha = DateTime.parse(operation['fecha']);
        final stockFinal = (operation['stock_final'] ?? 0).toDouble();
        final cantidad = (operation['cantidad'] ?? 0).toDouble();
        final tipoOperacion = operation['tipo_operacion'] ?? 'Operación';

        final cantidadConSigno =
            tipoOperacion == 'Recepción' ? cantidad : -cantidad;

        stockHistory.add(
          _createStockPoint(
            fecha,
            stockFinal.abs(),
            cantidadConSigno,
            tipoOperacion,
            operation['documento'] ?? '',
          ),
        );
      }

      // Punto actual si difiere
      final ultimoStock =
          stockHistory.isNotEmpty ? stockHistory.last['cantidad'] : 0.0;
      if ((ultimoStock - stockActual).abs() > 0.01) {
        stockHistory.add(
          _createCurrentStockPoint(stockActual, 'Stock actual del sistema'),
        );
      }

      return stockHistory;
    } catch (e) {
      print('❌ Error al obtener histórico de inventario: $e');
      return [
        _createCurrentStockPoint(stockActual, 'Error al cargar histórico'),
      ];
    }
  }

  // Métodos auxiliares para crear puntos de stock
  static Map<String, dynamic> _createStockPoint(
    DateTime fecha,
    double cantidad,
    double operacionCantidad,
    String tipoOperacion,
    String documento,
  ) {
    return {
      'fecha': fecha,
      'cantidad': cantidad,
      'operacion_cantidad': operacionCantidad,
      'tipo_operacion': tipoOperacion,
      'documento': documento,
    };
  }

  static Map<String, dynamic> _createCurrentStockPoint(
    double stockActual,
    String documento,
  ) {
    return _createStockPoint(
      DateTime.now(),
      stockActual,
      0.0,
      'Stock Actual',
      documento,
    );
  }

  /// Actualiza un producto existente
  static Future<bool> updateProduct(
    String productId,
    Map<String, dynamic> productData,
  ) async {
    try {
      print('🔍 Actualizando producto: $productId');
      print('📦 Datos: $productData');

      final response = await _supabase.rpc(
        'fn_actualizar_producto',
        params: {
          'p_id_producto': int.tryParse(productId),
          'p_denominacion': productData['denominacion'],
          'p_descripcion': productData['descripcion'],
          'p_nombre_comercial': productData['nombre_comercial'],
          'p_sku': productData['sku'],
          'p_codigo_barras': productData['codigo_barras'],
          'p_imagen': productData['imagen'],
          'p_es_vendible': productData['es_vendible'],
          'p_id_categoria': productData['id_categoria'],
          'p_id_proveedor': productData['id_proveedor'],
        },
      );

      return response == true;
    } catch (e, stackTrace) {
      print('❌ Error al actualizar producto: $e');
      print('📍 StackTrace: $stackTrace');
      return false;
    }
  }

  /// Actualiza solo el proveedor de un producto
  static Future<bool> updateProductSupplier(
    int productId,
    int? supplierId,
  ) async {
    try {
      print('🔍 Actualizando proveedor del producto: $productId a $supplierId');

      final response = await _supabase.rpc(
        'fn_actualizar_proveedor_producto',
        params: {
          'p_id_producto': productId,
          'p_id_proveedor': supplierId,
        },
      );

      return response == true;
    } catch (e, stackTrace) {
      print('❌ Error al actualizar proveedor del producto: $e');
      print('📍 StackTrace: $stackTrace');
      return false;
    }
  }

  /// Duplica un producto existente
  static Future<Map<String, dynamic>?> duplicateProduct(
    String productId,
  ) async {
    try {
      print('🔍 Duplicando producto: $productId');

      final response = await _supabase.rpc(
        'fn_duplicar_producto',
        params: {'p_id_producto': int.tryParse(productId)},
      );

      if (response != null && response['success'] == true) {
        return response;
      }
      return null;
    } catch (e, stackTrace) {
      print('❌ Error al duplicar producto: $e');
      print('📍 StackTrace: $stackTrace');
      return null;
    }
  }

  /// Elimina un producto
  static Future<bool> deleteProduct(String productId) async {
    try {
      print('🔍 Eliminando producto: $productId');

      final response = await _supabase.rpc(
        'fn_eliminar_producto_completo',
        params: {'p_id_producto': int.tryParse(productId)},
      );

      return response == true;
    } catch (e, stackTrace) {
      print('❌ Error al eliminar producto: $e');
      print('📍 StackTrace: $stackTrace');
      return false;
    }
  }

  /// Detecta inconsistencias en el histórico de stock de un producto
  static Future<void> detectStockInconsistencies(String productId) async {
    try {
      print(
        '🔍 Detectando inconsistencias en histórico de stock para producto: $productId',
      );

      final response = await _supabase.rpc(
        'fn_detectar_inconsistencias_stock',
        params: {'p_id_producto': int.tryParse(productId), 'p_dias': 30},
      );

      if (response == null) {
        print('✅ No se encontraron inconsistencias en el stock');
        return;
      }

      final List<dynamic> inconsistencias = response as List<dynamic>;

      if (inconsistencias.isEmpty) {
        print('✅ No se encontraron inconsistencias en el stock');
        return;
      }

      print('⚠️ INCONSISTENCIAS DETECTADAS: ${inconsistencias.length}');
      print('');

      for (int i = 0; i < inconsistencias.length; i++) {
        var inc = inconsistencias[i];
        print('--- Inconsistencia ${i + 1} ---');
        print('Operación ID: ${inc['operacion_id']}');
        print('Número de operación: ${inc['operacion_numero']}');
        print('Tipo: ${inc['tipo_operacion']}');
        print('Fecha: ${inc['fecha']}');
        print('Cantidad: ${inc['cantidad']}');
        print('Stock inicial (actual): ${inc['stock_inicial_actual']}');
        print('Stock final (anterior): ${inc['stock_final_anterior']}');
        print('Diferencia: ${inc['diferencia']}');
        print('Documento: ${inc['documento']}');
        print('');
      }

      // Calcular total de discrepancias
      double totalDiscrepancia = 0;
      for (var inc in inconsistencias) {
        totalDiscrepancia += (inc['diferencia'] ?? 0).toDouble();
      }

      print('📊 RESUMEN DE INCONSISTENCIAS:');
      print('Total de operaciones con problemas: ${inconsistencias.length}');
      print('Suma total de discrepancias: $totalDiscrepancia');
      print('');
    } catch (e, stackTrace) {
      print('❌ Error al detectar inconsistencias: $e');
      print('📍 StackTrace: $stackTrace');
    }
  }

  /// Obtiene el ID de tienda del usuario con múltiples estrategias de fallback
  static Future<int?> _getStoreId([int? providedStoreId]) async {
    try {
      // 1. Usar ID proporcionado si está disponible
      if (providedStoreId != null) {
        print('🏪 Usando ID de tienda proporcionado: $providedStoreId');
        return providedStoreId;
      }

      // 2. Intentar obtener desde el servicio de selector de tienda
      _storeSelectorService ??= StoreSelectorService();

      final selectedStoreId = await _storeSelectorService!.getSelectedStoreId();
      if (selectedStoreId != null) {
        print('🏪 ID de tienda desde selector: $selectedStoreId');
        return selectedStoreId;
      }

      // 3. Inicializar el servicio si no está inicializado
      if (!_storeSelectorService!.isInitialized) {
        print('🔄 Inicializando servicio de selector de tienda...');
        await _storeSelectorService!.initialize();

        final storeIdAfterInit =
            await _storeSelectorService!.getSelectedStoreId();
        if (storeIdAfterInit != null) {
          print('🏪 ID de tienda después de inicializar: $storeIdAfterInit');
          return storeIdAfterInit;
        }
      }

      // 4. Fallback: usar la primera tienda disponible
      final stores = _storeSelectorService!.userStores;
      if (stores.isNotEmpty) {
        final firstStoreId = stores.first.id;
        print(
          '🏪 Usando primera tienda disponible como fallback: $firstStoreId',
        );
        return firstStoreId;
      }

      print('❌ No se pudo obtener ID de tienda por ningún método');
      return null;
    } catch (e, stackTrace) {
      print('❌ Error al obtener ID de tienda: $e');
      print('📍 StackTrace: $stackTrace');
      return null;
    }
  }

  static double _calculatePromotionalPrice(
    double basePrice,
    double discount,
    bool isCharge,
  ) {
    if (isCharge) {
      return basePrice + (basePrice * discount / 100);
    } else {
      return basePrice - (basePrice * discount / 100);
    }
  }

  static String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return 'N/A';
    try {
      // Manejar tanto formato ISO 8601 como TIMESTAMP de PostgreSQL
      final date = DateTime.parse(dateStr);
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    } catch (e) {
      print('⚠️ Error formateando fecha: $dateStr - $e');
      return 'N/A';
    }
  }

  static bool _isPromotionActive(
    String? startDate,
    String? endDate,
    bool estado, // ✅ Cambiar de int? a bool
  ) {
    // ✅ CORRECCIÓN: Validar boolean directamente
    if (startDate == null || endDate == null || !estado) {
      return true;
    }

    try {
      final now = DateTime.now();
      final start = DateTime.parse(startDate);
      final end = DateTime.parse(endDate);

      // Verificar que esté dentro del rango de fechas
      final enVigencia = now.isAfter(start) && now.isBefore(end);

      print('🔍 Validando vigencia:');
      print('   - Ahora: $now');
      print('   - Inicio: $start');
      print('   - Fin: $end');
      print('   - En vigencia: $enVigencia');
      print('   - Estado activo: $estado');

      return enVigencia && estado;
    } catch (e) {
      print('❌ Error validando promoción activa: $e');
      return false;
    }
  }

  /// Actualiza los datos de una operación de recepción (precios, facturas, descuentos)
  static Future<Map<String, dynamic>> updateReceptionOperation({
    required String operationId,
    String? entregadoPor,
    String? recibidoPor,
    double? montoTotal,
    String? observaciones,
    String? numeroFactura,
    DateTime? fechaFactura,
    double? montoFactura,
    String? monedaFactura,
    String? pdfFactura,
    String? observacionesCompra,
    List<Map<String, dynamic>>? productosData,
  }) async {
    try {
      print('🔍 Actualizando operación de recepción: $operationId');

      // Preparar parámetros para la función
      final params = <String, dynamic>{
        'p_id_operacion': int.tryParse(operationId),
      };

      // Agregar parámetros opcionales solo si no son null
      if (entregadoPor != null) params['p_entregado_por'] = entregadoPor;
      if (recibidoPor != null) params['p_recibido_por'] = recibidoPor;
      if (montoTotal != null) params['p_monto_total'] = montoTotal;
      if (observaciones != null) params['p_observaciones'] = observaciones;
      if (numeroFactura != null) params['p_numero_factura'] = numeroFactura;
      if (fechaFactura != null)
        params['p_fecha_factura'] =
            fechaFactura.toIso8601String().split('T')[0];
      if (montoFactura != null) params['p_monto_factura'] = montoFactura;
      if (monedaFactura != null) params['p_moneda_factura'] = monedaFactura;
      if (pdfFactura != null) params['p_pdf_factura'] = pdfFactura;
      if (observacionesCompra != null)
        params['p_observaciones_compra'] = observacionesCompra;
      if (productosData != null && productosData.isNotEmpty) {
        params['p_productos_data'] = productosData;
      }

      print('📤 Parámetros enviados: $params');

      final response = await _supabase.rpc(
        'fn_actualizar_operacion_recepcion',
        params: params,
      );

      print('📥 Respuesta recibida: $response');

      if (response != null && response is Map<String, dynamic>) {
        if (response['success'] == true) {
          print('✅ Operación de recepción actualizada correctamente');
          return {
            'success': true,
            'message':
                response['message'] ?? 'Operación actualizada correctamente',
            'data': response,
          };
        } else {
          print('❌ Error en la actualización: ${response['message']}');
          return {
            'success': false,
            'message':
                response['message'] ??
                'Error desconocido al actualizar la operación',
          };
        }
      } else {
        print('❌ Respuesta inválida del servidor');
        return {'success': false, 'message': 'Respuesta inválida del servidor'};
      }
    } catch (e, stackTrace) {
      print('❌ Error al actualizar operación de recepción: $e');
      print('📍 StackTrace: $stackTrace');
      return {
        'success': false,
        'message': 'Error al actualizar la operación: $e',
      };
    }
  }

  /// Obtiene los detalles completos de una operación de recepción para edición
  static Future<Map<String, dynamic>?> getReceptionOperationDetails(
    String operationId,
  ) async {
    try {
      print('🔍 Obteniendo detalles de operación de recepción: $operationId');

      // Parse the operation ID and validate it
      final parsedId = int.tryParse(operationId);
      if (parsedId == null) {
        print('❌ ID de operación inválido: $operationId');
        return null;
      }

      // First get the operation details
      final operationResponse =
          await _supabase
              .from('app_dat_operaciones')
              .select('*')
              .eq('id', parsedId)
              .single();

      // Then get the related products for this operation from reception products table
      final productsResponse = await _supabase
          .from('app_dat_recepcion_productos')
          .select('''
            *,
            app_dat_producto(id, denominacion, sku)
          ''')
          .eq('id_operacion', parsedId);

      // Combine the data
      final result = Map<String, dynamic>.from(operationResponse);
      result['app_dat_recepcion_productos'] = productsResponse;

      print('📥 Detalles obtenidos: $result');
      return result;
    } catch (e, stackTrace) {
      print('❌ Error al obtener detalles de operación: $e');
      print('📍 StackTrace: $stackTrace');
      return null;
    }
  }

  /// Obtiene un producto completo por ID con todas sus variantes y presentaciones configuradas
  static Future<Product?> getProductoCompletoById(int productId) async {
    try {
      print('🔍 Obteniendo producto completo por ID: $productId');

      // Obtener datos básicos del producto
      final productResponse = await _supabase
          .from('app_dat_producto')
          .select('''
            id,
            denominacion,
            denominacion_corta,
            descripcion,
            descripcion_corta,
            nombre_comercial,
            sku,
            codigo_barras,
            imagen,
            es_refrigerado,
            es_fragil,
            es_peligroso,
            es_vendible,
            es_comprable,
            es_inventariable,
            es_por_lotes,
            es_servicio,
            es_elaborado,
            um,
            created_at,
            id_categoria,
            dias_alert_caducidad,
            id_proveedor,
            app_dat_proveedor ( denominacion )
          ''')
          .eq('id', productId)
          .limit(1);

      if (productResponse.isEmpty) {
        print('⚠️ No se encontró producto con ID: $productId');
        return null;
      }

      final productData = productResponse.first as Map<String, dynamic>;

      // Obtener categoría
      final categoria = await _supabase
          .from('app_dat_categoria')
          .select('id, denominacion')
          .eq('id', productData['id_categoria'])
          .limit(1);

      final categoriaData = categoria.isNotEmpty
          ? categoria.first as Map<String, dynamic>
          : {'id': '', 'denominacion': 'Sin categoría'};

      // Obtener presentaciones con información de la tabla de presentaciones
      final presentacionesResponse = await _supabase
          .from('app_dat_producto_presentacion')
          .select('''
            id,
            id_producto,
            id_presentacion,
            cantidad,
            es_base,
            precio_promedio,
            app_nom_presentacion!inner(id, denominacion)
          ''')
          .eq('id_producto', productId);

      final presentaciones = presentacionesResponse
          .map<Map<String, dynamic>>((item) {
            final itemMap = item as Map<String, dynamic>;
            final nomPres = itemMap['app_nom_presentacion'] as Map<String, dynamic>?;
            return {
              'id': itemMap['id'],
              'id_producto': itemMap['id_producto'],
              'id_presentacion': itemMap['id_presentacion'],
              'cantidad': itemMap['cantidad'],
              'es_base': itemMap['es_base'],
              'precio_promedio': itemMap['precio_promedio'] ?? 0.0,
              'presentacion': nomPres?['denominacion'] ?? 'Presentación',
            };
          })
          .toList();

      // Obtener multimedias
      final multimediasResponse = await _supabase
          .from('app_dat_producto_multimedias')
          .select('id, media, created_at')
          .eq('id_producto', productId);

      // Obtener etiquetas
      final etiquetasResponse = await _supabase
          .from('app_dat_producto_etiquetas')
          .select('etiqueta')
          .eq('id_producto', productId);

      final etiquetas = etiquetasResponse
          .map<String>((item) => (item as Map<String, dynamic>)['etiqueta'] as String)
          .toList();

      // Obtener subcategorías asignadas al producto (no todas de la categoría)
      final subcategoriasResponse = await _supabase
          .from('app_dat_productos_subcategorias')
          .select('''
            id,
            id_producto,
            id_sub_categoria,
            app_dat_subcategorias!inner(id, denominacion, idcategoria)
          ''')
          .eq('id_producto', productId);
      
      // Mapear la respuesta para obtener solo los datos de subcategoría
      final subcategoriasMapped = subcategoriasResponse
          .map<Map<String, dynamic>>((item) {
            final itemMap = item as Map<String, dynamic>;
            final subcat = itemMap['app_dat_subcategorias'] as Map<String, dynamic>?;
            print('📋 Subcategoría encontrada: ${subcat?['denominacion']}');
            return {
              'id': subcat?['id'],
              'denominacion': subcat?['denominacion'],
              'idcategoria': subcat?['idcategoria'],
            };
          })
          .toList();
      
      print('✅ Total subcategorías obtenidas: ${subcategoriasMapped.length}');

      // Obtener precio de venta (tabla separada)
      double precioVenta = 0.0;
      try {
        final precioVentaResponse = await _supabase
            .from('app_dat_precio_venta')
            .select('precio_venta_cup')
            .eq('id_producto', productId)
            .order('fecha_desde', ascending: false)
            .limit(1);

        if (precioVentaResponse.isNotEmpty) {
          precioVenta = (precioVentaResponse.first['precio_venta_cup'] as num?)?.toDouble() ?? 0.0;
          print('💰 Precio de venta obtenido: $precioVenta');
        }
      } catch (e) {
        print('⚠️ Error obteniendo precio de venta: $e');
      }

      print('✅ Producto obtenido: ${productData['denominacion']}');
      print('📊 Presentaciones encontradas: ${presentaciones.length}');

      // Construir el objeto Product
      return Product(
        id: productData['id'].toString(),
        name: productData['denominacion'] ?? '',
        denominacion: productData['denominacion'] ?? '',
        denominacionCorta: productData['denominacion_corta'],
        description: productData['descripcion'] ?? '',
        descripcionCorta: productData['descripcion_corta'],
        categoryId: categoriaData['id'].toString(),
        categoryName: categoriaData['denominacion'] ?? '',
        brand: productData['nombre_comercial'] ?? 'Sin marca',
        sku: productData['sku'] ?? '',
        barcode: productData['codigo_barras'] ?? '',
        codigoBarras: productData['codigo_barras'],
        basePrice: precioVenta, // Precio de venta obtenido de app_dat_precio_venta
        imageUrl: productData['imagen'] ?? '',
        isActive: productData['es_vendible'] ?? true,
        createdAt: DateTime.parse(productData['created_at'] ?? DateTime.now().toIso8601String()),
        updatedAt: DateTime.now(), // Usar fecha actual ya que no existe updated_at en BD
        nombreComercial: productData['nombre_comercial'],
        um: productData['um'],
        esRefrigerado: productData['es_refrigerado'] ?? false,
        esFragil: productData['es_fragil'] ?? false,
        esPeligroso: productData['es_peligroso'] ?? false,
        esVendible: productData['es_vendible'] ?? true,
        esComprable: productData['es_comprable'] ?? true,
        esInventariable: productData['es_inventariable'] ?? true,
        esPorLotes: productData['es_por_lotes'] ?? false,
        esServicio: productData['es_servicio'] ?? false,
        precioVenta: precioVenta, // Precio de venta obtenido de app_dat_precio_venta
        stockDisponible: 0, // Se carga en otra parte
        tieneStock: false,
        subcategorias: subcategoriasMapped,
        presentaciones: presentaciones,
        multimedias: multimediasResponse.cast<Map<String, dynamic>>(),
        etiquetas: etiquetas,
        inventario: const [],
        variantesDisponibles: const [],
        esOferta: false,
        precioOferta: 0.0,
        stockMinimo: 0,
        stockMaximo: 0,
        diasAlertCaducidad: (productData['dias_alert_caducidad'] as num?)?.toInt() ?? 0,
        unidadMedida: productData['um'],
        esElaborado: productData['es_elaborado'] ?? false,
        idProveedor: productData['id_proveedor'],
        nombreProveedor: (productData['app_dat_proveedor'] as Map<String, dynamic>?)?['denominacion'],
      );
    } catch (e, stackTrace) {
      print('❌ Error obteniendo producto completo: $e');
      print('📍 StackTrace: $stackTrace');
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> getProductsForIngredients() async {
    try {
      print(
        '🔍 ===== INICIANDO CARGA RÁPIDA DE PRODUCTOS PARA INGREDIENTES =====',
      );

      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();
      if (idTienda == null) {
        throw Exception(
          'No se encontró ID de tienda en las preferencias del usuario',
        );
      }

      final response = await _supabase
          .from('app_dat_producto')
          .select('id, denominacion, sku, imagen, es_elaborado')
          .eq('id_tienda', idTienda)
          .eq('es_vendible', true)
          .eq('es_inventariable', true)
          .order('denominacion');

      print('📦 Productos obtenidos: ${response.length}');

      // Convertir directamente sin cálculos de costo
      final List<Map<String, dynamic>> productos =
          response.map((item) {
            return {
              'id': item['id'],
              'denominacion': item['denominacion'],
              'sku': item['sku'],
              'imagen': item['imagen'],
              'es_elaborado': item['es_elaborado'] ?? false,
              'precio_venta': 0.0, // Valor por defecto
              'stock_disponible': 0, // Valor por defecto
            };
          }).toList();

      print(
        '✅ Procesamiento completado rápidamente: ${productos.length} productos',
      );

      // DEBUG: Mostrar detalles de los primeros 3 productos
      if (productos.isNotEmpty) {
        print('🔍 ===== ANÁLISIS DE PRODUCTOS RECIBIDOS (SIN COSTOS) =====');
        for (int i = 0; i < productos.length && i < 3; i++) {
          final producto = productos[i];
          print('--- Producto ${i + 1} ---');
          print('ID: ${producto['id']}');
          print('Denominación: ${producto['denominacion']}');
          print('SKU: ${producto['sku']}');
          print('Es elaborado: ${producto['es_elaborado']}');
          print('---');
        }
        print('=======================================');
      }

      return productos;
    } catch (e) {
      print('Error obteniendo productos para ingredientes: $e');
      return [];
    }
  }

  /// Obtiene unidades de medida disponibles
  static Future<List<Map<String, dynamic>>> getUnidadesMedida() async {
    try {
      final response = await _supabase
          .from('app_nom_unidades_medida')
          .select('''
            id,
            denominacion,
            abreviatura,
            tipo_unidad,
            es_base
          ''')
          .order('denominacion');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error obteniendo unidades de medida: $e');
      return [
        {'id': 1, 'denominacion': 'Unidad', 'abreviatura': 'und'},
        {'id': 2, 'denominacion': 'Kilogramo', 'abreviatura': 'kg'},
        {'id': 3, 'denominacion': 'Litro', 'abreviatura': 'l'},
        {'id': 4, 'denominacion': 'Gramo', 'abreviatura': 'g'},
        {'id': 5, 'denominacion': 'Mililitro', 'abreviatura': 'ml'},
      ];
    }
  }

  /// Obtiene la presentación base de un producto
  static Future<Map<String, dynamic>?> getBasePresentacion(
    int productId,
  ) async {
    try {
      print('🔍 Obteniendo presentación base para producto: $productId');

      final response = await _supabase
          .from('app_dat_producto_presentacion')
          .select('''
          id,
          id_presentacion,
          cantidad,
          app_nom_presentacion!inner(id, denominacion)
        ''')
          .eq('id_producto', productId)
          .eq('es_base', true)
          .limit(1);

      if (response.isNotEmpty) {
        final basePresentation = response.first;
        print(
          '✅ Presentación base encontrada: ${basePresentation['app_nom_presentacion']['denominacion']}',
        );
        return {
          'id_presentacion': basePresentation['id'],
          'cantidad': basePresentation['cantidad'],
          'denominacion':
              basePresentation['app_nom_presentacion']['denominacion'],
        };
      }

      print('⚠️ No se encontró presentación base para producto: $productId');
      return null;
    } catch (e) {
      print('❌ Error obteniendo presentación base: $e');
      return null;
    }
  }

  /// Convierte cantidad de cualquier presentación a presentación base
  static Future<double> convertToBasePresentacion({
    required int productId,
    required int fromPresentacionId,
    required double cantidad,
  }) async {
    try {
      print('🔄 ===== CONVERSIÓN A PRESENTACIÓN BASE =====');
      print('🔄 Producto: $productId');
      print('🔄 Desde presentación: $fromPresentacionId');
      print('🔄 Cantidad original: $cantidad');

      // Obtener presentación base
      final basePresentation = await getBasePresentacion(productId);
      if (basePresentation == null) {
        print('❌ No se pudo obtener presentación base');
        return cantidad; // Retornar cantidad original si no hay presentación base
      }

      final basePresentacionId = basePresentation['id_presentacion'];

      // Si ya es la presentación base, no convertir
      if (fromPresentacionId == basePresentacionId) {
        print('✅ Ya es presentación base, no se requiere conversión');
        return cantidad;
      }

      // Obtener datos de la presentación origen
      final fromResponse = await _supabase
          .from('app_dat_producto_presentacion')
          .select('cantidad')
          .eq('id_producto', productId)
          .eq('id_presentacion', fromPresentacionId)
          .limit(1);

      if (fromResponse.isEmpty) {
        print('❌ No se encontró presentación origen: $fromPresentacionId');
        return cantidad;
      }

      final fromCantidad = fromResponse.first['cantidad'] as double;
      final baseCantidad = basePresentation['cantidad'] as double;

      // Calcular conversión
      // Ejemplo: 1 Caja = 24 Unidades, 1 Unidad = 1 Unidad base
      // Si tengo 2 Cajas, necesito: 2 * 24 / 1 = 48 Unidades base
      final cantidadEnBase = (cantidad * fromCantidad) / baseCantidad;

      print(
        '🔄 Presentación origen: $fromCantidad unidades base por presentación',
      );
      print(
        '🔄 Presentación base: $baseCantidad unidades base por presentación',
      );
      print(
        '🔄 Cálculo: ($cantidad * $fromCantidad) / $baseCantidad = $cantidadEnBase',
      );
      print('✅ Cantidad convertida a presentación base: $cantidadEnBase');

      return cantidadEnBase;
    } catch (e) {
      print('❌ Error en conversión a presentación base: $e');
      return cantidad; // Retornar cantidad original en caso de error
    }
  }

  /// Obtiene información completa de presentaciones de un producto
  static Future<List<Map<String, dynamic>>> getPresentacionesCompletas(
    int productId,
  ) async {
    try {
      print('🔍 Obteniendo presentaciones completas para producto: $productId');

      final response = await _supabase
          .from('app_dat_producto_presentacion')
          .select('''
          id_presentacion,
          cantidad,
          es_base,
          app_nom_presentacion!inner(id, denominacion)
        ''')
          .eq('id_producto', productId)
          .order('es_base', ascending: false); // Base primero

      final presentaciones =
          response
              .map<Map<String, dynamic>>(
                (item) => {
                  'id_presentacion': item['id_presentacion'],
                  'cantidad': item['cantidad'],
                  'es_base': item['es_base'],
                  'denominacion': item['app_nom_presentacion']['denominacion'],
                },
              )
              .toList();

      print('✅ Presentaciones obtenidas: ${presentaciones.length}');
      for (final pres in presentaciones) {
        print(
          '   - ${pres['denominacion']}: ${pres['cantidad']} ${pres['es_base'] ? '(BASE)' : ''}',
        );
      }

      return presentaciones;
    } catch (e) {
      print('❌ Error obteniendo presentaciones completas: $e');
      return [];
    }
  }

  /// Obtiene las unidades de medida por presentación de un producto
  static Future<List<Map<String, dynamic>>> getPresentacionUnidadMedida(
    int productId,
  ) async {
    try {
      print(
        '🔍 Obteniendo unidades de medida por presentación para producto: $productId',
      );

      final response = await _supabase
          .from('app_dat_presentacion_unidad_medida')
          .select('''
            id,
            id_presentacion,
            id_unidad_medida,
            cantidad_um,
            app_nom_presentacion!inner(id, denominacion),
            app_nom_unidades_medida!inner(id, denominacion, abreviatura)
          ''')
          .eq('id_producto', productId);

      print(
        '📦 Unidades de medida por presentación obtenidas: ${response.length}',
      );
      return List<Map<String, dynamic>>.from(response);
    } catch (e, stackTrace) {
      print('❌ Error obteniendo unidades de medida por presentación: $e');
      print('📍 StackTrace: $stackTrace');
      return [];
    }
  }

  /// Obtiene los ingredientes de un producto elaborado
  static Future<List<Map<String, dynamic>>> getProductIngredients(
    String productId,
  ) async {
    try {
      print('🍽️ Obteniendo ingredientes para producto elaborado: $productId');

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
          .eq('id_producto_elaborado', int.tryParse(productId) ?? 0);

      print('📦 Ingredientes obtenidos: ${response.length}');

      return response.map<Map<String, dynamic>>((item) {
        final producto = item['app_dat_producto'] as Map<String, dynamic>;

        return {
          'id': item['id'],
          'cantidad_necesaria': (item['cantidad_necesaria'] ?? 0.0).toDouble(),
          'unidad_medida': item['unidad_medida'] ?? 'und',
          'producto_id': producto['id'],
          'producto_nombre': producto['denominacion'] ?? 'Sin nombre',
          'producto_sku': producto['sku'] ?? '',
          'producto_imagen': producto['imagen'] ?? '',
        };
      }).toList();
    } catch (e, stackTrace) {
      print('❌ Error al obtener ingredientes: $e');
      print('📍 StackTrace: $stackTrace');
      return [];
    }
  }

  /// Inserta las unidades de medida por presentación en la nueva tabla
  static Future<void> insertPresentacionUnidadMedida({
    required int productId,
    required List<Map<String, dynamic>> presentacionUnidadMedidaData,
  }) async {
    try {
      print('🔧 ===== INSERTANDO UNIDADES DE MEDIDA POR PRESENTACIÓN =====');
      print('🔧 Producto ID: $productId');
      print(
        '🔧 Total registros a insertar: ${presentacionUnidadMedidaData.length}',
      );

      if (presentacionUnidadMedidaData.isEmpty) {
        print(
          '⚠️ No hay datos de unidades de medida por presentación para insertar',
        );
        return;
      }

      // Insertar cada registro individualmente para mejor control de errores
      for (int i = 0; i < presentacionUnidadMedidaData.length; i++) {
        final data = presentacionUnidadMedidaData[i];

        try {
          print('🔧 Insertando registro ${i + 1}: $data');

          final response =
              await _supabase
                  .from('app_dat_presentacion_unidad_medida')
                  .insert({
                    'id_producto': productId,
                    'id_presentacion': data['id_presentacion'],
                    'id_unidad_medida': data['id_unidad_medida'],
                    'cantidad_um': data['cantidad_um'],
                  })
                  .select()
                  .single();

          print(
            '✅ Registro ${i + 1} insertado exitosamente: ${response['id']}',
          );
        } catch (e) {
          print('❌ Error insertando registro ${i + 1}: $e');
          print('❌ Datos del registro: $data');
          // Continuar con los demás registros
        }
      }

      print(
        '✅ Proceso de inserción de unidades de medida por presentación completado',
      );
    } catch (e, stackTrace) {
      print('❌ Error general en insertPresentacionUnidadMedida: $e');
      print('📍 StackTrace: $stackTrace');
      throw Exception(
        'Error al insertar unidades de medida por presentación: $e',
      );
    }
  }

  /// Inserta ingredientes para un producto elaborado
  static Future<bool> insertProductIngredients({
    required int productId,
    required List<Map<String, dynamic>> ingredientes,
    required bool esServicio,
  }) async {
    try {
      print('🍽️ ===== INICIANDO INSERCIÓN DE INGREDIENTES =====');
      print('🍽️ Producto elaborado ID: $productId');
      print('🍽️ Total ingredientes recibidos: ${ingredientes.length}');
      print('🍽️ Datos completos recibidos: $ingredientes');

      if (ingredientes.isEmpty) {
        print('⚠️ ADVERTENCIA: Lista de ingredientes está vacía');
        return false;
      }

      // Preparar datos para la inserción
      final ingredientesData =
          ingredientes.map((ingrediente) {
            print('🔍 Procesando ingrediente: $ingrediente');

            final data = {
              'id_producto_elaborado': productId,
              'id_ingrediente':
                  ingrediente['id_producto'], // ID del producto ingrediente
              'cantidad_necesaria':
                  ingrediente['cantidad'], // Cantidad necesaria
              'unidad_medida': ingrediente['unidad_medida'], // Unidad de medida
            };

            print('🔍 Datos preparados para inserción: $data');
            return data;
          }).toList();

      print('🍽️ Datos finales para insertar: $ingredientesData');

      // Insertar cada ingrediente individualmente para mejor control de errores
      int insertedCount = 0;
      for (final ingredienteData in ingredientesData) {
        try {
          print('📤 Insertando ingrediente: $ingredienteData');

          await _supabase
              .from('app_dat_producto_ingredientes')
              .insert(ingredienteData);

          insertedCount++;
          print(
            '✅ Ingrediente insertado exitosamente: ${ingredienteData['id_ingrediente']} - Cantidad: ${ingredienteData['cantidad_necesaria']}',
          );
        } catch (e) {
          print(
            '❌ ERROR insertando ingrediente específico ${ingredienteData['id_ingrediente']}: $e',
          );
          print('❌ Datos que causaron error: $ingredienteData');
          // Continuar con los demás ingredientes
        }
      }

      print('📊 ===== RESUMEN INSERCIÓN INGREDIENTES =====');
      print('📊 Ingredientes procesados: ${ingredientes.length}');
      print('📊 Ingredientes insertados exitosamente: $insertedCount');
      print(
        '📊 Ingredientes con error: ${ingredientes.length - insertedCount}',
      );

      final success = insertedCount > 0;
      print('📊 Resultado final: ${success ? "ÉXITO" : "FALLO"}');

      // Si se insertaron ingredientes exitosamente, actualizar el campo es_elaborado del producto
      if (success && !esServicio) {
        try {
          print(
            '🔄 Actualizando campo es_elaborado = true para producto ID: $productId',
          );

          await _supabase
              .from('app_dat_producto')
              .update({'es_elaborado': true})
              .eq('id', productId);

          print('✅ Campo es_elaborado actualizado exitosamente a TRUE');
        } catch (e) {
          print('❌ ERROR al actualizar campo es_elaborado: $e');
          // No fallar la operación completa por este error
        }
      }

      return success; // Retorna true si al menos un ingrediente se insertó
    } catch (e, stackTrace) {
      print('❌ ===== ERROR CRÍTICO EN insertProductIngredients =====');
      print('❌ Error: $e');
      print('❌ StackTrace: $stackTrace');
      print('❌ ProductId: $productId');
      print('❌ Ingredientes: $ingredientes');
      return false;
    }
  }

  /// Obtiene la unidad de medida base de un producto
  /// Obtiene la unidad de medida base de un producto
  static Future<int?> getUnidadMedidaProducto(int productId) async {
    try {
      print('🔍 Obteniendo unidad de medida para producto $productId');

      final response =
          await _supabase
              .from('app_dat_producto')
              .select('um')
              .eq('id', productId)
              .single();

      final umRaw = response['um'];
      print('🔍 DEBUG: um raw = $umRaw (tipo: ${umRaw.runtimeType})');

      int? unidadMedida;
      if (umRaw is int) {
        unidadMedida = umRaw;
      } else if (umRaw is String) {
        // Si es string, convertir a int
        unidadMedida = int.tryParse(umRaw);
        if (unidadMedida == null) {
          print(
            '⚠️ No se pudo convertir "$umRaw" a int, usando mapeo de string',
          );
          // Usar el mismo mapeo que para ingredientes
          unidadMedida = await _getUnidadIdFromString(umRaw);
        }
      }

      print('📦 Unidad de medida del producto $productId: $unidadMedida');

      return unidadMedida;
    } catch (e) {
      print('❌ Error obteniendo unidad de medida del producto $productId: $e');
      return null;
    }
  }

  static Future<double> _calcularCostoUnitarioIngrediente(int productId) async {
    try {
      print('🔧 Iniciando cálculo de costo para producto ID: $productId');

      // 1. Obtener presentación base
      print('📋 Paso 1: Obteniendo presentación base...');
      final basePresentacion = await getBasePresentacion(productId);
      if (basePresentacion == null) {
        print('❌ No se encontró presentación base para producto $productId');
        return 0.0;
      }
      print(
        '✅ Presentación base encontrada: ${basePresentacion['denominacion']} (ID: ${basePresentacion['id_presentacion']})',
      );

      // 2. Obtener última recepción por compra - CONSULTA CORREGIDA
      print('📋 Paso 2: Buscando última recepción por compra...');

      // Primero intentemos una consulta más simple para verificar la estructura
      final recepcionResponse = await _supabase
          .from('app_dat_recepcion_productos')
          .select('costo_real, cantidad, created_at')
          .eq('id_producto', productId)
          .eq('id_presentacion', basePresentacion['id_presentacion'])
          .order('created_at', ascending: false)
          .limit(1);

      print(
        '📊 Consulta de recepción ejecutada. Resultados encontrados: ${recepcionResponse.length}',
      );

      if (recepcionResponse.isEmpty) {
        print(
          '❌ No se encontraron recepciones para producto $productId con presentación ${basePresentacion['id_presentacion']}',
        );

        // Intentar obtener cualquier recepción del producto sin filtrar por presentación
        print('🔄 Intentando buscar recepciones sin filtro de presentación...');
        final recepcionAnyResponse = await _supabase
            .from('app_dat_recepcion_productos')
            .select('costo_real, cantidad, created_at, id_presentacion')
            .eq('id_producto', productId)
            .order('created_at', ascending: false)
            .limit(1);

        if (recepcionAnyResponse.isEmpty) {
          print('❌ No se encontraron recepciones para producto $productId');
          return 0.0;
        } else {
          print(
            '✅ Encontrada recepción con presentación diferente: ${recepcionAnyResponse.first}',
          );
          // Usar esta recepción aunque sea de otra presentación
          final recepcion = recepcionAnyResponse.first;
          final costoReal = (recepcion['costo_real'] ?? 0.0).toDouble();
          final cantidadRecibida = (recepcion['cantidad'] ?? 1.0).toDouble();

          if (costoReal > 0 && cantidadRecibida > 0) {
            final costoUnitario = costoReal / cantidadRecibida;
            print(
              '✅ Costo unitario calculado (presentación diferente): $costoUnitario',
            );
            return costoUnitario;
          }
        }

        return 0.0;
      }

      final recepcion = recepcionResponse.first;
      final costoReal = (recepcion['costo_real'] ?? 0.0).toDouble();
      final cantidadRecibida = (recepcion['cantidad'] ?? 1.0).toDouble();

      print(
        '✅ Recepción encontrada - Costo real: $costoReal, Cantidad: $cantidadRecibida',
      );

      // 3. Obtener cantidad de UM por presentación
      print('📋 Paso 3: Obteniendo cantidad de unidades de medida...');
      final umResponse = await _supabase
          .from('app_dat_presentacion_unidad_medida')
          .select('cantidad_um')
          .eq('id_producto', productId)
          .eq('id_presentacion', basePresentacion['id_presentacion'])
          .limit(1);

      print(
        '📊 Consulta de UM ejecutada. Resultados encontrados: ${umResponse.length}',
      );

      double cantidadUM = 1.0;
      if (umResponse.isNotEmpty) {
        cantidadUM = (umResponse.first['cantidad_um'] ?? 1.0).toDouble();
        print('✅ Cantidad UM encontrada: $cantidadUM');
      } else {
        print(
          '⚠️ No se encontró cantidad UM, usando valor por defecto: $cantidadUM',
        );
      }

      // 4. Calcular costo por UM
      print('📋 Paso 4: Calculando costo final...');

      if (cantidadRecibida <= 0) {
        print('❌ Cantidad recibida inválida: $cantidadRecibida');
        return 0.0;
      }

      final costoPorPresentacion = costoReal / cantidadRecibida;
      final costoFinal = costoPorPresentacion / cantidadUM;

      print(
        '🧮 Cálculo: ($costoReal / $cantidadRecibida) / $cantidadUM = $costoFinal',
      );
      print('✅ Costo unitario calculado para producto $productId: $costoFinal');

      return costoFinal;
    } catch (e) {
      print('❌ Error calculando costo unitario para producto $productId: $e');
      print('📍 Stack trace: ${StackTrace.current}');
      return 0.0;
    }
  }

  /// Obtiene ID de unidad usando RestaurantService (método correcto)
  static Future<int?> _getUnidadIdFromString(String unidadString) async {
    try {
      final unidades = await RestaurantService.getUnidadesMedida();

      // Buscar por abreviatura primero
      for (final unidad in unidades) {
        if (unidad.abreviatura.toLowerCase() == unidadString.toLowerCase()) {
          print(
            '✅ Unidad encontrada por abreviatura: "$unidadString" → ID ${unidad.id}',
          );
          return unidad.id;
        }
      }

      // Buscar por denominación
      for (final unidad in unidades) {
        if (unidad.denominacion.toLowerCase().contains(
          unidadString.toLowerCase(),
        )) {
          print(
            '✅ Unidad encontrada por denominación: "$unidadString" → ID ${unidad.id}',
          );
          return unidad.id;
        }
      }

      print('⚠️ Unidad no encontrada: "$unidadString"');
      return 17; // ID de "Unidad" como fallback
    } catch (e) {
      print('❌ Error obteniendo unidad: $e');
      return 17;
    }
  }

  /// Obtiene los productos que usan este producto como ingrediente
  static Future<List<Map<String, dynamic>>> getProductsUsingThisIngredient(
    String productId,
  ) async {
    try {
      print('🔍 Obteniendo productos que usan el ingrediente: $productId');

      final response = await _supabase.rpc(
        'obtener_productos_que_usan_ingrediente_detallado',
        params: {
          'p_id_producto_ingrediente': int.parse(productId),
        },
      );

      print('📦 Respuesta RPC recibida: ${response.toString()}');
      
      if (response == null) {
        print('⚠️ Respuesta nula de la función RPC');
        return [];
      }

      final List<dynamic> productosData = response as List<dynamic>;
      print('📊 Total productos encontrados que usan este ingrediente: ${productosData.length}');

      return productosData.cast<Map<String, dynamic>>();
    } catch (e, stackTrace) {
      print('❌ Error obteniendo productos que usan este ingrediente: $e');
      print('📍 StackTrace: $stackTrace');
      return [];
    }
  }

  /// Sube una imagen al bucket de Supabase Storage para productos
  static Future<String?> _uploadProductImage(Uint8List imageBytes, String fileName) async {
    try {
      debugPrint('📤 Subiendo imagen de producto: $fileName');
      
      // Generar nombre único para evitar conflictos
      final uniqueFileName = 'product_${DateTime.now().millisecondsSinceEpoch}_$fileName';
      
      // Subir imagen al bucket 'images_back' con opciones específicas
      final response = await _supabase.storage
          .from('images_back')
          .uploadBinary(
            uniqueFileName, 
            imageBytes,
            fileOptions: const FileOptions(
              cacheControl: '3600',
              upsert: true, // Permite sobrescribir si existe
            ),
          );

      if (response.isEmpty) {
        throw Exception('Error al subir imagen');
      }

      // Obtener URL pública de la imagen
      final imageUrl = _supabase.storage
          .from('images_back')
          .getPublicUrl(uniqueFileName);

      debugPrint('✅ Imagen de producto subida exitosamente: $imageUrl');
      return imageUrl;
    } catch (e) {
      debugPrint('❌ Error al subir imagen de producto: $e');
      
      // Si falla con RLS, intentar continuar sin imagen
      if (e.toString().contains('row-level security policy')) {
        debugPrint('⚠️ Error de permisos RLS - continuando sin imagen');
        return null;
      }
      
      return null;
    }
  }

  /// Actualiza la imagen de un producto en la base de datos
  static Future<bool> updateProductImage({
    required String productId,
    required Uint8List imageBytes,
    required String imageFileName,
  }) async {
    try {
      debugPrint('🖼️ Actualizando imagen del producto ID: $productId');
      
      // Subir nueva imagen
      final imageUrl = await _uploadProductImage(imageBytes, imageFileName);
      if (imageUrl == null) {
        throw Exception('Error al subir la imagen');
      }

      // Actualizar el producto con la nueva URL de imagen
      await _supabase
          .from('app_dat_producto')
          .update({'imagen': imageUrl})
          .eq('id', productId);

      debugPrint('✅ Imagen del producto actualizada exitosamente');
      return true;
    } catch (e) {
      debugPrint('❌ Error al actualizar imagen del producto: $e');
      return false;
    }
  }

  /// Elimina la imagen de un producto (establece la URL como vacía)
  static Future<bool> removeProductImage({
    required String productId,
  }) async {
    try {
      debugPrint('🗑️ Eliminando imagen del producto ID: $productId');
      
      // Actualizar el producto con imagen vacía
      await _supabase
          .from('app_dat_producto')
          .update({'imagen': ''})
          .eq('id', productId);

      debugPrint('✅ Imagen del producto eliminada exitosamente');
      return true;
    } catch (e) {
      debugPrint('❌ Error al eliminar imagen del producto: $e');
      return false;
    }
  }

  /// Actualiza la denominación corta de un producto buscándolo por denominación
  /// Usa la función RPC de Supabase para mayor seguridad y mejor manejo de errores
  static Future<bool> updateProductShortNameByDenomination(
    String denominacion,
    String nuevaDenominacionCorta,
  ) async {
    try {
      debugPrint('🔍 Actualizando denominación corta por denominación: $denominacion');
      debugPrint('📝 Nueva denominación corta: $nuevaDenominacionCorta');
      
      // Obtener ID de tienda desde las preferencias del usuario
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();
      if (idTienda == null) {
        throw Exception('No se encontró ID de tienda en las preferencias del usuario');
      }

      debugPrint('🏪 ID de tienda: $idTienda');

      // Llamar a la función RPC de Supabase
      final response = await _supabase.rpc(
        'fn_actualizar_denominacion_corta_por_denominacion',
        params: {
          'p_id_tienda': idTienda,
          'p_denominacion': denominacion,
          'p_nueva_denominacion_corta': nuevaDenominacionCorta,
        },
      );

      debugPrint('📦 Respuesta RPC: $response');

      if (response == null) {
        debugPrint('❌ Respuesta nula de la función RPC');
        return false;
      }

      // Verificar si la operación fue exitosa
      final success = response['success'] as bool? ?? false;
      
      if (success) {
        debugPrint('✅ Denominación corta actualizada exitosamente');
        debugPrint('📊 Producto ID: ${response['product_id']}');
        debugPrint('📝 Denominación anterior: ${response['previous_short_name']}');
        debugPrint('📝 Denominación nueva: ${response['new_short_name']}');
        return true;
      } else {
        final error = response['error'] ?? 'Error desconocido';
        final message = response['message'] ?? 'Sin mensaje';
        debugPrint('⚠️ Error en la actualización: $error');
        debugPrint('💬 Mensaje: $message');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Error al actualizar denominación corta: $e');
      return false;
    }
  }

  /// Actualiza múltiples denominaciones cortas de forma masiva
  /// Usa la función RPC masiva para mejor rendimiento
  static Future<Map<String, dynamic>> updateMultipleProductShortNames(
    List<Map<String, String>> actualizaciones,
  ) async {
    try {
      debugPrint('🔄 Iniciando actualización masiva de ${actualizaciones.length} productos');
      
      // Obtener ID de tienda desde las preferencias del usuario
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();
      if (idTienda == null) {
        throw Exception('No se encontró ID de tienda en las preferencias del usuario');
      }

      debugPrint('🏪 ID de tienda: $idTienda');

      // Convertir la lista a JSON para la función RPC
      final jsonActualizaciones = actualizaciones.map((item) => {
        'denominacion': item['denominacion'],
        'codigo': item['codigo'],
      }).toList();

      debugPrint('📋 Datos a procesar: $jsonActualizaciones');

      // Llamar a la función RPC masiva
      debugPrint('🔄 Llamando a función RPC: fn_actualizar_denominacion_corta_masivo');
      debugPrint('📊 Parámetros: p_id_tienda=$idTienda, p_actualizaciones=$jsonActualizaciones');
      
      final response = await _supabase.rpc(
        'fn_actualizar_denominacion_corta_masivo',
        params: {
          'p_id_tienda': idTienda,
          'p_actualizaciones': jsonActualizaciones,
        },
      );

      debugPrint('📦 Respuesta RPC masiva: $response');
      debugPrint('📊 Tipo de respuesta: ${response.runtimeType}');

      if (response == null) {
        return {
          'success': false,
          'error': 'Respuesta nula de la función RPC',
          'summary': {
            'total_processed': 0,
            'successful': 0,
            'failed': actualizaciones.length,
          }
        };
      }

      return Map<String, dynamic>.from(response);
    } catch (e) {
      debugPrint('❌ Error en actualización masiva: $e');
      return {
        'success': false,
        'error': 'Error en actualización masiva: $e',
        'summary': {
          'total_processed': 0,
          'successful': 0,
          'failed': actualizaciones.length,
        }
      };
    }
  }

  /// Inicializa los precios promedio de las presentaciones de un producto
  /// Busca operaciones de recepción y calcula el promedio del precio unitario
  static Future<Map<String, dynamic>> initializePresentationAveragePrices({
    required String productId,
  }) async {
    try {
      debugPrint('🔍 Inicializando precios promedio para producto: $productId');

      // Obtener ID de tienda desde las preferencias del usuario
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();
      if (idTienda == null) {
        throw Exception('No se encontró ID de tienda en las preferencias del usuario');
      }

      // Obtener presentaciones del producto
      final presentaciones = await _supabase
          .from('app_dat_producto_presentacion')
          .select('id, id_producto, id_presentacion, cantidad')
          .eq('id_producto', productId);

      debugPrint('📊 Presentaciones encontradas: ${presentaciones.length}');

      if (presentaciones.isEmpty) {
        return {
          'success': false,
          'error': 'No hay presentaciones para este producto',
          'updated': 0,
        };
      }

      int updated = 0;

      // Para cada presentación, calcular el precio promedio
      for (final pres in presentaciones) {
        final idPresentacion = pres['id'];
        final cantidadPresentacion = (pres['cantidad'] as num?)?.toDouble() ?? 1.0;

        debugPrint('🔄 Procesando presentación ID: $idPresentacion (cantidad: $cantidadPresentacion)');

        // Obtener operaciones de recepción para este producto en esta tienda
        // Necesitamos hacer JOIN con app_dat_operaciones para obtener id_tienda
        final operaciones = await _supabase
            .from('app_dat_recepcion_productos')
            .select('precio_unitario, cantidad, app_dat_operaciones(id_tienda)')
            .eq('id_producto', productId)
            .not('precio_unitario', 'is', null);

        // Filtrar por tienda
        final operacionesPorTienda = (operaciones as List<dynamic>)
            .where((op) {
              final opData = op as Map<String, dynamic>;
              final operacionData = opData['app_dat_operaciones'] as Map<String, dynamic>?;
              final tiendaId = operacionData?['id_tienda'];
              return tiendaId == idTienda;
            })
            .toList();

        if (operacionesPorTienda.isNotEmpty) {
          // Calcular promedio del precio unitario
          double totalPrecio = 0;
          for (final op in operacionesPorTienda) {
            final opData = op as Map<String, dynamic>;
            totalPrecio += (opData['precio_unitario'] as num).toDouble();
          }
          final precioPromedio = totalPrecio / operacionesPorTienda.length;

          debugPrint('  💰 Precio promedio calculado: $precioPromedio');
          debugPrint('  📊 Basado en ${operacionesPorTienda.length} operaciones de recepción');

          // Actualizar el precio_promedio en la presentación
          await _supabase
              .from('app_dat_producto_presentacion')
              .update({'precio_promedio': precioPromedio})
              .eq('id', idPresentacion);

          updated++;
          debugPrint('  ✅ Presentación actualizada');
        } else {
          debugPrint('  ⚠️ No hay operaciones de recepción para este producto en esta tienda');
        }
      }

      debugPrint('✅ Inicialización completada: $updated presentaciones actualizadas');
      return {
        'success': true,
        'updated': updated,
        'message': '$updated presentaciones actualizadas con precios promedio',
      };
    } catch (e) {
      debugPrint('❌ Error al inicializar precios promedio: $e');
      return {
        'success': false,
        'error': 'Error al inicializar precios: $e',
        'updated': 0,
      };
    }
  }

  /// Actualiza el precio promedio de una presentación específica
  static Future<bool> updatePresentationAveragePrice({
    required String presentationId,
    required double newPrice,
  }) async {
    try {
      debugPrint('💰 Actualizando precio promedio de presentación: $presentationId');
      debugPrint('📝 Nuevo precio: $newPrice');

      await _supabase
          .from('app_dat_producto_presentacion')
          .update({'precio_promedio': newPrice})
          .eq('id', presentationId);

      debugPrint('✅ Precio promedio actualizado exitosamente');
      return true;
    } catch (e) {
      debugPrint('❌ Error al actualizar precio promedio: $e');
      return false;
    }
  }

  /// Actualiza el precio base de venta de un producto
  static Future<bool> updateBasePriceVenta({
    required int productId,
    required double newPrice,
  }) async {
    try {
      debugPrint('💰 Actualizando precio base de venta para producto: $productId');
      debugPrint('📝 Nuevo precio: $newPrice');

      // Actualizar en app_dat_precio_venta
      await _supabase
          .from('app_dat_precio_venta')
          .update({'precio_venta_cup': newPrice})
          .eq('id_producto', productId);

      debugPrint('✅ Precio base actualizado exitosamente');
      return true;
    } catch (e) {
      debugPrint('❌ Error al actualizar precio base: $e');
      return false;
    }
  }
}
