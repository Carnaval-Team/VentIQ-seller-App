/// Lectura y parche de un importe de TPV.
/// Un vacío no es cero. El cero explícito no es un precio válido.
class TpvPriceMoney {
  static double? opcional(Object? raw) {
    if (raw == null) return null;
    final text = raw.toString().trim();
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (value == null || value <= 0 || value.isNaN || value.isInfinite) {
      throw FormatException('Precio invalido');
    }
    return value;
  }

  /// Celda vacía o columna ausente: heredar. Cero o texto inválido: rechazar.
  static ({double? valor, bool heredar}) leerCelda(
    Map<String, dynamic> row,
    String columna,
  ) {
    if (!row.containsKey(columna)) {
      return (valor: null, heredar: true);
    }
    final raw = row[columna];
    if (raw == null || raw.toString().trim().isEmpty) {
      return (valor: null, heredar: true);
    }
    return (valor: opcional(raw), heredar: false);
  }
}

class TpvPricePreview {
  static String texto({required bool editando, required bool usdVacio}) {
    if (usdVacio && editando) {
      return 'USD vacío: se conserva el de esta vigencia. El CUP sigue obligatorio.';
    }
    if (usdVacio) {
      return 'Sin USD propio. No se habilita un precio solo en USD.';
    }
    return 'USD propio de esta vigencia. No reemplaza el CUP.';
  }
}
