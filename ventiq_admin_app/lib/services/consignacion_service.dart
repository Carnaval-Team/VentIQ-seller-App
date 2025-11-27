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

        enrichedContratos.add({
          ...contrato,
          'tienda_consignadora': tiendaConsignadora,
          'tienda_consignataria': tiendaConsignataria,
        });
      }

      return enrichedContratos;
    } catch (e) {
      debugPrint('❌ Error obteniendo contratos: $e');
      return [];
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
        debugPrint('⚠️ RPC no disponible, usando query alternativa: $rpcError');

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
          .select('cantidad_enviada, cantidad_vendida, cantidad_devuelta')
          .eq('id', idProductoConsignacion)
          .single();

      final cantidadEnviada = (prodConsig['cantidad_enviada'] as num).toDouble();
      final cantidadVendida = (prodConsig['cantidad_vendida'] as num).toDouble();
      final cantidadDevuelta = (prodConsig['cantidad_devuelta'] as num).toDouble();

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
  static Future<bool> asignarProductos({
    required int idContrato,
    required List<Map<String, dynamic>> productos,
    int? idAlmacenOrigen,
    int? idTiendaOrigen,
    int? idTiendaDestino,
    String? nombreTiendaConsignadora,
    int? idAlmacenDestino,
  }) async {
    try {
      debugPrint('📦 Asignando ${productos.length} productos al contrato $idContrato...');

      // Obtener datos del contrato si se proporcionan
      Map<String, dynamic>? contrato;
      if (idAlmacenOrigen == null || idTiendaOrigen == null || idTiendaDestino == null) {
        contrato = await _supabase
            .from('app_dat_contrato_consignacion')
            .select('id_tienda_consignadora, id_tienda_consignataria, id_almacen_destino, app_dat_tienda!id_tienda_consignadora(denominacion)')
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

      // Obtener o crear zona de consignación (solo en almacén destino)
      final zona = await obtenerOCrearZonaConsignacion(
        idContrato: idContrato,
        idAlmacenDestino: idAlmacenDestino,
        idTiendaConsignadora: idTiendaOrigen!,
        idTiendaConsignataria: idTiendaDestino!,
        nombreTiendaConsignadora: nombreTiendaConsignadora ?? 'Tienda',
      );

      if (zona == null) {
        debugPrint('❌ Error: No se pudo crear la zona de consignación');
        return false;
      }

      final idZonaDestino = zona['id'] as int;

      // Asignar productos al contrato con estado PENDIENTE
      for (var producto in productos) {
        final productoData = {
          'id_contrato': idContrato,
          'id_producto': producto['id_producto'],
          'id_variante': producto['id_variante'],
          'id_presentacion': producto['id_presentacion'],
          'id_ubicacion_origen': producto['id_ubicacion'], // Guardar ubicación de origen
          'cantidad_enviada': producto['cantidad'],
          'precio_venta_sugerido': producto['precio_venta_sugerido'],
          'puede_modificar_precio': producto['puede_modificar_precio'] ?? false,
          'estado': 0, // PENDIENTE - Esperando confirmación del consignatario
        };

        // Insertar producto en consignación
        final prodConsig = await _supabase
            .from('app_dat_producto_consignacion')
            .insert(productoData)
            .select()
            .single();

        debugPrint('✅ Producto consignación creado (Pendiente): ${prodConsig['id']}');
        debugPrint('   Ubicación origen: ${producto['id_ubicacion']}');
      }

      debugPrint('✅ Productos asignados exitosamente (Estado: Pendiente)');
      return true;
    } catch (e) {
      debugPrint('❌ Error asignando productos: $e');
      return false;
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

      // Obtener un tipo de layout válido (usar el primero disponible)
      int? idTipoLayout;
      try {
        final tiposLayout = await _supabase
            .from('app_nom_tipo_layout_almacen')
            .select('id')
            .limit(1);
        
        if ((tiposLayout as List).isNotEmpty) {
          idTipoLayout = tiposLayout[0]['id'] as int;
        }
      } catch (e) {
        debugPrint('⚠️ Error obteniendo tipo de layout: $e');
      }

      if (idTipoLayout == null) {
        debugPrint('❌ Error: No hay tipos de layout disponibles');
        return null;
      }

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
        debugPrint('📝 Creando nueva zona de recepción: $nombreZona');
        
        final nuevaZonaDestino = await _supabase
            .from('app_dat_layout_almacen')
            .insert({
              'id_almacen': idAlmacenDestino,
              'id_tipo_layout': idTipoLayout,
              'denominacion': nombreZona,
            })
            .select()
            .single();

        debugPrint('✅ Zona de recepción creada: ${nuevaZonaDestino['id']}');
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

      // Obtener datos de los productos en consignación (incluyendo ubicación de origen)
      final productosConsignacion = await _supabase
          .from('app_dat_producto_consignacion')
          .select('id, id_producto, id_presentacion, cantidad_enviada, id_ubicacion_origen')
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
  static Future<bool> crearOperacionesAuditoria({
    required int idTiendaOrigen,
    required int idTiendaDestino,
    required int idAlmacenOrigen,
    required int idAlmacenDestino,
    required int idZonaDestino,
    required List<Map<String, dynamic>> productos,
    Map<int, Map<String, int>>? mapeoProductos,
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
      
      for (final producto in productos) {
        final cantidad = (producto['cantidad_enviada'] ?? producto['cantidad'] ?? 0).toDouble();
        // En EXTRACCIÓN usamos el producto ORIGINAL
        final idProductoOriginal = producto['id_producto'] as int;
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

      for (final producto in productos) {
        final cantidad = (producto['cantidad_enviada'] ?? producto['cantidad'] ?? 0).toDouble();
        final idProductoOriginal = producto['id_producto'] as int;
        
        // En RECEPCIÓN usamos el producto DUPLICADO/REUTILIZADO
        final int idProductoDuplicado;
        if (mapeoProductos != null && mapeoProductos.containsKey(idProductoOriginal)) {
          idProductoDuplicado = mapeoProductos[idProductoOriginal]!['id_duplicado'] ?? idProductoOriginal;
          debugPrint('📍 Usando mapeo: Producto original $idProductoOriginal → Producto recepción $idProductoDuplicado');
        } else {
          idProductoDuplicado = idProductoOriginal; // Fallback al original si no hay mapeo
          debugPrint('⚠️ Sin mapeo para producto $idProductoOriginal, usando original como fallback');
        }
        
        var idPresentacion = producto['id_presentacion'] as int?;

        // Si no hay id_presentacion, obtenerlo del producto duplicado
        if (idPresentacion == null) {
          try {
            final presentacionResponse = await _supabase
                .from('app_dat_producto_presentacion')
                .select('id')
                .eq('id_producto', idProductoDuplicado)
                .limit(1);
            
            if ((presentacionResponse as List).isNotEmpty) {
              idPresentacion = presentacionResponse[0]['id'] as int;
            }
          } catch (e) {
            debugPrint('⚠️ Error obteniendo presentación: $e');
          }
        }

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
              });
            debugPrint('✅ Producto recibido registrado: $idProductoDuplicado (duplicado de $idProductoOriginal) en zona $idUbicacionDestino');
          } catch (e) {
            debugPrint('❌ Error registrando producto recibido: $e');
          }
      }

      debugPrint('✅ Operaciones de auditoría creadas exitosamente (1 extracción + 1 recepción)');
      return true;
    } catch (e) {
      debugPrint('❌ Error creando operaciones de auditoría: $e');
      return false;
    }
  }
}
