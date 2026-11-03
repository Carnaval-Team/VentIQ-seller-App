import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

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

  final UserPreferencesService _prefs = UserPreferencesService();

  StreamSubscription<AuthState>? _authSub;
  Timer? _timer;
  bool _started = false;
  bool _refreshing = false;

  /// Margen antes de la expiración en el que se dispara el refresh.
  static const Duration _refreshMargin = Duration(minutes: 2);
  static const Duration _checkInterval = Duration(seconds: 60);

  void start() {
    if (_started) return;
    _started = true;

    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen(
      _onAuthState,
      onError: (Object e) => print('⚠️ SessionRefresh: error en auth stream: $e'),
    );

    // Revisión periódica por si el auto-refresh interno de gotrue no corrió
    // (app reanudada, timer perdido en background, etc.).
    _timer = Timer.periodic(_checkInterval, (_) => _checkAndRefresh());

    print('🔐 SessionRefreshService iniciado');
  }

  void stop() {
    _authSub?.cancel();
    _authSub = null;
    _timer?.cancel();
    _timer = null;
    _started = false;
  }

  Future<void> _onAuthState(AuthState event) async {
    final session = event.session;
    switch (event.event) {
      case AuthChangeEvent.tokenRefreshed:
      case AuthChangeEvent.signedIn:
        // Mantener el token persistido al día tras cada rotación/login.
        if (session != null && session.accessToken.isNotEmpty) {
          await _prefs.updateAccessToken(
            session.accessToken,
            expiresAt: session.expiresAt,
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
  Future<bool> ensureFreshSession() => _checkAndRefresh();

  Future<bool> _checkAndRefresh() async {
    if (_refreshing) return true;
    final client = Supabase.instance.client;
    final session = client.auth.currentSession;
    if (session == null) return false;

    final expiresAt = session.expiresAt;
    if (expiresAt != null) {
      final expiresIn = DateTime.fromMillisecondsSinceEpoch(
        expiresAt * 1000,
        isUtc: true,
      ).difference(ServerTimeService().now().toUtc());
      if (expiresIn > _refreshMargin) return true;
    }

    _refreshing = true;
    try {
      final response = await client.auth.refreshSession();
      final newSession = response.session;
      if (newSession != null) {
        await _prefs.updateAccessToken(
          newSession.accessToken,
          expiresAt: newSession.expiresAt,
        );
        print('🔄 Sesión refrescada manualmente');
        return true;
      }
      return false;
    } on AuthException catch (e) {
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
      return false;
    } finally {
      _refreshing = false;
    }
  }
}
