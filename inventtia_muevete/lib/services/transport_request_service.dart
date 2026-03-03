import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/transport_request_model.dart';
import '../models/driver_offer_model.dart';
import '../models/notification_model.dart';
import 'notification_service.dart';

class TransportRequestService {
  final SupabaseClient _supabase = Supabase.instance.client;
  RealtimeChannel? _offersChannel;
  RealtimeChannel? _solicitudChannel;
  RealtimeChannel? _ofertaUpdateChannel;

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

  /// Enriches an offer data map with full driver + vehicle info.
  /// Joins: drivers -> vehiculos for marca/modelo/chapa/color.
  /// Also counts completed offers for trip count.
  Future<void> _enrichOfferData(
      Map<String, dynamic> data, dynamic driverId) async {
    try {
      // drivers JOIN vehiculos (via drivers.vehiculo FK)
      final driverRow = await _supabase
          .schema('muevete')
          .from('drivers')
          .select(
            'name, image, categoria, telefono, kyc, '
            'vehiculos!drivers_vehiculo_fkey(marca, modelo, chapa, color)',
          )
          .eq('id', driverId)
          .maybeSingle();

      if (driverRow != null) {
        data['driver_name'] = driverRow['name'];
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

      // Count completed trips: ofertas aceptadas where the solicitud is completada
      final tripRows = await _supabase
          .schema('muevete')
          .from('ofertas_chofer')
          .select('solicitud_id, solicitudes_transporte!ofertas_chofer_solicitud_id_fkey(estado)')
          .eq('driver_id', driverId)
          .eq('estado', 'aceptada');
      int completedCount = 0;
      for (final row in (tripRows as List)) {
        final solicitud = row['solicitudes_transporte'] as Map<String, dynamic>?;
        if (solicitud?['estado'] == 'completada') completedCount++;
      }
      data['trip_count'] = completedCount;
    } catch (_) {}
  }

  /// Fetches all existing offers for a request, enriched with full driver info.
  Future<List<DriverOfferModel>> getExistingOffers(int requestId) async {
    final rows = await _supabase
        .schema('muevete')
        .from('ofertas_chofer')
        .select('*')
        .eq('solicitud_id', requestId)
        .order('created_at', ascending: true);

    final result = <DriverOfferModel>[];
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final enriched = Map<String, dynamic>.from(row);
      final driverId = enriched['driver_id'];
      if (driverId != null) await _enrichOfferData(enriched, driverId);
      result.add(DriverOfferModel.fromJson(enriched));
    }
    return result;
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
            final driverId = data['driver_id'];
            if (driverId != null) await _enrichOfferData(data, driverId);
            final offer = DriverOfferModel.fromJson(data);
            onOffer(offer);
          },
        )
        .subscribe();
  }

  /// Accepts a driver offer: sets offer estado to 'aceptada' and
  /// updates the parent request estado to 'aceptada'.
  /// Returns the full solicitud row (contains destination coords).
  Future<Map<String, dynamic>> acceptOffer(int offerId) async {
    // Update the offer status
    final offerResponse = await _supabase
        .schema('muevete')
        .from('ofertas_chofer')
        .update({'estado': 'aceptada'})
        .eq('id', offerId)
        .select()
        .single();

    // Update the parent request and return full solicitud row
    final solicitudId = offerResponse['solicitud_id'];
    if (solicitudId != null) {
      final solicitud = await _supabase
          .schema('muevete')
          .from('solicitudes_transporte')
          .update({'estado': 'aceptada'})
          .eq('id', solicitudId)
          .select()
          .single();

      // Reject all other offers for this solicitud
      await _supabase
          .schema('muevete')
          .from('ofertas_chofer')
          .update({'estado': 'rechazada'})
          .eq('solicitud_id', solicitudId)
          .neq('id', offerId)
          .neq('estado', 'aceptada');

      // Reject all other pending offers this driver has with OTHER clients
      final driverId = offerResponse['driver_id'];
      if (driverId != null) {
        await _supabase
            .schema('muevete')
            .from('ofertas_chofer')
            .update({'estado': 'rechazada'})
            .eq('driver_id', driverId)
            .eq('estado', 'pendiente');
      }

      // Notify the driver that their offer was accepted
      try {
        final driverId = offerResponse['driver_id'];
        if (driverId != null) {
          // Get driver's auth UUID from muevete.drivers
          final driverRow = await _supabase
              .schema('muevete')
              .from('drivers')
              .select('uuid')
              .eq('id', driverId)
              .maybeSingle();
          final driverUuid = driverRow?['uuid'] as String?;
          if (driverUuid != null) {
            await NotificationService().createNotification(
              userUuid: driverUuid,
              tipo: NotificationType.ofertaAceptada,
              titulo: 'Oferta aceptada',
              mensaje: 'Un pasajero aceptó tu oferta. Dirígete al punto de recogida.',
              data: {'solicitud_id': solicitudId, 'oferta_id': offerId},
            );
          }
        }
      } catch (_) {}

      return Map<String, dynamic>.from(solicitud);
    }
    return {};
  }

  /// Subscribes to UPDATE events on a specific solicitud.
  /// [onEstadoChange] is called with the new estado string when it changes.
  void subscribeToSolicitudChanges(
    int solicitudId,
    void Function(String newEstado) onEstadoChange,
  ) {
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
            final newEstado = payload.newRecord['estado'] as String?;
            if (newEstado != null) onEstadoChange(newEstado);
          },
        )
        .subscribe();
  }

  /// Subscribes to UPDATE events on ofertas for a solicitud.
  /// [onOfertaUpdate] is called with the updated raw offer row.
  void subscribeToOfertaUpdates(
    int solicitudId,
    void Function(Map<String, dynamic> row) onOfertaUpdate,
  ) {
    _ofertaUpdateChannel = _supabase
        .channel('oferta_update_$solicitudId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'muevete',
          table: 'ofertas_chofer',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'solicitud_id',
            value: solicitudId.toString(),
          ),
          callback: (payload) {
            onOfertaUpdate(Map<String, dynamic>.from(payload.newRecord));
          },
        )
        .subscribe();
  }

  /// Removes all realtime subscriptions.
  Future<void> unsubscribe() async {
    if (_offersChannel != null) {
      try {
        await _supabase.removeChannel(_offersChannel!);
      } catch (_) {}
      _offersChannel = null;
    }
    if (_solicitudChannel != null) {
      try {
        await _supabase.removeChannel(_solicitudChannel!);
      } catch (_) {}
      _solicitudChannel = null;
    }
    if (_ofertaUpdateChannel != null) {
      try {
        await _supabase.removeChannel(_ofertaUpdateChannel!);
      } catch (_) {}
      _ofertaUpdateChannel = null;
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
