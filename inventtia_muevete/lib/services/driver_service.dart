import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/transport_request_model.dart';

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

  /// Inserts a driver offer into muevete.ofertas_chofer.
  Future<Map<String, dynamic>> makeOffer(
    int requestId,
    int driverId,
    double price,
    int estimatedMinutes, {
    String? message,
  }) async {
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

  /// Removes the realtime subscription for transport requests.
  Future<void> unsubscribe() async {
    if (_requestsChannel != null) {
      await _supabase.removeChannel(_requestsChannel!);
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
