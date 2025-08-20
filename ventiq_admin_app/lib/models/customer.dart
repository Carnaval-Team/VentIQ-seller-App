class Customer {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String address;
  final String city;
  final String country;
  final String segment; // premium, regular, nuevo
  final int loyaltyPoints;
  final String loyaltyLevel; // bronce, plata, oro, platino
  final double totalPurchases;
  final int totalOrders;
  final DateTime lastPurchase;
  final DateTime registrationDate;
  final bool isActive;
  final List<String> preferences;

  Customer({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.address,
    required this.city,
    required this.country,
    required this.segment,
    required this.loyaltyPoints,
    required this.loyaltyLevel,
    required this.totalPurchases,
    required this.totalOrders,
    required this.lastPurchase,
    required this.registrationDate,
    this.isActive = true,
    this.preferences = const [],
  });

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'] ?? '',
      address: json['address'] ?? '',
      city: json['city'] ?? '',
      country: json['country'] ?? '',
      segment: json['segment'] ?? 'nuevo',
      loyaltyPoints: json['loyaltyPoints'] ?? 0,
      loyaltyLevel: json['loyaltyLevel'] ?? 'bronce',
      totalPurchases: (json['totalPurchases'] ?? 0.0).toDouble(),
      totalOrders: json['totalOrders'] ?? 0,
      lastPurchase: DateTime.parse(json['lastPurchase'] ?? DateTime.now().toIso8601String()),
      registrationDate: DateTime.parse(json['registrationDate'] ?? DateTime.now().toIso8601String()),
      isActive: json['isActive'] ?? true,
      preferences: List<String>.from(json['preferences'] ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'address': address,
      'city': city,
      'country': country,
      'segment': segment,
      'loyaltyPoints': loyaltyPoints,
      'loyaltyLevel': loyaltyLevel,
      'totalPurchases': totalPurchases,
      'totalOrders': totalOrders,
      'lastPurchase': lastPurchase.toIso8601String(),
      'registrationDate': registrationDate.toIso8601String(),
      'isActive': isActive,
      'preferences': preferences,
    };
  }
}

class CustomerPurchaseHistory {
  final String id;
  final String customerId;
  final String orderId;
  final DateTime purchaseDate;
  final double amount;
  final String paymentMethod;
  final List<String> products;
  final String status;

  CustomerPurchaseHistory({
    required this.id,
    required this.customerId,
    required this.orderId,
    required this.purchaseDate,
    required this.amount,
    required this.paymentMethod,
    required this.products,
    required this.status,
  });

  factory CustomerPurchaseHistory.fromJson(Map<String, dynamic> json) {
    return CustomerPurchaseHistory(
      id: json['id'] ?? '',
      customerId: json['customerId'] ?? '',
      orderId: json['orderId'] ?? '',
      purchaseDate: DateTime.parse(json['purchaseDate'] ?? DateTime.now().toIso8601String()),
      amount: (json['amount'] ?? 0.0).toDouble(),
      paymentMethod: json['paymentMethod'] ?? '',
      products: List<String>.from(json['products'] ?? []),
      status: json['status'] ?? '',
    );
  }
}
