class Supplier {
  final int id;
  final String denominacion;
  final String? direccion;
  final String? ubicacion;
  final String skuCodigo;
  final int? leadTime; // días
  final DateTime createdAt;
  final bool isActive;
  
  // Campos calculados opcionales
  final double? averageLeadTime;
  final int? totalOrders;
  final double? averageOrderValue;
  final DateTime? lastOrderDate;
  
  Supplier({
    required this.id,
    required this.denominacion,
    this.direccion,
    this.ubicacion,
    required this.skuCodigo,
    this.leadTime,
    required this.createdAt,
    this.isActive = true,
    this.averageLeadTime,
    this.totalOrders,
    this.averageOrderValue,
    this.lastOrderDate,
  });
  
  factory Supplier.fromJson(Map<String, dynamic> json) {
    return Supplier(
      id: json['id'] ?? 0,
      denominacion: json['denominacion'] ?? '',
      direccion: json['direccion'],
      ubicacion: json['ubicacion'],
      skuCodigo: json['sku_codigo'] ?? '',
      leadTime: json['lead_time'],
      createdAt: DateTime.parse(
        json['created_at'] ?? DateTime.now().toIso8601String(),
      ),
      isActive: json['is_active'] ?? true,
      averageLeadTime: json['average_lead_time']?.toDouble(),
      totalOrders: json['total_orders'],
      averageOrderValue: json['average_order_value']?.toDouble(),
      lastOrderDate: json['last_order_date'] != null
          ? DateTime.parse(json['last_order_date'])
          : null,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'denominacion': denominacion,
      'direccion': direccion,
      'ubicacion': ubicacion,
      'sku_codigo': skuCodigo,
      'lead_time': leadTime,
      'created_at': createdAt.toIso8601String(),
      'is_active': isActive,
    };
  }
  
  Map<String, dynamic> toInsertJson() {
    return {
      'denominacion': denominacion,
      'direccion': direccion,
      'ubicacion': ubicacion,
      'sku_codigo': skuCodigo,
      'lead_time': leadTime,
    };
  }
  
  // Helper methods
  String get displayName => denominacion;
  
  String get fullAddress {
    final parts = <String>[];
    if (direccion != null && direccion!.isNotEmpty) parts.add(direccion!);
    if (ubicacion != null && ubicacion!.isNotEmpty) parts.add(ubicacion!);
    return parts.join(', ');
  }
  
  String get leadTimeDisplay {
    if (leadTime == null) return 'No especificado';
    if (leadTime == 1) return '1 día';
    return '$leadTime días';
  }
  
  bool get hasMetrics => totalOrders != null && totalOrders! > 0;
  
  String get performanceLevel {
    if (!hasMetrics) return 'Sin datos';
    if (totalOrders! >= 10) return 'Excelente';
    if (totalOrders! >= 5) return 'Bueno';
    return 'Regular';
  }
  
  @override
  String toString() => 'Supplier(id: $id, denominacion: $denominacion)';
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Supplier &&
          runtimeType == other.runtimeType &&
          id == other.id;
  
  @override
  int get hashCode => id.hashCode;
  
  // Copy with method for updates
  Supplier copyWith({
    int? id,
    String? denominacion,
    String? direccion,
    String? ubicacion,
    String? skuCodigo,
    int? leadTime,
    DateTime? createdAt,
    bool? isActive,
    double? averageLeadTime,
    int? totalOrders,
    double? averageOrderValue,
    DateTime? lastOrderDate,
  }) {
    return Supplier(
      id: id ?? this.id,
      denominacion: denominacion ?? this.denominacion,
      direccion: direccion ?? this.direccion,
      ubicacion: ubicacion ?? this.ubicacion,
      skuCodigo: skuCodigo ?? this.skuCodigo,
      leadTime: leadTime ?? this.leadTime,
      createdAt: createdAt ?? this.createdAt,
      isActive: isActive ?? this.isActive,
      averageLeadTime: averageLeadTime ?? this.averageLeadTime,
      totalOrders: totalOrders ?? this.totalOrders,
      averageOrderValue: averageOrderValue ?? this.averageOrderValue,
      lastOrderDate: lastOrderDate ?? this.lastOrderDate,
    );
  }
}
