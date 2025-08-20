class Warehouse {
  final String id;
  final String name;
  final String description;
  final String address;
  final String city;
  final String country;
  final double? latitude;
  final double? longitude;
  final String type; // principal, secundario, temporal
  final bool isActive;
  final DateTime createdAt;
  final List<WarehouseZone> zones;

  Warehouse({
    required this.id,
    required this.name,
    required this.description,
    required this.address,
    required this.city,
    required this.country,
    this.latitude,
    this.longitude,
    required this.type,
    this.isActive = true,
    required this.createdAt,
    this.zones = const [],
  });

  factory Warehouse.fromJson(Map<String, dynamic> json) {
    return Warehouse(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      address: json['address'] ?? '',
      city: json['city'] ?? '',
      country: json['country'] ?? '',
      latitude: json['latitude']?.toDouble(),
      longitude: json['longitude']?.toDouble(),
      type: json['type'] ?? 'principal',
      isActive: json['isActive'] ?? true,
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      zones: (json['zones'] as List<dynamic>?)
          ?.map((z) => WarehouseZone.fromJson(z))
          .toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'address': address,
      'city': city,
      'country': country,
      'latitude': latitude,
      'longitude': longitude,
      'type': type,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'zones': zones.map((z) => z.toJson()).toList(),
    };
  }
}

class WarehouseZone {
  final String id;
  final String warehouseId;
  final String name;
  final String code;
  final String type; // recepcion, almacenamiento, picking, expedicion
  final String conditions; // temperatura, humedad, etc.
  final int capacity;
  final int currentOccupancy;
  final List<String> locations;

  WarehouseZone({
    required this.id,
    required this.warehouseId,
    required this.name,
    required this.code,
    required this.type,
    required this.conditions,
    required this.capacity,
    required this.currentOccupancy,
    this.locations = const [],
  });

  factory WarehouseZone.fromJson(Map<String, dynamic> json) {
    return WarehouseZone(
      id: json['id'] ?? '',
      warehouseId: json['warehouseId'] ?? '',
      name: json['name'] ?? '',
      code: json['code'] ?? '',
      type: json['type'] ?? '',
      conditions: json['conditions'] ?? '',
      capacity: json['capacity'] ?? 0,
      currentOccupancy: json['currentOccupancy'] ?? 0,
      locations: List<String>.from(json['locations'] ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'warehouseId': warehouseId,
      'name': name,
      'code': code,
      'type': type,
      'conditions': conditions,
      'capacity': capacity,
      'currentOccupancy': currentOccupancy,
      'locations': locations,
    };
  }
}
