import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/store.dart';
import 'consignacion_duplicacion_service.dart';

class ConsignacionService {
  static final _supabase = Supabase.instance.client;
  
  // Caché para productos de consignación
  static final Map<int, Map<String, dynamic>> _cacheProductos = {};
  static final Map<int, DateTime> _cacheTimestamps = {};
  static const Duration _cacheDuration = Duration(minutes: 5);

  /// Limpiar caché de productos para un contrato específico
  static void clearProductosCache(int idContrato) {
    _cacheProductos.remove(idContrato);
    _cacheProductos.remove(-idContrato); // También limpiar pendientes
    _cacheTimestamps.remove(idContrato);
    _cacheTimestamps.remove(-idContrato);
    debugPrint('🗑️ Caché limpiado para contrato: $idContrato');
  }

  /// Limpiar todo el caché
  static void clearAllCache() {
    _cacheProductos.clear();
    _cacheTimestamps.clear();
    debugPrint('🗑️ Todo el caché ha sido limpiado');
  }

  /// Obtener contratos activos de consignación para una tienda
  static Future<List<Map<String, dynamic>>> getActiveContratos(int idTienda) async {
    try {
      debugPrint('📋 Obteniendo contratos activos para tienda: $idTienda');

      // Obtener contratos donde la tienda es consignadora o consignataria
      final response = await _supabase
          .from('app_dat_contrato_consignacion')
          .select('*')
          .or('id_tienda_consignadora.eq.$idTienda,id_tienda_consignataria.eq.$idTienda')
          .eq('estado', 1)
          .order('created_at', ascending: false);

      debugPrint('✅ Contratos obtenidos: ${response.length}');

      // Enriquecer con datos de tiendas
      final List<Map<String, dynamic>> enrichedContratos = [];
      for (var contrato in response) {
        final idConsignadora = contrato['id_tienda_consignadora'];
        final idConsignataria = contrato['id_tienda_consignataria'];

        // Obtener datos de tiendas
        final tiendaConsignadora = await _supabase
            .from('app_dat_tienda')
            .select('id, denominacion, direccion')
            .eq('id', idConsignadora)
            .single();

        final tiendaConsignataria = await _supabase
            .from('app_dat_tienda')
            .select('id, denominacion, direccion')
            .eq('id', idConsignataria)
            .single();

        // Obtener datos del almacén destino si existe
        Map<String, dynamic>? almacenDestino;
        if (contrato['id_almacen_destino'] != null) {
          try {
            almacenDestino = await _supabase
                .from('app_dat_almacen')
                .select('id, denominacion, direccion')
                .eq('id', contrato['id_almacen_destino'])
                .single();
            debugPrint('✅ Almacén destino obtenido: ${almacenDestino['denominacion']}');
          } catch (e) {
            debugPrint('⚠️ No se pudo obtener almacén destino: $e');
          }
        }

        enrichedContratos.add({
          ...contrato,
          'tienda_consignadora': tiendaConsignadora,
          'tienda_consignataria': tiendaConsignataria,
          if (almacenDestino != null) 'almacen_destino': almacenDestino,
        });
      }

      return enrichedContratos;
    } catch (e) {
      debugPrint('❌ Error obteniendo contratos: $e');
      return [];
    }
  }

  /// Obtener contratos con filtrado, búsqueda y paginación
  static Future<Map<String, dynamic>> getContratosFiltrados({
    required int idTienda,
    int? estadoConfirmacion, // null = todos, 0 = pendientes, 1 = confirmados, 2 = cancelados
    String? searchTerm, // búsqueda por nombre de tienda
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      debugPrint('🔍 Buscando contratos: searchTerm=$searchTerm, estado=$estadoConfirmacion, offset=$offset, limit=$limit');

      // Paso 1: Obtener contratos base (sin enriquecer aún)
      var query = _supabase
          .from('app_dat_contrato_consignacion')
          .select('*')
          .or('id_tienda_consignadora.eq.$idTienda,id_tienda_consignataria.eq.$idTienda')
          .eq('estado', 1);

      // Aplicar filtro de estado de confirmación
      if (estadoConfirmacion != null) {
        query = query.eq('estado_confirmacion', estadoConfirmacion);
      }

      // Obtener total de registros (sin paginación)
      final allResponse = await query.order('created_at', ascending: false);
      final totalRegistros = allResponse.length;

      // Aplicar paginación
      final response = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      debugPrint('✅ Contratos base obtenidos: ${response.length} de $totalRegistros');

      // Paso 2: Enriquecer con datos de tiendas y filtrar por búsqueda
      final List<Map<String, dynamic>> enrichedContratos = [];
      
      for (var contrato in response) {
        final idConsignadora = contrato['id_tienda_consignadora'];
        final idConsignataria = contrato['id_tienda_consignataria'];

        // Obtener datos de tiendas
        final tiendaConsignadora = await _supabase
            .from('app_dat_tienda')
            .select('id, denominacion, direccion')
            .eq('id', idConsignadora)
            .single();

        final tiendaConsignataria = await _supabase
            .from('app_dat_tienda')
            .select('id, denominacion, direccion')
            .eq('id', idConsignataria)
            .single();

        // Obtener datos del almacén destino si existe
        Map<String, dynamic>? almacenDestino;
        if (contrato['id_almacen_destino'] != null) {
          try {
            almacenDestino = await _supabase
                .from('app_dat_almacen')
                .select('id, denominacion, direccion')
                .eq('id', contrato['id_almacen_destino'])
                .single();
          } catch (e) {
            debugPrint('⚠️ No se pudo obtener almacén destino: $e');
          }
        }

        final contratoEnriquecido = {
          ...contrato,
          'tienda_consignadora': tiendaConsignadora,
          'tienda_consignataria': tiendaConsignataria,
          if (almacenDestino != null) 'almacen_destino': almacenDestino,
        };

        // Paso 3: Filtrar por búsqueda (en memoria, después de enriquecer)
        if (searchTerm != null && searchTerm.isNotEmpty) {
          final searchLower = searchTerm.toLowerCase();
          final tiendaConsignadoraNombre = (tiendaConsignadora['denominacion'] as String?)?.toLowerCase() ?? '';
          final tiendaConsignatariaNombre = (tiendaConsignataria['denominacion'] as String?)?.toLowerCase() ?? '';
          
          // Si no coincide con ninguna tienda, saltar este contrato
          if (!tiendaConsignadoraNombre.contains(searchLower) && 
              !tiendaConsignatariaNombre.contains(searchLower)) {
            continue;
          }
        }

        enrichedContratos.add(contratoEnriquecido);
      }

      debugPrint('✅ Contratos enriquecidos: ${enrichedContratos.length}');

      return {
        'contratos': enrichedContratos,
        'total': totalRegistros,
        'offset': offset,
        'limit': limit,
        'hasMore': (offset + limit) < totalRegistros,
      };
    } catch (e) {
      debugPrint('❌ Error buscando contratos: $e');
      return {
        'contratos': [],
        'total': 0,
        'offset': offset,
        'limit': limit,
        'hasMore': false,
        'error': e.toString(),
      };
    }
  }

  /// Obtener productos en consignación de un contrato (CONFIRMADOS) - CON CACHÉ
  static Future<List<Map<String, dynamic>>> getProductosConsignacion(int idContrato) async {
    try {
      // Verificar caché
      if (_cacheProductos.containsKey(idContrato)) {
        final timestamp = _cacheTimestamps[idContrato];
        if (timestamp != null && DateTime.now().difference(timestamp) < _cacheDuration) {
          debugPrint('📦 Productos obtenidos del CACHÉ para contrato: $idContrato');
          return List<Map<String, dynamic>>.from(
            (_cacheProductos[idContrato]!['productos'] as List)
                .map((item) => Map<String, dynamic>.from(item as Map))
          );
        }
      }

      debugPrint('📦 Obteniendo productos en consignación para contrato: $idContrato (OPTIMIZADO)');

      // Intentar usar RPC
      try {
        final response = await _supabase.rpc(
          'get_productos_consignacion_optimizado',
          params: {'p_id_contrato': idContrato},
        ) as List;

        debugPrint('✅ Productos obtenidos (RPC): ${response.length}');

        final productos = response
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();

        // Guardar en caché
        _cacheProductos[idContrato] = {'productos': productos};
        _cacheTimestamps[idContrato] = DateTime.now();

        return productos;
      } catch (rpcError) {
        // Silenciar error de tipos si el RPC falla por desajuste bigint/integer en DB
        // Pero loguear si es otro tipo de error
        final errorStr = rpcError.toString();
        if (!errorStr.contains('42804')) { 
          debugPrint('⚠️ RPC error (no crítico, usando fallback): $rpcError');
        } else {
          debugPrint('ℹ️ Usando consulta optimizada (fallback automático por desajuste de tipos en RPC)');
        }

        // Fallback a query manual
        final response = await _supabase
            .from('app_dat_producto_consignacion')
            .select('*, producto:id_producto(id, denominacion, sku, descripcion)')
            .eq('id_contrato', idContrato)
            .eq('estado', 1)
            .order('created_at', ascending: false);

        debugPrint('✅ Productos obtenidos (fallback): ${response.length}');

        final productos = List<Map<String, dynamic>>.from(response);

        // Guardar en caché
        _cacheProductos[idContrato] = {'productos': productos};
        _cacheTimestamps[idContrato] = DateTime.now();

        return productos;
      }
    } catch (e) {
      debugPrint('❌ Error obteniendo productos en consignación: $e');
      return [];
    }
  }

  /// Obtener stock actual de productos en la zona de destino de un contrato
  /// Fuente de verdad: app_dat_inventario_productos (cantidad_final)
  static Future<List<Map<String, dynamic>>> getStockEnZonaDestino(int idContrato, int idZonaDestino) async {
    try {
      debugPrint('📊 Obteniendo stock real en zona de destino: $idZonaDestino para contrato: $idContrato');

      final response = await _supabase
          .from('app_dat_inventario_productos')
          .select('''
            id_producto,
            id_presentacion,
            cantidad_final,
            app_dat_producto!id_producto(id, denominacion, sku)
          ''')
          .eq('id_ubicacion', idZonaDestino)
          .order('id', ascending: false);

      debugPrint('✅ Stock obtenido: ${response.length} registros');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ Error obteniendo stock en zona destino: $e');
      return [];
    }
  }

