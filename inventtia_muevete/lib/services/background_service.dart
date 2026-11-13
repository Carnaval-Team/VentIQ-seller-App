import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../utils/constants.dart';
import '../utils/helpers.dart';
import 'local_notification_service.dart';
import 'offline_queue_service.dart';

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

  /// Update the Android foreground notification title/body (e.g. ride phase).
  static void updateStatus({required String title, required String content}) {
    if (kIsWeb) return;
    _service.invoke('updateStatus', {
      'title': title,
      'content': content,
    });
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

  // Initialize offline queue for position caching.
  final prefs = await SharedPreferences.getInstance();
  final offlineQueue = OfflineQueueService(prefs);

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
  String notifTitle = 'Muevete activo';
  String notifContent = 'Conectado y recibiendo solicitudes';

  RealtimeChannel? requestsChannel;
  RealtimeChannel? requestsUpdateChannel;
  RealtimeChannel? solicitudesClientChannel;
  RealtimeChannel? notificationsChannel;
  StreamSubscription<Position>? gpsSubscription;
  Timer? radiusExpansionTimer;
  Timer? heartbeatTimer;
  Timer? pollingTimer;

  void applyForegroundNotification({String? title, String? content}) {
    if (title != null) notifTitle = title;
    if (content != null) notifContent = content;
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: notifTitle,
        content: notifContent,
      );
    }
  }

  // Pending requests for expanding radius (driver only)
  final List<Map<String, dynamic>> pendingRequests = [];

  // ── Stop handler ──
  service.on('stop').listen((_) async {
    gpsSubscription?.cancel();
    radiusExpansionTimer?.cancel();
    heartbeatTimer?.cancel();
    pollingTimer?.cancel();
    if (requestsChannel != null) supabase.removeChannel(requestsChannel!);
    if (requestsUpdateChannel != null) {
      supabase.removeChannel(requestsUpdateChannel!);
    }
    if (solicitudesClientChannel != null) {
      supabase.removeChannel(solicitudesClientChannel!);
    }
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

  // ── Status updates from UI (ride / request phase) ──
  service.on('updateStatus').listen((data) {
    if (data == null) return;
    applyForegroundNotification(
      title: data['title']?.toString(),
      content: data['content']?.toString(),
    );
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
    if (role == 'driver') {
      applyForegroundNotification(
        title: 'Muevete - Conductor',
        content: 'Ubicación activa · Esperando solicitudes',
      );
    } else {
      applyForegroundNotification(
        title: 'Muevete activo',
        content: 'Ubicación compartida en segundo plano',
      );
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

    // Aviso al chofer de un viaje nuevo con precio fijo (sin negociación):
    // el precio y el neto salen de la propia fila de la solicitud.
    void notifyRequest(Map<String, dynamic> rec) {
      final solicitudId = rec['id'];
      localNotif.showRideRequest(
        title: 'Nuevo viaje disponible',
        body: _textoPrecioViaje(rec),
        solicitudId: solicitudId?.toString(),
      );
      service.invoke('notification', {
        ...rec,
        'type': 'viaje_disponible',
        'solicitud_id': solicitudId,
      });
    }

    // Aviso al cliente cuando su solicitud ya tiene conductor (`driver_id`).
    // Sustituye al antiguo canal de ofertas: ya no hay nada que aceptar.
    int? ultimaSolicitudAsignada;

    void notifyAssigned(Map<String, dynamic> rec) {
      final solicitudId = (rec['id'] as num?)?.toInt();
      if (solicitudId != null && solicitudId == ultimaSolicitudAsignada) {
        return;
      }
      if (solicitudId != null) ultimaSolicitudAsignada = solicitudId;

      final precio = _num(rec['precio_plataforma']);
      localNotif.showDriverAssigned(
        title: 'Conductor asignado',
        body: precio == null
            ? 'Tu conductor va en camino.'
            : 'Tu conductor va en camino. Precio: ${Helpers.formatCup(precio)}',
        solicitudId: solicitudId?.toString(),
      );
      service.invoke('notification', {
        'type': 'viaje_asignado',
        'solicitud_id': solicitudId,
        'precio_plataforma': rec['precio_plataforma'],
      });
    }

    // ── Driver-specific subscriptions ──
    if (role == 'driver') {
      final steps = AppConstants.radiusSteps;

      // Listen for new ride requests — add to pending list
      requestsChannel = supabase
          .channel('bg_solicitudes_driver')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'muevete',
            table: 'solicitudes_transporte',
            callback: (payload) {
              final rec = payload.newRecord;
              // Sólo los viajes publicados (`pendiente`) son tomables.
              if ((rec['estado']?.toString() ?? 'pendiente') != 'pendiente') {
                return;
              }
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

      // Flush any queued positions from previous sessions
      if (driverId != null && offlineQueue.hasPending) {
        try {
          final online = await OfflineQueueService.hasInternetConnection();
          if (online) {
            await _flushQueue(queue: offlineQueue, supabase: supabase);
          }
        } catch (e) {
          debugPrint('[BackgroundService] Initial queue flush error: $e');
        }
      }

      // Start GPS tracking to update driver location
      _startGpsTracking(
        service: service,
        supabase: supabase,
        driverId: driverId,
        queue: offlineQueue,
        onPosition: (lat, lon) {
          currentLat = lat;
          currentLon = lon;
        },
        onNotificationTick: (time) {
          // Keep the current phase status; only append last GPS timestamp.
          final base = notifContent.contains(' · Última:')
              ? notifContent.split(' · Última:').first
              : notifContent;
          applyForegroundNotification(content: '$base · Última: $time');
        },
        gpsSubscriptionSetter: (sub) => gpsSubscription = sub,
      );
    }

    // ── Client-specific subscriptions ──
    if (role == 'client') {
      // El conductor se asigna actualizando la solicitud (`driver_id`), no con
      // ofertas: se avisa al cliente en cuanto su viaje queda `aceptada`.
      solicitudesClientChannel = supabase
          .channel('bg_solicitudes_client_$userUuid')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'muevete',
            table: 'solicitudes_transporte',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: userUuid!,
            ),
            callback: (payload) {
              final rec = payload.newRecord;
              if (rec['estado']?.toString() != 'aceptada') return;
              if (rec['driver_id'] == null) return;
              notifyAssigned(rec);
            },
          )
          .subscribe();
    }

    // ── Heartbeat: check channel health every 5 min ──
    heartbeatTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      debugPrint('[BackgroundService] Heartbeat check');

      void resubscribeIfNeeded(RealtimeChannel? ch, String name) {
        if (ch == null) return;
        // Only re-subscribe if the channel is closed/errored, not if already joined
        if (ch.isJoined || ch.isJoining) {
          debugPrint('[BackgroundService] $name already active, skipping');
          return;
        }
        try {
          ch.subscribe();
          debugPrint('[BackgroundService] $name re-subscribed');
        } catch (e) {
          debugPrint('[BackgroundService] $name re-subscribe error: $e');
        }
      }

      resubscribeIfNeeded(notificationsChannel, 'notifications');
      resubscribeIfNeeded(requestsChannel, 'requests');
      resubscribeIfNeeded(requestsUpdateChannel, 'requestsUpdate');
      resubscribeIfNeeded(solicitudesClientChannel, 'solicitudesClient');
    });

    // ── Polling fallback: check for missed data every 60s ──
    DateTime lastPoll = DateTime.now();
    pollingTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      // `created_at`/`updated_at` son timestamptz: se comparan en UTC.
      final since = lastPoll.toUtc().toIso8601String();
      lastPoll = DateTime.now();

      try {
        if (role == 'driver') {
          // Check for pending solicitudes created since last poll
          final result = await supabase
              .schema('muevete')
              .from('solicitudes_transporte')
              .select('id, estado, direccion_origen, direccion_destino, '
                  'lat_origen, lon_origen, precio_plataforma, precio_chofer, '
                  'comision_pct, comision_monto, metodo_pago')
              .eq('estado', 'pendiente')
              .gte('created_at', since)
              .limit(10);
          for (final rec in (result as List)) {
            final originLat = double.tryParse(rec['lat_origen']?.toString() ?? '');
            final originLon = double.tryParse(rec['lon_origen']?.toString() ?? '');
            if (originLat == null || originLon == null) continue;
            final dist = _haversine(currentLat, currentLon, originLat, originLon);
            if (dist <= AppConstants.radiusSteps.last) {
              notifyRequest(Map<String, dynamic>.from(rec as Map));
            }
          }
        } else if (role == 'client') {
          // Red de seguridad del aviso `viaje_asignado`: si se perdió el
          // UPDATE en tiempo real, el polling lo recupera (avisando una vez).
          final result = await supabase
              .schema('muevete')
              .from('solicitudes_transporte')
              .select('id, estado, driver_id, precio_plataforma')
              .eq('user_id', userUuid!)
              .eq('estado', 'aceptada')
              .gte('updated_at', since)
              .limit(5);
          for (final rec in (result as List)) {
            if (rec['driver_id'] == null) continue;
            notifyAssigned(Map<String, dynamic>.from(rec as Map));
          }
        }
      } catch (e) {
        debugPrint('[BackgroundService] Polling error: $e');
      }

      // Periodic flush of offline queue (driver only)
      if (role == 'driver' && driverId != null && offlineQueue.hasPending) {
        try {
          final online = await OfflineQueueService.hasInternetConnection();
          if (online) {
            await _flushQueue(queue: offlineQueue, supabase: supabase);
          }
        } catch (e) {
          debugPrint('[BackgroundService] Periodic queue flush error: $e');
        }
      }
    });
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
  required OfflineQueueService queue,
  required void Function(double lat, double lon) onPosition,
  required void Function(String time) onNotificationTick,
  required void Function(StreamSubscription<Position>) gpsSubscriptionSetter,
}) {
  const notifConfig = ForegroundNotificationConfig(
    notificationTitle: 'Muevete - Ubicación activa',
    notificationText: 'Rastreando tu ubicación en segundo plano',
    enableWakeLock: true,
  );

  void listenToStream(Stream<Position> stream) {
    final sub = stream.listen((position) async {
      final lat = position.latitude;
      final lon = position.longitude;
      onPosition(lat, lon);

      // Send to UI
      service.invoke('locationUpdate', {'lat': lat, 'lon': lon});

      // Refresh foreground notification timestamp without wiping ride status
      final now = DateTime.now();
      final time =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      onNotificationTick(time);

      // Update driver location in Supabase + track history
      if (driverId != null) {
        final online = await OfflineQueueService.hasInternetConnection();

        if (online) {
          try {
            // Flush offline queue first
            await _flushQueue(queue: queue, supabase: supabase);

            // Write current position only — never touch place.estado here
            await supabase
                .schema('muevete')
                .from('place')
                .update({'latitude': lat, 'longitude': lon})
                .eq('driver', driverId);

            await supabase.schema('muevete').from('track_place_history').insert({
              'driver_id': driverId,
              'latitude': lat,
              'longitude': lon,
            });
          } catch (e) {
            debugPrint('[GPS] Write failed, enqueuing: $e');
            queue.enqueue(
              driverId: driverId,
              latitude: lat,
              longitude: lon,
            );
          }
        } else {
          queue.enqueue(
            driverId: driverId,
            latitude: lat,
            longitude: lon,
          );
        }
      }
    });
    gpsSubscriptionSetter(sub);
  }

  // Try high accuracy first, fallback to medium on error
  try {
    listenToStream(Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        intervalDuration: const Duration(seconds: 10),
        foregroundNotificationConfig: notifConfig,
      ),
    ));
  } catch (e) {
    debugPrint('[GPS] High accuracy failed, falling back to medium: $e');
    listenToStream(Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 10,
        intervalDuration: const Duration(seconds: 10),
        foregroundNotificationConfig: notifConfig,
      ),
    ));
  }
}

