import 'package:supabase_flutter/supabase_flutter.dart';

class WalletService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Fetches the client balance from muevete.suscription_user.
  Future<double> getClientBalance(String uuid) async {
    final response = await _supabase
        .schema('muevete')
        .from('suscription_user')
        .select('balance')
        .eq('user_id', uuid)
        .maybeSingle();

    if (response == null) return 0.0;
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

  /// Adds funds to a client wallet: updates balance and creates a transaction record.
  Future<void> addFunds(String uuid, double amount) async {
    // Get current balance
    final currentBalance = await getClientBalance(uuid);
    final newBalance = currentBalance + amount;

    // Update the balance in suscription_user
    await _supabase
        .schema('muevete')
        .from('suscription_user')
        .update({'balance': newBalance})
        .eq('user_id', uuid);

    // Create a transaction record
    await _supabase.schema('muevete').from('transacciones_wallet').insert({
      'user_id': uuid,
      'tipo': 'recarga',
      'monto': amount,
      'balance_despues': newBalance,
    });
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

  /// Processes a ride payment: deducts from client, credits driver,
  /// and creates transaction records for both parties.
  Future<void> processRidePayment(
    int tripId,
    String clientUuid,
    int driverId,
    double amount,
  ) async {
    // Get current balances
    final clientBalance = await getClientBalance(clientUuid);
    final driverBalance = await getDriverBalance(driverId);

    if (clientBalance < amount) {
      throw Exception('Insufficient client balance');
    }

    final newClientBalance = clientBalance - amount;
    final newDriverBalance = driverBalance + amount;

    // Deduct from client
    await _supabase
        .schema('muevete')
        .from('suscription_user')
        .update({'balance': newClientBalance})
        .eq('user_id', clientUuid);

    // Credit driver
    await _supabase
        .schema('muevete')
        .from('wallet_drivers')
        .update({'balance': newDriverBalance})
        .eq('driver_id', driverId);

    // Create client transaction record (debit)
    await _supabase.schema('muevete').from('transacciones_wallet').insert({
      'user_id': clientUuid,
      'tipo': 'pago_viaje',
      'monto': -amount,
      'balance_despues': newClientBalance,
      'viaje_id': tripId,
    });

    // Create driver transaction record (credit)
    await _supabase.schema('muevete').from('transacciones_wallet').insert({
      'driver_id': driverId,
      'tipo': 'cobro_viaje',
      'monto': amount,
      'balance_despues': newDriverBalance,
      'viaje_id': tripId,
    });
  }
}