  /// Obtener productos pendientes de confirmación en un contrato
  static Future<List<Map<String, dynamic>>> getProductosPendientesConsignacion(int idContrato) async {
    try {
      debugPrint('📦 Obteniendo productos pendientes de confirmación para contrato: $idContrato');

      // Intentar usar RPC
      try {
        final response = await _supabase.rpc(
          'get_productos_pendientes_consignacion_optimizado',
          params: {'p_id_contrato': idContrato},
        ) as List;

        debugPrint('✅ Productos pendientes obtenidos (RPC): ${response.length}');

        final productos = response
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();

        return productos;
      } catch (rpcError) {
        debugPrint('⚠️ RPC no disponible, usando query alternativa: $rpcError');

        // Fallback a query manual
        final response = await _supabase
            .from('app_dat_producto_consignacion')
            .select('*, producto:id_producto(id, denominacion, sku, descripcion)')
            .eq('id_contrato', idContrato)
            .eq('estado', 0)
            .order('created_at', ascending: false);

        debugPrint('✅ Productos pendientes obtenidos (fallback): ${response.length}');

        final productos = List<Map<String, dynamic>>.from(response);

        return productos;
      }
    } catch (e) {
      debugPrint('❌ Error obteniendo productos pendientes: $e');
      return [];
    }
  }

