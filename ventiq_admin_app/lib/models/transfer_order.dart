class TransferOrder {
  final String id;
  final String warehouseOriginId;
  final String warehouseOriginName;
  final String zoneOriginId;
  final String zoneOriginName;
  final String? warehouseDestinationId;
  final String? warehouseDestinationName;
  final String? zoneDestinationId;
  final String? zoneDestinationName;
  final List<TransferOrderItem> items;
  final TransferOrderStatus status;
  final DateTime createdAt;
  final DateTime? confirmedAt;
  final String createdByUserId;
  final String? confirmedByUserId;
  final String? observations;
  final double totalItems;
  final List<TransferOperation> operations;

  TransferOrder({
    required this.id,
    required this.warehouseOriginId,
    required this.warehouseOriginName,
    required this.zoneOriginId,
    required this.zoneOriginName,
    this.warehouseDestinationId,
    this.warehouseDestinationName,
    this.zoneDestinationId,
    this.zoneDestinationName,
    required this.items,
    required this.status,
    required this.createdAt,
    this.confirmedAt,
    required this.createdByUserId,
    this.confirmedByUserId,
    this.observations,
    required this.totalItems,
    required this.operations,
  });

  factory TransferOrder.fromJson(Map<String, dynamic> json) {
    return TransferOrder(
      id: json['id'] ?? '',
      warehouseOriginId:
          json['warehouse_origin_id'] ?? json['warehouseOriginId'] ?? '',
      warehouseOriginName:
          json['warehouse_origin_name'] ?? json['warehouseOriginName'] ?? '',
      zoneOriginId: json['zone_origin_id'] ?? json['zoneOriginId'] ?? '',
      zoneOriginName: json['zone_origin_name'] ?? json['zoneOriginName'] ?? '',
      warehouseDestinationId:
          json['warehouse_destination_id'] ?? json['warehouseDestinationId'],
      warehouseDestinationName:
          json['warehouse_destination_name'] ??
          json['warehouseDestinationName'],
      zoneDestinationId:
          json['zone_destination_id'] ?? json['zoneDestinationId'],
      zoneDestinationName:
          json['zone_destination_name'] ?? json['zoneDestinationName'],
      items:
          (json['items'] as List<dynamic>?)
              ?.map((item) => TransferOrderItem.fromJson(item))
              .toList() ??
          [],
      status: TransferOrderStatus.values.firstWhere(
        (s) => s.name == (json['status'] ?? 'pending'),
        orElse: () => TransferOrderStatus.pending,
      ),
      createdAt:
          DateTime.tryParse(json['created_at'] ?? json['createdAt'] ?? '') ??
          DateTime.now(),
      confirmedAt:
          json['confirmed_at'] != null || json['confirmedAt'] != null
              ? DateTime.tryParse(json['confirmed_at'] ?? json['confirmedAt'])
              : null,
      createdByUserId:
          json['created_by_user_id'] ?? json['createdByUserId'] ?? '',
      confirmedByUserId:
          json['confirmed_by_user_id'] ?? json['confirmedByUserId'],
      observations: json['observations'],
      totalItems: (json['total_items'] ?? json['totalItems'] ?? 0).toDouble(),
      operations:
          (json['operations'] as List<dynamic>?)
              ?.map((op) => TransferOperation.fromJson(op))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'warehouse_origin_id': warehouseOriginId,
      'warehouse_origin_name': warehouseOriginName,
      'zone_origin_id': zoneOriginId,
      'zone_origin_name': zoneOriginName,
      'warehouse_destination_id': warehouseDestinationId,
      'warehouse_destination_name': warehouseDestinationName,
      'zone_destination_id': zoneDestinationId,
      'zone_destination_name': zoneDestinationName,
      'items': items.map((item) => item.toJson()).toList(),
      'status': status.name,
      'created_at': createdAt.toIso8601String(),
      'confirmed_at': confirmedAt?.toIso8601String(),
      'created_by_user_id': createdByUserId,
      'confirmed_by_user_id': confirmedByUserId,
      'observations': observations,
      'total_items': totalItems,
      'operations': operations.map((op) => op.toJson()).toList(),
    };
  }

  static List<TransferOperation> generateOperations(
    String transferId,
    TransferOrder transfer,
  ) {
    return [
      TransferOperation(
        id: '${transferId}_global',
        transferOrderId: transferId,
        type: TransferOperationType.global,
        description:
            'Transferencia global de ${transfer.zoneOriginName} a ${transfer.zoneDestinationName}',
        warehouseId: transfer.warehouseOriginId,
        zoneId: transfer.zoneOriginId,
        status: TransferOperationStatus.pending,
        createdAt: DateTime.now(),
      ),
      TransferOperation(
        id: '${transferId}_extraction',
        transferOrderId: transferId,
        type: TransferOperationType.extraction,
        description: 'Extracción de productos desde ${transfer.zoneOriginName}',
        warehouseId: transfer.warehouseOriginId,
        zoneId: transfer.zoneOriginId,
        status: TransferOperationStatus.pending,
        createdAt: DateTime.now(),
      ),
      TransferOperation(
        id: '${transferId}_entry',
        transferOrderId: transferId,
        type: TransferOperationType.entry,
        description: 'Entrada de productos en ${transfer.zoneDestinationName}',
        warehouseId:
            transfer.warehouseDestinationId ?? transfer.warehouseOriginId,
        zoneId: transfer.zoneDestinationId ?? '',
        status: TransferOperationStatus.pending,
        createdAt: DateTime.now(),
      ),
    ];
  }
}

