import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_preferences_service.dart';

class AuthService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static final UserPreferencesService _prefsService = UserPreferencesService();

  static User? get currentUser => _supabase.auth.currentUser;
  static String? get currentUserId => currentUser?.id;
  static bool get isLoggedIn => currentUser != null;

  static Stream<AuthState> get authStateChanges =>
      _supabase.auth.onAuthStateChange;

  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  static Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) async {
    return await _supabase.auth.signUp(
      email: email,
      password: password,
    );
  }

  static Future<void> signOut() async {
    await _supabase.auth.signOut();
    // Limpiar preferencias locales
    await _prefsService.clearUserData();
  }

  static Future<void> resetPassword(String email) async {
    await _supabase.auth.resetPasswordForEmail(email);
  }

  /// Crea un nuevo usuario en auth.users y su perfil en flow.perfil.
  /// Retorna el UUID del usuario creado. Requiere la RPC flow.admin_create_user.
  static Future<String> createUserFromAdmin({
    required String email,
    required String password,
    required String nombre,
    required String apellidos,
    required String ci,
    String? telefono,
  }) async {
    final res = await _supabase.schema('flow').rpc(
      'admin_create_user',
      params: {
        'p_email': email.trim().toLowerCase(),
        'p_password': password,
        'p_nombre': nombre.trim(),
        'p_apellidos': apellidos.trim(),
        'p_ci': ci.trim(),
        'p_telefono': telefono?.trim(),
      },
    );
    return res.toString();
  }

  // Métodos robustos para gestión de usuario (estilo ventiq_app)

  /// Obtener usuario actual con múltiples fallbacks
  static Future<User?> getCurrentUserWithFallback() async {
    try {
      // 1. Intentar de Supabase directo
      final supabaseUser = _supabase.auth.currentUser;
      if (supabaseUser != null) {
        return supabaseUser;
      }

      // 2. Intentar getUser() de Supabase
      final response = await _supabase.auth.getUser();
      if (response.user != null) {
        return response.user;
      }

      // 3. Fallback a SharedPreferences
      final userId = await _prefsService.getUserId();
      if (userId != null) {
        final userResponse = await _supabase.auth.getUser();
        return userResponse.user;
      }

      return null;
    } catch (e) {
      print('❌ Error obteniendo usuario con fallback: $e');
      return null;
    }
  }

  /// Obtener UUID del usuario con múltiples fallbacks
  static Future<String?> getCurrentUserId() async {
    try {
      // 1. Intentar de Supabase directo
      final supabaseUser = _supabase.auth.currentUser;
      if (supabaseUser?.id != null) {
        return supabaseUser!.id;
      }

      // 2. Intentar getUser() de Supabase
      final response = await _supabase.auth.getUser();
      if (response.user?.id != null) {
        return response.user!.id;
      }

      // 3. Fallback a SharedPreferences
      final cachedUserId = await _prefsService.getUserId();
      if (cachedUserId != null) {
        return cachedUserId;
      }

      return null;
    } catch (e) {
      print('❌ Error obteniendo UUID del usuario: $e');
      // Último recurso: intentar de SharedPreferences
      return await _prefsService.getUserId();
    }
  }

  /// Verificar si hay sesión válida (incluyendo offline)
  static Future<bool> hasValidSession() async {
    return await _prefsService.hasValidSession();
  }

  /// Forzar refresh de sesión
  static Future<bool> refreshSession() async {
    return await _prefsService.refreshSession();
  }

  /// Sincronizar estado con Supabase Auth
  static Future<void> syncWithSupabaseAuth() async {
    await _prefsService.syncWithSupabaseAuth();
  }

  /// Verificar si hay datos cacheados
  static Future<bool> hasCachedData() async {
    return await _prefsService.hasCachedData();
  }
}
