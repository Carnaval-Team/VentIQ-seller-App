import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'user_session_service.dart';

class AccessModeInfo {
  final String token;
  final bool isLoggedIn;
  final String? displayName;
  final String? email;

  const AccessModeInfo({
    required this.token,
    required this.isLoggedIn,
    this.displayName,
    this.email,
  });

  String get friendlyName {
    final name = (displayName ?? '').trim();
    if (name.isNotEmpty) return name;
    final mail = (email ?? '').trim();
    if (mail.isNotEmpty) return mail;
    return 'Invitado';
  }
}

class UserActivityService {
  static const String appName = 'inventtia_catalgo';
  static const String _guestTokenKey = 'guest_user_token_marketplace';

  final SupabaseClient _supabase;
  final UserSessionService _sessionService;
  final Uuid _uuid;

  UserActivityService({
    SupabaseClient? supabase,
    UserSessionService? sessionService,
    Uuid? uuid,
  }) : _supabase = supabase ?? Supabase.instance.client,
       _sessionService = sessionService ?? UserSessionService(),
       _uuid = uuid ?? const Uuid();

  Future<String> _getOrCreateGuestToken() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_guestTokenKey);
    if (existing != null && existing.trim().isNotEmpty) return existing;

    final token = _uuid.v4();
    await prefs.setString(_guestTokenKey, token);
    return token;
  }

  Future<AccessModeInfo> resolveAccessMode() async {
    final authUser = _supabase.auth.currentUser;
    final sessionUser = await _sessionService.getUser();

    String? token = authUser?.id;
    String? email = authUser?.email;
    bool isLoggedIn = token != null && token.isNotEmpty;

    final sessionId = sessionUser?['uuid'];
    if (!isLoggedIn && sessionId is String && sessionId.isNotEmpty) {
      token = sessionId;
      isLoggedIn = true;
    }

    final displayName = _buildDisplayName(sessionUser);
    if (email == null || email.trim().isEmpty) {
      final storedEmail = sessionUser?['email'];
      if (storedEmail is String && storedEmail.trim().isNotEmpty) {
        email = storedEmail;
      }
    }

    token ??= await _getOrCreateGuestToken();

    return AccessModeInfo(
      token: token,
      isLoggedIn: isLoggedIn,
      displayName: displayName,
      email: email,
    );
  }

  Future<AccessModeInfo> registerAccess() async {
    final info = await resolveAccessMode();

    try {
      await _supabase.rpc(
        'fn_upsert_actividad_usuario',
        params: {'p_token': info.token, 'p_app': appName},
      );
    } catch (e) {
      print('❌ Error registrando actividad del usuario: $e');
    }

    return info;
  }

  String _buildDisplayName(Map<String, dynamic>? user) {
    if (user == null) return '';
    final nombres = (user['nombres'] as String?)?.trim();
    final apellidos = (user['apellidos'] as String?)?.trim();
    final parts = [
      if (nombres != null && nombres.isNotEmpty) nombres,
      if (apellidos != null && apellidos.isNotEmpty) apellidos,
    ];
    return parts.join(' ');
  }
}
