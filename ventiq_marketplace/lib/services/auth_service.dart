import 'package:supabase_flutter/supabase_flutter.dart';

import 'user_session_service.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final UserSessionService _sessionService;

  AuthService({UserSessionService? sessionService})
    : _sessionService = sessionService ?? UserSessionService();

  User? get currentUser => _supabase.auth.currentUser;

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final response = await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );

    final user = response.user;
    if (user == null) {
      throw Exception('No se pudo iniciar sesión.');
    }

    await _sessionService.saveUser(
      uuid: user.id,
      email: user.email ?? email,
      nombres: (user.userMetadata?['nombres'] as String?),
      apellidos: (user.userMetadata?['apellidos'] as String?),
      telefono: (user.userMetadata?['telefono'] as String?),
    );
  }

  Future<void> signUpWithEmail({
    required String email,
    required String password,
    required String nombres,
    required String apellidos,
    required String telefono,
  }) async {
    final response = await _supabase.auth.signUp(
      email: email,
      password: password,
      data: {'nombres': nombres, 'apellidos': apellidos, 'telefono': telefono},
    );

    final user = response.user;
    if (user == null) {
      throw Exception('No se pudo crear la cuenta.');
    }

    if (response.session == null) {
      try {
        final login = await _supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );
        if (login.session == null) {
          throw Exception();
        }
      } catch (_) {
        throw Exception(
          'Cuenta creada, pero Supabase requiere confirmación por correo. Desactiva la confirmación de email en Authentication > Providers > Email.',
        );
      }
    }

    await _sessionService.saveUser(
      uuid: user.id,
      email: user.email ?? email,
      nombres: nombres,
      apellidos: apellidos,
      telefono: telefono,
    );
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
    await _sessionService.clear();
  }

  Future<void> syncLocalUserFromSupabaseIfNeeded() async {
    final localUserId = await _sessionService.getUserId();
    if (localUserId != null) return;

    final user = _supabase.auth.currentUser;
    if (user == null) return;

    await _sessionService.saveUser(
      uuid: user.id,
      email: user.email ?? '',
      nombres: (user.userMetadata?['nombres'] as String?),
      apellidos: (user.userMetadata?['apellidos'] as String?),
      telefono: (user.userMetadata?['telefono'] as String?),
    );
  }
}
