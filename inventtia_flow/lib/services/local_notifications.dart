import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Envoltura segura sobre flutter_local_notifications.
/// El paquete NO soporta Web: todas las operaciones son no-op si kIsWeb.
class LocalNotifications {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String _channelId = 'notificaciones_flow';
  static const String _channelName = 'Notificaciones';
  static const String _channelDesc =
      'Avisos de colas y reservaciones';

  static bool _inited = false;

  /// Inicializa el plugin y crea el canal Android. Llamar una vez en main().
  static Future<void> init() async {
    if (kIsWeb || _inited) return;
    _inited = true;

    const androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initSettings =
        InitializationSettings(android: androidInit, iOS: iosInit);

    await _plugin.initialize(initSettings);

    // Canal Android (necesario en Android 8+).
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Permiso de notificaciones (Android 13+).
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Muestra una notificación del sistema. No-op en Web.
  static Future<void> show({
    required int id,
    required String titulo,
    required String mensaje,
  }) async {
    if (kIsWeb) return;
    if (!_inited) await init();

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(''),
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    await _plugin.show(id, titulo, mensaje, details);
  }
}
