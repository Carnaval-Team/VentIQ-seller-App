import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/supabase_config.dart';

/// Servicio para manejar la ejecución en segundo plano y notificaciones en tiempo real vía WebSocket
class BackgroundServiceManager {
  static const String _tableNotifications = 'app_dat_notificaciones';

  static Future<void> initializeService() async {
    final service = FlutterBackgroundService();

    // Configuración para Android
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: true,
        isForegroundMode: true,
        notificationChannelId: 'ventiq_marketplace_notifications',
        initialNotificationTitle: 'VentiQ Marketplace',
        initialNotificationContent: 'Servicio de notificaciones activo',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    return true;
  }

  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();

    // Inicializar Supabase en el Isolate de segundo plano
    await Supabase.initialize(
      url: SupabaseConfig.supabaseUrl,
      anonKey: SupabaseConfig.supabaseAnonKey,
    );

    final supabase = Supabase.instance.client;

    // Obtener el ID de usuario persistido (necesitamos esto porque el Isolate es independiente)
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');

    if (userId == null || userId.isEmpty) {
      print(
        'BackgroundService: No userId found, skipping realtime subscription',
      );
      return;
    }

    print('BackgroundService: Initializing for user $userId');

    // Inicializar notificaciones locales
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    // Suscribirse a cambios en tiempo real
    supabase
        .channel('background_notifications_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: _tableNotifications,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) async {
            final data = payload.newRecord;
            final title = data['titulo'] ?? 'Nueva notificación';
            final body = data['mensaje'] ?? '';
            final extraData = data['data_json'] ?? {};
            final notificationId =
                data['id'] ?? DateTime.now().millisecondsSinceEpoch;

            // Mostrar notificación local
            await flutterLocalNotificationsPlugin.show(
              notificationId,
              title,
              body,
              const NotificationDetails(
                android: AndroidNotificationDetails(
                  'ventiq_marketplace_notifications',
                  'Notificaciones Marketplace',
                  importance: Importance.max,
                  priority: Priority.high,
                ),
                iOS: DarwinNotificationDetails(),
              ),
              payload: jsonEncode(extraData),
            );
          },
        )
        .subscribe();
  }
}
