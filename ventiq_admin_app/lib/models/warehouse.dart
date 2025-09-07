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
  final List<WarehouseStockLimit> stockLimits;
  final List<WarehouseWorker> workers;

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
    this.stockLimits = const [],
    this.workers = const [],
  });

  factory Warehouse.fromJson(Map<String, dynamic> json) {
    // Parse layouts first
    final layouts =
        (json['layouts'] as List<dynamic>?)
            ?.map((l) => WarehouseLayout.fromJson(l))
            .toList() ??
        [];

    // Convert layouts to zones for UI compatibility
    final zones =
        layouts
            .map(
              (layout) => WarehouseZone(
                id: layout.id,
                warehouseId: json['id']?.toString() ?? '',
                name: layout.denominacion,
                code: layout.skuCodigo ?? '',
                type: layout.tipoLayout,
                conditions:
                    layout.condiciones.isNotEmpty
                        ? layout.condiciones
                            .map((c) => c.condicion?.denominacion ?? '')
                            .join(', ')
                        : '',
                capacity: 1000,
                currentOccupancy: 0,
                locations: [],
                parentId: layout.idLayoutPadre, // Map parent relationship
                abc: layout.abcClassification?.abcLetter,
                conditionCodes:
                    layout.condiciones
                        .map((c) => c.condicion?.denominacion ?? '')
                        .where((name) => name.isNotEmpty)
                        .toList(),
              ),
            )
            .toList();

    final stockLimits =
        (json['stock_limits'] as List<dynamic>?)
            ?.map((l) => WarehouseStockLimit.fromJson(l))
            .toList() ??
        [];

    final workers =
        (json['workers'] as List<dynamic>?)
            ?.map((w) => WarehouseWorker.fromJson(w))
            .toList() ??
        [];

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
      createdAt:
          json['created_at'] != null
              ? DateTime.parse(json['created_at'])
              : DateTime.parse(
                json['createdAt'] ?? DateTime.now().toIso8601String(),
              ),
      zones: zones, // Use converted zones from layouts
      // Supabase specific fields
      denominacion: json['denominacion'] ?? '',
      direccion: json['direccion'] ?? '',
      ubicacion: json['ubicacion'],
      tienda:
          json['tienda'] != null
              ? WarehouseStore.fromJson(json['tienda'])
              : null,
      roles:
          (json['roles'] as List<dynamic>?)
              ?.map((r) => r.toString())
              .toList() ??
          [],
      layouts: layouts,
      condiciones:
          (json['condiciones'] as List<dynamic>?)
              ?.map((c) => WarehouseCondition.fromJson(c))
              .toList() ??
          [],
      almacenerosCount: json['almaceneros_count'] ?? 0,
      limitesStockCount: json['limites_stock_count'] ?? 0,
      stockLimits: stockLimits,
      workers: workers,
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
      'stock_limits': stockLimits.map((l) => l.toJson()).toList(),
      'workers': workers.map((w) => w.toJson()).toList(),
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
  final List<String>
  conditionCodes; // e.g., ['refrigerado','fragil','peligroso']
  final int productCount; // productos ubicados en esta zona
  final double utilization; // 0.0 - 1.0 (ocupación)
  final String? parentId; // layout padre (opcional)

  // Getter for display name combining name and code
  String get displayName => code.isNotEmpty ? '$name ($code)' : name;

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
    return {'id': id, 'denominacion': denominacion, 'direccion': direccion};
  }
}

class WarehouseLayout {
  final String id;
  final String denominacion;
  final String tipoLayout;
  final String? skuCodigo;
  final String? idLayoutPadre;
  final String idAlmacen;
  final DateTime createdAt;
  final List<WarehouseLayoutCondition> condiciones;
  final WarehouseLayoutABC? abcClassification;

  WarehouseLayout({
    required this.id,
    required this.denominacion,
    required this.tipoLayout,
    this.skuCodigo,
    this.idLayoutPadre,
    required this.idAlmacen,
    required this.createdAt,
    this.condiciones = const [],
    this.abcClassification,
  });

