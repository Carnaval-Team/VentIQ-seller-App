class InventoryMetrics {
  final double totalValue;
  final int totalProducts;
  final int lowStockProducts;
  final int outOfStockProducts;
  final double averageRotation;
  final double monthlyMovement;
  final DateTime calculatedAt;

  // Métricas de tendencia
  final double valueChangePercent;
  final double rotationChangePercent;
  final double movementChangePercent;

  InventoryMetrics({
    required this.totalValue,
    required this.totalProducts,
    required this.lowStockProducts,
    required this.outOfStockProducts,
    required this.averageRotation,
    required this.monthlyMovement,
    required this.calculatedAt,
    this.valueChangePercent = 0.0,
    this.rotationChangePercent = 0.0,
    this.movementChangePercent = 0.0,
  });

  factory InventoryMetrics.fromJson(Map<String, dynamic> json) {
    return InventoryMetrics(
      totalValue: (json['totalValue'] ?? 0).toDouble(),
      totalProducts: json['totalProducts'] ?? 0,
      lowStockProducts: json['lowStockProducts'] ?? 0,
      outOfStockProducts: json['outOfStockProducts'] ?? 0,
      averageRotation: (json['averageRotation'] ?? 0).toDouble(),
      monthlyMovement: (json['monthlyMovement'] ?? 0).toDouble(),
      calculatedAt: DateTime.parse(
        json['calculated_at'] ?? DateTime.now().toIso8601String(),
      ),
      valueChangePercent: (json['value_change_percent'] ?? 0).toDouble(),
      rotationChangePercent: (json['rotation_change_percent'] ?? 0).toDouble(),
      movementChangePercent: (json['movement_change_percent'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total_value': totalValue,
      'total_products': totalProducts,
      'low_stock_products': lowStockProducts,
      'out_of_stock_products': outOfStockProducts,
      'average_rotation': averageRotation,
      'monthly_movement': monthlyMovement,
      'calculated_at': calculatedAt.toIso8601String(),
      'value_change_percent': valueChangePercent,
      'rotation_change_percent': rotationChangePercent,
      'movement_change_percent': movementChangePercent,
    };
  }

  // Getters para indicadores de salud
  String get stockHealthLevel {
    final outOfStockRatio =
        totalProducts > 0 ? outOfStockProducts / totalProducts : 0;
    if (outOfStockRatio > 0.2) return 'Crítico';
    if (outOfStockRatio > 0.1) return 'Alerta';
    if (outOfStockRatio > 0.05) return 'Precaución';
    return 'Saludable';
  }

  String get rotationLevel {
    if (averageRotation >= 12) return 'Excelente';
    if (averageRotation >= 6) return 'Buena';
    if (averageRotation >= 3) return 'Regular';
    return 'Lenta';
  }

  bool get hasPositiveTrend => valueChangePercent > 0;
  bool get hasGoodRotation => averageRotation >= 6;
  bool get hasStockIssues =>
      outOfStockProducts > 0 || lowStockProducts > totalProducts * 0.1;

  @override
  String toString() =>
      'InventoryMetrics(value: $totalValue, products: $totalProducts)';
}

class ProductMovementMetric {
  final int productId;
  final String productName;
  final String category;
  final double totalMovement;
  final double averageMovement;
  final int transactionCount;
  final double rotationRate;
  final DateTime lastMovement;
  final String movementTrend; // 'increasing', 'decreasing', 'stable'

  ProductMovementMetric({
    required this.productId,
    required this.productName,
    required this.category,
    required this.totalMovement,
    required this.averageMovement,
    required this.transactionCount,
    required this.rotationRate,
    required this.lastMovement,
    required this.movementTrend,
  });

  factory ProductMovementMetric.fromJson(Map<String, dynamic> json) {
    return ProductMovementMetric(
      productId: json['product_id'] ?? 0,
      productName: json['product_name'] ?? '',
      category: json['category'] ?? '',
      totalMovement: (json['total_movement'] ?? 0).toDouble(),
      averageMovement: (json['average_movement'] ?? 0).toDouble(),
      transactionCount: json['transaction_count'] ?? 0,
      rotationRate: (json['rotation_rate'] ?? 0).toDouble(),
      lastMovement: DateTime.parse(
        json['last_movement'] ?? DateTime.now().toIso8601String(),
      ),
      movementTrend: json['movement_trend'] ?? 'stable',
    );
  }

  String get rotationLabel {
    if (rotationRate >= 12) return 'Alta';
    if (rotationRate >= 6) return 'Media';
    if (rotationRate >= 3) return 'Baja';
    return 'Muy Baja';
  }

  String get trendLabel {
    switch (movementTrend) {
      case 'increasing':
        return 'Creciente';
      case 'decreasing':
        return 'Decreciente';
      default:
        return 'Estable';
    }
  }
}

class StockAlert {
  final int productId;
  final String productName;
  final String alertType; // 'out_of_stock', 'low_stock', 'overstock', 'expiring'
  final String severity; // 'critical', 'warning', 'info'
  final double currentStock;
  final double? minStock;
  final double? maxStock;
  final String message;
  final DateTime createdAt;
  final bool isActive;

  StockAlert({
    required this.productId,
    required this.productName,
    required this.alertType,
    required this.severity,
    required this.currentStock,
    this.minStock,
    this.maxStock,
    required this.message,
    required this.createdAt,
    this.isActive = true,
  });

  factory StockAlert.fromJson(Map<String, dynamic> json) {
    return StockAlert(
      productId: json['product_id'] ?? 0,
      productName: json['product_name'] ?? '',
      alertType: json['alert_type'] ?? '',
      severity: json['severity'] ?? 'info',
      currentStock: (json['current_stock'] ?? 0).toDouble(),
      minStock: json['min_stock']?.toDouble(),
      maxStock: json['max_stock']?.toDouble(),
      message: json['message'] ?? '',
      createdAt: DateTime.parse(
        json['created_at'] ?? DateTime.now().toIso8601String(),
      ),
      isActive: json['is_active'] ?? true,
    );
  }

  String get alertTypeLabel {
    switch (alertType) {
      case 'out_of_stock':
        return 'Sin Stock';
      case 'low_stock':
        return 'Stock Bajo';
      case 'overstock':
        return 'Sobrestock';
      case 'expiring':
        return 'Por Vencer';
      default:
        return 'Alerta';
    }
  }

  String get severityLabel {
    switch (severity) {
      case 'critical':
        return 'Crítico';
      case 'warning':
        return 'Advertencia';
      default:
        return 'Información';
    }
  }
}
