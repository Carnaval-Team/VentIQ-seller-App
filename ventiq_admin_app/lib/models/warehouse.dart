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
  // Supabase specific fields
  final String denominacion;
  final String direccion;
  final String? ubicacion;
  final WarehouseStore? tienda;
  final List<String> roles;
  final List<WarehouseLayout> layouts;
  final List<WarehouseCondition> condiciones;
  final int almacenerosCount;
  final int limitesStockCount;

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
    // Supabase specific fields
    required this.denominacion,
    required this.direccion,
    this.ubicacion,
    this.tienda,
    this.roles = const [],
    this.layouts = const [],
    this.condiciones = const [],
    this.almacenerosCount = 0,
    this.limitesStockCount = 0,
  });

  factory Warehouse.fromJson(Map<String, dynamic> json) {
    // Parse layouts first
    final layouts = (json['layouts'] as List<dynamic>?)
        ?.map((l) => WarehouseLayout.fromJson(l))
        .toList() ?? [];
    
    // Convert layouts to zones for UI compatibility
    final zones = layouts.map((layout) => WarehouseZone(
      id: layout.id,
      warehouseId: json['id']?.toString() ?? '',
      name: layout.denominacion,
      code: layout.skuCodigo ?? '',
      type: layout.tipoLayout,
      conditions: '',
      capacity: 1000,
      currentOccupancy: 0,
      locations: [],
    )).toList();
    
    return Warehouse(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? json['denominacion'] ?? '',
      description: json['description'] ?? '',
      address: json['address'] ?? json['direccion'] ?? '',
      city: json['city'] ?? '',
      country: json['country'] ?? 'Chile',
      latitude: json['latitude']?.toDouble(),
      longitude: json['longitude']?.toDouble(),
      type: json['type'] ?? 'principal',
      isActive: json['isActive'] ?? true,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'])
          : DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      zones: zones, // Use converted zones from layouts
      // Supabase specific fields
      denominacion: json['denominacion'] ?? '',
      direccion: json['direccion'] ?? '',
      ubicacion: json['ubicacion'],
      tienda: json['tienda'] != null ? WarehouseStore.fromJson(json['tienda']) : null,
      roles: (json['roles'] as List<dynamic>?)?.map((r) => r.toString()).toList() ?? [],
      layouts: layouts,
      condiciones: (json['condiciones'] as List<dynamic>?)
          ?.map((c) => WarehouseCondition.fromJson(c))
          .toList() ?? [],
      almacenerosCount: json['almaceneros_count'] ?? 0,
      limitesStockCount: json['limites_stock_count'] ?? 0,
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
      // Supabase specific fields
      'denominacion': denominacion,
      'direccion': direccion,
      'ubicacion': ubicacion,
      'tienda': tienda?.toJson(),
      'roles': roles,
      'layouts': layouts.map((l) => l.toJson()).toList(),
      'condiciones': condiciones.map((c) => c.toJson()).toList(),
      'almaceneros_count': almacenerosCount,
      'limites_stock_count': limitesStockCount,
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
  final String? abc; // 'A', 'B', 'C'
  final List<String> conditionCodes; // e.g., ['refrigerado','fragil','peligroso']
  final int productCount; // productos ubicados en esta zona
  final double utilization; // 0.0 - 1.0 (ocupación)
  final String? parentId; // layout padre (opcional)

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
    this.abc,
    this.conditionCodes = const [],
    this.productCount = 0,
    this.utilization = 0.0,
    this.parentId,
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
      abc: json['abc'],
      conditionCodes: List<String>.from(json['conditionCodes'] ?? []),
      productCount: json['productCount'] ?? 0,
      utilization: (json['utilization'] ?? 0.0).toDouble(),
      parentId: json['parentId'],
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
      'abc': abc,
      'conditionCodes': conditionCodes,
      'productCount': productCount,
      'utilization': utilization,
      'parentId': parentId,
    };
  }
}

class WarehouseStore {
  final String id;
  final String denominacion;
  final String direccion;

  WarehouseStore({
    required this.id,
    required this.denominacion,
    required this.direccion,
  });

  factory WarehouseStore.fromJson(Map<String, dynamic> json) {
    return WarehouseStore(
      id: json['id']?.toString() ?? '',
      denominacion: json['denominacion'] ?? '',
      direccion: json['direccion'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'denominacion': denominacion,
      'direccion': direccion,
    };
  }
}

class WarehouseLayout {
  final String id;
  final String denominacion;
  final String tipoLayout;
  final String? skuCodigo;

  WarehouseLayout({
    required this.id,
    required this.denominacion,
    required this.tipoLayout,
    this.skuCodigo,
  });

  factory WarehouseLayout.fromJson(Map<String, dynamic> json) {
    return WarehouseLayout(
      id: json['id']?.toString() ?? '',
      denominacion: json['denominacion'] ?? '',
      tipoLayout: json['tipo_layout'] ?? '',
      skuCodigo: json['sku_codigo'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'denominacion': denominacion,
      'tipo_layout': tipoLayout,
      'sku_codigo': skuCodigo,
    };
  }
}

class WarehouseCondition {
  final String id;
  final String denominacion;

  WarehouseCondition({
    required this.id,
    required this.denominacion,
  });

  factory WarehouseCondition.fromJson(Map<String, dynamic> json) {
    return WarehouseCondition(
      id: json['id']?.toString() ?? '',
      denominacion: json['denominacion'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'denominacion': denominacion,
    };
  }
}

class WarehousePaginationResponse {
  final List<Warehouse> almacenes;
  final WarehousePagination paginacion;

  WarehousePaginationResponse({
    required this.almacenes,
    required this.paginacion,
  });

  factory WarehousePaginationResponse.fromJson(Map<String, dynamic> json) {
    return WarehousePaginationResponse(
      almacenes: (json['almacenes'] as List<dynamic>)
          .map((w) => Warehouse.fromJson(w))
          .toList(),
      paginacion: WarehousePagination.fromJson(json['paginacion']),
    );
  }
}

class WarehousePagination {
  final int paginaActual;
  final int porPagina;
  final int totalAlmacenes;
  final int totalPaginas;
  final bool tieneAnterior;
  final bool tieneSiguiente;

  WarehousePagination({
    required this.paginaActual,
    required this.porPagina,
    required this.totalAlmacenes,
    required this.totalPaginas,
    required this.tieneAnterior,
    required this.tieneSiguiente,
  });

  factory WarehousePagination.fromJson(Map<String, dynamic> json) {
    return WarehousePagination(
      paginaActual: json['pagina_actual'] ?? 1,
      porPagina: json['por_pagina'] ?? 10,
      totalAlmacenes: json['total_almacenes'] ?? 0,
      totalPaginas: json['total_paginas'] ?? 0,
      tieneAnterior: json['tiene_anterior'] ?? false,
      tieneSiguiente: json['tiene_siguiente'] ?? false,
    );
  }
}
