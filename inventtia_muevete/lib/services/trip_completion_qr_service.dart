import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Generates and validates QR payloads for offline trip completion.
///
/// Payload format: base64(JSON + HMAC-SHA256 signature).
/// The HMAC prevents tampering; the timestamp prevents replay (10 min window).
class TripCompletionQrService {
  // In production, load from env / secure storage.
  static const String _hmacSecret = 'muevete-qr-secret-2024';
  static const Duration _maxAge = Duration(minutes: 10);

  /// Build a signed QR payload string (base64-encoded JSON).
  static String generatePayload({
    required int solicitudId,
    required int viajeId,
    required int driverId,
    required String userId,
    required double precio,
    required String metodoPago,
  }) {
    final ts = DateTime.now().toUtc().toIso8601String();
    final data = {
      'sol_id': solicitudId,
      'viaje_id': viajeId,
      'driver_id': driverId,
      'user_id': userId,
      'precio': precio,
      'metodo': metodoPago,
      'ts': ts,
    };
    final jsonStr = jsonEncode(data);
    final hmac = _sign(jsonStr);
    data['hmac'] = hmac;
    return base64Encode(utf8.encode(jsonEncode(data)));
  }

  /// Decode and validate a scanned QR string.
  /// Returns the payload map on success, or `null` if invalid / expired.
  static Map<String, dynamic>? validateAndDecode(String raw) {
    try {
      final jsonStr = utf8.decode(base64Decode(raw));
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      // Extract and remove HMAC for verification
      final receivedHmac = data.remove('hmac') as String?;
      if (receivedHmac == null) return null;

      // Verify signature
      final expectedHmac = _sign(jsonEncode(data));
      if (receivedHmac != expectedHmac) return null;

      // Verify timestamp freshness
      final ts = DateTime.tryParse(data['ts'] as String? ?? '');
      if (ts == null) return null;
      if (DateTime.now().toUtc().difference(ts) > _maxAge) return null;

      return data;
    } catch (_) {
      return null;
    }
  }

  static String _sign(String payload) {
    final key = utf8.encode(_hmacSecret);
    final bytes = utf8.encode(payload);
    return Hmac(sha256, key).convert(bytes).toString();
  }
}
