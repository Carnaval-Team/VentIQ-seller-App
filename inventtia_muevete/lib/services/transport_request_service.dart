import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/tarifa_model.dart';

/// Acceso a las RPC del flujo de taxi con precio fijo.
///
/// Contrato: `docs/plan-taxi-precio-fijo/13-contrato-app-rpc.md`.
/// **Regla de oro: desde aquí nunca se envía un precio.** No existe parámetro
/// de precio en ninguna firma; si el cliente lo intentara, el servidor
/// recotiza y lo ignora.
class TransportRequestService {
  final SupabaseClient _supabase = Supabase.instance.client;

  RealtimeChannel? _solicitudChannel;
  RealtimeChannel? _disponiblesChannel;

  // ── Catálogo de vehículos (v_catalogo_vehiculos) ─────────────────────────

  /// Lee `muevete.v_catalogo_vehiculos` (ya viene ordenado por `orden`).
  ///
  /// Columnas: `id`, `tipo`, `nombre`, `orden`, `pasajeros_max`, `categoria`.
  /// `id` es lo que se manda como `p_id_tipo`.
  Future<List<CatalogoVehiculo>> catalogoVehiculos() async {
    final rows = await _supabase
        .schema('muevete')
        .from('v_catalogo_vehiculos')
        .select('id, tipo, nombre, orden, pasajeros_max, categoria');

    return List<Map<String, dynamic>>.from(rows)
        .map(CatalogoVehiculo.fromJson)
        .where((v) => v.id > 0)
        .toList();
  }

  // ── §3.1 fn_cotizar_viaje — preview (no escribe nada) ────────────────────

  /// Cotiza el viaje. Devuelve el jsonb crudo de `fn_cotizar_viaje`; la UI
  /// lo mapea con [Cotizacion.fromJson].
  Future<Map<String, dynamic>> cotizar({
    required double latOrigen,
    required double lonOrigen,
    required double latDestino,
    required double lonDestino,
    required int idTipo,
    DateTime? at,
    double? km,
    String? provincia,
    String? municipio,
  }) async {
    final res = await _supabase.schema('muevete').rpc(
      'fn_cotizar_viaje',
      params: {
        'p_lat_o': latOrigen,
        'p_lon_o': lonOrigen,
        'p_lat_d': latDestino,
        'p_lon_d': lonDestino,
        'p_id_tipo': idTipo,
        'p_at': (at ?? DateTime.now()).toUtc().toIso8601String(),
        'p_km': km,
        'p_provincia': provincia,
        'p_municipio': municipio,
      },
    );

    if (res is Map) return Map<String, dynamic>.from(res);
    return const <String, dynamic>{};
  }

  // ── §3.2 fn_crear_solicitud — publicar ──────────────────────────────────

  /// Publica la solicitud. El precio lo calcula el servidor; devuelve la fila
  /// completa de `muevete.solicitudes_transporte`.
  Future<Map<String, dynamic>> crearSolicitud({
    required double latOrigen,
    required double lonOrigen,
    required double latDestino,
    required double lonDestino,
    required int idTipo,
    required String dirOrigen,
    required String dirDestino,
    required double km,
    required String metodoPago, // 'efectivo' | 'wallet'
    String? provincia,
    String? municipio,
    int pasajeros = 1,
  }) async {
    final res = await _supabase.schema('muevete').rpc(
      'fn_crear_solicitud',
      params: {
        'p_lat_o': latOrigen,
        'p_lon_o': lonOrigen,
        'p_lat_d': latDestino,
        'p_lon_d': lonDestino,
        'p_id_tipo': idTipo,
        'p_dir_o': dirOrigen,
        'p_dir_d': dirDestino,
        'p_km': km,
        'p_metodo_pago': metodoPago,
        'p_provincia': provincia,
        'p_municipio': municipio,
        'p_pasajeros': pasajeros,
      },
    );

    if (res is Map) return Map<String, dynamic>.from(res);
    if (res is List && res.isNotEmpty && res.first is Map) {
      return Map<String, dynamic>.from(res.first as Map);
    }
    return const <String, dynamic>{};
  }

  // ── §3.3 fn_viajes_disponibles — lista del chofer ───────────────────────

  /// Viajes disponibles para el chofer autenticado (`setof jsonb`).
  Future<List<ViajeDisponible>> viajesDisponibles({
    double? lat,
    double? lon,
    int limite = 30,
  }) async {
    final res = await _supabase.schema('muevete').rpc(
      'fn_viajes_disponibles',
      params: {
        'p_lat': lat,
        'p_lon': lon,
        'p_limite': limite,
      },
    );

    final rows = res is List ? res : const <dynamic>[];
    return rows
        .whereType<Map>()
        .map((row) => ViajeDisponible.fromJson(Map<String, dynamic>.from(row)))
        .where((v) => v.solicitudId > 0)
        .toList();
  }

