import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cxc_cliente.dart';
import 'user_preferences_service.dart';

/// Servicio de Cuentas por Cobrar (ventas a "pago pendiente" / fiado).
///
/// Se apoya en app_dat_operacion_venta.es_pagada + app_dat_pago_venta (ya
/// existentes) y en las funciones RPC fn_cxc_* creadas en
/// docs/migrations/10_cuentas_por_cobrar.sql.
class CxcService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static final UserPreferencesService _prefsService = UserPreferencesService();

  /// Lista los clientes con saldo pendiente en la tienda actual.
  static Future<List<CxcCliente>> listarClientesConSaldo() async {
    try {
      final idTienda = await _prefsService.getIdTienda();
      if (idTienda == null) {
        throw Exception('No se encontró la tienda del usuario');
      }

      final response = await _supabase.rpc(
        'fn_cxc_listar_clientes',
        params: {'p_id_tienda': idTienda},
      );

      if (response is! List) return [];
      return response
          .map((e) => CxcCliente.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      print('❌ Error listando clientes con CxC: $e');
      rethrow;
    }
  }

  /// Historial completo (pagadas y pendientes) de ventas a crédito de un
  /// cliente.
  static Future<List<CxcVenta>> historialCliente(int idCliente) async {
    try {
      final response = await _supabase.rpc(
        'fn_cxc_historial_cliente',
        params: {'p_id_cliente': idCliente},
      );

      if (response is! List) return [];
      return response
          .map((e) => CxcVenta.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      print('❌ Error obteniendo historial CxC del cliente $idCliente: $e');
      return [];
    }
  }

  /// Saldo total pendiente de un cliente.
  static Future<double> saldoCliente(int idCliente) async {
    try {
      final response = await _supabase.rpc(
        'fn_cxc_saldo_cliente',
        params: {'p_id_cliente': idCliente},
      );
      return (response as num?)?.toDouble() ?? 0.0;
    } catch (e) {
      print('❌ Error obteniendo saldo CxC del cliente $idCliente: $e');
      return 0.0;
    }
  }

  /// Obtiene el estado actual de bloqueo de un cliente.
  static Future<bool> estaBloqueado(int idCliente) async {
    try {
      // Los clientes de CxC viven en app_dat_cliente_cxc, una tabla
      // independiente de app_dat_clientes.
      final response = await _supabase
          .from('app_dat_cliente_cxc')
          .select('bloqueado_cxc')
          .eq('id', idCliente)
          .maybeSingle();
      return response?['bloqueado_cxc'] == true;
    } catch (e) {
      print('❌ Error obteniendo estado de bloqueo del cliente $idCliente: $e');
      return false;
    }
  }

  /// Bloquea o desbloquea a un cliente para que no se le puedan seguir
  /// generando nuevas cuentas por cobrar.
  static Future<void> setBloqueoCliente(
    int idCliente,
    bool bloqueado,
  ) async {
    await _supabase.rpc(
      'fn_cxc_set_bloqueo_cliente',
      params: {'p_id_cliente': idCliente, 'p_bloqueado': bloqueado},
    );
  }

  /// Registra un cobro/liquidación para un cliente.
  ///
  /// Si [distribucion] es null, el monto se aplica automáticamente en modo
  /// FIFO a las ventas pendientes más antiguas. Si se provee, debe ser una
  /// lista de mapas {'id_operacion_venta': id, 'monto': monto} con la
  /// distribución exacta elegida por el admin.
  static Future<Map<String, dynamic>> registrarLiquidacion({
    required int idCliente,
    required double monto,
    required int idMedioPago,
    String? referencia,
    String? observaciones,
    List<Map<String, dynamic>>? distribucion,
  }) async {
    final idTienda = await _prefsService.getIdTienda();
    if (idTienda == null) {
      throw Exception('No se encontró la tienda del usuario');
    }
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('No hay usuario autenticado');
    }

    final response = await _supabase.rpc(
      'fn_cxc_registrar_liquidacion',
      params: {
        'p_id_cliente': idCliente,
        'p_id_tienda': idTienda,
        'p_monto': monto,
        'p_id_medio_pago': idMedioPago,
        'p_referencia': referencia,
        'p_creado_por': userId,
        'p_observaciones': observaciones,
        'p_distribucion': distribucion,
      },
    );

    return Map<String, dynamic>.from(response as Map);
  }
}
