import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'consignacion_envio_listado_service.dart';

/// Servicio para gestionar envíos de consignación
/// Maneja el ciclo completo: creación, configuración, envío, aceptación/rechazo
class ConsignacionEnvioService {
  static final _supabase = Supabase.instance.client;

  /// Estados de envío
  static const int ESTADO_PROPUESTO = 1;
  static const int ESTADO_CONFIGURADO = 2;
  static const int ESTADO_EN_TRANSITO = 3;
  static const int ESTADO_ACEPTADO = 4;
  static const int ESTADO_RECHAZADO = 5;
  static const int ESTADO_ENTREGADO = 6;

  /// Estados de producto en envío
  static const int PRODUCTO_PROPUESTO = 1;
  static const int PRODUCTO_CONFIGURADO = 2;
  static const int PRODUCTO_ACEPTADO = 3;
  static const int PRODUCTO_RECHAZADO = 4;

  /// Tipos de movimiento
  static const int MOVIMIENTO_CREACION = 1;
  static const int MOVIMIENTO_CONFIGURACION = 2;
  static const int MOVIMIENTO_ENVIO = 3;
  static const int MOVIMIENTO_ACEPTACION = 4;
  static const int MOVIMIENTO_RECHAZO = 5;
  static const int MOVIMIENTO_ENTREGA = 6;
  static const int MOVIMIENTO_MODIFICACION = 7;
  static const int MOVIMIENTO_CANCELACION = 8;

  /// Tipos de envío
  static const int TIPO_ENVIO_DIRECTO = 1;
  static const int TIPO_ENVIO_DEVOLUCION = 2;

  // ============================================================================
  // CREAR ENVÍO CON OPERACIÓN DE EXTRACCIÓN
  // ============================================================================

  /// Crea un envío de consignación con operación de extracción
  /// Se ejecuta al seleccionar productos con cantidades en el primer paso
  static Future<Map<String, dynamic>?> crearEnvio({
    required int idContrato,
    required int idAlmacenOrigen,
    required int idAlmacenDestino,
    required String idUsuario,
    required List<Map<String, dynamic>> productos,
    int? idOperacionExtraccion,
    String? descripcion,
  }) async {
    try {
      debugPrint('📦 Creando envío de consignación...');
      debugPrint('   Contrato: $idContrato');
      debugPrint('   Productos: ${productos.length}');
      debugPrint('   Operación Extracción: $idOperacionExtraccion');

      // Preparar productos en formato JSONB
      // precio_venta: precio de costo para la consignación (configurado por consignador en CUP)
      // precio_costo_usd: precio_venta convertido a USD según tasa vigente
      // precio_costo_cup: precio_venta (precio configurado por consignador)
      // precio_venta_cup: se configura después por el consignatario en ConfirmarRecepcionConsignacionScreen
      // ⭐ NUEVO: Incluye datos originales (presentación, variante, ubicación) para devoluciones
      final productosJson = productos.map((p) {
        final precioVentaCup = (p['precio_venta'] ?? 0.0) as double;
        final tasaCambio = (p['tasa_cambio'] ?? 440.0) as double;
        final precioCostoUsd = tasaCambio > 0 ? precioVentaCup / tasaCambio : 0.0;
        
        return {
          'id_inventario': p['id_inventario'],
          'id_producto': p['id_producto'],
          'cantidad': p['cantidad'],
          'precio_costo_usd': precioCostoUsd, // Precio configurado convertido a USD
          'precio_costo_cup': precioVentaCup, // Precio configurado por consignador
          'precio_venta': precioVentaCup, // Mismo valor para compatibilidad con RPC
          'tasa_cambio': tasaCambio,
          // ⭐ DATOS ORIGINALES (el RPC los obtiene del inventario, pero los pasamos por si acaso)
          'id_presentacion': p['id_presentacion'],
          'id_variante': p['id_variante'],
          'id_ubicacion': p['id_ubicacion'],
        };
      }).toList();
      
      debugPrint('💰 Productos con precios de costo para consignación:');
      for (var p in productosJson) {
        debugPrint('   - ID Producto: ${p['id_producto']}, Cantidad: ${p['cantidad']}, Precio Costo Consignación: ${p['precio_venta']}');
      }

      // Llamar función RPC
      final response = await _supabase.rpc(
        'crear_envio_consignacion',
        params: {
          'p_id_contrato': idContrato,
          'p_id_almacen_origen': idAlmacenOrigen,
          'p_id_almacen_destino': idAlmacenDestino,
          'p_id_usuario': idUsuario,
          'p_productos': productosJson,
          'p_descripcion': descripcion,
          'p_id_operacion_extraccion': idOperacionExtraccion,
        },
      );

      debugPrint('📊 Respuesta del RPC: $response');
      debugPrint('📊 Tipo de respuesta: ${response.runtimeType}');
      
      if (response != null && response is List && response.isNotEmpty) {
        debugPrint('📊 Primer elemento: ${response[0]}');
        debugPrint('📊 Tipo del primer elemento: ${response[0].runtimeType}');
        
        final resultado = response[0] as Map<String, dynamic>;
        debugPrint('📊 Claves del mapa: ${resultado.keys.toList()}');
        debugPrint('📊 Valores del mapa: ${resultado.values.toList()}');
        
        debugPrint('✅ Envío creado exitosamente');
        debugPrint('   ID Envío: ${resultado['id_envio']}');
        debugPrint('   Número: ${resultado['numero_envio']}');
        debugPrint('   ID Operación: ${resultado['id_operacion_extraccion']}');
        return resultado;
      }

      debugPrint('❌ Error: Respuesta vacía al crear envío');
      return null;
    } catch (e) {
      debugPrint('❌ Error creando envío: $e');
      return null;
    }
  }

