import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import 'permissions_service.dart';
import 'subscription_guard_service.dart';
import 'user_preferences_service.dart';
import 'native_session_vault_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  static StreamSubscription<AuthState>? _sessionSubscription;
  factory AuthService() => _instance;
  AuthService._internal();

  SupabaseClient get _supabase => Supabase.instance.client;

  // Initialize Supabase
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: SupabaseConfig.supabaseUrl,
      anonKey: SupabaseConfig.supabaseAnonKey,
    );
    await NativeSessionVaultService.restoreSupabaseSession();
    await PermissionsService().initializeSessionPermissions();
    _sessionSubscription ??= Supabase.instance.client.auth.onAuthStateChange
        .listen((state) {
          if (state.event == AuthChangeEvent.signedOut) {
            NativeSessionVaultService.clear();
            PermissionsService().clearAllCache();
          } else {
            NativeSessionVaultService.saveSession(state.session);
          }
        });
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
