import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationService {
  static final LocalNotificationService _instance =
      LocalNotificationService._internal();
  factory LocalNotificationService() => _instance;
  LocalNotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Global navigator key — set from main.dart so we can navigate on tap.
  static GlobalKey<NavigatorState>? navigatorKey;

  static const _channelId = 'muevete_notifications';
  static const _channelName = 'Notificaciones Muevete';

  static const _foregroundChannelId = 'muevete_foreground';
  static const _foregroundChannelName = 'Servicio activo';

  Future<void> init() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Create notification channels
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'Solicitudes, ofertas y alertas',
          importance: Importance.high,
        ),
      );
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _foregroundChannelId,
          _foregroundChannelName,
          description: 'Servicio de ubicación en segundo plano',
          importance: Importance.low,
          showBadge: false,
        ),
      );
    }
  }

  /// Show a notification for a new ride request (driver).
  Future<void> showRideRequest({
    required String title,
    required String body,
    String? solicitudId,
  }) async {
    await _plugin.show(
      1001,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
        ),
      ),
      payload: 'ride_request:${solicitudId ?? ''}',
    );
  }

  /// Show a notification for a driver offer (client).
  Future<void> showDriverOffer({
    required String title,
    required String body,
    String? solicitudId,
  }) async {
    await _plugin.show(
      1002,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
        ),
      ),
      payload: 'driver_offer:${solicitudId ?? ''}',
    );
  }

  /// Show a generic notification.
  Future<void> showGeneric({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: payload,
    );
  }

  static void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || navigatorKey?.currentState == null) return;

    final nav = navigatorKey!.currentState!;

    if (payload.startsWith('ride_request:')) {
      nav.pushNamedAndRemoveUntil('/driver/requests', (r) => r.isFirst);
    } else if (payload.startsWith('driver_offer:')) {
      nav.pushNamedAndRemoveUntil('/client/driver-offers', (r) => r.isFirst);
    }
  }
}
