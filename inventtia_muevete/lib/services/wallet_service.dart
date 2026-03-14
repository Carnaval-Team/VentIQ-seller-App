import 'package:supabase_flutter/supabase_flutter.dart';

class WalletService {
  final SupabaseClient _supabase = Supabase.instance.client;

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

  /// Creates a pending recharge transaction for a client wallet.
  /// Does NOT update the balance — it stays pending until admin approval.
  /// Returns the transaction ID.
  Future<int> addFunds(String uuid, double amount) async {
    // Ensure wallet row exists
    await getClientBalance(uuid);

    // amount = lo que se acredita al usuario
    // El usuario debe pagar amount * 1.11 (recarga + 11% comisión)
    final response = await _supabase
        .schema('muevete')
        .from('transacciones_wallet')
        .insert({
          'user_id': uuid,
          'tipo': 'recarga',
          'monto': amount,
          'estado': 'pendiente',
          'descripcion':
              'Recarga de \$${amount.toStringAsFixed(2)} — pago total: \$${(amount * 1.11).toStringAsFixed(2)} (incluye 11% comisión)',
        })
        .select('id')
        .single();

    return response['id'] as int;
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

  /// Creates a pending recharge transaction for a driver wallet.
  /// Does NOT update the balance — it stays pending until admin approval.
  /// Returns the transaction ID.
  Future<int> addDriverFunds(int driverId, double amount) async {
    // Ensure wallet row exists
    final existing = await _supabase
        .schema('muevete')
        .from('wallet_drivers')
        .select('id')
        .eq('driver_id', driverId)
        .maybeSingle();

    if (existing == null) {
      await _supabase
          .schema('muevete')
          .from('wallet_drivers')
          .insert({'driver_id': driverId, 'balance': 0});
    }

    // amount = lo que se acredita al conductor
    // El conductor debe pagar amount * 1.11 (recarga + 11% comisión)
    final response = await _supabase
        .schema('muevete')
        .from('transacciones_wallet')
        .insert({
          'driver_id': driverId,
          'tipo': 'recarga',
          'monto': amount,
          'estado': 'pendiente',
          'descripcion':
              'Recarga de \$${amount.toStringAsFixed(2)} — pago total: \$${(amount * 1.11).toStringAsFixed(2)} (incluye 11% comisión)',
        })
        .select('id')
        .single();

    return response['id'] as int;
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

  /// Holds (deducts) client funds when an offer is accepted (wallet payment).
  /// Throws if insufficient balance.
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

  /// Records the client wallet transaction after ride completion.
  /// Funds were already deducted at holdClientFunds.
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

  /// Refunds held client funds (on cancellation).
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

  /// Charges the driver 15% commission on ride completion.
  /// Throws if insufficient balance.
  Future<void> chargeDriverCommission(
    int driverId, double commission, int viajeId) async {
    final driverBalance = await getDriverBalance(driverId);
    if (driverBalance < commission) {
      throw Exception(
        'Saldo del conductor insuficiente para comisión de \$${commission.toStringAsFixed(2)}');
    }

    final newBalance = driverBalance - commission;
    await _supabase
        .schema('muevete')
        .from('wallet_drivers')
        .update({'balance': newBalance})
        .eq('driver_id', driverId);

    await _supabase.schema('muevete').from('transacciones_wallet').insert({
      'driver_id': driverId,
      'tipo': 'comision_viaje',
      'monto': -commission,
      'balance_despues': newBalance,
      'viaje_id': viajeId,
      'descripcion': 'Comisión 15% por viaje completado',
    });
  }

  /// Credits the driver wallet with the ride fare minus 15% commission
  /// when the client paid via wallet.
  Future<void> creditDriverForWalletPayment(
    int driverId, double rideFare, int viajeId) async {
    final commission = rideFare * 0.15;
    final netAmount = rideFare - commission;

    final currentBalance = await getDriverBalance(driverId);
    final newBalance = currentBalance + netAmount;

    // Ensure wallet row exists
    final existing = await _supabase
        .schema('muevete')
        .from('wallet_drivers')
        .select('id')
        .eq('driver_id', driverId)
        .maybeSingle();

    if (existing == null) {
      await _supabase
          .schema('muevete')
          .from('wallet_drivers')
          .insert({'driver_id': driverId, 'balance': newBalance});
    } else {
      await _supabase
          .schema('muevete')
          .from('wallet_drivers')
          .update({'balance': newBalance})
          .eq('driver_id', driverId);
    }

    await _supabase.schema('muevete').from('transacciones_wallet').insert({
      'driver_id': driverId,
      'tipo': 'pago_viaje',
      'monto': netAmount,
      'balance_despues': newBalance,
      'viaje_id': viajeId,
      'descripcion':
          'Pago por viaje (tarifa \$${rideFare.toStringAsFixed(2)} - 15% comisión)',
    });
  }

  /// Checks if driver has enough balance for 15% commission.
  Future<bool> driverHasEnoughForCommission(
    int driverId, double offerPrice) async {
    final balance = await getDriverBalance(driverId);
    return balance >= (offerPrice * 0.15);
  }

  /// Processes ride completion payment via RPC (SECURITY DEFINER).
  /// This bypasses RLS so the client can trigger driver wallet updates.
  Future<void> completeRidePaymentRpc({
    required String metodoPago,
    required String clientUuid,
    required int driverId,
    required int viajeId,
    required double precioFinal,
  }) async {
    final result = await _supabase.rpc('complete_ride_payment', params: {
      'p_metodo_pago': metodoPago,
      'p_client_uuid': clientUuid,
      'p_driver_id': driverId,
      'p_viaje_id': viajeId,
      'p_precio_final': precioFinal,
    });

    final data = result as Map<String, dynamic>;
    if (data['success'] != true) {
      throw Exception(data['error'] ?? 'Error procesando pago');
    }
  }
}