/// Flush offline queue to Supabase in chunks of 50.
/// Uses partial removal per chunk for safety — if a chunk fails,
/// already-sent entries are not re-sent.
Future<void> _flushQueue({
  required OfflineQueueService queue,
  required SupabaseClient supabase,
}) async {
  if (!queue.hasPending) return;

  final total = queue.pendingCount;
  debugPrint('[GPS] Flushing $total queued positions');

  const chunkSize = 50;
  int sent = 0;

  while (queue.hasPending) {
    final entries = queue.peekAll();
    final chunk = entries.take(chunkSize).toList();

    final rows = chunk
        .map((e) => {
              'driver_id': e['driver_id'],
              'latitude': e['latitude'],
              'longitude': e['longitude'],
              if (e['timestamp'] != null) 'created_at': e['timestamp'],
            })
        .toList();

    try {
      await supabase.schema('muevete').from('track_place_history').insert(rows);
      // Only remove the chunk that was sent successfully
      queue.removeFirst(chunk.length);
      sent += chunk.length;
    } catch (e) {
      debugPrint('[GPS] Flush chunk failed after $sent/$total sent: $e');
      return; // Stop flushing — remaining entries stay in queue
    }
  }

  debugPrint('[GPS] Queue flushed successfully ($sent entries)');
}

