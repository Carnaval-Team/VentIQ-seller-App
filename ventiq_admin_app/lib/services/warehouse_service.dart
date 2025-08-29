import '../models/warehouse.dart';
import '../models/store.dart';
import 'mock_data_service.dart';
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
      print('🔄 Usando datos mock como fallback...');

      // Fallback a datos mock
      final mockWarehouses = MockDataService.getMockWarehouses();
      print('🤖 Datos mock cargados: ${mockWarehouses.length} almacenes');

      return WarehousePaginationResponse(
        almacenes: mockWarehouses,
        paginacion: WarehousePagination(
          paginaActual: pagina,
          porPagina: porPagina,
          totalPaginas: 1,
          totalAlmacenes: mockWarehouses.length,
          tieneSiguiente: false,
          tieneAnterior: false,
        ),
      );
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
      print('⚠️ Error en listWarehouses, usando datos mock: $e');
      // Fallback a datos mock en caso de error
      final all = MockDataService.getMockWarehouses();
      final filtered =
          all.where((w) {
            final byStore =
                storeId == null || storeId.isEmpty || storeId == 'all';
            final bySearch =
                search == null || search.trim().isEmpty
                    ? true
                    : w.name.toLowerCase().contains(search.toLowerCase());
            return byStore && bySearch;
          }).toList();
      await Future.delayed(const Duration(milliseconds: 250));
      return filtered;
    }
  }

  /// Obtiene detalles completos de un almacén usando la función listar
  Future<Warehouse> getWarehouseDetail(String id) async {
    try {
      print('🔍 Obteniendo detalle del almacén usando listar_almacenes_acceso_usuario con ID: $id');
      
      // Usar la función listar con filtro por ID específico
      final response = await _supabase.rpc(
        'listar_almacenes_acceso_usuario',
        params: {
          'p_uuid': _supabase.auth.currentUser?.id,
          'p_pagina': 1,
          'p_por_pagina': 1,
          'p_denominacion_filter': null,
          'p_direccion_filter': null,
          'p_tienda_filter': int.parse(id), // Filtrar por almacén específico
        },
      );

      print('🔍 ===== RESPUESTA COMPLETA LISTAR =====');
      print('🔍 Tipo de respuesta: ${response.runtimeType}');
      print('🔍 Respuesta completa: $response');
      print('🔍 ===================================');

      if (response == null || 
          !response['success'] || 
          response['data']['almacenes'] == null ||
          (response['data']['almacenes'] as List).isEmpty) {
        print('⚠️ No se encontró el almacén con ID: $id');
        throw Exception('Almacén no encontrado');
      }

      final almacenes = response['data']['almacenes'] as List;
      final warehouseData = almacenes.firstWhere(
        (almacen) => almacen['id'].toString() == id,
        orElse: () => almacenes.first,
      );
      
      print('🔍 ===== WAREHOUSE DATA =====');
      print('🔍 warehouseData completo: $warehouseData');
      print('🔍 ===========================');
      
      print('🔍 Estructura de warehouseData:');
      print('  - id: ${warehouseData['id']}');
      print('  - denominacion: ${warehouseData['denominacion']}');
      print('  - layouts: ${warehouseData['layouts']}');
      print('  - layouts type: ${warehouseData['layouts'].runtimeType}');
      print('  - condiciones: ${warehouseData['condiciones']}');
      print('  - tienda: ${warehouseData['tienda']}');
      print('  - roles: ${warehouseData['roles']}');

      // Crear el objeto Warehouse con los datos de la función listar
      final warehouse = Warehouse(
        id: warehouseData['id']?.toString() ?? id,
        name: warehouseData['denominacion'] ?? '',
        description: 'Almacén ${warehouseData['denominacion'] ?? ''}',
        address: warehouseData['direccion'] ?? '',
        city: warehouseData['ubicacion'] ?? '',
        country: 'Chile',
        type: 'principal',
        createdAt: warehouseData['created_at'] != null 
            ? DateTime.parse(warehouseData['created_at'])
            : DateTime.now(),
        zones: _parseLayoutsToZones(warehouseData['layouts']),
        // Supabase specific fields
        denominacion: warehouseData['denominacion'] ?? '',
        direccion: warehouseData['direccion'] ?? '',
        ubicacion: warehouseData['ubicacion'],
        tienda: warehouseData['tienda'] != null 
            ? WarehouseStore(
                id: warehouseData['tienda']['id']?.toString() ?? '',
                denominacion: warehouseData['tienda']['denominacion'] ?? '',
                direccion: warehouseData['tienda']['direccion'] ?? '',
              )
            : null,
        roles: (warehouseData['roles'] as List<dynamic>?)?.map((r) => r.toString()).toList() ?? [],
        layouts: _parseLayouts(warehouseData['layouts']),
        condiciones: (warehouseData['condiciones'] as List<dynamic>?)
            ?.map((c) => WarehouseCondition.fromJson(c))
            .toList() ?? [],
        almacenerosCount: warehouseData['almaceneros_count'] ?? 0,
        limitesStockCount: warehouseData['limites_stock_count'] ?? 0,
      );

      return warehouse;
    } catch (e) {
      print('❌ Error en getWarehouseDetail: $e');
      // Fallback a datos mock en caso de error
      final all = MockDataService.getMockWarehouses();
      final w = all.firstWhere((e) => e.id == id, orElse: () => all.first);
      return w;
    }
  }

  /// Parsea los layouts de la nueva respuesta RPC
  List<WarehouseLayout> _parseNewLayouts(dynamic layoutsData) {
    if (layoutsData == null) return [];

    try {
      print('🔍 Parseando layouts - tipo: ${layoutsData.runtimeType}');
      print('🔍 Contenido layouts: $layoutsData');
      
      final List<dynamic> layouts = layoutsData is List 
          ? layoutsData 
          : [];

      print('🔍 Layouts como lista: ${layouts.length} elementos');

      return layouts
          .map(
            (layout) {
              print('🔍 Layout individual: $layout');
              return WarehouseLayout(
                id: layout['layout_id']?.toString() ?? '',
                denominacion: layout['denominacion'] ?? '',
                tipoLayout: layout['tipo_layout'] ?? '',
                skuCodigo: layout['sku_codigo'],
              );
            },
          )
          .toList();
    } catch (e) {
      print('❌ Error parsing new layouts: $e');
      return [];
    }
  }

  /// Parsea los layouts de la respuesta de Supabase (método legacy)
  List<WarehouseLayout> _parseLayouts(dynamic layoutsData) {
    if (layoutsData == null) return [];

    try {
      final List<dynamic> layouts =
          layoutsData is String
              ? [] // Si es string vacío, retornar lista vacía
              : layoutsData as List<dynamic>;

      return layouts
          .map(
            (layout) => WarehouseLayout(
              id: layout['layout_id']?.toString() ?? '',
              denominacion: layout['denominacion'] ?? '',
              tipoLayout: layout['tipo_layout'] ?? '',
              skuCodigo: layout['sku_codigo'],
            ),
          )
          .toList();
    } catch (e) {
      print('Error parsing layouts: $e');
      return [];
    }
  }

  /// Convierte layouts nuevos a zones para compatibilidad con la UI existente
  List<WarehouseZone> _parseNewLayoutsToZones(dynamic layoutsData) {
    if (layoutsData == null) return [];

    try {
      print('🔍 Parseando layouts a zones - tipo: ${layoutsData.runtimeType}');
      
      final List<dynamic> layouts = layoutsData is List 
          ? layoutsData 
          : [];

      print('🔍 Convirtiendo ${layouts.length} layouts a zones');

      return layouts.map((layout) {
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
              conditions.map((c) => c['condicion']?.toString() ?? '').toList(),
        );
      }).toList();
    } catch (e) {
      print('❌ Error parsing new layouts to zones: $e');
      return [];
    }
  }

  /// Convierte layouts a zones para compatibilidad con la UI existente (método legacy)
  List<WarehouseZone> _parseLayoutsToZones(dynamic layoutsData) {
    if (layoutsData == null) return [];

    try {
      final List<dynamic> layouts =
          layoutsData is String ? [] : layoutsData as List<dynamic>;

      return layouts.map((layout) {
        final conditions = layout['condiciones'] as List<dynamic>? ?? [];
        final conditionNames = conditions
            .map((c) => c['condicion']?.toString() ?? '')
            .join(', ');

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
              conditions.map((c) => c['condicion']?.toString() ?? '').toList(),
        );
      }).toList();
    } catch (e) {
      print('Error parsing layouts to zones: $e');
      return [];
    }
  }

  /// Parsea los límites de stock de la nueva respuesta RPC
  List<Map<String, dynamic>>? _parseNewStockLimits(dynamic stockLimitsData) {
    if (stockLimitsData == null) return null;

    try {
      print('🔍 Parseando stock limits - tipo: ${stockLimitsData.runtimeType}');
      print('🔍 Contenido stock limits: $stockLimitsData');
      
      final List<dynamic> limits = stockLimitsData is List 
          ? stockLimitsData 
          : [];

      print('🔍 Stock limits como lista: ${limits.length} elementos');

      return limits
          .map(
            (limit) {
              print('🔍 Stock limit individual: $limit');
              return {
                'producto_id': limit['producto_id'],
                'producto_nombre': limit['producto_nombre'],
                'stock_min': limit['stock_min'],
                'stock_max': limit['stock_max'],
                'stock_ordenar': limit['stock_ordenar'],
              };
            },
          )
          .toList();
    } catch (e) {
      print('❌ Error parsing new stock limits: $e');
      return null;
    }
  }

  /// Parsea los límites de stock (método legacy)
  List<Map<String, dynamic>>? _parseStockLimits(dynamic stockLimitsData) {
    if (stockLimitsData == null) return null;

    try {
      final List<dynamic> limits =
          stockLimitsData is String ? [] : stockLimitsData as List<dynamic>;

      return limits
          .map(
            (limit) => {
              'producto_id': limit['producto_id'],
              'producto_nombre': limit['producto_nombre'],
              'stock_min': limit['stock_min'],
              'stock_max': limit['stock_max'],
              'stock_ordenar': limit['stock_ordenar'],
            },
          )
          .toList();
    } catch (e) {
      print('Error parsing stock limits: $e');
      return null;
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
    // POST /api/almacenes/{id}/layouts
    await Future.delayed(const Duration(milliseconds: 150));
  }

  Future<void> updateLayout(
    String warehouseId,
    String layoutId,
    Map<String, dynamic> layout,
  ) async {
    // PUT /api/almacenes/{id}/layouts/{layoutId}
    await Future.delayed(const Duration(milliseconds: 150));
  }

  Future<void> deleteLayout(String warehouseId, String layoutId) async {
    // DELETE /api/almacenes/{id}/layouts/{layoutId}
    await Future.delayed(const Duration(milliseconds: 150));
  }

  Future<String> duplicateLayout(String warehouseId, String layoutId) async {
    // POST /api/almacenes/{id}/layouts/{layoutId}/duplicate
    await Future.delayed(const Duration(milliseconds: 150));
    return 'new-layout-id';
  }

  Future<void> bulkUpdateABC(
    String warehouseId,
    Map<String, String> layoutToAbc,
  ) async {
    // POST /api/almacenes/{id}/layouts/abc: { layoutId: 'A'|'B'|'C' }
    await Future.delayed(const Duration(milliseconds: 200));
  }

  Future<void> updateLayoutConditions(
    String warehouseId,
    String layoutId,
    List<String> conditionCodes,
  ) async {
    // PUT /api/almacenes/{id}/layouts/{layoutId}/condiciones
    await Future.delayed(const Duration(milliseconds: 150));
  }

  Future<void> updateStockLimits(
    String warehouseId,
    List<Map<String, dynamic>> limits,
  ) async {
    // POST /api/almacenes/{id}/limites-stock
    await Future.delayed(const Duration(milliseconds: 150));
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
        print('⚠️ Respuesta nula, usando datos mock');
        return _getMockTiposLayout();
      }
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error obteniendo tipos layout: $e');
      return _getMockTiposLayout();
    }
  }
  
  List<Map<String, dynamic>> _getMockTiposLayout() {
    return [
      {'id': 1, 'denominacion': 'Almacenamiento', 'sku_codigo': 'ALM'},
      {'id': 2, 'denominacion': 'Picking', 'sku_codigo': 'PICK'},
      {'id': 3, 'denominacion': 'Expedición', 'sku_codigo': 'EXP'},
      {'id': 4, 'denominacion': 'Recepción', 'sku_codigo': 'REC'},
      {'id': 5, 'denominacion': 'Cuarentena', 'sku_codigo': 'CUAR'},
    ];
  }

  /// Obtiene condiciones disponibles desde Supabase
  Future<List<Map<String, dynamic>>> getCondiciones() async {
    try {
      final response = await _supabase
          .from('app_nom_tipo_condicion')
          .select(
            'id, denominacion, descripcion, es_refrigerado, es_fragil, es_peligroso',
          )
          .order('denominacion');

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error obteniendo condiciones: $e');
      // Fallback a datos mock
      return [
        {
          'id': 1,
          'denominacion': 'Refrigerado',
          'es_refrigerado': true,
          'es_fragil': false,
          'es_peligroso': false,
        },
        {
          'id': 2,
          'denominacion': 'Frágil',
          'es_refrigerado': false,
          'es_fragil': true,
          'es_peligroso': false,
        },
        {
          'id': 3,
          'denominacion': 'Peligroso',
          'es_refrigerado': false,
          'es_fragil': false,
          'es_peligroso': true,
        },
        {
          'id': 4,
          'denominacion': 'Seco',
          'es_refrigerado': false,
          'es_fragil': false,
          'es_peligroso': false,
        },
        {
          'id': 5,
          'denominacion': 'Ventilado',
          'es_refrigerado': false,
          'es_fragil': false,
          'es_peligroso': false,
        },
      ];
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
      print('Error obteniendo productos: $e');
      // Fallback a datos mock
      return [
        {'id': 1, 'denominacion': 'Coca Cola 350ml', 'sku': 'COCA350'},
        {'id': 2, 'denominacion': 'Pan Integral', 'sku': 'PAN001'},
        {'id': 3, 'denominacion': 'Leche Entera 1L', 'sku': 'LECHE1L'},
        {'id': 4, 'denominacion': 'Arroz Blanco 1kg', 'sku': 'ARROZ1K'},
        {'id': 5, 'denominacion': 'Aceite Vegetal 1L', 'sku': 'ACEITE1L'},
      ];
    }
  }
}
