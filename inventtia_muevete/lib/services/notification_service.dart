import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';
import '../models/notification_model.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final SupabaseClient _supabase = Supabase.instance.client;
  final AudioPlayer _audioPlayer = AudioPlayer();
  RealtimeChannel? _channel;

  final StreamController<NotificationModel> _controller =
      StreamController<NotificationModel>.broadcast();

  Stream<NotificationModel> get notificationStream => _controller.stream;

  String? _currentUserUuid;

  /// Subscribe to realtime notifications for a user.
  void subscribe(String userUuid) {
    _currentUserUuid = userUuid;
    _channel?.unsubscribe();

    _channel = _supabase
        .channel('notificaciones_$userUuid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'muevete',
          table: 'notificaciones',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_uuid',
            value: userUuid,
          ),
          callback: (payload) {
            final notification = NotificationModel.fromMap(payload.newRecord);
            _controller.add(notification);
            _playAlert();
          },
        )
        .subscribe();
  }

  /// Push a local notification (without DB) for realtime events
  /// already detected by existing subscriptions.
  void pushLocal({
    required NotificationType tipo,
    required String titulo,
    required String mensaje,
    Map<String, dynamic> data = const {},
  }) {
    final notification = NotificationModel(
      userUuid: _currentUserUuid ?? '',
      tipo: tipo,
      titulo: titulo,
      mensaje: mensaje,
      data: data,
    );
    _controller.add(notification);
    _playAlert();
  }

  /// Insert a notification in the DB (will trigger realtime for the recipient).
  Future<void> createNotification({
    required String userUuid,
    required NotificationType tipo,
    required String titulo,
    required String mensaje,
    Map<String, dynamic> data = const {},
  }) async {
    try {
      final notification = NotificationModel(
        userUuid: userUuid,
        tipo: tipo,
        titulo: titulo,
        mensaje: mensaje,
        data: data,
      );
      await _supabase
          .schema('muevete')
          .from('notificaciones')
          .insert(notification.toMap());
    } catch (e) {
      debugPrint('NotificationService.createNotification error: $e');
    }
  }

  /// Mark a notification as read.
  Future<void> markAsRead(int id) async {
    try {
      await _supabase
          .schema('muevete')
          .from('notificaciones')
          .update({'leida': true})
          .eq('id', id);
    } catch (_) {}
  }

  Future<void> _playAlert() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/notification.wav'));
    } catch (_) {}

    try {
      if (!kIsWeb && (await Vibration.hasVibrator() ?? false)) {
        Vibration.vibrate(duration: 300);
      }
    } catch (_) {}
  }

  Future<void> unsubscribe() async {
    if (_channel != null) {
      try {
        await _supabase.removeChannel(_channel!);
      } catch (_) {}
      _channel = null;
    }
  }

  void dispose() {
    _controller.close();
    _audioPlayer.dispose();
    unsubscribe();
  }
}
