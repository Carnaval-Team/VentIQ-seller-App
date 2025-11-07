import '../models/warehouse.dart';
import '../models/store.dart';
import 'user_preferences_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WarehouseService {
  final _supabase = Supabase.instance.client;
  final _prefsService = UserPreferencesService();

  /// Lista almacenes con paginación usando Supabase RPC
  Future<WarehousePaginationResponse> listWarehousesWithPagination({
    String? denominacionFilter,
    String? direccionFilter,
    int? tiendaFilter,
    int pagina = 1,
    int porPagina = 10,
  }) async {
    print('🚀 === INICIANDO listWarehousesWithPagination ===');
    try {
      // Obtener UUID del usuario para la consulta
      print('🔑 Obteniendo UUID del usuario...');
      final userId = await _prefsService.getUserId();
      if (userId == null) {
        print('❌ Usuario ID es null - no se puede continuar');
        throw Exception('No se encontró el ID de usuario');
      }
      print('✅ Usuario ID obtenido: $userId');

      print('🔍 Preparando llamada RPC listar_almacenes_acceso_usuario:');
      print('  - Usuario ID: $userId');
      print('  - Denominación: $denominacionFilter');
      print('  - Dirección: $direccionFilter');
      print('  - Tienda: $tiendaFilter');
      print('  - Página: $pagina');
      print('  - Por página: $porPagina');

      print('📡 Ejecutando RPC...');
      final response = await _supabase.rpc(
        'listar_almacenes_acceso_usuario',
        params: {
          'p_uuid': userId,
          'p_denominacion_filter': denominacionFilter,
          'p_direccion_filter': direccionFilter,
          'p_tienda_filter': tiendaFilter,
          'p_pagina': pagina,
          'p_por_pagina': porPagina,
        },
      );

      print('✅ Respuesta de Supabase recibida!');
      print('  - Tipo: ${response.runtimeType}');
      print('  - Es null: ${response == null}');
      print('  - Contenido: $response');

      if (response == null) {
        print('⚠️ Respuesta es null - usando datos mock');
        throw Exception('Respuesta de Supabase es null');
      }

      print('🔄 Parseando respuesta...');

      // Check if response has success structure
      if (response['success'] == false) {
        throw Exception(response['message'] ?? 'Error en la consulta RPC');
      }

      // Extract data from the response
      final data = response['data'];
      if (data == null) {
        throw Exception('No se encontraron datos en la respuesta');
      }

      final parsedResponse = WarehousePaginationResponse.fromJson(data);
      print('✅ Respuesta parseada exitosamente:');
      print('  - Almacenes: ${parsedResponse.almacenes.length}');
      print('  - Página actual: ${parsedResponse.paginacion.paginaActual}');
      print('  - Total páginas: ${parsedResponse.paginacion.totalPaginas}');
      print('  - Total almacenes: ${parsedResponse.paginacion.totalAlmacenes}');

      return parsedResponse;
    } catch (e, stackTrace) {
      print('❌ ERROR en listWarehousesWithPagination: $e');
      print('📍 Stack trace: $stackTrace');
      rethrow;
    } finally {
      print('🏁 === FIN listWarehousesWithPagination ===');
    }
  }

  /// Método de compatibilidad para mantener la interfaz existente
  Future<List<Warehouse>> listWarehouses({
    String? storeId,
    String? search,
  }) async {
    try {
      final response = await listWarehousesWithPagination(
        denominacionFilter: search,
        tiendaFilter:
            storeId != null && storeId != 'all' ? int.tryParse(storeId) : null,
        pagina: 1,
        porPagina: 100, // Obtener muchos para compatibilidad
      );
      return response.almacenes;
    } catch (e) {
      print('❌ Error en listWarehouses: $e');
      rethrow;
    }
  }

  /// Obtiene el detalle completo de un almacén específico usando Supabase RPC
  Future<Warehouse> getWarehouseDetail(String id) async {
    try {
      print('🔍 Obteniendo detalle del almacén ID: $id');

      // Usar el RPC específico para obtener detalle completo del almacén
      final response = await _supabase.rpc(
        'get_detalle_almacen_completo',
        params: {'p_almacen_id': int.parse(id)},
      );

      // print('🔍 ===== RESPUESTA get_detalle_almacen_completo =====');
      // print('🔍 Tipo de respuesta: ${response.runtimeType}');
      // print('🔍 Respuesta completa: $response');
      // print('🔍 ===============================================');

      if (response == null) {
        // print(
        //   '⚠️ No se recibió respuesta del RPC get_detalle_almacen_completo',
        // );
        throw Exception('No se pudo obtener el detalle del almacén');
      }

      // Manejar diferentes estructuras de respuesta
      dynamic warehouseData;

      // Si la respuesta es una lista, tomar el primer elemento
      if (response is List && response.isNotEmpty) {
        warehouseData = response[0];
        // print('🔍 Respuesta es lista, tomando primer elemento');
      } else if (response is Map) {
        warehouseData = response;
        // print('🔍 Respuesta es mapa directo');
      } else {
        // print(
        //   '🔍 Respuesta tiene estructura inesperada: ${response.runtimeType}',
        // );
        warehouseData = response;
      }

      // print('🔍 ===== WAREHOUSE DATA DETALLE =====');
      // print('🔍 warehouseData completo: $warehouseData');
      // print('🔍 ================================');

      // print('🔍 Estructura de warehouseData:');
      // print('  - id: ${warehouseData['almacen_id']}');
      // print('  - denominacion: ${warehouseData['almacen_nombre']}');
      // print('  - layouts: ${warehouseData['layouts']}');
      // print('  - layouts type: ${warehouseData['layouts']?.runtimeType}');
      // print('  - condiciones: ${warehouseData['condiciones']}');
      // print('  - tienda: ${warehouseData['tienda_nombre']}');
      // print('  - limites_stock: ${warehouseData['limites_stock']}');

      // Crear el objeto Warehouse con los datos del detalle completo
      final warehouse = Warehouse(
        id: warehouseData['almacen_id']?.toString() ?? id,
        name: warehouseData['almacen_nombre'] ?? '',
        description: 'Almacén ${warehouseData['almacen_nombre'] ?? ''}',
        address: warehouseData['direccion'] ?? '',
        city: warehouseData['ubicacion'] ?? '',
        country: 'Chile',
        type: 'principal',
        createdAt:
            warehouseData['created_at'] != null
                ? DateTime.parse(warehouseData['created_at'])
                : DateTime.now(),
        zones: _parseNewLayoutsToZones(warehouseData['layouts']),
        // Supabase specific fields
        denominacion: warehouseData['almacen_nombre'] ?? '',
        direccion: warehouseData['direccion'] ?? '',
        ubicacion: warehouseData['ubicacion'],
        tienda: _parseWarehouseStoreFromRpc(warehouseData),
        roles: _parseRoles(warehouseData['roles']),
        layouts: _parseLayouts(warehouseData['layouts'], id),
        condiciones: _parseCondiciones(warehouseData['condiciones']),
        almacenerosCount: warehouseData['almaceneros_count'] ?? 0,
        limitesStockCount: warehouseData['limites_stock_count'] ?? 0,
        stockLimits: _parseStockLimits(warehouseData['limites_stock']),
        workers: _parseWorkers(warehouseData['workers']),
      );

      print('🔍 ===== WAREHOUSE CREADO =====');
      print('🔍 ID: ${warehouse.id}');
      print('🔍 Nombre: ${warehouse.name}');
      print('🔍 Layouts count: ${warehouse.layouts.length}');
      print('🔍 Zones count: ${warehouse.zones.length}');
      print('🔍 =============================');

      return warehouse;
    } catch (e) {
      print('❌ Error en getWarehouseDetail: $e');
      rethrow;
    }
  }

  /// Helper method to safely parse WarehouseStore from RPC response
  WarehouseStore? _parseWarehouseStoreFromRpc(dynamic warehouseData) {
    if (warehouseData == null) return null;

    try {
      return WarehouseStore(
        id: warehouseData['tienda_id']?.toString() ?? '',
        denominacion: warehouseData['tienda_nombre'] ?? '',
        direccion: warehouseData['tienda_direccion'] ?? '',
      );
    } catch (e) {
      print('❌ Error parsing warehouse store from RPC: $e');
      return null;
    }
  }

  /// Helper method to safely parse WarehouseStore
  WarehouseStore? _parseWarehouseStore(dynamic tiendaData) {
    if (tiendaData == null) return null;

    try {
      return WarehouseStore(
        id: tiendaData['id']?.toString() ?? '',
        denominacion: tiendaData['denominacion'] ?? '',
        direccion: tiendaData['direccion'] ?? '',
      );
    } catch (e) {
      print('❌ Error parsing warehouse store: $e');
      return null;
    }
  }

  /// Helper method to safely parse roles
  List<String> _parseRoles(dynamic rolesData) {
    if (rolesData == null) return [];

    try {
      if (rolesData is List) {
        return rolesData.map((r) => r.toString()).toList();
      }
      return [];
    } catch (e) {
      print('❌ Error parsing roles: $e');
      return [];
    }
  }

  /// Helper method to safely parse conditions
  List<WarehouseCondition> _parseCondiciones(dynamic condicionesData) {
    if (condicionesData == null) return [];

    try {
      if (condicionesData is List) {
        return condicionesData
            .map((c) => WarehouseCondition.fromJson(c))
            .toList();
      }
      return [];
    } catch (e) {
      print('❌ Error parsing condiciones: $e');
      return [];
    }
  }

  /// Helper method to safely parse stock limits
  List<WarehouseStockLimit> _parseStockLimits(dynamic stockLimitsData) {
    if (stockLimitsData == null) return [];

    try {
      if (stockLimitsData is List) {
        return stockLimitsData
            .map((l) => WarehouseStockLimit.fromJson(l))
            .toList();
      }
      return [];
    } catch (e) {
      print('❌ Error parsing stock limits: $e');
      return [];
    }
  }

  /// Helper method to safely parse workers
  List<WarehouseWorker> _parseWorkers(dynamic workersData) {
    if (workersData == null) return [];

    try {
      if (workersData is List) {
        return workersData.map((w) => WarehouseWorker.fromJson(w)).toList();
      }
      return [];
    } catch (e) {
      print('❌ Error parsing workers: $e');
      return [];
    }
  }

  /// Parsea los layouts de la respuesta de Supabase (método legacy)
  List<WarehouseLayout> _parseLayouts(dynamic layoutsData, String warehouseId) {
    if (layoutsData == null) {
      print('🔍 layoutsData is null, returning empty list');
      return [];
    }

    try {
      print('🔍 Parsing layouts - type: ${layoutsData.runtimeType}');
      print('🔍 Layouts content: $layoutsData');

      // Handle different data types safely
      List<dynamic> layouts = [];

      if (layoutsData is List) {
        layouts = layoutsData;
      } else if (layoutsData is String && layoutsData.isEmpty) {
        print('🔍 layoutsData is empty string, returning empty list');
        return [];
      } else {
        print('🔍 layoutsData is unexpected type: ${layoutsData.runtimeType}');
        return [];
      }

      print('🔍 Processing ${layouts.length} layouts');

      return layouts
          .map((layout) {
            try {
              return WarehouseLayout(
                id: layout['layout_id']?.toString() ?? '',
                denominacion: layout['denominacion'] ?? '',
                tipoLayout: layout['tipo_layout'] ?? '',
                skuCodigo: layout['sku_codigo'],
                idAlmacen: warehouseId,
                createdAt:
                    layout['created_at'] != null
                        ? DateTime.parse(layout['created_at'])
                        : DateTime.now(),
              );
            } catch (e) {
              print('❌ Error parsing individual layout: $e');
              return null;
            }
          })
          .where((layout) => layout != null)
          .cast<WarehouseLayout>()
          .toList();
    } catch (e) {
      print('❌ Error parsing layouts: $e');
      return [];
    }
  }

  /// Convierte layouts nuevos a zones para compatibilidad con la UI existente
  List<WarehouseZone> _parseNewLayoutsToZones(dynamic layoutsData) {
    if (layoutsData == null) {
      print('🔍 layoutsData is null for zones, returning empty list');
      return [];
    }

    try {
      print('🔍 Parseando layouts a zones - tipo: ${layoutsData.runtimeType}');

      // Handle different data types safely
      List<dynamic> layouts = [];

      if (layoutsData is List) {
        layouts = layoutsData;
      } else if (layoutsData is String && layoutsData.isEmpty) {
        print('🔍 layoutsData is empty string for zones, returning empty list');
        return [];
      } else {
        print(
          '🔍 layoutsData is unexpected type for zones: ${layoutsData.runtimeType}',
        );
        return [];
      }

      print('🔍 Convirtiendo ${layouts.length} layouts a zones');

      return layouts
          .map((layout) {
            try {
              print('🔍 Layout para zone: $layout');

              final conditions = layout['condiciones'] as List<dynamic>? ?? [];
              final conditionNames = conditions
                  .map((c) => c['condicion']?.toString() ?? '')
                  .join(', ');

              print('🔍 Condiciones: $conditionNames');

              return WarehouseZone(
                id: layout['layout_id']?.toString() ?? '',
                warehouseId: '', // Se asignará después
                name: layout['denominacion'] ?? '',
                code: layout['sku_codigo'] ?? '',
                type: layout['tipo_layout'] ?? 'almacenamiento',
                conditions: conditionNames,
                capacity: 1000, // Valor por defecto
                currentOccupancy: 0,
                locations: [],
                conditionCodes:
                    conditions
                        .map((c) => c['condicion']?.toString() ?? '')
                        .toList(),
                parentId:
                    layout['layout_padre']
                        ?.toString(), // Handle string parent names
              );
            } catch (e) {
              print('❌ Error parsing individual layout to zone: $e');
              return null;
            }
          })
          .where((zone) => zone != null)
          .cast<WarehouseZone>()
          .toList();
    } catch (e) {
      print('❌ Error parsing new layouts to zones: $e');
      return [];
    }
  }

  /// Crea un almacén completo usando Supabase RPC
  Future<Map<String, dynamic>> createWarehouse({
    required String denominacionAlmacen,
    required String direccionAlmacen,
    required int idTiendaParam,
    String? ubicacionAlmacen,
    List<String>? almacenesosData,
    List<int>? condicionesData,
    List<Map<String, dynamic>>? layoutsData,
    List<Map<String, dynamic>>? limitesStockData,
  }) async {
    try {
      // Obtener UUID del usuario para el registro
      final userId = await _prefsService.getUserId();
      if (userId == null) {
        throw Exception('No se encontró el ID de usuario');
      }

      print('🏗️ Creando almacén con registrar_almacen_completo:');
      print('  - Denominación: $denominacionAlmacen');
      print('  - Dirección: $direccionAlmacen');
      print('  - ID Tienda: $idTiendaParam');
      print('  - Ubicación: $ubicacionAlmacen');
      print('  - Usuario: $userId');
      print('  - Layouts: ${layoutsData?.length ?? 0}');
      print('  - Condiciones: ${condicionesData?.length ?? 0}');
      print('  - Límites Stock: ${limitesStockData?.length ?? 0}');

      final response = await _supabase.rpc(
        'registrar_almacen_completo',
        params: {
          'denominacion_almacen': denominacionAlmacen,
          'direccion_almacen': direccionAlmacen,
          'id_tienda_param': idTiendaParam,
          'ubicacion_almacen': ubicacionAlmacen,
          'usuario_registrador': userId,
          'almaceneros_data': almacenesosData,
          'condiciones_data': condicionesData,
          'layouts_data': layoutsData,
          'limites_stock_data': limitesStockData,
        },
      );

      print('📦 Respuesta de registrar_almacen_completo:');
      print(response);

      if (response == null) {
        throw Exception('No se recibió respuesta del servidor');
      }

      // Verificar si la respuesta indica éxito
      if (response['success'] == false) {
        throw Exception(
          response['message'] ?? 'Error desconocido al crear almacén',
        );
      }

      return response;
    } catch (e) {
      print('❌ Error en createWarehouse: $e');
      rethrow;
    }
  }

  Future<void> updateWarehouseBasic(
    String id,
    Map<String, dynamic> payload,
  ) async {
    // PUT /api/almacenes/{id}
    await Future.delayed(const Duration(milliseconds: 150));
  }

  Future<void> deleteWarehouse(String id) async {
    // DELETE /api/almacenes/{id}
    await Future.delayed(const Duration(milliseconds: 150));
  }

  Future<void> addLayout(
    String warehouseId,
    Map<String, dynamic> layout,
  ) async {
    try {
      print('🏗️ Agregando layout al almacén $warehouseId');
      print('📦 Datos del layout: $layout');

      // Obtener UUID del usuario
      final userId = await _prefsService.getUserId();
      if (userId == null) {
        throw Exception('No se encontró el ID de usuario');
      }

      // Llamar RPC para registrar/actualizar layout (insertar nuevo)
      final response = await _supabase.rpc(
        'fn_registrar_actualizar_layout_almacen',
        params: {
          'p_denominacion': layout['name'],
          'p_id_almacen': int.parse(warehouseId),
          'p_id_layout': null, // null para insertar nuevo
          'p_id_layout_padre':
              layout['parentId'] != null
                  ? int.tryParse(layout['parentId'].toString())
                  : null,
          'p_id_tipo_layout': layout['typeId'],
          'p_sku_codigo': layout['code'],
        },
      );

      print('✅ Layout agregado exitosamente: $response');

      if (response == null || response['success'] == false) {
        throw Exception(response?['message'] ?? 'Error al agregar layout');
      }
    } catch (e) {
      print('❌ Error en addLayout: $e');
      rethrow;
    }
  }

  Future<void> updateLayout(
    String warehouseId,
    String layoutId,
    Map<String, dynamic> layout,
  ) async {
    try {
      print('🔄 Actualizando layout $layoutId del almacén $warehouseId');
      print('📦 Nuevos datos: $layout');

      // Obtener UUID del usuario
      final userId = await _prefsService.getUserId();
      if (userId == null) {
        throw Exception('No se encontró el ID de usuario');
      }

      // Llamar RPC para registrar/actualizar layout (actualizar existente)
      final response = await _supabase.rpc(
        'fn_registrar_actualizar_layout_almacen',
        params: {
          'p_denominacion': layout['name'],
          'p_id_almacen': int.parse(warehouseId),
          'p_id_layout': int.parse(layoutId), // ID del layout a actualizar
          'p_id_layout_padre':
              layout['parentId'] != null
                  ? int.tryParse(layout['parentId'].toString())
                  : null,
          'p_id_tipo_layout': layout['typeId'],
          'p_sku_codigo': layout['code'],
        },
      );

      print('✅ Layout actualizado exitosamente: $response');

      if (response == null || response['success'] == false) {
        throw Exception(response?['message'] ?? 'Error al actualizar layout');
      }
    } catch (e) {
      print('❌ Error en updateLayout: $e');
      rethrow;
    }
  }

  Future<void> deleteLayout(String warehouseId, String layoutId) async {
    try {
      print('🗑️ Eliminando layout $layoutId del almacén $warehouseId');

      // Obtener UUID del usuario
      final userId = await _prefsService.getUserId();
      if (userId == null) {
        throw Exception('No se encontró el ID de usuario');
      }

      // Llamar RPC para eliminar layout
      final response = await _supabase.rpc(
        'fn_eliminar_layout_almacen',
        params: {
          'p_id_layout': int.parse(layoutId),
          'p_usuario_eliminador': userId,
        },
      );

      print('✅ Layout eliminado exitosamente: $response');

      if (response == null || response['success'] == false) {
        throw Exception(response?['message'] ?? 'Error al eliminar layout');
      }
    } catch (e) {
      print('❌ Error en deleteLayout: $e');
      rethrow;
    }
  }

  Future<String> duplicateLayout(String warehouseId, String layoutId) async {
    try {
      print('📋 Duplicando layout $layoutId del almacén $warehouseId');

      // Obtener UUID del usuario
      final userId = await _prefsService.getUserId();
      if (userId == null) {
        throw Exception('No se encontró el ID de usuario');
      }

      // Llamar RPC para duplicar layout
      final response = await _supabase.rpc(
        'fn_duplicar_layout_almacen',
        params: {
          'p_id_layout_origen': int.parse(layoutId),
          'p_usuario_duplicador': userId,
        },
      );

      print('✅ Layout duplicado exitosamente: $response');

      if (response == null || response['success'] == false) {
        throw Exception(response?['message'] ?? 'Error al duplicar layout');
      }

      // Retornar el ID del nuevo layout
      return response['data']?['nuevo_layout_id']?.toString() ??
          'new-layout-id';
    } catch (e) {
      print('❌ Error en duplicateLayout: $e');
      rethrow;
    }
  }

  Future<void> bulkUpdateABC(
    String warehouseId,
    Map<String, String> layoutToAbc,
  ) async {
    try {
      print(
        '🔄 Actualizando clasificación ABC masiva para almacén $warehouseId',
      );
      print('📦 Layouts a actualizar: $layoutToAbc');

      // Obtener UUID del usuario
      final userId = await _prefsService.getUserId();
      if (userId == null) {
        throw Exception('No se encontró el ID de usuario');
      }

      // Llamar RPC para actualización masiva de ABC
      final response = await _supabase.rpc(
        'fn_actualizar_abc_layouts_masivo',
        params: {
          'p_id_almacen': int.parse(warehouseId),
          'p_layouts_abc': layoutToAbc,
          'p_usuario_modificador': userId,
        },
      );

      print('✅ ABC actualizado masivamente: $response');

      if (response == null || response['success'] == false) {
        throw Exception(response?['message'] ?? 'Error al actualizar ABC');
      }
    } catch (e) {
      print('❌ Error en bulkUpdateABC: $e');
      rethrow;
    }
  }

  Future<void> updateLayoutConditions(
    String warehouseId,
    String layoutId,
    List<String> conditionCodes,
  ) async {
    try {
      print('🔄 Actualizando condiciones del layout $layoutId');
      print('📦 Nuevas condiciones: $conditionCodes');

      // Obtener UUID del usuario
      final userId = await _prefsService.getUserId();
      if (userId == null) {
        throw Exception('No se encontró el ID de usuario');
      }

      // Llamar RPC para actualizar condiciones
      final response = await _supabase.rpc(
        'fn_actualizar_condiciones_layout',
        params: {
          'p_id_layout': int.parse(layoutId),
          'p_condiciones': conditionCodes,
          'p_usuario_modificador': userId,
        },
      );

      print('✅ Condiciones actualizadas: $response');

      if (response == null || response['success'] == false) {
        throw Exception(
          response?['message'] ?? 'Error al actualizar condiciones',
        );
      }
    } catch (e) {
      print('❌ Error en updateLayoutConditions: $e');
      rethrow;
    }
  }

  Future<void> updateStockLimits(
    String warehouseId,
    List<Map<String, dynamic>> limits,
  ) async {
    try {
      print('🔄 Actualizando límites de stock para almacén $warehouseId');
      print('📦 Límites: ${limits.length} productos');

      // Obtener UUID del usuario
      final userId = await _prefsService.getUserId();
      if (userId == null) {
        throw Exception('No se encontró el ID de usuario');
      }

      // Llamar RPC para actualizar límites de stock
      final response = await _supabase.rpc(
        'fn_actualizar_limites_stock_almacen',
        params: {
          'p_id_almacen': int.parse(warehouseId),
          'p_limites_stock': limits,
          'p_usuario_modificador': userId,
        },
      );

      print('✅ Límites de stock actualizados: $response');

      if (response == null || response['success'] == false) {
        throw Exception(response?['message'] ?? 'Error al actualizar límites');
      }
    } catch (e) {
      print('❌ Error en updateStockLimits: $e');
      rethrow;
    }
  }

  /// Ya no se necesita listar tiendas - siempre se usa la tienda del usuario desde preferencias
  Future<List<Store>> listStores() async {
    // Esta función ya no es necesaria ya que la tienda se obtiene de user preferences
    // Se mantiene por compatibilidad pero retorna lista vacía
    return [];
  }

  /// Obtiene tipos de layout disponibles desde Supabase
  Future<List<Map<String, dynamic>>> getTiposLayout() async {
    try {
      print('🔍 Llamando RPC fn_listar_tipos_layout_almacen');

      final response = await _supabase.rpc('fn_listar_tipos_layout_almacen');

      print('🔍 Respuesta tipos layout: $response');

      if (response == null) {
        throw Exception('No se pudo obtener tipos de layout del servidor');
      }

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error obteniendo tipos layout: $e');
      rethrow;
    }
  }


  /// Obtiene condiciones disponibles desde Supabase
  Future<List<Map<String, dynamic>>> getCondiciones() async {
    try {
      print('🔍 Llamando RPC fn_listar_todos_tipos_condiciones');

      final response = await _supabase.rpc('fn_listar_todos_tipos_condiciones');

      print('🔍 Respuesta condiciones: $response');

      if (response == null) {
        throw Exception('No se pudo obtener condiciones del servidor');
      }

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error obteniendo condiciones: $e');
      rethrow;
    }
  }


  /// Obtiene productos filtrados por tienda desde Supabase
  Future<List<Map<String, dynamic>>> getProductos() async {
    try {
      final idTienda = await _prefsService.getIdTienda();
      if (idTienda == null) {
        throw Exception('No se encontró ID de tienda en preferencias');
      }

      final response = await _supabase
          .from('app_dat_producto')
          .select('id, denominacion, sku, nombre_comercial, descripcion, um')
          .eq('id_tienda', idTienda)
          .eq('es_inventariable', true)
          .order('denominacion');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error obteniendo productos: $e');
      rethrow;
    }
  }

  /// Obtiene productos ubicados en un layout específico
  Future<List<Map<String, dynamic>>> getProductosByLayout(
    String layoutId,
  ) async {
    try {
      print('🔍 Obteniendo productos para layout: $layoutId');

      // Obtener ID de tienda desde preferencias
      final idTienda = await _prefsService.getIdTienda();
      if (idTienda == null) {
        print('❌ No se encontró ID de tienda en preferencias');
        return [];
      }

      print('🔍 ID Tienda: $idTienda, Layout ID: $layoutId');

      // Usar RPC fn_listar_inventario_productos_paged con filtro por ubicación
      final response = await _supabase.rpc(
        'fn_listar_inventario_productos_paged',
        params: {
          'p_id_tienda': idTienda,
          'p_id_ubicacion': int.tryParse(layoutId) ?? 0,
          'p_pagina': 1,
          'p_limite': 100, // Límite razonable para productos por layout
          'p_mostrar_sin_stock': false, // Mostrar todos los productos
          'p_es_inventariable': true, // Solo productos inventariables
        },
      );

      print(
        '📦 Respuesta inventario productos: ${response?.length ?? 0} items',
      );

      if (response == null || response.isEmpty) {
        print('⚠️ No se encontraron productos para este layout');
        return [];
      }

      // Transformar la respuesta del RPC al formato esperado por la UI
      final rawProducts =
          (response as List).map((item) {
            return {
              'id': item['id'],
              'denominacion': item['nombre_producto'] ?? 'Producto sin nombre',
              'sku': item['sku_producto'] ?? 'N/A',
              'descripcion': item['categoria'] ?? '',
              'um': 'UN', // Unidad por defecto
              'stock_actual': (item['cantidad_final'] ?? 0).toInt(),
              'stock_minimo':
                  10, // Valor por defecto, se podría obtener de límites
              'stock_maximo': 100, // Valor por defecto
              'stock_disponible': (item['stock_disponible'] ?? 0).toInt(),
              'stock_reservado': (item['stock_reservado'] ?? 0).toInt(),
              'ubicacion': item['ubicacion'] ?? 'Sin ubicación',
              'almacen': item['almacen'] ?? '',
              'tienda': item['tienda'] ?? '',
              'categoria': item['categoria'] ?? 'Sin categoría',
              'subcategoria': item['subcategoria'] ?? 'Sin subcategoría',
              'variante': item['variante'] ?? 'Unidad',
              'opcion_variante': item['opcion_variante'] ?? 'Única',
              'presentacion': item['presentacion'] ?? 'Unidad',
              'precio_venta': item['precio_venta'] ?? 0,
              'costo_promedio': item['costo_promedio'] ?? 0,
              'margen_actual': item['margen_actual'],
              'clasificacion_abc': item['clasificacion_abc'] ?? 3,
              'abc_descripcion': item['abc_descripcion'] ?? 'No clasificado',
              'es_vendible': item['es_vendible'] ?? true,
              'es_inventariable': item['es_inventariable'] ?? true,
              'fecha_ultima_actualizacion': item['fecha_ultima_actualizacion'],
              'lote': null, // No disponible en esta función
              'fecha_vencimiento': null, // No disponible en esta función
              'created_at': item['fecha_ultima_actualizacion'],
              // Clave única para agrupación por producto
              'product_key': '${item['id']}_${item['id_variante'] ?? 'null'}_${item['id_opcion_variante'] ?? 'null'}_${item['id_presentacion'] ?? 'null'}',
            };
          }).toList();

      print('📦 Productos sin agrupar: ${rawProducts.length}');

      // Agrupar productos por clave única para eliminar duplicados históricos
      final Map<String, Map<String, dynamic>> groupedProducts = {};
      
      for (final product in rawProducts) {
        final productKey = product['product_key'];
        
        if (!groupedProducts.containsKey(productKey)) {
          // Tomar la primera ocurrencia (más reciente por el ORDER BY de la función SQL)
          groupedProducts[productKey] = Map<String, dynamic>.from(product);
          // print('📦 Agregando producto: ${product['denominacion']} (key: $productKey, stock: ${product['stock_actual']})');
        } 
      }

      final products = groupedProducts.values.toList();
      //print('📦 Productos únicos después de agrupar: ${products.length}');
      // Log algunos productos para debug
      if (products.isNotEmpty) {
        print(
          '🔍 Primer producto: ${products.first['denominacion']} - Stock: ${products.first['stock_actual']}',
        );
      }

      return products;
    } catch (e) {
      print('❌ Error obteniendo productos del layout con RPC: $e');
      rethrow;
    }
  }


  /// Registrar o actualizar un layout usando RPC
  Future<Map<String, dynamic>?> registerOrUpdateLayout({
    required String warehouseId,
    String? layoutId, // null para crear, con valor para actualizar
    required int tipoLayoutId,
    required String denominacion,
    required String skuCodigo,
    String? layoutPadreId,
  }) async {
    try {
      print('🔄 === INICIO registerOrUpdateLayout ===');
      print('🔄 Warehouse ID: $warehouseId');
      print('🔄 Layout ID: $layoutId');
      print('🔄 Tipo Layout ID: $tipoLayoutId');
      print('🔄 Denominación: $denominacion');
      print('🔄 SKU Código: $skuCodigo');
      print('🔄 Layout Padre ID: $layoutPadreId');

      final response = await _supabase.rpc(
        'fn_registrar_actualizar_layout_almacen',
        params: {
          'p_id_almacen': int.tryParse(warehouseId) ?? 0,
          'p_id_layout': layoutId != null ? int.tryParse(layoutId) : null,
          'p_id_tipo_layout': tipoLayoutId,
          'p_denominacion': denominacion,
          'p_sku_codigo': skuCodigo,
          'p_id_layout_padre':
              layoutPadreId != null ? int.tryParse(layoutPadreId) : null,
        },
      );

      print('🔄 Respuesta RPC: $response');

      if (response == null || response.isEmpty) {
        print('❌ Respuesta vacía del RPC');
        return null;
      }

      // La función devuelve: [id_layout, mensaje, estado_op]
      final result = response[0];
      final layoutIdResult = result['f1']; // id_layout
      final mensaje = result['f2']; // mensaje
      final estadoOp = result['f3']; // estado_op

      print('✅ Resultado:');
      print('  - Layout ID: $layoutIdResult');
      print('  - Mensaje: $mensaje');
      print('  - Estado: $estadoOp');

      if (estadoOp == 'error') {
        print('❌ Error en la operación: $mensaje');
        return {'success': false, 'message': mensaje, 'error': true};
      }

      return {
        'success': true,
        'layoutId': layoutIdResult?.toString(),
        'message': mensaje,
        'operation': estadoOp, // 'creado' o 'actualizado'
      };
    } catch (e) {
      print('❌ Error en registerOrUpdateLayout: $e');
      return {
        'success': false,
        'message': 'Error al procesar la solicitud: $e',
        'error': true,
      };
    }
  }
}