class TransferOrderItem {
  final String id;
  final String productId;
  final String productName;
  final String? productSku;
  final String? variantId;
  final String? variantName;
  final String? presentationId;
  final String? presentationName;
  final double quantity;
  final double availableStock;
  final String? observations;

  TransferOrderItem({
    required this.id,
    required this.productId,
    required this.productName,
    this.productSku,
    this.variantId,
    this.variantName,
    this.presentationId,
    this.presentationName,
    required this.quantity,
    required this.availableStock,
    this.observations,
  });

  factory TransferOrderItem.fromJson(Map<String, dynamic> json) {
    return TransferOrderItem(
      id: json['id'] ?? '',
      productId: json['product_id'] ?? json['productId'] ?? '',
      productName: json['product_name'] ?? json['productName'] ?? '',
      productSku: json['product_sku'] ?? json['productSku'],
      variantId: json['variant_id'] ?? json['variantId'],
      variantName: json['variant_name'] ?? json['variantName'],
      presentationId: json['presentation_id'] ?? json['presentationId'],
      presentationName: json['presentation_name'] ?? json['presentationName'],
      quantity: (json['quantity'] ?? 0).toDouble(),
      availableStock:
          (json['available_stock'] ?? json['availableStock'] ?? 0).toDouble(),
      observations: json['observations'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product_id': productId,
      'product_name': productName,
      'product_sku': productSku,
      'variant_id': variantId,
      'variant_name': variantName,
      'presentation_id': presentationId,
      'presentation_name': presentationName,
      'quantity': quantity,
      'available_stock': availableStock,
      'observations': observations,
    };
  }

  String get displayName {
    List<String> parts = [productName];
    if (variantName != null && variantName!.isNotEmpty) {
      parts.add(variantName!);
    }
    if (presentationName != null && presentationName!.isNotEmpty) {
      parts.add(presentationName!);
    }
    return parts.join(' - ');
  }
}

class TransferOperation {
  final String id;
  final String transferOrderId;
  final TransferOperationType type;
  final String description;
  final String warehouseId;
  final String zoneId;
  final TransferOperationStatus status;
  final DateTime createdAt;
  final DateTime? executedAt;
  final String? executedByUserId;
  final String? observations;

  TransferOperation({
    required this.id,
    required this.transferOrderId,
    required this.type,
    required this.description,
    required this.warehouseId,
    required this.zoneId,
    required this.status,
    required this.createdAt,
    this.executedAt,
    this.executedByUserId,
    this.observations,
  });

