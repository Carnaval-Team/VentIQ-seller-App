/// Utility functions for price formatting and calculations
class PriceUtils {
  /// Rounds a discount price to the nearest integer and formats it with .00
  /// This ensures all discount prices are displayed as whole numbers with .00
  static double roundDiscountPrice(double discountPrice) {
    return discountPrice.roundToDouble();
  }

  /// Formats a discount price as a string with .00 decimals
  static String formatDiscountPrice(double discountPrice) {
    final roundedPrice = roundDiscountPrice(discountPrice);
    return roundedPrice.toStringAsFixed(2);
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

  /// Formats a quantity smartly: "2" for 2.0, "1.5" for 1.5, "0.25" for 0.25
  static String paymentCurrency(Map<String, dynamic> payment) {
    final raw = (payment['moneda'] ?? payment['currency'] ?? '')
        .toString()
        .trim()
        .toUpperCase();
    return raw == 'USD' ? 'USD' : 'CUP';
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

  static double paymentCupEquivalent(
    Map<String, dynamic> payment, {
    double? fallbackRate,
  }) {
    final savedRaw = payment['monto_cup_equivalente'];
    if (savedRaw != null) {
      final saved = _paymentNumber(savedRaw);
      // 0 explícito en filas USD suele ser dato incompleto: recalcular.
      if (saved > 0 || paymentCurrency(payment) != 'USD') return saved;
    }
    final amount = paymentAmount(payment);
    if (paymentCurrency(payment) != 'USD') return amount;
    final rate = _paymentNumber(payment['tasa_usd']);
    final effectiveRate = rate > 0 ? rate : (fallbackRate ?? 0);
    if (effectiveRate > 0) return amount * effectiveRate;
    return amount;
  }

  static double paymentTotalCup(
    List<Map<String, dynamic>> payments, {
    double? fallbackRate,
  }) =>
      payments.fold(
        0,
        (total, payment) =>
            total + paymentCupEquivalent(payment, fallbackRate: fallbackRate),
      );

  static double paymentTotalUsd(List<Map<String, dynamic>> payments) => payments
      .where((payment) => paymentCurrency(payment) == 'USD')
      .fold(0, (total, payment) => total + paymentAmount(payment));

  static String formatPaymentAmount(Map<String, dynamic> payment) =>
      '${paymentAmount(payment).toStringAsFixed(2)} ${paymentCurrency(payment)}';

  static String paymentDisplayCurrency(List<Map<String, dynamic>> payments) {
    if (payments.isEmpty) return 'CUP';
    return payments.every((payment) => paymentCurrency(payment) == 'USD')
        ? 'USD'
        : 'CUP';
  }

  static double? paymentUsdRate(
    List<Map<String, dynamic>> payments, {
    double? fallbackRate,
  }) {
    for (final payment in payments) {
      if (paymentCurrency(payment) != 'USD') continue;
      final rate = _paymentNumber(payment['tasa_usd']);
      if (rate > 0) return rate;
    }
    if (fallbackRate != null && fallbackRate > 0) return fallbackRate;
    return null;
  }

  static String formatCupAmountForPayments(
    double cupAmount,
    List<Map<String, dynamic>> payments, {
    double? fallbackRate,
  }) {
    if (paymentDisplayCurrency(payments) == 'USD') {
      final rate = paymentUsdRate(payments, fallbackRate: fallbackRate);
      if (rate != null && rate > 0) {
        return '${(cupAmount / rate).toStringAsFixed(2)} USD';
      }
      // Orden USD sin tasa usable: no mentir con etiqueta CUP.
      return '${cupAmount.toStringAsFixed(2)} USD';
    }
    return '${cupAmount.toStringAsFixed(2)} CUP';
  }

  /// Convierte un monto CUP a la moneda de visualización del ticket.
  static double cupToTicketAmount(
    double cupAmount,
    List<Map<String, dynamic>> payments, {
    double? fallbackRate,
  }) {
    if (paymentDisplayCurrency(payments) != 'USD') return cupAmount;
    final rate = paymentUsdRate(payments, fallbackRate: fallbackRate);
    if (rate == null || rate <= 0) return cupAmount;
    return cupAmount / rate;
  }

  static String formatTicketMoney(
    double cupAmount,
    List<Map<String, dynamic>> payments, {
    int cupDecimals = 0,
    double? fallbackRate,
  }) {
    final isUsd = paymentDisplayCurrency(payments) == 'USD';
    final amount = cupToTicketAmount(
      cupAmount,
      payments,
      fallbackRate: fallbackRate,
    );
    if (isUsd) return '${amount.toStringAsFixed(2)} USD';
    return '\$${amount.toStringAsFixed(cupDecimals)} CUP';
  }

  /// Normaliza mapas de pago de listar_ordenes / get_sale_payments2 / checkout.
  static Map<String, dynamic> normalizePaymentMap(Map<String, dynamic> raw) {
    final map = Map<String, dynamic>.from(raw);
    final amount = paymentAmount(map);
    map['monto'] = amount;
    if (map['moneda'] == null && map['currency'] != null) {
      map['moneda'] = map['currency'];
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
    return quantity.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }
}
