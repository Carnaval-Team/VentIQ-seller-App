import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import 'permissions_service.dart';
import 'subscription_guard_service.dart';
import 'user_preferences_service.dart';
import 'native_session_vault_service.dart';
import 'session_cache_manager.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  static StreamSubscription<AuthState>? _sessionSubscription;

  /// Profundidad de un swap intencional de sesión (alta de trabajador / tienda).
  /// Mientras > 0 el listener no persiste sesiones intermedias ni limpia el vault.
  static int _sessionGuardDepth = 0;

  factory AuthService() => _instance;
  AuthService._internal();

  SupabaseClient get _supabase => Supabase.instance.client;

  /// Ejecuta [action] sin perder la sesión actual.
  ///
  /// Guarda la sesión previa, ignora eventos intermedios de auth (p. ej. un
  /// `signUp` que sustituye el JWT) y en el `finally` restaura siempre al
  /// usuario que había antes. Si no se puede restaurar, lanza.
  static Future<T> runWithSessionGuard<T>(Future<T> Function() action) async {
    final client = Supabase.instance.client;
    final prior = client.auth.currentSession;
    final priorUserId = prior?.user.id;
    final priorJson =
        prior == null ? null : jsonEncode(prior.toJson());

    _sessionGuardDepth++;
    try {
      return await action();
    } finally {
      try {
        if (priorJson != null && priorUserId != null) {
          await restoreAdminSession(
            adminSessionJson: priorJson,
            adminUserId: priorUserId,
          );
        }
      } finally {
        _sessionGuardDepth--;
        final session = client.auth.currentSession;
        if (session != null) {
          await NativeSessionVaultService.saveSession(session);
          if (session.accessToken.isNotEmpty) {
            await UserPreferencesService().updateAccessToken(
              session.accessToken,
              expiresAt: session.expiresAt,
            );
          }
          await PermissionsService().initializeSessionPermissions();
        }
      }
    }
  }

  /// Crea o vincula un usuario Auth sin quedarse en su sesión.
  ///
  /// `signUp` / `signInWithPassword` del SDK de cliente reemplazan la sesión
  /// activa; este método garantiza volver a la sesión anterior.
  static Future<({String uuid, bool alreadyExisted})> createOrLinkAuthUser({
    required String email,
    required String password,
    Map<String, dynamic>? data,
  }) async {
    return runWithSessionGuard(() async {
      final client = Supabase.instance.client;
      String? userUuid;
      var alreadyExisted = false;

      try {
        final authResponse = await client.auth.signUp(
          email: email,
          password: password,
          data: data,
          emailRedirectTo: null,
        );
        final user = authResponse.user;
        if (user == null) {
          throw Exception('Error al registrar usuario en Supabase Auth');
        }
        // Protección anti-enumeración: usuario fantasma sin identities.
        if (user.identities != null && user.identities!.isEmpty) {
          throw StateError('user_already_exists');
        }
        userUuid = user.id;
      } catch (signUpError) {
        final msg = signUpError.toString();
        final yaExiste =
            msg.contains('user_already_exists') ||
            msg.contains('User already registered');
        if (!yaExiste) rethrow;

        final loginResponse = await client.auth.signInWithPassword(
          email: email,
          password: password,
        );
        if (loginResponse.user == null) {
          throw Exception(
            'El email ya está registrado pero las credenciales no coinciden. '
            'Verifica la contraseña del usuario.',
          );
        }
        userUuid = loginResponse.user!.id;
        alreadyExisted = true;
      }

      if (userUuid == null || userUuid.isEmpty) {
        throw Exception(
          'No se pudo crear ni verificar el usuario de acceso para $email',
        );
      }
      return (uuid: userUuid, alreadyExisted: alreadyExisted);
    });
  }

  // Initialize Supabase
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: SupabaseConfig.supabaseUrl,
      anonKey: SupabaseConfig.supabaseAnonKey,
    );
    await NativeSessionVaultService.restoreSupabaseSession();
    await PermissionsService().initializeSessionPermissions();
    _sessionSubscription ??= Supabase.instance.client.auth.onAuthStateChange
        .listen((state) async {
          if (_sessionGuardDepth > 0) {
            // Swap controlado: no tocar vault/permisos con la sesión intermedia.
            return;
          }
          if (state.event == AuthChangeEvent.signedOut) {
            NativeSessionVaultService.clear();
            PermissionsService().clearAllCache();
            return;
          }
          final session = state.session;
          if (session == null) return;
          await NativeSessionVaultService.saveSession(session);
          // Mantener el access_token / expiry de preferencias al día con el JWT
          // real. Antes solo se escribían en el login y el splash cortaba a las
          // 24h aunque Supabase siguiera con refresh válido.
          if (session.accessToken.isNotEmpty) {
            await UserPreferencesService().updateAccessToken(
              session.accessToken,
              expiresAt: session.expiresAt,
            );
          }
        });
  }

  /// Fuente de verdad para splash/login: sesión Supabase usable.
  ///
  /// 1) Sesión vigente o refresh.
  /// 2) Si el refresh falla y hay "recordarme", reautentica con credenciales.
  /// 3) Sincroniza preferencias locales con el JWT actual.
  static Future<bool> ensureValidSession() async {
    final client = Supabase.instance.client;
    final prefs = UserPreferencesService();

    Session? session = client.auth.currentSession;

    if (session != null && session.isExpired) {
      try {
        session = (await client.auth.refreshSession()).session;
      } catch (e) {
        print('⚠️ ensureValidSession: refresh falló: $e');
        session = null;
      }
    }

    if (session == null) {
      session = await _tryReauthenticateFromRememberMe(prefs);
    }

    if (session == null) {
      return false;
    }

    if (session.accessToken.isNotEmpty) {
      await prefs.updateAccessToken(
        session.accessToken,
        expiresAt: session.expiresAt,
      );
    }
    await PermissionsService().initializeSessionPermissions();
    return true;
  }

  static Future<Session?> _tryReauthenticateFromRememberMe(
    UserPreferencesService prefs,
  ) async {
    try {
      final remember = await prefs.shouldRememberMe();
      if (!remember) return null;
      final credentials = await prefs.getSavedCredentials();
      final email = credentials['email'];
      final password = credentials['password'];
      if (email == null ||
          email.isEmpty ||
          password == null ||
          password.isEmpty) {
        return null;
      }
      print('🔐 ensureValidSession: reautenticando con credenciales guardadas');
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return response.session;
    } catch (e) {
      print('⚠️ ensureValidSession: reautenticación falló: $e');
      return null;
    }
  }

  /// Restaura la sesión del admin tras un signUp/signIn temporal.
  /// Si [recoverSession] falla, intenta "recordarme" o la sesión JSON de nuevo.
  static Future<void> restoreAdminSession({
    required String adminSessionJson,
    required String adminUserId,
  }) async {
    final client = Supabase.instance.client;
    final currentUserId = client.auth.currentSession?.user.id;
    if (currentUserId == adminUserId) return;

    try {
      await client.auth.recoverSession(adminSessionJson);
    } catch (e) {
      print('⚠️ recoverSession falló: $e');
    }

    if (client.auth.currentSession?.user.id == adminUserId) {
      print('🔄 Sesión del administrador restaurada');
      return;
    }

    final recovered = await _tryReauthenticateFromRememberMe(
      UserPreferencesService(),
    );
    if (recovered?.user.id == adminUserId) {
      print('🔄 Sesión del administrador restaurada vía recordarme');
      return;
    }

    // Último intento: recover otra vez (refresh token del snapshot).
    try {
      final decoded = jsonDecode(adminSessionJson);
      if (decoded is Map && decoded['refresh_token'] is String) {
        await client.auth.setSession(decoded['refresh_token'] as String);
      }
    } catch (e) {
      print('⚠️ setSession de respaldo falló: $e');
    }

    if (client.auth.currentSession?.user.id != adminUserId) {
      throw Exception(
        'No se pudo restaurar la sesión del administrador tras crear el usuario',
      );
    }
  }

  // Sign in with email and password
  Future<AuthResponse> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      print('🔐 Admin login attempt for: $email');
      print('✅ Login successful: ${response.user?.id}');

      return response;
    } catch (e) {
      print('❌ Admin login error: $e');
      rethrow;
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      // Intentar cerrar sesión en Supabase (puede fallar por red o sesión ya expirada)
      try {
        await _supabase.auth.signOut(scope: SignOutScope.local);
        print('✅ Supabase auth signOut completed');
      } catch (authError) {
        print('⚠️ Supabase auth signOut warning: $authError');
        // Continuamos con la limpieza local sin rethrow
      }

      await NativeSessionVaultService.clear();

      // Limpiar TODO el caché de permisos (incluyendo roles por tienda)
      PermissionsService().clearAllCache();

      // Limpiar caché de suscripción
      await SubscriptionGuardService().clearCache();

      // Limpiar TODOS los datos del usuario (tienda, roles, etc.)
      await UserPreferencesService().clearUserData();

      // Invalidar todos los cachés en memoria (roles, tiendas, suscripción, etc.)
      await SessionCacheManager.clearForLogout();

      print('👋 Admin signed out successfully (local cleanup complete)');
    } catch (e) {
      print('❌ Admin sign out error during cleanup: $e');
      // Intentar limpiar preferencias al menos si algo falla catastróficamente
      try {
        await UserPreferencesService().clearUserData();
      } catch (_) {}
      rethrow;
    }
  }

  // Get current user
  User? get currentUser => _supabase.auth.currentUser;

  // Get current session
  Session? get currentSession => _supabase.auth.currentSession;

  // Check if user is signed in
  bool get isSignedIn => currentUser != null;

  // Listen to auth state changes
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  // Verify supervisor permissions and get all stores for user
  Future<List<Map<String, dynamic>>?> verifySupervisorPermissions(
    String userId,
  ) async {
    try {
      print('🔍 Verifying supervisor permissions for user: $userId');

      final response = await _supabase
          .from('app_dat_supervisor')
          .select('*,app_dat_tienda(id,denominacion)')
          .eq('uuid', userId);

      if (response.isNotEmpty) {
        print('✅ Supervisor found with ${response.length} store(s)');
        for (var store in response) {
          print(
            '   - Store ID: ${store['id_tienda']}, Name: ${store['app_dat_tienda']?['denominacion']}',
          );
        }
        return List<Map<String, dynamic>>.from(response);
      }

      print('❌ No supervisor record found for user: $userId');

      final auditorResponse = await _supabase
          .from('auditor')
          .select('*,app_dat_tienda(id,denominacion)')
          .eq('uuid', userId);

      if (auditorResponse.isNotEmpty) {
        print('✅ Auditor found with ${auditorResponse.length} store(s)');
        for (var store in auditorResponse) {
          print(
            '   - Store ID: ${store['id_tienda']}, Name: ${store['app_dat_tienda']?['denominacion']}',
          );
        }
        return List<Map<String, dynamic>>.from(auditorResponse);
      }

      print('❌ No auditor record found for user: $userId');
      return null;
    } catch (e) {
      print('❌ Supervisor verification error: $e');
      return null;
    }
  }

  // Complete login with supervisor verification
  Future<Map<String, dynamic>> signInWithSupervisorVerification({
    required String email,
    required String password,
  }) async {
    try {
      // Step 1: Authenticate with Supabase
      final authResponse = await signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (authResponse.user == null) {
        throw Exception('Authentication failed');
      }

      final userId = authResponse.user!.id;

      // Step 2: Verify supervisor permissions and get all stores
      final supervisorStores = await verifySupervisorPermissions(userId);

      if (supervisorStores == null || supervisorStores.isEmpty) {
        // Sign out the user since they don't have supervisor privileges
        await signOut();
        throw Exception('NO_SUPERVISOR_PRIVILEGES');
      }

      // Step 3: Return complete data for saving
      return {
        'user': authResponse.user!,
        'session': authResponse.session!,
        'supervisorStores': supervisorStores,
        'defaultStore': supervisorStores.first, // Use first store as default
      };
    } catch (e) {
      print('❌ Complete login error: $e');
      rethrow;
    }
  }

  // Get admin profile from user metadata
  Future<Map<String, dynamic>?> getAdminProfile(String userId) async {
    try {
      print('👤 Fetching admin profile for user: $userId');

      final user = currentUser;
      if (user == null) return null;

      return {
        'name':
            user.userMetadata?['name'] ??
            user.email?.split('@')[0] ??
            'Administrador',
        'role': 'Supervisor',
        'email': user.email,
      };
    } catch (e) {
      print('❌ Admin profile fetch error: $e');
      return null;
    }
  }

  // Verify admin permissions (backward compatibility)
  Future<bool> verifyAdminPermissions(String userId) async {
    final supervisorData = await verifySupervisorPermissions(userId);
    return supervisorData != null;
  }
}