/// Texto de la notificación del chofer. NO usa "a ti te tocan X": el neto no es
/// lo que cobra en mano. Según el método de pago:
///   · efectivo → `El cliente paga 1 500 CUP en efectivo · se te descontarán 225 CUP de tu wallet`
///   · wallet   → `El cliente paga 1 500 CUP con wallet · se te acreditarán 1 275 CUP`
///
/// `comision_monto`/`precio_chofer` son los números autoritativos del servidor;
/// si la fila no los trae se estiman con `comision_pct` **sólo para este texto**
/// (la lista de viajes siempre pinta lo que calcula el servidor).
String _textoPrecioViaje(Map<String, dynamic> rec) {
  final plataforma = _num(rec['precio_plataforma']);
  if (plataforma == null) return 'El cliente solicita un viaje';

  final pct = _num(rec['comision_pct']) ?? 0;
  final metodo = (rec['metodo_pago']?.toString() ?? 'efectivo').toLowerCase();
  final comision = _num(rec['comision_monto']) ?? plataforma * pct / 100;

  if (metodo == 'wallet') {
    final chofer = _num(rec['precio_chofer']) ?? (plataforma - comision);
    return 'El cliente paga ${Helpers.formatCup(plataforma)} con wallet · '
        'se te acreditarán ${Helpers.formatCup(chofer)}';
  }

  return 'El cliente paga ${Helpers.formatCup(plataforma)} en efectivo · '
      'se te descontarán ${Helpers.formatCup(comision)} de tu wallet';
}

num? _num(Object? value) {
  if (value is num) return value;
  final text = value?.toString();
  return text == null ? null : num.tryParse(text);
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
