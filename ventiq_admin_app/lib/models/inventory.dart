class InventoryItem {
  final String id;
  final String productId;
  final String variantId;
  final String productName;
  final String variantName;
  final String presentation;
  final String sku;
  final String warehouseId;
  final String warehouseName;
  final String location;
  final int currentStock;
  final int minStock;
  final int maxStock;
  final double unitCost;
  final String abcClassification; // A, B, C
  final DateTime lastMovement;
  final bool needsRestock;

  InventoryItem({
    required this.id,
    required this.productId,
    required this.variantId,
    required this.productName,
    required this.variantName,
    required this.presentation,
    required this.sku,
    required this.warehouseId,
    required this.warehouseName,
    required this.location,
    required this.currentStock,
    required this.minStock,
    required this.maxStock,
    required this.unitCost,
    required this.abcClassification,
    required this.lastMovement,
    required this.needsRestock,
  });

  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    return InventoryItem(
      id: json['id'] ?? '',
      productId: json['productId'] ?? '',
      variantId: json['variantId'] ?? '',
      productName: json['productName'] ?? '',
      variantName: json['variantName'] ?? '',
      presentation: json['presentation'] ?? '',
      sku: json['sku'] ?? '',
      warehouseId: json['warehouseId'] ?? '',
      warehouseName: json['warehouseName'] ?? '',
      location: json['location'] ?? '',
      currentStock: json['currentStock'] ?? 0,
      minStock: json['minStock'] ?? 0,
      maxStock: json['maxStock'] ?? 0,
      unitCost: (json['unitCost'] ?? 0.0).toDouble(),
      abcClassification: json['abcClassification'] ?? 'C',
      lastMovement: DateTime.parse(json['lastMovement'] ?? DateTime.now().toIso8601String()),
      needsRestock: json['needsRestock'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'productId': productId,
      'variantId': variantId,
      'productName': productName,
      'variantName': variantName,
      'presentation': presentation,
      'sku': sku,
      'warehouseId': warehouseId,
      'warehouseName': warehouseName,
      'location': location,
      'currentStock': currentStock,
      'minStock': minStock,
      'maxStock': maxStock,
      'unitCost': unitCost,
      'abcClassification': abcClassification,
      'lastMovement': lastMovement.toIso8601String(),
      'needsRestock': needsRestock,
    };
  }
}

class InventoryMovement {
  final String id;
  final String inventoryItemId;
  final String type; // entrada, salida, transferencia, ajuste
  final int quantity;
  final String reason;
  final String userId;
  final String userName;
  final DateTime timestamp;
  final String? fromWarehouse;
  final String? toWarehouse;
  final String? reference;

  InventoryMovement({
    required this.id,
    required this.inventoryItemId,
    required this.type,
    required this.quantity,
    required this.reason,
    required this.userId,
    required this.userName,
    required this.timestamp,
    this.fromWarehouse,
    this.toWarehouse,
    this.reference,
  });

  factory InventoryMovement.fromJson(Map<String, dynamic> json) {
    return InventoryMovement(
      id: json['id'] ?? '',
      inventoryItemId: json['inventoryItemId'] ?? '',
      type: json['type'] ?? '',
      quantity: json['quantity'] ?? 0,
      reason: json['reason'] ?? '',
      userId: json['userId'] ?? '',
      userName: json['userName'] ?? '',
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
      fromWarehouse: json['fromWarehouse'],
      toWarehouse: json['toWarehouse'],
      reference: json['reference'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'inventoryItemId': inventoryItemId,
      'type': type,
      'quantity': quantity,
      'reason': reason,
      'userId': userId,
      'userName': userName,
      'timestamp': timestamp.toIso8601String(),
      'fromWarehouse': fromWarehouse,
      'toWarehouse': toWarehouse,
      'reference': reference,
    };
  }
}
