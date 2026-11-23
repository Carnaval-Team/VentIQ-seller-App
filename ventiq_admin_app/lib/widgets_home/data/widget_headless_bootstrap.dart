import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/supabase_config.dart';

/// Arranque mínimo de Supabase para isolates headless (WorkManager y el
/// callback de interactividad de home_widget).
///
/// Un isolate de background NO pasa por `main()` ni por `AuthService.initialize`,
/// así que hay que inicializar Supabase a mano. La sesión se recupera sola:
/// `supabase_flutter` la persiste en SharedPreferences (clave
/// `sb-<host>-auth-token`) y esas preferencias son las mismas que ve el isolate,
/// porque los plugins se registran automáticamente en el FlutterEngine que crea
/// home_widget.
class WidgetHeadlessBootstrap {
  WidgetHeadlessBootstrap._();

  static bool _initialized = false;

  /// Inicializa Supabase una sola vez por isolate.
  ///
  /// Devuelve `true` si hay sesión utilizable. Sin sesión los RPCs fallarían con
  /// "Acceso denegado", así que el llamador debe mostrar el estado de error en
  /// lugar de dejar el widget en blanco.
  static Future<bool> ensureReady() async {
    if (!_initialized) {
      try {
        await Supabase.initialize(
          url: SupabaseConfig.supabaseUrl,
          anonKey: SupabaseConfig.supabaseAnonKey,
          // En background no hace falta escuchar deep links de auth.
          authOptions: const FlutterAuthClientOptions(
            detectSessionInUri: false,
          ),
        );
        _initialized = true;
      } catch (error) {
        // `initialize` lanza si ya se inicializó en este isolate (caso del
        // isolate principal, donde AuthService ya lo hizo).
        if (_isAlreadyInitialized(error)) {
          _initialized = true;
        } else {
          debugPrint('❌ Widget headless: no se pudo inicializar Supabase: $error');
          return false;
        }
      }
    }

    return await _hasUsableSession();
  }

  static Future<bool> _hasUsableSession() async {
    final auth = Supabase.instance.client.auth;
    final session = auth.currentSession;

    // NO llamar refreshSession aquí. Un refresh fallido (red, 429, etc.) hace
    // que gotrue emita signedOut y borre el storage compartido con la app en
    // foreground: el usuario aparece "deslogueado" sin haber cerrado sesión.
    // Si el access token ya venció, el widget simplemente no refresca datos
    // hasta que la app principal rote el JWT.
    if (session == null || session.isExpired) {
      return false;
    }

    return true;
  }

  static bool _isAlreadyInitialized(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('already initialized') ||
        text.contains('this instance is already');
  }
}
