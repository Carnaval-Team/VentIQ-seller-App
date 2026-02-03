import 'price_utils.dart';

class PromotionRules {
  static const Set<int> _recargoPromotionTypes = {8, 9};
  static const Set<int> _quantityGreaterPromotionTypes = {10, 11};
  static const Set<int> _twoForOnePromotionTypes = {3};

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

    final requiredPaymentId = promotion['id_medio_pago_requerido'] as int?;
    if (requiredPaymentId == null) {
      if (isRecargoPromotionType(promotion)) {
        return paymentMethodId == 1;
      }
      return true;
    }

    if (paymentMethodId == null) {
      return false;
    }

    return normalizePaymentMethodId(paymentMethodId) == requiredPaymentId;
  }

  static bool isRecargoPromotionType(Map<String, dynamic> promotion) {
    final typeId = _parsePromotionTypeId(promotion);
    if (typeId != null && _recargoPromotionTypes.contains(typeId)) {
      return true;
    }

    if (promotion['es_recargo'] == true) {
      return true;
    }

    return promotion['tipo_descuento'] == 3;
  }

  static bool isTwoForOnePromotionType(Map<String, dynamic> promotion) {
    final typeId = _parsePromotionTypeId(promotion);
    if (typeId != null && _twoForOnePromotionTypes.contains(typeId)) {
      return true;
    }

    final name =
        '${promotion['tipo_promocion_nombre'] ?? ''} ${promotion['nombre'] ?? ''} ${promotion['descripcion'] ?? ''}'
            .toLowerCase();
    return name.contains('2x1') ||
        name.contains('2 x 1') ||
        name.contains('dos por uno');
  }

  static bool isQuantityGreaterPromotionType(Map<String, dynamic> promotion) {
    final typeId = _parsePromotionTypeId(promotion);
    return typeId != null && _quantityGreaterPromotionTypes.contains(typeId);
  }

  static bool requiresExactMinCompra(Map<String, dynamic> promotion) {
    final rawExact =
        promotion['min_compra_exacta'] ?? promotion['min_compra_exacto'];
    if (rawExact is bool) {
      return rawExact;
    }

    return false;
  }

  static bool isMinimumPurchaseMet(
    Map<String, dynamic> promotion, {
    required int? quantity,
  }) {
    final minCompra = _parseMinCompra(promotion);
    if (minCompra == null || minCompra <= 0) {
      return true;
    }

    if (quantity == null || quantity <= 0) {
      return false;
    }

    if (isQuantityGreaterPromotionType(promotion)) {
      return quantity > minCompra;
    }

    if (requiresExactMinCompra(promotion)) {
      return quantity == minCompra;
    }

    if (isTwoForOnePromotionType(promotion)) {
      return quantity >= minCompra && quantity % minCompra == 0;
    }

    return quantity >= minCompra;
  }

  static bool isGlobalPromotion(Map<String, dynamic> promotion) {
    return promotion['aplica_todo'] == true;
  }

  static Map<String, dynamic>? pickPromotionForPayment({
    required List<Map<String, dynamic>>? productPromotions,
    required Map<String, dynamic>? globalPromotion,
    required int? paymentMethodId,
    required int? quantity,
  }) {
    final productPromotion = _pickMostRecentPromotion(
      productPromotions,
      paymentMethodId: paymentMethodId,
      quantity: quantity,
    );
    if (productPromotion != null) {
      return productPromotion;
    }

    if (globalPromotion == null || globalPromotion['aplica_todo'] == false) {
      return null;
    }

    if (!isMinimumPurchaseMet(globalPromotion, quantity: quantity)) {
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
    required int? quantity,
  }) {
    final productPromotion = _pickMostRecentPromotion(
      productPromotions,
      quantity: quantity,
    );
    if (productPromotion != null) {
      return productPromotion;
    }

    if (globalPromotion == null || globalPromotion['aplica_todo'] == false) {
      return null;
    }

    if (!isMinimumPurchaseMet(globalPromotion, quantity: quantity)) {
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
    int? quantity,
  }) {
    if (promotions == null || promotions.isEmpty) {
      return null;
    }

    final sortedPromotions = _sortPromotionsByRecency(promotions);
    for (final promotion in sortedPromotions) {
      if (!isMinimumPurchaseMet(promotion, quantity: quantity)) {
        continue;
      }

      if (paymentMethodId == null) {
        return promotion;
      }

      if (!isPaymentMethodCompatible(promotion, paymentMethodId)) {
        continue;
      }

      return promotion;
    }

    return null;
  }

  static int? _parsePromotionTypeId(Map<String, dynamic> promotion) {
    final rawId = promotion['id_tipo_promocion'] ?? promotion['tipo_promocion'];

    if (rawId is int) {
      return rawId;
    }

    if (rawId is num) {
      return rawId.toInt();
    }

    if (rawId is String) {
      return int.tryParse(rawId);
    }

    return null;
  }

  static int? _parseMinCompra(Map<String, dynamic> promotion) {
    final rawMinCompra = promotion['min_compra'];

    if (rawMinCompra is int) {
      return rawMinCompra;
    }

    if (rawMinCompra is num) {
      return rawMinCompra.round();
    }

    if (rawMinCompra is String) {
      final normalized = rawMinCompra.replaceAll(',', '.').trim();
      if (normalized.isEmpty) {
        return null;
      }
      return int.tryParse(normalized) ?? double.tryParse(normalized)?.round();
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
