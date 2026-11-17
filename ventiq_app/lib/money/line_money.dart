import 'exact_money.dart';

/// Resultado de una línea. Los importes finales ya están a 2 decimales.
class LineMoney {
  final String moneda;
  final ExactMoney unitarioNeto;
  final ExactMoney bruto;
  final ExactMoney previoManual;
  final ExactMoney manualNominal;
  final ExactMoney neto;
  final ExactMoney equivalenteCup;
  final ExactMoney residual;
  final bool esGratuidad;

  const LineMoney({
    required this.moneda,
    required this.unitarioNeto,
    required this.bruto,
    required this.previoManual,
    required this.manualNominal,
    required this.neto,
    required this.equivalenteCup,
    required this.residual,
    required this.esGratuidad,
  });

  Map<String, String> toFixture() {
    return {
      'unit_net': unitarioNeto.toString(),
      'line_gross': bruto.toFixed(2),
      'subtotal_before_manual': previoManual.toFixed(2),
      'manual_nominal': manualNominal.toString(),
      'line_net': neto.toFixed(2),
      'cup_net': equivalenteCup.toFixed(2),
      'rounding_delta': residual.toString(),
    };
  }
}

class LineMoneyException implements Exception {
  final String code;
  LineMoneyException(this.code);
  @override
  String toString() => code;
}

/// Precio propio, ajuste automático, manual por unidad, cantidad y neto a 2 decimales.
class LineMoneyCalculator {
  static LineMoney calcular({
    required String moneda,
    required String cantidad,
    required String? precioUnitario,
    required String automaticoTipo,
    required String automaticoValor,
    required String manualUnitario,
    required String? tasaCup,
  }) {
    if (moneda != 'CUP' && moneda != 'USD') {
      throw LineMoneyException('UNSUPPORTED_CURRENCY');
    }
    if (precioUnitario == null || precioUnitario.trim().isEmpty || precioUnitario == '0') {
      throw LineMoneyException('NATIVE_PRICE_UNAVAILABLE');
    }
    final cantidadExacta = _parse(cantidad, 'INVALID_QUANTITY');
    if (cantidadExacta == ExactMoney.cero || cantidad.startsWith('-')) {
      throw LineMoneyException('INVALID_QUANTITY');
    }
    final precio = _parse(precioUnitario, 'NATIVE_PRICE_UNAVAILABLE');
    if (precio == ExactMoney.cero || precioUnitario.startsWith('-')) {
      throw LineMoneyException('NATIVE_PRICE_UNAVAILABLE');
    }
    final manual = _parse(manualUnitario, 'INVALID_DECIMAL');
    if (manualUnitario.startsWith('-')) {
      throw LineMoneyException('INVALID_DECIMAL');
    }
    final antes = _aplicarAutomatico(precio, automaticoTipo, automaticoValor);
    if (manual > antes) {
      throw LineMoneyException('INVALID_DECIMAL');
    }
    final unitario = antes - manual;
    final tasa = _tasa(moneda, tasaCup);
    final bruto = precio.timesMoney(cantidadExacta).roundHalfUp(2);
    final previo = antes.timesMoney(cantidadExacta).roundHalfUp(2);
    final nominal = manual.timesMoney(cantidadExacta);
    final exacto = unitario.timesMoney(cantidadExacta);
    final neto = exacto.roundHalfUp(2);
    return LineMoney(
      moneda: moneda,
      unitarioNeto: unitario,
      bruto: bruto,
      previoManual: previo,
      manualNominal: nominal,
      neto: neto,
      equivalenteCup: neto.timesMoney(tasa).roundHalfUp(2),
      residual: neto - exacto,
      esGratuidad: neto == ExactMoney.cero,
    );
  }

  /// Suma netos ya fijados. No vuelve a redondear el grupo ideal.
  static ExactMoney sumarNetos(Iterable<LineMoney> lineas) {
    var total = ExactMoney.cero;
    for (final linea in lineas) {
      total += linea.neto;
    }
    return total;
  }

  static ExactMoney _aplicarAutomatico(
    ExactMoney precio,
    String tipo,
    String valor,
  ) {
    switch (tipo) {
      case 'none':
        return precio;
      case 'discount_percent':
        return precio.percentOff(_porcentaje(valor));
      case 'surcharge_percent':
        return precio.percentOn(_porcentaje(valor));
      case 'discount_unit':
        final descuento = _parse(valor, 'INVALID_DECIMAL');
        if (descuento > precio) throw LineMoneyException('INVALID_DECIMAL');
        return precio - descuento;
      case 'surcharge_unit':
        return precio + _parse(valor, 'INVALID_DECIMAL');
      default:
        throw LineMoneyException('INVALID_DECIMAL');
    }
  }

  static int _porcentaje(String valor) {
    if (!RegExp(r'^\d+$').hasMatch(valor)) {
      throw LineMoneyException('INVALID_DECIMAL');
    }
    final percent = int.parse(valor);
    if (percent < 0 || percent > 100) {
      throw LineMoneyException('INVALID_DECIMAL');
    }
    return percent;
  }

  static ExactMoney _tasa(String moneda, String? tasa) {
    if (moneda == 'CUP') {
      if (tasa != null && tasa != '1') {
        throw LineMoneyException('INVALID_DECIMAL');
      }
      return ExactMoney.parse('1');
    }
    if (tasa == null || tasa.isEmpty || tasa == '0' || tasa.startsWith('-')) {
      throw LineMoneyException('SNAPSHOT_EVIDENCE_REQUIRED');
    }
    return _parse(tasa, 'INVALID_DECIMAL');
  }

  static ExactMoney _parse(String raw, String code) {
    try {
      return ExactMoney.parse(raw);
    } on FormatException {
      throw LineMoneyException(code);
    }
  }
}
