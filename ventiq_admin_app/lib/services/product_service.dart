import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'dart:io';
import '../models/product.dart';
import 'user_preferences_service.dart';
import 'store_selector_service.dart';

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
        throw Exception('No se encontró ID de tienda en las preferencias del usuario');
      }

      print('🔍 Llamando RPC get_productos_completos_by_tienda_optimized');
      print('📍 Parámetros: idTienda=$idTienda, categoryId=$categoryId, soloDisponibles=$soloDisponibles');

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
        print('🔍 Campo es_elaborado existe: ${primerProducto.containsKey('es_elaborado')}');
        print('🔍 Valor de es_elaborado: ${primerProducto['es_elaborado']}');
        print('🔍 Tipo de es_elaborado: ${primerProducto['es_elaborado'].runtimeType}');
        print('🔍 Denominación: ${primerProducto['denominacion']}');
        print('🔍 ID: ${primerProducto['id']}');
        print('=======================================');
      }

      // Convertir cada producto del JSON al modelo Product
      final productos = productosData.map((productoJson) {
        return _convertToProduct(productoJson as Map<String, dynamic>);
      }).toList();

      // TEMPORAL: Obtener el campo es_elaborado para cada producto
      print('🔧 OBTENIENDO CAMPO es_elaborado PARA CADA PRODUCTO...');
      for (int i = 0; i < productos.length; i++) {
        try {
          final productId = int.tryParse(productos[i].id);
          if (productId != null) {
            final elaboradoResponse = await _supabase
                .from('app_dat_producto')
                .select('es_elaborado')
                .eq('id', productId)
                .single();
            
            final esElaborado = elaboradoResponse['es_elaborado'] ?? false;
            print('🔧 Producto ${productos[i].denominacion} (ID: $productId) - es_elaborado: $esElaborado');
            
            // Actualizar el producto con el valor correcto
            productos[i] = productos[i].copyWith(esElaborado: esElaborado);
          }
        } catch (e) {
          print('⚠️ Error obteniendo es_elaborado para producto ${productos[i].id}: $e');
        }
      }

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

    } catch (e, stackTrace) {
      print('❌ Error al obtener categorías: $e');
      print('📍 StackTrace: $stackTrace');
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
        stockDisponible: json['stock_disponible'] ?? 0,
        tieneStock: (json['stock_disponible'] ?? 0) > 0,
        subcategorias: subcategorias.cast<Map<String, dynamic>>(),
        presentaciones: presentaciones.cast<Map<String, dynamic>>(),
        multimedias: (json['multimedias'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
        etiquetas: (json['etiquetas'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
        inventario: (json['inventario'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
        variantesDisponibles: (json['variantes_disponibles'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
        esElaborado: json['es_elaborado'] ?? false,
      );
      
      print('✅ Producto convertido - ID: ${json['id']}, esElaborado final: ${json['es_elaborado'] ?? false}');

    } catch (e, stackTrace) {
      print('❌ Error al convertir producto: $e');
      print('📦 JSON problemático: $json');
      print('📍 StackTrace: $stackTrace');
      rethrow;
    }
  }

  /// Save debug JSON to Documents folder for debugging large RPC responses
  
  /// Elimina un producto completo y todos sus datos relacionados
  static Future<Map<String, dynamic>> deleteProductComplete(int productId) async {
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
        print('📊 Registros eliminados: ${result['total_registros_eliminados']}');
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
  static Future<List<Map<String, dynamic>>> getProductStockLocations(String productId) async {
    try {
      print('🔍 Obteniendo ubicaciones de stock para producto: $productId');

      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();
      if (idTienda == null) {
        throw Exception('No se encontró ID de tienda en las preferencias del usuario');
      }

      final response = await _supabase.rpc(
        'fn_listar_inventario_productos_paged',
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
      return data.map((item) => {
        'ubicacion': item['ubicacion'] ?? item['almacen'] ?? 'Sin ubicación',
        'cantidad': (item['cantidad_final'] ?? 0).toDouble(),
        'reservado': (item['stock_reservado'] ?? 0).toDouble(),
      }).toList();

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
      print('🔍 Obteniendo operaciones de recepción para producto: $productId (página: $page, límite: $limit)');

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
  static Future<List<Map<String, dynamic>>> getProductPriceHistory(String productId) async {
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

      return response.map<Map<String, dynamic>>((item) => {
        'fecha': DateTime.parse(item['fecha_desde']),
        'precio': (item['precio_venta_cup'] ?? 0.0).toDouble(),
      }).toList();

    } catch (e, stackTrace) {
      print('❌ Error al obtener histórico de precios: $e');
      print('📍 StackTrace: $stackTrace');
      return [];
    }
  }

  /// Obtiene los precios promocionales activos para un producto
  static Future<List<Map<String, dynamic>>> getProductPromotionalPrices(String productId) async {
    try {
      print('🔍 Obteniendo precios promocionales para producto: $productId');

      final response = await _supabase.rpc(
        'fn_listar_promociones_producto',
        params: {'p_id_producto': int.tryParse(productId)},
      );

      if (response == null) return [];

      final List<dynamic> data = response as List<dynamic>;
      return data.map<Map<String, dynamic>>((promo) => {
        'promocion': promo['nombre'] ?? 'Promoción sin nombre',
        'precio_original': (promo['precio_base'] ?? 0.0).toDouble(),
        'precio_promocional': _calculatePromotionalPrice(
          (promo['precio_base'] ?? 0.0).toDouble(),
          (promo['valor_descuento'] ?? 0.0).toDouble(),
          promo['es_recargo'] ?? false,
        ),
        'vigencia': '${_formatDate(promo['fecha_inicio'])} - ${_formatDate(promo['fecha_fin'])}',
        'activa': _isPromotionActive(promo['fecha_inicio'], promo['fecha_fin'], promo['estado']),
      }).toList();

    } catch (e, stackTrace) {
      print('❌ Error al obtener precios promocionales: $e');
      print('📍 StackTrace: $stackTrace');
      return [];
    }
  }

  /// Obtiene el histórico de stock para un producto específico
  static Future<List<Map<String, dynamic>>> getProductStockHistory(String productId, double stockActual) async {
    try {
      print('🔍 Obteniendo histórico de inventario para producto: $productId');
      print('📦 Stock actual recibido como parámetro: $stockActual');

      final response = await _supabase.rpc(
        'fn_listar_historial_inventario_producto_v2',
        params: {
          'p_id_producto': int.tryParse(productId),
          'p_dias': 30,
        },
      );

      if (response == null) return [];

      final List<dynamic> data = response as List<dynamic>;
      
      // Convertir las operaciones a formato para gráfico de stock acumulativo
      List<Map<String, dynamic>> stockHistory = [];
      
      if (data.isNotEmpty) {
        print('📊 Total operaciones recibidas: ${data.length}');
        
        // Ordenar operaciones por fecha (más antigua primero para calcular hacia adelante)
        data.sort((a, b) => DateTime.parse(a['fecha']).compareTo(DateTime.parse(b['fecha'])));
        
        print('🔍 ANÁLISIS DETALLADO DE OPERACIONES:');
        for (int i = 0; i < data.length; i++) {
          var op = data[i];
          print('Op ${i + 1}: ${op['tipo_operacion']} | Cantidad: ${op['cantidad']} | Stock inicial: ${op['stock_inicial']} | Stock final: ${op['stock_final']} | Fecha: ${op['fecha']}');
        }
        
        // Calcular stock hacia adelante desde 0
        double stockAcumulado = 0.0;
        
        // Agregar punto inicial (antes de cualquier operación)
        if (data.isNotEmpty) {
          final primeraFecha = DateTime.parse(data.first['fecha']);
          final fechaInicial = primeraFecha.subtract(Duration(days: 1));
          
          stockHistory.add({
            'fecha': fechaInicial,
            'cantidad': 0.0,
            'operacion_cantidad': 0.0,
            'tipo_operacion': 'Inicial',
            'documento': 'Stock inicial',
          });
          
          print('📈 Punto inicial agregado: Stock = 0.0, Fecha = $fechaInicial');
        }
        
        print('🔄 CALCULANDO STOCK PASO A PASO:');
        print('🔍 VALIDANDO CONSISTENCIA DE OPERACIONES:');
        
        double stockAnteriorEsperado = 0.0;
        int inconsistenciasDetectadas = 0;
        
        for (int i = 0; i < data.length; i++) {
          var operation = data[i];
          final fecha = DateTime.parse(operation['fecha']);
          final cantidad = (operation['cantidad'] ?? 0).toDouble();
          final tipoOperacion = operation['tipo_operacion'] ?? 'Operación';
          final stockInicialBD = (operation['stock_inicial'] ?? 0).toDouble();
          final stockFinalBD = (operation['stock_final'] ?? 0).toDouble();
          
          // Mostrar detalles de las primeras 15 operaciones
          bool mostrarDetalle = i < 15;
          
          if (mostrarDetalle) {
            print('--- Operación ${i + 1} ---');
            print('Tipo: $tipoOperacion');
            print('Cantidad: $cantidad');
            print('Stock inicial BD: $stockInicialBD');
            print('Stock final BD: $stockFinalBD');
            print('Stock esperado anterior: $stockAnteriorEsperado');
          }
          
          // Validar consistencia PARA TODAS LAS OPERACIONES
          if (i > 0 && (stockInicialBD - stockAnteriorEsperado).abs() > 0.01) {
            inconsistenciasDetectadas++;
            if (mostrarDetalle || inconsistenciasDetectadas <= 20) { // Mostrar primeras 20 inconsistencias
              print('⚠️ INCONSISTENCIA ${inconsistenciasDetectadas} DETECTADA!');
              print('   Operación ${i + 1}: $tipoOperacion');
              print('   Stock inicial BD: $stockInicialBD');
              print('   Stock esperado: $stockAnteriorEsperado');
              print('   Diferencia: ${stockInicialBD - stockAnteriorEsperado}');
              print('   Fecha: $fecha');
            }
          }
          
          // Determinar si es entrada o salida según el tipo de operación
          double cantidadConSigno;
          if (tipoOperacion == 'Recepción') {
            cantidadConSigno = cantidad; // Entrada: suma al stock
            if (mostrarDetalle) print('Es ENTRADA: +$cantidad');
          } else {
            cantidadConSigno = -cantidad; // Salida: resta del stock (Venta, Extracción, Salida)
            if (mostrarDetalle) print('Es SALIDA: -$cantidad');
          }
          
          // Sumar la operación al stock acumulado
          stockAcumulado += cantidadConSigno;
          
          if (mostrarDetalle) {
            print('Stock después (calculado): $stockAcumulado');
            print('Stock final BD: $stockFinalBD');
            
            // Validar que nuestro cálculo coincida con la BD
            if ((stockAcumulado - stockFinalBD).abs() > 0.01) {
              print('⚠️ DISCREPANCIA EN CÁLCULO!');
              print('   Calculado: $stockAcumulado');
              print('   BD: $stockFinalBD');
              print('   Diferencia: ${stockAcumulado - stockFinalBD}');
            }
            print('Stock en gráfico: ${stockAcumulado.abs()}');
            print('---');
          }
          
          stockHistory.add({
            'fecha': fecha,
            'cantidad': stockAcumulado.abs(), // Usar valor absoluto para evitar negativos
            'operacion_cantidad': cantidadConSigno,
            'tipo_operacion': tipoOperacion,
            'documento': operation['documento'] ?? '',
          });
          
          // Actualizar stock esperado para la siguiente operación
          stockAnteriorEsperado = stockFinalBD;
          
          // Mostrar progreso cada 50 operaciones
          if (i > 0 && (i + 1) % 50 == 0) {
            print('📊 Procesadas ${i + 1} operaciones...');
          }
        }
        
        print('');
        print('📊 RESUMEN DE ANÁLISIS COMPLETO:');
        print('Total operaciones procesadas: ${data.length}');
        print('Inconsistencias detectadas: $inconsistenciasDetectadas');
        if (inconsistenciasDetectadas > 20) {
          print('(Mostrando solo las primeras 20 inconsistencias en detalle)');
        }
        
        // Agregar punto actual si es diferente del último calculado
        if (stockAcumulado.abs() != stockActual) {
          print('⚠️ DISCREPANCIA DETECTADA:');
          print('Stock calculado: ${stockAcumulado.abs()}');
          print('Stock actual real: $stockActual');
          print('Diferencia: ${stockActual - stockAcumulado.abs()}');
          
          // En lugar de ajustar, mostrar el gráfico con los datos calculados
          // pero agregar una nota sobre la discrepancia
          stockHistory.add({
            'fecha': DateTime.now(),
            'cantidad': stockActual,
            'operacion_cantidad': stockActual - stockAcumulado.abs(),
            'tipo_operacion': 'Discrepancia',
            'documento': 'Diferencia entre histórico y stock actual: ${(stockActual - stockAcumulado.abs()).toStringAsFixed(0)} unidades',
          });
        }
        
        print('📈 RESUMEN FINAL:');
        print('Stock inicial en gráfico: ${stockHistory.first['cantidad']}');
        print('Stock final calculado: ${stockAcumulado.abs()}');
        print('Stock actual real: $stockActual');
        print('Total puntos en gráfico: ${stockHistory.length}');
        print('Última operación: ${data.last['tipo_operacion']} - ${data.last['cantidad']} - ${data.last['fecha']}');
        
        // Agregar información sobre la integridad de los datos
        final diferencia = stockActual - stockAcumulado.abs();
        if (diferencia.abs() > 100) { // Si la diferencia es significativa
          print('⚠️ ADVERTENCIA: Discrepancia significativa en los datos');
          print('   Esto puede indicar:');
          print('   - Operaciones no registradas en el histórico');
          print('   - Ajustes manuales de inventario no documentados');
          print('   - Diferencias entre el stock teórico y físico');
          
          // Ejecutar análisis de inconsistencias automáticamente
          print('');
          print('🔍 EJECUTANDO ANÁLISIS DE INCONSISTENCIAS...');
          await detectStockInconsistencies(productId);
        }
        
        print('✅ Histórico de stock calculado: ${stockHistory.length} puntos');
        return stockHistory;
      } else {
        print('📊 No hay operaciones de inventario para este producto en los últimos 30 días');
        // Crear un punto único con el stock actual
        return [{
          'fecha': DateTime.now(),
          'cantidad': stockActual,
          'operacion_cantidad': 0.0,
          'tipo_operacion': 'Stock Actual',
          'documento': 'Sin operaciones recientes',
        }];
      }

    } catch (e, stackTrace) {
      print('❌ Error al obtener histórico de inventario: $e');
      print('📍 StackTrace: $stackTrace');
      return [];
    }
  }

  /// Actualiza un producto existente
  static Future<bool> updateProduct(String productId, Map<String, dynamic> productData) async {
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
        },
      );

      return response == true;

    } catch (e, stackTrace) {
      print('❌ Error al actualizar producto: $e');
      print('📍 StackTrace: $stackTrace');
      return false;
    }
  }

  /// Duplica un producto existente
  static Future<Map<String, dynamic>?> duplicateProduct(String productId) async {
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
      print('🔍 Detectando inconsistencias en histórico de stock para producto: $productId');

      final response = await _supabase.rpc(
        'fn_detectar_inconsistencias_stock',
        params: {
          'p_id_producto': int.tryParse(productId),
          'p_dias': 30,
        },
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
        
        final storeIdAfterInit = await _storeSelectorService!.getSelectedStoreId();
        if (storeIdAfterInit != null) {
          print('🏪 ID de tienda después de inicializar: $storeIdAfterInit');
          return storeIdAfterInit;
        }
      }

      // 4. Fallback: usar la primera tienda disponible
      final stores = _storeSelectorService!.userStores;
      if (stores.isNotEmpty) {
        final firstStoreId = stores.first.id;
        print('🏪 Usando primera tienda disponible como fallback: $firstStoreId');
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

  static double _calculatePromotionalPrice(double basePrice, double discount, bool isCharge) {
    if (isCharge) {
      return basePrice + (basePrice * discount / 100);
    } else {
      return basePrice - (basePrice * discount / 100);
    }
  }

  static String _formatDate(String? dateStr) {
    if (dateStr == null) return 'N/A';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    } catch (e) {
      return 'N/A';
    }
  }

  static bool _isPromotionActive(String? startDate, String? endDate, int? status) {
    if (startDate == null || endDate == null || status != 1) return false;
    
    try {
      final now = DateTime.now();
      final start = DateTime.parse(startDate);
      final end = DateTime.parse(endDate);
      return now.isAfter(start) && now.isBefore(end);
    } catch (e) {
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
      if (fechaFactura != null) params['p_fecha_factura'] = fechaFactura.toIso8601String().split('T')[0];
      if (montoFactura != null) params['p_monto_factura'] = montoFactura;
      if (monedaFactura != null) params['p_moneda_factura'] = monedaFactura;
      if (pdfFactura != null) params['p_pdf_factura'] = pdfFactura;
      if (observacionesCompra != null) params['p_observaciones_compra'] = observacionesCompra;
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
            'message': response['message'] ?? 'Operación actualizada correctamente',
            'data': response,
          };
        } else {
          print('❌ Error en la actualización: ${response['message']}');
          return {
            'success': false,
            'message': response['message'] ?? 'Error desconocido al actualizar la operación',
          };
        }
      } else {
        print('❌ Respuesta inválida del servidor');
        return {
          'success': false,
          'message': 'Respuesta inválida del servidor',
        };
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
  static Future<Map<String, dynamic>?> getReceptionOperationDetails(String operationId) async {
    try {
      print('🔍 Obteniendo detalles de operación de recepción: $operationId');

      // Parse the operation ID and validate it
      final parsedId = int.tryParse(operationId);
      if (parsedId == null) {
        print('❌ ID de operación inválido: $operationId');
        return null;
      }

      // First get the operation details
      final operationResponse = await _supabase
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
      // Obtener ID de tienda desde las preferencias del usuario
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();
      if (idTienda == null) {
        throw Exception('No se encontró ID de tienda en las preferencias del usuario');
      }

      print('🔍 Obteniendo producto completo por ID: $productId');
      
      // Llamar a la función RPC para obtener un producto específico con todas sus configuraciones
      final response = await _supabase.rpc(
        'get_producto_completo_by_id',
        params: {
          'id_producto_param': productId,
          'id_tienda_param': idTienda,
        },
      );

      print('📦 Respuesta producto por ID: $response');

      if (response == null || response.isEmpty) {
        print('⚠️ No se encontró producto con ID: $productId');
        return null;
      }

      // El response debería ser un objeto con la estructura del producto
      final productData = response is List ? response.first : response;
      
      return Product.fromJson(productData);
    } catch (e) {
      print('❌ Error obteniendo producto por ID $productId: $e');
      return null;
    }
  }

  /// Obtiene productos para ingredientes filtrados por tienda del usuario
  static Future<List<Map<String, dynamic>>> getProductsForIngredients() async {
    try {
      // Obtener ID de tienda desde las preferencias del usuario
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();
      if (idTienda == null) {
        throw Exception('No se encontró ID de tienda en las preferencias del usuario');
      }

      final response = await _supabase
          .from('app_dat_producto')
          .select('''
            id,
            denominacion,
            sku,
            imagen,
            es_elaborado
          ''')
          .eq('es_inventariable', true)
          .eq('id_tienda', idTienda) // Filtrar por tienda del usuario
          .order('denominacion');

      return response.map<Map<String, dynamic>>((item) => {
        'id': item['id'],
        'denominacion': item['denominacion'],
        'sku': item['sku'],
        'imagen': item['imagen'],
        'es_elaborado': item['es_elaborado'] ?? false,
        'precio_venta': 0.0, // Por ahora sin precio
        'stock_disponible': 0, // Por ahora sin stock
      }).toList();
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
static Future<Map<String, dynamic>?> getBasePresentacion(int productId) async {
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
      print('✅ Presentación base encontrada: ${basePresentation['app_nom_presentacion']['denominacion']}');
      return {
        'id_presentacion': basePresentation['id'],
        'cantidad': basePresentation['cantidad'],
        'denominacion': basePresentation['app_nom_presentacion']['denominacion'],
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
    
    print('🔄 Presentación origen: $fromCantidad unidades base por presentación');
    print('🔄 Presentación base: $baseCantidad unidades base por presentación');
    print('🔄 Cálculo: ($cantidad * $fromCantidad) / $baseCantidad = $cantidadEnBase');
    print('✅ Cantidad convertida a presentación base: $cantidadEnBase');
    
    return cantidadEnBase;
    
  } catch (e) {
    print('❌ Error en conversión a presentación base: $e');
    return cantidad; // Retornar cantidad original en caso de error
  }
}

/// Obtiene información completa de presentaciones de un producto
static Future<List<Map<String, dynamic>>> getPresentacionesCompletas(int productId) async {
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
    
    final presentaciones = response.map<Map<String, dynamic>>((item) => {
      'id_presentacion': item['id_presentacion'],
      'cantidad': item['cantidad'],
      'es_base': item['es_base'],
      'denominacion': item['app_nom_presentacion']['denominacion'],
    }).toList();
    
    print('✅ Presentaciones obtenidas: ${presentaciones.length}');
    for (final pres in presentaciones) {
      print('   - ${pres['denominacion']}: ${pres['cantidad']} ${pres['es_base'] ? '(BASE)' : ''}');
    }
    
    return presentaciones;
    
  } catch (e) {
    print('❌ Error obteniendo presentaciones completas: $e');
    return [];
  }
}
  /// Obtiene las unidades de medida por presentación de un producto
  static Future<List<Map<String, dynamic>>> getPresentacionUnidadMedida(int productId) async {
    try {
      print('🔍 Obteniendo unidades de medida por presentación para producto: $productId');
      
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
      
      print('📦 Unidades de medida por presentación obtenidas: ${response.length}');
      return List<Map<String, dynamic>>.from(response);
      
    } catch (e, stackTrace) {
      print('❌ Error obteniendo unidades de medida por presentación: $e');
      print('📍 StackTrace: $stackTrace');
      return [];
    }
  }

  /// Obtiene los ingredientes de un producto elaborado
  static Future<List<Map<String, dynamic>>> getProductIngredients(String productId) async {
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
      print('🔧 Total registros a insertar: ${presentacionUnidadMedidaData.length}');
      
      if (presentacionUnidadMedidaData.isEmpty) {
        print('⚠️ No hay datos de unidades de medida por presentación para insertar');
        return;
      }
      
      // Insertar cada registro individualmente para mejor control de errores
      for (int i = 0; i < presentacionUnidadMedidaData.length; i++) {
        final data = presentacionUnidadMedidaData[i];
        
        try {
          print('🔧 Insertando registro ${i + 1}: $data');
          
          final response = await _supabase
              .from('app_dat_presentacion_unidad_medida')
              .insert({
                'id_producto': productId,
                'id_presentacion': data['id_presentacion'],
                'id_unidad_medida': data['id_unidad_medida'],
                'cantidad_um': data['cantidad_um'],
              })
              .select()
              .single();
          
          print('✅ Registro ${i + 1} insertado exitosamente: ${response['id']}');
          
        } catch (e) {
          print('❌ Error insertando registro ${i + 1}: $e');
          print('❌ Datos del registro: $data');
          // Continuar con los demás registros
        }
      }
      
      print('✅ Proceso de inserción de unidades de medida por presentación completado');
      
    } catch (e, stackTrace) {
      print('❌ Error general en insertPresentacionUnidadMedida: $e');
      print('📍 StackTrace: $stackTrace');
      throw Exception('Error al insertar unidades de medida por presentación: $e');
    }
  }

  /// Inserta ingredientes para un producto elaborado
  static Future<bool> insertProductIngredients({
    required int productId,
    required List<Map<String, dynamic>> ingredientes,
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
      final ingredientesData = ingredientes.map((ingrediente) {
        print('🔍 Procesando ingrediente: $ingrediente');
        
        final data = {
          'id_producto_elaborado': productId,
          'id_ingrediente': ingrediente['id_producto'], // ID del producto ingrediente
          'cantidad_necesaria': ingrediente['cantidad'], // Cantidad necesaria
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
          print('✅ Ingrediente insertado exitosamente: ${ingredienteData['id_ingrediente']} - Cantidad: ${ingredienteData['cantidad_necesaria']}');
        } catch (e) {
          print('❌ ERROR insertando ingrediente específico ${ingredienteData['id_ingrediente']}: $e');
          print('❌ Datos que causaron error: $ingredienteData');
          // Continuar con los demás ingredientes
        }
      }

      print('📊 ===== RESUMEN INSERCIÓN INGREDIENTES =====');
      print('📊 Ingredientes procesados: ${ingredientes.length}');
      print('📊 Ingredientes insertados exitosamente: $insertedCount');
      print('📊 Ingredientes con error: ${ingredientes.length - insertedCount}');
      
      final success = insertedCount > 0;
      print('📊 Resultado final: ${success ? "ÉXITO" : "FALLO"}');
      
      // Si se insertaron ingredientes exitosamente, actualizar el campo es_elaborado del producto
      if (success) {
        try {
          print('🔄 Actualizando campo es_elaborado = true para producto ID: $productId');
          
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
}
