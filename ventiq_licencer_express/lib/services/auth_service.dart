import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  AuthService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );

    final user = response.user ?? _client.auth.currentUser;
    if (user == null) {
      throw Exception('No se pudo iniciar sesion.');
    }

    final isSuperadmin = await _isSuperadmin(email);
    if (!isSuperadmin) {
      await _client.auth.signOut();
      throw Exception('Acceso restringido solo a superadmin.');
    }
  }

  Future<void> signOut() => _client.auth.signOut();

  Future<bool> isCurrentUserSuperadmin() async {
    final email = _client.auth.currentUser?.email;
    if (email == null || email.isEmpty) {
      return false;
    }
    return _isSuperadmin(email);
  }

  Future<bool> _isSuperadmin(String email) async {
    try {
      final data = await _client
          .from('app_dat_superadmin')
          .select('id')
          .eq('correo', email)
          .maybeSingle();
      if (data != null) {
        return true;
      }
    } catch (_) {}

    try {
      final data = await _client
          .from('app_dat_superadmin')
          .select('id')
          .eq('email', email)
          .maybeSingle();
      return data != null;
    } catch (_) {
      return false;
    }
  }
}
