import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import 'admin_access_service.dart';
import 'moneda_venta_service.dart';
import 'subscription_guard_service.dart';
import 'user_preferences_service.dart';
import 'auto_sync_service.dart';
import 'settings_integration_service.dart';
import 'session_refresh_service.dart';
import 'server_time_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  SupabaseClient get client => Supabase.instance.client;

  // Inicializar Supabase
  static Future<void> initialize() async {
    await ServerTimeService().loadPersistedOffset();
    await ServerTimeService().refreshFromNetwork();
    await Supabase.initialize(
      url: SupabaseConfig.supabaseUrl,
      anonKey: SupabaseConfig.supabaseAnonKey,
    );

    // Rotación automática del token: refresca antes de expirar, mantiene el
    // token persistido al día y reautentica si el refresh token falla.
    SessionRefreshService().start();
  }

  // Obtener usuario actual
  User? get currentUser => client.auth.currentUser;

  // Verificar si el usuario está autenticado
  bool get isAuthenticated => currentUser != null;

  // Stream de cambios de autenticación
  Stream<AuthState> get authStateChanges => client.auth.onAuthStateChange;

  // Login con email y password
  Future<AuthResponse> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final elapsed = Stopwatch()..start();
    final attempt = DateTime.now().microsecondsSinceEpoch.toString();
    void log(String event, [Map<String, Object?> fields = const {}]) {
      if (!kDebugMode) return;
      debugPrint(
        jsonEncode({
          'event': event,
          'attempt': attempt,
          'elapsed_ms': elapsed.elapsedMilliseconds,
          ...fields,
        }),
      );
    }

    log('login_auth_started', {
      'host': Uri.parse(SupabaseConfig.supabaseUrl).host,
    });
    final pendingTimer =
        kDebugMode
            ? Timer(const Duration(seconds: 15), () {
              log('login_auth_pending');
            })
            : null;
    try {
      final response = await client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      SessionRefreshService().alignCurrentSession();
      log('login_auth_completed', {
        'has_user': response.user != null,
        'has_session': response.session != null,
      });
      return response;
    } on AuthException catch (e) {
      log('login_auth_failed', {
        'type': e.runtimeType.toString(),
        'status': e.statusCode,
        'code': e.code,
      });
      rethrow;
    } catch (e) {
      log('login_auth_failed', {'type': e.runtimeType.toString()});
      rethrow;
    } finally {
      pendingTimer?.cancel();
      elapsed.stop();
    }
  }

  // Registro con email y password
  Future<AuthResponse> signUpWithEmailAndPassword({
    required String email,
    required String password,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final response = await client.auth.signUp(
        email: email,
        password: password,
        data: metadata,
      );
      return response;
    } catch (e) {
      rethrow;
    }
  }

  // Cerrar sesión
  Future<void> signOut({bool preserveOfflineLicense = false}) async {
    try {
      // Detener sync antes de limpiar credenciales (evita sync en pantalla login).
      await AutoSyncService().stopAutoSync();
      await SettingsIntegrationService().stop();

      await client.auth.signOut();
      // Limpiar caché de suscripción y rol admin.
      // En dispositivo full-offline no borrar la licencia firmada:
      // el siguiente vendedor local la necesita sin volver al servidor.
      if (preserveOfflineLicense) {
        SubscriptionGuardService().clearMemoryCacheOnly();
      } else {
        final fullOffline =
            await UserPreferencesService().isDeviceFullOfflineReady();
        if (fullOffline) {
          SubscriptionGuardService().clearMemoryCacheOnly();
        } else {
          await SubscriptionGuardService().clearCache();
        }
      }
      AdminAccessService().clearMemoryCache();
      // La moneda de venta es una preferencia **de este teléfono**: si no se
      // limpia, el siguiente vendedor que entre heredaría la divisa y las tasas
      // del anterior (y la guardada, que puede no existir en su tienda).
      await MonedaVentaService.limpiar();
      print('👋 Usuario cerró sesión exitosamente');
    } catch (e) {
      print('❌ Error al cerrar sesión: $e');
      rethrow;
    }
  }

  // Resetear password
  Future<void> resetPassword(String email) async {
    try {
      await client.auth.resetPasswordForEmail(email);
    } catch (e) {
      rethrow;
    }
  }

  // Obtener información del usuario
  Future<User?> getUserProfile() async {
    try {
      return currentUser;
    } catch (e) {
      return null;
    }
  }

  // Actualizar perfil del usuario
  Future<UserResponse> updateUserProfile({
    String? email,
    String? password,
    Map<String, dynamic>? data,
  }) async {
    try {
      final response = await client.auth.updateUser(
        UserAttributes(email: email, password: password, data: data),
      );
      return response;
    } catch (e) {
      rethrow;
    }
  }
}
