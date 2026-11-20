import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/session_expiry.dart';

import 'reauthentication_service.dart';
import 'server_time_service.dart';
import 'user_preferences_service.dart';

/// Rotación automática del token de sesión.
///
/// supabase_flutter refresca el JWT por su cuenta mientras la app está en
/// foreground con red, pero no cubre:
///  - el `accessToken` persistido en SharedPreferences (queda congelado al
///    valor del login y es lo que leen servicios offline/licencia);
///  - el caso en que el refresh token ya no es válido (expulsión, robo,
///    rotación en servidor): aquí se cae a reautenticar con las credenciales
///    guardadas, mismo camino que la reconexión automática.
///
/// Uso: `SessionRefreshService().start()` una vez (se llama desde
/// AuthService.initialize). Es idempotente y no-op cuando no hay sesión.
class SessionRefreshService {
  static final SessionRefreshService _instance =
      SessionRefreshService._internal();
  factory SessionRefreshService() => _instance;
  SessionRefreshService._internal();

  @visibleForTesting
  SessionRefreshService.forTesting({required SupabaseClient client})
    : _clientOverride = client;

  SupabaseClient? _clientOverride;
  SupabaseClient get _client => _clientOverride ?? Supabase.instance.client;
  final UserPreferencesService _prefs = UserPreferencesService();

  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<void>? _clockSub;
  Timer? _timer;
  bool _started = false;
  Future<bool>? _refreshInFlight;
  DateTime? _retryAfter;
  int _explicitSignOutVersion = 0;

  /// Expiración (ya alineada al reloj del dispositivo) del último token visto.
  ///
  /// Solo se usa como respaldo cuando el evento `signedOut` no trae
  /// `signOutReason` (gotrue 2.26 sí lo trae; `supabase_flutter ^2.16.0` lo
  /// exige). Antes, sin el motivo, había que deducirlo: si el token todavía no
  /// había expirado, el cierre lo pidió alguien; si ya había expirado, era la
  /// caducidad. Esa deducción falla con gotrue 2.26: un 429 en el refresh
  /// hace que el SDK cierre la sesión con `sessionExpired` aunque el JWT siga
  /// vigente, y se tomaba por un cierre explícito.
  DateTime? _ultimaExpiracion;

  /// `'explicit'` si el cierre lo provocó el usuario, `'session_expired'` si lo
  /// provocó el SDK (refresh rechazado), `'session_missing'` si no se pudo
  /// recuperar la sesión guardada, `null` cuando el evento no es un cierre.
  String? _motivoSignOut(AuthState event) {
    if (event.event != AuthChangeEvent.signedOut) return null;
    final SignOutReason? motivo = event.signOutReason;
    if (motivo != null) {
      switch (motivo) {
        case SignOutReason.userInitiated:
          return 'explicit';
        case SignOutReason.sessionExpired:
          return 'session_expired';
        case SignOutReason.sessionMissing:
          return 'session_missing';
      }
    }
    final DateTime? exp = _ultimaExpiracion;
    // Sin dato previo no se puede distinguir. Se asume explícito, que es el
    // caso conservador: corta la reautenticación automática.
    if (exp == null) return 'explicit';
    return exp.isAfter(DateTime.now()) ? 'explicit' : 'session_expired';
  }

  /// Margen antes de la expiración en el que se dispara el refresh.
  static const Duration _refreshMargin = Duration(minutes: 2);
  static const Duration _checkInterval = Duration(seconds: 60);

  void start() {
    if (_started) return;
    _started = true;

    alignCurrentSession();
    _clockSub = ServerTimeService().clockChanges.listen(
      (_) => alignCurrentSession(),
    );
    _authSub = _client.auth.onAuthStateChange.listen(
      _onAuthState,
      onError:
          (Object e) => debugPrint(
            jsonEncode({
              'event': 'auth_stream_error',
              'type': e.runtimeType.toString(),
              if (e is AuthException) 'status': e.statusCode,
              if (e is AuthException) 'code': e.code,
            }),
          ),
    );

    // Revisión periódica por si el auto-refresh interno de gotrue no corrió
    // (app reanudada, timer perdido en background, etc.).
    _timer = Timer.periodic(_checkInterval, (_) => ensureFreshSession());

    print('🔐 SessionRefreshService iniciado');
  }

  void stop() {
    _authSub?.cancel();
    _authSub = null;
    _clockSub?.cancel();
    _clockSub = null;
    _timer?.cancel();
    _timer = null;
    _started = false;
  }

  void alignCurrentSession() {
    final session = _client.auth.currentSession;
    if (session == null) return;
    alignSessionExpiryToDeviceClock(session, ServerTimeService().now());
    final int? expira = session.expiresAt;
    if (expira != null) {
      _ultimaExpiracion = DateTime.fromMillisecondsSinceEpoch(expira * 1000);
    }
  }

