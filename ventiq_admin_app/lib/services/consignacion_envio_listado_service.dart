import 'package:supabase_flutter/supabase_flutter.dart';

class ConsignacionEnvioListadoService {
  static final _supabase = Supabase.instance.client;

  // Estados de envío
  static const int ESTADO_PROPUESTO = 1;
  static const int ESTADO_CONFIGURADO = 2;
  static const int ESTADO_EN_TRANSITO = 3;
  static const int ESTADO_ACEPTADO = 4;
  static const int ESTADO_RECHAZADO = 5;
  static const int ESTADO_PARCIALMENTE_ACEPTADO = 6;

  // Estados de producto
  static const int ESTADO_PRODUCTO_PROPUESTO = 1;
  static const int ESTADO_PRODUCTO_CONFIGURADO = 2;
  static const int ESTADO_PRODUCTO_ACEPTADO = 3;
  static const int ESTADO_PRODUCTO_RECHAZADO = 4;

  /// Obtiene lista de envíos con filtros opcionales y totales calculados
  static Future<List<Map<String, dynamic>>> obtenerEnvios({
    int? idContrato,
    int? estadoEnvio,
    int? idTienda,
  }) async {
    try {
      print('🔍 Obteniendo envíos con filtros: idContrato=$idContrato, estadoEnvio=$estadoEnvio, idTienda=$idTienda');
      
      final response = await _supabase.rpc(
        'obtener_envios_consignacion_con_totales',
        params: {
          'p_id_contrato': idContrato,
          'p_estado_envio': estadoEnvio,
          'p_id_tienda': idTienda,
        },
      );

      print('📦 Respuesta RPC recibida: ${response?.runtimeType}');
      if (response == null) {
        print('⚠️ Respuesta nula');
        return [];
      }
      
      final envios = List<Map<String, dynamic>>.from(response as List);
      print('✅ Envíos obtenidos: ${envios.length}');
      
      // Logging detallado de cada envío
      for (var i = 0; i < envios.length; i++) {
        final envio = envios[i];
        print('📋 Envío $i:');
        print('   - ID: ${envio['id_envio']}');
        print('   - Número: ${envio['numero_envio']}');
        print('   - Estado: ${envio['estado_envio_texto']}');
        print('   - Cantidad Productos: ${envio['cantidad_productos']}');
        print('   - Cantidad Total Unidades: ${envio['cantidad_total_unidades']}');
        print('   - Valor Total Costo: ${envio['valor_total_costo']}');
      }
      
      return envios;
    } catch (e) {
      print('❌ Error obteniendo envíos: $e');
      rethrow;
    }
  }

  /// Obtiene envíos por estado con totales calculados
  static Future<List<Map<String, dynamic>>> obtenerEnviosPorEstado(
    int estadoEnvio,
  ) async {
    try {
      final response = await _supabase.rpc(
        'obtener_envios_consignacion_con_totales',
        params: {
          'p_id_contrato': null,
          'p_estado_envio': estadoEnvio,
          'p_id_tienda': null,
        },
      );

      if (response == null) return [];
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      print('❌ Error obteniendo envíos por estado: $e');
      rethrow;
    }
  }

  /// Obtiene envíos de un contrato específico con totales calculados
  static Future<List<Map<String, dynamic>>> obtenerEnviosPorContrato(
    int idContrato,
  ) async {
    try {
      final response = await _supabase.rpc(
        'obtener_envios_consignacion_con_totales',
        params: {
          'p_id_contrato': idContrato,
          'p_estado_envio': null,
          'p_id_tienda': null,
        },
      );

      if (response == null) return [];
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      print('❌ Error obteniendo envíos del contrato: $e');
      rethrow;
    }
  }

  /// Determina si el usuario es consignador o consignatario de un contrato
  static Future<String?> obtenerRolEnContrato(
    int idContrato,
    String idUsuario,
  ) async {
    try {
      final contrato = await _supabase
          .from('app_dat_contrato_consignacion')
          .select('id_tienda_consignadora, id_tienda_consignataria')
          .eq('id', idContrato)
          .single();

      // Obtener tienda del usuario
      final usuario = await _supabase
          .from('app_dat_usuario')
          .select('id_tienda')
          .eq('uuid', idUsuario)
          .single();

      final idTiendaUsuario = usuario['id_tienda'] as int;
      final idConsignadora = contrato['id_tienda_consignadora'] as int;
      final idConsignataria = contrato['id_tienda_consignataria'] as int;

      if (idTiendaUsuario == idConsignadora) {
        return 'consignador';
      } else if (idTiendaUsuario == idConsignataria) {
        return 'consignatario';
      }
      return null;
    } catch (e) {
      print('❌ Error obteniendo rol del usuario: $e');
      return null;
    }
  }

