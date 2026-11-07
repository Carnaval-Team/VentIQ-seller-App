import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

DateTime? sessionTokenExpiresAt(Session session) {
  try {
    final parts = session.accessToken.split('.');
    if (parts.length != 3) return null;
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    if (payload is! Map<String, dynamic>) return null;
    final expiresAt = payload['exp'];
    if (expiresAt is! int) return null;
    return DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000, isUtc: true);
  } on FormatException {
    return null;
  } on RangeError {
    return null;
  }
}

void alignSessionExpiryToDeviceClock(
  Session session,
  DateTime serverNow, {
  DateTime? deviceNow,
}) {
  final expiresAt = sessionTokenExpiresAt(session);
  if (expiresAt == null) return;
  final remaining = expiresAt.difference(serverNow);
  session.expiresAt =
      (deviceNow ?? DateTime.now()).add(remaining).millisecondsSinceEpoch ~/
      1000;
}

bool isTransientAuthFailure(AuthException error) =>
    error is AuthRetryableFetchException ||
    error.statusCode == '429' ||
    (int.tryParse(error.statusCode ?? '') ?? 0) >= 500;

bool isDefinitiveAccessDenial(Object error) =>
    (error is PostgrestException && error.code == '42501') ||
    error.toString() ==
        'Exception: Usuario no autorizado: debe ser vendedor, gerente o supervisor';

bool isInvalidRefreshToken(AuthException error) => const {
  'refresh_token_not_found',
  'refresh_token_already_used',
  'session_not_found',
  'session_expired',
}.contains(error.code);
