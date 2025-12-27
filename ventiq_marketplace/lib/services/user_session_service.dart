import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class UserSessionService {
  static const String _userKey = 'marketplace_user';

  Future<void> saveUser({
    required String uuid,
    required String email,
    String? nombres,
    String? apellidos,
    String? telefono,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final payload = <String, dynamic>{
      'uuid': uuid,
      'email': email,
      'nombres': nombres,
      'apellidos': apellidos,
      'telefono': telefono,
    };

    await prefs.setString(_userKey, jsonEncode(payload));
  }

  Future<Map<String, dynamic>?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_userKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return Map<String, dynamic>.from(decoded as Map);
    } catch (_) {
      return null;
    }
  }

  Future<String?> getUserId() async {
    final user = await getUser();
    final uuid = user?['uuid'];
    if (uuid is String && uuid.isNotEmpty) return uuid;
    return null;
  }

  Future<bool> isLoggedIn() async {
    final uuid = await getUserId();
    return uuid != null;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
  }
}
