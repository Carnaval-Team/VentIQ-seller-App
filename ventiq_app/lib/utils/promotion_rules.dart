import 'price_utils.dart';

class PromotionRules {
  static int normalizePaymentMethodId(int? paymentMethodId) {
    if (paymentMethodId == 999) {
      return 4;
    }
    return paymentMethodId ?? -1;
  }

  static bool isPaymentMethodCompatible(
    Map<String, dynamic> promotion,
    int? paymentMethodId,
  ) {
    if (promotion['requiere_medio_pago'] != true) {
      return true;
    }

    if (paymentMethodId == null) {
      return false;
    }

    final requiredPaymentId = promotion['id_medio_pago_requerido'] as int?;
    if (requiredPaymentId == null) {
      return false;
    }

    return normalizePaymentMethodId(paymentMethodId) == requiredPaymentId;
  }

  static bool isGlobalPromotion(Map<String, dynamic> promotion) {
    return promotion['aplica_todo'] == true;
  }

  static Map<String, dynamic>? pickPromotionForPayment({
    required List<Map<String, dynamic>>? productPromotions,
    required Map<String, dynamic>? globalPromotion,
    required int? paymentMethodId,
  }) {
    final productPromotion = _pickMostRecentPromotion(
      productPromotions,
      paymentMethodId: paymentMethodId,
    );
    if (productPromotion != null) {
      return productPromotion;
    }

    if (globalPromotion == null || globalPromotion['aplica_todo'] == false) {
      return null;
    }

    if (!isPaymentMethodCompatible(globalPromotion, paymentMethodId)) {
      return null;
    }

    return globalPromotion;
  }

  static Map<String, dynamic>? pickPromotionForDisplay({
    required List<Map<String, dynamic>>? productPromotions,
    required Map<String, dynamic>? globalPromotion,
  }) {
    final productPromotion = _pickMostRecentPromotion(productPromotions);
    if (productPromotion != null) {
      return productPromotion;
    }

    if (globalPromotion == null || globalPromotion['aplica_todo'] == false) {
      return null;
    }

    return globalPromotion;
  }

  static double resolveBasePrice({
    required double unitPrice,
    double? basePrice,
    Map<String, dynamic>? promotion,
  }) {
    final promoBase = (promotion?['precio_base'] as num?)?.toDouble();
    return basePrice ?? promoBase ?? unitPrice;
  }

  static Map<String, double> calculatePromotionPrices({
    required double basePrice,
    required Map<String, dynamic> promotion,
  }) {
    final valorDescuento = promotion['valor_descuento'] as double?;
    final tipoDescuento = promotion['tipo_descuento'] as int?;

    return PriceUtils.calculatePromotionPrices(
      basePrice,
      valorDescuento,
      tipoDescuento,
    );
  }

  static double selectPriceForPayment({
    required Map<String, double> prices,
    required int? paymentMethodId,
  }) {
    return resolvePaymentType(paymentMethodId) == 1
        ? prices['precio_oferta']!
        : prices['precio_venta']!;
  }

  static int resolvePaymentType(int? paymentMethodId) {
    if (paymentMethodId == null || paymentMethodId == 1) {
      return 1;
    }
    return 2;
  }

  static Map<String, dynamic>? _pickMostRecentPromotion(
    List<Map<String, dynamic>>? promotions, {
    int? paymentMethodId,
  }) {
    if (promotions == null || promotions.isEmpty) {
      return null;
    }

    final sortedPromotions = _sortPromotionsByRecency(promotions);
    if (paymentMethodId == null) {
      return sortedPromotions.first;
    }

    for (final promotion in sortedPromotions) {
      if (isPaymentMethodCompatible(promotion, paymentMethodId)) {
        return promotion;
      }
    }

    return null;
  }

  static List<Map<String, dynamic>> _sortPromotionsByRecency(
    List<Map<String, dynamic>> promotions,
  ) {
    final sorted = [...promotions];
    sorted.sort((a, b) {
      final dateA = _parsePromotionDate(a);
      final dateB = _parsePromotionDate(b);

      if (dateA != null || dateB != null) {
        return (dateB ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
          dateA ?? DateTime.fromMillisecondsSinceEpoch(0),
        );
      }

      return _parsePromotionId(b).compareTo(_parsePromotionId(a));
    });

    return sorted;
  }

  static DateTime? _parsePromotionDate(Map<String, dynamic> promotion) {
    final rawDate =
        promotion['created_at'] ??
        promotion['fecha_inicio'] ??
        promotion['updated_at'];

    if (rawDate is DateTime) {
      return rawDate;
    }

    if (rawDate is String) {
      return DateTime.tryParse(rawDate);
    }

    return null;
  }

  static int _parsePromotionId(Map<String, dynamic> promotion) {
    final rawId = promotion['id_promocion'] ?? promotion['id'];

    if (rawId is int) {
      return rawId;
    }

    if (rawId is num) {
      return rawId.toInt();
    }

    if (rawId is String) {
      return int.tryParse(rawId) ?? 0;
    }

    return 0;
  }
}