  // ── §3.4 fn_tomar_viaje — el primero gana ───────────────────────────────

  /// Toma el viaje. Si otro chofer llegó primero lanza `P0020 ya_tomado`.
  Future<Map<String, dynamic>> tomarViaje(int solicitudId) async {
    final res = await _supabase.schema('muevete').rpc(
      'fn_tomar_viaje',
      params: {'p_solicitud_id': solicitudId},
    );

    if (res is Map) return Map<String, dynamic>.from(res);
    return const <String, dynamic>{};
  }

  // ── §3.5 fn_completar_viaje — cerrar (no recibe precio) ─────────────────

  /// Cierra el viaje. Idempotente: la cola offline puede repetir la llamada.
  /// `p_espera_min` sólo se usa si el viaje no trae espera medida en servidor.
  Future<Map<String, dynamic>> completarViaje(
    int viajeId, {
    int? esperaMin,
  }) async {
    final res = await _supabase.schema('muevete').rpc(
      'fn_completar_viaje',
      params: {
        'p_viaje_id': viajeId,
        'p_espera_min': esperaMin,
      },
    );

    if (res is Map) return Map<String, dynamic>.from(res);
    return const <String, dynamic>{};
  }

  // ── §3.6 fn_cancelar_solicitud — cancelar (idempotente) ─────────────────

  Future<Map<String, dynamic>> cancelarSolicitud(
    int solicitudId, {
    String? motivo,
  }) async {
    final res = await _supabase.schema('muevete').rpc(
      'fn_cancelar_solicitud',
      params: {
        'p_solicitud_id': solicitudId,
        'p_motivo': motivo,
      },
    );

    if (res is Map) return Map<String, dynamic>.from(res);
    return const <String, dynamic>{};
  }

  // ── Lecturas de apoyo ───────────────────────────────────────────────────

  /// Devuelve la fila pública de una solicitud concreta, o null.
  Future<Map<String, dynamic>?> solicitudPorId(int solicitudId) async {
    try {
      final row = await _supabase
          .schema('muevete')
          .from('solicitudes_transporte')
          .select()
          .eq('id', solicitudId)
          .maybeSingle();
      return row == null ? null : Map<String, dynamic>.from(row);
    } catch (_) {
      return null;
    }
  }

  /// Solicitud pendiente más reciente del usuario (para reanudar el flujo).
  Future<Map<String, dynamic>?> getActiveRequest(String userId) async {
    final response = await _supabase
        .schema('muevete')
        .from('solicitudes_transporte')
        .select()
        .eq('user_id', userId)
        .eq('estado', 'pendiente')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    return response;
  }

  /// Datos de contacto del cliente (nombre y teléfono) para el chofer.
  Future<Map<String, dynamic>?> clienteDeUsuario(String userId) async {
    try {
      final row = await _supabase
          .schema('muevete')
          .from('users')
          .select('name, phone')
          .eq('uuid', userId)
          .maybeSingle();
      return row == null ? null : Map<String, dynamic>.from(row);
    } catch (_) {
      return null;
    }
  }

