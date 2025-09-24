import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/inventory.dart';
import '../models/warehouse.dart';
import '../models/transfer_order.dart';
import 'user_preferences_service.dart';
import 'transfer_service.dart';
import 'product_service.dart';
import 'financial_service.dart';
import 'restaurant_service.dart'; // Agregar import para conversión de unidades

class InventoryService {
  static final InventoryService _instance = InventoryService._internal();
  factory InventoryService() => _instance;
  InventoryService._internal();

  static final SupabaseClient _supabase = Supabase.instance.client;
  static final UserPreferencesService _prefsService = UserPreferencesService();
  static final FinancialService _financialService = FinancialService();

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

      // CORREGIDO: Los productos ya vienen procesados, no procesar de nuevo
      print('✅ Usando productos ya procesados (sin doble procesamiento)');

      // LOG DETALLADO: Verificar estructura de productos
      print('🔍 ESTRUCTURA DE PRODUCTOS ENVIADOS:');
      for (int i = 0; i < productos.length; i++) {
        final producto = productos[i];
        print(
          '   Producto $i: id_producto=${producto['id_producto']}, cantidad=${producto['cantidad']}, id_presentacion=${producto['id_presentacion']}',
        );
      }

      final response = await _supabase.rpc(
        'fn_insertar_extraccion_completa',
        params: {
          'p_autorizado_por': autorizadoPor,
          'p_estado_inicial': estadoInicial,
          'p_id_motivo_operacion': idMotivoOperacion,
          'p_id_tienda': idTienda,
          'p_observaciones': observaciones,
          'p_productos': productos, // Usar productos tal como vienen
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
      final userData = await _prefsService.getUserData();
      final idTiendaRaw = userData['idTienda'];
      final idTienda =
          idTiendaRaw is int
              ? idTiendaRaw
              : (idTiendaRaw is String ? int.tryParse(idTiendaRaw) : null);

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
          'p_limite': 9999,
          'p_mostrar_sin_stock': mostrarSinStock ?? true,
          'p_origen_cambio': origenCambio,
          'p_pagina': 1,
        },
      );

      print('📦 RPC Response type: ${response.runtimeType}');
      print('📦 RPC Response length: ${response?.length ?? 0}');
      print('📦 RPC Response first: ${response?[0]}');

      if (response == null || response.isEmpty) {
        print('⚠️ No data received from RPC');
        return InventoryResponse(products: []);
      }

      // Handle nested response structure from fn_listar_inventario_productos_paged
      final data =
          response is List
              ? response as List<dynamic>
              : (response['data'] as List<dynamic>? ?? []);
      print('📦 Encontradas ${data.length} variantes con stock');

      final List<InventoryProduct> products = [];
      InventorySummary? summary;
      PaginationInfo? pagination;

