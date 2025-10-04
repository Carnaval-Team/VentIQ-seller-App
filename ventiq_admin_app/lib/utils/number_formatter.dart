/// Utilidad para formatear números grandes con sufijos K y M
class NumberFormatter {
  /// Formatea valores de moneda para mostrar K y M para números grandes
  /// Ejemplo: 1500000 -> "1.5M", 150000 -> "150K", 1234.56 -> "1234.56"
  static String formatCurrency(double value) {
    if (value == 0) return '0.00';
    
    if (value >= 1000000) {
      // Para millones, mostrar con 1 decimal
      double millions = value / 1000000;
      if (millions == millions.roundToDouble()) {
        return '${millions.toStringAsFixed(0)}M';
      } else {
        return '${millions.toStringAsFixed(1)}M';
      }
    } else if (value >= 100000) {
      // Para valores >= 100,000, mostrar en K sin decimales
      return '${(value / 1000).toStringAsFixed(0)}K';
    } else {
      // Para valores menores, mostrar con decimales normales
      return value.toStringAsFixed(2);
    }
  }

  /// Formatea números enteros para mostrar K y M
  /// Ejemplo: 1500000 -> "1.5M", 1500 -> "1K", 123 -> "123"
  static String formatNumber(double value) {
    if (value == 0) return '0';
    
    if (value >= 1000000) {
      // Para millones, mostrar con 1 decimal si es necesario
      double millions = value / 1000000;
      if (millions == millions.roundToDouble()) {
        return '${millions.toStringAsFixed(0)}M';
      } else {
        return '${millions.toStringAsFixed(1)}M';
      }
    } else if (value >= 1000) {
      // Para miles, sin decimales
      return '${(value / 1000).toStringAsFixed(0)}K';
    } else {
      return value.toStringAsFixed(0);
    }
  }

  /// Formatea números con separadores de miles
  /// Ejemplo: 1234567 -> "1,234,567"
  static String formatWithCommas(double value) {
    return value.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }
}
