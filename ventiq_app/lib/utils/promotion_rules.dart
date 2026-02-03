import 'price_utils.dart';

class PromotionRules {
  static const Set<int> _recargoPromotionTypes = {8, 9};
  static const Set<int> _percentageDiscountPromotionTypes = {1, 10};
  static const Set<int> _fixedDiscountPromotionTypes = {2, 3, 4, 5, 6, 7, 11};
  static const Set<int> _quantityGreaterPromotionTypes = {10, 11};
  static const Set<int> _twoForOnePromotionTypes = {3};

  static int normalizePaymentMethodId(int? paymentMethodId) {
    if (paymentMethodId == 999 || paymentMethodId == 99) {
      return 4;
    }
    return paymentMethodId ?? -1;
  }

  static bool isPaymentMethodCompatible(
    Map<String, dynamic> promotion,
    int? paymentMethodId,
  ) {
    final requiresPayment =
        promotion['requiere_medio_pago'] == true ||
        promotion['id_medio_pago_requerido'] != null;

    if (!requiresPayment) {
      return true;
    }

    final requiredPaymentId = promotion['id_medio_pago_requerido'] as int?;
    if (requiredPaymentId == null) {
      return false;
    }

    if (paymentMethodId == null) {
      return false;
    }

    return normalizePaymentMethodId(paymentMethodId) ==
        normalizePaymentMethodId(requiredPaymentId);
  }

  static bool isRecargoPromotionType(Map<String, dynamic> promotion) {
    final typeId = _parsePromotionTypeId(promotion);
    if (typeId != null && _recargoPromotionTypes.contains(typeId)) {
      return true;
    }

    if (promotion['es_recargo'] == true) {
      return true;
    }

    final tipoDescuento = resolvePromotionDiscountType(promotion);
    return tipoDescuento == 3 || tipoDescuento == 4;
  }

  static int? resolveTipoDescuentoFromPromotionTypeId(int? promotionTypeId) {
    if (promotionTypeId == null) {
      return null;
    }

    if (promotionTypeId == 9) {
      return 3;
    }

    if (promotionTypeId == 8) {
      return 4;
    }

    if (_percentageDiscountPromotionTypes.contains(promotionTypeId)) {
      return 1;
    }

    if (_fixedDiscountPromotionTypes.contains(promotionTypeId)) {
      return 2;
    }

    return null;
  }

  static int? resolvePromotionDiscountType(Map<String, dynamic> promotion) {
    final typeId = _parsePromotionTypeId(promotion);
    final mappedById = resolveTipoDescuentoFromPromotionTypeId(typeId);
    if (mappedById != null) {
      return mappedById;
    }

    final rawTipo = promotion['tipo_descuento'];
    if (rawTipo is int) {
      return rawTipo;
    }

    if (rawTipo is num) {
      return rawTipo.toInt();
    }

    if (rawTipo is String) {
      return int.tryParse(rawTipo);
    }

    return _resolveTipoDescuentoFromName(
      promotion['tipo_promocion_nombre'] as String?,
    );
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
      return quantity >= minCompra;
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
    final tipoDescuento = resolvePromotionDiscountType(promotion);

    return PriceUtils.calculatePromotionPrices(
      basePrice,
      valorDescuento,
      tipoDescuento,
    );
  }

  static double selectPriceForPayment({
    required Map<String, double> prices,
    required int? paymentMethodId,
    Map<String, dynamic>? promotion,
  }) {
    final requiresPayment =
        promotion != null &&
        (promotion['requiere_medio_pago'] == true ||
            promotion['id_medio_pago_requerido'] != null);

    if (requiresPayment) {
      final applyRecargo = isRecargoPromotionType(promotion);
      return applyRecargo ? prices['precio_venta']! : prices['precio_oferta']!;
    }

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

  static int? _resolveTipoDescuentoFromName(String? tipoNombre) {
    switch (tipoNombre?.toLowerCase()) {
      case 'descuento porcentual':
      case 'descuento %':
        return 1;
      case 'descuento exacto':
      case 'descuento fijo':
        return 2;
      case 'recargo porcentual':
        return 3;
      case 'recargo fijo':
        return 4;
      default:
        return null;
    }
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
