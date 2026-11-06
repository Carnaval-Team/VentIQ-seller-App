/// Utility functions for price formatting and calculations
class PriceUtils {
  static String formatAmount(
    num amount, {
    int decimals = 2,
    String separator = '\u202F',
  }) {
    final parts = amount.toStringAsFixed(decimals).split('.');
    final integer = parts.first.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]}$separator',
    );
    return parts.length == 1 ? integer : '$integer.${parts.last}';
  }

  /// Rounds a discount price to the nearest integer and formats it with .00
  /// This ensures all discount prices are displayed as whole numbers with .00
  static double roundDiscountPrice(double discountPrice) {
    return discountPrice.roundToDouble();
  }

  /// Formats a discount price as a string with .00 decimals
  static String formatDiscountPrice(double discountPrice) {
    final roundedPrice = roundDiscountPrice(discountPrice);
    return formatAmount(roundedPrice);
  }

  /// Calculates and rounds discount price based on original price and discount parameters
  static double? calculateAndRoundDiscountPrice(
    double originalPrice,
    double? valorDescuento,
    int? tipoDescuento,
  ) {
    if (valorDescuento == null || tipoDescuento == null) return null;

    double discountedPrice;

    if (tipoDescuento == 1) {
      // Descuento porcentual
      discountedPrice = originalPrice - (originalPrice * valorDescuento / 100);
    } else if (tipoDescuento == 2) {
      // Descuento exacto (fijo)
      discountedPrice = originalPrice - valorDescuento;
      discountedPrice = discountedPrice > 0 ? discountedPrice : 0.0;
    } else if (tipoDescuento == 3) {
      // Recargo porcentual - aumenta el precio
      discountedPrice = originalPrice + (originalPrice * valorDescuento / 100);
    } else if (tipoDescuento == 4) {
      // Recargo exacto (fijo) - aumenta el precio
      discountedPrice = originalPrice + valorDescuento;
    } else {
      return null;
    }

    return roundDiscountPrice(discountedPrice);
  }

  /// Calcula precios con promoción y maneja el intercambio de precios para "Recargo porcentual"
  /// Retorna un mapa con precio_venta y precio_oferta según el tipo de promoción
  static Map<String, double> calculatePromotionPrices(
    double originalPrice,
    double? valorDescuento,
    int? tipoDescuento,
  ) {
    if (valorDescuento == null || tipoDescuento == null) {
      return {'precio_venta': originalPrice, 'precio_oferta': originalPrice};
    }

    double calculatedPrice;

    if (tipoDescuento == 1) {
      // Descuento porcentual
      calculatedPrice = originalPrice - (originalPrice * valorDescuento / 100);
      return {
        'precio_venta': originalPrice,
        'precio_oferta': roundDiscountPrice(calculatedPrice),
      };
    } else if (tipoDescuento == 2) {
      // Descuento exacto
      calculatedPrice = originalPrice - valorDescuento;
      calculatedPrice = calculatedPrice > 0 ? calculatedPrice : 0.0;
      return {
        'precio_venta': originalPrice,
        'precio_oferta': roundDiscountPrice(calculatedPrice),
      };
    } else if (tipoDescuento == 3) {
      // Recargo porcentual - intercambiar precios
      calculatedPrice = originalPrice + (originalPrice * valorDescuento / 100);
      return {
        'precio_venta': roundDiscountPrice(
          calculatedPrice,
        ), // El precio mayor es ahora precio_venta
        'precio_oferta':
            originalPrice, // El precio original es ahora precio_oferta (menor)
      };
    } else if (tipoDescuento == 4) {
      // Recargo exacto - intercambiar precios
      calculatedPrice = originalPrice + valorDescuento;
      return {
        'precio_venta': roundDiscountPrice(calculatedPrice),
        'precio_oferta': originalPrice,
      };
    }

    return {'precio_venta': originalPrice, 'precio_oferta': originalPrice};
  }

  /// Determina si hay promoción activa
  static bool hasActivePromotion(int? tipoDescuento) {
    return tipoDescuento != null && [1, 2, 3, 4].contains(tipoDescuento);
  }

  /// Obtiene el texto descriptivo del tipo de promoción
  static String getPromotionTypeText(int? tipoDescuento) {
    switch (tipoDescuento) {
      case 1:
        return 'Descuento porcentual';
      case 2:
        return 'Descuento exacto';
      case 3:
        return 'Recargo porcentual';
      case 4:
        return 'Recargo fijo';
      default:
        return '';
    }
  }

  /// Moneda base contable del sistema. Todo se consolida en ella.
  static const String baseCurrency = 'CUP';

  /// Código de moneda del pago, **sin colapsar**.
  ///
  /// Antes devolvía `'USD'` o `'CUP'` (cualquier otra cosa era CUP). Ahora
  /// devuelve el código real, que es lo que permite que una fila `EUR` no se
  /// contabilice como CUP.
  ///
  /// Se normaliza a CUP cuando no viene o cuando el valor no es un código
  /// ISO-4217 de 3 letras (filas antiguas con datos sucios).
  static String paymentCurrency(Map<String, dynamic> payment) {
    final raw =
        (payment['moneda'] ?? payment['currency'] ?? '')
            .toString()
            .trim()
            .toUpperCase();
    if (raw.isEmpty) return baseCurrency;
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(raw)) return baseCurrency;
    return raw;
  }

  static double _paymentNumber(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double paymentAmount(Map<String, dynamic> payment) {
    // listar_ordenes histórico usa `total`; get_sale_payments2 / checkout usan `monto`.
    return _paymentNumber(
      payment['monto'] ??
          payment['total'] ??
          payment['monto_pago'] ??
          payment['monto_total'] ??
          payment['monto_entrega'],
    );
  }

  /// Tasa aplicada del pago (moneda nativa → moneda base).
  ///
  /// Orden de resolución:
  ///   1. `tasa_cambio` (columna nueva, cualquier divisa)
  ///   2. `tasa_usd`   (columna histórica, solo USD)
  ///   3. derivada de `monto_cup_equivalente / monto` (lo que guardó el servidor)
  ///
  /// Devuelve 0 si no hay ninguna forma de determinarla.
  static double paymentRate(Map<String, dynamic> payment) {
    final direct = _paymentNumber(payment['tasa_cambio']);
    if (direct > 0) return direct;

    final legacy = _paymentNumber(payment['tasa_usd']);
    if (legacy > 0) return legacy;

    final amount = paymentAmount(payment);
    final saved = _paymentNumber(payment['monto_cup_equivalente']);
    if (amount > 0 && saved > 0) return saved / amount;

    return 0;
  }

  static double paymentCupEquivalent(
    Map<String, dynamic> payment, {
    double? fallbackRate,
  }) {
    final amount = paymentAmount(payment);
    if (paymentCurrency(payment) == baseCurrency) return amount;

    var rate = paymentRate(payment);
    if (rate <= 0 && fallbackRate != null && fallbackRate > 0) {
      rate = fallbackRate;
    }

    final saved = _paymentNumber(payment['monto_cup_equivalente']);
    if (rate > 0) {
      final calculated = amount * rate;
      // Se prefiere el equivalente guardado si cuadra con monto × tasa: es el
      // valor exacto con el que el servidor decidió `es_pagada`.
      final roundingTolerance = rate * 0.005 + 0.01;
      return saved > 0 && (saved - calculated).abs() <= roundingTolerance
          ? saved
          : calculated;
    }

    return saved > 0 ? saved : amount;
  }

  static double paymentTotalCup(
    List<Map<String, dynamic>> payments, {
    double? fallbackRate,
  }) => payments.fold(
    0,
    (total, payment) =>
        total + paymentCupEquivalent(payment, fallbackRate: fallbackRate),
  );

  /// Suma de los importes NATIVOS de una moneda concreta, sin convertir.
  ///
  /// Es la respuesta exacta a «¿cuánto se cobró en USD?»: no pasa por ninguna
  /// tasa, así que no arrastra redondeos ni depende de la tasa del día.
  static double paymentTotalIn(
    List<Map<String, dynamic>> payments,
    String codigo,
  ) {
    final target = codigo.trim().toUpperCase();
    return payments
        .where((payment) => paymentCurrency(payment) == target)
        .fold(0, (total, payment) => total + paymentAmount(payment));
  }

  /// Se conserva por compatibilidad: suma solo las líneas en USD.
  static double paymentTotalUsd(List<Map<String, dynamic>> payments) =>
      paymentTotalIn(payments, 'USD');

  static String formatPaymentAmount(Map<String, dynamic> payment) =>
      '${formatAmount(paymentAmount(payment))} ${paymentCurrency(payment)}';

  /// Moneda en la que se presenta el total de un conjunto de pagos.
  ///
  /// Todos en la misma divisa → esa divisa. Mezcla → la moneda base (CUP),
  /// que es el consolidado.
  static String paymentDisplayCurrency(List<Map<String, dynamic>> payments) {
    if (payments.isEmpty) return baseCurrency;
    final codigos = payments.map(paymentCurrency).toSet();
    return codigos.length == 1 ? codigos.first : baseCurrency;
  }

  /// Tasa de la primera línea de esa moneda (o la de respaldo).
  static double? paymentRateFor(
    List<Map<String, dynamic>> payments,
    String codigo, {
    double? fallbackRate,
  }) {
    final target = codigo.trim().toUpperCase();
    for (final payment in payments) {
      if (paymentCurrency(payment) != target) continue;
      final rate = paymentRate(payment);
      if (rate > 0) return rate;
    }
    if (fallbackRate != null && fallbackRate > 0) return fallbackRate;
    return null;
  }

  /// Se conserva por compatibilidad: tasa de las líneas en USD.
  static double? paymentUsdRate(
    List<Map<String, dynamic>> payments, {
    double? fallbackRate,
  }) => paymentRateFor(payments, 'USD', fallbackRate: fallbackRate);

  static String formatCupAmountForPayments(
    double cupAmount,
    List<Map<String, dynamic>> payments, {
    double? fallbackRate,
  }) {
    final display = paymentDisplayCurrency(payments);
    if (display == baseCurrency) {
      return '${formatAmount(cupAmount)} $baseCurrency';
    }
    final rate = paymentRateFor(payments, display, fallbackRate: fallbackRate);
    if (rate != null && rate > 0) {
      return '${formatAmount(cupAmount / rate)} $display';
    }
    // Sin tasa usable: no mentir con una etiqueta que no corresponde.
    return '${formatAmount(cupAmount)} $display';
  }

  /// Convierte un monto CUP a la moneda de visualización del ticket.
  static double cupToTicketAmount(
    double cupAmount,
    List<Map<String, dynamic>> payments, {
    double? fallbackRate,
  }) {
    final display = paymentDisplayCurrency(payments);
    if (display == baseCurrency) return cupAmount;
    final rate = paymentRateFor(payments, display, fallbackRate: fallbackRate);
    if (rate == null || rate <= 0) return cupAmount;
    return cupAmount / rate;
  }

  static String formatTicketMoney(
    double cupAmount,
    List<Map<String, dynamic>> payments, {
    int cupDecimals = 0,
    double? fallbackRate,
  }) {
    final display = paymentDisplayCurrency(payments);
    final amount = cupToTicketAmount(
      cupAmount,
      payments,
      fallbackRate: fallbackRate,
    );
    if (display == baseCurrency) {
      return '\$${formatAmount(amount, decimals: cupDecimals, separator: ' ')} $baseCurrency';
    }
    return '${formatAmount(amount, separator: ' ')} $display';
  }

  /// Ajusta UNA línea de pago cuando se aplica un descuento al total.
  ///
  /// El descuento se expresa en moneda base (CUP). Devuelve los tres valores que
  /// hay que escribir en la fila para que quede **coherente**:
  /// `monto × tasa == monto_cup_equivalente`.
  ///
  /// Antes, el llamador escribía `monto = precioFinal` (un importe en CUP) sin
  /// tocar `moneda` ni el equivalente: en una venta en USD grababa un importe en
  /// CUP como si fueran dólares. Esta función es pura para poder probarla.
  ///
  /// - [montoDescontado]: cuánto se rebaja, en moneda base.
  /// - [montoBaseTotal]: importe ANTES del descuento, en moneda base.
  static ({double montoNativo, double equivalenteBase, double baseNativo})
  ajustarPagoPorDescuento(
    Map<String, dynamic> pago, {
    required double montoDescontado,
    required double montoBaseTotal,
  }) {
    final esMonedaBase = paymentCurrency(pago) == baseCurrency;
    final tasa = paymentRate(pago);
    final equivalenteActual = esMonedaBase
        ? paymentAmount(pago)
        : paymentCupEquivalent(pago);

    final equivalenteBase = (equivalenteActual - montoDescontado)
        .clamp(0, double.maxFinite)
        .toDouble();

    if (esMonedaBase) {
      return (
        montoNativo: equivalenteBase,
        equivalenteBase: equivalenteBase,
        baseNativo: montoBaseTotal,
      );
    }

    if (tasa <= 0) {
      // Sin tasa utilizable no se inventa una conversión: se conserva el importe
      // nativo original y solo se corrige el equivalente.
      return (
        montoNativo: paymentAmount(pago),
        equivalenteBase: equivalenteBase,
        baseNativo: montoBaseTotal,
      );
    }

    return (
      montoNativo: equivalenteBase / tasa,
      equivalenteBase: equivalenteBase,
      baseNativo: montoBaseTotal / tasa,
    );
  }

  /// Normaliza mapas de pago de listar_ordenes / get_sale_payments2 / checkout.
  static Map<String, dynamic> normalizePaymentMap(Map<String, dynamic> raw) {
    final map = Map<String, dynamic>.from(raw);
    final amount = paymentAmount(map);
    map['monto'] = amount;
    if (map['moneda'] == null && map['currency'] != null) {
      map['moneda'] = map['currency'];
    }
    // Tasa: unificar las dos columnas y rellenar la que falte.
    //   `tasa_cambio` es la genérica (cualquier divisa).
    //   `tasa_usd`    es la histórica (solo USD) y se mantiene por compatibilidad.
    if (map['tasa_cambio'] == null && map['tasa_usd'] != null) {
      map['tasa_cambio'] = map['tasa_usd'];
    }
    if (map['tasa_usd'] == null &&
        map['tasa_cambio'] != null &&
        paymentCurrency(map) == 'USD') {
      map['tasa_usd'] = map['tasa_cambio'];
    }
    if (map['denominacion'] == null) {
      map['denominacion'] = paymentMethodName(map);
    }
    if (map['es_efectivo'] == null && map['medio_pago_es_efectivo'] != null) {
      map['es_efectivo'] = map['medio_pago_es_efectivo'];
    }
    if (map['es_digital'] == null && map['medio_pago_es_digital'] != null) {
      map['es_digital'] = map['medio_pago_es_digital'];
    }
    if (map['id_medio_pago'] == null && map['medio_pago_id'] != null) {
      map['id_medio_pago'] = map['medio_pago_id'];
    }
    return map;
  }

  static List<Map<String, dynamic>> normalizePayments(dynamic rawList) {
    if (rawList is! List) return const [];
    return rawList
        .map(asPaymentMap)
        .whereType<Map<String, dynamic>>()
        .map(normalizePaymentMap)
        .toList();
  }

  static Map<String, dynamic>? asPaymentMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  static String paymentMethodName(Map<String, dynamic> payment) {
    for (final key in [
      'medio_pago_denominacion',
      'medio_pago_nombre',
      'denominacion',
      'metodo_pago',
      'medio_pago',
    ]) {
      final value = payment[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return 'Pago';
  }

  static bool paymentIsPending(Map<String, dynamic> payment) {
    final id = int.tryParse(
      '${payment['id_medio_pago'] ?? payment['medio_pago_id'] ?? ''}',
    );
    return id == 998;
  }

  static bool paymentIsCash(Map<String, dynamic> payment) {
    if (paymentIsPending(payment)) return false;
    final id = int.tryParse(
      '${payment['id_medio_pago'] ?? payment['medio_pago_id'] ?? ''}',
    );
    return payment['es_efectivo'] == true ||
        payment['medio_pago_es_efectivo'] == true ||
        id == 1 ||
        id == 999;
  }

  /// No efectivo ni pendiente → transferencia/digital/otros.
  static bool paymentIsDigital(Map<String, dynamic> payment) {
    if (paymentIsPending(payment) || paymentIsCash(payment)) return false;
    return true;
  }

  static String formatQuantity(double quantity) {
    if (quantity == quantity.roundToDouble()) {
      return quantity.toInt().toString();
    }
    return quantity
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }
}

extension MonetaryAmountFormat on num {
  String toMoneyString([int decimals = 2, String separator = '\u202F']) =>
      PriceUtils.formatAmount(this, decimals: decimals, separator: separator);
}