  Future<void> _onAuthState(AuthState event) async {
    final session = event.session;
    if (session != null) {
      alignSessionExpiryToDeviceClock(session, ServerTimeService().now());
      // Se recuerda la expiración ya alineada: es la referencia para saber,
      // cuando llegue el `signedOut`, si el token había caducado o el cierre
      // lo pidió el usuario (gotrue 2.13 no da el motivo).
      // `expiresAt` es `int?` en gotrue 2.13: puede venir nulo si el JWT no
      // trae `exp`, y en ese caso no hay referencia que guardar.
      final int? expira = session.expiresAt;
      if (expira != null) {
        _ultimaExpiracion = DateTime.fromMillisecondsSinceEpoch(expira * 1000);
      }
    }
    // Se calcula DESPUÉS de refrescar la expiración: en un `signedOut` no hay
    // sesión, así que usa la última conocida.
    final String? motivoSignOut = _motivoSignOut(event);
    if (motivoSignOut == 'explicit') {
      _explicitSignOutVersion++;
    }
    debugPrint(
      jsonEncode({
        'event': 'auth_session_changed',
        'change': event.event.name,
        'has_session': session != null,
        'reason': motivoSignOut,
      }),
    );
    switch (event.event) {
      case AuthChangeEvent.tokenRefreshed:
      case AuthChangeEvent.signedIn:
        // Mantener el token persistido al día tras cada rotación/login.
        if (session != null && session.accessToken.isNotEmpty) {
          _retryAfter = null;
          final tokenExpiry = sessionTokenExpiresAt(session);
          await _prefs.updateAccessToken(
            session.accessToken,
            expiresAt:
                tokenExpiry == null
                    ? null
                    : tokenExpiry.millisecondsSinceEpoch ~/ 1000,
          );
          if (event.event == AuthChangeEvent.tokenRefreshed) {
            print('🔄 Token de sesión rotado (persistido actualizado)');
          }
        }
        break;
      default:
        break;
    }
  }

  /// Fuerza un refresh si la sesión expira pronto. Devuelve true si al final
  /// hay una sesión vigente.
  Future<bool> ensureFreshSession({bool allowReauthentication = true}) =>
      _refreshInFlight ??= _checkAndRefresh(
        allowReauthentication: allowReauthentication,
      ).whenComplete(() => _refreshInFlight = null);

  Future<bool> _checkAndRefresh({required bool allowReauthentication}) async {
    final client = _client;
    final session = client.auth.currentSession;
    if (session == null) return false;
    alignCurrentSession();
    final now = ServerTimeService().now().toUtc();
    final expiresAt = sessionTokenExpiresAt(session);
    if (expiresAt != null && expiresAt.difference(now) > _refreshMargin) {
      return true;
    }
    if (_retryAfter != null && now.isBefore(_retryAfter!)) return false;
    final signOutVersion = _explicitSignOutVersion;
    try {
      final response = await client.auth.refreshSession();
      final newSession = response.session;
      if (newSession != null) {
        final tokenExpiry = sessionTokenExpiresAt(newSession);
        if (client.auth.currentSession?.accessToken != newSession.accessToken ||
            tokenExpiry == null ||
            !tokenExpiry.isAfter(ServerTimeService().now())) {
          return false;
        }
        alignCurrentSession();
        _retryAfter = null;
        await _prefs.updateAccessToken(
          newSession.accessToken,
          expiresAt: tokenExpiry.millisecondsSinceEpoch ~/ 1000,
        );
        print('🔄 Sesión refrescada manualmente');
        return true;
      }
      return false;
    } on AuthException catch (e) {
      debugPrint(
        jsonEncode({
          'event': 'session_refresh_failed',
          'status': e.statusCode,
          'code': e.code,
          'transient': isTransientAuthFailure(e),
        }),
      );
      if (isTransientAuthFailure(e)) {
        _retryAfter = ServerTimeService().now().add(const Duration(minutes: 2));
        if (client.auth.currentSession == null &&
            _explicitSignOutVersion == signOutVersion &&
            expiresAt != null &&
            expiresAt.isAfter(ServerTimeService().now())) {
          await client.auth.setInitialSession(jsonEncode(session.toJson()));
          alignCurrentSession();
        }
        return false;
      }
      if (!allowReauthentication || !isInvalidRefreshToken(e)) return false;
      // Refresh token inválido/expulsado: caer a reautenticación con las
      // credenciales guardadas (mismo flujo que al recuperar conexión).
      print('⚠️ Refresh token rechazado (${e.message}); reautenticando...');
      try {
        return await ReauthenticationService().reauthenticateUser();
      } catch (reauthError) {
        print('❌ Reautenticación fallida: $reauthError');
        return false;
      }
    } catch (e) {
      // Típicamente error de red: se reintenta en el próximo tick.
      print('⚠️ Refresh de sesión falló (se reintenta): $e');
      _retryAfter = ServerTimeService().now().add(const Duration(minutes: 2));
      return false;
    }
  }
}
