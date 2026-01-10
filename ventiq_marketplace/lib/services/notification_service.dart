import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/notification_model.dart';
import '../services/app_navigation_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'user_preferences_service.dart';
import 'user_session_service.dart';
import 'background_service.dart';

class NotificationService with WidgetsBindingObserver {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final UserSessionService _sessionService = UserSessionService();
  final UserPreferencesService _preferencesService = UserPreferencesService();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  static const int _persistentBarNotificationId = 990000;

  static const String _actionOpenHub = 'open_hub';
  static const String _actionOpenSearch = 'open_search';
  static const String _actionOpenSettings = 'open_settings';
  static const String _actionOpenNotifications = 'open_notifications';

  Map<String, dynamic>? _pendingNavigation;

  static const String _channelId = 'ventiq_marketplace_notifications';
  static const String _channelName = 'Notificaciones Marketplace';
  static const String _channelDescription =
      'Notificaciones de Inventtia Marketplace';

  static const String _persistentBarChannelId =
      'ventiq_marketplace_persistent_bar';
  static const String _persistentBarChannelName = 'Barra Marketplace';
  static const String _persistentBarChannelDescription =
      'Barra persistente de Inventtia Marketplace';

  static const String _tableConsent = 'app_dat_preferencias_notificaciones';
  static const String _tableStoreSubscriptions =
      'app_dat_suscripcion_notificaciones_tienda';
  static const String _tableProductSubscriptions =
      'app_dat_suscripcion_notificaciones_producto';

  static const String _tableNotifications = 'app_dat_notificaciones';

  final _notificationsController =
      StreamController<List<NotificationModel>>.broadcast();
  Stream<List<NotificationModel>> get notificationsStream =>
      _notificationsController.stream;

  final _unreadCountController = StreamController<int>.broadcast();
  Stream<int> get unreadCountStream => _unreadCountController.stream;

  List<NotificationModel> _notifications = [];
  int _unreadCount = 0;

  List<NotificationModel> get notifications =>
      List.unmodifiable(_notifications);
  int get unreadCount => _unreadCount;

  RealtimeChannel? _realtimeChannel;
  bool _realtimeActive = false;
  String? _realtimeUserId;

  AppLifecycleState? _lastLifecycleState;

  Uint8List? _persistentBarLargeIconBytes;

