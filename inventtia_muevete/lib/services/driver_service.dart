import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/transport_request_model.dart';
import '../models/notification_model.dart';
import 'notification_service.dart';

class DriverService {
  final SupabaseClient _supabase = Supabase.instance.client;
  RealtimeChannel? _requestsChannel;

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

  /// Subscribes to new transport requests using Supabase Realtime
  /// on the muevete.solicitudes_transporte table.
  /// Filters incoming requests by distance from the driver's position.
  void subscribeToRequests(
    double lat,
    double lon,
    double radiusKm,
    Function(TransportRequestModel) onRequest,
  ) {
    _requestsChannel = _supabase
        .channel('solicitudes_transporte_driver')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'muevete',
          table: 'solicitudes_transporte',
          callback: (payload) {
            final data = payload.newRecord;
            final request = TransportRequestModel.fromJson(data);

            // Filter by distance from driver's current position
            final originLat = double.tryParse(
              data['lat_origen']?.toString() ?? '',
            );
            final originLon = double.tryParse(
              data['lon_origen']?.toString() ?? '',
            );

            if (originLat != null && originLon != null) {
              final distance = _haversineDistance(
                lat,
                lon,
                originLat,
                originLon,
              );
              if (distance <= radiusKm) {
                onRequest(request);
              }
            }
          },
        )
        .subscribe();
  }

  /// Returns true if [driverId] already has an offer for [requestId].
  Future<bool> hasExistingOffer(int requestId, int driverId) async {
    final existing = await _supabase
        .schema('muevete')
        .from('ofertas_chofer')
        .select('id')
        .eq('solicitud_id', requestId)
        .eq('driver_id', driverId)
        .maybeSingle();
    return existing != null;
  }

  /// Inserts a driver offer into muevete.ofertas_chofer.
  /// Throws if the driver already has an offer for this request.
  Future<Map<String, dynamic>> makeOffer(
    int requestId,
    int driverId,
    double price,
    int estimatedMinutes, {
    String? message,
  }) async {
    // Guard: no duplicate offers
    final duplicate = await hasExistingOffer(requestId, driverId);
    if (duplicate) {
      throw Exception('Ya enviaste una oferta para esta solicitud');
    }

    final offerData = <String, dynamic>{
      'solicitud_id': requestId,
      'driver_id': driverId,
      'precio': price,
      'tiempo_estimado': estimatedMinutes,
      'estado': 'pendiente',
    };

    if (message != null) {
      offerData['mensaje'] = message;
    }

    final response = await _supabase
        .schema('muevete')
        .from('ofertas_chofer')
        .insert(offerData)
        .select()
        .single();

    // Notify client about new offer
    try {
      final solicitud = await fetchSolicitudById(requestId);
      final clientUuid = solicitud?['user_id'] as String?;
      if (clientUuid != null) {
        await NotificationService().createNotification(
          userUuid: clientUuid,
          tipo: NotificationType.nuevaOferta,
          titulo: 'Nueva oferta',
          mensaje: 'Un conductor te ofrece viaje por Gs. ${price.toInt()}',
          data: {'solicitud_id': requestId, 'oferta_id': response['id']},
        );
      }
    } catch (_) {}

    return response;
  }

  /// Fetches the active trip for a driver from muevete.viajes.
  Future<Map<String, dynamic>?> getActiveTrip(int driverId) async {
    final response = await _supabase
        .schema('muevete')
        .from('viajes')
        .select()
        .eq('driver_id', driverId)
        .eq('completado', false)
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

  /// Creates a new viaje in muevete.viajes when a ride starts.
  /// Returns the created viaje row with its id.
  Future<Map<String, dynamic>> createViaje({
    required int driverId,
    required String userId,       // auth.users UUID
    required double latDestino,   // client's destination lat
    required double lonDestino,   // client's destination lon
    String? userDisplay,
    String? telefono,
  }) async {
    final row = await _supabase
        .schema('muevete')
        .from('viajes')
        .insert({
          'driver_id': driverId,
          'user': userId,
          'estado': false,           // false = going to pickup, true = trip started
          'completado': false,
          'latitud_cliente': latDestino.toString(),
          'longitud_cliente': lonDestino.toString(),
          if (userDisplay != null) 'user_display': userDisplay,
          if (telefono != null) 'telefono': telefono,
        })
        .select()
        .single();
    return row;
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

  /// Subscribes to Realtime UPDATE on ofertas_chofer for this driver.
  /// Fires [onAccepted] when an offer's estado changes to 'aceptada'.
  RealtimeChannel subscribeToMyOfferAcceptances(
    int driverId,
    void Function(Map<String, dynamic> offer) onAccepted,
  ) {
    return _supabase
        .channel('offer_accept_$driverId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'muevete',
          table: 'ofertas_chofer',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'driver_id',
            value: driverId.toString(),
          ),
          callback: (payload) {
            final row = Map<String, dynamic>.from(payload.newRecord);
            if (row['estado'] == 'aceptada') {
              onAccepted(row);
            }
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

  /// Updates solicitud estado (e.g. 'completada').
  Future<void> updateSolicitudEstado(int solicitudId, String estado) async {
    await _supabase
        .schema('muevete')
        .from('solicitudes_transporte')
        .update({'estado': estado})
        .eq('id', solicitudId);
  }

  /// Removes the realtime subscription for transport requests.
  Future<void> unsubscribe() async {
    if (_requestsChannel != null) {
      try {
        await _supabase.removeChannel(_requestsChannel!);
      } catch (_) {
        // realtime_client has a known Web bug with List<Binding> cast on unsubscribe
      }
      _requestsChannel = null;
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
