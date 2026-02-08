import 'package:supabase_flutter/supabase_flutter.dart';

class ProductMovementsService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Obtiene movimientos de un producto con paginado usando RPC optimizado
  /// Una sola consulta que retorna recepciones, extracciones y controles
  /// con toda la información relacionada (usuario, ubicación, proveedor, etc.)
  static Future<Map<String, dynamic>> getProductMovements({
    required int productId,
    DateTime? dateFrom,
    DateTime? dateTo,
    int? operationTypeId,
    int? warehouseId,
    int offset = 0,
    int limit = 20,
  }) async {
    try {
      print('🔍 Obteniendo movimientos del producto $productId (offset: $offset, limit: $limit)');
      print('📅 Filtros: desde=$dateFrom, hasta=$dateTo, tipoOp=$operationTypeId, almacén=$warehouseId');

      // Intentar usar el RPC optimizado primero
      try {
        final response = await _supabase.rpc(
          'get_product_movements_optimized',

          params: {
            'p_id_producto': productId,
            'p_fecha_desde': dateFrom?.toString().split(' ')[0],
            'p_fecha_hasta': dateTo?.toString().split(' ')[0],
            'p_tipo_operacion_id': operationTypeId,
            'p_id_almacen': warehouseId,
            'p_offset': offset,
            'p_limit': limit,
          },
        );

        if (response == null) {
          print('⚠️ RPC retornó null, usando fallback');
          return await _getMovementsFallback(
            productId,
            dateFrom,
            dateTo,
            operationTypeId,
            warehouseId,
            offset: offset,
            limit: limit,
          );
        }

        final movements = List<Map<String, dynamic>>.from(response);
        final totalCount = movements.isNotEmpty ? (movements[0]['total_count'] as int?) ?? 0 : 0;
        
        print('✅ Movimientos obtenidos desde RPC: ${movements.length} de $totalCount total');
        return {
          'movements': movements,
          'total_count': totalCount,
          'offset': offset,
          'limit': limit,
        };
      } catch (rpcError) {
        print('⚠️ Error al llamar RPC: $rpcError');
        print('🔄 Usando fallback a consultas directas');
        return await _getMovementsFallback(
          productId,
          dateFrom,
          dateTo,
          operationTypeId,
          warehouseId,
          offset: offset,
          limit: limit,
        );
      }
    } catch (e) {
      print('❌ Error al obtener movimientos: $e');
      rethrow;
    }
  }

  /// Fallback: Obtiene movimientos desde app_dat_inventario_productos si el RPC no está disponible
  static Future<Map<String, dynamic>> _getMovementsFallback(
    int productId,
    DateTime? dateFrom,
    DateTime? dateTo,
    int? operationTypeId,
    int? warehouseId, {
    int offset = 0,
    int limit = 20,
  }) async {
    try {
      print('📊 Usando fallback: consultas desde app_dat_inventario_productos');
      print('📅 Filtros: desde=$dateFrom, hasta=$dateTo, tipoOp=$operationTypeId, almacén=$warehouseId');

      // Obtener registros de inventario para el producto
      var inventoryQuery = _supabase
          .from('app_dat_inventario_productos')
          .select('''
            id,
            id_producto,
            id_recepcion,
            id_extraccion,
            id_control,
            cantidad_inicial,
            cantidad_final,
            created_at,
            id_ubicacion,
            id_proveedor
          ''')
          .eq('id_producto', productId);

      // Filtrar por almacén si se especifica
      if (warehouseId != null) {
        // Obtener zonas del almacén especificado
        final zonasQuery = await _supabase
            .from('app_dat_layout_almacen')
            .select('id')
            .eq('id_almacen', warehouseId);
        
        final zonaIds = zonasQuery.map((z) => z['id'] as int).toList();
        
        if (zonaIds.isNotEmpty) {
          inventoryQuery = inventoryQuery.filter('id_ubicacion', 'in', zonaIds);
        } else {
          // Si el almacén no tiene zonas, no retornar resultados
          inventoryQuery = inventoryQuery.eq('id', -1);
        }
      }

      if (dateFrom != null) {
        inventoryQuery = inventoryQuery.gte('created_at', dateFrom.toIso8601String());
      }
      if (dateTo != null) {
        inventoryQuery = inventoryQuery.lte('created_at', dateTo.toIso8601String());
      }

      final inventoryRecords = await inventoryQuery;

      if (inventoryRecords.isEmpty) {
        print('⚠️ No hay registros de inventario para el producto');
        return {
          'movements': [],
          'total_count': 0,
          'offset': offset,
          'limit': limit,
        };
      }

      print('📦 Registros de inventario encontrados: ${inventoryRecords.length}');

      // Obtener todos los tipos de operación disponibles
      final tiposOperacion = await _supabase
          .from('app_nom_tipo_operacion')
          .select('id, denominacion, descripcion');

      final tiposMap = {
        for (var tipo in tiposOperacion)
          tipo['id'] as int: tipo['denominacion'] as String
      };

      List<Map<String, dynamic>> movements = [];

      // Procesar cada registro de inventario
      for (var record in inventoryRecords) {
        // Obtener detalles de recepción si existe
        if (record['id_recepcion'] != null) {
          final details = await _getRecepcionDetailsFallback(
            record['id_recepcion'] as int,
            tiposMap,
            operationTypeId,
            record,
          );
          if (details != null) {
            movements.add(details);
          }
        }

        // Obtener detalles de extracción si existe
        if (record['id_extraccion'] != null) {
          final details = await _getExtraccionDetailsFallback(
            record['id_extraccion'] as int,
            tiposMap,
            operationTypeId,
            record,
          );
          if (details != null) {
            movements.add(details);
          }
        }

        // Obtener detalles de control si existe
        if (record['id_control'] != null) {
          final details = await _getControlDetailsFallback(
            record['id_control'] as int,
            tiposMap,
            operationTypeId,
            record,
          );
          if (details != null) {
            movements.add(details);
          }
        }
      }

      // Ordenar por fecha descendente
      movements.sort((a, b) {
        final dateA = DateTime.tryParse(a['fecha'] as String? ?? '');
        final dateB = DateTime.tryParse(b['fecha'] as String? ?? '');
        if (dateA == null || dateB == null) return 0;
        return dateB.compareTo(dateA);
      });

      final totalCount = movements.length;
      // Aplicar paginado
      final paginatedMovements = movements.skip(offset).take(limit).toList();

      print('✅ Movimientos obtenidos desde fallback: ${paginatedMovements.length} de $totalCount total');
      return {
        'movements': paginatedMovements,
        'total_count': totalCount,
        'offset': offset,
        'limit': limit,
      };
    } catch (e) {
      print('❌ Error en fallback: $e');
      rethrow;
    }
  }

  /// Obtiene detalles de una recepción (fallback)
  static Future<Map<String, dynamic>?> _getRecepcionDetailsFallback(
    int recepcionId,
    Map<int, String> tiposMap,
    int? operationTypeId,
    Map<String, dynamic> inventoryRecord,
  ) async {
    try {
      // Obtener detalles de la recepción
      final recepcion = await _supabase
          .from('app_dat_recepcion_productos')
          .select('''
            id,
            id_operacion,
            cantidad,
            precio_unitario,
            costo_real,
            created_at,
            id_proveedor,
            id_ubicacion
          ''')
          .eq('id', recepcionId)
          .maybeSingle();

      if (recepcion == null) return null;

      // Obtener detalles de la operación
      final operacion = await _supabase
          .from('app_dat_operaciones')
          .select('''
            id,
            id_tipo_operacion,
            uuid,
            observaciones,
            created_at
          ''')
          .eq('id', recepcion['id_operacion'] as int)
          .maybeSingle();

      if (operacion == null) return null;

      final tipoOperacionId = operacion['id_tipo_operacion'] as int;
      
      // Filtrar por tipo de operación si se especifica
      if (operationTypeId != null && tipoOperacionId != operationTypeId) {
        return null;
      }

      // Obtener detalles de la recepción (quién entregó y recibió)
      final operacionRecepcion = await _supabase
          .from('app_dat_operacion_recepcion')
          .select('entregado_por, recibido_por')
          .eq('id_operacion', recepcion['id_operacion'] as int)
          .maybeSingle();

      // Obtener nombre de la ubicación y almacén
      String? ubicacionNombre;
      String? almacenNombre;
      String? zonaNombre;
      if (recepcion['id_ubicacion'] != null) {
        final ubicacion = await _supabase
            .from('app_dat_layout_almacen')
            .select('''
              denominacion,
              id_almacen,
              app_dat_almacen!inner(denominacion)
            ''')
            .eq('id', recepcion['id_ubicacion'] as int)
            .maybeSingle();
        
        if (ubicacion != null) {
          ubicacionNombre = ubicacion['denominacion'] as String?;
          almacenNombre = (ubicacion['app_dat_almacen'] as Map<String, dynamic>?)?['denominacion'] as String?;
          zonaNombre = ubicacionNombre; // Para compatibilidad con vista existente
        }
      }

      // Obtener nombre del proveedor
      String? proveedorNombre;
      if (recepcion['id_proveedor'] != null) {
        final proveedor = await _supabase
            .from('app_dat_proveedor')
            .select('nombre')
            .eq('id', recepcion['id_proveedor'] as int)
            .maybeSingle();
        proveedorNombre = proveedor?['nombre'] as String?;
      }

      return {
        'id': recepcion['id'],
        'id_operacion': recepcion['id_operacion'],
        'tipo_movimiento': 'Recepción',
        'tipo_operacion': tiposMap[tipoOperacionId] ?? 'Desconocido',
        'tipo_operacion_id': tipoOperacionId,
        'cantidad': recepcion['cantidad'],
        'precio_unitario': recepcion['precio_unitario'],
        'costo_real': recepcion['costo_real'],
        'fecha': recepcion['created_at'],
        'entregado_por': operacionRecepcion?['entregado_por'] as String?,
        'recibido_por': operacionRecepcion?['recibido_por'] as String?,
        'ubicacion': ubicacionNombre ?? 'Desconocida',
        'almacen': almacenNombre ?? 'Desconocido',
        'zona': zonaNombre ?? 'Desconocida',
        'proveedor': proveedorNombre,
        'observaciones': operacion['observaciones'],
        'cantidad_inicial': inventoryRecord['cantidad_inicial'],
        'cantidad_final': inventoryRecord['cantidad_final'],
      };
    } catch (e) {
      print('❌ Error al obtener detalles de recepción: $e');
      return null;
    }
  }

  /// Obtiene detalles de una extracción (fallback)
  static Future<Map<String, dynamic>?> _getExtraccionDetailsFallback(
    int extraccionId,
    Map<int, String> tiposMap,
    int? operationTypeId,
    Map<String, dynamic> inventoryRecord,
  ) async {
    try {
      // Obtener detalles de la extracción
      final extraccion = await _supabase
          .from('app_dat_extraccion_productos')
          .select('''
            id,
            id_operacion,
            cantidad,
            precio_unitario,
            importe_real,
            created_at,
            id_ubicacion
          ''')
          .eq('id', extraccionId)
          .maybeSingle();

      if (extraccion == null) return null;

      // Obtener detalles de la operación
      final operacion = await _supabase
          .from('app_dat_operaciones')
          .select('''
            id,
            id_tipo_operacion,
            uuid,
            observaciones,
            created_at
          ''')
          .eq('id', extraccion['id_operacion'] as int)
          .maybeSingle();

      if (operacion == null) return null;

      final tipoOperacionId = operacion['id_tipo_operacion'] as int;
      
      // Filtrar por tipo de operación si se especifica
      if (operationTypeId != null && tipoOperacionId != operationTypeId) {
        return null;
      }

      // Obtener detalles de la extracción (observaciones y autorizado por)
      final operacionExtraccion = await _supabase
          .from('app_dat_operacion_extraccion')
          .select('observaciones, autorizado_por')
          .eq('id_operacion', extraccion['id_operacion'] as int)
          .maybeSingle();

      // Obtener nombre de la ubicación y almacén
      String? ubicacionNombre;
      String? almacenNombre;
      String? zonaNombre;
      if (extraccion['id_ubicacion'] != null) {
        final ubicacion = await _supabase
            .from('app_dat_layout_almacen')
            .select('''
              denominacion,
              id_almacen,
              app_dat_almacen!inner(denominacion)
            ''')
            .eq('id', extraccion['id_ubicacion'] as int)
            .maybeSingle();
        
        if (ubicacion != null) {
          ubicacionNombre = ubicacion['denominacion'] as String?;
          almacenNombre = (ubicacion['app_dat_almacen'] as Map<String, dynamic>?)?['denominacion'] as String?;
          zonaNombre = ubicacionNombre; // Para compatibilidad con vista existente
        }
      }

      return {
        'id': extraccion['id'],
        'id_operacion': extraccion['id_operacion'],
        'tipo_movimiento': 'Extracción',
        'tipo_operacion': tiposMap[tipoOperacionId] ?? 'Desconocido',
        'tipo_operacion_id': tipoOperacionId,
        'cantidad': extraccion['cantidad'],
        'precio_unitario': extraccion['precio_unitario'],
        'importe_real': extraccion['importe_real'],
        'fecha': extraccion['created_at'],
        'ubicacion': ubicacionNombre ?? 'Desconocida',
        'almacen': almacenNombre ?? 'Desconocido',
        'zona': zonaNombre ?? 'Desconocida',
        'observaciones': operacionExtraccion?['observaciones'] as String?,
        'autorizado_por': operacionExtraccion?['autorizado_por'] as String?,
        'cantidad_inicial': inventoryRecord['cantidad_inicial'],
        'cantidad_final': inventoryRecord['cantidad_final'],
      };
    } catch (e) {
      print('❌ Error al obtener detalles de extracción: $e');
      return null;
    }
  }

  /// Obtiene detalles de un control de productos (fallback)
  static Future<Map<String, dynamic>?> _getControlDetailsFallback(
    int controlId,
    Map<int, String> tiposMap,
    int? operationTypeId,
    Map<String, dynamic> inventoryRecord,
  ) async {
    try {
      // Obtener detalles del control
      final control = await _supabase
          .from('app_dat_control_productos')
          .select('''
            id,
            id_operacion,
            cantidad,
            created_at,
            id_ubicacion
          ''')
          .eq('id', controlId)
          .maybeSingle();

      if (control == null) return null;

      // Obtener detalles de la operación
      final operacion = await _supabase
          .from('app_dat_operaciones')
          .select('''
            id,
            id_tipo_operacion,
            uuid,
            observaciones,
            created_at
          ''')
          .eq('id', control['id_operacion'] as int)
          .maybeSingle();

      if (operacion == null) return null;

      final tipoOperacionId = operacion['id_tipo_operacion'] as int;
      
      // Filtrar por tipo de operación si se especifica
      if (operationTypeId != null && tipoOperacionId != operationTypeId) {
        return null;
      }

      // Obtener nombre de la ubicación y almacén
      String? ubicacionNombre;
      String? almacenNombre;
      String? zonaNombre;
      if (control['id_ubicacion'] != null) {
        final ubicacion = await _supabase
            .from('app_dat_layout_almacen')
            .select('''
              denominacion,
              id_almacen,
              app_dat_almacen!inner(denominacion)
            ''')
            .eq('id', control['id_ubicacion'] as int)
            .maybeSingle();
        
        if (ubicacion != null) {
          ubicacionNombre = ubicacion['denominacion'] as String?;
          almacenNombre = (ubicacion['app_dat_almacen'] as Map<String, dynamic>?)?['denominacion'] as String?;
          zonaNombre = ubicacionNombre; // Para compatibilidad con vista existente
        }
      }

      return {
        'id': control['id'],
        'id_operacion': control['id_operacion'],
        'tipo_movimiento': 'Control',
        'tipo_operacion': tiposMap[tipoOperacionId] ?? 'Desconocido',
        'tipo_operacion_id': tipoOperacionId,
        'cantidad': control['cantidad'],
        'fecha': control['created_at'],
        'ubicacion': ubicacionNombre ?? 'Desconocida',
        'almacen': almacenNombre ?? 'Desconocido',
        'zona': zonaNombre ?? 'Desconocida',
        'observaciones': operacion['observaciones'],
        'cantidad_inicial': inventoryRecord['cantidad_inicial'],
        'cantidad_final': inventoryRecord['cantidad_final'],
      };
    } catch (e) {
      print('❌ Error al obtener detalles de control: $e');
      return null;
    }
  }

  /// Obtiene todos los tipos de operación disponibles
  static Future<List<Map<String, dynamic>>> getOperationTypes() async {
    try {
      final response = await _supabase
          .from('app_nom_tipo_operacion')
          .select('id, denominacion, descripcion')
          .order('denominacion');
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error al obtener tipos de operación: $e');
      return [];
    }
  }
}
