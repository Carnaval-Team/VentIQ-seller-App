import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/store.dart';

class ConsignacionService {
  static final _supabase = Supabase.instance.client;

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

  /// Obtener productos en consignación de un contrato
  static Future<List<Map<String, dynamic>>> getProductosConsignacion(int idContrato) async {
    try {
      debugPrint('📦 Obteniendo productos en consignación para contrato: $idContrato');

      final response = await _supabase
          .from('app_dat_producto_consignacion')
          .select('*')
          .eq('id_contrato', idContrato)
          .eq('estado', 1)
          .order('created_at', ascending: false);

      debugPrint('✅ Productos obtenidos: ${response.length}');

      // Enriquecer con datos de productos
      final List<Map<String, dynamic>> enrichedProductos = [];
      for (var prodConsig in response) {
        final idProducto = prodConsig['id_producto'];

        // Obtener datos del producto
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
      debugPrint('❌ Error obteniendo productos en consignación: $e');
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

      for (var contrato in contratos) {
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
      }

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

  /// Crear un nuevo contrato de consignación
  static Future<Map<String, dynamic>?> crearContrato({
    required int idTiendaConsignadora,
    required int idTiendaConsignataria,
    required double porcentajeComision,
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

  /// Asignar productos a un contrato de consignación
  static Future<bool> asignarProductos({
    required int idContrato,
    required List<Map<String, dynamic>> productos,
  }) async {
    try {
      debugPrint('📦 Asignando ${productos.length} productos al contrato $idContrato...');

      for (var producto in productos) {
        final productoData = {
          'id_contrato': idContrato,
          'id_producto': producto['id_producto'],
          'id_variante': producto['id_variante'],
          'id_presentacion': producto['id_presentacion'],
          'cantidad_enviada': producto['cantidad'],
          'precio_venta_sugerido': producto['precio_venta_sugerido'],
          'estado': 1, // Activo
        };

        // Insertar producto en consignación
        final prodConsig = await _supabase
            .from('app_dat_producto_consignacion')
            .insert(productoData)
            .select()
            .single();

        // Registrar movimiento de envío
        await _supabase.from('app_dat_movimiento_consignacion').insert({
          'id_producto_consignacion': prodConsig['id'],
          'tipo_movimiento': 1, // Envío
          'cantidad': producto['cantidad'],
          'observaciones': 'Envío inicial de producto en consignación',
        });
      }

      debugPrint('✅ Productos asignados exitosamente');
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
}
