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
    var session = auth.currentSession;

    // Con el token vencido se intenta refrescar antes de rendirse: el refresh
    // token persiste en SharedPreferences junto al access token.
    if (session != null && session.isExpired) {
      try {
        final response = await auth.refreshSession();
        session = response.session;
      } catch (error) {
        debugPrint('⚠️ Widget headless: refresh de sesión falló: $error');
        return false;
      }
    }

    return session != null;
  }

  static bool _isAlreadyInitialized(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('already initialized') ||
        text.contains('this instance is already');
  }
}