  factory WarehouseLayout.fromJson(Map<String, dynamic> json) {
    return WarehouseLayout(
      id: json['id']?.toString() ?? '',
      denominacion: json['denominacion'] ?? '',
      tipoLayout: json['tipo_layout'] ?? '',
      skuCodigo: json['sku_codigo'],
      idLayoutPadre: json['id_layout_padre']?.toString(),
      idAlmacen: json['id_almacen']?.toString() ?? '',
      createdAt:
          json['created_at'] != null
              ? DateTime.parse(json['created_at'])
              : DateTime.now(),
      condiciones:
          (json['condiciones'] as List<dynamic>?)
              ?.map((c) => WarehouseLayoutCondition.fromJson(c))
              .toList() ??
          [],
      abcClassification:
          json['abc_classification'] != null
              ? WarehouseLayoutABC.fromJson(json['abc_classification'])
              : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'denominacion': denominacion,
      'tipo_layout': tipoLayout,
      'sku_codigo': skuCodigo,
      'id_layout_padre': idLayoutPadre,
      'id_almacen': idAlmacen,
      'created_at': createdAt.toIso8601String(),
      'condiciones': condiciones.map((c) => c.toJson()).toList(),
      'abc_classification': abcClassification?.toJson(),
    };
  }
}

class WarehouseLayoutCondition {
  final String id;
  final String idLayout;
  final String idCondicion;
  final DateTime createdAt;
  final WarehouseCondition? condicion;

  WarehouseLayoutCondition({
    required this.id,
    required this.idLayout,
    required this.idCondicion,
    required this.createdAt,
    this.condicion,
  });

  factory WarehouseLayoutCondition.fromJson(Map<String, dynamic> json) {
    return WarehouseLayoutCondition(
      id: json['id']?.toString() ?? '',
      idLayout: json['id_layout']?.toString() ?? '',
      idCondicion: json['id_condicion']?.toString() ?? '',
      createdAt:
          json['created_at'] != null
              ? DateTime.parse(json['created_at'])
              : DateTime.now(),
      condicion:
          json['condicion'] != null
              ? WarehouseCondition.fromJson(json['condicion'])
              : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'id_layout': idLayout,
      'id_condicion': idCondicion,
      'created_at': createdAt.toIso8601String(),
      'condicion': condicion?.toJson(),
    };
  }
}

class WarehouseLayoutABC {
  final String id;
  final String idLayout;
  final int clasificacionAbc; // 1=A, 2=B, 3=C
  final DateTime fechaDesde;
  final DateTime? fechaHasta;
  final DateTime createdAt;

  WarehouseLayoutABC({
    required this.id,
    required this.idLayout,
    required this.clasificacionAbc,
    required this.fechaDesde,
    this.fechaHasta,
    required this.createdAt,
  });

  String get abcLetter {
    switch (clasificacionAbc) {
      case 1:
        return 'A';
      case 2:
        return 'B';
      case 3:
        return 'C';
      default:
        return 'C';
    }
  }

