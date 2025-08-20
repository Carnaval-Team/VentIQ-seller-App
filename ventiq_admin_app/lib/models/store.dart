class Store {
  final String id;
  final String name;
  final String address;
  final String phone;
  final String email;
  final String manager;
  final bool isActive;
  final String timezone;
  final Map<String, String> businessHours;
  final double latitude;
  final double longitude;
  final String currency;
  final String taxId;
  final DateTime createdAt;
  final DateTime? lastUpdated;

  Store({
    required this.id,
    required this.name,
    required this.address,
    required this.phone,
    required this.email,
    required this.manager,
    this.isActive = true,
    required this.timezone,
    required this.businessHours,
    required this.latitude,
    required this.longitude,
    required this.currency,
    required this.taxId,
    required this.createdAt,
    this.lastUpdated,
  });

  factory Store.fromJson(Map<String, dynamic> json) {
    return Store(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      address: json['address'] ?? '',
      phone: json['phone'] ?? '',
      email: json['email'] ?? '',
      manager: json['manager'] ?? '',
      isActive: json['isActive'] ?? true,
      timezone: json['timezone'] ?? 'America/Santiago',
      businessHours: Map<String, String>.from(json['businessHours'] ?? {}),
      latitude: (json['latitude'] ?? 0.0).toDouble(),
      longitude: (json['longitude'] ?? 0.0).toDouble(),
      currency: json['currency'] ?? 'CLP',
      taxId: json['taxId'] ?? '',
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      lastUpdated: json['lastUpdated'] != null ? DateTime.parse(json['lastUpdated']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'phone': phone,
      'email': email,
      'manager': manager,
      'isActive': isActive,
      'timezone': timezone,
      'businessHours': businessHours,
      'latitude': latitude,
      'longitude': longitude,
      'currency': currency,
      'taxId': taxId,
      'createdAt': createdAt.toIso8601String(),
      'lastUpdated': lastUpdated?.toIso8601String(),
    };
  }

  Store copyWith({
    String? id,
    String? name,
    String? address,
    String? phone,
    String? email,
    String? manager,
    bool? isActive,
    String? timezone,
    Map<String, String>? businessHours,
    double? latitude,
    double? longitude,
    String? currency,
    String? taxId,
    DateTime? createdAt,
    DateTime? lastUpdated,
  }) {
    return Store(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      manager: manager ?? this.manager,
      isActive: isActive ?? this.isActive,
      timezone: timezone ?? this.timezone,
      businessHours: businessHours ?? this.businessHours,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      currency: currency ?? this.currency,
      taxId: taxId ?? this.taxId,
      createdAt: createdAt ?? this.createdAt,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}
