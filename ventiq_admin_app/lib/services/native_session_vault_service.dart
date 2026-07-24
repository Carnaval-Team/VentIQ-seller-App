import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NativeSessionVaultService {
  static const _channel = MethodChannel('com.inventtia.admin/session_vault');

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> saveSession(Session? session) async {
    if (!_isAndroid || session == null) return;
    await _channel.invokeMethod<void>('write', {
      'session': jsonEncode(session.toJson()),
    });
  }

  static Future<bool> restoreSupabaseSession() async {
    if (!_isAndroid || Supabase.instance.client.auth.currentSession != null) {
      return Supabase.instance.client.auth.currentSession != null;
    }

    final persistedSession = await _channel.invokeMethod<String>('read');
    if (persistedSession == null || persistedSession.isEmpty) return false;

    try {
      final response = await Supabase.instance.client.auth.recoverSession(
        persistedSession,
      );
      return response.session != null;
    } catch (_) {
      await clear();
      return false;
    }
  }

  static Future<void> clear() async {
    if (!_isAndroid) return;
    await _channel.invokeMethod<void>('clear');
  }
}
