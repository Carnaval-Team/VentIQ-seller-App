import '../models/bank_sms_payment.dart';

/// Parser de los SMS de confirmación de pago del número corto `PAGOxMOVIL`.
///
/// La plantilla del banco no es estable en espaciado ni en saltos de línea:
/// en muestras reales aparecen `Monto Pagado: 840.00 CUP` y
/// `Monto Pagado:1.00 CUP` (sin espacio), y el `Nro. Transaccion Banco:`
/// suele venir con el valor en la línea siguiente y con un punto final.
/// Por eso el parseo normaliza los espacios y usa regex laxas en lugar de
/// partir por líneas.
class BankSmsParser {
  /// Remitentes aceptados. El corto real es `PAGOxMOVIL`, pero algunas
  /// operadoras lo entregan normalizado (mayúsculas, sin la `x`) y en pruebas
  /// llega desde un número normal.
  static const Set<String> knownSenders = {
    'PAGOXMOVIL',
    'PAGOMOVIL',
    'PAGO X MOVIL',
  };

  /// Bancos conocidos, del nombre más largo al más corto para que
  /// "Banco Popular de Ahorro" no se confunda con "Banco Popular".
  static const List<String> _bancos = [
    'Banco Popular de Ahorro',
    'Banco Metropolitano',
    'Banco Bandec',
    'Bandec',
    'Metropolitano',
    'Popular de Ahorro',
  ];

  /// `true` si el remitente parece ser la pasarela de pago.
  ///
  /// Se compara sin espacios ni signos para tolerar `PAGOxMOVIL`,
  /// `PAGO-MOVIL`, etc.
  static bool isKnownSender(String? address) {
    if (address == null || address.trim().isEmpty) return false;
    final normalized =
        address.toUpperCase().replaceAll(RegExp(r'[\s\-_.]'), '');
    for (final sender in knownSenders) {
      if (normalized == sender.replaceAll(' ', '')) return true;
    }
    // `PAGOxMOVIL` puede llegar con prefijos/sufijos de operadora.
    return normalized.contains('PAGOXMOVIL') ||
        normalized.contains('PAGOMOVIL');
  }

  /// Intenta parsear el cuerpo de un SMS. Devuelve `null` si no corresponde a
  /// una confirmación de pago completada (p. ej. un SMS de pago rechazado, o
  /// un fragmento incompleto de un mensaje multipart todavía sin reensamblar).
  static BankSmsPayment? parse(
    String body, {
    DateTime? receivedAt,
  }) {
    if (body.trim().isEmpty) return null;

    // Normalizar: saltos de línea → espacios, colapsar espacios múltiples.
    // Esto permite que el mismo regex funcione con el valor en la misma línea
    // o en la siguiente.
    final text = body.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Debe ser una confirmación exitosa. "Elpago"/"El pago" (con y sin
    // espacio, ambos aparecen en muestras reales) y "completado".
    final esCompletado = RegExp(
      r'el\s?pago\s+externo\s+fue\s+completado',
      caseSensitive: false,
    ).hasMatch(text);
    if (!esCompletado) return null;

    // El nro de transacción del banco es obligatorio: sin él no hay
    // identificador único y no podemos garantizar idempotencia.
    final nroTxBanco = _matchGroup(
      text,
      // Alfanumérico de al menos 8 chars. Se excluye el punto final.
      RegExp(
        r'Nro\.?\s*Transaccion\s+Banco\s*:?\s*([A-Z0-9]{8,})',
        caseSensitive: false,
      ),
    );
    if (nroTxBanco == null) return null;

    // El monto también es obligatorio: es lo que se compara con el total.
    // Tolera ausencia de espacio tras los dos puntos y separador de miles.
    final montoRaw = _matchGroup(
      text,
      RegExp(
        r'Monto\s+Pagado\s*:?\s*([\d.,]+)\s*([A-Z]{3})?',
        caseSensitive: false,
      ),
    );
    if (montoRaw == null) return null;
    final monto = _parseAmount(montoRaw);
    if (monto == null || monto <= 0) return null;

    final moneda = _matchGroup(
          text,
          RegExp(
            r'Monto\s+Pagado\s*:?\s*[\d.,]+\s*([A-Z]{3})',
            caseSensitive: false,
          ),
        )?.toUpperCase() ??
        'CUP';

    return BankSmsPayment(
      banco: _detectBanco(text),
      fecha: _parseFecha(text),
      entidad: _matchGroup(
        text,
        // Se corta en la siguiente etiqueta conocida.
        RegExp(
          r'Entidad\s*:?\s*(.+?)\s*(?:Nro\.?\s*Transaccion|Monto\s+Pagado|Fecha\s*:)',
          caseSensitive: false,
        ),
      ),
      nroTransaccion: _matchGroup(
        text,
        // Negative lookahead para no capturar "Nro. Transaccion Banco".
        RegExp(
          r'Nro\.?\s*Transaccion\s*:?\s*(?!Banco)(\d{4,})',
          caseSensitive: false,
        ),
      ),
      nroTransaccionBanco: nroTxBanco.toUpperCase(),
      monto: monto,
      moneda: moneda,
      rawMessage: body,
      receivedAt: receivedAt ?? DateTime.now(),
    );
  }

  /// `true` si el texto parece el inicio de un SMS de pago pero aún no tiene
  /// todos los campos — señal de que es un fragmento multipart incompleto y
  /// conviene esperar/concatenar el resto antes de descartarlo.
  static bool looksLikePartialPayment(String body) {
    final text = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return false;
    final mencionaPago = RegExp(
      r'el\s?pago\s+externo|Monto\s+Pagado|Nro\.?\s*Transaccion',
      caseSensitive: false,
    ).hasMatch(text);
    return mencionaPago && parse(body) == null;
  }

  static String _detectBanco(String text) {
    final lower = text.toLowerCase();
    for (final banco in _bancos) {
      if (lower.contains(banco.toLowerCase())) {
        return banco.startsWith('Banco ') ? banco.substring(6) : banco;
      }
    }
    return 'Desconocido';
  }

  static String? _matchGroup(String text, RegExp pattern) {
    final match = pattern.firstMatch(text);
    if (match == null) return null;
    final value = match.group(1)?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  /// Convierte el monto del SMS a double.
  ///
  /// Formatos vistos: `840.00`, `1.00`. Se contempla `1,234.56` (coma como
  /// separador de miles) y `840,00` (coma decimal) por si la plantilla varía.
  static double? _parseAmount(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;

    final lastDot = s.lastIndexOf('.');
    final lastComma = s.lastIndexOf(',');

    if (lastDot >= 0 && lastComma >= 0) {
      // Ambos presentes: el último es el separador decimal.
      if (lastComma > lastDot) {
        s = s.replaceAll('.', '').replaceAll(',', '.');
      } else {
        s = s.replaceAll(',', '');
      }
    } else if (lastComma >= 0) {
      // Solo coma: decimal si deja 1-2 dígitos detrás, si no es de miles.
      final decimals = s.length - lastComma - 1;
      s = decimals <= 2 ? s.replaceAll(',', '.') : s.replaceAll(',', '');
    }

    return double.tryParse(s);
  }

  /// Parsea `Fecha: 11/8/2026` (d/M/yyyy, sin cero de relleno).
  static DateTime? _parseFecha(String text) {
    final raw = _matchGroup(
      text,
      RegExp(r'Fecha\s*:?\s*(\d{1,2}/\d{1,2}/\d{2,4})', caseSensitive: false),
    );
    if (raw == null) return null;

    final parts = raw.split('/');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    var year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    if (year < 100) year += 2000;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;

    return DateTime(year, month, day);
  }
}
