import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:pushy_flutter/pushy_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'local_notification_service.dart';

// Background notification handler — must be a top-level function.
@pragma('vm:entry-point')
void _pushyBackgroundHandler(Map<String, dynamic> data) {
  debugPrint('[Pushy] Background notification: $data');
}

class PushyService {
  PushyService._();

  static String? _deviceToken;

  /// Initialize Pushy listeners. Call once from main.dart after Supabase init.
  static Future<void> init() async {
    if (kIsWeb) return;

    // Set the app ID
    Pushy.setAppId('69a5cf6e17a786c0470bc2d1');

    // Start listening for notifications
    Pushy.listen();

    // Set foreground notification listener
    Pushy.setNotificationListener(_onForegroundNotification);

    // Set notification click listener
    Pushy.setNotificationClickListener(_onNotificationClick);

    debugPrint('[PushyService] Initialized');
  }

  /// Register the device with Pushy and store the token in Supabase.
  static Future<void> register(String userUuid) async {
    if (kIsWeb) return;

    try {
      final token = await Pushy.register();
      _deviceToken = token;
      debugPrint('[PushyService] Device token: $token');

      final supabase = Supabase.instance.client;
      await supabase.schema('muevete').from('push_tokens').upsert(
        {
          'user_uuid': userUuid,
          'device_token': token,
          'platform': Platform.isAndroid ? 'android' : 'ios',
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'user_uuid,device_token',
      );
      debugPrint('[PushyService] Token stored in push_tokens');
    } catch (e) {
      debugPrint('[PushyService] Registration error: $e');
    }
  }

  /// Remove the device token from Supabase on sign-out.
  static Future<void> unregister(String userUuid) async {
    if (kIsWeb) return;

    try {
      final supabase = Supabase.instance.client;
      if (_deviceToken != null) {
        await supabase
            .schema('muevete')
            .from('push_tokens')
            .delete()
            .eq('user_uuid', userUuid)
            .eq('device_token', _deviceToken!);
      }
      debugPrint('[PushyService] Token removed from push_tokens');
    } catch (e) {
      debugPrint('[PushyService] Unregister error: $e');
    }
  }

  // ── Foreground notification handler ──
  static void _onForegroundNotification(Map<String, dynamic> data) {
    debugPrint('[PushyService] Foreground notification: $data');

    final type = data['type']?.toString() ?? 'generic';
    final title = data['title']?.toString() ?? 'Muevete';
    final body = data['body']?.toString() ?? '';
    final solicitudId = data['solicitud_id']?.toString();

    final localNotif = LocalNotificationService();

    switch (type) {
      case 'ride_request':
        localNotif.showRideRequest(
          title: title,
          body: body,
          solicitudId: solicitudId,
        );
        break;
      case 'driver_offer':
        localNotif.showDriverOffer(
          title: title,
          body: body,
          solicitudId: solicitudId,
        );
        break;
      default:
        localNotif.showGeneric(
          id: DateTime.now().millisecondsSinceEpoch % 100000,
          title: title,
          body: body,
          payload: type,
        );
    }
  }

  // ── Notification click handler ──
  static void _onNotificationClick(Map<String, dynamic> data) {
    debugPrint('[PushyService] Notification clicked: $data');

    final nav = LocalNotificationService.navigatorKey?.currentState;
    if (nav == null) return;

    final type = data['type']?.toString() ?? '';

    switch (type) {
      case 'ride_request':
        nav.pushNamedAndRemoveUntil('/driver/requests', (r) => r.isFirst);
        break;
      case 'driver_offer':
        nav.pushNamedAndRemoveUntil(
            '/client/driver-offers', (r) => r.isFirst);
        break;
      default:
        break;
    }
  }
}
