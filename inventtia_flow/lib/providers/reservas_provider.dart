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
///
/// Se mantiene en vivo por dos vías:
/// - **Realtime** sobre `flow.agenda` (migración 37), que es la vía normal.
/// - Una **revalidación al volver a la app**, como red de seguridad por si esa
///   suscripción se cayó.
///
/// El feed del Home puede sembrar el contador una vez, en frío, para que el
/// badge no aparezca vacío durante el primer segundo.
class ReservasProvider extends ChangeNotifier with WidgetsBindingObserver {
  static const String _schema = 'flow';

  int _pendientes = 0;
  bool _cargando = false;
  String? _uuid;
  StreamSubscription<AuthState>? _authSub;

  /// `true` cuando ya respondió una carga real: a partir de ahí manda ella.
  bool _datosReales = false;

  /// Snapshot del feed del Home, solo válido mientras no haya carga real.
  int? _semillaPendientes;

  static const Duration _agrupaCambios = Duration(milliseconds: 400);
  Timer? _debounce;
  StreamSubscription<List<Map<String, dynamic>>>? _realUsuario;
  StreamSubscription<List<Map<String, dynamic>>>? _realReservadoPor;

  /// Reservas en estado `Reservado` (ni canceladas ni completadas).
  ///
  /// Mientras no haya carga real devuelve el snapshot que dejó el feed, para que
  /// el badge no aparezca vacío en frío.
  int get pendientes =>
      _datosReales ? _pendientes : (_semillaPendientes ?? _pendientes);

  bool get cargando => _cargando;

  bool get hayPendientes => pendientes > 0;

  ReservasProvider() {
    WidgetsBinding.instance.addObserver(this);
    final inicial = AuthService.currentUserId;
    if (inicial != null) {
      recargar();
      _suscribirRealtime(inicial);
    }
    // Re-suscribir / limpiar segun login-logout.
    _authSub = AuthService.authStateChanges.listen((state) {
      final nuevo = state.session?.user.id;
      if (nuevo == null) {
        limpiar();
      } else if (nuevo != _uuid) {
        recargar();
        _suscribirRealtime(nuevo);
      }
    });
  }

  /// Acepta el contador que trae el feed del Home (arranque en frío).
  ///
  /// No hace nada si ya hay una carga real: la lista de reservas y el badge
  /// salen de la misma consulta y no deben contradecirse.
  void sembrarPendientes(int pendientes) {
    if (_datosReales) return;
    final valor = pendientes < 0 ? 0 : pendientes;
    if (_semillaPendientes == valor) return;
    _semillaPendientes = valor;
    notifyListeners();
  }

  void limpiar() {
    _cancelarRealtime();
    _uuid = null;
    _pendientes = 0;
    _cargando = false;
    _datosReales = false;
    _semillaPendientes = null;
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
      _datosReales = true;
    } catch (e) {
      debugPrint('[flow] ReservasProvider.recargar ERROR: $e');
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }

  /// Escucha los cambios de las reservas del usuario.
  ///
  /// Son **dos** suscripciones porque una reserva puede ser suya
  /// (`uuid_usuario`) o haberla hecho él para un tercero (`reservado_por`), y un
  /// filtro de Realtime cubre una sola columna.
  ///
  /// El payload no se usa para contar: se vuelve a llamar a [recargar], que es
  /// la única que sabe qué cuenta como pendiente. Contar aquí la lista dejaría
  /// dos definiciones del mismo número, que es como aparecen los descuadres.
  void _suscribirRealtime(String uuid) {
    _cancelarRealtime();

    final tabla = Supabase.instance.client.schema(_schema).from('agenda');
    _realUsuario = tabla
        .stream(primaryKey: ['id'])
        .eq('uuid_usuario', uuid)
        .listen((_) => _programarRecarga(), onError: _errorRealtime);
    _realReservadoPor = tabla
        .stream(primaryKey: ['id'])
        .eq('reservado_por', uuid)
        .listen((_) => _programarRecarga(), onError: _errorRealtime);
  }

  /// Agrupa ráfagas: un cambio puede emitir varias filas casi a la vez.
  void _programarRecarga() {
    _debounce?.cancel();
    _debounce = Timer(_agrupaCambios, recargar);
  }

  void _errorRealtime(Object e) {
    debugPrint('[flow] ReservasProvider realtime ERROR: $e');
  }

  void _cancelarRealtime() {
    _debounce?.cancel();
    _debounce = null;
    _realUsuario?.cancel();
    _realUsuario = null;
    _realReservadoPor?.cancel();
    _realReservadoPor = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Red de seguridad: al volver a la app se revalida el badge. Realtime
    // debería haberlo hecho ya; esto cubre una suscripción caída.
    if (state == AppLifecycleState.resumed) recargar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelarRealtime();
    _authSub?.cancel();
    super.dispose();
  }
}
