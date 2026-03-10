import 'package:supabase_flutter/supabase_flutter.dart';

class MueveteService {
  static final _supabase = Supabase.instance.client;

  // ─── DRIVERS ──────────────────────────────────────────────────────────

  /// Fetches all drivers with their vehicle info.
  static Future<List<Map<String, dynamic>>> getDrivers() async {
    final rows = await _supabase
        .schema('muevete')
        .from('drivers')
        .select(
          '*, vehiculos!drivers_vehiculo_fkey(marca, modelo, chapa, color, categoria)',
        )
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Updates a driver's fields (kyc, revisado, motivo, estado, etc).
  static Future<void> updateDriver(int driverId, Map<String, dynamic> data) async {
    await _supabase
        .schema('muevete')
        .from('drivers')
        .update(data)
        .eq('id', driverId);
  }

  // ─── TRIPS (VIAJES) ──────────────────────────────────────────────────

  /// Fetches trips with driver name, enriched.
  static Future<List<Map<String, dynamic>>> getTrips({
    int limit = 100,
    int offset = 0,
    bool? completado,
  }) async {
    var query = _supabase
        .schema('muevete')
        .from('viajes')
        .select('*, drivers!viajes_driver_fkey(name, email, telefono)')
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    if (completado != null) {
      query = _supabase
          .schema('muevete')
          .from('viajes')
          .select('*, drivers!viajes_driver_fkey(name, email, telefono)')
          .eq('completado', completado)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
    }

    final rows = await query;
    return List<Map<String, dynamic>>.from(rows);
  }

  // ─── REQUESTS (SOLICITUDES) ───────────────────────────────────────────

  /// Fetches transport requests.
  static Future<List<Map<String, dynamic>>> getRequests({
    int limit = 100,
    int offset = 0,
    String? estado,
  }) async {
    var query = _supabase
        .schema('muevete')
        .from('solicitudes_transporte')
        .select('*')
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    if (estado != null) {
      query = _supabase
          .schema('muevete')
          .from('solicitudes_transporte')
          .select('*')
          .eq('estado', estado)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
    }

    final rows = await query;
    return List<Map<String, dynamic>>.from(rows);
  }

  // ─── OFFERS (OFERTAS) ─────────────────────────────────────────────────

  /// Fetches offers with driver info.
  static Future<List<Map<String, dynamic>>> getOffers({
    int limit = 100,
    int offset = 0,
  }) async {
    final rows = await _supabase
        .schema('muevete')
        .from('ofertas_chofer')
        .select('*, drivers!ofertas_chofer_driver_id_fkey(name, email)')
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return List<Map<String, dynamic>>.from(rows);
  }

  // ─── RATINGS (VALORACIONES) ───────────────────────────────────────────

  /// Fetches all ratings with driver name.
  static Future<List<Map<String, dynamic>>> getRatings({
    int limit = 100,
    int offset = 0,
  }) async {
    final rows = await _supabase
        .schema('muevete')
        .from('valoraciones_viaje')
        .select('*, drivers!valoraciones_viaje_driver_fkey(name, email)')
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return List<Map<String, dynamic>>.from(rows);
  }

  // ─── MAP POSITIONS ────────────────────────────────────────────────────

  /// Fetches all driver positions (online or all).
  static Future<List<Map<String, dynamic>>> getDriverPositions({
    bool onlineOnly = false,
  }) async {
    var query = _supabase
        .schema('muevete')
        .from('place')
        .select(
          '*, drivers!place_driver_fkey(id, name, email, telefono, kyc, image, vehiculos!drivers_vehiculo_fkey(marca, modelo, chapa, color))',
        );

    if (onlineOnly) {
      query = query.eq('estado', true);
    }

    final rows = await query;
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Fetches real-time driver positions from track_place_history.
  /// Returns the latest position per driver with driver info joined.
  /// Each entry includes a 'history' list with the last [historyLimit] points.
  static Future<List<Map<String, dynamic>>> getDriverPositionsFromHistory({
    bool onlineOnly = false,
    int historyLimit = 20,
  }) async {
    // 1. Get all drivers (with vehicle info + online status from place)
    final driversQuery = _supabase
        .schema('muevete')
        .from('place')
        .select(
          '*, drivers!place_driver_fkey(id, name, email, telefono, kyc, image, vehiculos!drivers_vehiculo_fkey(marca, modelo, chapa, color))',
        );

    final placeRows = onlineOnly
        ? await driversQuery.eq('estado', true)
        : await driversQuery;

    final results = <Map<String, dynamic>>[];

    for (final place in List<Map<String, dynamic>>.from(placeRows)) {
      final drv = place['drivers'] as Map<String, dynamic>?;
      final driverId = drv?['id'] as int?;
      if (driverId == null) continue;

      // 2. Get latest history points for this driver
      final historyRows = await _supabase
          .schema('muevete')
          .from('track_place_history')
          .select('latitude, longitude, created_at')
          .eq('driver_id', driverId)
          .order('created_at', ascending: false)
          .limit(historyLimit);

      final history = List<Map<String, dynamic>>.from(historyRows);

      if (history.isNotEmpty) {
        // Use latest history point as current position
        final latest = history.first;
        results.add({
          ...place,
          'latitude': latest['latitude'],
          'longitude': latest['longitude'],
          'history': history,
        });
      } else {
        // Fallback to place table if no history yet
        results.add({
          ...place,
          'history': <Map<String, dynamic>>[],
        });
      }
    }

    return results;
  }

  // ─── WALLETS ──────────────────────────────────────────────────────────

  /// Fetches client wallets with user info.
  static Future<List<Map<String, dynamic>>> getClientWallets() async {
    final rows = await _supabase
        .schema('muevete')
        .from('suscription_user')
        .select('*')
        .order('created_at', ascending: false);
    // Enrich with user name
    final result = <Map<String, dynamic>>[];
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final enriched = Map<String, dynamic>.from(row);
      try {
        final userRow = await _supabase
            .schema('muevete')
            .from('users')
            .select('name, email')
            .eq('uuid', row['user_id'])
            .maybeSingle();
        enriched['user_name'] = userRow?['name'];
        enriched['user_email'] = userRow?['email'];
      } catch (_) {}
      result.add(enriched);
    }
    return result;
  }

  /// Fetches driver wallets with driver info.
  static Future<List<Map<String, dynamic>>> getDriverWallets() async {
    final rows = await _supabase
        .schema('muevete')
        .from('wallet_drivers')
        .select('*, drivers!wallet_drivers_driver_id_fkey(name, email, telefono)')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Fetches wallet transactions.
  static Future<List<Map<String, dynamic>>> getTransactions({
    int limit = 100,
    int offset = 0,
  }) async {
    final rows = await _supabase
        .schema('muevete')
        .from('transacciones_wallet')
        .select('*')
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Fetches the verification record for a transaction.
  static Future<Map<String, dynamic>?> getVerificacion(int transaccionId) async {
    final row = await _supabase
        .schema('muevete')
        .from('verificacion_operacion_recarga')
        .select('*')
        .eq('transaccion_id', transaccionId)
        .maybeSingle();
    return row;
  }

  /// Approves a pending recharge: sets estado = 'completada' and credits the balance.
  static Future<void> approveRecarga(int transaccionId) async {
    // Get the transaction
    final tx = await _supabase
        .schema('muevete')
        .from('transacciones_wallet')
        .select('*')
        .eq('id', transaccionId)
        .single();

    final monto = (tx['monto'] as num).toDouble();
    final userId = tx['user_id'] as String?;
    final driverId = tx['driver_id'] as int?;

    // Update estado
    await _supabase
        .schema('muevete')
        .from('transacciones_wallet')
        .update({'estado': 'completada'})
        .eq('id', transaccionId);

    // Credit the balance
    if (userId != null) {
      final wallet = await _supabase
          .schema('muevete')
          .from('suscription_user')
          .select('balance')
          .eq('user_id', userId)
          .single();
      final newBalance = ((wallet['balance'] as num?)?.toDouble() ?? 0) + monto;
      await _supabase
          .schema('muevete')
          .from('suscription_user')
          .update({'balance': newBalance})
          .eq('user_id', userId);
    } else if (driverId != null) {
      final wallet = await _supabase
          .schema('muevete')
          .from('wallet_drivers')
          .select('balance')
          .eq('driver_id', driverId)
          .single();
      final newBalance = ((wallet['balance'] as num?)?.toDouble() ?? 0) + monto;
      await _supabase
          .schema('muevete')
          .from('wallet_drivers')
          .update({'balance': newBalance})
          .eq('driver_id', driverId);
    }
  }

  /// Rejects a pending recharge: sets estado = 'cancelada'.
  static Future<void> rejectRecarga(int transaccionId) async {
    await _supabase
        .schema('muevete')
        .from('transacciones_wallet')
        .update({'estado': 'cancelada'})
        .eq('id', transaccionId);
  }

  // ─── KYC & DOCUMENT VERIFICATION ─────────────────────────────────────

  /// Fetches drivers pending KYC review (revisado = false).
  static Future<List<Map<String, dynamic>>> getPendingKycDrivers() async {
    final rows = await _supabase
        .schema('muevete')
        .from('drivers')
        .select(
          '*, vehiculos!drivers_vehiculo_fkey(marca, modelo, chapa, color)',
        )
        .eq('revisado', false)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Approves a driver KYC.
  static Future<void> approveDriverKyc(int driverId) async {
    await _supabase
        .schema('muevete')
        .from('drivers')
        .update({'kyc': true, 'revisado': true, 'motivo': null})
        .eq('id', driverId);
  }

  /// Rejects a driver KYC with reason.
  static Future<void> rejectDriverKyc(int driverId, String motivo) async {
    await _supabase
        .schema('muevete')
        .from('drivers')
        .update({'kyc': false, 'revisado': true, 'motivo': motivo})
        .eq('id', driverId);
  }

  // ─── ACTIVE TRIP FOR DRIVER ──────────────────────────────────────────

  /// Returns {viaje, oferta, solicitud} for the driver's active trip, or null.
  static Future<Map<String, dynamic>?> getActiveTripForDriver(int driverId) async {
    // 1. Viaje activo (completado = false)
    final viaje = await _supabase
        .schema('muevete')
        .from('viajes')
        .select('*')
        .eq('driver_id', driverId)
        .eq('completado', false)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (viaje == null) return null;

    // 2. Oferta aceptada
    final oferta = await _supabase
        .schema('muevete')
        .from('ofertas_chofer')
        .select('*')
        .eq('driver_id', driverId)
        .eq('estado', 'aceptada')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (oferta == null) return {'viaje': viaje, 'oferta': null, 'solicitud': null};

    // 3. Solicitud de transporte
    final solicitudId = oferta['solicitud_id'];
    Map<String, dynamic>? solicitud;
    if (solicitudId != null) {
      solicitud = await _supabase
          .schema('muevete')
          .from('solicitudes_transporte')
          .select('*')
          .eq('id', solicitudId)
          .maybeSingle();
    }

    return {'viaje': viaje, 'oferta': oferta, 'solicitud': solicitud};
  }

  // ─── STATS / KPIs ────────────────────────────────────────────────────

  /// Returns summary counts for the dashboard.
  static Future<Map<String, int>> getStats() async {
    final drivers = await _supabase
        .schema('muevete')
        .from('drivers')
        .select('id')
        .count(CountOption.exact);
    final driversOnline = await _supabase
        .schema('muevete')
        .from('drivers')
        .select('id')
        .eq('estado', true)
        .count(CountOption.exact);
    final trips = await _supabase
        .schema('muevete')
        .from('viajes')
        .select('id')
        .count(CountOption.exact);
    final tripsCompleted = await _supabase
        .schema('muevete')
        .from('viajes')
        .select('id')
        .eq('completado', true)
        .count(CountOption.exact);
    final requests = await _supabase
        .schema('muevete')
        .from('solicitudes_transporte')
        .select('id')
        .count(CountOption.exact);
    final requestsPending = await _supabase
        .schema('muevete')
        .from('solicitudes_transporte')
        .select('id')
        .eq('estado', 'pendiente')
        .count(CountOption.exact);
    final users = await _supabase
        .schema('muevete')
        .from('users')
        .select('user_id')
        .count(CountOption.exact);
    final pendingKyc = await _supabase
        .schema('muevete')
        .from('drivers')
        .select('id')
        .eq('revisado', false)
        .count(CountOption.exact);

    return {
      'total_drivers': drivers.count,
      'drivers_online': driversOnline.count,
      'total_trips': trips.count,
      'trips_completed': tripsCompleted.count,
      'total_requests': requests.count,
      'requests_pending': requestsPending.count,
      'total_users': users.count,
      'pending_kyc': pendingKyc.count,
    };
  }
}