  /// Obtiene envíos de una tienda (como consignadora o consignataria) con totales calculados
  static Future<List<Map<String, dynamic>>> obtenerEnviosPorTienda(
    int idTienda,
  ) async {
    try {
      final response = await _supabase.rpc(
        'obtener_envios_consignacion_con_totales',
        params: {
          'p_id_contrato': null,
          'p_estado_envio': null,
          'p_id_tienda': idTienda,
        },
      );

      if (response == null) return [];
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      print('❌ Error obteniendo envíos de la tienda: $e');
      rethrow;
    }
  }

  /// Obtiene detalles completos de un envío con totales calculados
  static Future<Map<String, dynamic>?> obtenerDetallesEnvio(
    int idEnvio,
  ) async {
    try {
      print('🔍 Obteniendo detalles del envío: $idEnvio');
      
      // Usar el RPC que calcula totales correctamente
      final response = await _supabase.rpc(
        'obtener_envios_consignacion_con_totales',
        params: {
          'p_id_contrato': null,
          'p_estado_envio': null,
          'p_id_tienda': null,
        },
      );

      print('📦 Respuesta RPC detalles recibida: ${response?.runtimeType}');
      
      if (response == null || (response as List).isEmpty) {
        print('⚠️ Respuesta vacía para envío $idEnvio');
        return null;
      }
      
      // Filtrar por id_envio
      final detalles = response.firstWhere(
        (envio) => (envio['id_envio'] as num?)?.toInt() == idEnvio,
        orElse: () => null,
      );
      
      if (detalles == null) {
        print('⚠️ Envío no encontrado: $idEnvio');
        return null;
      }
      
      final detalle = detalles as Map<String, dynamic>;
      print('✅ Detalles del envío obtenidos:');
      print('   - ID Envío: ${detalle['id_envio']}');
      print('   - Número: ${detalle['numero_envio']}');
      print('   - Estado: ${detalle['estado_envio_texto']}');
      print('   - ID Contrato: ${detalle['id_contrato_consignacion']}');
      print('   - Cantidad Productos: ${detalle['cantidad_productos']}');
      print('   - Cantidad Total Unidades: ${detalle['cantidad_total_unidades']}');
      print('   - Valor Total Costo: ${detalle['valor_total_costo']}');
      print('   - Valor Total Venta: ${detalle['valor_total_venta']}');
      
      return detalle;
    } catch (e) {
      print('❌ Error obteniendo detalles del envío: $e');
      return null;
    }
  }

  /// Obtiene productos de un envío con detalles
  static Future<List<Map<String, dynamic>>> obtenerProductosEnvio(
    int idEnvio,
  ) async {
    try {
      print('📦 Obteniendo productos del envío: $idEnvio');
      
      final response = await _supabase.rpc(
        'obtener_productos_envio2',
        params: {
          'p_id_envio': idEnvio,
        },
      );

      if (response == null) {
        print('⚠️ Respuesta nula del RPC obtener_productos_envio');
        return [];
      }
      
      final productos = List<Map<String, dynamic>>.from(response as List);
      print('✅ Productos obtenidos: ${productos.length}');
      
      // Logging detallado de los campos retornados
      if (productos.isNotEmpty) {
        print('📋 Campos del primer producto: ${productos[0].keys.toList()}');
        for (var i = 0; i < productos.length; i++) {
          final p = productos[i];
          print('   Producto $i: id=${p['id']}, denominacion=${p['denominacion']}, cantidad=${p['cantidad_propuesta']}');
        }
      } else {
        print('⚠️ No hay productos en el envío $idEnvio');
      }
      
      return productos;
    } catch (e) {
      print('❌ Error obteniendo productos del envío: $e');
      print('   Stack trace: $e');
      return [];
    }
  }

