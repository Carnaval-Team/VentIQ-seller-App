import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/notificacion.dart';
import '../services/auth_service.dart';
import '../services/local_notifications.dart';
import '../services/notificacion_service.dart';

/// Estado global de notificaciones: mantiene la lista y el contador de no
/// leidas (para el badge), escucha el realtime de Supabase mientras la app
/// esta activa y dispara una notificacion local del sistema por cada nueva.
class NotificacionProvider extends ChangeNotifier {
  List<Notificacion> _items = [];
  StreamSubscription? _sub;
  StreamSubscription<AuthState>? _authSub;
  String? _uuid;

  // IDs ya conocidos: distingue INSERTs nuevos de la re-emision completa del
  // stream (que reenvia todo el set ordenado en cada cambio).
  final Set<int> _conocidos = {};
  bool _snapshotInicialRecibido = false;

  List<Notificacion> get items => _items;
  int get unreadCount => _items.where((n) => !n.leida).length;
  bool get hayNoLeidas => unreadCount > 0;

  NotificacionProvider() {
    final u = AuthService.currentUserId;
    if (u != null) _suscribir(u);
    // Re-suscribir / limpiar segun login-logout.
    _authSub = AuthService.authStateChanges.listen((state) {
      final nuevoUuid = state.session?.user.id;
      if (nuevoUuid == null) {
        _limpiar();
      } else if (nuevoUuid != _uuid) {
        _suscribir(nuevoUuid);
      }
    });
  }

  void _suscribir(String uuid) {
    _sub?.cancel();
    _uuid = uuid;
    _conocidos.clear();
    _snapshotInicialRecibido = false;
    _items = [];
    notifyListeners();

    _sub = NotificacionService.watch(uuid).listen((rows) {
      // El stream llega ascendente por created_at; la UI quiere descendente.
      final ordenadas = rows.reversed.toList();

      // Detecta novedades para disparar notificacion local. En el primer
      // snapshot solo registramos IDs (no notificamos historico).
      final nuevas = <Notificacion>[];
      for (final n in ordenadas) {
        if (!_conocidos.contains(n.id)) {
          _conocidos.add(n.id);
          if (_snapshotInicialRecibido) nuevas.add(n);
        }
      }

      _items = ordenadas;
      _snapshotInicialRecibido = true;
      notifyListeners();

      // Notificacion del sistema por cada nueva (no-op en Web).
      for (final n in nuevas) {
        LocalNotifications.show(
          id: n.id,
          titulo: n.titulo,
          mensaje: n.mensaje,
        );
      }
    }, onError: (e) {
      debugPrint('[flow] NotificacionProvider stream ERROR: $e');
    });
  }

  void _limpiar() {
    _sub?.cancel();
    _sub = null;
    _uuid = null;
    _conocidos.clear();
    _snapshotInicialRecibido = false;
    _items = [];
    notifyListeners();
  }

  /// Recarga manual (pull-to-refresh).
  Future<void> recargar() async {
    final u = _uuid;
    if (u == null) return;
    try {
      _items = await NotificacionService.getMisNotificaciones(u);
      _conocidos
        ..clear()
        ..addAll(_items.map((n) => n.id));
      _snapshotInicialRecibido = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[flow] NotificacionProvider recargar ERROR: $e');
    }
  }

  Future<void> marcarLeida(int id) async {
    // Optimista: actualiza UI ya.
    final idx = _items.indexWhere((n) => n.id == id);
    if (idx == -1 || _items[idx].leida) return;
    _items[idx] = _items[idx].copyWith(leida: true, leidaAt: DateTime.now());
    notifyListeners();
    try {
      await NotificacionService.marcarLeida(id);
    } catch (e) {
      debugPrint('[flow] marcarLeida ERROR: $e');
    }
  }

  Future<void> marcarTodasLeidas() async {
    final u = _uuid;
    if (u == null) return;
    final ahora = DateTime.now();
    _items = _items
        .map((n) => n.leida ? n : n.copyWith(leida: true, leidaAt: ahora))
        .toList();
    notifyListeners();
    try {
      await NotificacionService.marcarTodasLeidas(u);
    } catch (e) {
      debugPrint('[flow] marcarTodasLeidas ERROR: $e');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }
}
