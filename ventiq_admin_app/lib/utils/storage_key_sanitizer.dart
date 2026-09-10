String sanitizeStorageKey(String fileName) {
  String name = fileName.trim();
  if (name.isEmpty) return 'archivo';

  String ext = '';
  final lastDot = name.lastIndexOf('.');
  if (lastDot != -1 && lastDot < name.length - 1) {
    ext = name.substring(lastDot + 1).trim().toLowerCase();
  }

  String base = lastDot != -1 ? name.substring(0, lastDot) : name;

  base = _removeAccents(base)
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9._-]'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  if (base.isEmpty) base = 'archivo';

  return ext.isEmpty ? base : '$base.$ext';
}

String _removeAccents(String text) {
  const replacements = {
    'á': 'a',
    'à': 'a',
    'ä': 'a',
    'â': 'a',
    'ã': 'a',
    'å': 'a',
    'é': 'e',
    'è': 'e',
    'ë': 'e',
    'ê': 'e',
    'í': 'i',
    'ì': 'i',
    'ï': 'i',
    'î': 'i',
    'ó': 'o',
    'ò': 'o',
    'ö': 'o',
    'ô': 'o',
    'õ': 'o',
    'ø': 'o',
    'ú': 'u',
    'ù': 'u',
    'ü': 'u',
    'û': 'u',
    'ñ': 'n',
    'ç': 'c',
    'Á': 'a',
    'À': 'a',
    'Ä': 'a',
    'Â': 'a',
    'Ã': 'a',
    'Å': 'a',
    'É': 'e',
    'È': 'e',
    'Ë': 'e',
    'Ê': 'e',
    'Í': 'i',
    'Ì': 'i',
    'Ï': 'i',
    'Î': 'i',
    'Ó': 'o',
    'Ò': 'o',
    'Ö': 'o',
    'Ô': 'o',
    'Õ': 'o',
    'Ø': 'o',
    'Ú': 'u',
    'Ù': 'u',
    'Ü': 'u',
    'Û': 'u',
    'Ñ': 'n',
    'Ç': 'c',
  };

  final buffer = StringBuffer();
  for (final char in text.split('')) {
    buffer.write(replacements[char] ?? char);
  }
  return buffer.toString();
}