  factory WarehouseLayoutABC.fromJson(Map<String, dynamic> json) {
    return WarehouseLayoutABC(
      id: json['id']?.toString() ?? '',
      idLayout: json['id_layout']?.toString() ?? '',
      clasificacionAbc: json['clasificacion_abc'] ?? 3,
      fechaDesde:
          json['fecha_desde'] != null
              ? DateTime.parse(json['fecha_desde'])
              : DateTime.now(),
      fechaHasta:
          json['fecha_hasta'] != null
              ? DateTime.parse(json['fecha_hasta'])
              : null,
      createdAt:
          json['created_at'] != null
              ? DateTime.parse(json['created_at'])
              : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'id_layout': idLayout,
      'clasificacion_abc': clasificacionAbc,
      'fecha_desde': fechaDesde.toIso8601String().split('T')[0],
      'fecha_hasta': fechaHasta?.toIso8601String().split('T')[0],
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class WarehouseCondition {
  final String id;
  final String denominacion;
  final String? descripcion;
  final bool esRefrigerado;
  final bool esFragil;
  final bool esPeligroso;
  final DateTime createdAt;

  WarehouseCondition({
    required this.id,
    required this.denominacion,
    this.descripcion,
    this.esRefrigerado = false,
    this.esFragil = false,
    this.esPeligroso = false,
    required this.createdAt,
  });

  factory WarehouseCondition.fromJson(Map<String, dynamic> json) {
    return WarehouseCondition(
      id: json['id']?.toString() ?? '',
      denominacion: json['denominacion'] ?? '',
      descripcion: json['descripcion'],
      esRefrigerado: json['es_refrigerado'] ?? false,
      esFragil: json['es_fragil'] ?? false,
      esPeligroso: json['es_peligroso'] ?? false,
      createdAt:
          json['created_at'] != null
              ? DateTime.parse(json['created_at'])
              : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'denominacion': denominacion,
      'descripcion': descripcion,
      'es_refrigerado': esRefrigerado,
      'es_fragil': esFragil,
      'es_peligroso': esPeligroso,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class WarehouseStockLimit {
  final String id;
  final String idProducto;
  final String idAlmacen;
  final double? stockMin;
  final double? stockMax;
  final double? stockOrdenar;
  final DateTime createdAt;

  WarehouseStockLimit({
    required this.id,
    required this.idProducto,
    required this.idAlmacen,
    this.stockMin,
    this.stockMax,
    this.stockOrdenar,
    required this.createdAt,
  });

  factory WarehouseStockLimit.fromJson(Map<String, dynamic> json) {
    return WarehouseStockLimit(
      id: json['id']?.toString() ?? '',
      idProducto: json['id_producto']?.toString() ?? '',
      idAlmacen: json['id_almacen']?.toString() ?? '',
      stockMin: json['stock_min']?.toDouble(),
      stockMax: json['stock_max']?.toDouble(),
      stockOrdenar: json['stock_ordenar']?.toDouble(),
      createdAt:
          json['created_at'] != null
              ? DateTime.parse(json['created_at'])
              : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'id_producto': idProducto,
      'id_almacen': idAlmacen,
      'stock_min': stockMin,
      'stock_max': stockMax,
      'stock_ordenar': stockOrdenar,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class WarehouseWorker {
  final String id;
  final String uuid;
  final String idAlmacen;
  final String? idTrabajador;
  final DateTime createdAt;
  final WarehouseEmployee? trabajador;

  WarehouseWorker({
    required this.id,
    required this.uuid,
    required this.idAlmacen,
    this.idTrabajador,
    required this.createdAt,
    this.trabajador,
  });

  factory WarehouseWorker.fromJson(Map<String, dynamic> json) {
    return WarehouseWorker(
      id: json['id']?.toString() ?? '',
      uuid: json['uuid'] ?? '',
      idAlmacen: json['id_almacen']?.toString() ?? '',
      idTrabajador: json['id_trabajador']?.toString(),
      createdAt:
          json['created_at'] != null
              ? DateTime.parse(json['created_at'])
              : DateTime.now(),
      trabajador:
          json['trabajador'] != null
              ? WarehouseEmployee.fromJson(json['trabajador'])
              : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'uuid': uuid,
      'id_almacen': idAlmacen,
      'id_trabajador': idTrabajador,
      'created_at': createdAt.toIso8601String(),
      'trabajador': trabajador?.toJson(),
    };
  }
}

class WarehouseEmployee {
  final String id;
  final String? idTienda;
  final String? idRoll;
  final String? nombres;
  final String? apellidos;
  final DateTime createdAt;

  WarehouseEmployee({
    required this.id,
    this.idTienda,
    this.idRoll,
    this.nombres,
    this.apellidos,
    required this.createdAt,
  });

  String get fullName => '${nombres ?? ''} ${apellidos ?? ''}'.trim();

  factory WarehouseEmployee.fromJson(Map<String, dynamic> json) {
    return WarehouseEmployee(
      id: json['id']?.toString() ?? '',
      idTienda: json['id_tienda']?.toString(),
      idRoll: json['id_roll']?.toString(),
      nombres: json['nombres'],
      apellidos: json['apellidos'],
      createdAt:
          json['created_at'] != null
              ? DateTime.parse(json['created_at'])
              : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'id_tienda': idTienda,
      'id_roll': idRoll,
      'nombres': nombres,
      'apellidos': apellidos,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class WarehouseLayoutType {
  final String id;
  final String denominacion;
  final String skuCodigo;
  final DateTime createdAt;

  WarehouseLayoutType({
    required this.id,
    required this.denominacion,
    required this.skuCodigo,
    required this.createdAt,
  });

  factory WarehouseLayoutType.fromJson(Map<String, dynamic> json) {
    return WarehouseLayoutType(
      id: json['id']?.toString() ?? '',
      denominacion: json['denominacion'] ?? '',
      skuCodigo: json['sku_codigo'] ?? '',
      createdAt:
          json['created_at'] != null
              ? DateTime.parse(json['created_at'])
              : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'denominacion': denominacion,
      'sku_codigo': skuCodigo,
      'created_at': createdAt.toIso8601String(),
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
      almacenes:
          (json['almacenes'] as List<dynamic>)
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
