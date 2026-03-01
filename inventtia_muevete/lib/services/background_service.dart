import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../utils/constants.dart';
import 'local_notification_service.dart';

class BackgroundService {
  static final FlutterBackgroundService _service = FlutterBackgroundService();

  static Future<void> init() async {
    if (kIsWeb) return;
    await _service.configure(
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onStart,
        onBackground: _onIosBackground,
      ),
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        isForegroundMode: true,
        autoStart: false,
        autoStartOnBoot: true,
        foregroundServiceNotificationId: 888,
        initialNotificationTitle: 'Muevete activo',
        initialNotificationContent: 'Conectado y recibiendo solicitudes',
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
    );
  }

  /// Start the service passing user data.
  /// Retries up to [maxRetries] times with [retryDelay] between attempts.
  /// Returns true if the service started successfully, false otherwise.
  static Future<bool> start({
    required String userUuid,
    required String role,
    int? driverId,
    double? lat,
    double? lon,
    int maxRetries = 10,
    Duration retryDelay = const Duration(seconds: 10),
  }) async {
    if (kIsWeb) return true;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final isRunning = await _service.isRunning();
        if (isRunning) {
          _service.invoke('configure', {
            'userUuid': userUuid,
            'role': role,
            if (driverId != null) 'driverId': driverId,
            if (lat != null) 'lat': lat,
            if (lon != null) 'lon': lon,
          });
          return true;
        }

        await _service.startService();

        // Wait and verify the service actually started
        await Future.delayed(const Duration(seconds: 2));
        final running = await _service.isRunning();
        if (running) {
          _service.invoke('configure', {
            'userUuid': userUuid,
            'role': role,
            if (driverId != null) 'driverId': driverId,
            if (lat != null) 'lat': lat,
            if (lon != null) 'lon': lon,
          });
          debugPrint('[BackgroundService] Started on attempt $attempt');
          return true;
        }

        debugPrint('[BackgroundService] Attempt $attempt/$maxRetries failed - service not running');
      } catch (e) {
        debugPrint('[BackgroundService] Attempt $attempt/$maxRetries error: $e');
      }

      if (attempt < maxRetries) {
        await Future.delayed(retryDelay);
      }
    }

    debugPrint('[BackgroundService] Failed to start after $maxRetries attempts');
    return false;
  }

  /// Stop the background service.
  static Future<void> stop() async {
    if (kIsWeb) return;
    _service.invoke('stop');
  }

  /// Send updated location to the service (from UI).
  static void updateLocation(double lat, double lon) {
    if (kIsWeb) return;
    _service.invoke('updateLocation', {'lat': lat, 'lon': lon});
  }

  /// Listen for location updates coming FROM the background service.
  static Stream<Map<String, dynamic>?> get onLocationUpdate {
    if (kIsWeb) return const Stream.empty();
    return _service.on('locationUpdate');
  }

  /// Listen for notification events from the service.
  static Stream<Map<String, dynamic>?> get onNotification {
    if (kIsWeb) return const Stream.empty();
    return _service.on('notification');
  }
}

// ─── Isolate entry points ───

@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    DartPluginRegistrant.ensureInitialized();
  } catch (_) {}
  return true;
}