  /// Registrar venta de producto en consignación
  static Future<bool> registrarVenta({
    required int idProductoConsignacion,
    required double cantidad,
    required double precioUnitario,
    int? idOperacionVenta,
    String? observaciones,
  }) async {
    try {
      debugPrint('💰 Registrando venta de producto en consignación: $idProductoConsignacion');

      // Obtener datos actuales del producto en consignación
      final prodConsig = await _supabase
          .from('app_dat_producto_consignacion')
          .select('cantidad_enviada, cantidad_vendida, cantidad_devuelta')
          .eq('id', idProductoConsignacion)
          .single();

      final cantidadEnviada = (prodConsig['cantidad_enviada'] as num).toDouble();
      final cantidadVendida = (prodConsig['cantidad_vendida'] as num).toDouble();
      final cantidadDevuelta = (prodConsig['cantidad_devuelta'] as num).toDouble();

      // Validar que haya stock disponible
      final stockDisponible = cantidadEnviada - cantidadVendida - cantidadDevuelta;
      if (cantidad > stockDisponible) {
        debugPrint('❌ No hay suficiente stock disponible');
        return false;
      }

      // Registrar movimiento de venta
      await _supabase.from('app_dat_movimiento_consignacion').insert({
        'id_producto_consignacion': idProductoConsignacion,
        'tipo_movimiento': 2, // Venta
        'cantidad': cantidad,
        'precio_unitario': precioUnitario,
        'total': cantidad * precioUnitario,
        'id_operacion_venta': idOperacionVenta,
        'observaciones': observaciones,
      });

      // Actualizar cantidad vendida
      await _supabase
          .from('app_dat_producto_consignacion')
          .update({
            'cantidad_vendida': cantidadVendida + cantidad,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', idProductoConsignacion);

      debugPrint('✅ Venta registrada exitosamente');
      return true;
    } catch (e) {
      debugPrint('❌ Error registrando venta: $e');
      return false;
    }
  }

  /// Registrar devolución de producto en consignación
  /// ✅ NUEVO: Descuenta automáticamente del monto_total del contrato
  static Future<bool> registrarDevolucion({
    required int idProductoConsignacion,
    required double cantidad,
    String? observaciones,
  }) async {
    try {
      debugPrint('↩️ Registrando devolución de producto en consignación: $idProductoConsignacion');

      // Obtener datos actuales del producto en consignación
      final prodConsig = await _supabase
          .from('app_dat_producto_consignacion')
          .select('id_contrato, id_presentacion, id_producto, cantidad_enviada, cantidad_vendida, cantidad_devuelta')
          .eq('id', idProductoConsignacion)
          .single();

      final cantidadEnviada = (prodConsig['cantidad_enviada'] as num).toDouble();
      final cantidadVendida = (prodConsig['cantidad_vendida'] as num).toDouble();
      final cantidadDevuelta = (prodConsig['cantidad_devuelta'] as num).toDouble();
      final idContrato = prodConsig['id_contrato'] as int;
      final idPresentacion = prodConsig['id_presentacion'] as int;
      final idProducto = prodConsig['id_producto'] as int;

      // Validar que haya stock disponible para devolver
      final stockDisponible = cantidadEnviada - cantidadVendida - cantidadDevuelta;
      if (cantidad > stockDisponible) {
        debugPrint('❌ No hay suficiente stock disponible para devolver');
        return false;
      }

      // Registrar movimiento de devolución
      await _supabase.from('app_dat_movimiento_consignacion').insert({
        'id_producto_consignacion': idProductoConsignacion,
        'tipo_movimiento': 3, // Devolución
        'cantidad': cantidad,
        'observaciones': observaciones,
      });

      // Actualizar cantidad devuelta
      await _supabase
          .from('app_dat_producto_consignacion')
          .update({
            'cantidad_devuelta': cantidadDevuelta + cantidad,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', idProductoConsignacion);

      // ✅ NUEVO: Descontar del monto_total del contrato
      debugPrint('💰 Descontando devolución del monto total del contrato...');
      try {
        // Obtener precio promedio de la presentación desde recepción
        final preciosResponse = await _supabase
            .from('app_dat_recepcion_productos')
            .select('precio_unitario')
            .eq('id_presentacion', idPresentacion)
            .eq('id_producto', idProducto);

        double precioPromedio = 0.0;
        if ((preciosResponse as List).isNotEmpty) {
          // Calcular promedio de precios
          double sumaPrecio = 0.0;
          for (final precio in preciosResponse) {
            sumaPrecio += (precio['precio_unitario'] as num).toDouble();
          }
          precioPromedio = sumaPrecio / preciosResponse.length;
        }

        debugPrint('📊 Precio promedio de presentación $idPresentacion: \$$precioPromedio');

        // Calcular monto a descontar
        final montoDescuento = precioPromedio * cantidad;
        debugPrint('💰 Monto a descontar: \$$precioPromedio × $cantidad = \$$montoDescuento');

        // Obtener monto actual del contrato
        final contratoData = await _supabase
            .from('app_dat_contrato_consignacion')
            .select('monto_total')
            .eq('id', idContrato)
            .single();

        final montoActual = (contratoData['monto_total'] as num?)?.toDouble() ?? 0.0;
        final nuevoMonto = (montoActual - montoDescuento).clamp(0.0, double.infinity);

        debugPrint('📊 Monto actual del contrato: \$$montoActual');
        debugPrint('📊 Nuevo monto total: \$$nuevoMonto');

        // Actualizar monto_total del contrato
        await _supabase
            .from('app_dat_contrato_consignacion')
            .update({
              'monto_total': nuevoMonto,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', idContrato);

        debugPrint('✅ Monto total del contrato actualizado exitosamente');
      } catch (e) {
        debugPrint('⚠️ Error descontando del contrato: $e');
        // No retornar false aquí, la devolución ya se registró
        // Solo loguear el error del descuento
      }

      debugPrint('✅ Devolución registrada exitosamente');
      return true;
    } catch (e) {
      debugPrint('❌ Error registrando devolución: $e');
      return false;
    }
  }

  /// Obtener movimientos de un producto en consignación
  static Future<List<Map<String, dynamic>>> getMovimientos(int idProductoConsignacion) async {
    try {
      debugPrint('📊 Obteniendo movimientos para producto: $idProductoConsignacion');

      final response = await _supabase
          .from('app_dat_movimiento_consignacion')
          .select('*')
          .eq('id_producto_consignacion', idProductoConsignacion)
          .order('fecha_movimiento', ascending: false);

      debugPrint('✅ Movimientos obtenidos: ${response.length}');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ Error obteniendo movimientos: $e');
      return [];
    }
  }

  /// Obtener estadísticas de consignación para una tienda
  static Future<Map<String, dynamic>> getEstadisticas(int idTienda) async {
    try {
      debugPrint('📈 Obteniendo estadísticas de consignación para tienda: $idTienda');

      // Obtener contratos activos
      final contratos = await getActiveContratos(idTienda);
      
      int totalProductosEnviados = 0;
      int totalProductosVendidos = 0;
      double totalVentas = 0;

      /* for (var contrato in contratos) {
        final productos = await getProductosConsignacion(contrato['id']);
        
        for (var producto in productos) {
          totalProductosEnviados += (producto['cantidad_enviada'] as num).toInt();
          totalProductosVendidos += (producto['cantidad_vendida'] as num).toInt();
          
          // Calcular ventas
          final movimientos = await getMovimientos(producto['id']);
          for (var mov in movimientos) {
            if (mov['tipo_movimiento'] == 2) { // Venta
              totalVentas += (mov['total'] as num?)?.toDouble() ?? 0;
            }
          }
        }
      } */

      return {
        'contratos_activos': contratos.length,
        'productos_enviados': totalProductosEnviados,
        'productos_vendidos': totalProductosVendidos,
        'total_ventas': totalVentas,
      };
    } catch (e) {
      debugPrint('❌ Error obteniendo estadísticas: $e');
      return {
        'contratos_activos': 0,
        'productos_enviados': 0,
        'productos_vendidos': 0,
        'total_ventas': 0.0,
      };
    }
  }

  /// Obtener almacenes de una tienda
  static Future<List<Map<String, dynamic>>> getAlmacenesPorTienda(int idTienda) async {
    try {
      debugPrint('🏭 Obteniendo almacenes para tienda: $idTienda');

      final response = await _supabase
          .from('app_dat_almacen')
          .select('id, denominacion, direccion')
          .eq('id_tienda', idTienda)
          .order('denominacion');

      debugPrint('✅ Almacenes obtenidos: ${response.length}');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ Error obteniendo almacenes: $e');
      return [];
    }
  }

  /// Actualizar almacén destino de un contrato
  static Future<bool> actualizarAlmacenDestino(int idContrato, int idAlmacenDestino) async {
    try {
      debugPrint('🏭 Actualizando almacén destino del contrato: $idContrato');

      await _supabase
          .from('app_dat_contrato_consignacion')
          .update({'id_almacen_destino': idAlmacenDestino})
          .eq('id', idContrato);

      debugPrint('✅ Almacén destino actualizado: $idAlmacenDestino');
      return true;
    } catch (e) {
      debugPrint('❌ Error actualizando almacén destino: $e');
      return false;
    }
  }

  /// Actualizar layout destino (zona de consignación) de un contrato
  static Future<bool> actualizarLayoutDestino(int idContrato, int idLayoutDestino) async {
    try {
      debugPrint('🏭 Actualizando layout destino del contrato: $idContrato');

      await _supabase
          .from('app_dat_contrato_consignacion')
          .update({'id_layout_destino': idLayoutDestino})
          .eq('id', idContrato);

      debugPrint('✅ Layout destino actualizado: $idLayoutDestino');
      return true;
    } catch (e) {
      debugPrint('❌ Error actualizando layout destino: $e');
      return false;
    }
  }

  /// Obtener el almacén origen desde el primer producto de consignación
  static Future<int?> getAlmacenOrigenFromContrato(int idContrato) async {
    try {
      debugPrint('🏭 Obteniendo almacén origen para contrato: $idContrato');

      // Obtener el primer producto de consignación
      final productos = await getProductosConsignacion(idContrato);
      if (productos.isEmpty) {
        debugPrint('⚠️ No hay productos en el contrato');
        return null;
      }

      final idUbicacionOrigen = productos[0]['id_ubicacion_origen'] as int?;
      if (idUbicacionOrigen == null) {
        debugPrint('⚠️ El producto no tiene id_ubicacion_origen');
        return null;
      }

      // Buscar el almacén al que pertenece esta ubicación
      final ubicacionResponse = await _supabase
          .from('app_dat_layout_almacen')
          .select('id_almacen')
          .eq('id', idUbicacionOrigen)
          .single();

      final idAlmacenOrigen = ubicacionResponse['id_almacen'] as int;
      debugPrint('✅ Almacén origen obtenido: $idAlmacenOrigen');
      return idAlmacenOrigen;
    } catch (e) {
      debugPrint('❌ Error obteniendo almacén origen: $e');
      return null;
    }
  }


  /// Crear un nuevo contrato de consignación
  static Future<Map<String, dynamic>?> crearContrato({
    required int idTiendaConsignadora,
    required int idTiendaConsignataria,
    required double porcentajeComision,
    int? idAlmacenDestino,
    DateTime? fechaInicio,
    DateTime? fechaFin,
    int? plazoDias,
    String? condiciones,
  }) async {
    try {
      debugPrint('📝 Creando contrato de consignación...');

      final contratoData = {
        'id_tienda_consignadora': idTiendaConsignadora,
        'id_tienda_consignataria': idTiendaConsignataria,
        'porcentaje_comision': porcentajeComision,
        'id_almacen_destino': idAlmacenDestino,
        'fecha_inicio': (fechaInicio ?? DateTime.now()).toIso8601String().split('T')[0],
        'fecha_fin': fechaFin?.toIso8601String().split('T')[0],
        'plazo_dias': plazoDias,
        'condiciones': condiciones,
        'estado': 1, // Activo
      };

      final response = await _supabase
          .from('app_dat_contrato_consignacion')
          .insert(contratoData)
          .select()
          .single();

      debugPrint('✅ Contrato creado exitosamente: ${response['id']}');
      return response;
    } catch (e) {
      debugPrint('❌ Error creando contrato: $e');
      return null;
    }
  }

  /// Asignar productos a un contrato de consignación (VERSIÓN COMPLETA CON AUDITORÍA)
  /// Asignar productos a un contrato de consignación (VERSIÓN COMPLETA CON AUDITORÍA)
  static Future<bool> asignarProductos({
    required int idContrato,
    required List<Map<String, dynamic>> productos,
    int? idAlmacenOrigen,
    int? idTiendaOrigen,
    int? idTiendaDestino,
    String? nombreTiendaConsignadora,
    int? idAlmacenDestino,
    int? idEnvio, // ✅ ID del envío para vincular
    String? numeroEnvio, // ✅ Número de envío para la descripción
    int? idOperacionExtraccion, // ✅ NUEVO: Permitir reusar una operación existente
  }) async {
    try {
      debugPrint('📦 Asignando ${productos.length} productos al contrato $idContrato...');

      // Obtener datos del contrato si se proporcionan
      Map<String, dynamic>? contrato;
      if (idAlmacenOrigen == null || idTiendaOrigen == null || idTiendaDestino == null) {
        contrato = await _supabase
            .from('app_dat_contrato_consignacion')
            .select('id_tienda_consignadora, id_tienda_consignataria, id_almacen_destino, id_layout_destino, app_dat_tienda!id_tienda_consignadora(denominacion)')
            .eq('id', idContrato)
            .single();

        idTiendaOrigen = contrato['id_tienda_consignadora'];
        idTiendaDestino = contrato['id_tienda_consignataria'];
        nombreTiendaConsignadora = contrato['app_dat_tienda']['denominacion'];
      }

      // Obtener almacén destino del contrato si no se proporcionó
      if (idAlmacenDestino == null) {
        final contratoDestino = await _supabase
            .from('app_dat_contrato_consignacion')
            .select('id_almacen_destino')
            .eq('id', idContrato)
            .single();
        idAlmacenDestino = contratoDestino['id_almacen_destino'] as int?;
      }

      if (idAlmacenDestino == null) {
        debugPrint('❌ Error: No se especificó almacén destino');
        return false;
      }

      // 1. Crear o actualizar operación de extracción para RESERVAR el stock (Estado 1 = Pendiente)
      int? idExtraccion = idOperacionExtraccion;
      
      if (idExtraccion == null) {
        final uuid = _supabase.auth.currentUser?.id;
        final email = _supabase.auth.currentUser?.email ?? 'Sistema';
        
        if (uuid == null) throw Exception('Usuario no autenticado');

        final productosExtraccion = productos.map((p) => {
          'id_producto': p['id_producto'],
          'cantidad': p['cantidad'],
          'id_presentacion': p['id_presentacion'],
          'id_ubicacion': p['id_ubicacion'],
          'id_variante': p['id_variante'],
          'id_opcion_variante': p['id_opcion_variante'],
          'precio_unitario': p['precio_costo_unitario'] ?? 0,
        }).toList();

        debugPrint('🔄 Creando operación de extracción (Reserva) para ${productos.length} productos...');
        
        String observaciones = 'Envío a consignación - Contrato #$idContrato';
        if (numeroEnvio != null) {
          observaciones += '. Extracción para envío $numeroEnvio';
        }

        final extraccionResult = await _supabase.rpc(
          'fn_insertar_extraccion_completa',
          params: {
            'p_autorizado_por': email,
            'p_estado_inicial': 1, // 1 = Pendiente (Reserva)
            'p_id_motivo_operacion': 5, // Transferencia a otra tienda
            'p_id_tienda': idTiendaOrigen,
            'p_observaciones': observaciones,
            'p_productos': productosExtraccion,
            'p_uuid': uuid,
          },
        );

        if (extraccionResult['status'] != 'success') {
          throw Exception('Error creando reserva: ${extraccionResult['message']}');
        }

        idExtraccion = extraccionResult['id_operacion'];
        debugPrint('✅ Reserva creada con ID Operación: $idExtraccion');
      } else {
        debugPrint('🔗 Reusando operación de extracción existente: $idExtraccion');
        
        // OPCIONAL: Actualizar observaciones con el número de envío si no se hizo antes
        if (numeroEnvio != null) {
          try {
            await _supabase
                .from('app_dat_operaciones')
                .update({'observaciones': 'Envío a consignación - Contrato #$idContrato. Extracción para envío $numeroEnvio'})
                .eq('id', idExtraccion);
            debugPrint('✅ Observaciones de operación $idExtraccion actualizadas');
          } catch (e) {
            debugPrint('⚠️ No se pudo actualizar observaciones: $e');
          }
        }
      }

      // ✅ Vincular operación al envío si se proporcionó idEnvio
      if (idEnvio != null && idExtraccion != null) {
        await _supabase
            .from('app_dat_consignacion_envio')
            .update({'id_operacion_extraccion': idExtraccion})
            .eq('id', idEnvio);
        debugPrint('✅ Operación $idExtraccion vinculada al envío $idEnvio');
      }

      // 2. Asignar productos al contrato con referencia a la extracción
      for (var producto in productos) {
        final productoData = {
          'id_contrato': idContrato,
          'id_producto': producto['id_producto'],
          'id_variante': producto['id_variante'],
          'id_presentacion': producto['id_presentacion'],
          'id_ubicacion_origen': producto['id_ubicacion'],
          'cantidad_enviada': producto['cantidad'],
          'precio_venta_sugerido': producto['precio_costo_unitario'],
          'puede_modificar_precio': producto['puede_modificar_precio'] ?? false,
          'estado': 0, // PENDIENTE
          'id_operacion_extraccion': idExtraccion, // Link a la reserva
        };

        // Insertar producto en consignación
        final prodConsig = await _supabase
            .from('app_dat_producto_consignacion')
            .insert(productoData)
            .select()
            .single();

        debugPrint('✅ Producto consignación creado: ${prodConsig['id']}');

        // ✅ Si tenemos idEnvio, también actualizar app_dat_consignacion_envio_producto para vincularlo
        if (idEnvio != null) {
          await _supabase
              .from('app_dat_consignacion_envio_producto')
              .update({'id_producto_consignacion': prodConsig['id']})
              .match({
                'id_envio': idEnvio,
                'id_producto': producto['id_producto'],
                'estado': 1
              });
        }
      }

      debugPrint('✅ Productos asignados y reservados exitosamente');
      return true;
    } catch (e) {
      debugPrint('❌ Error asignando productos: $e');
      return false;
    }
  }

  /// ✅ NUEVO: Crear reserva de stock (operación de extracción pendiente)
  static Future<int?> crearReservaStock({
    required int idContrato,
    required List<Map<String, dynamic>> productos,
    required int idTiendaOrigen,
  }) async {
    try {
      final uuid = _supabase.auth.currentUser?.id;
      final email = _supabase.auth.currentUser?.email ?? 'Sistema';
      
      if (uuid == null) throw Exception('Usuario no autenticado');

      final productosExtraccion = productos.map((p) => {
        'id_producto': p['id_producto'],
        'cantidad': p['cantidad'],
        'id_presentacion': p['id_presentacion'],
        'id_ubicacion': p['id_ubicacion'],
        'id_variante': p['id_variante'],
        'id_opcion_variante': p['id_opcion_variante'],
        'precio_unitario': p['precio_costo_unitario'] ?? 0,
      }).toList();

      debugPrint('🔄 Reservando stock para ${productos.length} productos...');
      
      final extraccionResult = await _supabase.rpc(
        'fn_insertar_extraccion_completa',
        params: {
          'p_autorizado_por': email,
          'p_estado_inicial': 1, // 1 = Pendiente (Reserva)
          'p_id_motivo_operacion': 5, // Transferencia a otra tienda
          'p_id_tienda': idTiendaOrigen,
          'p_observaciones': 'Envío a consignación - Contrato #$idContrato (Reserva inicial)',
          'p_productos': productosExtraccion,
          'p_uuid': uuid,
        },
      );

      if (extraccionResult['status'] != 'success') {
        throw Exception('Error creando reserva: ${extraccionResult['message']}');
      }

      final idExtraccion = extraccionResult['id_operacion'] as int;
      debugPrint('✅ Stock reservado con ID Operación: $idExtraccion');
      return idExtraccion;
    } catch (e) {
      debugPrint('❌ Error reservando stock: $e');
      rethrow;
    }
  }

  /// Obtener todas las tiendas disponibles (excepto la actual)
  static Future<List<Map<String, dynamic>>> getTiendasDisponibles(int idTiendaActual) async {
    try {
      debugPrint('🏪 Obteniendo tiendas disponibles...');

      final response = await _supabase
          .from('app_dat_tienda')
          .select('id, denominacion, direccion')
          .neq('id', idTiendaActual)
          .order('denominacion');

      debugPrint('✅ Tiendas obtenidas: ${response.length}');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ Error obteniendo tiendas: $e');
      return [];
    }
  }

  /// Obtener productos de inventario de una tienda
  static Future<List<Map<String, dynamic>>> getProductosInventario(int idTienda) async {
    try {
      debugPrint('📦 Obteniendo productos de inventario para tienda: $idTienda');

      // Primero obtener almacenes de la tienda
      final almacenes = await _supabase
          .from('app_dat_almacen')
          .select('id')
          .eq('id_tienda', idTienda);

      if (almacenes.isEmpty) {
        debugPrint('⚠️ No hay almacenes para la tienda $idTienda');
        return [];
      }

      final almacenIds = (almacenes as List).map((a) => a['id']).toList();

      // Obtener layouts de esos almacenes
      final layouts = await _supabase
          .from('app_dat_layout_almacen')
          .select('id')
          .inFilter('id_almacen', almacenIds);

      if (layouts.isEmpty) {
        debugPrint('⚠️ No hay layouts para los almacenes');
        return [];
      }

      final layoutIds = (layouts as List).map((l) => l['id']).toList();

      // Obtener productos del inventario en esos layouts
      final response = await _supabase
          .from('app_dat_inventario_productos')
          .select('''
            *,
            app_dat_producto!inner(id, denominacion, sku, descripcion)
          ''')
          .inFilter('id_ubicacion', layoutIds)
          .gt('cantidad_final', 0)
          .order('app_dat_producto(denominacion)');

      debugPrint('✅ Productos obtenidos: ${response.length}');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ Error obteniendo productos: $e');
      return [];
    }
  }

  /// Obtener contratos donde la tienda es CONSIGNATARIA (recibe productos)
  static Future<List<Map<String, dynamic>>> getContratosComoConsignataria(int idTienda) async {
    try {
      debugPrint('📋 Obteniendo contratos como consignataria para tienda: $idTienda');

      final response = await _supabase
          .from('app_dat_contrato_consignacion')
          .select('*')
          .eq('id_tienda_consignataria', idTienda)
          .eq('estado', 1)
          .order('created_at', ascending: false);

      debugPrint('✅ Contratos obtenidos: ${response.length}');

      // Enriquecer con datos de tiendas
      final List<Map<String, dynamic>> enrichedContratos = [];
      for (var contrato in response) {
        final idConsignadora = contrato['id_tienda_consignadora'];

        // Obtener datos de tienda consignadora
        final tiendaConsignadora = await _supabase
            .from('app_dat_tienda')
            .select('id, denominacion, direccion')
            .eq('id', idConsignadora)
            .single();

        enrichedContratos.add({
          ...contrato,
          'tienda_consignadora': tiendaConsignadora,
        });
      }

      return enrichedContratos;
    } catch (e) {
      debugPrint('❌ Error obteniendo contratos como consignataria: $e');
      return [];
    }
  }

  /// Confirmar recepción de producto en consignación (por consignataria)
  static Future<bool> confirmarRecepcion({
    required int idProductoConsignacion,
    String? observaciones,
  }) async {
    try {
      debugPrint('✅ Confirmando recepción de producto: $idProductoConsignacion');

      await _supabase
          .from('app_dat_producto_consignacion')
          .update({
            'estado_confirmacion': 1, // Confirmado
            'fecha_confirmacion': DateTime.now().toIso8601String().split('T')[0],
            'observaciones': observaciones,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', idProductoConsignacion);

      debugPrint('✅ Recepción confirmada exitosamente');
      return true;
    } catch (e) {
      debugPrint('❌ Error confirmando recepción: $e');
      return false;
    }
  }

  /// Rechazar producto en consignación (por consignataria)
  static Future<bool> rechazarProducto({
    required int idProductoConsignacion,
    required String motivo,
  }) async {
    try {
      debugPrint('❌ Rechazando producto: $idProductoConsignacion');

      await _supabase
          .from('app_dat_producto_consignacion')
          .update({
            'estado_confirmacion': 2, // Rechazado
            'observaciones': motivo,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', idProductoConsignacion);

      debugPrint('✅ Producto rechazado exitosamente');
      return true;
    } catch (e) {
      debugPrint('❌ Error rechazando producto: $e');
      return false;
    }
  }

  /// Obtener productos pendientes de confirmación para una tienda consignataria
  static Future<List<Map<String, dynamic>>> getProductosPendientesConfirmacion(int idTienda) async {
    try {
      debugPrint('📋 Obteniendo productos pendientes de confirmación para tienda: $idTienda');

      // Obtener contratos donde la tienda es consignataria
      final contratos = await _supabase
          .from('app_dat_contrato_consignacion')
          .select('id')
          .eq('id_tienda_consignataria', idTienda)
          .eq('estado', 1);

      if (contratos.isEmpty) {
        return [];
      }

      final contratoIds = (contratos as List).map((c) => c['id']).toList();

      // Obtener productos pendientes de confirmación
      final response = await _supabase
          .from('app_dat_producto_consignacion')
          .select('*')
          .inFilter('id_contrato', contratoIds)
          .eq('estado_confirmacion', 0) // Pendiente
          .order('created_at', ascending: false);

      debugPrint('✅ Productos pendientes obtenidos: ${response.length}');

      // Enriquecer con datos de productos
      final List<Map<String, dynamic>> enrichedProductos = [];
      for (var prodConsig in response) {
        final idProducto = prodConsig['id_producto'];

        final producto = await _supabase
            .from('app_dat_producto')
            .select('id, denominacion, sku, descripcion')
            .eq('id', idProducto)
            .single();

        enrichedProductos.add({
          ...prodConsig,
          'producto': producto,
        });
      }

      return enrichedProductos;
    } catch (e) {
      debugPrint('❌ Error obteniendo productos pendientes: $e');
      return [];
    }
  }

  /// Obtener estadísticas de consignación para una tienda como consignataria
  static Future<Map<String, dynamic>> getEstadisticasConsignataria(int idTienda) async {
    try {
      debugPrint('📊 Obteniendo estadísticas de consignataria para tienda: $idTienda');

      // Obtener contratos donde es consignataria
      final contratos = await _supabase
          .from('app_dat_contrato_consignacion')
          .select('id, porcentaje_comision')
          .eq('id_tienda_consignataria', idTienda)
          .eq('estado', 1);

      if (contratos.isEmpty) {
        return {
          'total_contratos': 0,
          'total_enviado': 0,
          'total_vendido': 0,
          'total_devuelto': 0,
          'comision_total': 0,
          'a_pagar': 0,
        };
      }

      double totalEnviado = 0;
      double totalVendido = 0;
      double totalDevuelto = 0;
      double comisionTotal = 0;

      // Para cada contrato, obtener productos y calcular totales
      for (var contrato in contratos) {
        final idContrato = contrato['id'];
        final porcentajeComision = (contrato['porcentaje_comision'] as num).toDouble();

        final productos = await _supabase
            .from('app_dat_producto_consignacion')
            .select('cantidad_enviada, cantidad_vendida, cantidad_devuelta, precio_venta_sugerido')
            .eq('id_contrato', idContrato)
            .eq('estado', 1);

        for (var prod in productos) {
          final enviada = (prod['cantidad_enviada'] as num).toDouble();
          final vendida = (prod['cantidad_vendida'] as num).toDouble();
          final devuelta = (prod['cantidad_devuelta'] as num).toDouble();
          final precio = (prod['precio_venta_sugerido'] as num?)?.toDouble() ?? 0;

          totalEnviado += enviada;
          totalVendido += vendida;
          totalDevuelto += devuelta;

          // Calcular comisión sobre lo vendido
          final montoVendido = vendida * precio;
          comisionTotal += (montoVendido * porcentajeComision) / 100;
        }
      }

      final aPagar = (totalVendido * 0) - comisionTotal; // Simplificado: lo que debe pagar es la comisión

      return {
        'total_contratos': contratos.length,
        'total_enviado': totalEnviado,
        'total_vendido': totalVendido,
        'total_devuelto': totalDevuelto,
        'comision_total': comisionTotal,
        'a_pagar': comisionTotal, // Lo que debe pagar es la comisión
      };
    } catch (e) {
      debugPrint('❌ Error obteniendo estadísticas: $e');
      return {
        'total_contratos': 0,
        'total_enviado': 0,
        'total_vendido': 0,
        'total_devuelto': 0,
        'comision_total': 0,
        'a_pagar': 0,
      };
    }
  }

  /// Rescindir contrato de consignación (solo si no hay productos pendientes)
  static Future<bool> rescindirContrato({
    required int idContrato,
    String? motivo,
  }) async {
    try {
      debugPrint('🔴 Rescindiendo contrato: $idContrato');

      // Verificar que no hay productos pendientes (sin vender/devolver)
      final productos = await _supabase
          .from('app_dat_producto_consignacion')
          .select('cantidad_enviada, cantidad_vendida, cantidad_devuelta')
          .eq('id_contrato', idContrato)
          .eq('estado', 1);

      // Validar que todos los productos estén completamente vendidos o devueltos
      for (var prod in productos) {
        final enviada = (prod['cantidad_enviada'] as num).toDouble();
        final vendida = (prod['cantidad_vendida'] as num).toDouble();
        final devuelta = (prod['cantidad_devuelta'] as num).toDouble();
        final pendiente = enviada - vendida - devuelta;

        if (pendiente > 0) {
          debugPrint('❌ No se puede rescindir: hay $pendiente unidades pendientes');
          return false;
        }
      }

      // Desactivar todos los productos del contrato
      await _supabase
          .from('app_dat_producto_consignacion')
          .update({
            'estado': 0, // Inactivo
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id_contrato', idContrato);

      // Desactivar el contrato
      await _supabase
          .from('app_dat_contrato_consignacion')
          .update({
            'estado': 0, // Inactivo
            'fecha_fin': DateTime.now().toIso8601String().split('T')[0],
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', idContrato);

      // Registrar movimiento de rescisión (tipo 4) para cada producto
      final productosDelContrato = await _supabase
          .from('app_dat_producto_consignacion')
          .select('id')
          .eq('id_contrato', idContrato);

      for (var prod in productosDelContrato) {
        await _supabase.from('app_dat_movimiento_consignacion').insert({
          'id_producto_consignacion': prod['id'],
          'tipo_movimiento': 4, // Rescisión
          'observaciones': motivo ?? 'Contrato rescindido',
        });
      }

      debugPrint('✅ Contrato rescindido exitosamente');
      return true;
    } catch (e) {
      debugPrint('❌ Error rescindiendo contrato: $e');
      return false;
    }
  }

  /// Verificar si un contrato puede ser rescindido (no tiene productos pendientes)
  static Future<bool> puedeSerRescindido(int idContrato) async {
    try {
      final productos = await _supabase
          .from('app_dat_producto_consignacion')
          .select('cantidad_enviada, cantidad_vendida, cantidad_devuelta')
          .eq('id_contrato', idContrato)
          .eq('estado', 1);

      // Si no hay productos, puede rescindirse
      if (productos.isEmpty) {
        return true;
      }

      // Verificar que todos los productos estén completamente vendidos o devueltos
      for (var prod in productos) {
        final enviada = (prod['cantidad_enviada'] as num).toDouble();
        final vendida = (prod['cantidad_vendida'] as num).toDouble();
        final devuelta = (prod['cantidad_devuelta'] as num).toDouble();
        final pendiente = enviada - vendida - devuelta;

        if (pendiente > 0) {
          return false;
        }
      }

      return true;
    } catch (e) {
      debugPrint('❌ Error verificando si puede rescindirse: $e');
      return false;
    }
  }

  /// ✅ NUEVO: Validar orden de operaciones en consignación
  /// Verifica que la operación de extracción esté completada antes de completar la recepción
  /// Retorna: {valido: bool, mensaje: string, id_operacion_extraccion: int?, estado_extraccion: int?}
  static Future<Map<String, dynamic>> validarOrdenOperacionesConsignacion(int idOperacionRecepcion) async {
    try {
      debugPrint('🔍 Validando orden de operaciones para recepción: $idOperacionRecepcion');

      // Llamar a la función RPC de validación
      final response = await _supabase.rpc(
        'validar_orden_operaciones_consignacion',
        params: {'p_id_operacion_recepcion': idOperacionRecepcion},
      ) as List;

      if (response.isNotEmpty) {
        final result = response.first as Map<String, dynamic>;
        final valido = result['valido'] as bool;
        final mensaje = result['mensaje'] as String;
        final idOperacionExtraccion = result['id_operacion_extraccion'] as int?;
        final estadoExtraccion = result['estado_extraccion'] as int?;

        if (valido) {
          debugPrint('✅ Validación exitosa: $mensaje');
        } else {
          debugPrint('❌ Validación fallida: $mensaje');
          debugPrint('   Operación de extracción: $idOperacionExtraccion');
          debugPrint('   Estado: $estadoExtraccion (debe ser 3 = Completada)');
        }

        return {
          'valido': valido,
          'mensaje': mensaje,
          'id_operacion_extraccion': idOperacionExtraccion,
          'estado_extraccion': estadoExtraccion,
        };
      }

      debugPrint('❌ Error: Respuesta vacía de validación');
      return {
        'valido': false,
        'mensaje': 'Error en validación: respuesta vacía',
        'id_operacion_extraccion': null,
        'estado_extraccion': null,
      };
    } catch (e) {
      debugPrint('❌ Error validando orden de operaciones: $e');
      return {
        'valido': false,
        'mensaje': 'Error: $e',
        'id_operacion_extraccion': null,
        'estado_extraccion': null,
      };
    }
  }

  /// ✅ NUEVO: Validar estado del envío antes de completar una extracción
  /// Retorna: {valido: bool, mensaje: string, id_envio: int?, estado_envio: int?}
  static Future<Map<String, dynamic>> validarEstadoEnvioParaExtraccion(int idOperacionExtraccion) async {
    try {
      debugPrint('🔍 Validando estado de envío para extracción: $idOperacionExtraccion');

      // Buscar envío vinculado a esta operación de extracción
      final dataEnvio = await Supabase.instance.client
          .from('app_dat_consignacion_envio')
          .select('id, numero_envio, estado_envio')
          .eq('id_operacion_extraccion', idOperacionExtraccion)
          .maybeSingle();

      if (dataEnvio == null) {
        // No es una operación vinculada a un envío de consignación (o al menos no por id_operacion_extraccion)
        return {'valido': true, 'id_envio': null};
      }

      final idEnvio = dataEnvio['id'] as int;
      final estadoEnvio = dataEnvio['estado_envio'] as int;
      final numeroEnvio = dataEnvio['numero_envio'] as String;

      // El envío debe estar en estado CONFIGURADO (2) para ser enviado (en tránsito)
      // Si está en estado PROPUESTO (1), significa que aún no se le han asignado precios.
      if (estadoEnvio == 1) { // ESTADO_PROPUESTO
        return {
          'valido': false,
          'id_envio': idEnvio,
          'estado_envio': estadoEnvio,
          'mensaje': '⚠️ No se puede completar la extracción\n\n'
              'El envío $numeroEnvio aún no tiene precios configurados.\n\n'
              'Por favor, ve a la sección de "Envíos", selecciona este envío y completa la configuración de precios antes de extraer el stock físicamente.',
        };
      }

      return {
        'valido': true,
        'id_envio': idEnvio,
        'estado_envio': estadoEnvio,
      };
    } catch (e) {
      debugPrint('❌ Error validando estado de envío: $e');
      return {'valido': true, 'id_envio': null}; // En caso de duda, permitimos continuar
    }
  }

  /// ✅ NUEVO: Obtener información de operaciones relacionadas en consignación
  static Future<Map<String, dynamic>?> getOperacionesConsignacionRelacionadas(int idOperacionRecepcion) async {
    try {
      debugPrint('📊 Obteniendo operaciones relacionadas para recepción: $idOperacionRecepcion');

      final response = await _supabase.rpc(
        'get_operaciones_consignacion_relacionadas',
        params: {'p_id_operacion_recepcion': idOperacionRecepcion},
      ) as List;

      if (response.isNotEmpty) {
        final result = response.first as Map<String, dynamic>;
        debugPrint('✅ Operaciones relacionadas obtenidas');
        debugPrint('   Recepción: ${result['id_operacion_recepcion']}');
        debugPrint('   Extracción: ${result['id_operacion_extraccion']}');
        debugPrint('   Estado recepción: ${result['estado_recepcion']}');
        debugPrint('   Estado extracción: ${result['estado_extraccion']}');
        debugPrint('   Productos: ${result['productos_count']}');
        return result;
      }

      debugPrint('⚠️ No se encontraron operaciones relacionadas');
      return null;
    } catch (e) {
      debugPrint('❌ Error obteniendo operaciones relacionadas: $e');
      return null;
    }
  }

  /// Obtener contratos pendientes de confirmación para una tienda consignataria (OPTIMIZADO)
  static Future<List<Map<String, dynamic>>> getContratosPendientesConfirmacion(int idTienda) async {
    try {
      debugPrint('📋 Obteniendo contratos pendientes para tienda: $idTienda (OPTIMIZADO)');

      // Usar RPC para obtener contratos con datos de tienda en una sola query
      final response = await _supabase.rpc(
        'get_contratos_pendientes_confirmacion',
        params: {'p_id_tienda': idTienda},
      ) as List;

      debugPrint('✅ Contratos pendientes obtenidos: ${response.length}');

      // Convertir a List<Map<String, dynamic>>
      final List<Map<String, dynamic>> contratos = response
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      return contratos;
    } catch (e) {
      debugPrint('⚠️ RPC no disponible, usando query alternativa: $e');
      
      // Fallback a query manual si RPC no existe
      try {
        final response = await _supabase
            .from('app_dat_contrato_consignacion')
            .select('*, tienda_consignadora:id_tienda_consignadora(id, denominacion, direccion)')
            .eq('id_tienda_consignataria', idTienda)
            .eq('estado_confirmacion', 0)
            .eq('estado', 1)
            .order('created_at', ascending: false);

        debugPrint('✅ Contratos pendientes obtenidos (fallback): ${response.length}');
        return List<Map<String, dynamic>>.from(response);
      } catch (fallbackError) {
        debugPrint('❌ Error obteniendo contratos pendientes: $fallbackError');
        return [];
      }
    }
  }

  /// Confirmar contrato de consignación
  static Future<bool> confirmarContrato(int idContrato) async {
    try {
      debugPrint('✅ Confirmando contrato: $idContrato');

      await _supabase
          .from('app_dat_contrato_consignacion')
          .update({
            'estado_confirmacion': 1, // Confirmado
            'fecha_confirmacion': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', idContrato);

      debugPrint('✅ Contrato confirmado exitosamente');
      return true;
    } catch (e) {
      debugPrint('❌ Error confirmando contrato: $e');
      return false;
    }
  }

  /// Cancelar contrato de consignación
  static Future<bool> cancelarContrato(int idContrato, String motivo) async {
    try {
      debugPrint('❌ Cancelando contrato: $idContrato - Motivo: $motivo');

      await _supabase
          .from('app_dat_contrato_consignacion')
          .update({
            'estado_confirmacion': 2, // Cancelado
            'estado': 0, // Inactivo
            'fecha_confirmacion': DateTime.now().toIso8601String(),
            'motivo_cancelacion': motivo,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', idContrato);

      // Desactivar todos los productos del contrato
      await _supabase
          .from('app_dat_producto_consignacion')
          .update({'estado': 0})
          .eq('id_contrato', idContrato);

      debugPrint('✅ Contrato cancelado exitosamente');
      return true;
    } catch (e) {
      debugPrint('❌ Error cancelando contrato: $e');
      return false;
    }
  }

  /// Obtener o crear zona de consignación para un contrato
  /// SOLO crea/obtiene zona en almacén DESTINO
  /// La zona de origen se obtiene de los productos asignados (id_ubicacion_origen)
  static Future<Map<String, dynamic>?> obtenerOCrearZonaConsignacion({
    required int idContrato,
    required int idAlmacenDestino,
    required int idTiendaConsignadora,
    required int idTiendaConsignataria,
    required String nombreTiendaConsignadora,
  }) async {
    try {
      debugPrint('🔍 Buscando zona de consignación para contrato: $idContrato');

      // Nombre de la zona: "Consignaciones - NombreTiendaConsignadora"
      final nombreZona = 'Consignaciones - $nombreTiendaConsignadora';

      // Usar id_tipo_layout = 16 para zonas de consignación
      const int idTipoLayout = 16;
      debugPrint('📋 Usando id_tipo_layout = 16 para zona de consignación');

      // Buscar o crear zona en almacén DESTINO
      debugPrint('📦 Buscando zona de recepción en almacén destino: $idAlmacenDestino');
      
      final zonasDestinoExistentes = await _supabase
          .from('app_dat_layout_almacen')
          .select('id, denominacion')
          .eq('id_almacen', idAlmacenDestino)
          .eq('denominacion', nombreZona)
          .limit(1);

      Map<String, dynamic>? zonaDestino;

      if ((zonasDestinoExistentes as List).isNotEmpty) {
        debugPrint('✅ Zona de recepción existente encontrada: ${zonasDestinoExistentes[0]['id']}');
        zonaDestino = zonasDestinoExistentes[0] as Map<String, dynamic>;
      } else {
        debugPrint('📝 Creando nueva zona de recepción: $nombreZona con id_tipo_layout = 16');
        
        final nuevaZonaDestino = await _supabase
            .from('app_dat_layout_almacen')
            .insert({
              'id_almacen': idAlmacenDestino,
              'id_tipo_layout': idTipoLayout,
              'denominacion': nombreZona,
            })
            .select()
            .single();

        debugPrint('✅ Zona de recepción creada: ${nuevaZonaDestino['id']} con tipo layout 16');
        zonaDestino = nuevaZonaDestino as Map<String, dynamic>;
      }

      // Guardar relación contrato-zona en app_dat_consignacion_zona
      if (zonaDestino != null) {
        try {
          // Verificar si ya existe la relación
          final existente = await _supabase
              .from('app_dat_consignacion_zona')
              .select('id')
              .eq('id_contrato', idContrato)
              .eq('id_zona', zonaDestino['id'])
              .limit(1);

          if ((existente as List).isEmpty) {
            // Insertar solo si no existe
            await _supabase
                .from('app_dat_consignacion_zona')
                .insert({
                  'id_contrato': idContrato,
                  'id_zona': zonaDestino['id'],
                  'id_tienda_consignadora': idTiendaConsignadora,
                  'id_tienda_consignataria': idTiendaConsignataria,
                  'nombre_zona': nombreZona,
                });

            debugPrint('✅ Relación contrato-zona guardada');
          } else {
            debugPrint('⚠️ Relación contrato-zona ya existe');
          }
        } catch (e) {
          debugPrint('⚠️ Error guardando relación: $e');
        }
      }

      return zonaDestino;
    } catch (e) {
      debugPrint('❌ Error en obtenerOCrearZonaConsignacion: $e');
      return null;
    }
  }

  /// Confirmar recepción de productos en consignación (crea operaciones de auditoría)
  /// NUEVO: Duplica productos que no existen en tienda destino (bajo demanda)
  /// NUEVO: Configura precios de venta para cada producto
  static Future<bool> confirmarRecepcionProductosConsignacion({
    required int idContrato,
    required int idTiendaOrigen,
    required int idTiendaDestino,
    required int idAlmacenOrigen,
    required int idAlmacenDestino,
    required List<int> idsProductosConsignacion,
    Map<int, double>? preciosVenta,
  }) async {
    try {
      debugPrint('✅ Confirmando recepción de productos en consignación...');

      // Obtener datos de los productos en consignación (incluyendo precio del consignador)
      final productosConsignacion = await _supabase
          .from('app_dat_producto_consignacion')
          .select('id, id_producto, id_presentacion, cantidad_enviada, id_ubicacion_origen, precio_venta_sugerido')
          .inFilter('id', idsProductosConsignacion);

      if ((productosConsignacion as List).isEmpty) {
        debugPrint('❌ No se encontraron productos en consignación');
        return false;
      }

      // Obtener nombre de la tienda consignadora
      final tiendasResponse = await _supabase
          .from('app_dat_tienda')
          .select('denominacion')
          .eq('id', idTiendaOrigen)
          .single();
      
      final nombreTiendaConsignadora = tiendasResponse['denominacion'] as String? ?? 'Tienda';

      // Mapear productos: original -> duplicado/reutilizado (bajo demanda)
      // Si el producto existe en tienda destino, se reutiliza
      // Si NO existe, se duplica completamente
      debugPrint('🔄 Preparando duplicación bajo demanda de productos...');
      int productosDuplicados = 0;
      int productosReutilizados = 0;
      
      final Map<int, Map<String, int>> mapeoProductos = {};

      for (final prodConsig in productosConsignacion) {
        final idProductoOriginal = prodConsig['id_producto'] as int;
        final idProductoConsignacion = prodConsig['id'] as int;

        try {
          debugPrint('🔄 Procesando producto $idProductoOriginal para tienda destino $idTiendaDestino');
          
          // Usar duplicación bajo demanda
          final idProductoResultado = await ConsignacionDuplicacionService.duplicarProductoSiNecesario(
            idProductoOriginal: idProductoOriginal,
            idTiendaDestino: idTiendaDestino,
            idContratoConsignacion: idContrato,
            idTiendaOrigen: idTiendaOrigen,
          );

          if (idProductoResultado != null) {
            mapeoProductos[idProductoOriginal] = {
              'id_original': idProductoOriginal,
              'id_duplicado': idProductoResultado,
            };
            
            debugPrint('📋 Mapeo guardado: $idProductoOriginal → $idProductoResultado');
            
            // Verificar si fue duplicado o reutilizado
            if (idProductoResultado == idProductoOriginal) {
              productosReutilizados++;
              debugPrint('♻️ Producto reutilizado: $idProductoOriginal (mismo ID)');
            } else {
              productosDuplicados++;
              debugPrint('✅ Producto duplicado: $idProductoOriginal → $idProductoResultado (IDs diferentes)');
            }
          } else {
            debugPrint('❌ Error duplicando producto $idProductoOriginal: resultado NULL');
          }
        } catch (e) {
          debugPrint('❌ Error en duplicación de producto $idProductoOriginal: $e');
        }
      }

      debugPrint('📊 Duplicación completada:');
      debugPrint('   ✅ Productos duplicados: $productosDuplicados');
      debugPrint('   ♻️ Productos reutilizados: $productosReutilizados');
      debugPrint('📋 Mapeo de productos: ${mapeoProductos.length} entradas');
      for (final entry in mapeoProductos.entries) {
        debugPrint('   ${entry.key} → ${entry.value['id_duplicado']}');
      }

      // Obtener o crear zona de consignación (solo en almacén destino)
      final zona = await obtenerOCrearZonaConsignacion(
        idContrato: idContrato,
        idAlmacenDestino: idAlmacenDestino,
        idTiendaConsignadora: idTiendaOrigen,
        idTiendaConsignataria: idTiendaDestino,
        nombreTiendaConsignadora: nombreTiendaConsignadora,
      );

      if (zona == null) {
        debugPrint('❌ Error: No se pudo crear la zona de consignación');
        return false;
      }

      final idZonaDestino = zona['id'] as int;

      // Crear operaciones de auditoría para cada producto
      final operacionesCreadas = await crearOperacionesAuditoria(
        idTiendaOrigen: idTiendaOrigen,
        idTiendaDestino: idTiendaDestino,
        idAlmacenOrigen: idAlmacenOrigen,
        idAlmacenDestino: idAlmacenDestino,
        idZonaDestino: idZonaDestino,
        productos: productosConsignacion,
        mapeoProductos: mapeoProductos,
        preciosVenta: preciosVenta,
        idsProductosConsignacion: idsProductosConsignacion,
      );

      if (!operacionesCreadas) {
        debugPrint('❌ Error creando operaciones de auditoría');
        return false;
      }

      // Actualizar estado de productos a CONFIRMADO (1) y configurar precios de venta
      for (final idProductoConsignacion in idsProductosConsignacion) {
        try {
          await _supabase
              .from('app_dat_producto_consignacion')
              .update({'estado': 1}) // Confirmado
              .eq('id', idProductoConsignacion);

          // Registrar movimiento de envío
          await _supabase.from('app_dat_movimiento_consignacion').insert({
            'id_producto_consignacion': idProductoConsignacion,
            'tipo_movimiento': 1, // Envío
            'cantidad': (productosConsignacion.firstWhere((p) => p['id'] == idProductoConsignacion)['cantidad_enviada'] as num).toDouble(),
            'observaciones': 'Envío confirmado de producto en consignación',
          });

          debugPrint('✅ Producto consignación confirmado: $idProductoConsignacion');

          // NUEVO: Configurar precio de venta si se proporcionó
          if (preciosVenta != null && preciosVenta.containsKey(idProductoConsignacion)) {
            final precioVenta = preciosVenta[idProductoConsignacion]!;
            
            // Obtener el ID del producto duplicado/reutilizado
            final prodConsig = productosConsignacion.firstWhere((p) => p['id'] == idProductoConsignacion);
            final idProductoOriginal = prodConsig['id_producto'] as int;
            final idProductoDuplicado = mapeoProductos[idProductoOriginal]?['id_duplicado'] ?? idProductoOriginal;
            final idVariante = prodConsig['id_variante'] as int?;

            try {
              // Buscar si ya existe precio de venta para este producto (hoy o después)
              final hoy = DateTime.now().toIso8601String().split('T')[0];
              final preciosExistentes = await _supabase
                  .from('app_dat_precio_venta')
                  .select('id')
                  .eq('id_producto', idProductoDuplicado)
                  .eq('fecha_desde', hoy);

              if ((preciosExistentes as List).isNotEmpty) {
                // Actualizar precio existente
                await _supabase
                    .from('app_dat_precio_venta')
                    .update({
                      'precio_venta_cup': precioVenta,
                    })
                    .eq('id_producto', idProductoDuplicado)
                    .eq('fecha_desde', hoy);

                debugPrint('✅ Precio de venta actualizado: Producto $idProductoDuplicado = \$$precioVenta');
              } else {
                // Crear nuevo precio de venta
                await _supabase
                    .from('app_dat_precio_venta')
                    .insert({
                      'id_producto': idProductoDuplicado,
                      'id_variante': idVariante,
                      'precio_venta_cup': precioVenta,
                      'fecha_desde': hoy,
                    });

                debugPrint('✅ Precio de venta creado: Producto $idProductoDuplicado = \$$precioVenta');
              }
            } catch (e) {
              debugPrint('⚠️ Error configurando precio de venta: $e');
            }
          }
        } catch (e) {
          debugPrint('⚠️ Error actualizando producto consignación: $e');
        }
      }

      debugPrint('✅ Recepción de productos confirmada exitosamente');
      return true;
    } catch (e) {
      debugPrint('❌ Error confirmando recepción: $e');
      return false;
    }
  }

  /// Crear operaciones de auditoría (UNA extracción y UNA recepción para todos los productos)
  /// mapeoProductos: {id_producto_original: {id_original: int, id_duplicado: int}}
  /// preciosVenta: {idProductoConsignacion: precioVenta}
  static Future<bool> crearOperacionesAuditoria({
    required int idTiendaOrigen,
    required int idTiendaDestino,
    required int idAlmacenOrigen,
    required int idAlmacenDestino,
    required int idZonaDestino,
    required List<Map<String, dynamic>> productos,
    Map<int, Map<String, int>>? mapeoProductos,
    Map<int, double>? preciosVenta,
    List<int>? idsProductosConsignacion,
  }) async {
    try {
      debugPrint('📊 Creando operaciones de auditoría consolidadas...');

      // Tipo de operación: 7 = Extracción, 1 = Recepción
      // Estado: 1 = Pendiente
      const int tipoOperacionExtraccion = 7;
      const int tipoOperacionRecepcion = 1;
      const int estadoPendiente = 1;

      // ===== CREAR UNA SOLA OPERACIÓN DE EXTRACCIÓN =====
      debugPrint('📤 Creando operación de extracción para ${productos.length} producto(s)');
      
      int? idOperacionExtraccion;
      try {
        // 1. Crear operación base en app_dat_operaciones (EXTRACCIÓN)
        final operacionExtraccion = await _supabase
            .from('app_dat_operaciones')
            .insert({
              'id_tipo_operacion': tipoOperacionExtraccion,
              'id_tienda': idTiendaOrigen,
              'observaciones': 'Extracción en consignación - ${productos.length} producto(s)',
            })
            .select()
            .single();

        idOperacionExtraccion = operacionExtraccion['id'] as int;
        debugPrint('✅ Operación extracción creada: $idOperacionExtraccion');

        // 2. Guardar estado de la operación en app_dat_estado_operacion
        try {
          await _supabase
              .from('app_dat_estado_operacion')
              .insert({
                'id_operacion': idOperacionExtraccion,
                'estado': estadoPendiente,
                'comentario': 'Operación de extracción en consignación creada',
              });
          debugPrint('✅ Estado de extracción guardado: Pendiente');
        } catch (e) {
          debugPrint('⚠️ Error guardando estado de extracción: $e');
        }

        // 3. Registrar extracción en app_dat_operacion_extraccion
        try {
          await _supabase
              .from('app_dat_operacion_extraccion')
              .insert({
                'id_operacion': idOperacionExtraccion,
                'id_motivo_operacion': 7, // Motivo: Extracción
                'observaciones': 'Transferencia en consignación',
              });
          debugPrint('✅ Registro de extracción guardado');
        } catch (e) {
          debugPrint('⚠️ Error registrando extracción: $e');
        }
      } catch (e) {
        debugPrint('❌ Error en operación de extracción: $e');
        return false;
      }

      // ===== REGISTRAR TODOS LOS PRODUCTOS EN LA EXTRACCIÓN =====
      // Usar la ubicación guardada en cada producto (id_ubicacion_origen)
      // Si no existe, usar la primera ubicación del almacén origen (fallback)
      // ✅ NUEVO: Guardar ID de operación de extracción en cada producto
      
      for (int i = 0; i < productos.length; i++) {
        final producto = productos[i];
        final cantidad = (producto['cantidad_enviada'] ?? producto['cantidad'] ?? 0).toDouble();
        // En EXTRACCIÓN usamos el producto ORIGINAL
        final idProductoOriginal = producto['id_producto'] as int;
        final idProductoConsignacion = idsProductosConsignacion?[i] ?? 0;
        var idPresentacion = producto['id_presentacion'] as int?;
        var idUbicacionOrigen = producto['id_ubicacion_origen'] as int?;

        // Si no hay ubicación guardada, obtener la primera del almacén origen (fallback)
        if (idUbicacionOrigen == null) {
          debugPrint('⚠️ Producto $idProductoOriginal sin ubicación guardada, buscando fallback...');
          try {
            final ubicacionFallback = await _supabase
                .from('app_dat_layout_almacen')
                .select('id')
                .eq('id_almacen', idAlmacenOrigen)
                .limit(1);
            
            if ((ubicacionFallback as List).isNotEmpty) {
              idUbicacionOrigen = ubicacionFallback[0]['id'] as int;
              debugPrint('✅ Ubicación fallback encontrada: $idUbicacionOrigen');
            }
          } catch (e) {
            debugPrint('⚠️ Error obteniendo ubicación fallback: $e');
          }
        }

        // Si no hay id_presentacion, obtenerlo del producto original
        if (idPresentacion == null) {
          try {
            final presentacionResponse = await _supabase
                .from('app_dat_producto_presentacion')
                .select('id')
                .eq('id_producto', idProductoOriginal)
                .limit(1);
            
            if ((presentacionResponse as List).isNotEmpty) {
              idPresentacion = presentacionResponse[0]['id'] as int;
            }
          } catch (e) {
            debugPrint('⚠️ Error obteniendo presentación: $e');
          }
        }

        // Registrar producto extraído en app_dat_extraccion_productos (PRODUCTO ORIGINAL)
        if (idUbicacionOrigen != null) {
          try {
            await _supabase
                .from('app_dat_extraccion_productos')
                .insert({
                  'id_operacion': idOperacionExtraccion,
                  'id_producto': idProductoOriginal,
                  'id_ubicacion': idUbicacionOrigen,
                  'id_presentacion': idPresentacion,
                  'cantidad': cantidad,
                });
            debugPrint('✅ Producto extraído registrado: $idProductoOriginal desde ubicación $idUbicacionOrigen');
            
            // ✅ NUEVO: Guardar ID de operación de extracción en producto_consignacion
            if (idProductoConsignacion > 0) {
              try {
                await _supabase
                    .from('app_dat_producto_consignacion')
                    .update({'id_operacion_extraccion': idOperacionExtraccion})
                    .eq('id', idProductoConsignacion);
                debugPrint('✅ ID de operación de extracción guardado en producto_consignacion: $idProductoConsignacion');
              } catch (e) {
                debugPrint('⚠️ Error guardando ID de operación de extracción: $e');
              }
            }
          } catch (e) {
            debugPrint('❌ Error registrando producto extraído: $e');
          }
        } else {
          debugPrint('❌ No se pudo registrar producto extraído: ubicación no disponible');
        }
      }

      // ===== CREAR UNA SOLA OPERACIÓN DE RECEPCIÓN =====
      debugPrint('📥 Creando operación de recepción para ${productos.length} producto(s)');
      
      int? idOperacionRecepcion;
      try {
        // 5. Crear operación base en app_dat_operaciones (RECEPCIÓN)
        final operacionRecepcion = await _supabase
            .from('app_dat_operaciones')
            .insert({
              'id_tipo_operacion': tipoOperacionRecepcion,
              'id_tienda': idTiendaDestino,
              'observaciones': 'Recepción en consignación - ${productos.length} producto(s)',
            })
            .select()
            .single();

        idOperacionRecepcion = operacionRecepcion['id'] as int;
        debugPrint('✅ Operación recepción creada: $idOperacionRecepcion');

        // 6. Guardar estado de la operación en app_dat_estado_operacion
        try {
          await _supabase
              .from('app_dat_estado_operacion')
              .insert({
                'id_operacion': idOperacionRecepcion,
                'estado': estadoPendiente,
                'comentario': 'Operación de recepción en consignación creada',
              });
          debugPrint('✅ Estado de recepción guardado: Pendiente');
        } catch (e) {
          debugPrint('⚠️ Error guardando estado de recepción: $e');
        }

        // 7. Registrar recepción en app_dat_operacion_recepcion
        try {
          await _supabase
              .from('app_dat_operacion_recepcion')
              .insert({
                'id_operacion': idOperacionRecepcion,
                'recibido_por': 'Sistema',
                'motivo': 1, // Motivo por defecto
                'observaciones': 'Recepción en consignación',
              });
          debugPrint('✅ Registro de recepción guardado');
        } catch (e) {
          debugPrint('⚠️ Error registrando recepción: $e');
        }
      } catch (e) {
        debugPrint('❌ Error en operación de recepción: $e');
        return false;
      }

      // ===== REGISTRAR TODOS LOS PRODUCTOS EN LA RECEPCIÓN =====
      // Usar la zona de consignación como ubicación de destino
      // (Los productos se reciben en la zona de consignación del almacén destino)
      // Reutilizar idZonaDestino que ya fue pasado como parámetro
      final int idUbicacionDestino = idZonaDestino;
      debugPrint('✅ Zona de consignación destino: $idUbicacionDestino');
      debugPrint('📋 Mapeo disponible en recepción: ${mapeoProductos?.length ?? 0} entradas');
      if (mapeoProductos != null) {
        for (final entry in mapeoProductos.entries) {
          debugPrint('   ${entry.key} → ${entry.value['id_duplicado']}');
        }
      }

      // ✅ Calcular monto total de la operación
      double montoTotalOperacion = 0.0;

      for (int i = 0; i < productos.length; i++) {
        final producto = productos[i];
        final cantidad = (producto['cantidad_enviada'] ?? producto['cantidad'] ?? 0).toDouble();
        final idProductoOriginal = producto['id_producto'] as int;
        final idProductoConsignacion = idsProductosConsignacion?[i] ?? 0;
        
        // ✅ IMPORTANTE: Obtener el precio que envió el consignador (para precio promedio)
        final precioConsignador = (producto['precio_venta_sugerido'] as num?)?.toDouble() ?? 0.0;
        
        // En RECEPCIÓN usamos el producto DUPLICADO/REUTILIZADO
        final int? idProductoDuplicado;
        if (mapeoProductos != null && mapeoProductos.containsKey(idProductoOriginal)) {
          idProductoDuplicado = mapeoProductos[idProductoOriginal]!['id_duplicado'];
          debugPrint('📍 Usando mapeo: Producto original $idProductoOriginal → Producto recepción $idProductoDuplicado');
        } else {
          idProductoDuplicado = null;
          debugPrint('❌ CRÍTICO: Sin mapeo para producto $idProductoOriginal - NO se registrará recepción');
        }
        
        // ✅ VALIDACIÓN CRÍTICA: Si no hay producto duplicado, saltar este producto
        if (idProductoDuplicado == null) {
          debugPrint('⚠️ Saltando producto $idProductoOriginal: no hay ID de destino disponible');
          continue;
        }
        
        // ✅ IMPORTANTE: SIEMPRE obtener presentación del producto DUPLICADO (tienda destino)
        // NO usar la presentación del producto original, aunque venga en los datos
        int? idPresentacion;
        try {
          final presentacionResponse = await _supabase
              .from('app_dat_producto_presentacion')
              .select('id')
              .eq('id_producto', idProductoDuplicado)
              .limit(1);
          
          if ((presentacionResponse as List).isNotEmpty) {
            idPresentacion = presentacionResponse[0]['id'] as int;
            debugPrint('✅ Presentación obtenida del producto duplicado $idProductoDuplicado: $idPresentacion');
          } else {
            debugPrint('⚠️ No se encontró presentación para producto duplicado $idProductoDuplicado');
          }
        } catch (e) {
          debugPrint('⚠️ Error obteniendo presentación del producto duplicado: $e');
        }

        // Obtener el precio de venta configurado por el consignatario (para guardar en recepción)
        final precioVentaConsignatario = preciosVenta?[idProductoConsignacion] ?? 0.0;

        // ✅ Acumular monto total: precio de venta del consignatario × cantidad
        montoTotalOperacion += precioVentaConsignatario * cantidad;

        // 8. Registrar producto recibido en app_dat_recepcion_productos (PRODUCTO DUPLICADO)
        try {
          await _supabase
              .from('app_dat_recepcion_productos')
              .insert({
                'id_operacion': idOperacionRecepcion,
                'id_producto': idProductoDuplicado,
                'id_ubicacion': idUbicacionDestino,
                'id_presentacion': idPresentacion,
                'cantidad': cantidad,
                'precio_unitario': precioConsignador, // ✅ CORREGIDO: Usar precio del consignador (no del consignatario)
              });

            debugPrint('✅ Producto recibido registrado: $idProductoDuplicado (duplicado de $idProductoOriginal) en zona $idUbicacionDestino');
            debugPrint('   Precio unitario (del consignador): \$$precioConsignador, Cantidad: $cantidad');
            debugPrint('   Subtotal: \$${(precioConsignador * cantidad).toStringAsFixed(2)}');
            debugPrint('   ℹ️ Precio de venta del consignatario: \$$precioVentaConsignatario (se usa para venta, no para precio promedio)');

            // ℹ️ NO actualizar precio promedio en consignación
            // El precio promedio se actualiza solo cuando se venden los productos
            debugPrint('ℹ️ Precio promedio NO se actualiza en consignación (se actualiza al vender)');
            
            // ✅ NUEVO: Guardar ID de operación de recepción en producto_consignacion
            if (idProductoConsignacion > 0) {
              try {
                await _supabase
                    .from('app_dat_producto_consignacion')
                    .update({'id_operacion_recepcion': idOperacionRecepcion})
                    .eq('id', idProductoConsignacion);
                debugPrint('✅ ID de operación de recepción guardado en producto_consignacion: $idProductoConsignacion');
              } catch (e) {
                debugPrint('⚠️ Error guardando ID de operación de recepción: $e');
              }
            }
          } catch (e) {
            debugPrint('❌ Error registrando producto recibido: $e');
          }
      }

      // ℹ️ Nota: El monto total se calcula como suma de (precio_unitario × cantidad) para todos los productos
      // pero no se guarda en app_dat_operaciones (columna no existe)
      debugPrint('✅ Operaciones de auditoría creadas exitosamente (1 extracción + 1 recepción)');
      debugPrint('   Monto total calculado: \$${montoTotalOperacion.toStringAsFixed(2)}');
      debugPrint('   Fórmula: Suma de (precio_unitario × cantidad) para todos los productos');
      return true;
    } catch (e) {
      debugPrint('❌ Error creando operaciones de auditoría: $e');
      return false;
    }
  }

  /// ✅ NUEVO: Actualizar monto_total del contrato después de confirmar productos
  /// Calcula: sum(precio_costo_usd * cantidad_enviada) y lo SUMA al monto_total existente
  static Future<void> actualizarMontoTotalContrato({
    required int contratoId,
    required List<Map<String, dynamic>> productosConfirmados,
  }) async {
    try {
      debugPrint('💰 Actualizando monto_total del contrato $contratoId...');
      
      // Calculate total to add: sum(precio_costo_usd * cantidad_enviada)
      double montoAAgregar = 0.0;
      for (final producto in productosConfirmados) {
        // El precio_costo_usd es el precio configurado por el consignador en USD
        final precioCostoUsd = (producto['precio_costo_usd'] as num?)?.toDouble() ?? 0.0;
        final cantidadEnviada = (producto['cantidad_enviada'] as num?)?.toDouble() ?? 0.0;
        montoAAgregar += precioCostoUsd * cantidadEnviada;
        
        debugPrint('   Producto: ${producto['producto']?['denominacion'] ?? 'N/A'}');
        debugPrint('   Precio costo USD: \$${precioCostoUsd.toStringAsFixed(2)} USD × Cantidad: $cantidadEnviada = \$${(precioCostoUsd * cantidadEnviada).toStringAsFixed(2)} USD');
      }
      
      debugPrint('💰 Monto a agregar al contrato: \$${montoAAgregar.toStringAsFixed(2)}');
      
      // Get current monto_total
      final contratoData = await _supabase
          .from('app_dat_contrato_consignacion')
          .select('monto_total')
          .eq('id', contratoId)
          .single();
      
      final montoActual = (contratoData['monto_total'] as num?)?.toDouble() ?? 0.0;
      final nuevoMonto = montoActual + montoAAgregar;
      
      debugPrint('📊 Monto actual del contrato: \$${montoActual.toStringAsFixed(2)}');
      debugPrint('📊 Nuevo monto total: \$${nuevoMonto.toStringAsFixed(2)}');
      
      // Update contract monto_total (incremental sum)
      await _supabase
          .from('app_dat_contrato_consignacion')
          .update({
            'monto_total': nuevoMonto,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', contratoId);
      
      debugPrint('✅ Monto total del contrato actualizado exitosamente');
    } catch (e) {
      debugPrint('❌ Error actualizando monto total del contrato: $e');
      rethrow;
    }
  }

}
