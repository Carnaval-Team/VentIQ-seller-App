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

  /// Obtiene lista de envíos con filtros opcionales
  static Future<List<Map<String, dynamic>>> obtenerEnvios({
    int? idContrato,
    int? estadoEnvio,
    int? idTienda,
  }) async {
    try {
      final response = await _supabase.rpc(
        'obtener_envios_consignacion',
        params: {
          'p_id_contrato': idContrato,
          'p_estado_envio': estadoEnvio,
          'p_id_tienda': idTienda,
        },
      );

      if (response == null) return [];
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      print('❌ Error obteniendo envíos: $e');
      rethrow;
    }
  }

  /// Obtiene envíos por estado
  static Future<List<Map<String, dynamic>>> obtenerEnviosPorEstado(
    int estadoEnvio,
  ) async {
    try {
      final response = await _supabase.rpc(
        'obtener_envios_consignacion',
        params: {
          'p_estado_envio': estadoEnvio,
        },
      );

      if (response == null) return [];
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      print('❌ Error obteniendo envíos por estado: $e');
      rethrow;
    }
  }

  /// Obtiene envíos de un contrato específico
  static Future<List<Map<String, dynamic>>> obtenerEnviosPorContrato(
    int idContrato,
  ) async {
    try {
      final response = await _supabase.rpc(
        'obtener_envios_consignacion',
        params: {
          'p_id_contrato': idContrato,
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

  /// Obtiene envíos de una tienda (como consignadora o consignataria)
  static Future<List<Map<String, dynamic>>> obtenerEnviosPorTienda(
    int idTienda,
  ) async {
    try {
      final response = await _supabase.rpc(
        'obtener_envios_consignacion',
        params: {
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

  /// Obtiene detalles completos de un envío
  static Future<Map<String, dynamic>?> obtenerDetallesEnvio(
    int idEnvio,
  ) async {
    try {
      final response = await _supabase.rpc(
        'obtener_detalles_envio',
        params: {
          'p_id_envio': idEnvio,
        },
      );

      if (response == null || (response as List).isEmpty) return null;
      return response.first as Map<String, dynamic>;
    } catch (e) {
      print('❌ Error obteniendo detalles del envío: $e');
      rethrow;
    }
  }

  /// Obtiene productos de un envío con detalles
  static Future<List<Map<String, dynamic>>> obtenerProductosEnvio(
    int idEnvio,
  ) async {
    try {
      final response = await _supabase.rpc(
        'obtener_productos_envio_detallado',
        params: {
          'p_id_envio': idEnvio,
        },
      );

      if (response == null) return [];
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      print('❌ Error obteniendo productos del envío: $e');
      rethrow;
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
      return {'success': false, 'mensaje': 'Error: $e'};
    }
  }
}