@pragma('vm:entry-point')
Future<void> _onStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    DartPluginRegistrant.ensureInitialized();
  } catch (_) {}

  // Initialize local notifications inside the isolate.
  final localNotif = LocalNotificationService();
  await localNotif.init();

  // Reuse Supabase if already initialized (same isolate as UI), otherwise init.
  SupabaseClient supabase;
  try {
    supabase = Supabase.instance.client;
  } catch (_) {
    await Supabase.initialize(
      url: SupabaseConfig.supabaseUrl,
      anonKey: SupabaseConfig.supabaseAnonKey,
    );
    supabase = Supabase.instance.client;
  }

  String? userUuid;
  String? role;
  int? driverId;
  double currentLat = 0;
  double currentLon = 0;

  RealtimeChannel? requestsChannel;
  RealtimeChannel? requestsUpdateChannel;
  RealtimeChannel? offersChannel;
  RealtimeChannel? notificationsChannel;
  StreamSubscription<Position>? gpsSubscription;
  Timer? radiusExpansionTimer;

  // Pending requests for expanding radius (driver only)
  final List<Map<String, dynamic>> pendingRequests = [];

  // ── Stop handler ──
  service.on('stop').listen((_) async {
    gpsSubscription?.cancel();
    radiusExpansionTimer?.cancel();
    if (requestsChannel != null) supabase.removeChannel(requestsChannel!);
    if (requestsUpdateChannel != null) {
      supabase.removeChannel(requestsUpdateChannel!);
    }
    if (offersChannel != null) supabase.removeChannel(offersChannel!);
    if (notificationsChannel != null) {
      supabase.removeChannel(notificationsChannel!);
    }
    await service.stopSelf();
  });

  // ── Location updates from UI ──
  service.on('updateLocation').listen((data) {
    if (data != null) {
      currentLat = (data['lat'] as num).toDouble();
      currentLon = (data['lon'] as num).toDouble();
    }
  });

  // ── Configure handler — receives user data and sets up subscriptions ──
  service.on('configure').listen((data) async {
    if (data == null) return;

    userUuid = data['userUuid'] as String?;
    role = data['role'] as String?;
    driverId = data['driverId'] as int?;
    currentLat = (data['lat'] as num?)?.toDouble() ?? 0;
    currentLon = (data['lon'] as num?)?.toDouble() ?? 0;

    if (userUuid == null || role == null) return;

    // ── Update foreground notification with role info ──
    if (service is AndroidServiceInstance) {
      if (role == 'driver') {
        service.setForegroundNotificationInfo(
          title: 'Muevete - Conductor',
          content: 'Ubicación activa · Esperando solicitudes',
        );
      } else {
        service.setForegroundNotificationInfo(
          title: 'Muevete - Pasajero',
          content: 'Conectado · Esperando ofertas',
        );
      }
    }

    // ── Subscribe to notificaciones ──
    notificationsChannel = supabase
        .channel('bg_notif_$userUuid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'muevete',
          table: 'notificaciones',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_uuid',
            value: userUuid!,
          ),
          callback: (payload) {
            final rec = payload.newRecord;
            localNotif.showGeneric(
              id: rec['id'] is int ? rec['id'] : 2000,
              title: rec['titulo']?.toString() ?? 'Muevete',
              body: rec['mensaje']?.toString() ?? '',
            );
            service.invoke('notification', rec);
          },
        )
        .subscribe();

    // ── Driver-specific subscriptions ──
    if (role == 'driver') {
      final steps = AppConstants.radiusSteps;

      void notifyRequest(Map<String, dynamic> rec) {
        localNotif.showRideRequest(
          title: 'Nueva solicitud de viaje',
          body: rec['direccion_origen']?.toString() ??
              'Un pasajero solicita un viaje',
          solicitudId: rec['id']?.toString(),
        );
        service.invoke('notification', {
          'type': 'ride_request',
          ...rec,
        });
      }

      // Listen for new ride requests — add to pending list
      requestsChannel = supabase
          .channel('bg_solicitudes_driver')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'muevete',
            table: 'solicitudes_transporte',
            callback: (payload) {
              final rec = payload.newRecord;
              final originLat =
                  double.tryParse(rec['lat_origen']?.toString() ?? '');
              final originLon =
                  double.tryParse(rec['lon_origen']?.toString() ?? '');
              final solicitudId = rec['id'];

              if (originLat == null || originLon == null) return;

              final dist =
                  _haversine(currentLat, currentLon, originLat, originLon);
              final inRange = dist <= steps[0];

              pendingRequests.add({
                'data': rec,
                'solicitudId': solicitudId,
                'radiusIndex': 0,
                'notified': inRange,
                'addedAt': DateTime.now(),
                'originLat': originLat,
                'originLon': originLon,
              });

              if (inRange) notifyRequest(rec);
            },
          )
          .subscribe();

      // Listen for solicitud status changes — remove non-pending
      requestsUpdateChannel = supabase
          .channel('bg_solicitudes_update')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'muevete',
            table: 'solicitudes_transporte',
            callback: (payload) {
              final rec = payload.newRecord;
              final estado = rec['estado']?.toString();
              if (estado != null && estado != 'pendiente') {
                pendingRequests.removeWhere(
                    (r) => r['solicitudId'] == rec['id']);
              }
            },
          )
          .subscribe();

      // Listen for offers — remove solicitud that got an offer
      offersChannel = supabase
          .channel('bg_ofertas_driver')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'muevete',
            table: 'ofertas_chofer',
            callback: (payload) {
              final rec = payload.newRecord;
              final solId = rec['solicitud_id'];
              if (solId != null) {
                pendingRequests
                    .removeWhere((r) => r['solicitudId'] == solId);
              }
            },
          )
          .subscribe();

      // Expanding radius timer
      radiusExpansionTimer = Timer.periodic(
        AppConstants.radiusExpansionInterval,
        (_) {
          final now = DateTime.now();
          // Clean up requests older than 5 minutes
          pendingRequests.removeWhere((r) =>
              now.difference(r['addedAt'] as DateTime).inMinutes >= 5);

          for (final req in pendingRequests) {
            if (req['notified'] == true) continue;

            final idx = req['radiusIndex'] as int;
            if (idx < steps.length - 1) {
              req['radiusIndex'] = idx + 1;
            }

            final newRadius = steps[req['radiusIndex'] as int];
            final dist = _haversine(
              currentLat,
              currentLon,
              req['originLat'] as double,
              req['originLon'] as double,
            );

            if (dist <= newRadius) {
              req['notified'] = true;
              notifyRequest(req['data'] as Map<String, dynamic>);
            }
          }
        },
      );

      // Start GPS tracking to update driver location
      _startGpsTracking(
        service: service,
        supabase: supabase,
        driverId: driverId,
        onPosition: (lat, lon) {
          currentLat = lat;
          currentLon = lon;
        },
        gpsSubscriptionSetter: (sub) => gpsSubscription = sub,
      );
    }

    // ── Client-specific subscriptions ──
    if (role == 'client') {
      // Listen for driver offers on any of the user's active requests.
      offersChannel = supabase
          .channel('bg_ofertas_client_$userUuid')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'muevete',
            table: 'ofertas_chofer',
            callback: (payload) {
              final rec = payload.newRecord;
              localNotif.showDriverOffer(
                title: 'Nueva oferta de conductor',
                body: 'Un conductor te ha hecho una oferta',
                solicitudId: rec['solicitud_id']?.toString(),
              );
              service.invoke('notification', {
                'type': 'driver_offer',
                ...rec,
              });
            },
          )
          .subscribe();
    }
  });

  // Update the foreground notification periodically
  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
  }
}

