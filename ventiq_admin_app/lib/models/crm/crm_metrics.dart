/// Modelo atómico para métricas CRM integradas
class CRMMetrics {
  // Métricas de Clientes
  final int totalCustomers;
  final int activeCustomers;
  final int vipCustomers;
  final double averageCustomerValue;
  final int loyaltyPoints;

  // Métricas de Proveedores
  final int totalSuppliers;
  final int activeSuppliers;
  final double averageLeadTime;
  final double totalPurchaseValue;
  final int uniqueProducts;

  // Métricas Integradas
  final double relationshipScore;
  final int totalContacts;
  final int recentInteractions;

  const CRMMetrics({
    // Clientes
    this.totalCustomers = 0,
    this.activeCustomers = 0,
    this.vipCustomers = 0,
    this.averageCustomerValue = 0.0,
    this.loyaltyPoints = 0,
    
    // Proveedores
    this.totalSuppliers = 0,
    this.activeSuppliers = 0,
    this.averageLeadTime = 0.0,
    this.totalPurchaseValue = 0.0,
    this.uniqueProducts = 0,
    
    // Integradas
    this.relationshipScore = 0.0,
    this.totalContacts = 0,
    this.recentInteractions = 0,
  });

  /// Calcula el total de contactos (clientes + proveedores)
  int get totalContactsCalculated => totalCustomers + totalSuppliers;

  /// Calcula el porcentaje de contactos activos
  double get activeContactsPercentage {
    final totalActive = activeCustomers + activeSuppliers;
    final total = totalContactsCalculated;
    return total > 0 ? (totalActive / total) * 100 : 0.0;
  }

  /// Calcula el score de diversificación de proveedores
  double get supplierDiversificationScore {
    if (totalSuppliers == 0) return 0.0;
    return (uniqueProducts / totalSuppliers).clamp(0.0, 10.0);
  }

  /// Calcula el score de fidelización de clientes
  double get customerLoyaltyScore {
    if (totalCustomers == 0) return 0.0;
    final vipPercentage = (vipCustomers / totalCustomers) * 100;
    return vipPercentage.clamp(0.0, 100.0);
  }

  /// Crea una instancia desde JSON
  factory CRMMetrics.fromJson(Map<String, dynamic> json) {
    return CRMMetrics(
      totalCustomers: json['total_customers'] ?? 0,
      activeCustomers: json['active_customers'] ?? 0,
      vipCustomers: json['vip_customers'] ?? 0,
      averageCustomerValue: (json['average_customer_value'] ?? 0.0).toDouble(),
      loyaltyPoints: json['loyalty_points'] ?? 0,
      
      totalSuppliers: json['total_suppliers'] ?? 0,
      activeSuppliers: json['active_suppliers'] ?? 0,
      averageLeadTime: (json['average_lead_time'] ?? 0.0).toDouble(),
      totalPurchaseValue: (json['total_purchase_value'] ?? 0.0).toDouble(),
      uniqueProducts: json['unique_products'] ?? 0,
      
      relationshipScore: (json['relationship_score'] ?? 0.0).toDouble(),
      totalContacts: json['total_contacts'] ?? 0,
      recentInteractions: json['recent_interactions'] ?? 0,
    );
  }

  /// Convierte a JSON
  Map<String, dynamic> toJson() {
    return {
      'total_customers': totalCustomers,
      'active_customers': activeCustomers,
      'vip_customers': vipCustomers,
      'average_customer_value': averageCustomerValue,
      'loyalty_points': loyaltyPoints,
      
      'total_suppliers': totalSuppliers,
      'active_suppliers': activeSuppliers,
      'average_lead_time': averageLeadTime,
      'total_purchase_value': totalPurchaseValue,
      'unique_products': uniqueProducts,
      
      'relationship_score': relationshipScore,
      'total_contacts': totalContacts,
      'recent_interactions': recentInteractions,
    };
  }

  /// Crea una copia con valores actualizados
  CRMMetrics copyWith({
    int? totalCustomers,
    int? activeCustomers,
    int? vipCustomers,
    double? averageCustomerValue,
    int? loyaltyPoints,
    int? totalSuppliers,
    int? activeSuppliers,
    double? averageLeadTime,
    double? totalPurchaseValue,
    int? uniqueProducts,
    double? relationshipScore,
    int? totalContacts,
    int? recentInteractions,
  }) {
    return CRMMetrics(
      totalCustomers: totalCustomers ?? this.totalCustomers,
      activeCustomers: activeCustomers ?? this.activeCustomers,
      vipCustomers: vipCustomers ?? this.vipCustomers,
      averageCustomerValue: averageCustomerValue ?? this.averageCustomerValue,
      loyaltyPoints: loyaltyPoints ?? this.loyaltyPoints,
      
      totalSuppliers: totalSuppliers ?? this.totalSuppliers,
      activeSuppliers: activeSuppliers ?? this.activeSuppliers,
      averageLeadTime: averageLeadTime ?? this.averageLeadTime,
      totalPurchaseValue: totalPurchaseValue ?? this.totalPurchaseValue,
      uniqueProducts: uniqueProducts ?? this.uniqueProducts,
      
      relationshipScore: relationshipScore ?? this.relationshipScore,
      totalContacts: totalContacts ?? this.totalContacts,
      recentInteractions: recentInteractions ?? this.recentInteractions,
    );
  }

  @override
  String toString() {
    return 'CRMMetrics(customers: $totalCustomers, suppliers: $totalSuppliers, score: $relationshipScore)';
  }
}
