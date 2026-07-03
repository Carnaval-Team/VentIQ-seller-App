import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  static final SupabaseClient _supabase = Supabase.instance.client;

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
}
