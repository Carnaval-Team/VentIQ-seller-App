import 'package:flutter/foundation.dart';
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

  /// Fetches history trail for a single driver (on-demand).
  static Future<List<Map<String, dynamic>>> getDriverHistory(
    int driverId, {
    int limit = 20,
  }) async {
    final rows = await _supabase
        .schema('muevete')
        .from('track_place_history')
        .select('latitude, longitude, created_at')
        .eq('driver_id', driverId)
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows);
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

  // ─── SOLICITUDES DE PLAN (CARGA) ─────────────────────────────────────────

  /// Lista todas las solicitudes de activación de plan.
  /// [estado] puede ser null (todas), 'pendiente', 'aprobada' o 'rechazada'.
  static Future<List<Map<String, dynamic>>> getSolicitudesPlan(
      {String? estado}) async {
    debugPrint('[MueveteService.getSolicitudesPlan] iniciando query estado=$estado');

    // Query explícita por caso para evitar problemas de encadenamiento inmutable
    final List rows;
    if (estado != null) {
      rows = await _supabase
          .schema('muevete')
          .from('solicitudes_plan')
          .select('*')
          .eq('estado', estado)
          .order('created_at', ascending: false);
    } else {
      rows = await _supabase
          .schema('muevete')
          .from('solicitudes_plan')
          .select('*')
          .order('created_at', ascending: false);
    }
    final List<Map<String, dynamic>> result =
        List<Map<String, dynamic>>.from(rows);

    debugPrint('[MueveteService.getSolicitudesPlan] filas obtenidas: ${result.length}');
    for (final r in result) {
      debugPrint('[MueveteService.getSolicitudesPlan]  row → id=${r['id']} usuario_uuid=${r['usuario_uuid']} plan=${r['plan_codigo']} estado=${r['estado']} evidencia=${r['evidencia_url']}');
    }

    // Enriquecer con datos de usuario (muevete.users) y plan (muevete.planes)
    for (final row in result) {
      // Datos del usuario
      try {
        final uid = row['usuario_uuid'] as String?;
        debugPrint('[MueveteService.getSolicitudesPlan] buscando user uuid=$uid');
        if (uid != null) {
          final userRow = await _supabase
              .schema('muevete')
              .from('users')
              .select('name, email')
              .eq('uuid', uid)
              .maybeSingle();
          debugPrint('[MueveteService.getSolicitudesPlan] user result: $userRow');
          if (userRow != null) {
            row['usuario_nombre'] = userRow['name'];
            row['usuario_email'] = userRow['email'];
          }
        }
      } catch (e) {
        debugPrint('[MueveteService.getSolicitudesPlan] ERROR enrich user: $e');
      }

      // Datos del plan
      try {
        final planCodigo = row['plan_codigo'] as String?;
        debugPrint('[MueveteService.getSolicitudesPlan] buscando plan codigo=$planCodigo');
        if (planCodigo != null) {
          final planRow = await _supabase
              .schema('muevete')
              .from('planes')
              .select('nombre, precio_mensual')
              .eq('codigo', planCodigo)
              .maybeSingle();
          debugPrint('[MueveteService.getSolicitudesPlan] plan result: $planRow');
          if (planRow != null) {
            row['planes'] = planRow;
          }
        }
      } catch (e) {
        debugPrint('[MueveteService.getSolicitudesPlan] ERROR enrich plan: $e');
      }
    }

    debugPrint('[MueveteService.getSolicitudesPlan] resultado final: ${result.length} solicitudes');
    return result;
  }

  /// Cuenta solicitudes pendientes de plan.
  static Future<int> countSolicitudesPlanPendientes() async {
    final res = await _supabase
        .schema('muevete')
        .from('solicitudes_plan')
        .select('id')
        .eq('estado', 'pendiente')
        .count(CountOption.exact);
    return res.count;
  }

  /// Aprueba una solicitud de plan: verifica que el código de transferencia
  /// no esté duplicado, activa la suscripción vía RPC SECURITY DEFINER.
  /// [fechaVencimiento] debe ser el día 2 de un mes futuro. Si es null usa
  /// el próximo día 2 después de 1 mes desde hoy.
  static Future<void> aprobarSolicitudPlan({
    required int solicitudId,
    required String adminUuid,
    required String codigoTransferencia,
    String? observaciones,
    DateTime? fechaVencimiento,
  }) async {
    // Verificar unicidad del código de transferencia antes de llamar al RPC
    final existente = await _supabase
        .schema('muevete')
        .from('solicitudes_plan')
        .select('id')
        .eq('codigo_transferencia', codigoTransferencia)
        .maybeSingle();

    if (existente != null) {
      throw Exception(
          'El código de transferencia "$codigoTransferencia" ya fue utilizado. Verifique el comprobante.');
    }

    final fechaStr = fechaVencimiento != null
        ? '${fechaVencimiento.year}-${fechaVencimiento.month.toString().padLeft(2, '0')}-02'
        : null;

    await _supabase.schema('muevete').rpc('fn_aprobar_solicitud_plan', params: {
      'p_solicitud_id': solicitudId,
      'p_admin_uuid': adminUuid,
      'p_codigo_transferencia': codigoTransferencia,
      'p_observaciones': observaciones,
      if (fechaStr != null) 'p_fecha_vencimiento': fechaStr,
    });
  }

  /// Rechaza una solicitud de plan con observaciones.
  static Future<void> rechazarSolicitudPlan({
    required int solicitudId,
    required String adminUuid,
    required String observaciones,
  }) async {
    await _supabase.schema('muevete').rpc('fn_rechazar_solicitud_plan', params: {
      'p_solicitud_id': solicitudId,
      'p_admin_uuid': adminUuid,
      'p_observaciones': observaciones,
    });
  }

  // ─── CARGAS (FREIGHT) ─────────────────────────────────────────────────────

  /// Fetches all cargas with shipper and carrier info.
  static Future<List<Map<String, dynamic>>> getCargas({String? estado}) async {
    final List rows;
    const select = '''
      *, 
      app_nom_tipo_carga!cargas_tipo_carga_id_fkey(nombre, abreviacion),
      app_nom_tipo_equipo!cargas_tipo_equipo_id_fkey(nombre, abreviacion),
      app_nom_tipo_mercancia!cargas_tipo_mercancia_id_fkey(nombre, codigo)
    ''';

    if (estado != null) {
      rows = await _supabase
          .schema('muevete')
          .from('cargas')
          .select(select)
          .eq('estado', estado)
          .order('created_at', ascending: false);
    } else {
      rows = await _supabase
          .schema('muevete')
          .from('cargas')
          .select(select)
          .order('created_at', ascending: false);
    }

    final result = List<Map<String, dynamic>>.from(rows);

    // Enrich with shipper name (from drivers table via uuid)
    for (final row in result) {
      try {
        final shipperUuid = row['shipper_id'] as String?;
        if (shipperUuid != null) {
          final drv = await _supabase
              .schema('muevete')
              .from('drivers')
              .select('name, email')
              .eq('uuid', shipperUuid)
              .maybeSingle();
          row['shipper_name'] = drv?['name'];
          row['shipper_email'] = drv?['email'];
        }
      } catch (_) {}

      // Carrier name
      try {
        final carrierId = row['carrier_driver_id'] as int?;
        if (carrierId != null) {
          final drv = await _supabase
              .schema('muevete')
              .from('drivers')
              .select('name, email')
              .eq('id', carrierId)
              .maybeSingle();
          row['carrier_name'] = drv?['name'];
          row['carrier_email'] = drv?['email'];
        }
      } catch (_) {}
    }

    return result;
  }

  /// Fetches the estado nomenclator (app_nom_estado).
  static Future<List<Map<String, dynamic>>> getEstadosNomenclador() async {
    final rows = await _supabase
        .schema('muevete')
        .from('app_nom_estado')
        .select('*')
        .eq('activo', true)
        .order('orden', ascending: true);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Changes the state of a carga via RPC fn_cambiar_estado_carga.
  static Future<void> cambiarEstadoCarga({
    required int cargaId,
    required String estadoCodigo,
    String? usuarioUuid,
    String? motivo,
  }) async {
    await _supabase.schema('muevete').rpc('fn_cambiar_estado_carga', params: {
      'p_carga_id': cargaId,
      'p_estado_codigo': estadoCodigo,
      if (usuarioUuid != null) 'p_usuario_uuid': usuarioUuid,
      if (motivo != null) 'p_motivo': motivo,
    });
  }
}
