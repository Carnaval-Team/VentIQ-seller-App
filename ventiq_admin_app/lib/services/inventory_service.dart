import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/inventory.dart';
import '../models/warehouse.dart';
import '../models/transfer_order.dart';
import 'user_preferences_service.dart';
import 'transfer_service.dart';

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

  /// Get motivo extraction options from app_nom_motivo_extraccion table
  static Future<List<Map<String, dynamic>>> getMotivoExtraccionOptions() async {
    try {
      print('🔍 Obteniendo opciones de motivo de extracción...');

      final response = await _supabase.rpc('fn_listar_motivos_extraccion');

      print('✅ Opciones de motivo extracción obtenidas: ${response.length}');
      print('📋 Datos: $response');

      if (response.isEmpty) {
        print(
          '⚠️ No hay motivos de extracción configurados en la base de datos',
        );
        // Return default options if table is empty
        return [
          {
            'id': 1,
            'denominacion': 'Producto dañado',
            'descripcion': 'Producto con daños físicos',
          },
          {
            'id': 2,
            'denominacion': 'Producto vencido',
            'descripcion': 'Producto fuera de fecha de vencimiento',
          },
          {
            'id': 3,
            'denominacion': 'Devolución cliente',
            'descripcion': 'Producto devuelto por el cliente',
          },
          {
            'id': 4,
            'denominacion': 'Ajuste de inventario',
            'descripcion': 'Corrección de diferencias de inventario',
          },
          {
            'id': 5,
            'denominacion': 'Transferencia a otra tienda',
            'descripcion': 'Movimiento entre tiendas',
          },
          {
            'id': 6,
            'denominacion': 'Muestra promocional',
            'descripcion': 'Producto usado para promoción',
          },
          {
            'id': 7,
            'denominacion': 'Uso interno',
            'descripcion': 'Consumo interno de la empresa',
          },
          {
            'id': 8,
            'denominacion': 'Pérdida/robo',
            'descripcion': 'Producto perdido o robado',
          },
        ];
      }

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error al obtener opciones de motivo extracción: $e');
      print('🔄 Usando opciones por defecto...');

      // Return default options on error
      return [
        {
          'id': 1,
          'denominacion': 'Producto dañado',
          'descripcion': 'Producto con daños físicos',
        },
        {
          'id': 2,
          'denominacion': 'Producto vencido',
          'descripcion': 'Producto fuera de fecha de vencimiento',
        },
        {
          'id': 3,
          'denominacion': 'Devolución cliente',
          'descripcion': 'Producto devuelto por el cliente',
        },
        {
          'id': 4,
          'denominacion': 'Ajuste de inventario',
          'descripcion': 'Corrección de diferencias de inventario',
        },
        {
          'id': 5,
          'denominacion': 'Transferencia a otra tienda',
          'descripcion': 'Movimiento entre tiendas',
        },
        {
          'id': 6,
          'denominacion': 'Muestra promocional',
          'descripcion': 'Producto usado para promoción',
        },
        {
          'id': 7,
          'denominacion': 'Uso interno',
          'descripcion': 'Consumo interno de la empresa',
        },
        {
          'id': 8,
          'denominacion': 'Pérdida/robo',
          'descripcion': 'Producto perdido o robado',
        },
      ];
    }
  }

  /// Insert complete extraction using fn_insertar_extraccion_completa RPC
  static Future<Map<String, dynamic>> insertCompleteExtraction({
    required String autorizadoPor,
    required int estadoInicial,
    required int idMotivoOperacion,
    required int idTienda,
    required String observaciones,
    required List<Map<String, dynamic>> productos,
    required String uuid,
  }) async {
    try {
      print('🔍 Insertando extracción completa...');
      print('📦 Productos a extraer: ${productos.length}');
      print('idMotivoOperacion: $idMotivoOperacion');
      final response = await _supabase.rpc(
        'fn_insertar_extraccion_completa',
        params: {
          'p_autorizado_por': autorizadoPor,
          'p_estado_inicial': estadoInicial,
          'p_id_motivo_operacion': idMotivoOperacion,
          'p_id_tienda': idTienda,
          'p_observaciones': observaciones,
          'p_productos': productos,
          'p_uuid': uuid,
        },
      );

      print('📦 Respuesta extracción: ${response.toString()}');

      if (response == null) {
        throw Exception('Respuesta nula del servidor');
      }

      final result = response as Map<String, dynamic>;

      if (result['status'] == 'success') {
        print('✅ Extracción registrada exitosamente');
        print('📊 ID Operación: ${result['id_operacion']}');
        print('📊 Total productos: ${result['total_productos']}');
        print('📊 Cantidad total: ${result['cantidad_total']}');
      } else {
        print('❌ Error en extracción: ${result['message']}');
      }

      return result;
    } catch (e) {
      print('❌ Error al insertar extracción: $e');
      return {
        'status': 'error',
        'message': 'Error al registrar extracción: $e',
      };
    }
  }

  /// Get inventory operations using fn_listar_operaciones RPC with pagination and filters
  /// Now includes global transfer operations from TransferService
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
      final idTienda =
          idTiendaRaw is int
              ? idTiendaRaw
              : (idTiendaRaw is String ? int.tryParse(idTiendaRaw) : null);

      if (userUuid == null || idTienda == null) {
        throw Exception('No se encontró información del usuario o tienda');
      }

      // Get regular inventory operations
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
        operations =
            response
                .map((item) => Map<String, dynamic>.from(item as Map))
                .toList();
        totalCount =
            (response.first as Map<String, dynamic>)['total_count'] ?? 0;
      }

      return {'operations': operations, 'total_count': totalCount};
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
      final response = await _supabase.rpc(
        'fn_listar_inventario_productos_paged',
        params: {
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
        },
      );

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
              print(
                '📋 Product ${products.length}: ${product.nombreProducto} - Stock: ${product.cantidadFinal}',
              );
            }
          }
        } catch (e) {
          print('❌ Error parsing product row: $e');
          print('🔍 Row data: $row');
        }
      }

      print('✅ Successfully loaded ${products.length} inventory products');
      print(
        '📊 Summary: ${summary?.totalInventario} total, ${summary?.totalSinStock} sin stock, ${summary?.totalConCantidadBaja} stock bajo',
      );
      print(
        '📄 Pagination: Página ${pagination?.paginaActual}/${pagination?.totalPaginas}, Siguiente: ${pagination?.tieneSiguiente}',
      );

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

  /// Unified transfer function between layouts
  /// Creates extraction and reception operations to handle inventory movements
  static Future<Map<String, dynamic>> transferBetweenLayouts({
    required int idLayoutOrigen,
    required int idLayoutDestino,
    required List<Map<String, dynamic>> productos,
    required String autorizadoPor,
    required String observaciones,
    int estadoInicial = 1, // 1 = Pendiente, 2 = Confirmado
  }) async {
    try {
      print('🔄 Iniciando transferencia entre layouts...');
      print(
        '📦 Layout origen: $idLayoutOrigen → Layout destino: $idLayoutDestino',
      );
      print('📦 Productos a transferir: ${productos.length}');

      final userUuid = await _prefsService.getUserId();

      // Obtener ID de tienda desde usuario autenticado
      final userData = await _prefsService.getUserData();
      final idTienda = userData['idTienda'] as int?;

      if (userUuid == null || idTienda == null) {
        throw Exception(
          'No se encontró información del usuario o tienda autenticada',
        );
      }

      print('👤 Usuario UUID: $userUuid');
      print('🏪 ID Tienda (desde usuario): $idTienda');

      // Validate required fields in productos
      for (var producto in productos) {
        if (producto['id_producto'] == null || producto['cantidad'] == null) {
          throw Exception('Cada producto debe tener: id_producto y cantidad');
        }
      }

      // Step 1: Create extraction operation (ID 7 - salida de almacén origen)
      print('📋 Paso 1: Creando operación de extracción (Tipo 7)...');

      final extractionProducts =
          productos.map((p) => {...p, 'id_layout': idLayoutOrigen}).toList();

      final extractionResult = await insertCompleteExtraction(
        autorizadoPor: autorizadoPor,
        estadoInicial: estadoInicial,
        idMotivoOperacion:
            7, // ID correcto para salida de almacén por transferencia
        idTienda: idTienda,
        observaciones: 'Extracción para transferencia: $observaciones',
        productos: extractionProducts,
        uuid: userUuid,
      );

      if (extractionResult['status'] != 'success') {
        throw Exception('Error en extracción: ${extractionResult['message']}');
      }

      final idExtraccion = extractionResult['id_operacion'];
      print('✅ Extracción creada con ID: $idExtraccion');

      // Step 2: Create reception operation (ID 8 - entrada por transferencia)
      print('📋 Paso 2: Creando operación de recepción (Tipo 8)...');

      final receptionProducts =
          productos
              .map(
                (p) => {
                  'id_producto': p['id_producto'],
                  'id_variante': p['id_variante'],
                  'id_opcion_variante': p['id_opcion_variante'],
                  'cantidad': p['cantidad'],
                  'precio_unitario': p['precio_unitario'] ?? 0.0,
                  'id_layout': idLayoutDestino,
                  'id_motivo_operacion':
                      2, // ID correcto para entrada por transferencia
                },
              )
              .toList();

      final receptionResult = await insertInventoryReception(
        entregadoPor: autorizadoPor,
        idTienda: idTienda,
        montoTotal: receptionProducts.fold<double>(
          0.0,
          (sum, p) =>
              sum +
              ((p['cantidad'] as double) * (p['precio_unitario'] as double)),
        ),
        motivo: 2, // ID del motivo de recepción por transferencia
        observaciones: 'Transferencia: $observaciones',
        productos: receptionProducts,
        recibidoPor: autorizadoPor,
        uuid: userUuid,
      );

      if (receptionResult['status'] != 'success') {
        throw Exception('Error en recepción: ${receptionResult['message']}');
      }

      final idRecepcion = receptionResult['id_operacion'];
      print('✅ Recepción creada con ID: $idRecepcion');

      // Step 3: If estadoInicial is 2 (confirmed), complete the operations immediately
      if (estadoInicial == 2) {
        print('📋 Paso 3: Confirmando transferencia automáticamente...');

        // Confirm extraction
        final confirmExtractionResult = await _supabase.rpc(
          'fn_registrar_cambio_estado_operacion',
          params: {
            'p_id_operacion': idExtraccion,
            'p_nuevo_estado': 2, // Confirmado
            'p_comentario': 'Transferencia confirmada automáticamente',
            'p_uuid': userUuid,
          },
        );

        // Confirm reception
        final confirmReceptionResult = await _supabase.rpc(
          'fn_registrar_cambio_estado_operacion',
          params: {
            'p_id_operacion': idRecepcion,
            'p_nuevo_estado': 2, // Confirmado
            'p_comentario': 'Transferencia confirmada automáticamente',
            'p_uuid': userUuid,
          },
        );

        if (confirmExtractionResult['status'] != 'success' ||
            confirmReceptionResult['status'] != 'success') {
          print(
            '⚠️ Advertencia: Error al confirmar operaciones automáticamente',
          );
        }
      }

      print('✅ Transferencia completada exitosamente');
      return {
        'status': 'success',
        'message': 'Transferencia entre layouts completada exitosamente',
        'id_extraccion': idExtraccion,
        'id_recepcion': idRecepcion,
        'total_productos': productos.length,
        'estado': estadoInicial == 2 ? 'confirmado' : 'pendiente',
      };
    } catch (e) {
      print('❌ Error en transferencia: $e');
      return {'status': 'error', 'message': 'Error en transferencia: $e'};
    }
  }

  /// Confirm a pending transfer and account for inventory movements
  static Future<Map<String, dynamic>> confirmTransfer({
    required int idOperacionGeneral,
    required String comentario,
    required String uuid,
  }) async {
    try {
      print('🔄 Confirmando transferencia $idOperacionGeneral...');

      // Get the linked extraction and reception operations
      final operationsResponse =
          await _supabase
              .from('app_dat_operacion_transferencia')
              .select('id_extraccion, id_recepcion')
              .eq('id_operacion_general', idOperacionGeneral)
              .single();

      if (operationsResponse.isEmpty) {
        throw Exception(
          'No se encontraron operaciones vinculadas a la transferencia',
        );
      }

      final idExtraccion = operationsResponse['id_extraccion'];
      final idRecepcion = operationsResponse['id_recepcion'];

      // Complete extraction operation (accounting for inventory out)
      print('📤 Contabilizando extracción...');
      final extractionComplete = await completeOperation(
        idOperacion: idExtraccion,
        comentario: 'Confirmación de transferencia - Salida: $comentario',
        uuid: uuid,
      );

      if (extractionComplete['status'] != 'success') {
        throw Exception(
          'Error al contabilizar extracción: ${extractionComplete['message']}',
        );
      }

      // Complete reception operation (accounting for inventory in)
      print('📥 Contabilizando recepción...');
      final receptionComplete = await completeOperation(
        idOperacion: idRecepcion,
        comentario: 'Confirmación de transferencia - Entrada: $comentario',
        uuid: uuid,
      );

      if (receptionComplete['status'] != 'success') {
        throw Exception(
          'Error al contabilizar recepción: ${receptionComplete['message']}',
        );
      }

      // Update general operation status to confirmed
      print('✅ Actualizando estado de operación general...');
      await _supabase.rpc(
        'fn_actualizar_estado_operacion',
        params: {
          'p_id_operacion': idOperacionGeneral,
          'p_nuevo_estado': 2, // Confirmado
          'p_comentario': comentario,
          'p_uuid': uuid,
        },
      );

      print('✅ Transferencia confirmada y contabilizada exitosamente');
      return {
        'status': 'success',
        'message': 'Transferencia confirmada y contabilizada exitosamente',
        'id_operacion_general': idOperacionGeneral,
        'id_extraccion': idExtraccion,
        'id_recepcion': idRecepcion,
      };
    } catch (e) {
      print('❌ Error al confirmar transferencia: $e');
      return {
        'status': 'error',
        'message': 'Error al confirmar transferencia: $e',
      };
    }
  }

  /// Get pending transfers that need confirmation
  static Future<List<Map<String, dynamic>>> getPendingTransfers() async {
    try {
      print('🔍 Obteniendo transferencias pendientes...');

      final idTienda = await _prefsService.getIdTienda();
      if (idTienda == null) {
        throw Exception('No se encontró el ID de tienda');
      }

      final response = await _supabase
          .from('app_dat_operacion')
          .select('''
            id,
            tipo_operacion,
            estado,
            autorizado_por,
            observaciones,
            created_at,
            app_dat_operacion_transferencia!inner(
              id_extraccion,
              id_recepcion
            )
          ''')
          .eq('id_tienda', idTienda)
          .eq('tipo_operacion', 19) // ID correcto para transferencia
          .eq('estado', 1) // Pendiente
          .order('created_at', ascending: false);

      print('✅ Transferencias pendientes obtenidas: ${response.length}');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error al obtener transferencias pendientes: $e');
      return [];
    }
  }

  /// Get available zones/locations for a warehouse
  static Future<List<Map<String, dynamic>>> getWarehouseZones(
    int idAlmacen,
  ) async {
    try {
      print('🔍 Obteniendo zonas del almacén $idAlmacen...');

      final response = await _supabase
          .from('app_dat_layout_almacen')
          .select('id, denominacion, codigo, tipo, abc, capacidad')
          .eq('id_almacen', idAlmacen)
          .eq('activo', true)
          .order('denominacion');

      print('✅ Zonas obtenidas: ${response.length}');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error al obtener zonas: $e');
      return [];
    }
  }

  /// Get products in a specific zone
  static Future<List<InventoryProduct>> getZoneProducts({
    required int idAlmacen,
    required int idUbicacion,
  }) async {
    try {
      print(
        '🔍 Obteniendo productos de la zona $idUbicacion en almacén $idAlmacen...',
      );

      final response = await getInventoryProducts(
        idAlmacen: idAlmacen,
        idUbicacion: idUbicacion,
        mostrarSinStock: false, // Only show products with stock
      );

      print('✅ Productos en zona obtenidos: ${response.products.length}');
      return response.products;
    } catch (e) {
      print('❌ Error al obtener productos de zona: $e');
      return [];
    }
  }

  /// Get current USD price from reception table
  static Future<double> getCurrentProductPrice({
    required int idProducto,
    int? idVariante,
    int? idOpcionVariante,
  }) async {
    try {
      print('💰 Obteniendo precio actual del producto $idProducto');

      // Build the query with conditions
      var query = _supabase
          .from('app_dat_recepcion_productos')
          .select('precio_unitario')
          .eq('id_producto', idProducto);

      // Add variant conditions if they exist
      if (idVariante != null) {
        query = query.eq('id_variante', idVariante);
      } else {
        query = query.isFilter('id_variante', null);
      }

      if (idOpcionVariante != null) {
        query = query.eq('id_opcion_variante', idOpcionVariante);
      } else {
        query = query.isFilter('id_opcion_variante', null);
      }

      // Get the most recent price
      final response = await query
          .order('created_at', ascending: false)
          .limit(1);

      if (response.isNotEmpty && response[0]['precio_unitario'] != null) {
        final price = (response[0]['precio_unitario'] as num).toDouble();
        print('✅ Precio actual encontrado: \$${price.toStringAsFixed(2)} USD');
        return price;
      }

      print('⚠️ No se encontró precio para el producto');
      return 0.0;
    } catch (e) {
      print('❌ Error al obtener precio actual: $e');
      return 0.0;
    }
  }

  /// Update product price in reception table
  static Future<void> updateProductPrice({
    required int idProducto,
    int? idVariante,
    int? idOpcionVariante,
    required double nuevoPrecio,
  }) async {
    try {
      print(
        '💰 Actualizando precio del producto $idProducto a \$${nuevoPrecio.toStringAsFixed(2)} USD',
      );

      // Build the update query with conditions
      var query = _supabase
          .from('app_dat_recepcion_productos')
          .update({'precio_unitario': nuevoPrecio})
          .eq('id_producto', idProducto);

      // Add variant conditions if they exist
      if (idVariante != null) {
        query = query.eq('id_variante', idVariante);
      } else {
        query = query.isFilter('id_variante', null);
      }

      if (idOpcionVariante != null) {
        query = query.eq('id_opcion_variante', idOpcionVariante);
      } else {
        query = query.isFilter('id_opcion_variante', null);
      }

      // Execute the update
      await query;

      print('✅ Precio actualizado exitosamente');
    } catch (e) {
      print('❌ Error al actualizar precio: $e');
      throw Exception('Error al actualizar precio: $e');
    }
  }

  /// Inserta una recepción completa de inventario usando RPC
  static Future<Map<String, dynamic>> insertInventoryReception({
    required String entregadoPor,
    required int idTienda,
    required double montoTotal,
    required int motivo,
    required String observaciones,
    required List<Map<String, dynamic>> productos,
    required String recibidoPor,
    required String uuid,
  }) async {
    try {
      print('🔍 Insertando recepción de inventario...');
      print(
        '📦 Parámetros: entregadoPor=$entregadoPor, idTienda=$idTienda, productos=${productos.length}',
      );

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

  /// Get product variants and presentations available in a specific location
  /// Returns detailed information about stock availability for each variant/presentation
  static Future<List<Map<String, dynamic>>> getProductVariantsInLocation({
    required int idProducto,
    required int idLayout,
  }) async {
    try {
      print(
        '🔍 Obteniendo variantes del producto $idProducto en layout $idLayout...',
      );

      final response = await _supabase.rpc(
        'fn_listar_inventario_productos_paged',
        params: {
          'p_id_producto': idProducto,
          'p_id_layout': idLayout,
          'p_mostrar_sin_stock': false, // Solo con stock
          'p_page': 1,
          'p_page_size': 100, // Suficiente para todas las variantes
        },
      );

      if (response == null) {
        print('⚠️ Respuesta nula del RPC');
        return [];
      }

      final data = response['data'] as List<dynamic>? ?? [];
      print('📦 Encontradas ${data.length} variantes con stock');

      final variants =
          data.map<Map<String, dynamic>>((item) {
            final stockDisponible = (item['stock_disponible'] ?? 0).toDouble();

            return {
              'id_producto': item['id_producto'] ?? idProducto,
              'nombre_producto': item['denominacion'] ?? 'Producto sin nombre',
              'sku_producto': item['sku_producto'] ?? '',

              // Información de variante
              'id_variante': item['id_variante'],
              'variante_nombre': item['variante'] ?? 'Sin variante',
              'id_opcion_variante': item['id_opcion_variante'],
              'opcion_variante_nombre': item['opcion_variante'] ?? 'Única',

              // Información de presentación
              'id_presentacion': item['id_presentacion'],
              'presentacion_nombre': item['um'] ?? 'UN',
              'presentacion_codigo': item['um_codigo'] ?? 'UN',

              // Stock disponible
              'stock_disponible': stockDisponible,
              'stock_reservado': (item['stock_reservado'] ?? 0).toDouble(),
              'stock_actual': (item['stock_actual'] ?? 0).toDouble(),

              // Información adicional
              'precio_unitario': (item['precio_venta'] ?? 0).toDouble(),
              'id_layout': idLayout,

              // Clave única para identificar esta combinación específica
              'variant_key':
                  '${item['id_variante'] ?? 'null'}_${item['id_opcion_variante'] ?? 'null'}_${item['id_presentacion'] ?? 'null'}',
            };
          }).toList();

      // Agrupar por variante y opción para mejor organización
      final groupedVariants = <String, List<Map<String, dynamic>>>{};
      for (final variant in variants) {
        final key =
            '${variant['id_variante']}_${variant['id_opcion_variante']}';
        groupedVariants[key] ??= [];
        groupedVariants[key]!.add(variant);
      }

      print('📊 Variantes agrupadas: ${groupedVariants.keys.length} grupos');
      for (final entry in groupedVariants.entries) {
        print('   ${entry.key}: ${entry.value.length} presentaciones');
      }

      return variants;
    } catch (e) {
      print('❌ Error obteniendo variantes del producto: $e');
      return [];
    }
  }
}
