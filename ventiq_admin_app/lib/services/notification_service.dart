import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/notification_model.dart';
import 'local_notification_service.dart';

/// Servicio para gestionar notificaciones en tiempo real
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final LocalNotificationService _localNotificationService = LocalNotificationService();
  
  // Stream controller para notificaciones
  final _notificationsController = StreamController<List<NotificationModel>>.broadcast();
  Stream<List<NotificationModel>> get notificationsStream => _notificationsController.stream;
  
  // Stream controller para contador de no leídas
  final _unreadCountController = StreamController<int>.broadcast();
  Stream<int> get unreadCountStream => _unreadCountController.stream;
  
  // Lista local de notificaciones
  List<NotificationModel> _notifications = [];
  int _unreadCount = 0;
  
  // Suscripción a realtime
  RealtimeChannel? _realtimeChannel;
  
  /// Obtener notificaciones actuales
  List<NotificationModel> get notifications => List.unmodifiable(_notifications);
  
  /// Obtener contador de no leídas
  int get unreadCount => _unreadCount;

  /// Inicializar servicio y suscribirse a realtime
  Future<void> initialize() async {
    try {
      print('🔔 Inicializando NotificationService...');
      
      // Inicializar servicio de notificaciones locales
      await _localNotificationService.initialize();
      
      // Obtener usuario actual
      final user = _supabase.auth.currentUser;
      if (user == null) {
        print('⚠️ No hay usuario autenticado');
        return;
      }
      
      print('👤 Usuario autenticado: ${user.id}');
      
      // Cargar notificaciones iniciales
      await loadNotifications();
      
      // Suscribirse a cambios en tiempo real
      _subscribeToRealtimeUpdates(user.id);
      
      print('✅ NotificationService inicializado correctamente');
    } catch (e) {
      print('❌ Error inicializando NotificationService: $e');
    }
  }

  /// Suscribirse a actualizaciones en tiempo real
  void _subscribeToRealtimeUpdates(String userId) {
    try {
      print('📡 Suscribiéndose a notificaciones en tiempo real...');
      
      // Cancelar suscripción anterior si existe
      _realtimeChannel?.unsubscribe();
      
      // Crear nuevo canal de realtime
      _realtimeChannel = _supabase
          .channel('notifications_$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'app_dat_notificaciones',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: userId,
            ),
            callback: (payload) {
              print('🆕 Nueva notificación recibida: ${payload.newRecord}');
              _handleNewNotification(payload.newRecord);
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'app_dat_notificaciones',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: userId,
            ),
            callback: (payload) {
              print('🔄 Notificación actualizada: ${payload.newRecord}');
              _handleUpdatedNotification(payload.newRecord);
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.delete,
            schema: 'public',
            table: 'app_dat_notificaciones',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: userId,
            ),
            callback: (payload) {
              print('🗑️ Notificación eliminada: ${payload.oldRecord}');
              _handleDeletedNotification(payload.oldRecord);
            },
          )
          .subscribe();
      
      print('✅ Suscripción a realtime establecida');
    } catch (e) {
      print('❌ Error suscribiéndose a realtime: $e');
    }
  }

  /// Manejar nueva notificación
  void _handleNewNotification(Map<String, dynamic> data) {
    try {
      final notification = NotificationModel.fromJson(data);
      
      // Agregar al inicio de la lista
      _notifications.insert(0, notification);
      
      // Actualizar contador si no está leída
      if (!notification.leida) {
        _unreadCount++;
        _unreadCountController.add(_unreadCount);
      }
      
      // Emitir lista actualizada
      _notificationsController.add(_notifications);
      
      // Mostrar notificación push local
      _localNotificationService.showNotification(notification);
      
      print('✅ Nueva notificación agregada: ${notification.titulo}');
    } catch (e) {
      print('❌ Error procesando nueva notificación: $e');
    }
  }

  /// Manejar notificación actualizada
  void _handleUpdatedNotification(Map<String, dynamic> data) {
    try {
      final notification = NotificationModel.fromJson(data);
      
      // Buscar y actualizar en la lista
      final index = _notifications.indexWhere((n) => n.id == notification.id);
      if (index != -1) {
        final oldNotification = _notifications[index];
        _notifications[index] = notification;
        
        // Actualizar contador si cambió el estado de lectura
        if (oldNotification.leida != notification.leida) {
          if (notification.leida) {
            _unreadCount = (_unreadCount - 1).clamp(0, double.infinity).toInt();
          } else {
            _unreadCount++;
          }
          _unreadCountController.add(_unreadCount);
        }
        
        // Emitir lista actualizada
        _notificationsController.add(_notifications);
        
        print('✅ Notificación actualizada: ${notification.titulo}');
      }
    } catch (e) {
      print('❌ Error procesando notificación actualizada: $e');
    }
  }

  /// Manejar notificación eliminada
  void _handleDeletedNotification(Map<String, dynamic> data) {
    try {
      final id = data['id'] as int;
      
      // Buscar y eliminar de la lista
      final index = _notifications.indexWhere((n) => n.id == id);
      if (index != -1) {
        final notification = _notifications[index];
        _notifications.removeAt(index);
        
        // Actualizar contador si no estaba leída
        if (!notification.leida) {
          _unreadCount = (_unreadCount - 1).clamp(0, double.infinity).toInt();
          _unreadCountController.add(_unreadCount);
        }
        
        // Emitir lista actualizada
        _notificationsController.add(_notifications);
        
        print('✅ Notificación eliminada: ${notification.titulo}');
      }
    } catch (e) {
      print('❌ Error procesando notificación eliminada: $e');
    }
  }

  /// Cargar notificaciones desde Supabase
  Future<void> loadNotifications({
    int limit = 50,
    int offset = 0,
    bool soloNoLeidas = false,
  }) async {
    try {
      print('📥 Cargando notificaciones...');
      
      final response = await _supabase.rpc(
        'fn_obtener_notificaciones',
        params: {
          'p_limit': limit,
          'p_offset': offset,
          'p_solo_no_leidas': soloNoLeidas,
        },
      );
      
      if (response['success'] == true) {
        final notificacionesData = response['notificaciones'] as List<dynamic>;
        _notifications = notificacionesData
            .map((json) => NotificationModel.fromJson(json as Map<String, dynamic>))
            .toList();
        
        _unreadCount = response['no_leidas_count'] as int? ?? 0;
        
        // Emitir actualizaciones
        _notificationsController.add(_notifications);
        _unreadCountController.add(_unreadCount);
        
        print('✅ Notificaciones cargadas: ${_notifications.length}');
        print('📊 No leídas: $_unreadCount');
      } else {
        print('❌ Error en respuesta: ${response['error']}');
      }
    } catch (e) {
      print('❌ Error cargando notificaciones: $e');
      rethrow;
    }
  }

  /// Marcar notificación como leída
  Future<bool> markAsRead(int notificationId) async {
    try {
      print('📖 Marcando notificación $notificationId como leída...');
      
      final response = await _supabase.rpc(
        'fn_marcar_notificacion_leida',
        params: {'p_notificacion_id': notificationId},
      );
      
      if (response['success'] == true) {
        print('✅ Notificación marcada como leída');
        return true;
      } else {
        print('❌ Error: ${response['message']}');
        return false;
      }
    } catch (e) {
      print('❌ Error marcando notificación como leída: $e');
      return false;
    }
  }

  /// Marcar todas las notificaciones como leídas
  Future<bool> markAllAsRead() async {
    try {
      print('📖 Marcando todas las notificaciones como leídas...');
      
      final response = await _supabase.rpc('fn_marcar_todas_notificaciones_leidas');
      
      if (response['success'] == true) {
        final count = response['count'] as int? ?? 0;
        print('✅ $count notificaciones marcadas como leídas');
        
        // Actualizar lista local
        _notifications = _notifications.map((n) => n.copyWith(leida: true)).toList();
        _unreadCount = 0;
        
        _notificationsController.add(_notifications);
        _unreadCountController.add(_unreadCount);
        
        return true;
      } else {
        print('❌ Error: ${response['error']}');
        return false;
      }
    } catch (e) {
      print('❌ Error marcando todas como leídas: $e');
      return false;
    }
  }

  /// Eliminar notificación
  Future<bool> deleteNotification(int notificationId) async {
    try {
      print('🗑️ Eliminando notificación $notificationId...');
      
      await _supabase
          .from('app_dat_notificaciones')
          .delete()
          .eq('id', notificationId);
      
      print('✅ Notificación eliminada');
      return true;
    } catch (e) {
      print('❌ Error eliminando notificación: $e');
      return false;
    }
  }

  /// Crear notificación (solo para administradores o auto-notificaciones)
  Future<bool> createNotification({
    required String userId,
    required String tipo,
    required String titulo,
    required String mensaje,
    Map<String, dynamic>? data,
    String prioridad = 'normal',
    String? accion,
    String? icono,
    String? color,
    DateTime? fechaExpiracion,
  }) async {
    try {
      print('📝 Creando notificación...');
      
      final response = await _supabase.rpc(
        'fn_crear_notificacion',
        params: {
          'p_user_id': userId,
          'p_tipo': tipo,
          'p_titulo': titulo,
          'p_mensaje': mensaje,
          'p_data': data ?? {},
          'p_prioridad': prioridad,
          'p_accion': accion,
          'p_icono': icono,
          'p_color': color,
          'p_fecha_expiracion': fechaExpiracion?.toIso8601String(),
        },
      );
      
      if (response['success'] == true) {
        print('✅ Notificación creada: ${response['notificacion_id']}');
        return true;
      } else {
        print('❌ Error: ${response['message']}');
        return false;
      }
    } catch (e) {
      print('❌ Error creando notificación: $e');
      return false;
    }
  }

  /// Limpiar notificaciones expiradas
  Future<void> cleanExpiredNotifications() async {
    try {
      print('🧹 Limpiando notificaciones expiradas...');
      
      final response = await _supabase.rpc('fn_limpiar_notificaciones_expiradas');
      
      if (response['success'] == true) {
        final count = response['count'] as int? ?? 0;
        print('✅ $count notificaciones expiradas eliminadas');
      }
    } catch (e) {
      print('❌ Error limpiando notificaciones expiradas: $e');
    }
  }

  /// Cerrar servicio y limpiar recursos
  void dispose() {
    print('🔌 Cerrando NotificationService...');
    _realtimeChannel?.unsubscribe();
    _notificationsController.close();
    _unreadCountController.close();
  }
}
