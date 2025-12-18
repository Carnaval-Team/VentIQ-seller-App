import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    String? descripcion,
  }) async {
    try {
      debugPrint('📦 Creando envío de consignación...');
      debugPrint('   Contrato: $idContrato');
      debugPrint('   Productos: ${productos.length}');

      // Preparar productos en formato JSONB
      final productosJson = productos.map((p) => {
        'id_inventario': p['id_inventario'],
        'id_producto': p['id_producto'],
        'cantidad': p['cantidad'],
        'precio_costo_usd': p['precio_costo_usd'] ?? 0.0,
        'precio_costo_cup': p['precio_costo_cup'] ?? 0.0,
        'tasa_cambio': p['tasa_cambio'] ?? 440.0,
      }).toList();

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
        },
      );

      if (response != null && response is List && response.isNotEmpty) {
        final resultado = response[0] as Map<String, dynamic>;
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

  // ============================================================================
  // ACEPTAR ENVÍO
  // ============================================================================

  /// Acepta el envío completo y crea la operación de recepción
  static Future<Map<String, dynamic>?> aceptarEnvio({
    required int idEnvio,
    required String idUsuario,
  }) async {
    try {
      debugPrint('✅ Aceptando envío completo $idEnvio...');

      final response = await _supabase.rpc(
        'aceptar_envio_consignacion',
        params: {
          'p_id_envio': idEnvio,
          'p_id_usuario': idUsuario,
        },
      );

      if (response != null && response is List && response.isNotEmpty) {
        final resultado = response[0] as Map<String, dynamic>;
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
        debugPrint(success ? '✅ Envío rechazado y stock devuelto' : '❌ Error');
        return success;
      }

      return false;
    } catch (e) {
      debugPrint('❌ Error rechazando envío: $e');
      return false;
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

  /// Obtiene los productos de un envío desde la vista
  static Future<List<Map<String, dynamic>>> obtenerProductosEnvio(
    int idEnvio,
  ) async {
    try {
      final response = await _supabase
          .from('v_consignacion_envio_productos')
          .select()
          .eq('id_envio', idEnvio)
          .order('producto_nombre');

      return List<Map<String, dynamic>>.from(response);
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