void _startGpsTracking({
  required ServiceInstance service,
  required SupabaseClient supabase,
  required int? driverId,
  required void Function(double lat, double lon) onPosition,
  required void Function(StreamSubscription<Position>) gpsSubscriptionSetter,
}) {
  final sub = Geolocator.getPositionStream(
    locationSettings: AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
      intervalDuration: const Duration(seconds: 10),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'Muevete - Ubicación activa',
        notificationText: 'Rastreando tu ubicación en segundo plano',
        enableWakeLock: true,
      ),
    ),
  ).listen((position) async {
    final lat = position.latitude;
    final lon = position.longitude;
    onPosition(lat, lon);

    // Send to UI
    service.invoke('locationUpdate', {'lat': lat, 'lon': lon});

    // Update foreground notification with timestamp
    if (service is AndroidServiceInstance) {
      final now = DateTime.now();
      final time = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      service.setForegroundNotificationInfo(
        title: 'Muevete - Conductor',
        content: 'Rastreando ubicación · Última: $time',
      );
    }

    // Update driver location in Supabase
    if (driverId != null) {
      try {
        await supabase
            .schema('muevete')
            .from('place')
            .update({'latitude': lat, 'longitude': lon})
            .eq('driver', driverId);
      } catch (_) {}
    }
  });
  gpsSubscriptionSetter(sub);
}

/// Haversine distance in km.
double _haversine(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  final dLat = _toRad(lat2 - lat1);
  final dLon = _toRad(lon2 - lon1);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
  return r * 2 * atan2(sqrt(a), sqrt(1 - a));
}

double _toRad(double deg) => deg * pi / 180;
