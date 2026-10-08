import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/agenda_service.dart';
import '../services/auth_service.dart';

/// Contador de reservas activas del cliente para el badge de la barra inferior.
///
/// El badge estaba fijo en `'2'` dentro de `home_shell.dart`, así que mentía
/// siempre. Ahora sale de `flow.cliente_obtener_agendas` contando las reservas
/// en estado `Reservado` (los estados reales de `flow.nom_estado_agenda` son
/// `Reservado`, `Cancelado` y `Completado`).
class ReservasProvider extends ChangeNotifier {
  int _pendientes = 0;
  bool _cargando = false;
  String? _uuid;
  StreamSubscription<AuthState>? _authSub;

  /// Reservas en estado `Reservado` (ni canceladas ni completadas).
  int get pendientes => _pendientes;

  bool get cargando => _cargando;

  bool get hayPendientes => _pendientes > 0;

  ReservasProvider() {
    final inicial = AuthService.currentUserId;
    if (inicial != null) recargar();
    _authSub = AuthService.authStateChanges.listen((state) {
      final nuevo = state.session?.user.id;
      if (nuevo == null) {
        limpiar();
      } else if (nuevo != _uuid) {
        recargar();
      }
    });
  }

  void limpiar() {
    _uuid = null;
    _pendientes = 0;
    _cargando = false;
    notifyListeners();
  }

  Future<void> recargar() async {
    final uuid = AuthService.currentUserId;
    if (uuid == null) {
      limpiar();
      return;
    }
    if (_cargando) return;
    _uuid = uuid;
    _cargando = true;
    try {
      final agendas = await AgendaService.getMisTickets(uuid);
      if (_uuid != uuid) return;
      _pendientes = agendas
          .where((a) => a.estado?.esReservado ?? a.idEstado == 1)
          .length;
    } catch (e) {
      debugPrint('[flow] ReservasProvider.recargar ERROR: $e');
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