  /// Best-effort: viaje (`viajes.id`) asociado a una solicitud.
  /// Si la columna no existe en este despliegue devuelve null.
  Future<int?> viajeDeSolicitud(int solicitudId) async {
    try {
      final row = await _supabase
          .schema('muevete')
          .from('viajes')
          .select('id, completado')
          .eq('solicitud_id', solicitudId)
          .eq('completado', false)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return (row?['id'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  /// Conductores en línea cerca de un punto (para el mapa).
  Future<List<Map<String, dynamic>>> getNearbyDrivers(
    double lat,
    double lon,
    double radiusKm,
  ) async {
    final response = await _supabase
        .schema('muevete')
        .from('place')
        .select('''
          id,
          latitude,
          longitude,
          categoria,
          estado,
          vehiculo_id,
          drivers!place_driver_fkey (
            id,
            name,
            image,
            categoria,
            telefono
          )
        ''')
        .eq('estado', true);

    final List<Map<String, dynamic>> nearbyDrivers = [];
    for (final row in List<Map<String, dynamic>>.from(response)) {
      final driverLat = (row['latitude'] as num?)?.toDouble();
      final driverLon = (row['longitude'] as num?)?.toDouble();
      if (driverLat == null || driverLon == null) continue;
      final distance = _haversineDistance(lat, lon, driverLat, driverLon);
      if (distance <= radiusKm) {
        row['distance_km'] = distance;
        nearbyDrivers.add(row);
      }
    }

    nearbyDrivers.sort(
      (a, b) =>
          (a['distance_km'] as double).compareTo(b['distance_km'] as double),
    );
    return nearbyDrivers;
  }

  /// Enriches a driver data map with full driver + vehicle info.
  /// Joins: drivers -> vehiculos for marca/modelo/chapa/color.
  Future<void> _enrichDriverData(
      Map<String, dynamic> data, dynamic driverId) async {
    try {
      final driverRow = await _supabase
          .schema('muevete')
          .from('drivers')
          .select(
            'name, email, image, categoria, telefono, kyc, '
            'vehiculos!drivers_vehiculo_fkey(marca, modelo, chapa, color)',
          )
          .eq('id', driverId)
          .maybeSingle();

      if (driverRow != null) {
        data['driver_name'] = driverRow['name'];
        data['driver_email'] = driverRow['email'];
        data['driver_image'] = driverRow['image'];
        data['vehicle_info'] = driverRow['categoria'];
        final phone = driverRow['telefono'] as String?;
        data['driver_phone'] = phone;
        // "Verificado" means driver has a registered phone number
        data['driver_kyc'] = phone != null && phone.trim().isNotEmpty;
        final veh = driverRow['vehiculos'] as Map<String, dynamic>?;
        data['vehicle_marca'] = veh?['marca'];
        data['vehicle_modelo'] = veh?['modelo'];
        data['vehicle_chapa'] = veh?['chapa'];
        data['vehicle_color'] = veh?['color'];
      }

      // Average rating from valoraciones_viaje
      try {
        final ratingRows = await _supabase
            .schema('muevete')
            .from('valoraciones_viaje')
            .select('rating')
            .eq('driver_id', driverId);
        final ratingList = List<Map<String, dynamic>>.from(ratingRows);
        if (ratingList.isNotEmpty) {
          final sum =
              ratingList.fold<int>(0, (s, r) => s + (r['rating'] as int));
          data['driver_rating'] = sum / ratingList.length;
        }
      } catch (_) {}

      // Completed trips: solicitudes completadas asignadas a este chofer.
      try {
        final tripRows = await _supabase
            .schema('muevete')
            .from('solicitudes_transporte')
            .select('id')
            .eq('driver_id', driverId)
            .eq('estado', 'completada');
        data['trip_count'] = List<dynamic>.from(tripRows).length;
      } catch (_) {
        data['trip_count'] = 0;
      }
    } catch (_) {}
  }

  /// Datos del conductor (nombre, imagen, vehículo, rating, viajes).
  /// Se usa para pintar al conductor que tomó la solicitud.
  Future<Map<String, dynamic>?> getDriverDetails(int driverId) async {
    final data = <String, dynamic>{'driver_id': driverId};
    try {
      await _enrichDriverData(data, driverId);
      return data;
    } catch (_) {
      return null;
    }
  }

  // ── Realtime ────────────────────────────────────────────────────────────

  /// Escucha los cambios de estado de una solicitud concreta (cliente).
  /// Llama a [onUpdate] con la fila nueva cuando cambia `estado`/`driver_id`.
  void subscribeToSolicitud(
    int solicitudId,
    void Function(Map<String, dynamic> row) onUpdate,
  ) {
    _solicitudChannel?.unsubscribe();
    _solicitudChannel = _supabase
        .channel('solicitud_$solicitudId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'muevete',
          table: 'solicitudes_transporte',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: solicitudId.toString(),
          ),
          callback: (payload) {
            onUpdate(Map<String, dynamic>.from(payload.newRecord));
          },
        )
        .subscribe();
  }

  /// Escucha INSERT/UPDATE de `muevete.solicitudes_transporte` para refrescar
  /// la lista de viajes disponibles del chofer (regla del §6 del contrato).
  void subscribeToSolicitudesDisponibles(void Function() onCambio) {
    _disponiblesChannel?.unsubscribe();
    _disponiblesChannel = _supabase
        .channel('driver_solicitudes_disponibles')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'muevete',
          table: 'solicitudes_transporte',
          callback: (_) => onCambio(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'muevete',
          table: 'solicitudes_transporte',
          callback: (_) => onCambio(),
        )
        .subscribe();
  }

  /// Baja todas las suscripciones abiertas.
  Future<void> unsubscribe() async {
    final solicitud = _solicitudChannel;
    if (solicitud != null) {
      try {
        await _supabase.removeChannel(solicitud);
      } catch (_) {}
      _solicitudChannel = null;
    }
    final disponibles = _disponiblesChannel;
    if (disponibles != null) {
      try {
        await _supabase.removeChannel(disponibles);
      } catch (_) {}
      _disponiblesChannel = null;
    }
  }

  /// Haversine formula to calculate distance in km between two lat/lon points.
  double _haversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadiusKm = 6371.0;
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * pi / 180.0;
  }
}