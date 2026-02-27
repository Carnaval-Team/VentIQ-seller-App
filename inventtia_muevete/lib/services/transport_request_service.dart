import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/transport_request_model.dart';
import '../models/driver_offer_model.dart';

class TransportRequestService {
  final SupabaseClient _supabase = Supabase.instance.client;
  RealtimeChannel? _offersChannel;

  /// Creates a new transport request in muevete.solicitudes_transporte.
  Future<Map<String, dynamic>> createRequest(TransportRequestModel request) async {
    final response = await _supabase
        .schema('muevete')
        .from('solicitudes_transporte')
        .insert(request.toJson())
        .select()
        .single();

    return response;
  }

  /// Cancels a transport request by setting its estado to 'cancelada'.
  Future<void> cancelRequest(int requestId) async {
    await _supabase
        .schema('muevete')
        .from('solicitudes_transporte')
        .update({'estado': 'cancelada'})
        .eq('id', requestId);
  }

  /// Fetches the active (pending) transport request for a given user UUID.
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

  /// Queries muevete.place (online drivers) with JOIN to muevete.drivers
  /// for name and image. Filters by Haversine distance client-side.
  Future<List<Map<String, dynamic>>> getNearbyDrivers(
    double lat,
    double lon,
    double radiusKm,
  ) async {
    // Single JOIN: place -> drivers (name, image, categoria)
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

  /// Fetches all existing offers for a request, enriched with driver info.
  Future<List<DriverOfferModel>> getExistingOffers(int requestId) async {
    final rows = await _supabase
        .schema('muevete')
        .from('ofertas_chofer')
        .select('*, drivers!ofertas_chofer_driver_id_fkey(name, image, categoria)')
        .eq('solicitud_id', requestId)
        .order('created_at', ascending: true);

    return List<Map<String, dynamic>>.from(rows).map((row) {
      final driver = row['drivers'] as Map<String, dynamic>?;
      final enriched = Map<String, dynamic>.from(row);
      enriched['driver_name'] = driver?['name'];
      enriched['driver_image'] = driver?['image'];
      enriched['vehicle_info'] = driver?['categoria'];
      return DriverOfferModel.fromJson(enriched);
    }).toList();
  }

  /// Subscribes to driver offers for a given transport request using
  /// Supabase Realtime on the muevete.ofertas_chofer table.
  void subscribeToOffers(int requestId, Function(DriverOfferModel) onOffer) {
    _offersChannel = _supabase
        .channel('ofertas_chofer_$requestId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'muevete',
          table: 'ofertas_chofer',
          // Supabase Realtime filters require String values
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'solicitud_id',
            value: requestId.toString(),
          ),
          callback: (payload) async {
            final data = Map<String, dynamic>.from(payload.newRecord);
            // Enrich offer with driver name/image via a follow-up query
            final driverId = data['driver_id'];
            if (driverId != null) {
              try {
                final driverRow = await _supabase
                    .schema('muevete')
                    .from('drivers')
                    .select('name, image, categoria')
                    .eq('id', driverId)
                    .maybeSingle();
                if (driverRow != null) {
                  data['driver_name'] = driverRow['name'];
                  data['driver_image'] = driverRow['image'];
                  data['vehicle_info'] = driverRow['categoria'];
                }
              } catch (_) {}
            }
            final offer = DriverOfferModel.fromJson(data);
            onOffer(offer);
          },
        )
        .subscribe();
  }

  /// Accepts a driver offer: sets offer estado to 'aceptada' and
  /// updates the parent request estado to 'aceptada'.
  Future<void> acceptOffer(int offerId) async {
    // Update the offer status
    final offerResponse = await _supabase
        .schema('muevete')
        .from('ofertas_chofer')
        .update({'estado': 'aceptada'})
        .eq('id', offerId)
        .select()
        .single();

    // Update the parent request status
    final solicitudId = offerResponse['solicitud_id'];
    if (solicitudId != null) {
      await _supabase
          .schema('muevete')
          .from('solicitudes_transporte')
          .update({'estado': 'aceptada'})
          .eq('id', solicitudId);
    }
  }

  /// Removes the realtime subscription for offers.
  Future<void> unsubscribe() async {
    if (_offersChannel != null) {
      await _supabase.removeChannel(_offersChannel!);
      _offersChannel = null;
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
