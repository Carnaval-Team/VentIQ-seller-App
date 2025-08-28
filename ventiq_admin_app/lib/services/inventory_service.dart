import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/inventory.dart';
import '../models/warehouse.dart';
import 'user_preferences_service.dart';

class InventoryService {
  static final InventoryService _instance = InventoryService._internal();
  factory InventoryService() => _instance;
  InventoryService._internal();

  static final SupabaseClient _supabase = Supabase.instance.client;
  static final UserPreferencesService _prefsService = UserPreferencesService();

  /// Get motivo reception options from app_nom_motivo_recepcion table
  static Future<List<Map<String, dynamic>>> getMotivoRecepcionOptions() async {
    try {
      print('🔍 Obteniendo opciones de motivo de recepción...');
      
      final response = await _supabase
          .from('app_nom_motivo_recepcion')
          .select('id, denominacion, descripcion');

      print('✅ Opciones de motivo obtenidas: ${response.length}');
      return List<Map<String, dynamic>>.from(response);
      
    } catch (e) {
      print('❌ Error al obtener opciones de motivo: $e');
      rethrow;
    }
  }

  /// Get inventory operations using fn_listar_operaciones RPC with pagination and filters
  static Future<Map<String, dynamic>> getInventoryOperations({
    String? busqueda,
    DateTime? fechaDesde,
    DateTime? fechaHasta,
    int? limite,
    int? pagina,
  }) async {
    try {
      print('🔍 Obteniendo operaciones de inventario...');
      
      final userUuid = await _prefsService.getUserId();
      final userData = await _prefsService.getUserData();
      final idTiendaRaw = userData['idTienda'];
      final idTienda = idTiendaRaw is int ? idTiendaRaw : (idTiendaRaw is String ? int.tryParse(idTiendaRaw) : null);
      
      if (userUuid == null || idTienda == null) {
        throw Exception('No se encontró información del usuario o tienda');
      }

      final response = await _supabase.rpc(
        'fn_listar_operaciones_inventario_re',
        params: {
          'p_id_tienda': idTienda,
          'p_id_tpv': null,
          'p_id_tipo_operacion': null,
          'p_estados': null,
          'p_fecha_desde': fechaDesde?.toIso8601String().split('T')[0],
          'p_fecha_hasta': fechaHasta?.toIso8601String().split('T')[0],
          'p_uuid_usuario_operador': null,
          'p_busqueda': busqueda,
          'p_limite': limite,
          'p_pagina': pagina,
        },
      );

      if (response == null) {
        throw Exception('No se recibió respuesta del servidor');
      }

      // Extract total count from the first item if available
      int totalCount = 0;
      List<Map<String, dynamic>> operations = [];
      
      if (response is List && response.isNotEmpty) {
        operations = response.map((item) => Map<String, dynamic>.from(item as Map)).toList();
        totalCount = (response.first as Map<String, dynamic>)['total_count'] ?? 0;
      }

      return {
        'operations': operations,
        'total_count': totalCount,
      };
    } catch (e) {
      print('Error al obtener operaciones de inventario: $e');
      rethrow;
    }
  }

