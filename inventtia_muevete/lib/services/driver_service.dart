import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/valoracion_model.dart';

/// Datos y operaciones del chofer que NO son dinero.
///
/// Tomar y cerrar viajes vive en las RPC (`fn_tomar_viaje`,
/// `fn_completar_viaje`, ver `TransportProvider`): aquí no se negocia ni se
/// escribe ningún precio. El flujo viejo de ofertas (crear oferta, escuchar
/// aceptaciones, suscribirse a solicitudes) se eliminó en H5.
class DriverService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Toggles the driver's online/offline status in both
  /// muevete.drivers and muevete.place tables.
  Future<void> toggleOnlineStatus(int driverId, bool online) async {
    // Update driver status
    await _supabase
        .schema('muevete')
        .from('drivers')
        .update({'estado': online})
        .eq('id', driverId);

    // Update place status
    await _supabase
        .schema('muevete')
        .from('place')
        .update({'estado': online})
        .eq('driver', driverId);
  }

  /// Updates the driver's current location in the muevete.place table.
  Future<void> updateDriverLocation(
    int driverId,
    double lat,
    double lon,
  ) async {
    await _supabase
        .schema('muevete')
        .from('place')
        .update({
          'latitude': lat,
          'longitude': lon,
        })
        .eq('driver', driverId);
  }

  /// Fetches the active trip for a driver from muevete.viajes.
  Future<Map<String, dynamic>?> getActiveTrip(int driverId, {String? userId}) async {
    var query = _supabase
        .schema('muevete')
        .from('viajes')
        .select()
        .eq('driver_id', driverId)
        .eq('completado', false);
        
    if (userId != null) {
      query = query.eq('user', userId);
    }

    final response = await query
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    return response;
  }

  /// Updates a trip's status in muevete.viajes.
  Future<void> updateTripStatus(
    int tripId, {
    bool? estado,
    bool? completado,
  }) async {
    final Map<String, dynamic> updateData = {};

    if (estado != null) {
      updateData['estado'] = estado;
    }
    if (completado != null) {
      updateData['completado'] = completado;
    }

    if (updateData.isNotEmpty) {
      await _supabase
          .schema('muevete')
          .from('viajes')
          .update(updateData)
          .eq('id', tripId);
    }
  }

  /// Creates a vehicle in muevete.vehiculos and assigns it to the driver.
  Future<Map<String, dynamic>> createVehicleForDriver({
    required int driverId,
    required int vehicleTypeId,
    required String marca,
    required String modelo,
    required String chapa,
    required String color,
    String? categoria,
    String? capacidad,
  }) async {
    // 1. Insert vehicle
    final vehicleRow = await _supabase
        .schema('muevete')
        .from('vehiculos')
        .insert({
          'marca': marca,
          'modelo': modelo,
          'chapa': chapa,
          'color': color,
          if (categoria != null) 'categoria': categoria,
          if (capacidad != null) 'capacidad': capacidad,
          'id_tipo_vehiculo': vehicleTypeId,
        })
        .select()
        .single();

    final vehicleId = vehicleRow['id'] as int;

    // 2. Assign to driver
    await _supabase
        .schema('muevete')
        .from('drivers')
        .update({'vehiculo': vehicleId})
        .eq('id', driverId);

    return vehicleRow;
  }

  /// Updates fields of an existing vehicle in muevete.vehiculos.
  Future<void> updateVehicle(int vehicleId, Map<String, dynamic> data) async {
    await _supabase
        .schema('muevete')
        .from('vehiculos')
        .update(data)
        .eq('id', vehicleId);
  }

  /// Upserts the driver location into muevete.place.
  /// If no place row exists for this driver, inserts one.
  Future<void> upsertDriverLocation({
    required int driverId,
    required int vehicleId,
    required double lat,
    required double lon,
    required bool online,
  }) async {
    await _supabase.schema('muevete').from('place').upsert(
      {
        'driver': driverId,
        'latitude': lat,
        'longitude': lon,
        'estado': online,
        'vehiculo_id': vehicleId,
      },
      onConflict: 'driver',
    );
  }

  /// Fetches pending transport requests near [lat]/[lon] within [radiusKm].
  /// NOTE: user_id references auth.users (not muevete.users), so we can't
  /// join to get client info from the REST API — fetch solicitudes only.
  Future<List<Map<String, dynamic>>> fetchNearbyPendingRequests(
    double lat,
    double lon,
    double radiusKm,
  ) async {
    final rows = await _supabase
        .schema('muevete')
        .from('solicitudes_transporte')
        .select(
          'id, user_id, lat_origen, lon_origen, lat_destino, lon_destino, '
          'tipo_vehiculo, precio_oferta, estado, direccion_origen, '
          'direccion_destino, distancia_km, expires_at, created_at, id_tipo_vehiculo',
        )
        .eq('estado', 'pendiente')
        .order('created_at', ascending: false)
        .limit(50);

    // Filter by radius client-side (Supabase Free tier lacks PostGIS).
    // Requests older than globalVisibilityDelay are shown to ALL drivers
    // (no distance filter) so they get maximum exposure.
    final now = DateTime.now();
    final nearby = <Map<String, dynamic>>[];
    for (final row in rows) {
      final originLat = (row['lat_origen'] as num?)?.toDouble();
      final originLon = (row['lon_origen'] as num?)?.toDouble();
      if (originLat == null || originLon == null) continue;

      // Check if request is old enough to skip distance filter
      final createdAtStr = row['created_at'] as String?;
      if (createdAtStr != null) {
        final createdAt = DateTime.tryParse(createdAtStr);
        if (createdAt != null &&
            now.difference(createdAt) > const Duration(minutes: 1)) {
          nearby.add(row);
          continue;
        }
      }

      final dist = _haversineDistance(lat, lon, originLat, originLon);
      if (dist <= radiusKm) {
        nearby.add(row);
      }
    }
    return nearby;
  }

  /// Subscribes to Realtime updates on a specific viaje row.
  /// [onUpdate] is called with the full updated row when it changes.
  RealtimeChannel subscribeToViaje(
    int viajeId,
    void Function(Map<String, dynamic> row) onUpdate,
  ) {
    return _supabase
        .channel('viaje_$viajeId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'muevete',
          table: 'viajes',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: viajeId.toString(),
          ),
          callback: (payload) {
            onUpdate(Map<String, dynamic>.from(payload.newRecord));
          },
        )
        .subscribe();
  }

  /// Fetches a full solicitud row by ID with all fields needed for the ride.
  Future<Map<String, dynamic>?> fetchSolicitudById(int solicitudId) async {
    return await _supabase
        .schema('muevete')
        .from('solicitudes_transporte')
        .select()
        .eq('id', solicitudId)
        .maybeSingle();
  }

  /// Fetches client info from muevete.users by auth UUID.
  /// Note: muevete.users uses `phone` (not `telefono`) and `image`.
  Future<Map<String, dynamic>?> fetchClientInfo(String userId) async {
    return await _supabase
        .schema('muevete')
        .from('users')
        .select('uuid, name, phone, photo_url')
        .eq('uuid', userId)
        .maybeSingle();
  }

  /// LEGACY: el flujo de precio fijo ya no abre canales propios desde este
  /// servicio (la lista de viajes disponibles la refresca `TransportProvider`).
  /// Se conserva el método para no romper a quien lo invoca al desconectarse.
  Future<void> unsubscribe() async {}

  /// Submits a rating for a completed trip.
  Future<void> submitRating({
    required int viajeId,
    required int driverId,
    required String userId,
    required int rating,
    String? comentario,
  }) async {
    await _supabase.schema('muevete').from('valoraciones_viaje').insert({
      'viaje_id': viajeId,
      'driver_id': driverId,
      'user_id': userId,
      'rating': rating,
      if (comentario != null && comentario.trim().isNotEmpty)
        'comentario': comentario.trim(),
    });
  }

  /// Returns the average rating for a driver, or null if no ratings exist.
  Future<double?> getDriverAverageRating(int driverId) async {
    final rows = await _supabase
        .schema('muevete')
        .from('valoraciones_viaje')
        .select('rating')
        .eq('driver_id', driverId);
    final list = List<Map<String, dynamic>>.from(rows);
    if (list.isEmpty) return null;
    final sum = list.fold<int>(0, (s, r) => s + (r['rating'] as int));
    return sum / list.length;
  }

  /// Returns all ratings for a driver, enriched with the client's name.
  Future<List<ValoracionModel>> getDriverRatings(int driverId) async {
    final rows = await _supabase
        .schema('muevete')
        .from('valoraciones_viaje')
        .select('*')
        .eq('driver_id', driverId)
        .order('created_at', ascending: false);

    final result = <ValoracionModel>[];
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final enriched = Map<String, dynamic>.from(row);
      // Fetch client name from muevete.users
      try {
        final userRow = await _supabase
            .schema('muevete')
            .from('users')
            .select('name')
            .eq('uuid', row['user_id'])
            .maybeSingle();
        enriched['user_name'] = userRow?['name'] as String?;
      } catch (_) {}
      result.add(ValoracionModel.fromJson(enriched));
    }
    return result;
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
    final lat1Rad = _degreesToRadians(lat1);
    final lat2Rad = _degreesToRadians(lat2);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1Rad) * cos(lat2Rad) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * pi / 180.0;
  }
}
