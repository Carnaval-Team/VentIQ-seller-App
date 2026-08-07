/// Utilidades para texto en tickets térmicos (ancho típico ~32 caracteres).
///
/// Las impresoras ESC/POS suelen usar CP437/CP850 y no UTF-8: acentos y ñ
/// salen como basura. [sanitizeForThermalPrinter] los convierte a ASCII.

/// Reemplaza acentos/ñ y elimina caracteres no imprimibles para ESC/POS.
String sanitizeForThermalPrinter(String input) {
  if (input.isEmpty) return input;

  const map = <String, String>{
    'á': 'a',
    'à': 'a',
    'ä': 'a',
    'â': 'a',
    'Á': 'A',
    'À': 'A',
    'Ä': 'A',
    'Â': 'A',
    'é': 'e',
    'è': 'e',
    'ë': 'e',
    'ê': 'e',
    'É': 'E',
    'È': 'E',
    'Ë': 'E',
    'Ê': 'E',
    'í': 'i',
    'ì': 'i',
    'ï': 'i',
    'î': 'i',
    'Í': 'I',
    'Ì': 'I',
    'Ï': 'I',
    'Î': 'I',
    'ó': 'o',
    'ò': 'o',
    'ö': 'o',
    'ô': 'o',
    'Ó': 'O',
    'Ò': 'O',
    'Ö': 'O',
    'Ô': 'O',
    'ú': 'u',
    'ù': 'u',
    'ü': 'u',
    'û': 'u',
    'Ú': 'U',
    'Ù': 'U',
    'Ü': 'U',
    'Û': 'U',
    'ñ': 'n',
    'Ñ': 'N',
    'ç': 'c',
    'Ç': 'C',
    '¿': '?',
    '¡': '!',
    'º': 'o',
    'ª': 'a',
    '€': 'EUR',
    '—': '-',
    '–': '-',
    '“': '"',
    '”': '"',
    '‘': "'",
    '’': "'",
    '…': '...',
  };

  final buffer = StringBuffer();
  for (final rune in input.runes) {
    final ch = String.fromCharCode(rune);
    if (map.containsKey(ch)) {
      buffer.write(map[ch]);
      continue;
    }
    // ASCII imprimible + tab/newline básicos
    if (rune == 9 || rune == 10 || rune == 13 || (rune >= 32 && rune <= 126)) {
      buffer.write(ch);
    } else {
      buffer.write('?');
    }
  }
  return buffer.toString();
}

List<String> wrapTicketText(String text, {int maxChars = 32}) {
  final cleaned =
      sanitizeForThermalPrinter(text).trim().replaceAll(RegExp(r'\s+'), ' ');
  if (cleaned.isEmpty) return const [''];
  if (cleaned.length <= maxChars) return [cleaned];

  final words = cleaned.split(' ');
  final lines = <String>[];
  var current = '';

  void flush() {
    if (current.isNotEmpty) {
      lines.add(current);
      current = '';
    }
  }

  void appendHardBroken(String word) {
    var rest = word;
    while (rest.length > maxChars) {
      flush();
      lines.add(rest.substring(0, maxChars));
      rest = rest.substring(maxChars);
    }
    current = rest;
  }

  for (final word in words) {
    if (current.isEmpty) {
      if (word.length <= maxChars) {
        current = word;
      } else {
        appendHardBroken(word);
      }
      continue;
    }

    final candidate = '$current $word';
    if (candidate.length <= maxChars) {
      current = candidate;
    } else {
      flush();
      if (word.length <= maxChars) {
        current = word;
      } else {
        appendHardBroken(word);
      }
    }
  }
  flush();
  return lines;
}

/// Formatea `qty x nombre` permitiendo que el nombre completo salga en varias líneas.
List<String> formatTicketProductLines(
  Object qty,
  String productName, {
  int maxChars = 32,
}) {
  final qtyLabel = sanitizeForThermalPrinter(qty.toString()).trim();
  final name = sanitizeForThermalPrinter(productName)
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
  final prefix = '${qtyLabel}x ';
  final budget = maxChars - prefix.length;

  if (name.length <= budget) {
    return ['$prefix$name'];
  }

  final nameLines = wrapTicketText(name, maxChars: maxChars);
  if (nameLines.isEmpty) return [prefix.trimRight()];

  final first = nameLines.first;
  final lines = <String>[];
  if (first.length <= budget) {
    lines.add('$prefix$first');
    lines.addAll(nameLines.skip(1));
  } else {
    // Prefijo en su línea y nombre completo debajo.
    lines.add(prefix.trimRight());
    lines.addAll(nameLines);
  }
  return lines;
}