  /// Obtiene envíos pendientes de aceptación (EN_TRANSITO)
  static Future<List<Map<String, dynamic>>> obtenerEnviosPendientes() async {
    return obtenerEnviosPorEstado(ESTADO_EN_TRANSITO);
  }

  /// Obtiene envíos aceptados
  static Future<List<Map<String, dynamic>>> obtenerEnviosAceptados() async {
    return obtenerEnviosPorEstado(ESTADO_ACEPTADO);
  }

  /// Obtiene envíos rechazados
  static Future<List<Map<String, dynamic>>> obtenerEnviosRechazados() async {
    return obtenerEnviosPorEstado(ESTADO_RECHAZADO);
  }

  /// Obtiene envíos parcialmente aceptados
  static Future<List<Map<String, dynamic>>>
      obtenerEnviosParcialmentAceptados() async {
    return obtenerEnviosPorEstado(ESTADO_PARCIALMENTE_ACEPTADO);
  }

  /// Convierte código de estado a texto
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
      case ESTADO_PARCIALMENTE_ACEPTADO:
        return 'PARCIALMENTE ACEPTADO';
      default:
        return 'DESCONOCIDO';
    }
  }

  /// Obtiene color para estado de envío
  static String obtenerColorEstado(int estado) {
    switch (estado) {
      case ESTADO_PROPUESTO:
        return '#FFA500'; // Naranja
      case ESTADO_CONFIGURADO:
        return '#4169E1'; // Azul real
      case ESTADO_EN_TRANSITO:
        return '#FFD700'; // Oro
      case ESTADO_ACEPTADO:
        return '#00AA00'; // Verde
      case ESTADO_RECHAZADO:
        return '#FF0000'; // Rojo
      case ESTADO_PARCIALMENTE_ACEPTADO:
        return '#FF8C00'; // Naranja oscuro
      default:
        return '#808080'; // Gris
    }
  }

  /// Cancela un envío de consignación
  static Future<Map<String, dynamic>> cancelarEnvio(
    int idEnvio,
    String idUsuario,
    String? motivo,
  ) async {
    try {
      final response = await _supabase.rpc(
        'cancelar_envio_consignacion',
        params: {
          'p_id_envio': idEnvio,
          'p_id_usuario': idUsuario,
          'p_motivo': motivo,
        },
      );

      if (response == null || (response as List).isEmpty) {
        return {'success': false, 'mensaje': 'Error desconocido'};
      }

      return response.first as Map<String, dynamic>;
    } catch (e) {
      print('❌ Error cancelando envío: $e');
      return {'success': false, 'mensaje': e.toString()};
    }
  }

  /// Rechaza un producto individualmente dentro de un envío.
  /// Devuelve stock, remueve el producto del envío y de la extracción asociada.
  static Future<Map<String, dynamic>> rechazarProductoEnvio(
    int idEnvio,
    int idEnvioProducto,
    String idUsuario,
    String motivoRechazo,
  ) async {
    try {
      final response = await _supabase.rpc(
        'rechazar_producto_envio_consignacion',
        params: {
          'p_id_envio': idEnvio,
          'p_id_envio_producto': idEnvioProducto,
          'p_id_usuario': idUsuario,
          'p_motivo_rechazo': motivoRechazo,
        },
      );

      if (response == null || (response as List).isEmpty) {
        return {'success': false, 'mensaje': 'Error desconocido'};
      }

      return response.first as Map<String, dynamic>;
    } catch (e) {
      print('❌ Error rechazando producto del envío: $e');
      return {'success': false, 'mensaje': e.toString()};
    }
  }

  /// Actualiza el estado de un envío de consignación
  static Future<bool> actualizarEstadoEnvio(
    int idEnvio,
    int nuevoEstado,
  ) async {
    try {
      print('🔄 Actualizando estado del envío $idEnvio a ${obtenerTextoEstado(nuevoEstado)}');
      
      await _supabase
          .from('app_dat_consignacion_envio')
          .update({'estado': nuevoEstado})
          .eq('id', idEnvio);

      print('✅ Estado del envío actualizado correctamente');
      return true;
    } catch (e) {
      print('❌ Error actualizando estado del envío: $e');
      return false;
    }
  }
}