  DateTime? _parseNullableDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lastLifecycleState = state;
    try {
      if (state == AppLifecycleState.resumed) {
        unawaited(_startOrSchedulePersistentBar());
      }
    } catch (_) {}
  }

  Future<String?> _resolveUserId() async {
    final authId = _supabase.auth.currentUser?.id;
    if (authId != null && authId.isNotEmpty) return authId;
    return _sessionService.getUserId();
  }

  Future<void> initialize() async {
    if (_initialized) return;

    if (kIsWeb) {
      _initialized = true;
      return;
    }

    try {
      // Intentar persistir el userId para el servicio de segundo plano
      final uuid = await _resolveUserId();
      if (uuid != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_id', uuid);
      }
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const darwinSettings = DarwinInitializationSettings();

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      );

      await _notificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      try {
        final launchDetails = await _notificationsPlugin
            .getNotificationAppLaunchDetails();
        final response = launchDetails?.notificationResponse;
        if (launchDetails?.didNotificationLaunchApp == true &&
            response != null) {
          _onNotificationTapped(response);
        }
      } catch (_) {}

      await _ensureDefaultAndroidChannel();
      await _ensurePersistentBarAndroidChannel();

      try {
        WidgetsBinding.instance.addObserver(this);
      } catch (_) {}

      _initialized = true;
    } catch (_) {}
  }

  Future<AndroidBitmap<Object>?> _getPersistentBarLargeIcon() async {
    try {
      if (_persistentBarLargeIconBytes != null) {
        return ByteArrayAndroidBitmap(_persistentBarLargeIconBytes!)
            as AndroidBitmap<Object>;
      }

      final data = await rootBundle.load('assets/logo_app.png');
      _persistentBarLargeIconBytes = data.buffer.asUint8List();
      return ByteArrayAndroidBitmap(_persistentBarLargeIconBytes!)
          as AndroidBitmap<Object>;
    } catch (_) {
      return null;
    }
  }

  void _onNotificationTapped(NotificationResponse response) {
    try {
      final actionId = response.actionId;
      final payloadRaw = response.payload;

      Map<String, dynamic> payload = {};
      if (payloadRaw != null && payloadRaw.isNotEmpty) {
        final decoded = jsonDecode(payloadRaw);
        if (decoded is Map<String, dynamic>) {
          payload = decoded;
        } else if (decoded is Map) {
          payload = Map<String, dynamic>.from(decoded);
        }
      }

      _pendingNavigation = _resolveNavigation(
        payload: payload,
        actionId: actionId,
      );

      Future.microtask(() {
        drainPendingNavigation();
      });
    } catch (_) {
      _pendingNavigation = {'route': '/home'};
    }
  }

  Map<String, dynamic> _resolveNavigation({
    required Map<String, dynamic> payload,
    required String? actionId,
  }) {
    final type = (payload['type'] ?? '').toString();

    final isPersistentBarAction =
        actionId != null &&
        actionId.isNotEmpty &&
        <String>{
          _actionOpenHub,
          _actionOpenNotifications,
          _actionOpenSearch,
          _actionOpenSettings,
        }.contains(actionId);

    if (type == 'persistent_bar' || isPersistentBarAction) {
      final effectiveAction = (actionId == null || actionId.isEmpty)
          ? _actionOpenHub
          : actionId;

      if (effectiveAction == _actionOpenSearch) {
        return {
          'route': '/home',
          'arguments': {'initialTabIndex': 2},
          'clearStack': true,
        };
      }

      if (effectiveAction == _actionOpenSettings) {
        return {'route': '/notification-settings'};
      }

      if (effectiveAction == _actionOpenNotifications) {
        return {
          'route': '/notification-hub',
          'arguments': {'initialTabIndex': 1},
        };
      }

      return {
        'route': '/notification-hub',
        'arguments': {'initialTabIndex': 0},
      };
    }

    if (payload.containsKey('route')) {
      final route = (payload['route'] ?? '').toString();
      if (route.isNotEmpty) {
        return {
          'route': route,
          'arguments': payload['arguments'],
          'clearStack': payload['clearStack'] == true,
        };
      }
    }

    if (payload.containsKey('notification_id')) {
      return {
        'route': '/notification-hub',
        'arguments': {'initialTabIndex': 1},
      };
    }

    return {'route': '/home'};
  }

  Future<void> drainPendingNavigation() async {
    final pending = _pendingNavigation;
    if (pending == null) return;

    final navigator = AppNavigationService.navigatorKey.currentState;
    if (navigator == null) return;

    final route = (pending['route'] ?? '').toString();
    if (route.isEmpty) return;

    final args = pending['arguments'];
    final clearStack = pending['clearStack'] == true;

    _pendingNavigation = null;

    try {
      if (clearStack) {
        await AppNavigationService.pushNamedAndRemoveUntil(
          route,
          arguments: args,
        );
      } else {
        await AppNavigationService.pushNamed(route, arguments: args);
      }
    } catch (_) {}
  }

  Future<void> _ensureDefaultAndroidChannel() async {
    try {
      final androidImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      if (androidImplementation == null) return;

      const channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.defaultImportance,
      );

      await androidImplementation.createNotificationChannel(channel);
    } catch (_) {}
  }

  Future<void> _ensurePersistentBarAndroidChannel() async {
    try {
      final androidImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      if (androidImplementation == null) return;

      const channel = AndroidNotificationChannel(
        _persistentBarChannelId,
        _persistentBarChannelName,
        description: _persistentBarChannelDescription,
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
      );

      await androidImplementation.createNotificationChannel(channel);
    } catch (_) {}
  }

  Future<bool> requestSystemNotificationPermission() async {
    if (kIsWeb) return false;

    await initialize();

    bool granted = true;

    try {
      final androidImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      if (androidImplementation != null) {
        final res = await androidImplementation
            .requestNotificationsPermission();
        if (res != null) granted = granted && res;
      }
    } catch (_) {}

    try {
      final iosImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();

      if (iosImplementation != null) {
        final res = await iosImplementation.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        if (res != null) granted = granted && res;
      }
    } catch (_) {}

    try {
      final macosImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >();

      if (macosImplementation != null) {
        final res = await macosImplementation.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        if (res != null) granted = granted && res;
      }
    } catch (_) {}

    return granted;
  }

  Future<bool> saveNotificationConsent({
    required NotificationConsentStatus status,
  }) async {
    var finalStatus = status;

    if (status == NotificationConsentStatus.accepted) {
      final granted = await requestSystemNotificationPermission();
      if (!granted) {
        finalStatus = NotificationConsentStatus.denied;
      }
    }

    await _preferencesService.setNotificationConsentStatus(finalStatus);
    await _syncConsentToSupabase(finalStatus);

    if (finalStatus == NotificationConsentStatus.accepted) {
      await initializeUserNotifications(force: true);
    } else {
      await clearUserNotifications();
    }

    return finalStatus == NotificationConsentStatus.accepted;
  }

  Future<void> initializeUserNotifications({bool force = false}) async {
    try {
      await syncNotificationConsentWithSupabase();

      final consent = await _preferencesService.getNotificationConsentStatus();
      if (consent != NotificationConsentStatus.accepted) {
        await clearUserNotifications();
        return;
      }

      final uuid = await _resolveUserId();
      if (uuid == null) {
        await clearUserNotifications();
        return;
      }

      if (!force && _realtimeActive && _realtimeUserId == uuid) {
        return;
      }

      await loadNotifications();
      _subscribeToRealtimeUpdates(uuid);
      _realtimeActive = true;
      _realtimeUserId = uuid;

      await _startOrSchedulePersistentBar();

      // Inicializar el servicio de segundo plano
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        // Asegurar que el userId esté persistido
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_id', uuid);

        await BackgroundServiceManager.initializeService();
      }
    } catch (_) {}
  }

  Future<void> syncNotificationConsentWithSupabase() async {
    try {
      final uuid = await _resolveUserId();
      if (uuid == null) return;

      final localStatus = await _preferencesService
          .getNotificationConsentStatus();
      final localUpdatedAt = await _preferencesService
          .getNotificationConsentUpdatedAt();

      Map<String, dynamic>? remote;
      try {
        remote = await _supabase
            .from(_tableConsent)
            .select('estado, created_at, updated_at')
            .eq('id_usuario', uuid)
            .maybeSingle();
      } catch (_) {
        remote = null;
      }

      final remoteStatus = NotificationConsentStatus.fromValue(
        remote?['estado'] as String?,
      );
      final remoteUpdatedAt =
          _parseNullableDate(remote?['updated_at']) ??
          _parseNullableDate(remote?['created_at']);

      if (remoteStatus == null) {
        if (localStatus != null) {
          await _syncConsentToSupabase(localStatus);
        }
        return;
      }

      if (localStatus == null) {
        await _preferencesService.setNotificationConsentStatus(
          remoteStatus,
          updatedAt: remoteUpdatedAt,
        );
        return;
      }

      final effectiveRemoteTime =
          remoteUpdatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final effectiveLocalTime =
          localUpdatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

      if (effectiveRemoteTime.isAfter(effectiveLocalTime)) {
        await _preferencesService.setNotificationConsentStatus(
          remoteStatus,
          updatedAt: remoteUpdatedAt,
        );
        return;
      }

      if (effectiveLocalTime.isAfter(effectiveRemoteTime) &&
          localStatus != remoteStatus) {
        await _syncConsentToSupabase(localStatus);
      }
    } catch (_) {}
  }

  Future<void> clearUserNotifications() async {
    try {
      await _realtimeChannel?.unsubscribe();
    } catch (_) {}
    _realtimeChannel = null;
    _realtimeActive = false;
    _realtimeUserId = null;

    _notifications = [];
    _unreadCount = 0;
    _notificationsController.add(_notifications);
    _unreadCountController.add(_unreadCount);

    try {
      await _cancelPersistentBar();
    } catch (_) {}
  }

  Future<void> _cancelPersistentBar() async {
    if (kIsWeb) return;

    try {
      await initialize();
      await _notificationsPlugin.cancel(_persistentBarNotificationId);
    } catch (_) {}
  }

  Future<void> _startOrSchedulePersistentBar() async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android) return;

    try {
      final consent = await _preferencesService.getNotificationConsentStatus();
      if (consent != NotificationConsentStatus.accepted) return;

      final uuid = await _sessionService.getUserId();
      if (uuid == null) return;

      await initialize();

      final largeIcon = await _getPersistentBarLargeIcon();

      final androidDetails = AndroidNotificationDetails(
        _persistentBarChannelId,
        _persistentBarChannelName,
        channelDescription: _persistentBarChannelDescription,
        importance: Importance.low,
        priority: Priority.low,
        playSound: false,
        enableVibration: false,
        enableLights: false,
        silent: true,
        autoCancel: false,
        ongoing: true,
        onlyAlertOnce: true,
        showWhen: false,
        icon: '@mipmap/ic_launcher',
        largeIcon: largeIcon,
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction(
            _actionOpenHub,
            'Hub',
            showsUserInterface: true,
            cancelNotification: false,
          ),
          AndroidNotificationAction(
            _actionOpenNotifications,
            'Notifs',
            showsUserInterface: true,
            cancelNotification: false,
          ),
          AndroidNotificationAction(
            _actionOpenSearch,
            'Buscar',
            showsUserInterface: true,
            cancelNotification: false,
          ),
          AndroidNotificationAction(
            _actionOpenSettings,
            'Config',
            showsUserInterface: true,
            cancelNotification: false,
          ),
        ],
      );

      final details = NotificationDetails(android: androidDetails);
      final payload = jsonEncode({'type': 'persistent_bar'});

      try {
        await _notificationsPlugin.cancel(_persistentBarNotificationId);
      } catch (_) {}

      try {
        await _notificationsPlugin.show(
          _persistentBarNotificationId,
          'Inventta Catalogo',
          'Accesos rápidos',
          details,
          payload: payload,
        );
      } catch (_) {}
    } catch (_) {}
  }

  void _subscribeToRealtimeUpdates(String userId) {
    try {
      _realtimeChannel?.unsubscribe();
    } catch (_) {}

    try {
      _realtimeChannel = _supabase
          .channel('marketplace_notifications_$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: _tableNotifications,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: userId,
            ),
            callback: (payload) {
              _handleNewNotification(payload.newRecord);
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: _tableNotifications,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: userId,
            ),
            callback: (payload) {
              _handleUpdatedNotification(payload.newRecord);
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.delete,
            schema: 'public',
            table: _tableNotifications,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: userId,
            ),
            callback: (payload) {
              _handleDeletedNotification(payload.oldRecord);
            },
          )
          .subscribe();
    } catch (_) {}
  }

  void _handleNewNotification(Map<String, dynamic> data) {
    try {
      final notification = NotificationModel.fromJson(data);
      if (notification.isExpired) return;

      _notifications.insert(0, notification);
      if (_notifications.length > 100) {
        _notifications = _notifications.take(100).toList();
      }

      if (!notification.leida) {
        _unreadCount++;
      }

      _notificationsController.add(_notifications);
      _unreadCountController.add(_unreadCount);

      _showLocalNotification(notification);
    } catch (_) {}
  }

  void _handleUpdatedNotification(Map<String, dynamic> data) {
    try {
      final notification = NotificationModel.fromJson(data);
      final index = _notifications.indexWhere((n) => n.id == notification.id);
      if (index == -1) return;

      final old = _notifications[index];
      _notifications[index] = notification;

      if (old.leida != notification.leida) {
        if (notification.leida) {
          _unreadCount = (_unreadCount - 1).clamp(0, 1 << 31).toInt();
        } else {
          _unreadCount++;
        }
      }

      _notificationsController.add(_notifications);
      _unreadCountController.add(_unreadCount);
    } catch (_) {}
  }

  void _handleDeletedNotification(Map<String, dynamic> data) {
    try {
      final id = (data['id'] as num?)?.toInt();
      if (id == null) return;

      final index = _notifications.indexWhere((n) => n.id == id);
      if (index == -1) return;

      final removed = _notifications.removeAt(index);
      if (!removed.leida) {
        _unreadCount = (_unreadCount - 1).clamp(0, 1 << 31).toInt();
      }

      _notificationsController.add(_notifications);
      _unreadCountController.add(_unreadCount);
    } catch (_) {}
  }

  Future<void> loadNotifications({
    int limit = 50,
    int offset = 0,
    bool onlyUnread = false,
  }) async {
    final uuid = await _sessionService.getUserId();
    if (uuid == null) {
      _notifications = [];
      _unreadCount = 0;
      _notificationsController.add(_notifications);
      _unreadCountController.add(_unreadCount);
      return;
    }

    try {
      var query = _supabase
          .from(_tableNotifications)
          .select()
          .eq('user_id', uuid);

      if (onlyUnread) {
        query = query.eq('leida', false);
      }

      final rows = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
      final parsed = (rows as List<dynamic>)
          .map(
            (e) =>
                NotificationModel.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .where((n) => !n.isExpired)
          .toList();

      _notifications = parsed;
      _unreadCount = _notifications.where((n) => !n.leida).length;
      _notificationsController.add(_notifications);
      _unreadCountController.add(_unreadCount);
    } catch (_) {}
  }

  Future<bool> markAsRead(int notificationId) async {
    try {
      await _supabase
          .from(_tableNotifications)
          .update({'leida': true})
          .eq('id', notificationId);

      final index = _notifications.indexWhere((n) => n.id == notificationId);
      if (index != -1 && !_notifications[index].leida) {
        _notifications[index] = _notifications[index].copyWith(
          leida: true,
          leidaAt: DateTime.now(),
        );
        _unreadCount = (_unreadCount - 1).clamp(0, 1 << 31).toInt();
        _notificationsController.add(_notifications);
        _unreadCountController.add(_unreadCount);
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> markAllAsRead() async {
    try {
      final uuid = await _sessionService.getUserId();
      if (uuid == null) return false;

      await _supabase
          .from(_tableNotifications)
          .update({'leida': true})
          .eq('user_id', uuid)
          .eq('leida', false);

      _notifications = _notifications
          .map(
            (n) =>
                n.leida ? n : n.copyWith(leida: true, leidaAt: DateTime.now()),
          )
          .toList();
      _unreadCount = 0;
      _notificationsController.add(_notifications);
      _unreadCountController.add(_unreadCount);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteNotification(int notificationId) async {
    try {
      await _supabase
          .from(_tableNotifications)
          .delete()
          .eq('id', notificationId);

      final index = _notifications.indexWhere((n) => n.id == notificationId);
      if (index != -1) {
        final removed = _notifications.removeAt(index);
        if (!removed.leida) {
          _unreadCount = (_unreadCount - 1).clamp(0, 1 << 31).toInt();
        }
        _notificationsController.add(_notifications);
        _unreadCountController.add(_unreadCount);
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _showLocalNotification(NotificationModel notification) async {
    if (kIsWeb) return;

    try {
      await initialize();

      const androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        icon: '@mipmap/ic_launcher',
      );

      const details = NotificationDetails(android: androidDetails);

      await _notificationsPlugin.show(
        notification.id,
        notification.titulo,
        notification.mensaje,
        details,
        payload: jsonEncode({'notification_id': notification.id}),
      );
    } catch (_) {}
  }

  Future<void> _syncConsentToSupabase(NotificationConsentStatus status) async {
    try {
      final uuid = await _resolveUserId();
      if (uuid == null) return;

      final row = await _supabase
          .from(_tableConsent)
          .upsert({
            'id_usuario': uuid,
            'estado': status.value,
          }, onConflict: 'id_usuario')
          .select('created_at, updated_at')
          .maybeSingle();

      final remoteUpdatedAt =
          _parseNullableDate(row?['updated_at']) ??
          _parseNullableDate(row?['created_at']);

      await _preferencesService.setNotificationConsentStatus(
        status,
        updatedAt: remoteUpdatedAt,
      );
    } catch (_) {}
  }

  Future<bool> isStoreSubscriptionActive({required int storeId}) async {
    try {
      final uuid = await _sessionService.getUserId();
      if (uuid == null) return false;

      final row = await _supabase
          .from(_tableStoreSubscriptions)
          .select('activo')
          .eq('id_usuario', uuid)
          .eq('id_tienda', storeId)
          .maybeSingle();

      if (row == null) return false;
      return row['activo'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> toggleStoreSubscription({required int storeId}) async {
    final uuid = await _sessionService.getUserId();
    if (uuid == null) {
      throw StateError('Usuario no autenticado');
    }

    final current = await isStoreSubscriptionActive(storeId: storeId);
    final next = !current;

    await _supabase.from(_tableStoreSubscriptions).upsert({
      'id_usuario': uuid,
      'id_tienda': storeId,
      'activo': next,
    }, onConflict: 'id_usuario,id_tienda');

    return next;
  }

  Future<bool> isProductSubscriptionActive({required int productId}) async {
    try {
      final uuid = await _sessionService.getUserId();
      if (uuid == null) return false;

      final row = await _supabase
          .from(_tableProductSubscriptions)
          .select('activo')
          .eq('id_usuario', uuid)
          .eq('id_producto', productId)
          .maybeSingle();

      if (row == null) return false;
      return row['activo'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> toggleProductSubscription({required int productId}) async {
    final uuid = await _sessionService.getUserId();
    if (uuid == null) {
      throw StateError('Usuario no autenticado');
    }

    final current = await isProductSubscriptionActive(productId: productId);
    final next = !current;

    await _supabase.from(_tableProductSubscriptions).upsert({
      'id_usuario': uuid,
      'id_producto': productId,
      'activo': next,
    }, onConflict: 'id_usuario,id_producto');

    return next;
  }

  Future<void> showTestNotification({
    String title = 'Inventta Catalogo',
    String body = 'Notificación de prueba',
  }) async {
    if (kIsWeb) return;

    await initialize();

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/ic_launcher',
    );

    const details = NotificationDetails(android: androidDetails);

    try {
      await _notificationsPlugin.show(
        DateTime.now().millisecondsSinceEpoch.remainder(1 << 31),
        title,
        body,
        details,
        payload: jsonEncode({'type': 'test'}),
      );
    } catch (_) {}
  }
}
