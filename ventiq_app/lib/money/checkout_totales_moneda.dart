import '../utils/price_utils.dart';

/// Totales del checkout por moneda, sin convertir entre monedas.
class CheckoutTotalesMoneda {
  /// Cobro anterior: cada línea vale [cup] en moneda base y se cobra en
  /// [moneda]. Sin tasa válida la línea queda en [base]. [factor] reparte el
  /// descuento promocional como el cobro.
  static Map<String, double> desdeLineas(
    List<({double cup, String moneda})> lineas, {
    required double Function(String moneda) tasa,
    required String base,
    double factor = 1.0,
  }) {
    final importes = <String, double>{};
    for (final linea in lineas) {
      var moneda = linea.moneda;
      if (moneda != base && tasa(moneda) <= 0) moneda = base;
      final cup = linea.cup * factor;
      final monto = moneda == base ? cup : cup / tasa(moneda);
      importes[moneda] = (importes[moneda] ?? 0.0) + monto;
    }
    return importes;
  }

  /// Desglose editado: importes nativos de cada pago, escalados por [escala].
  static Map<String, double> desdePagos(
    List<Map<String, dynamic>> pagos, {
    double escala = 1.0,
  }) {
    final importes = <String, double>{};
    for (final pago in pagos) {
      final moneda = PriceUtils.paymentCurrency(pago);
      importes[moneda] =
          (importes[moneda] ?? 0.0) + PriceUtils.paymentAmount(pago) * escala;
    }
    return importes;
  }

  /// Lo que baja cada moneda de [subtotales] a [totales].
  static Map<String, double> diferencia(
    Map<String, double> subtotales,
    Map<String, double> totales,
  ) {
    return {
      for (final moneda in subtotales.keys)
        if (subtotales[moneda]! - (totales[moneda] ?? 0.0) > 0.004)
          moneda: subtotales[moneda]! - (totales[moneda] ?? 0.0),
    };
  }

  /// Una línea por moneda, en el orden de [orden]; las demás al final.
  static String formatear(
    Map<String, double> importes, {
    required List<String> orden,
    required String base,
    String prefijo = '',
  }) {
    if (importes.isEmpty) return '${prefijo}0.00 $base';
    int posicion(String moneda) {
      final i = orden.indexOf(moneda);
      return i < 0 ? orden.length : i;
    }

    final monedas = importes.keys.toList()
      ..sort((a, b) => posicion(a).compareTo(posicion(b)));
    return monedas
        .map((m) => '$prefijo${importes[m]!.toMoneyString(2)} $m')
        .join('\n');
  }
}
