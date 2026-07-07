import 'dart:math';

/// Generador de UUID v4 sin dependencias externas.
///
/// Se usa como `client_uuid` para garantizar idempotencia al sincronizar
/// ventas/turnos creados offline: cada orden offline lleva un UUID único y
/// estable que el servidor usa para no duplicar la operación si la
/// sincronización se reintenta. Reemplaza el uso del timestamp como
/// identificador (que podía colisionar).
class UuidGenerator {
  static final Random _random = Random.secure();

  /// Genera un UUID v4 (formato 8-4-4-4-12, variante RFC 4122).
  static String v4() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));

    // Versión 4 (xxxx...4xxx...)
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    // Variante RFC 4122 (10xx)
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final h = bytes.map(hex).toList();

    return '${h[0]}${h[1]}${h[2]}${h[3]}-'
        '${h[4]}${h[5]}-'
        '${h[6]}${h[7]}-'
        '${h[8]}${h[9]}-'
        '${h[10]}${h[11]}${h[12]}${h[13]}${h[14]}${h[15]}';
  }
}