  // ============================================================================
  // CREAR DEVOLUCIÓN (CONSIGNATARIO -> CONSIGNADOR)
  // ============================================================================

  /// Crea una solicitud de devolución de consignación
  static Future<Map<String, dynamic>?> crearDevolucion({
    required int idContrato,
    required int idAlmacenOrigen,
    required String idUsuario,
    required List<Map<String, dynamic>> productos,
    int? idOperacionExtraccion,
    String? descripcion,
  }) async {
    try {
      debugPrint('🔄 Creando solicitud de devolución...');
      debugPrint('   Operación extracción pre-construida: $idOperacionExtraccion');
      
      // Preparar productos en formato JSONB incluyendo presentación/variante/ubicación
      // para que el RPC pueda almacenarlos y obtener_productos_envio2 los pueda consultar
      final productosJson = productos.map((p) => {
        'id_inventario': p['id_inventario'],
        'id_producto': p['id_producto'],
        'cantidad': p['cantidad'],
        'precio_costo_usd': p['precio_costo_usd'] ?? 0.0,
        'precio_costo_cup': p['precio_costo_cup'] ?? 0.0,
        'tasa_cambio': p['tasa_cambio'] ?? 440.0,
        'id_presentacion': p['id_presentacion'],
        'id_variante': p['id_variante'],
        'id_ubicacion': p['id_ubicacion'],
      }).toList();

      final response = await _supabase.rpc(
        'crear_devolucion_consignacion_v2',
        params: {
          'p_id_contrato': idContrato,
          'p_id_almacen_origen': idAlmacenOrigen,
          'p_id_usuario': idUsuario,
          'p_productos': productosJson,
          'p_descripcion': descripcion,
          'p_id_operacion_extraccion': idOperacionExtraccion,
        },
      );

      if (response != null && response is List && response.isNotEmpty) {
        return response[0] as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error creando devolución: $e');
      return null;
    }
  }

  // ============================================================================
  // APROBAR DEVOLUCIÓN (POR EL CONSIGNADOR)
  // ============================================================================

  /// Aprueba una devolución y define el almacén donde se recibirá
  static Future<Map<String, dynamic>?> aprobarDevolucion({
    required int idEnvio,
    required int idAlmacenRecepcion,
    required String idUsuario,
    int? idZonaRecepcion,
  }) async {
    try {
      debugPrint('✅ Aprobando devolución $idEnvio...');

      final response = await _supabase.rpc(
        'aprobar_devolucion_consignacion_v2',
        params: {
          'p_id_envio': idEnvio,
          'p_id_almacen_recepcion': idAlmacenRecepcion,
          'p_id_usuario': idUsuario,
          if (idZonaRecepcion != null) 'p_id_zona_recepcion': idZonaRecepcion,
        },
      );

      if (response != null && response is List && response.isNotEmpty) {
        return response[0] as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error aprobando devolución: $e');
      return null;
    }
  }

  // ============================================================================
  // ACTUALIZAR PRECIOS DEL ENVÍO
  // ============================================================================

  /// Actualiza los precios de venta de los productos del envío
  /// Se ejecuta en el segundo paso al configurar precios
  static Future<bool> actualizarPrecios({
    required int idEnvio,
    required String idUsuario,
    required List<Map<String, dynamic>> productos,
  }) async {
    try {
      debugPrint('💰 Actualizando precios del envío $idEnvio...');

      // Preparar productos con precios
      final productosJson = productos.map((p) => {
        'id_envio_producto': p['id_envio_producto'],
        'precio_venta_cup': p['precio_venta_cup'],
      }).toList();

      // Llamar función RPC
      final response = await _supabase.rpc(
        'actualizar_precios_envio',
        params: {
          'p_id_envio': idEnvio,
          'p_id_usuario': idUsuario,
          'p_productos': productosJson,
        },
      );

      if (response != null && response is List && response.isNotEmpty) {
        final resultado = response[0] as Map<String, dynamic>;
        final success = resultado['success'] as bool;
        debugPrint(success ? '✅ Precios actualizados' : '❌ Error actualizando precios');
        return success;
      }

      return false;
    } catch (e) {
      debugPrint('❌ Error actualizando precios: $e');
      return false;
    }
  }

  // ============================================================================
  // MARCAR ENVÍO COMO EN TRÁNSITO
  // ============================================================================

  /// Marca el envío como enviado al consignatario
  static Future<bool> marcarEnTransito({
    required int idEnvio,
    required String idUsuario,
  }) async {
    try {
      debugPrint('🚚 Marcando envío $idEnvio como en tránsito...');

      final response = await _supabase.rpc(
        'marcar_envio_en_transito',
        params: {
          'p_id_envio': idEnvio,
          'p_id_usuario': idUsuario,
        },
      );

      if (response != null && response is List && response.isNotEmpty) {
        final resultado = response[0] as Map<String, dynamic>;
        final success = resultado['success'] as bool;
        debugPrint(success ? '✅ Envío marcado en tránsito' : '❌ Error');
        return success;
      }

      return false;
    } catch (e) {
      debugPrint('❌ Error marcando envío en tránsito: $e');
      return false;
    }
  }

  /// Marca el envío como entregado (recepción completada)
  static Future<bool> marcarEntregado({
    required int idEnvio,
    required String idUsuario,
  }) async {
    try {
      debugPrint('🏁 Finalizando envío $idEnvio (marcando como entregado)...');

      // Actualizar estado del envío
      final response = await _supabase
          .from('app_dat_consignacion_envio')
          .update({
            'estado_envio': ESTADO_ENTREGADO,
            'fecha_entrega': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', idEnvio)
          .select();

      if (response.isNotEmpty) {
        // Registrar movimiento
        await _supabase.from('app_dat_consignacion_envio_movimiento').insert({
          'id_envio': idEnvio,
          'id_usuario': idUsuario,
          'tipo_movimiento': MOVIMIENTO_ENTREGA,
          'estado_anterior': ESTADO_ACEPTADO,
          'estado_nuevo': ESTADO_ENTREGADO,
          'descripcion': 'Envío marcado como entregado automáticamente al completar recepción',
        });

        debugPrint('✅ Envío entregado exitosamente');
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('❌ Error finalizando envío: $e');
      return false;
    }
  }

  // ============================================================================
  // ACEPTAR ENVÍO
  // ============================================================================

  /// Acepta el envío completo y crea operaciones de extracción y recepción
  /// Retorna IDs de operaciones guardados ANTES de procesarlas (estado PENDIENTE)
  static Future<Map<String, dynamic>?> aceptarEnvio({
    required int idEnvio,
    required String idUsuario,
    required int idTiendaDestino,
    List<dynamic>? preciosProductos,
  }) async {
    try {
      debugPrint('✅ Aceptando envío completo $idEnvio...');

      final response = await _supabase.rpc(
        'aceptar_envio_consignacion',
        params: {
          'p_id_envio': idEnvio,
          'p_id_usuario': idUsuario,
          'p_precios_productos': preciosProductos ?? [],
        },
      );

      if (response != null && response is List && response.isNotEmpty) {
        final resultado = response[0] as Map<String, dynamic>;
        final success = resultado['success'] as bool?;
        
        if (success == true) {
          final idOperacionExtraccion = resultado['id_operacion_extraccion'] as int?;
          final idOperacionRecepcion = resultado['id_operacion_recepcion'] as int?;
          final mensaje = resultado['mensaje'] as String?;
          
          debugPrint('✅ Envío aceptado exitosamente');
          debugPrint('   ID Operación Extracción: $idOperacionExtraccion (estado: PENDIENTE)');
          debugPrint('   ID Operación Recepción: $idOperacionRecepcion (estado: PENDIENTE)');
          debugPrint('   Mensaje: $mensaje');
          debugPrint('   ℹ️ Operaciones creadas con estado PENDIENTE');
          debugPrint('   ℹ️ La recepción NO se puede completar hasta que la extracción esté completada');
          
          // 2. Configurar precios de venta y precio promedio
          if (idOperacionRecepcion != null && preciosProductos != null && preciosProductos.isNotEmpty) {
            debugPrint('\n💰 Configurando precios de venta y precio promedio...');
            await configurarPreciosRecepcion(
              idOperacionRecepcion: idOperacionRecepcion,
              idTiendaDestino: idTiendaDestino,
              idEnvio: idEnvio,
              preciosProductos: preciosProductos,
            );
          }
        } else {
          debugPrint('❌ Error: ${resultado['mensaje']}');
        }
        
        // Devolvemos el resultado completo sea success true o false
        // para que la UI pueda mostrar el mensaje de error si existe.
        return resultado;
      }

      return null;
    } catch (e) {
      debugPrint('❌ Error aceptando envío: $e');
      return null;
    }
  }

  /// Actualiza precio_venta_cup en app_dat_consignacion_envio_producto
  /// Esto guarda el precio de venta configurado por el consignatario en los detalles del envío
  static Future<void> actualizarPreciosEnvioProductos({
    required int idEnvio,
    required List<dynamic> preciosProductos,
  }) async {
    try {
      debugPrint('💾 Guardando precios de venta en detalles del envío: $idEnvio');
      
      for (final precioData in preciosProductos) {
        final precioMap = precioData as Map<String, dynamic>;
        final idProducto = precioMap['id_producto'] as int?;
        final precioVentaCup = (precioMap['precio_venta_cup'] as num?)?.toDouble() ?? 0.0;
        
        if (idProducto != null && precioVentaCup > 0) {
          await _supabase
              .from('app_dat_consignacion_envio_producto')
              .update({'precio_venta_cup': precioVentaCup})
              .eq('id_envio', idEnvio)
              .eq('id_producto', idProducto);
          
          debugPrint('✅ Precio de venta actualizado: Producto $idProducto = \$$precioVentaCup CUP');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error actualizando precios en detalles del envío: $e');
    }
  }

  /// Configura precios de venta (CUP) y precio promedio (USD) después de aceptar envío
  /// También actualiza el estado del envío a CONFIGURADO
  static Future<Map<String, dynamic>?> configurarPreciosRecepcion({
    required int idOperacionRecepcion,
    required int idTiendaDestino,
    required int idEnvio,
    required List<dynamic> preciosProductos,
  }) async {
    try {
      debugPrint('💰 Configurando precios para operación de recepción: $idOperacionRecepcion');

      // ✅ NUEVO: Guardar precios en detalles del envío
      await actualizarPreciosEnvioProductos(
        idEnvio: idEnvio,
        preciosProductos: preciosProductos,
      );

      final response = await _supabase.rpc(
        'configurar_precios_recepcion_consignacion',
        params: {
          'p_id_operacion_recepcion': idOperacionRecepcion,
          'p_id_tienda_destino': idTiendaDestino,
          'p_precios_productos': preciosProductos,
        },
      );

      if (response != null && response is List && response.isNotEmpty) {
        final resultado = response[0] as Map<String, dynamic>;
        final success = resultado['success'] as bool?;
        
        if (success == true) {
          final preciosConfigurados = resultado['precios_configurados'] as int?;
          final mensaje = resultado['mensaje'] as String?;
          
          debugPrint('✅ Precios configurados exitosamente');
          debugPrint('   Productos: $preciosConfigurados');
          debugPrint('   Mensaje: $mensaje');
          debugPrint('   ✅ app_dat_precio_venta actualizado (CUP)');
          debugPrint('   ✅ app_dat_producto_presentacion.precio_promedio actualizado (USD, promedio ponderado)');
          
          // Actualizar estado del envío a CONFIGURADO (2)
          final estadoActualizado = await ConsignacionEnvioListadoService.actualizarEstadoEnvio(
            idEnvio,
            ConsignacionEnvioListadoService.ESTADO_CONFIGURADO,
          );
          
          if (estadoActualizado) {
            debugPrint('✅ Estado del envío actualizado a CONFIGURADO');
          } else {
            debugPrint('⚠️ No se pudo actualizar el estado del envío');
          }
          
          return resultado;
        } else {
          debugPrint('⚠️ Error configurando precios: ${resultado['mensaje']}');
        }
      }

      return null;
    } catch (e) {
      debugPrint('⚠️ Error configurando precios: $e');
      // No lanzar excepción, solo log (no debe bloquear la aceptación del envío)
      return null;
    }
  }

  /// Acepta productos seleccionados y rechaza/elimina los demás
  /// Los productos rechazados se eliminan del envío y se devuelve el stock
  static Future<Map<String, dynamic>?> aceptarEnvioParcial({
    required int idEnvio,
    required String idUsuario,
    required List<int> idsProductosAceptados,
  }) async {
    try {
      debugPrint('✅ Aceptando envío parcial $idEnvio...');
      debugPrint('   Productos aceptados: ${idsProductosAceptados.length}');

      // Preparar productos aceptados en formato JSONB
      final productosJson = idsProductosAceptados.map((id) => {
        'id_envio_producto': id,
      }).toList();

      final response = await _supabase.rpc(
        'aceptar_envio_consignacion_parcial',
        params: {
          'p_id_envio': idEnvio,
          'p_id_usuario': idUsuario,
          'p_productos_aceptados': productosJson,
        },
      );

      if (response != null && response is List && response.isNotEmpty) {
        final resultado = response[0] as Map<String, dynamic>;
        final success = resultado['success'] as bool;
        
        if (success) {
          debugPrint('✅ Envío procesado exitosamente');
          debugPrint('   Productos aceptados: ${resultado['productos_aceptados']}');
          debugPrint('   Productos rechazados: ${resultado['productos_rechazados']}');
          debugPrint('   ID Operación Recepción: ${resultado['id_operacion_recepcion']}');
          return resultado;
        } else {
          debugPrint('❌ Error: ${resultado['mensaje']}');
        }
      }

      return null;
    } catch (e) {
      debugPrint('❌ Error aceptando envío parcial: $e');
      return null;
    }
  }

  /// Obtiene productos del envío para aceptación
  static Future<List<Map<String, dynamic>>> obtenerProductosParaAceptacion(
    int idEnvio,
  ) async {
    try {
      final response = await _supabase.rpc(
        'obtener_productos_envio_para_aceptacion',
        params: {'p_id_envio': idEnvio},
      );

      if (response != null && response is List) {
        return List<Map<String, dynamic>>.from(response);
      }

      return [];
    } catch (e) {
      debugPrint('❌ Error obteniendo productos para aceptación: $e');
      return [];
    }
  }

  // ============================================================================
  // RECHAZAR ENVÍO
  // ============================================================================

  /// Rechaza el envío y revierte la operación de extracción
  static Future<bool> rechazarEnvio({
    required int idEnvio,
    required String idUsuario,
    required String motivoRechazo,
  }) async {
    try {
      debugPrint('❌ Rechazando envío $idEnvio...');
      debugPrint('   Motivo: $motivoRechazo');

      final response = await _supabase.rpc(
        'rechazar_envio_consignacion',
        params: {
          'p_id_envio': idEnvio,
          'p_id_usuario': idUsuario,
          'p_motivo_rechazo': motivoRechazo,
        },
      );

      if (response != null && response is List && response.isNotEmpty) {
        final resultado = response[0] as Map<String, dynamic>;
        final success = resultado['success'] as bool;
        final mensaje = resultado['mensaje'] as String? ?? '';
        
        if (success) {
          debugPrint('✅ Envío rechazado con éxito: $mensaje');
        } else {
          debugPrint('❌ Error rechazando envío: $mensaje');
        }
        return success;
      }

      return false;
    } catch (e) {
      debugPrint('❌ Error excepcion rechazando envío: $e');
      return false;
    }
  }

  /// Rechaza un producto individual del envío
  static Future<Map<String, dynamic>> rechazarProductoEnvio({
    required int idEnvio,
    required int idEnvioProducto,
    required String idUsuario,
    required String motivoRechazo,
  }) async {
    try {
      debugPrint('❌ Rechazando producto $idEnvioProducto del envío $idEnvio...');

      final response = await _supabase.rpc(
        'rechazar_producto_envio_consignacion2',
        params: {
          'p_id_envio': idEnvio,
          'p_id_envio_producto': idEnvioProducto,
          'p_id_usuario': idUsuario,
          'p_motivo_rechazo': motivoRechazo,
        },
      );

      if (response != null && response is List && response.isNotEmpty) {
        final resultado = response[0] as Map<String, dynamic>;
        final success = resultado['success'] as bool;
        final mensaje = resultado['mensaje'] as String? ?? '';
        
        if (success) {
          debugPrint('✅ Producto rechazado con éxito: $mensaje');
        } else {
          debugPrint('❌ Error rechazando producto: $mensaje');
        }
        return {'success': success, 'mensaje': mensaje};
      }

      return {'success': false, 'mensaje': 'Sin respuesta del servidor'};
    } catch (e) {
      debugPrint('❌ Error excepcion rechazando producto: $e');
      return {'success': false, 'mensaje': e.toString()};
    }
  }

  // ============================================================================
  // CONSULTAS
  // ============================================================================

  /// Obtiene todos los envíos de un contrato
  static Future<List<Map<String, dynamic>>> obtenerEnviosPorContrato(
    int idContrato,
  ) async {
    try {
      final response = await _supabase.rpc(
        'obtener_envios_por_contrato',
        params: {'p_id_contrato': idContrato},
      );

      if (response != null && response is List) {
        return List<Map<String, dynamic>>.from(response);
      }

      return [];
    } catch (e) {
      debugPrint('❌ Error obteniendo envíos: $e');
      return [];
    }
  }

  /// Obtiene el detalle completo de un envío
  static Future<Map<String, dynamic>?> obtenerDetalleEnvio(
    int idEnvio,
  ) async {
    try {
      final response = await _supabase.rpc(
        'obtener_detalle_envio',
        params: {'p_id_envio': idEnvio},
      );

      if (response != null && response is List && response.isNotEmpty) {
        return response[0] as Map<String, dynamic>;
      }

      return null;
    } catch (e) {
      debugPrint('❌ Error obteniendo detalle de envío: $e');
      return null;
    }
  }

  /// Obtiene el historial de movimientos de un envío
  static Future<List<Map<String, dynamic>>> obtenerHistorialEnvio(
    int idEnvio,
  ) async {
    try {
      final response = await _supabase.rpc(
        'obtener_historial_envio',
        params: {'p_id_envio': idEnvio},
      );

      if (response != null && response is List) {
        return List<Map<String, dynamic>>.from(response);
      }

      return [];
    } catch (e) {
      debugPrint('❌ Error obteniendo historial: $e');
      return [];
    }
  }

  /// Obtiene los productos de un envío con detalles
  static Future<List<Map<String, dynamic>>> obtenerProductosEnvio(
    int idEnvio,
  ) async {
    try {
      debugPrint('📦 Obteniendo productos del envío: $idEnvio');
      
      final response = await _supabase.rpc(
        'obtener_productos_envio2',
        params: {
          'p_id_envio': idEnvio,
        },
      );

      if (response == null) {
        debugPrint('⚠️ Respuesta nula');
        return [];
      }
      
      final productos = List<Map<String, dynamic>>.from(response as List);
      debugPrint('✅ Productos obtenidos: ${productos.length}');
      
      // Logging de los campos retornados
      if (productos.isNotEmpty) {
        debugPrint('📋 Campos del primer producto: ${productos[0].keys.toList()}');
      }
      
      return productos;
    } catch (e) {
      debugPrint('❌ Error obteniendo productos del envío: $e');
      return [];
    }
  }

  /// Obtiene envíos pendientes de aceptación para una tienda consignataria
  static Future<List<Map<String, dynamic>>> obtenerEnviosPendientes(
    int idTienda,
  ) async {
    try {
      final response = await _supabase
          .from('v_consignacion_envios')
          .select()
          .eq('id_tienda_consignataria', idTienda)
          .eq('estado_envio', ESTADO_EN_TRANSITO)
          .order('fecha_envio', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ Error obteniendo envíos pendientes: $e');
      return [];
    }
  }

  /// Obtiene envíos por estado
  static Future<List<Map<String, dynamic>>> obtenerEnviosPorEstado({
    required int idContrato,
    required int estado,
  }) async {
    try {
      final response = await _supabase
          .from('v_consignacion_envios')
          .select()
          .eq('id_contrato_consignacion', idContrato)
          .eq('estado_envio', estado)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ Error obteniendo envíos por estado: $e');
      return [];
    }
  }

  // ============================================================================
  // UTILIDADES
  // ============================================================================

  /// Convierte código de estado a texto legible
  static String obtenerTextoEstado(int estado) {
    switch (estado) {
      case ESTADO_PROPUESTO:
        return 'PROPUESTO';
      case ESTADO_CONFIGURADO:
        return 'CONFIGURADO';
      case ESTADO_EN_TRANSITO:
        return 'EN TRÁNSITO';
      case ESTADO_ACEPTADO:
        return 'ACEPTADO';
      case ESTADO_RECHAZADO:
        return 'RECHAZADO';
      case ESTADO_ENTREGADO:
        return 'ENTREGADO';
      default:
        return 'DESCONOCIDO';
    }
  }

  /// Convierte código de estado de producto a texto
  static String obtenerTextoEstadoProducto(int estado) {
    switch (estado) {
      case PRODUCTO_PROPUESTO:
        return 'PROPUESTO';
      case PRODUCTO_CONFIGURADO:
        return 'CONFIGURADO';
      case PRODUCTO_ACEPTADO:
        return 'ACEPTADO';
      case PRODUCTO_RECHAZADO:
        return 'RECHAZADO';
      default:
        return 'DESCONOCIDO';
    }
  }

  /// Obtiene color según estado del envío
  static String obtenerColorEstado(int estado) {
    switch (estado) {
      case ESTADO_PROPUESTO:
        return '#FFA500'; // Naranja
      case ESTADO_CONFIGURADO:
        return '#2196F3'; // Azul
      case ESTADO_EN_TRANSITO:
        return '#9C27B0'; // Púrpura
      case ESTADO_ACEPTADO:
        return '#4CAF50'; // Verde
      case ESTADO_RECHAZADO:
        return '#F44336'; // Rojo
      case ESTADO_ENTREGADO:
        return '#00BCD4'; // Cian
      default:
        return '#9E9E9E'; // Gris
    }
  }
}
