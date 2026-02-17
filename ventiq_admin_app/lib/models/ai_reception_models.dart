class AiReceptionDraft {
  final String localId;
  final String? originalTerm;
  final int? productId; // Matched Product ID
  final String productName; // Matched or inferred name
  final String? productSku;
  final double quantity;
  final double? price;
  final bool isMatched; // True if productId is found
  final String? unit; // e.g. 'caja', 'botella' from text

  const AiReceptionDraft({
    required this.localId,
    this.originalTerm,
    this.productId,
    required this.productName,
    this.productSku,
    required this.quantity,
    this.price,
    this.isMatched = false,
    this.unit,
  });

  AiReceptionDraft copyWith({
    String? productName,
    int? productId,
    String? productSku,
    double? quantity,
    double? price,
    bool? isMatched,
    String? unit,
  }) {
    return AiReceptionDraft(
      localId: localId,
      originalTerm: originalTerm,
      productName: productName ?? this.productName,
      productId: productId ?? this.productId,
      productSku: productSku ?? this.productSku,
      quantity: quantity ?? this.quantity,
      price: price ?? this.price,
      isMatched: isMatched ?? this.isMatched,
      unit: unit ?? this.unit,
    );
  }
}

class AiReceptionResult {
  final List<AiReceptionDraft> items;
  final String? reason;
  final String? location;
  final String? currency;
  final String? observations;
  final String? receivedBy;
  final String? deliveredBy;

  const AiReceptionResult({
    required this.items,
    this.reason,
    this.location,
    this.currency,
    this.observations,
    this.receivedBy,
    this.deliveredBy,
  });
}

class ProductAiContext {
  final int id;
  final String denominacion;
  final String? sku;

  ProductAiContext({required this.id, required this.denominacion, this.sku});

  Map<String, dynamic> toJson() => {
    'id': id,
    'n': denominacion,
    if (sku != null) 's': sku,
  };
}

class MotivoAiContext {
  final int id;
  final String denominacion;

  MotivoAiContext({required this.id, required this.denominacion});

  Map<String, dynamic> toJson() => {'id': id, 'n': denominacion};
}

class UbicacionAiContext {
  final int id;
  final String denominacion;

  UbicacionAiContext({required this.id, required this.denominacion});

  Map<String, dynamic> toJson() => {'id': id, 'n': denominacion};
}