  /// Get inventory products using fn_listar_inventario_productos RPC with pagination
  static Future<InventoryResponse> getInventoryProducts({
    String? busqueda,
    int? clasificacionAbc,
    bool? conStockMinimo,
    bool? esInventariable,
    bool? esVendible,
    int? idAlmacen,
    int? idCategoria,
    int? idOpcionVariante,
    int? idPresentacion,
    int? idProducto,
    int? idProveedor,
    int? idSubcategoria,
    int? idUbicacion,
    int? idVariante,
    int limite = 50,
    bool? mostrarSinStock,
    String? origenCambio,
    int pagina = 1,
  }) async {
    try {
      print('🔍 InventoryService: Getting inventory products...');
      
      // Get store ID from preferences
      final idTienda = await _prefsService.getIdTienda();
      print('📍 Store ID from preferences: $idTienda');

      if (idTienda == null) {
        throw Exception('No se encontró el ID de tienda en las preferencias');
      }

      // Call the RPC function
      final response = await _supabase.rpc('fn_listar_inventario_productos_paged', params: {
        'p_busqueda': busqueda,
        'p_clasificacion_abc': clasificacionAbc,
        'p_con_stock_minimo': conStockMinimo,
        'p_es_inventariable': esInventariable,
        'p_es_vendible': esVendible,
        'p_id_almacen': idAlmacen,
        'p_id_categoria': idCategoria,
        'p_id_opcion_variante': idOpcionVariante,
        'p_id_presentacion': idPresentacion,
        'p_id_producto': idProducto,
        'p_id_proveedor': idProveedor,
        'p_id_subcategoria': idSubcategoria,
        'p_id_tienda': idTienda,
        'p_id_ubicacion': idUbicacion,
        'p_id_variante': idVariante,
        'p_limite': limite,
        'p_mostrar_sin_stock': mostrarSinStock ?? true,
        'p_origen_cambio': origenCambio,
        'p_pagina': pagina,
      });

      print('📦 RPC Response type: ${response.runtimeType}');
      print('📦 RPC Response length: ${response?.length ?? 0}');
      
      if (response == null || response.isEmpty) {
        print('⚠️ No data received from RPC');
        return InventoryResponse(products: []);
      }
      
      print('📦 RPC Response first: ${response[0]}');

      // Parse the response
      final List<InventoryProduct> products = [];
      InventorySummary? summary;
      PaginationInfo? pagination;
      
      for (final row in response) {
        try {
          if (row is Map<String, dynamic>) {
            final product = InventoryProduct.fromSupabaseRpc(row);
            products.add(product);
            
            // Extract summary and pagination from first product (they're the same for all rows)
            if (summary == null && product.resumenInventario != null) {
              summary = product.resumenInventario;
            }
            if (pagination == null && product.infoPaginacion != null) {
              pagination = product.infoPaginacion;
            }
            
            // Debug first few products
            if (products.length <= 3) {
              print('📋 Product ${products.length}: ${product.nombreProducto} - Stock: ${product.cantidadFinal}');
            }
          }
        } catch (e) {
          print('❌ Error parsing product row: $e');
          print('🔍 Row data: $row');
        }
      }

      print('✅ Successfully loaded ${products.length} inventory products');
      print('📊 Summary: ${summary?.totalInventario} total, ${summary?.totalSinStock} sin stock, ${summary?.totalConCantidadBaja} stock bajo');
      print('📄 Pagination: Página ${pagination?.paginaActual}/${pagination?.totalPaginas}, Siguiente: ${pagination?.tieneSiguiente}');
      
      return InventoryResponse(
        products: products,
        summary: summary,
        pagination: pagination,
      );

    } catch (e) {
      print('❌ Error in getInventoryProducts: $e');
      rethrow;
    }
  }

  /// Get warehouses for the current store
  static Future<List<Warehouse>> getWarehouses() async {
    try {
      print('🏪 InventoryService: Getting warehouses...');
      
      // Get store ID from preferences
      final idTienda = await _prefsService.getIdTienda();
      print('📍 Store ID for warehouses: $idTienda');

      if (idTienda == null) {
        throw Exception('No se encontró el ID de tienda en las preferencias');
      }

      // Query app_dat_almacen table with store filter
      final response = await _supabase
          .from('app_dat_almacen')
          .select('*')
          .eq('id_tienda', idTienda);

      print('🏬 Warehouses response: ${response.length} warehouses found');

      final List<Warehouse> warehouses = [];
      for (final warehouseData in response) {
        try {
          // Convert to Warehouse model (adapt to existing structure)
          final warehouse = Warehouse(
            id: warehouseData['id']?.toString() ?? '',
            name: warehouseData['denominacion'] ?? 'Almacén sin nombre',
            description: warehouseData['descripcion'] ?? 'Almacén de productos',
            address: warehouseData['direccion'] ?? '',
            city: warehouseData['ciudad'] ?? 'Sin especificar',
            country: warehouseData['pais'] ?? 'Chile',
            latitude: warehouseData['latitud']?.toDouble(),
            longitude: warehouseData['longitud']?.toDouble(),
            type: warehouseData['tipo'] ?? 'principal',
            isActive: warehouseData['activo'] ?? true,
            createdAt: warehouseData['created_at'] != null 
                ? DateTime.parse(warehouseData['created_at'])
                : DateTime.now(),
            zones: [], // Will be populated separately if needed
            // Supabase specific fields
            denominacion: warehouseData['denominacion'] ?? '',
            direccion: warehouseData['direccion'] ?? '',
            ubicacion: warehouseData['ubicacion'],
            tienda: null, // Will be populated if needed
            roles: [],
            layouts: [],
            condiciones: [],
            almacenerosCount: 0,
            limitesStockCount: 0,
          );
          
          warehouses.add(warehouse);
          print('🏪 Warehouse: ${warehouse.name}');
        } catch (e) {
          print('❌ Error parsing warehouse: $e');
          print('🔍 Warehouse data: $warehouseData');
        }
      }

      print('✅ Successfully loaded ${warehouses.length} warehouses');
      return warehouses;

    } catch (e) {
      print('❌ Error in getWarehouses: $e');
      rethrow;
    }
  }

