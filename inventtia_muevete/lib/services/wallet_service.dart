import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WalletService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Caché en memoria de `muevete.configuracion_tarifas` (singleton `id = 1`).
  static Map<String, dynamic>? _configuracionCache;

  /// Fetches the client balance from muevete.suscription_user.
  /// Creates a row if one doesn't exist yet.
  Future<double> getClientBalance(String uuid) async {
    final response = await _supabase
        .schema('muevete')
        .from('suscription_user')
        .select('balance')
        .eq('user_id', uuid)
        .maybeSingle();

    if (response == null) {
      // Create wallet row for new user
      await _supabase
          .schema('muevete')
          .from('suscription_user')
          .insert({'user_id': uuid, 'balance': 0});
      return 0.0;
    }
    return (response['balance'] as num?)?.toDouble() ?? 0.0;
  }

  /// Fetches the driver balance from muevete.wallet_drivers.
  Future<double> getDriverBalance(int driverId) async {
    final response = await _supabase
        .schema('muevete')
        .from('wallet_drivers')
        .select('balance')
        .eq('driver_id', driverId)
        .maybeSingle();

    if (response == null) return 0.0;
    return (response['balance'] as num?)?.toDouble() ?? 0.0;
  }

  /// % de recarga configurado en el servidor (configuracion_tarifas.recarga_pct).
  /// Se cachea en memoria: cambia como mucho por configuración del superadmin.
  ///
  /// Devuelve además `limite_deuda_efectivo`, `permite_deuda` y `moneda` para
  /// que la billetera del chofer pinte el tope real de deuda. Si la consulta
  /// falla devuelve valores seguros (`recarga_pct: 0`, sin deuda permitida)
  /// sin cachearlos, para reintentar en la siguiente apertura.
  Future<Map<String, dynamic>> configuracionRecarga() async {
    final cache = _configuracionCache;
    if (cache != null) return cache;

    const defaults = <String, dynamic>{
      'recarga_pct': 0,
      'limite_deuda_efectivo': 0,
      'permite_deuda': false,
      'moneda': 'CUP',
    };

    try {
      final row = await _supabase
          .schema('muevete')
          .from('configuracion_tarifas')
          .select('recarga_pct, limite_deuda_efectivo, permite_deuda, moneda')
          .eq('id', 1)
          .maybeSingle();

      if (row == null) return defaults;

      final config = <String, dynamic>{
        'recarga_pct': (row['recarga_pct'] as num?)?.toDouble() ?? 0,
        'limite_deuda_efectivo':
            (row['limite_deuda_efectivo'] as num?)?.toDouble() ?? 0,
        'permite_deuda': row['permite_deuda'] as bool? ?? false,
        'moneda': row['moneda']?.toString() ?? 'CUP',
      };
      _configuracionCache = config;
      return config;
    } catch (e) {
      debugPrint('WalletService.configuracionRecarga error: $e');
      return defaults;
    }
  }

  /// Crea una recarga pendiente para el cliente a través de `fn_recargar_wallet`.
  ///
  /// [uuid] se conserva por compatibilidad con las pantallas existentes: el
  /// servidor identifica al usuario por el token de sesión. El monto a pagar y
  /// el % de recarga los calcula la RPC (`total_a_pagar`, `recarga_pct`); la
  /// app ya no aplica ningún multiplicador.
  Future<int> addFunds(String uuid, double amount) async {
    final res = await recargar(metodo: 'efectivo', monto: amount);
    return _transaccionId(res);
  }

  /// §3.7 `fn_recargar_wallet`.
  ///
  /// `total_a_pagar` ya incluye el % de recarga: la app no aplica ningún
  /// multiplicador fijo (antes se duplicaba el porcentaje en Dart).
  Future<Map<String, dynamic>> recargar({
    required String metodo, // 'efectivo' | 'transferencia' | 'usd' ...
    required double monto,
    String? evidencia,
  }) async {
    final res = await _supabase.schema('muevete').rpc(
      'fn_recargar_wallet',
      params: {
        'p_metodo': metodo,
        'p_monto': monto,
        'p_evidencia': evidencia,
      },
    );
    if (res is Map) return Map<String, dynamic>.from(res);
    return const <String, dynamic>{};
  }

  int _transaccionId(Map<String, dynamic> res) {
    final id = (res['transaccion_id'] as num?)?.toInt();
    if (id == null) {
      throw Exception(
        res['error']?.toString() ?? 'No se pudo registrar la recarga',
      );
    }
    return id;
  }

  /// Fetches all wallet transactions for a given user UUID.
  Future<List<Map<String, dynamic>>> getTransactions(String uuid) async {
    final response = await _supabase
        .schema('muevete')
        .from('transacciones_wallet')
        .select()
        .eq('user_id', uuid)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  /// Crea una recarga pendiente para el chofer vía `fn_recargar_wallet`.
  ///
  /// [driverId] se conserva por compatibilidad: la RPC decide si la recarga es
  /// de chofer (`es_recarga_chofer`) según la sesión autenticada.
  Future<int> addDriverFunds(int driverId, double amount) async {
    final res = await recargar(metodo: 'efectivo', monto: amount);
    return _transaccionId(res);
  }

  /// Fetches all wallet transactions for a given driver ID.
  Future<List<Map<String, dynamic>>> getDriverTransactions(int driverId) async {
    final response = await _supabase
        .schema('muevete')
        .from('transacciones_wallet')
        .select()
        .eq('driver_id', driverId)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  /// Uploads verification evidence for a pending recharge transaction.
  Future<void> uploadVerificacion({
    required int transaccionId,
    String? imagenUrl,
    String? detalleTexto,
  }) async {
    await _supabase
        .schema('muevete')
        .from('verificacion_operacion_recarga')
        .insert({
      'transaccion_id': transaccionId,
      if (imagenUrl != null) 'imagen_url': imagenUrl,
      if (detalleTexto != null) 'detalle_texto': detalleTexto,
    });
  }

  /// Checks if a verification exists for a given transaction.
  Future<Map<String, dynamic>?> getVerificacion(int transaccionId) async {
    final response = await _supabase
        .schema('muevete')
        .from('verificacion_operacion_recarga')
        .select()
        .eq('transaccion_id', transaccionId)
        .maybeSingle();

    return response;
  }

  /// Lists pending recargas that don't have a verification yet.
  Future<List<Map<String, dynamic>>> getPendingRecargas({
    String? uuid,
    int? driverId,
  }) async {
    var query = _supabase
        .schema('muevete')
        .from('transacciones_wallet')
        .select()
        .eq('tipo', 'recarga')
        .eq('estado', 'pendiente');

    if (uuid != null) {
      query = query.eq('user_id', uuid);
    }
    if (driverId != null) {
      query = query.eq('driver_id', driverId);
    }

    final response = await query.order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  /// LEGACY: la retención del cliente la hace `fn_tomar_viaje` en el servidor.
  @Deprecated('La retención de wallet vive en fn_tomar_viaje (servidor).')
  Future<void> holdClientFunds(String clientUuid, double amount) async {
    final clientBalance = await getClientBalance(clientUuid);
    if (clientBalance < amount) {
      throw Exception('Saldo insuficiente. Necesitas \$${amount.toStringAsFixed(2)}');
    }

    final newBalance = clientBalance - amount;
    await _supabase
        .schema('muevete')
        .from('suscription_user')
        .update({'balance': newBalance})
        .eq('user_id', clientUuid);
  }

  /// LEGACY: el movimiento lo registra `fn_completar_viaje`.
  @Deprecated('El pago del viaje lo registra fn_completar_viaje (servidor).')
  Future<void> confirmClientPayment(
    String clientUuid, double amount, int viajeId) async {
    final currentBalance = await getClientBalance(clientUuid);
    await _supabase.schema('muevete').from('transacciones_wallet').insert({
      'user_id': clientUuid,
      'tipo': 'pago_viaje',
      'monto': -amount,
      'balance_despues': currentBalance,
      'viaje_id': viajeId,
      'descripcion': 'Pago de viaje por wallet',
    });
  }

  /// LEGACY: el reembolso lo aplica `fn_cancelar_solicitud` y la RPC devuelve
  /// `reembolso` y `saldo`.
  @Deprecated('El reembolso lo aplica fn_cancelar_solicitud (servidor).')
  Future<void> refundClientFunds(
    String clientUuid, double amount, int solicitudId) async {
    final currentBalance = await getClientBalance(clientUuid);
    final newBalance = currentBalance + amount;

    await _supabase
        .schema('muevete')
        .from('suscription_user')
        .update({'balance': newBalance})
        .eq('user_id', clientUuid);

    await _supabase.schema('muevete').from('transacciones_wallet').insert({
      'user_id': clientUuid,
      'tipo': 'reembolso',
      'monto': amount,
      'balance_despues': newBalance,
      'descripcion': 'Reembolso por cancelación de solicitud #$solicitudId',
    });
  }

  // La comisión del chofer y su crédito los calcula y aplica
  // `fn_completar_viaje` en el servidor: `chargeDriverCommission`,
  // `creditDriverForWalletPayment` y `driverHasEnoughForCommission` se
  // eliminaron de la app porque duplicaban esa aritmética.

  /// Processes ride completion payment via RPC (SECURITY DEFINER).
  ///
  /// LEGACY: el flujo de precio fijo cierra con `fn_completar_viaje`
  /// (`TransportProvider.completarViaje`), que no recibe precios. Se mantiene
  /// sólo para builds antiguas y viajes históricos; no debe llamarse desde el
  /// flujo nuevo.
  @Deprecated('Usa fn_completar_viaje vía TransportProvider.completarViaje.')
  Future<void> completeRidePaymentRpc({
    required String metodoPago,
    required String clientUuid,
    required int driverId,
    required int viajeId,
    required double precioFinal,
    required double precioBase,
  }) async {
    final result = await _supabase.rpc('complete_ride_payment', params: {
      'p_metodo_pago': metodoPago,
      'p_client_uuid': clientUuid,
      'p_driver_id': driverId,
      'p_viaje_id': viajeId,
      'p_precio_final': precioFinal,
      'p_precio_base': precioBase,
    });

    final data = result as Map<String, dynamic>;
    if (data['success'] != true) {
      throw Exception(data['error'] ?? 'Error procesando pago');
    }
  }
}