  factory TransferOperation.fromJson(Map<String, dynamic> json) {
    return TransferOperation(
      id: json['id'] ?? '',
      transferOrderId:
          json['transfer_order_id'] ?? json['transferOrderId'] ?? '',
      type: TransferOperationType.values.firstWhere(
        (t) => t.name == (json['type'] ?? 'global'),
        orElse: () => TransferOperationType.global,
      ),
      description: json['description'] ?? '',
      warehouseId: json['warehouse_id'] ?? json['warehouseId'] ?? '',
      zoneId: json['zone_id'] ?? json['zoneId'] ?? '',
      status: TransferOperationStatus.values.firstWhere(
        (s) => s.name == (json['status'] ?? 'pending'),
        orElse: () => TransferOperationStatus.pending,
      ),
      createdAt:
          DateTime.tryParse(json['created_at'] ?? json['createdAt'] ?? '') ??
          DateTime.now(),
      executedAt:
          json['executed_at'] != null || json['executedAt'] != null
              ? DateTime.tryParse(json['executed_at'] ?? json['executedAt'])
              : null,
      executedByUserId: json['executed_by_user_id'] ?? json['executedByUserId'],
      observations: json['observations'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'transfer_order_id': transferOrderId,
      'type': type.name,
      'description': description,
      'warehouse_id': warehouseId,
      'zone_id': zoneId,
      'status': status.name,
      'created_at': createdAt.toIso8601String(),
      'executed_at': executedAt?.toIso8601String(),
      'executed_by_user_id': executedByUserId,
      'observations': observations,
    };
  }
}

enum TransferOrderStatus {
  pending,
  confirmed,
  cancelled,
  completed;

  String get displayName {
    switch (this) {
      case TransferOrderStatus.pending:
        return 'Pendiente';
      case TransferOrderStatus.confirmed:
        return 'Confirmado';
      case TransferOrderStatus.cancelled:
        return 'Cancelado';
      case TransferOrderStatus.completed:
        return 'Completado';
    }
  }

  
}

enum TransferOperationType {
  global, // Operación global de transferencia
  extraction, // Extracción de zona origen
  entry; // Entrada en zona destino

  String get displayName {
    switch (this) {
      case TransferOperationType.global:
        return 'Transferencia Global';
      case TransferOperationType.extraction:
        return 'Extracción';
      case TransferOperationType.entry:
        return 'Entrada';
    }
  }

  
}

enum TransferOperationStatus {
  pending,
  executed,
  failed;

  String get displayName {
    switch (this) {
      case TransferOperationStatus.pending:
        return 'Pendiente';
      case TransferOperationStatus.executed:
        return 'Ejecutado';
      case TransferOperationStatus.failed:
        return 'Fallido';
    }
  }

  
}

class ProductVariantPresentation {
  final String productId;
  final String productName;
  final String? productSku;
  final String? variantId;
  final String? variantName;
  final String? presentationId;
  final String? presentationName;
  final double availableStock;
  final String? imageUrl;

  ProductVariantPresentation({
    required this.productId,
    required this.productName,
    this.productSku,
    this.variantId,
    this.variantName,
    this.presentationId,
    this.presentationName,
    required this.availableStock,
    this.imageUrl,
  });

  factory ProductVariantPresentation.fromJson(Map<String, dynamic> json) {
    return ProductVariantPresentation(
      productId: json['product_id'] ?? json['productId'] ?? '',
      productName:
          json['product_name'] ??
          json['productName'] ??
          json['denominacion'] ??
          '',
      productSku: json['product_sku'] ?? json['productSku'] ?? json['sku'],
      variantId: json['variant_id'] ?? json['variantId'],
      variantName: json['variant_name'] ?? json['variantName'],
      presentationId: json['presentation_id'] ?? json['presentationId'],
      presentationName: json['presentation_name'] ?? json['presentationName'],
      availableStock:
          (json['available_stock'] ??
                  json['availableStock'] ??
                  json['stock'] ??
                  0)
              .toDouble(),
      imageUrl: json['image_url'] ?? json['imageUrl'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      'product_name': productName,
      'product_sku': productSku,
      'variant_id': variantId,
      'variant_name': variantName,
      'presentation_id': presentationId,
      'presentation_name': presentationName,
      'available_stock': availableStock,
      'image_url': imageUrl,
    };
  }

  String get displayName {
    List<String> parts = [productName];
    if (variantName != null && variantName!.isNotEmpty) {
      parts.add(variantName!);
    }
    if (presentationName != null && presentationName!.isNotEmpty) {
      parts.add(presentationName!);
    }
    return parts.join(' - ');
  }

  String get uniqueKey {
    return '${productId}_${variantId ?? 'no_variant'}_${presentationId ?? 'no_presentation'}';
  }
}
