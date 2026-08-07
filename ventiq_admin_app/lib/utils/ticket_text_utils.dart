/// Utilidades para texto en tickets térmicos (ancho típico ~32 caracteres).
List<String> wrapTicketText(String text, {int maxChars = 32}) {
  final cleaned = text.trim().replaceAll(RegExp(r'\s+'), ' ');
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
  final qtyLabel = qty.toString().trim();
  final name = productName.trim().replaceAll(RegExp(r'\s+'), ' ');
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
