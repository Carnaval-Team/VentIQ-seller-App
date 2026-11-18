import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// Firma y verificación de los QR de cierre de viaje sin conexión.
///
/// ── Formato del payload ──────────────────────────────────────────────────
///
/// El QR es `base64(utf8(json))` y el json lleva siempre la firma en `hmac`.
///
/// * **v2** — el que escribe esta build:
///   ```json
///   {"v": 2, "solicitud_id": 123, "viaje_id": 456, "ts": "…Z", "hmac": "…"}
///   ```
///   **Sin precios.** El monto, la comisión y el neto los fija el servidor en
///   `muevete.fn_completar_viaje`, que no recibe precio y es idempotente.
///   Cualquier cifra en el QR sólo invitaría a manipularla.
///
/// * **v1** — payload de builds anteriores (`sol_id`, `driver_id`, `user_id`,
///   `metodo`, `precio`, `precio_base`). Se sigue **aceptando al leer** para no
///   invalidar QRs ya mostrados en un teléfono, pero sus precios **se ignoran**:
///   al validar sólo se devuelven `solicitud_id` y `viaje_id`.
///
/// ── El secreto no vive en el repositorio ─────────────────────────────────
///
/// Se inyecta en tiempo de compilación:
///
/// ```bash
/// flutter build apk --dart-define=MUEVETE_QR_SECRET=<secreto>
/// flutter run --dart-define=MUEVETE_QR_SECRET=<secreto>
/// ```
///
/// Si la define falta o está vacía el servicio **falla cerrado**:
/// [generatePayload] lanza [StateError] y [validateAndDecode] devuelve `null`.
/// La UI debe mostrar el aviso de [noConfiguradoMensaje] en vez de un QR roto.
///
/// El anti-replay es una ventana de 10 minutos sobre `ts` (UTC).
class TripCompletionQrService {
  /// Secreto HMAC inyectado con `--dart-define=MUEVETE_QR_SECRET=…`.
  /// Nunca se hardcodea: el repo es público.
  static const String _hmacSecret = String.fromEnvironment('MUEVETE_QR_SECRET');

  /// Ventana anti-replay: un QR más viejo (o más nuevo) que esto no vale.
  static const Duration _maxAge = Duration(minutes: 10);

  /// Versión que escribe esta build.
  static const int _versionActual = 2;

  /// Texto único para la UI cuando falta la configuración.
  static const String noConfiguradoMensaje =
      'El cierre por QR no está configurado; usa el cierre en la app.';

  /// Sólo tests: permite fijar el secreto sin recompilar con `--dart-define`.
  ///
  /// `flutter analyze` avisa si se usa fuera de `test/`. En la app siempre es
  /// `null` y manda [_hmacSecret].
  @visibleForTesting
  static String? secretoParaTests;

  static String get _secreto => secretoParaTests ?? _hmacSecret;

  /// `true` cuando hay secreto configurado. Con `false`, generar y validar
  /// QR está deshabilitado (fail closed).
  static bool get configurado => _secreto.trim().isNotEmpty;

  /// Construye el QR firmado (base64 de JSON + HMAC-SHA256).
  ///
  /// No lleva precios: el servidor decide el monto al cerrar.
  static String generatePayload({
    required int solicitudId,
    required int viajeId,
  }) {
    if (!configurado) {
      throw StateError('Cierre por QR no configurado: falta MUEVETE_QR_SECRET');
    }

    final data = <String, dynamic>{
      'v': _versionActual,
      'solicitud_id': solicitudId,
      'viaje_id': viajeId,
      'ts': DateTime.now().toUtc().toIso8601String(),
    };
    data['hmac'] = _sign(jsonEncode(data));
    return base64Encode(utf8.encode(jsonEncode(data)));
  }

  /// Decodifica y valida un QR escaneado.
  ///
  /// Devuelve `{v, solicitud_id, viaje_id, ts}` — **nunca precios** — o `null`
  /// si el QR es inválido, la firma no cuadra, está fuera de la ventana de
  /// 10 minutos o el servicio no está configurado.
  static Map<String, dynamic>? validateAndDecode(String raw) {
    // Fail closed: sin secreto no se valida nada.
    if (!configurado) return null;

    try {
      final jsonStr = utf8.decode(base64Decode(raw));
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      // La firma se calculó sobre el json SIN el campo `hmac`.
      final recibida = data.remove('hmac');
      if (recibida is! String || recibida.isEmpty) return null;

      // Comparación en tiempo constante byte a byte (no `==` de strings).
      if (!_firmaValida(recibida, _sign(jsonEncode(data)))) return null;

      // Ventana anti-replay.
      final ts = DateTime.tryParse(data['ts'] as String? ?? '');
      if (ts == null) return null;
      final desfase = DateTime.now().toUtc().difference(ts.toUtc());
      if (desfase.abs() > _maxAge) return null;

      // v1 y v2 comparten `viaje_id`; la solicitud cambió de nombre (`sol_id`).
      final viajeId = data['viaje_id'];
      final solicitudId = data['solicitud_id'] ?? data['sol_id'];
      if (viajeId is! int || solicitudId is! int) return null;

      // Se devuelve un mapa normalizado: los precios de un v1 se descartan.
      return <String, dynamic>{
        'v': (data['v'] as num?)?.toInt() ?? 1,
        'solicitud_id': solicitudId,
        'viaje_id': viajeId,
        'ts': ts.toUtc().toIso8601String(),
      };
    } catch (_) {
      return null;
    }
  }

  static String _sign(String payload) {
    final key = utf8.encode(_secreto);
    final bytes = utf8.encode(payload);
    return Hmac(sha256, key).convert(bytes).toString();
  }

  /// Compara las dos firmas en tiempo constante: recorre siempre todos los
  /// bytes y acumula la diferencia con XOR, sin cortocircuitos.
  static bool _firmaValida(String recibida, String esperada) {
    final a = utf8.encode(recibida);
    final b = utf8.encode(esperada);
    if (a.length != b.length) return false;
    var diferencia = 0;
    for (var i = 0; i < b.length; i++) {
      diferencia |= a[i] ^ b[i];
    }
    return diferencia == 0;
  }
}