      for (final row in data) {
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
      final idTiendaRaw = userData['idTienda'];
      final idTienda =
          idTiendaRaw is int
              ? idTiendaRaw
              : (idTiendaRaw is String ? int.tryParse(idTiendaRaw) : null);

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

      final extractionProducts = await processProductsForExtraction(productos);

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
                  'id_presentacion':
                      p['id_presentacion'], // Add missing presentation ID
                  'cantidad': p['cantidad'],
                  'precio_unitario': p['precio_unitario'] ?? 0.0,
                  'id_ubicacion':
                      idLayoutDestino, // Fix: use id_ubicacion instead of id_layout
                  'id_motivo_operacion':
                      2, // ID correcto para entrada por transferencia
                },
              )
              .toList();

      final processedReceptionProducts = await processProductsForReception(
        receptionProducts,
      );

      final receptionResult = await insertInventoryReception(
        entregadoPor: autorizadoPor,
        idTienda: idTienda,
        montoTotal: processedReceptionProducts.fold<double>(
          0.0,
          (sum, p) =>
              sum +
              ((p['cantidad'] as double) * (p['precio_unitario'] as double)),
        ),
        motivo: 2, // ID del motivo de recepción por transferencia
        observaciones: 'Transferencia: $observaciones',
        productos: processedReceptionProducts,
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

        // Complete extraction operation (accounting for inventory out)
        print('📤 Contabilizando extracción...');
        final completeExtractionResult = await completeOperation(
          idOperacion: idExtraccion,
          comentario:
              'Extracción de transferencia completada automáticamente - $observaciones',
          uuid: userUuid,
        );

        print(
          '📋 Resultado completeOperation (extracción): $completeExtractionResult',
        );

        if (completeExtractionResult['status'] != 'success') {
          print(
            '⚠️ Error al completar extracción: ${completeExtractionResult['message']}',
          );
        } else {
          print('✅ Extracción completada exitosamente');
          print(
            '📊 Productos afectados (extracción): ${completeExtractionResult['productos_afectados']}',
          );
        }

        // Complete reception operation (accounting for inventory in)
        print('📥 Contabilizando recepción...');
        final completeReceptionResult = await completeOperation(
          idOperacion: idRecepcion,
          comentario:
              'Recepción de transferencia completada automáticamente - $observaciones',
          uuid: userUuid,
        );

        print(
          '📋 Resultado completeOperation (recepción): $completeReceptionResult',
        );

        if (completeReceptionResult['status'] != 'success') {
          print(
            '⚠️ Error al completar recepción: ${completeReceptionResult['message']}',
          );
        } else {
          print('✅ Recepción completada exitosamente');
          print(
            '📊 Productos afectados (recepción): ${completeReceptionResult['productos_afectados']}',
          );
        }

        // Check if both operations completed successfully
        if (completeExtractionResult['status'] != 'success' ||
            completeReceptionResult['status'] != 'success') {
          print(
            '⚠️ Advertencia: Error al completar operaciones automáticamente',
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

      // NUEVO: Procesar productos para conversión automática a presentación base
      print('🔄 Procesando productos para conversión a presentación base...');
      final productosConvertidos = await processProductsForReception(productos);

      final response = await _supabase.rpc(
        'fn_insertar_recepcion_completa',
        params: {
          'p_entregado_por': entregadoPor,
          'p_id_tienda': idTienda,
          'p_monto_total': montoTotal,
          'p_motivo': motivo,
          'p_observaciones': observaciones,
          'p_productos': productosConvertidos, // Usar productos convertidos
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

  /// Verifica el inventario de ingredientes en una zona específica
  static Future<Map<String, dynamic>> checkIngredientsInventoryInZone({
    required List<Map<String, dynamic>> ingredients,
    required String zoneId,
  }) async {
    try {
      print('🔍 Verificando inventario de ingredientes en zona $zoneId');

      List<Map<String, dynamic>> availableIngredients = [];
      List<Map<String, dynamic>> unavailableIngredients = [];

      final storeId = await _getStoreId();

      for (final ingredient in ingredients) {
        final productIdRaw = ingredient['id_producto'];
        final productId =
            productIdRaw is int
                ? productIdRaw
                : int.tryParse(productIdRaw.toString()) ?? 0;

        if (productId == 0) {
          print('⚠️ ID de producto inválido: $productIdRaw, saltando...');
          continue;
        }

        final requiredQuantity = ingredient['cantidad'] as double;

        // Obtener inventario del producto en la zona específica
        final response = await _supabase.rpc(
          'fn_listar_inventario_productos_paged',
          params: {
            'p_id_tienda': storeId,
            'p_id_ubicacion': int.tryParse(zoneId) ?? 1,
            'p_id_producto': productId,
            'p_pagina': 1,
            'p_limite': 1,
            'p_mostrar_sin_stock': false,
            'p_es_inventariable': true,
          },
        );

        if (response != null && response.isNotEmpty) {
          final inventoryData = response is List ? response[0] : response;
          print('📦 Respuesta RPC para producto $productId: $response');

          final stockEnPresentacion =
              (inventoryData['stock_disponible'] as num?)?.toDouble() ?? 0.0;
          final idPresentacion = inventoryData['id_presentacion'] as int?;
          final presentacionNombre =
              inventoryData['presentacion_nombre'] ?? 'Sin presentación';

          print(
            '📦 Stock en presentación: $stockEnPresentacion $presentacionNombre (presentación ID: $idPresentacion)',
          );

          // NUEVA LÓGICA: Mantener stock en unidades de presentación y convertir cantidad requerida a unidades de presentación
          double availableStock = stockEnPresentacion;
          double cantidadPorPresentacion = 1.0;
          double cantidadRequeridaEnPresentacion = requiredQuantity;

          // Obtener la cantidad por presentación y unidad de medida para hacer conversiones
          if (idPresentacion != null && stockEnPresentacion > 0) {
            try {
              print(
                '🔍 Obteniendo cantidad por presentación para producto $productId...',
              );

              // Consultar la tabla app_dat_presentacion_unidad_medida
              final presentacionUmResponse = await _supabase
                  .from('app_dat_presentacion_unidad_medida')
                  .select('cantidad_um, id_unidad_medida')
                  .eq('id_producto', productId)
                  .limit(1);

              if (presentacionUmResponse.isNotEmpty) {
                cantidadPorPresentacion =
                    (presentacionUmResponse.first['cantidad_um'] as num)
                        .toDouble();
                final unidadProductoId =
                    presentacionUmResponse.first['id_unidad_medida'] as int?;

                print('✅ Cantidad por presentación: $cantidadPorPresentacion');
                print('✅ Unidad del producto ID: $unidadProductoId');

                // NUEVA LÓGICA: Convertir cantidad del ingrediente a unidad base del producto
                double cantidadEnUnidadBase = requiredQuantity;
                final unidadIngrediente =
                    ingredient['unidad_medida'] as String? ?? '';
                print('🔍 DEBUG CONVERSIÓN:');
                print('   - unidadIngrediente: "$unidadIngrediente"');
                print('   - unidadProductoId: $unidadProductoId');
                print('   - requiredQuantity: $requiredQuantity');
                print('   - ingredient keys: ${ingredient.keys.toList()}');
                if (unidadIngrediente.isNotEmpty && unidadProductoId != null) {
                  final unidadIngredienteId = await _mapUnidadStringToId(
                    unidadIngrediente,
                  );

                  if (unidadIngredienteId != null &&
                      unidadIngredienteId != unidadProductoId) {
                    print(
                      '🔄 Convirtiendo de unidad $unidadIngredienteId ($unidadIngrediente) a unidad $unidadProductoId...',
                    );

                    try {
                      cantidadEnUnidadBase =
                          await RestaurantService.convertirUnidades(
                            cantidad: requiredQuantity,
                            unidadOrigen: unidadIngredienteId,
                            unidadDestino: unidadProductoId,
                            idProducto: productId,
                          );
                      print(
                        '✅ Conversión exitosa: $requiredQuantity $unidadIngrediente → $cantidadEnUnidadBase',
                      );
                    } catch (e) {
                      print(
                        '⚠️ Error en conversión: $e, usando cantidad original',
                      );
                      cantidadEnUnidadBase = requiredQuantity;
                    }
                  } else {
                    print(
                      '📝 Sin conversión necesaria: unidades iguales o no mapeables',
                    );
                  }
                }

                // Convertir cantidad en unidad base a unidades de presentación
                cantidadRequeridaEnPresentacion =
                    cantidadEnUnidadBase / cantidadPorPresentacion;

                print('🔄 Conversión completa:');
                print(
                  '   1. Ingrediente: $requiredQuantity $unidadIngrediente',
                );
                print('   2. En unidad base: $cantidadEnUnidadBase');
                print(
                  '   3. En presentaciones: $cantidadEnUnidadBase ÷ $cantidadPorPresentacion = $cantidadRequeridaEnPresentacion',
                );
              } else {
                print(
                  '⚠️ No se encontró configuración de UM, usando cantidad por defecto: 1.0',
                );
              }
            } catch (e) {
              print(
                '⚠️ Error obteniendo cantidad por presentación: $e, usando 1.0',
              );
            }
          }

          print('📦 Stock disponible: $availableStock $presentacionNombre');
          print('🔢 Cantidad por presentación: $cantidadPorPresentacion');
          print(
            '⚖️ Comparación: $availableStock $presentacionNombre >= $cantidadRequeridaEnPresentacion $presentacionNombre',
          );

          final ingredientInfo = {
            ...ingredient,
            'stock_disponible': availableStock,
            'unidad_presentacion': presentacionNombre,
            'cantidad_necesaria_original': requiredQuantity,
            'cantidad_necesaria_presentacion': cantidadRequeridaEnPresentacion,
            'cantidad_por_presentacion': cantidadPorPresentacion,
            'denominacion':
                inventoryData['denominacion'] ?? 'Producto $productId',
            'sku': inventoryData['sku'] ?? '',
            'id_presentacion':
                idPresentacion, // ✅ AGREGAR: id_presentacion del inventario
            'id_variante': inventoryData['id_variante'], // Agregar id_variante
            'id_opcion_variante':
                inventoryData['id_opcion_variante'], // Agregar id_opcion_variante
          };

          // Comparar en unidades de presentación
          if (availableStock >= cantidadRequeridaEnPresentacion) {
            availableIngredients.add(ingredientInfo);
            print(
              '✅ Producto $productId disponible: $availableStock >= $cantidadRequeridaEnPresentacion $presentacionNombre',
            );
          } else {
            unavailableIngredients.add(ingredientInfo);
            print(
              '❌ Producto $productId insuficiente: $availableStock < $cantidadRequeridaEnPresentacion $presentacionNombre',
            );
          }
        } else {
          unavailableIngredients.add({
            ...ingredient,
            'stock_disponible': 0.0,
            'denominacion': 'Producto $productId',
            'sku': '',
          });
        }
      }

      return {
        'success': unavailableIngredients.isEmpty,
        'available_ingredients': availableIngredients,
        'unavailable_ingredients': unavailableIngredients,
        'zone_id': zoneId,
      };
    } catch (e) {
      print('❌ Error verificando inventario: $e');
      return {
        'success': false,
        'error': e.toString(),
        'available_ingredients': <Map<String, dynamic>>[],
        'unavailable_ingredients': <Map<String, dynamic>>[],
        'zone_id': zoneId,
      };
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
          'p_id_ubicacion':
              idLayout, // Fix: use p_id_ubicacion instead of p_id_layout
          'p_mostrar_sin_stock': false, // Solo con stock
          'p_pagina': 1, // Fix: use p_pagina instead of p_page
          'p_limite': 100, // Fix: use p_limite instead of p_page_size
        },
      );

      if (response == null) {
        print('⚠️ Respuesta nula del RPC');
        return [];
      }

      // Handle nested response structure from fn_listar_inventario_productos_paged
      final data =
          response is List
              ? response as List<dynamic>
              : (response['data'] as List<dynamic>? ?? []);
      print('📦 Encontradas ${data.length} variantes con stock');

      final variants =
          data.map<Map<String, dynamic>>((item) {
            final stockDisponible =
                (item['stock_disponible'] as num?)?.toDouble() ?? 0.0;

            // Debug logging for variant data analysis
            /* print('🔍 Processing item:');
            print('   - id_variante: ${item['id_variante']} (${item['id_variante'].runtimeType})');
            print('   - variante: ${item['variante']} (${item['variante'].runtimeType})');
            print('   - id_opcion_variante: ${item['id_opcion_variante']} (${item['id_opcion_variante'].runtimeType})');
            print('   - opcion_variante: ${item['opcion_variante']} (${item['opcion_variante'].runtimeType})');
            print('   - id_presentacion: ${item['id_presentacion']} (${item['id_presentacion'].runtimeType})');
            print('   - um: ${item['um']} (${item['um'].runtimeType})');
            print('   - stock_disponible: ${item['stock_disponible']}');*/

            return {
              'id_producto': item['id_producto'] ?? idProducto,
              'nombre_producto': item['denominacion'] ?? 'Producto sin nombre',
              'sku_producto': item['sku_producto'] ?? '',

              // Información de variante
              'id_variante': item['id_variante'],
              'variante_nombre': item['variante'] ?? 'Sin variante',
              'id_opcion_variante': item['id_opcion_variante'],
              'opcion_variante_nombre': item['opcion_variante'] ?? 'Única',

              // Información de presentación - Handle null id_presentacion
              'id_presentacion':
                  item['id_presentacion'], // Keep original null value
              'presentacion_nombre':
                  item['id_presentacion'] != null
                      ? _safeSubstring(
                        item['um'] ?? 'UN',
                        0,
                        3,
                      ) // Safe substring to prevent RangeError
                      : 'Sin presentación',
              'presentacion_codigo':
                  item['id_presentacion'] != null
                      ? (item['um_codigo'] ?? 'UN')
                      : 'SIN_PRES',

              // Stock disponible
              'stock_disponible': stockDisponible,
              'stock_reservado':
                  (item['stock_reservado'] as num?)?.toDouble() ?? 0.0,
              'stock_actual': (item['stock_actual'] as num?)?.toDouble() ?? 0.0,

              // Información adicional
              'precio_unitario':
                  (item['precio_venta'] as num?)?.toDouble() ?? 0.0,
              'id_layout': idLayout,

              // Clave única para agrupación - Solo por presentación para transferencias
              'presentation_key': '${item['id_presentacion'] ?? 'null'}',
            };
          }).toList();

      // Agrupar por presentación únicamente (ignorar variantes)
      final Map<String, Map<String, dynamic>> groupedPresentations = {};

      for (final variant in variants) {
        final presentationKey = variant['presentation_key'];

        if (!groupedPresentations.containsKey(presentationKey)) {
          // Tomar la primera ocurrencia de cada presentación (stocks ya consolidados en SQL)
          groupedPresentations[presentationKey] = Map<String, dynamic>.from(
            variant,
          );
          print(
            '📦 Agregando presentación: ${variant['presentacion_nombre']} (key: $presentationKey, stock: ${variant['stock_disponible']})',
          );
        } else {
          // No sumar stocks - ya vienen consolidados de la función SQL
          print(
            '📦 Ignorando duplicado de presentación: ${variant['presentacion_nombre']} (key: $presentationKey, stock: ${variant['stock_disponible']})',
          );
        }
      }

      final groupedVariants = groupedPresentations.values.toList();
      print(
        '📦 Después de agrupar: ${groupedVariants.length} presentaciones únicas',
      );

      return groupedVariants;
    } catch (e) {
      print('❌ Error obteniendo variantes del producto: $e');
      return [];
    }
  }

  /// Get product presentations available in a specific location/zone
  /// This method queries for all presentations of a product in a zone, even if no inventory exists
  /// Used as fallback when getProductVariantsInLocation returns empty
  static Future<List<Map<String, dynamic>>> getProductPresentationsInZone({
    required int idProducto,
    required int idLayout,
  }) async {
    try {
      print(
        '🔍 Obteniendo presentaciones del producto $idProducto en zona $idLayout...',
      );

      // Query to get all presentations configured for this product in this zone
      final response = await _supabase.rpc(
        'fn_listar_inventario_productos_paged',
        params: {
          'p_id_producto': idProducto,
          'p_id_ubicacion':
              idLayout, // Fix: use p_id_ubicacion instead of p_id_layout
          'p_mostrar_sin_stock': true, // Include zero stock items
          'p_pagina': 1, // Fix: use p_pagina instead of p_page
          'p_limite': 100, // Fix: use p_limite instead of p_page_size
        },
      );

      if (response == null) {
        print('⚠️ Respuesta nula del RPC para presentaciones');
        return [];
      }

      final data = response['data'] as List<dynamic>? ?? [];
      print('📦 Encontradas ${data.length} presentaciones configuradas');

      final presentations =
          data.map<Map<String, dynamic>>((item) {
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
              'id_presentacion':
                  item['id_presentacion'], // Keep original null value
              'presentacion_nombre':
                  item['id_presentacion'] != null
                      ? _safeSubstring(
                        item['um'] ?? 'UN',
                        0,
                        3,
                      ) // Safe substring to prevent RangeError
                      : 'Sin presentación',
              'presentacion_codigo':
                  item['id_presentacion'] != null
                      ? (item['um_codigo'] ?? 'UN')
                      : 'SIN_PRES',

              // Stock (puede ser 0)
              'stock_disponible':
                  (item['stock_disponible'] as num?)?.toDouble() ?? 0.0,
              'stock_reservado':
                  (item['stock_reservado'] as num?)?.toDouble() ?? 0.0,
              'stock_actual': (item['stock_actual'] as num?)?.toDouble() ?? 0.0,

              // Información adicional
              'precio_unitario':
                  (item['precio_venta'] as num?)?.toDouble() ?? 0.0,
              'id_layout': idLayout,

              // Clave única
              'variant_key':
                  '${item['id_variante'] ?? 'null'}_${item['id_opcion_variante'] ?? 'null'}_${item['id_presentacion'] ?? 'null'}',
            };
          }).toList();

      print('📊 Presentaciones encontradas: ${presentations.length}');
      for (final pres in presentations) {
        print(
          '   - ID: ${pres['id_presentacion']}, Nombre: ${pres['presentacion_nombre']}, Stock: ${pres['stock_disponible']}',
        );
      }

      return presentations;
    } catch (e) {
      print('❌ Error obteniendo presentaciones del producto: $e');
      return [];
    }
  }

  /// Procesa productos para recepción convirtiendo a presentación base
  static Future<List<Map<String, dynamic>>> processProductsForReception(
    List<Map<String, dynamic>> productos,
  ) async {
    final processedProducts = <Map<String, dynamic>>[];

    print('🔄 ===== PROCESANDO PRODUCTOS PARA RECEPCIÓN =====');
    print('🔄 Total productos a procesar: ${productos.length}');

    for (final producto in productos) {
      try {
        final productIdRaw = producto['id_producto'];
        final productId =
            productIdRaw is int
                ? productIdRaw
                : int.tryParse(productIdRaw.toString()) ?? 0;

        if (productId == 0) {
          print('⚠️ ID de producto inválido: $productIdRaw, saltando...');
          continue;
        }

        final presentacionId = producto['id_presentacion'] as int?;
        final cantidadOriginal = (producto['cantidad'] as num).toDouble();

        print('🔄 Procesando producto ID: $productId');
        print('🔄 Presentación seleccionada: $presentacionId');
        print('🔄 Cantidad original: $cantidadOriginal');

        if (presentacionId == null) {
          print(
            '⚠️ No hay presentación seleccionada, usando cantidad original',
          );
          processedProducts.add(producto);
          continue;
        }

        // Convertir a presentación base
        final cantidadEnBase = await ProductService.convertToBasePresentacion(
          productId: productId,
          fromPresentacionId: presentacionId,
          cantidad: cantidadOriginal,
        );

        // Obtener presentación base
        final basePresentation = await ProductService.getBasePresentacion(
          productId,
        );

        if (basePresentation != null) {
          // Crear producto procesado con presentación base
          final processedProduct = Map<String, dynamic>.from(producto);
          processedProduct['id_presentacion'] =
              basePresentation['id_presentacion'];
          processedProduct['cantidad'] = cantidadEnBase;
          processedProduct['cantidad_original'] = cantidadOriginal;
          processedProduct['presentacion_original'] = presentacionId;
          processedProduct['conversion_applied'] =
              cantidadEnBase != cantidadOriginal;

          processedProducts.add(processedProduct);

          print('✅ Producto procesado:');
          print(
            '   - Cantidad original: $cantidadOriginal (presentación: $presentacionId)',
          );
          print(
            '   - Cantidad en base: $cantidadEnBase (presentación: ${basePresentation['id_presentacion']})',
          );
          print(
            '   - Conversión aplicada: ${cantidadEnBase != cantidadOriginal}',
          );
        } else {
          print('⚠️ No se pudo obtener presentación base, usando original');
          processedProducts.add(producto);
        }
      } catch (e) {
        print('❌ Error procesando producto: $e');
        processedProducts.add(producto); // Agregar original en caso de error
      }
    }

    print('✅ Procesamiento completado: ${processedProducts.length} productos');
    return processedProducts;
  }

  /// Procesa productos para extracción convirtiendo a presentación base
  static Future<List<Map<String, dynamic>>> processProductsForExtraction(
    List<Map<String, dynamic>> productos,
  ) async {
    final processedProducts = <Map<String, dynamic>>[];

    print('🔄 ===== PROCESANDO PRODUCTOS PARA EXTRACCIÓN =====');
    print('🔄 Total productos a procesar: ${productos.length}');

    for (final producto in productos) {
      try {
        final productIdRaw = producto['id_producto'];
        final productId =
            productIdRaw is int
                ? productIdRaw
                : int.tryParse(productIdRaw.toString()) ?? 0;

        if (productId == 0) {
          print('⚠️ ID de producto inválido: $productIdRaw, saltando...');
          continue;
        }

        final presentacionId = producto['id_presentacion'] as int?;
        final cantidadOriginal = (producto['cantidad'] as num).toDouble();

        print('🔄 Procesando extracción producto ID: $productId');
        print('🔄 Presentación seleccionada: $presentacionId');
        print('🔄 Cantidad a extraer: $cantidadOriginal');

        if (presentacionId == null) {
          print(
            '⚠️ No hay presentación seleccionada, usando cantidad original',
          );
          processedProducts.add(producto);
          continue;
        }

        // Convertir a presentación base
        final cantidadEnBase = await ProductService.convertToBasePresentacion(
          productId: productId,
          fromPresentacionId: presentacionId,
          cantidad: cantidadOriginal,
        );

        // Obtener presentación base
        final basePresentation = await ProductService.getBasePresentacion(
          productId,
        );

        if (basePresentation != null) {
          // Crear producto procesado con presentación base
          final processedProduct = Map<String, dynamic>.from(producto);
          processedProduct['id_presentacion'] =
              basePresentation['id_presentacion'];
          processedProduct['cantidad'] = cantidadEnBase;
          processedProduct['cantidad_original'] = cantidadOriginal;
          processedProduct['presentacion_original'] = presentacionId;
          processedProduct['conversion_applied'] =
              cantidadEnBase != cantidadOriginal;

          processedProducts.add(processedProduct);

          print('✅ Extracción procesada:');
          print(
            '   - Cantidad original: $cantidadOriginal (presentación: $presentacionId)',
          );
          print(
            '   - Cantidad en base: $cantidadEnBase (presentación: ${basePresentation['id_presentacion']})',
          );
          print(
            '   - Conversión aplicada: ${cantidadEnBase != cantidadOriginal}',
          );
        } else {
          print('⚠️ No se pudo obtener presentación base, usando original');
          processedProducts.add(producto);
        }
      } catch (e) {
        print('❌ Error procesando extracción: $e');
        processedProducts.add(producto); // Agregar original en caso de error
      }
    }

    print(
      '✅ Procesamiento de extracción completado: ${processedProducts.length} productos',
    );
    return processedProducts;
  }

  /// Descompone un producto elaborado recursivamente
  static Future<void> _decomposeRecursively(
    int productId,
    double quantity,
    Map<int, Map<String, dynamic>> consolidatedIngredients,
  ) async {
    print('🔄 Descomponiendo producto $productId con cantidad $quantity');

    final ingredients = await ProductService.getProductIngredients(
      productId.toString(),
    );

    if (ingredients.isEmpty) {
      print('⚠️ Producto $productId sin ingredientes - tratando como simple');
      _addToConsolidatedWithUnit(
        consolidatedIngredients,
        productId,
        quantity,
        'und',
        'Producto $productId',
        '',
      );
      return;
    }

    for (final ingredient in ingredients) {
      final ingredientIdRaw = ingredient['producto_id'];
      final ingredientId =
          ingredientIdRaw is int
              ? ingredientIdRaw
              : int.tryParse(ingredientIdRaw.toString()) ?? 0;

      if (ingredientId == 0) {
        print('⚠️ ID de ingrediente inválido: $ingredientIdRaw, saltando...');
        continue;
      }

      final cantidadNecesaria =
          (ingredient['cantidad_necesaria'] as num).toDouble();
      final unidadMedidaIngrediente =
          ingredient['unidad_medida'] as String? ?? 'und';
      final denominacionIngrediente =
          ingredient['producto_nombre'] ?? 'Producto $ingredientId';
      final skuIngrediente = ingredient['producto_sku'] ?? '';
      final totalQuantityEnUnidadIngrediente = cantidadNecesaria * quantity;

      print('🧪 Ingrediente ID: $ingredientId');
      print(
        '   - Cantidad necesaria: $cantidadNecesaria $unidadMedidaIngrediente',
      );
      print(
        '   - Cantidad total requerida: $totalQuantityEnUnidadIngrediente $unidadMedidaIngrediente',
      );

      // Convertir la cantidad del ingrediente a su presentación base
      double cantidadEnPresentacionBase;
      try {
        // Obtener la presentación base del ingrediente
        final basePresentation = await ProductService.getBasePresentacion(
          ingredientId,
        );

        if (basePresentation != null) {
          // Si el ingrediente tiene presentaciones configuradas, convertir
          print(
            '   - Presentación base encontrada: ${basePresentation['denominacion']}',
          );

          // TODO: Aquí necesitamos convertir de la unidad del ingrediente a la presentación base
          // Por ahora, usamos la cantidad directamente pero esto debe mejorarse
          cantidadEnPresentacionBase = totalQuantityEnUnidadIngrediente;

          print(
            '   - Cantidad en presentación base: $cantidadEnPresentacionBase',
          );
        } else {
          // Si no tiene presentaciones configuradas, usar cantidad directa
          cantidadEnPresentacionBase = totalQuantityEnUnidadIngrediente;
          print(
            '   - Sin presentación base configurada, usando cantidad directa',
          );
        }
      } catch (e) {
        print(
          '⚠️ Error al obtener presentación base para ingrediente $ingredientId: $e',
        );
        cantidadEnPresentacionBase = totalQuantityEnUnidadIngrediente;
      }

      final isElaborated = await _isProductElaborated(ingredientId);

      if (isElaborated) {
        print(
          '🔄 Ingrediente $ingredientId es elaborado, descomponiendo recursivamente...',
        );
        await _decomposeRecursively(
          ingredientId,
          cantidadEnPresentacionBase,
          consolidatedIngredients,
        );
      } else {
        print('✅ Ingrediente $ingredientId es simple, agregando directamente');
        _addToConsolidatedWithUnit(
          consolidatedIngredients,
          ingredientId,
          cantidadEnPresentacionBase,
          unidadMedidaIngrediente,
          denominacionIngrediente,
          skuIngrediente,
        );
      }
    }
  }

  /// Consolida ingredientes (versión simple para compatibilidad)
  static void _addToConsolidated(
    Map<int, double> consolidatedIngredients,
    int productId,
    double quantity,
  ) {
    if (consolidatedIngredients.containsKey(productId)) {
      consolidatedIngredients[productId] =
          consolidatedIngredients[productId]! + quantity;
    } else {
      consolidatedIngredients[productId] = quantity;
    }
    print(
      '📊 Consolidado: Producto $productId = ${consolidatedIngredients[productId]} unidades',
    );
  }

  /// Verifica si un producto es elaborado consultando el campo es_elaborado
  static Future<bool> _isProductElaborated(int productId) async {
    try {
      print('🔍 Verificando si producto $productId es elaborado...');

      final response =
          await _supabase
              .from('app_dat_producto')
              .select('es_elaborado')
              .eq('id', productId)
              .single();

      final isElaborated = response['es_elaborado'] ?? false;
      print('📋 Producto $productId es elaborado: $isElaborated');

      return isElaborated;
    } catch (e) {
      print('⚠️ Error verificando si producto $productId es elaborado: $e');
      // En caso de error, asumir que no es elaborado para evitar recursión infinita
      return false;
    }
  }

  /// Descompone productos elaborados en sus ingredientes base
  /// Retorna una lista de productos (ingredientes) con sus cantidades consolidadas
  static Future<List<Map<String, dynamic>>> decomposeElaboratedProducts(
    List<Map<String, dynamic>> productos,
  ) async {
    print('🧪 Iniciando descomposición de productos elaborados...');

    final Map<int, Map<String, dynamic>> consolidatedIngredients = {};

    for (final producto in productos) {
      final productIdRaw = producto['id_producto'];
      final productId =
          productIdRaw is int
              ? productIdRaw
              : int.tryParse(productIdRaw.toString()) ?? 0;

      if (productId == 0) {
        print('⚠️ ID de producto inválido: $productIdRaw, saltando...');
        continue;
      }

      final cantidad = (producto['cantidad'] as num).toDouble();

      print('📦 Procesando producto ID: $productId, cantidad: $cantidad');

      // Verificar si el producto es elaborado
      final isElaborated = await _isProductElaborated(productId);

      if (isElaborated) {
        print('🔄 Producto $productId es elaborado, descomponiendo...');
        await _decomposeRecursively(
          productId,
          cantidad,
          consolidatedIngredients,
        );
      } else {
        print('✅ Producto $productId es simple, agregando directamente');
        _addToConsolidatedWithUnit(
          consolidatedIngredients,
          productId,
          cantidad,
          'und',
          'Producto $productId',
          '',
        );
      }
    }

    // Convertir el mapa consolidado a lista de productos
    final List<Map<String, dynamic>> productosFinales = [];

    for (final entry in consolidatedIngredients.entries) {
      final productId = entry.key;
      final ingredientData = entry.value;

      // Obtener información del producto para mantener estructura consistente
      final productInfo =
          await _supabase
              .from('app_dat_producto')
              .select('denominacion, sku')
              .eq('id', productId)
              .single();

      productosFinales.add({
        'id_producto': productId,
        'cantidad': ingredientData['cantidad'],
        'unidad_medida': ingredientData['unidad_medida'], // ✅ PRESERVAR UNIDAD
        'denominacion': ingredientData['denominacion'],
        'sku': ingredientData['sku'],
        'es_elaborado': false,
        'id_variante': null,
        'id_opcion_variante': null,
        'id_presentacion': null,
      });
    }

    print(
      '🎯 Descomposición completada: ${productosFinales.length} ingredientes únicos',
    );
    for (final producto in productosFinales) {
      print(
        '   - ${producto['denominacion']}: ${producto['cantidad']} ${producto['unidad_medida']}', // ✅ AGREGAR UNIDAD
      );
    }

    return productosFinales;
  }

  /// Get inventory summary by user using fn_inventario_resumen_por_usuario RPC
  /// Returns aggregated inventory data with product names, variants, and location/presentation counts
  static Future<List<InventorySummaryByUser>>
  getInventorySummaryByUser(
    int? idAlmacen,
    String? busqueda,
  ) async {
    try {
      final userData = await _prefsService.getUserData();
      final idTiendaRaw = userData['idTienda'];
      final idTienda =
          idTiendaRaw is int
              ? idTiendaRaw
              : (idTiendaRaw is String ? int.tryParse(idTiendaRaw) : null);

      if (idTienda == null) {
        throw Exception('No se encontró el ID de tienda en las preferencias');
      }

      print('🔍 InventoryService: Getting inventory summary by user...');

      final response = await _supabase.rpc(
        'fn_inventario_resumen_por_usuario_almacen',
        params: {
          'p_id_tienda': idTienda,
          'p_id_almacen': idAlmacen,
          'p_busqueda': busqueda,
          'p_mostrar_sin_stock': true,
          'p_limite': 9999,
          'p_pagina':   1,
        },
      );

      print('📦 Raw response type: ${response.runtimeType}');
      print('📦 Response length: ${response?.length ?? 0}');
      print('📦 Raw response data: $response');

      if (response == null) {
        print('❌ Response is null');
        return [];
      }

      if (response is! List) {
        print('❌ Response is not a List, got: ${response.runtimeType}');
        return [];
      }

      final List<dynamic> responseList = response as List<dynamic>;
      print('📋 Processing ${responseList.length} items from response');

      final List<InventorySummaryByUser> summaries = [];

      for (int i = 0; i < responseList.length; i++) {
        final item = responseList[i];
        /*  print('🔍 Processing item $i: $item');
        print('🔍 Item type: ${item.runtimeType}');*/

        if (item is Map<String, dynamic>) {
          /*    print('🔍 Item keys: ${item.keys.toList()}');
          print('🔍 Item values: ${item.values.toList()}');*/

         

          try {
            final summary = InventorySummaryByUser.fromJson(item);
            summaries.add(summary);
          } catch (e, stackTrace) {
            print('❌ Error creating InventorySummaryByUser from item $i: $e');
            print('❌ Stack trace: $stackTrace');
            print('❌ Failed item data: $item');
          }
        } else {
          print('❌ Item $i is not a Map, got: ${item.runtimeType}');
        }
      }

      print('✅ Successfully processed ${summaries.length} inventory summaries');
      for (int i = 0; i < summaries.length; i++) {
        final summary = summaries[i];
        print(
          '📋 Summary $i: ${summary.productoNombre} (ID: ${summary.idProducto}) - ${summary.cantidadTotalEnAlmacen} units, ${summary.zonasDiferentes} zones, ${summary.presentacionesDiferentes} presentations',
        );
      }

      return summaries;
    } catch (e, stackTrace) {
      print('❌ Error in getInventorySummaryByUser: $e');
      print('❌ Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Insert inventory adjustment using fn_insertar_ajuste_inventario RPC
  static Future<Map<String, dynamic>> insertInventoryAdjustment({
    required int idProducto,
    required int idUbicacion,
    required int? idPresentacion, // Make nullable to handle "Sin presentación"
    required double cantidadAnterior,
    required double cantidadNueva,
    required String motivo,
    required String observaciones,
    required String uuid,
    required int idTipoOperacion,
  }) async {
    try {
      /*print('🔍 Insertando ajuste de inventario...');
      print('📦 Parámetros:');
      print('   - ID Producto: $idProducto');
      print('   - ID Ubicación: $idUbicacion');
      print('   - ID Presentación: $idPresentacion');
      print('   - Cantidad Anterior: $cantidadAnterior');
      print('   - Cantidad Nueva: $cantidadNueva');
      print('   - Motivo: $motivo');
      print('   - Observaciones: $observaciones');
      print('   - UUID Usuario: $uuid');
      print('   - ID Tipo Operación: $idTipoOperacion');*/

      final response = await _supabase.rpc(
        'fn_insertar_ajuste_inventario',
        params: {
          'p_id_producto': idProducto,
          'p_id_ubicacion': idUbicacion,
          'p_id_presentacion': idPresentacion,
          'p_cantidad_anterior': cantidadAnterior,
          'p_cantidad_nueva': cantidadNueva,
          'p_motivo': motivo,
          'p_observaciones': observaciones,
          'p_uuid_usuario': uuid,
          'p_id_tipo_operacion': idTipoOperacion,
        },
      );

      print('📦 Respuesta RPC: $response');

      if (response == null) {
        throw Exception('Respuesta nula de la función RPC');
      }

      final result = response as Map<String, dynamic>;

      if (result['status'] == 'success') {
        print('✅ Ajuste de inventario registrado exitosamente');
        print('📊 ID Operación: ${result['id_operacion']}');
      } else {
        print('❌ Error en ajuste: ${result['message']}');
      }

      return result;
    } catch (e, stackTrace) {
      print('❌ Error en insertInventoryAdjustment: $e');
      print('📍 StackTrace: $stackTrace');
      return {
        'status': 'error',
        'message': 'Error al insertar ajuste de inventario: $e',
      };
    }
  }

  /// Obtiene inventario simple para exportación
  static Future<List<Map<String, dynamic>>> getInventarioSimple({
    int? idAlmacen,
    int? idTienda,
    DateTime? fechaHasta,
  }) async {
    try {
      print('🔍 Calling fn_listar_inventario_simple with params:');
      print('  - idAlmacen: $idAlmacen');
      print('  - idTienda: $idTienda');
      print('  - fechaHasta: $fechaHasta');

      final response = await _supabase.rpc(
        'fn_listar_inventario_simple',
        params: {
          'p_id_almacen': idAlmacen,
          'p_id_tienda': idTienda,
          'p_fecha_hasta': fechaHasta?.toIso8601String(),
        },
      );

      print('📦 Response received: ${response?.length ?? 0} items');

      if (response == null) {
        print('❌ Response is null');
        return [];
      }

      if (response is! List) {
        print('❌ Response is not a List, got: ${response.runtimeType}');
        return [];
      }

      final List<Map<String, dynamic>> inventoryList = [];
      for (final item in response) {
        if (item is Map<String, dynamic>) {
          inventoryList.add(item);
        }
      }

      print('✅ Processed ${inventoryList.length} inventory items');
      return inventoryList;
    } catch (e) {
      print('❌ Error in getInventarioSimple: $e');
      rethrow;
    }
  }

  static String _safeSubstring(String text, int start, int end) {
    if (text.isEmpty) {
      return '';
    }

    if (start > text.length) {
      return '';
    }

    if (end > text.length) {
      end = text.length;
    }

    return text.substring(start, end);
  }

  String _truncateString(String text, int maxLength) {
    if (text.length <= maxLength) {
      return text;
    }

    // Find a good place to cut (avoid cutting in the middle of a word)
    int end = maxLength;
    int start = 0;

    // Try to cut at a space or punctuation
    for (int i = maxLength - 1; i >= maxLength - 10 && i > 0; i--) {
      if (text[i] == ' ' || text[i] == ',' || text[i] == '.') {
        end = i;
        break;
      }
    }

    return text.substring(start, end);
  }

  // ==========================================
  // EXTRACCIÓN DE PRODUCTOS ELABORADOS
  // ==========================================

  /// Procesa la extracción de productos elaborados con descomposición automática
  Future<Map<String, dynamic>> processElaboratedProductsExtraction({
    required List<Map<String, dynamic>> productos,
    required String observaciones,
    required String autorizadoPor,
    required int idMotivoOperacion,
    required String uuid,
    required int idUbicacion, // Add the missing parameter
  }) async {
    try {
      print('🔄 Iniciando procesamiento de productos elaborados...');
      print('📍 Zona de extracción: $idUbicacion');

      // Paso 1: Descomponer productos elaborados en ingredientes
      final productosDescompuestos =
          await InventoryService.decomposeElaboratedProducts(productos);

      print('📦 Productos originales: ${productos.length}');
      print('🧪 Ingredientes finales: ${productosDescompuestos.length}');

      // Paso 2: Asociar ingredientes con la ubicación especificada
      final productosConUbicacion =
          productosDescompuestos.map((producto) {
            return {
              ...producto,
              'id_ubicacion':
                  idUbicacion, // Asociar cada ingrediente con la zona
            };
          }).toList();

      // Paso 3: Aplicar conversiones de presentación a ingredientes finales
      final checkResult = await checkIngredientsInventoryInZone(
        ingredients: productosDescompuestos,
        zoneId: idUbicacion.toString(),
      );

      final availableIngredientsRaw =
          checkResult['available_ingredients'] as List;
      final availableIngredients =
          availableIngredientsRaw
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();

      print(
        '🔍 DEBUG: availableIngredients.length = ${availableIngredients.length}',
      );
      print('🔍 DEBUG: checkResult success = ${checkResult['success']}');

      // Verificar ingredientes no disponibles
      final unavailableIngredientsRaw =
          checkResult['unavailable_ingredients'] as List? ?? [];
      print(
        '🔍 DEBUG: unavailableIngredients.length = ${unavailableIngredientsRaw.length}',
      );

      if (unavailableIngredientsRaw.isNotEmpty) {
        print(
          '⚠️ ADVERTENCIA: Hay ${unavailableIngredientsRaw.length} ingredientes no disponibles',
        );
        for (final unavailable in unavailableIngredientsRaw) {
          final item = Map<String, dynamic>.from(unavailable as Map);
          print(
            '   - ${item['denominacion']}: requiere ${item['cantidad_necesaria_presentacion']} pero solo hay ${item['stock_disponible']}',
          );
        }
      }

      if (availableIngredients.isEmpty) {
        throw Exception('No hay ingredientes disponibles para extraer');
      }

      // Crear productos para extracción con formato correcto
      final productosParaExtraccion =
          availableIngredients
              .map(
                (ingredient) => {
                  'id_producto': ingredient['id_producto'],
                  'cantidad':
                      (ingredient['cantidad_necesaria_presentacion'] as num)
                          .toDouble(),
                  'id_presentacion': ingredient['id_presentacion'],
                  'id_ubicacion': idUbicacion,
                  'id_variante': ingredient['id_variante'],
                  'id_opcion_variante': ingredient['id_opcion_variante'],
                  'precio_unitario':
                      0.0, // Precio por defecto para extracciones
                },
              )
              .toList();

      print(
        '🔍 DEBUG: productosParaExtraccion.length = ${productosParaExtraccion.length}',
      );
      print('🔍 DEBUG: productosParaExtraccion = $productosParaExtraccion');

      // Paso 4: Obtener datos del usuario
      final userData = await _prefsService.getUserData();
      final idTiendaRaw = userData['idTienda'];
      final idTienda =
          idTiendaRaw is int
              ? idTiendaRaw
              : (idTiendaRaw is String ? int.tryParse(idTiendaRaw) : null);

      if (idTienda == null) {
        throw Exception('No se encontró información de la tienda');
      }

      // Paso 5: Ejecutar extracción completa
      final result = await insertCompleteExtraction(
        autorizadoPor: autorizadoPor,
        estadoInicial: 1,
        idMotivoOperacion: idMotivoOperacion,
        idTienda: idTienda,
        observaciones: 'Extracción de productos elaborados: $observaciones',
        productos:
            productosParaExtraccion, // ✅ CORREGIDO: usar productosParaExtraccion
        uuid: uuid,
      );

      if (result['status'] == 'success') {
        return {
          'status': 'success',
          'message':
              'Extracción de productos elaborados completada exitosamente',
          'id_operacion': result['id_operacion'],
          'productos_procesados': productos.length,
          'ingredientes_extraidos': productosDescompuestos.length,
        };
      } else {
        throw Exception(result['message'] ?? 'Error en la extracción');
      }
    } catch (e) {
      print('❌ Error en processElaboratedProductsExtraction: $e');
      return {'status': 'error', 'message': 'Error al procesar extracción: $e'};
    }
  }

  /// Get store ID from user preferences with fallback
  static Future<int> _getStoreId() async {
    try {
      final storeId = await _prefsService.getIdTienda();
      return storeId ?? 1; // Default value if no store configured
    } catch (e) {
      print('❌ Error getting store ID: $e');
      return 1; // Default value
    }
  }

  /// Complete an operation by calling fn_contabilizar_operacion RPC
  static Future<Map<String, dynamic>> completeOperation({
    required int idOperacion,
    required String comentario,
    required String uuid,
  }) async {
    try {
      print('🔄 Completando operación $idOperacion...');
      print('📋 Parámetros:');
      print('   - p_id_operacion: $idOperacion');
      print('   - p_comentario: $comentario');
      print('   - p_uuid: $uuid');

      final response = await _supabase.rpc(
        'fn_contabilizar_operacion',
        params: {
          'p_id_operacion': idOperacion,
          'p_comentario': comentario,
          'p_uuid': uuid,
        },
      );

      print('✅ Operación $idOperacion completada exitosamente');
      print('📦 Respuesta RPC: $response');
      return {
        'success': true,
        'message': 'Operación completada exitosamente',
        'data': response,
      };
    } catch (e) {
      print('❌ ERROR DETALLADO completando operación $idOperacion:');
      print('   - Error: $e');
      print('   - Tipo de error: ${e.runtimeType}');
      print('   - Stack trace: ${StackTrace.current}');

      // Si es un error de PostgreSQL, mostrar más detalles
      if (e.toString().contains('PostgrestException')) {
        print('   - Es un error de PostgreSQL');
      }

      return {
        'success': false,
        'message': 'Error completando operación: $e',
        'error': e.toString(),
        'error_type': e.runtimeType.toString(),
      };
    }
  }

  /// Cancel an operation by inserting a record in app_dat_estado_operacion with estado = 3
  static Future<Map<String, dynamic>> cancelOperation({
    required int idOperacion,
    required String comentario,
    required String uuid,
  }) async {
    try {
      print('🚫 Cancelando operación $idOperacion...');
      print('📋 Parámetros:');
      print('   - id_operacion: $idOperacion');
      print('   - estado: 3 (cancelado)');
      print('   - comentario: $comentario');
      print('   - uuid: $uuid');

      // Insert record in app_dat_estado_operacion with estado = 3 (cancelado)
      final response = await _supabase
          .from('app_dat_estado_operacion')
          .insert({
            'id_operacion': idOperacion,
            'estado': 3, // 3 = Cancelado
            'uuid': uuid,
            'comentario': comentario.isEmpty ? 'Operación cancelada desde la app' : comentario,
          })
          .select()
          .single();

      print('✅ Operación $idOperacion cancelada exitosamente');
      print('📦 Respuesta insert: $response');
      
      return {
        'status': 'success',
        'mensaje': 'Operación cancelada exitosamente',
        'data': response,
      };
    } catch (e) {
      print('❌ ERROR DETALLADO cancelando operación $idOperacion:');
      print('   - Error: $e');
      print('   - Tipo de error: ${e.runtimeType}');
      print('   - Stack trace: ${StackTrace.current}');

      // Si es un error de PostgreSQL, mostrar más detalles
      if (e.toString().contains('PostgrestException')) {
        print('   - Es un error de PostgreSQL');
      }

      return {
        'status': 'error',
        'message': 'Error cancelando operación: $e',
        'error': e.toString(),
        'error_type': e.runtimeType.toString(),
      };
    }
  }

  /// Convierte cantidad de ingrediente a unidades de inventario
  static Future<double> _convertirCantidadAInventario({
    required double cantidadNecesaria,
    required int productId,
    int? unidadIngrediente,
    int? unidadInventario,
  }) async {
    try {
      if (unidadIngrediente == null ||
          unidadInventario == null ||
          unidadIngrediente == unidadInventario) {
        return cantidadNecesaria;
      }

      final cantidadConvertida = await RestaurantService.convertirUnidades(
        cantidad: cantidadNecesaria,
        unidadOrigen: unidadIngrediente,
        unidadDestino: unidadInventario,
        idProducto: productId,
      );

      return cantidadConvertida;
    } catch (e) {
      print('❌ Error conversión: $e');
      return cantidadNecesaria;
    }
  }

  /// Mapea nombres de unidades en string a sus IDs correspondientes usando la base de datos
  static Future<int?> _mapUnidadStringToId(String unidadString) async {
    try {
      print('🔍 Buscando unidad: "$unidadString"');

      // Normalizar el string (lowercase y trim)
      final unidadNormalizada = unidadString.toLowerCase().trim();
      print('🔍 Unidad normalizada: "$unidadNormalizada"');

      // Obtener todas las unidades de medida de la base de datos
      final unidadesMedida = await RestaurantService.getUnidadesMedida();
      print('🔍 Total unidades en BD: ${unidadesMedida.length}');

      // Mostrar todas las unidades disponibles para debugging
      for (final unidad in unidadesMedida) {
        print(
          '📋 Unidad BD: ID=${unidad.id}, denominacion="${unidad.denominacion}", abreviatura="${unidad.abreviatura}"',
        );
      }

      // Buscar por denominación exacta
      for (final unidad in unidadesMedida) {
        if (unidad.denominacion.toLowerCase() == unidadNormalizada) {
          print(
            '✅ Unidad encontrada por denominación: "${unidad.denominacion}" → ID ${unidad.id}',
          );
          return unidad.id;
        }
      }

      // Buscar por abreviatura exacta
      for (final unidad in unidadesMedida) {
        if (unidad.abreviatura.toLowerCase() == unidadNormalizada) {
          print(
            '✅ Unidad encontrada por abreviatura: "${unidad.abreviatura}" → ID ${unidad.id}',
          );
          return unidad.id;
        }
      }

      // Buscar por coincidencias parciales en denominación
      for (final unidad in unidadesMedida) {
        if (unidad.denominacion.toLowerCase().contains(unidadNormalizada) ||
            unidadNormalizada.contains(unidad.denominacion.toLowerCase())) {
          print(
            '✅ Unidad encontrada por coincidencia parcial: "${unidad.denominacion}" → ID ${unidad.id}',
          );
          return unidad.id;
        }
      }

      print('⚠️ Unidad no encontrada en BD: "$unidadString" - usando fallback');
      return _mapUnidadStringToIdFallback(unidadString);
    } catch (e) {
      print('❌ Error buscando unidad en BD: $e - usando fallback');
      return _mapUnidadStringToIdFallback(unidadString);
    }
  }

  /// Mapeo básico como fallback si falla la consulta a la base de datos
  static int? _mapUnidadStringToIdFallback(String unidadString) {
    print('🔄 Usando mapeo fallback para: "$unidadString"');

    // Normalizar el string (lowercase y trim)
    final unidadNormalizada = unidadString.toLowerCase().trim();

    // Mapeo de strings comunes a IDs de unidades de medida (valores típicos)
    switch (unidadNormalizada) {
      case 'gramos':
      case 'gramo':
      case 'g':
      case 'gr':
        print('✅ Fallback: "$unidadString" → ID 1 (gramos)');
        return 2; // ID típico para gramos

      case 'kilogramos':
      case 'kilogramo':
      case 'kg':
      case 'kilo':
      case 'kilos':
        print('✅ Fallback: "$unidadString" → ID 2 (kilogramos)');
        return 1; // ID típico para kilogramos

      case 'mililitros':
      case 'mililitro':
      case 'ml':
        print('✅ Fallback: "$unidadString" → ID 3 (mililitros)');
        return 3; // ID típico para mililitros

      case 'litros':
      case 'litro':
      case 'l':
      case 'lt':
        print('✅ Fallback: "$unidadString" → ID 4 (litros)');
        return 4; // ID típico para litros

      case 'unidades':
      case 'unidad':
      case 'u':
      case 'und':
      case 'un':
      case 'piezas':
      case 'pieza':
      case 'pza':
        print('✅ Fallback: "$unidadString" → ID 5 (unidades)');
        return 5; // ID típico para unidades

      default:
        print(
          '⚠️ Unidad desconocida en fallback: "$unidadString" - retornando ID 5 (unidades por defecto)',
        );
        return 5; // Usar unidades como fallback por defecto
    }
  }

  /// Consolida ingredientes preservando información de unidad de medida
  static void _addToConsolidatedWithUnit(
    Map<int, Map<String, dynamic>> consolidated,
    int productId,
    double quantity,
    String unit,
    String denominacion,
    String sku,
  ) {
    if (consolidated.containsKey(productId)) {
      // Sumar cantidad si ya existe
      consolidated[productId]!['cantidad'] += quantity;
    } else {
      // Crear nuevo registro con toda la información
      consolidated[productId] = {
        'cantidad': quantity,
        'unidad_medida': unit,
        'denominacion': denominacion,
        'sku': sku,
      };
    }
  }
}