  /// Get inventory products with warehouse filter
  static Future<InventoryResponse> getInventoryByWarehouse(int warehouseId, {int pagina = 1}) async {
    return getInventoryProducts(idAlmacen: warehouseId, pagina: pagina);
  }

  /// Search inventory products
  static Future<InventoryResponse> searchInventoryProducts(String query, {int pagina = 1}) async {
    return getInventoryProducts(busqueda: query, pagina: pagina);
  }

  /// Get products with low stock
  static Future<InventoryResponse> getLowStockProducts({int pagina = 1}) async {
    return getInventoryProducts(conStockMinimo: true, pagina: pagina);
  }

  /// Get products without stock
  static Future<InventoryResponse> getOutOfStockProducts({int pagina = 1}) async {
    return getInventoryProducts(mostrarSinStock: false, pagina: pagina);
  }

  /// Inserta una recepción completa de inventario usando RPC
  static Future<Map<String, dynamic>> insertInventoryReception({
    required String entregadoPor,
    required int idTienda,
    required double montoTotal,
    required String motivo,
    required String observaciones,
    required List<Map<String, dynamic>> productos,
    required String recibidoPor,
    required String uuid,
  }) async {
    try {
      print('🔍 Insertando recepción de inventario...');
      print('📦 Parámetros: entregadoPor=$entregadoPor, idTienda=$idTienda, productos=${productos.length}');

      final response = await _supabase.rpc(
        'fn_insertar_recepcion_completa',
        params: {
          'p_entregado_por': entregadoPor,
          'p_id_tienda': idTienda,
          'p_monto_total': montoTotal,
          'p_motivo': motivo,
          'p_observaciones': observaciones,
          'p_productos': productos,
          'p_recibido_por': recibidoPor,
          'p_uuid': uuid,
        },
      );

      print('📦 Respuesta RPC: $response');

      if (response == null) {
        throw Exception('Respuesta nula de la función RPC');
      }

      return response as Map<String, dynamic>;

    } catch (e, stackTrace) {
      print('❌ Error en insertInventoryReception: $e');
      print('📍 StackTrace: $stackTrace');
      throw Exception('Error al insertar recepción: $e');
    }
  }

  /// Complete operation using fn_contabilizar_operacion RPC
  static Future<Map<String, dynamic>> completeOperation({
    required int idOperacion,
    required String comentario,
    required String uuid,
  }) async {
    try {
      print('🔄 Completando operación $idOperacion...');
      
      final response = await _supabase.rpc(
        'fn_contabilizar_operacion',
        params: {
          'p_id_operacion': idOperacion,
          'p_comentario': comentario,
          'p_uuid': uuid,
        },
      );

      print('✅ Operación completada: $response');

      if (response == null) {
        throw Exception('No se recibió respuesta del servidor');
      }

      return response as Map<String, dynamic>;
    } catch (e) {
      print('❌ Error al completar operación: $e');
      rethrow;
    }
  }
}
