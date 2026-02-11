class StoreAiUserDraft {
  final String? fullName;
  final String? phone;
  final String? email;
  final String? password;

  const StoreAiUserDraft({
    this.fullName,
    this.phone,
    this.email,
    this.password,
  });

  factory StoreAiUserDraft.fromJson(Map<String, dynamic> json) {
    return StoreAiUserDraft(
      fullName: json['full_name']?.toString(),
      phone: json['phone']?.toString(),
      email: json['email']?.toString(),
      password: json['password']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'full_name': fullName,
      'phone': phone,
      'email': email,
      'password': password,
    };
  }
}

class StoreAiLocationDraft {
  final String? countryCode;
  final String? countryName;
  final String? stateCode;
  final String? stateName;
  final String? city;
  final double? latitude;
  final double? longitude;

  const StoreAiLocationDraft({
    this.countryCode,
    this.countryName,
    this.stateCode,
    this.stateName,
    this.city,
    this.latitude,
    this.longitude,
  });

  factory StoreAiLocationDraft.fromJson(Map<String, dynamic> json) {
    final legacyCountry = json['country']?.toString();
    final legacyState = json['state']?.toString();
    return StoreAiLocationDraft(
      countryCode: json['country_code']?.toString() ?? legacyCountry,
      countryName: json['country_name']?.toString() ?? legacyCountry,
      stateCode: json['state_code']?.toString() ?? legacyState,
      stateName: json['state_name']?.toString() ?? legacyState,
      city: json['city']?.toString(),
      latitude:
          json['latitude'] is num ? (json['latitude'] as num).toDouble() : null,
      longitude:
          json['longitude'] is num
              ? (json['longitude'] as num).toDouble()
              : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'country_code': countryCode,
      'country_name': countryName,
      'state_code': stateCode,
      'state_name': stateName,
      'city': city,
      'latitude': latitude,
      'longitude': longitude,
    };
  }
}

class StoreAiWarehouseDraft {
  final String? name;
  final String? address;
  final String? location;

  const StoreAiWarehouseDraft({this.name, this.address, this.location});

  factory StoreAiWarehouseDraft.fromJson(Map<String, dynamic> json) {
    return StoreAiWarehouseDraft(
      name: json['name']?.toString(),
      address: json['address']?.toString(),
      location: json['location']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'name': name, 'address': address, 'location': location};
  }
}

class StoreAiLayoutDraft {
  final String? name;
  final String? code;
  final String? warehouseName;
  final int? tipoLayoutId;

  const StoreAiLayoutDraft({
    this.name,
    this.code,
    this.warehouseName,
    this.tipoLayoutId,
  });

  factory StoreAiLayoutDraft.fromJson(Map<String, dynamic> json) {
    return StoreAiLayoutDraft(
      name: json['name']?.toString(),
      code: json['code']?.toString(),
      warehouseName: json['warehouse_name']?.toString(),
      tipoLayoutId:
          json['tipo_layout_id'] is int ? json['tipo_layout_id'] as int : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'code': code,
      'warehouse_name': warehouseName,
      'tipo_layout_id': tipoLayoutId,
    };
  }
}

class StoreAiTpvDraft {
  final String? name;
  final String? warehouseName;

  const StoreAiTpvDraft({this.name, this.warehouseName});

  factory StoreAiTpvDraft.fromJson(Map<String, dynamic> json) {
    return StoreAiTpvDraft(
      name: json['name']?.toString(),
      warehouseName: json['warehouse_name']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'name': name, 'warehouse_name': warehouseName};
  }
}

class StoreAiPlan {
  final StoreAiUserDraft user;
  final String? storeName;
  final String? storeAddress;
  final StoreAiLocationDraft location;
  final List<StoreAiWarehouseDraft> warehouses;
  final List<StoreAiLayoutDraft> layouts;
  final List<StoreAiTpvDraft> tpvs;

  const StoreAiPlan({
    required this.user,
    required this.storeName,
    required this.storeAddress,
    required this.location,
    required this.warehouses,
    required this.layouts,
    required this.tpvs,
  });

  factory StoreAiPlan.empty() {
    return StoreAiPlan(
      user: const StoreAiUserDraft(),
      storeName: null,
      storeAddress: null,
      location: const StoreAiLocationDraft(),
      warehouses: const [],
      layouts: const [],
      tpvs: const [],
    );
  }

  factory StoreAiPlan.fromJson(Map<String, dynamic> json) {
    final user =
        json['user'] is Map<String, dynamic>
            ? StoreAiUserDraft.fromJson(json['user'] as Map<String, dynamic>)
            : const StoreAiUserDraft();
    final location =
        json['location'] is Map<String, dynamic>
            ? StoreAiLocationDraft.fromJson(
              json['location'] as Map<String, dynamic>,
            )
            : const StoreAiLocationDraft();

    final warehousesRaw = json['warehouses'];
    final layoutsRaw = json['layouts'];
    final tpvsRaw = json['tpvs'];

    return StoreAiPlan(
      user: user,
      storeName: json['store_name']?.toString(),
      storeAddress: json['store_address']?.toString(),
      location: location,
      warehouses:
          warehousesRaw is List
              ? warehousesRaw
                  .whereType<Map>()
                  .map(
                    (e) => StoreAiWarehouseDraft.fromJson(
                      Map<String, dynamic>.from(e),
                    ),
                  )
                  .toList()
              : const [],
      layouts:
          layoutsRaw is List
              ? layoutsRaw
                  .whereType<Map>()
                  .map(
                    (e) => StoreAiLayoutDraft.fromJson(
                      Map<String, dynamic>.from(e),
                    ),
                  )
                  .toList()
              : const [],
      tpvs:
          tpvsRaw is List
              ? tpvsRaw
                  .whereType<Map>()
                  .map(
                    (e) =>
                        StoreAiTpvDraft.fromJson(Map<String, dynamic>.from(e)),
                  )
                  .toList()
              : const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user': user.toJson(),
      'store_name': storeName,
      'store_address': storeAddress,
      'location': location.toJson(),
      'warehouses': warehouses.map((e) => e.toJson()).toList(),
      'layouts': layouts.map((e) => e.toJson()).toList(),
      'tpvs': tpvs.map((e) => e.toJson()).toList(),
    };
  }

  int get warehousesCount => warehouses.length;
  int get layoutsCount => layouts.length;
  int get tpvsCount => tpvs.length;
}
