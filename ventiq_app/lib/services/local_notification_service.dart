import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/notification_model.dart';

/// Servicio para gestionar notificaciones push locales
class LocalNotificationService {
  static final LocalNotificationService _instance = LocalNotificationService._internal();
  factory LocalNotificationService() => _instance;
  LocalNotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Inicializar el servicio de notificaciones locales
  Future<void> initialize() async {
    if (_initialized) {
      print('📱 LocalNotificationService ya está inicializado');
      return;
    }

    try {
      print('📱 Inicializando LocalNotificationService...');

      // Configuración para Android
      const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

      // Configuración de inicialización
      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
      );

      // Inicializar plugin
      await _notificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // Solicitar permisos en Android 13+
      await _requestPermissions();

      _initialized = true;
      print('✅ LocalNotificationService inicializado correctamente');
    } catch (e) {
      print('❌ Error inicializando LocalNotificationService: $e');
    }
  }

  /// Solicitar permisos de notificación
  Future<void> _requestPermissions() async {
    try {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

      if (androidImplementation != null) {
        // Solicitar permiso de notificaciones (Android 13+)
        final bool? granted = await androidImplementation.requestNotificationsPermission();
        print('📱 Permiso de notificaciones: ${granted == true ? "Concedido" : "Denegado"}');

        // Solicitar permiso de alarmas exactas (opcional)
        final bool? exactAlarmGranted = await androidImplementation.requestExactAlarmsPermission();
        print('⏰ Permiso de alarmas exactas: ${exactAlarmGranted == true ? "Concedido" : "Denegado"}');
      }
    } catch (e) {
      print('⚠️ Error solicitando permisos: $e');
    }
  }

  /// Manejar tap en notificación
  void _onNotificationTapped(NotificationResponse response) {
    print('🔔 Notificación tocada: ${response.payload}');
    // Aquí puedes implementar navegación según el payload
    // Por ejemplo: Navigator.pushNamed(context, response.payload);
  }

  /// Mostrar notificación local desde NotificationModel
  Future<void> showNotification(NotificationModel notification) async {
    if (!_initialized) {
      print('⚠️ LocalNotificationService no está inicializado');
      await initialize();
    }

    try {
      // Obtener color según tipo
      final color = notification.getColor();
      
      // Determinar prioridad de Android
      final Priority priority = notification.isUrgent 
          ? Priority.max 
          : notification.prioridad == NotificationPriority.alta
              ? Priority.high
              : Priority.defaultPriority;

      // Determinar importancia
      final Importance importance = notification.isUrgent
          ? Importance.max
          : notification.prioridad == NotificationPriority.alta
              ? Importance.high
              : Importance.defaultImportance;

      // Configuración de Android
      final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'ventiq_notifications', // Canal ID
        'Notificaciones VentIQ', // Nombre del canal
        channelDescription: 'Notificaciones de la aplicación VentIQ',
        importance: importance,
        priority: priority,
        showWhen: true,
        color: color,
        enableVibration: true,
        playSound: true,
        icon: '@mipmap/ic_launcher',
        styleInformation: BigTextStyleInformation(
          notification.mensaje,
          contentTitle: notification.titulo,
          summaryText: _getTipoText(notification.tipo),
        ),
        // Agregar badge para notificaciones urgentes
        number: notification.isUrgent ? 1 : null,
      );

      final NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
      );

      // Mostrar notificación
      await _notificationsPlugin.show(
        notification.id, // ID único de la notificación
        notification.titulo,
        notification.mensaje,
        notificationDetails,
        payload: notification.accion, // Para navegación al tocar
      );

      print('✅ Notificación local mostrada: ${notification.titulo}');
    } catch (e) {
      print('❌ Error mostrando notificación local: $e');
    }
  }

  /// Obtener texto descriptivo del tipo de notificación
  String _getTipoText(NotificationType tipo) {
    switch (tipo) {
      case NotificationType.alerta:
        return 'Alerta';
      case NotificationType.info:
        return 'Información';
      case NotificationType.warning:
        return 'Advertencia';
      case NotificationType.success:
        return 'Éxito';
      case NotificationType.error:
        return 'Error';
      case NotificationType.promocion:
        return 'Promoción';
      case NotificationType.sistema:
        return 'Sistema';
      case NotificationType.pedido:
        return 'Pedido';
      case NotificationType.inventario:
        return 'Inventario';
      case NotificationType.venta:
        return 'Venta';
    }
  }

  /// Cancelar notificación específica
  Future<void> cancelNotification(int id) async {
    try {
      await _notificationsPlugin.cancel(id);
      print('🗑️ Notificación $id cancelada');
    } catch (e) {
      print('❌ Error cancelando notificación: $e');
    }
  }

  /// Cancelar todas las notificaciones
  Future<void> cancelAllNotifications() async {
    try {
      await _notificationsPlugin.cancelAll();
      print('🗑️ Todas las notificaciones canceladas');
    } catch (e) {
      print('❌ Error cancelando todas las notificaciones: $e');
    }
  }

  /// Obtener notificaciones activas
  Future<List<ActiveNotification>> getActiveNotifications() async {
    try {
      final androidImplementation = _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        return await androidImplementation.getActiveNotifications();
      }
      return [];
    } catch (e) {
      print('❌ Error obteniendo notificaciones activas: $e');
      return [];
    }
  }

  /// Crear canal de notificación personalizado (Android 8.0+)
  Future<void> createNotificationChannel({
    required String id,
    required String name,
    String? description,
    Importance importance = Importance.defaultImportance,
  }) async {
    try {
      final androidImplementation = _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      
      if (androidImplementation != null) {
        final AndroidNotificationChannel channel = AndroidNotificationChannel(
          id,
          name,
          description: description,
          importance: importance,
          playSound: true,
          enableVibration: true,
        );

        await androidImplementation.createNotificationChannel(channel);
        print('✅ Canal de notificación creado: $name');
      }
    } catch (e) {
      print('❌ Error creando canal de notificación: $e');
    }
  }
}
