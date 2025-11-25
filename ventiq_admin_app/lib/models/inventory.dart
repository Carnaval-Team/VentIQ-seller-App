import 'package:flutter/material.dart';

// Models for JSON fields from RPC function
class InventorySummary {
  final int totalInventario;
  final int totalConCantidadBaja;
  final int totalSinStock;

  InventorySummary({
    required this.totalInventario,
    required this.totalConCantidadBaja,
    required this.totalSinStock,
  });

  factory InventorySummary.fromJson(Map<String, dynamic> json) {
    return InventorySummary(
      totalInventario: json['total_inventario'] ?? 0,
      totalConCantidadBaja: json['total_con_cantidad_baja'] ?? 0,
      totalSinStock: json['total_sin_stock'] ?? 0,
    );
  }
}

class PaginationInfo {
  final int paginaActual;
  final int totalItems;
  final int totalPaginas;
  final int totalRegistros;
  final bool tieneAnterior;
  final bool tieneSiguiente;

  PaginationInfo({
    required this.paginaActual,
    required this.totalItems,
    required this.totalPaginas,
    required this.totalRegistros,
    required this.tieneAnterior,
    required this.tieneSiguiente,
  });

  factory PaginationInfo.fromJson(Map<String, dynamic> json) {
    return PaginationInfo(
      paginaActual: json['pagina_actual'] ?? 1,
      totalItems: json['total_items'] ?? 50,
      totalPaginas: json['total_paginas'] ?? 1,
      totalRegistros: json['total_registros'] ?? 0,
      tieneAnterior: json['tiene_anterior'] ?? false,
      tieneSiguiente: json['tiene_siguiente'] ?? false,
    );
  }
}

// New model for Supabase RPC response
class InventoryProduct {
  final int id;
  final String skuProducto;
  final String nombreProducto;
  final String? denominacionCorta;
  final String? nombreComercial;
  final String? descripcion;
  final String? descripcionCorta;
  final int idCategoria;
  final String categoria;
  final int idSubcategoria;
  final String subcategoria;
  final int idTienda;
  final String tienda;
  final int idAlmacen;
  final String almacen;
  final int idUbicacion;
  final String ubicacion;
  final int? idVariante;
  final String variante;
  final int? idOpcionVariante;
  final String opcionVariante;
  final int? idPresentacion;
  final String presentacion;
  final double cantidadInicial;
  final double cantidadFinal;
  final double? entradasPeriodo;
  final double? extraccionesPeriodo;
  final double? ventasPeriodo;
  final double stockDisponible;
  final double stockReservado;
  final double stockDisponibleAjustado;
  final bool esVendible;
  final bool esInventariable;
  final bool esElaborado;
  final double? precioVenta;
  final double? costoPromedio;
  final double? margenActual;
  final int clasificacionAbc;
  final String abcDescripcion;
  final DateTime fechaUltimaActualizacion;
  final int totalCount;
  final InventorySummary? resumenInventario;
  final PaginationInfo? infoPaginacion;

  // Virtual fields for stock level calculation
  String get stockLevel {
    if (cantidadFinal <= 0) return 'Sin Stock';
    if (cantidadFinal <= 10) return 'Stock Bajo'; // Virtual threshold
    return 'Stock OK';
  }

  Color get stockLevelColor {
    switch (stockLevel) {
      case 'Sin Stock':
        return const Color(0xFFDC2626); // Red
      case 'Stock Bajo':
        return const Color(0xFFF59E0B); // Orange
      default:
        return const Color(0xFF10B981); // Green
    }
  }

  InventoryProduct({
    required this.id,
    required this.skuProducto,
    required this.nombreProducto,
    this.denominacionCorta,
    this.nombreComercial,
    this.descripcion,
    this.descripcionCorta,
    required this.idCategoria,
    required this.categoria,
    required this.idSubcategoria,
    required this.subcategoria,
    required this.idTienda,
    required this.tienda,
    required this.idAlmacen,
    required this.almacen,
    required this.idUbicacion,
    required this.ubicacion,
    this.idVariante,
    required this.variante,
    this.idOpcionVariante,
    required this.opcionVariante,
    this.idPresentacion,
    required this.presentacion,
    required this.cantidadInicial,
    required this.cantidadFinal,
    this.entradasPeriodo,
    this.extraccionesPeriodo,
    this.ventasPeriodo,
    required this.stockDisponible,
    required this.stockReservado,
    required this.stockDisponibleAjustado,
    required this.esVendible,
    required this.esInventariable,
    this.esElaborado = false,
    this.precioVenta,
    this.costoPromedio,
    this.margenActual,
    required this.clasificacionAbc,
    required this.abcDescripcion,
    required this.fechaUltimaActualizacion,
    required this.totalCount,
    this.resumenInventario,
    this.infoPaginacion,
  });

  factory InventoryProduct.fromSupabaseRpc(dynamic data) {
    if (data is Map<String, dynamic>) {
      return InventoryProduct.fromMap(data);
    } else if (data is List<dynamic>) {
      return InventoryProduct.fromList(data);
    } else {
      throw ArgumentError(
        'Invalid data type for InventoryProduct.fromSupabaseRpc',
      );
    }
  }

  factory InventoryProduct.fromMap(Map<String, dynamic> map) {
    // Parse JSON fields
    InventorySummary? summary;
    PaginationInfo? pagination;

    if (map['resumen_inventario'] != null) {
      if (map['resumen_inventario'] is String) {
        // Parse JSON string
        final summaryJson = map['resumen_inventario'] as String;
        // Handle JSON parsing here if needed
      } else if (map['resumen_inventario'] is Map) {
        summary = InventorySummary.fromJson(
          map['resumen_inventario'] as Map<String, dynamic>,
        );
      }
    }

    if (map['info_paginacion'] != null) {
      if (map['info_paginacion'] is String) {
        // Parse JSON string
        final paginationJson = map['info_paginacion'] as String;
        // Handle JSON parsing here if needed
      } else if (map['info_paginacion'] is Map) {
        pagination = PaginationInfo.fromJson(
          map['info_paginacion'] as Map<String, dynamic>,
        );
      }
    }

    return InventoryProduct(
      id: map['id'] ?? 0,
      skuProducto: map['sku_producto'] ?? '',
      nombreProducto: map['nombre_producto'] ?? '',
      denominacionCorta: map['denominacion_corta'],
      nombreComercial: map['nombre_comercial'],
      descripcion: map['descripcion'],
      descripcionCorta: map['descripcion_corta'],
      idCategoria: map['id_categoria'] ?? 0,
      categoria: map['categoria'] ?? '',
      idSubcategoria: map['id_subcategoria'] ?? 0,
      subcategoria: map['subcategoria'] ?? '',
      idTienda: map['id_tienda'] ?? 0,
      tienda: map['tienda'] ?? '',
      idAlmacen: map['id_almacen'] ?? 0,
      almacen: map['almacen'] ?? '',
      idUbicacion: map['id_ubicacion'] ?? 0,
      ubicacion: map['ubicacion'] ?? '',
      idVariante: map['id_variante'],
      variante: map['variante'] ?? 'Unidad',
      idOpcionVariante: map['id_opcion_variante'],
      opcionVariante: map['opcion_variante'] ?? 'Única',
      idPresentacion: map['id_presentacion'],
      presentacion: map['presentacion'] ?? 'Unidad',
      cantidadInicial: (map['cantidad_inicial'] ?? 0).toDouble(),
      cantidadFinal: (map['cantidad_final'] ?? 0).toDouble(),
      entradasPeriodo: map['entradas_periodo'] != null ? (map['entradas_periodo']).toDouble() : null,
      extraccionesPeriodo: map['extracciones_periodo'] != null ? (map['extracciones_periodo']).toDouble() : null,
      ventasPeriodo: map['ventas_periodo'] != null ? (map['ventas_periodo']).toDouble() : null,
      stockDisponible: (map['stock_disponible'] ?? 0).toDouble(),
      stockReservado: (map['stock_reservado'] ?? 0).toDouble(),
      stockDisponibleAjustado:
          (map['stock_disponible_ajustado'] ?? 0).toDouble(),
      esVendible: map['es_vendible'] ?? false,
      esInventariable: map['es_inventariable'] ?? false,
      esElaborado: map['es_elaborado'] ?? false,
      precioVenta: map['precio_venta']?.toDouble(),
      costoPromedio: map['costo_promedio']?.toDouble(),
      margenActual: map['margen_actual']?.toDouble(),
      clasificacionAbc: map['clasificacion_abc'] ?? 3,
      abcDescripcion: map['abc_descripcion'] ?? 'No clasificado',
      fechaUltimaActualizacion:
          map['fecha_ultima_actualizacion'] != null
              ? DateTime.parse(map['fecha_ultima_actualizacion'])
              : DateTime.now(),
      totalCount: map['total_count'] ?? 0,
      resumenInventario: summary,
      infoPaginacion: pagination,
    );
  }

  factory InventoryProduct.fromList(List<dynamic> row) {
    return InventoryProduct(
      id: row[0] ?? 0,
      skuProducto: row[1] ?? '',
      nombreProducto: row[2] ?? '',
      nombreComercial: row[3],
      denominacionCorta: row[4],
      descripcion: row[5],
      descripcionCorta: row[6],
      idCategoria: row[8] ?? 0,
      categoria: row[9] ?? '',
      idSubcategoria: row[10] ?? 0,
      subcategoria: row[11] ?? '',
      idTienda: row[12] ?? 0,
      tienda: row[13] ?? '',
      idAlmacen: row[14] ?? 0,
      almacen: row[15] ?? '',
      idUbicacion: row[16] ?? 0,
      ubicacion: row[17] ?? '',
      idVariante: row[18],
      variante: row[19] ?? 'Unidad',
      idOpcionVariante: row[20],
      opcionVariante: row[21] ?? 'Única',
      idPresentacion: row[22],
      presentacion: row[23] ?? 'Unidad',
      cantidadInicial: (row[24] ?? 0).toDouble(),
      cantidadFinal: (row[25] ?? 0).toDouble(),
      entradasPeriodo: null,
      extraccionesPeriodo: null,
      ventasPeriodo: null,
      stockDisponible: (row[26] ?? 0).toDouble(),
      stockReservado: (row[27] ?? 0).toDouble(),
      stockDisponibleAjustado: (row[28] ?? 0).toDouble(),
      esVendible: row[29] ?? false,
      esInventariable: row[31] ?? false,
      esElaborado: row[38] ?? false,
      precioVenta: row[42]?.toDouble(),
      costoPromedio: row[43]?.toDouble(),
      margenActual: row[44]?.toDouble(),
      clasificacionAbc: row[45] ?? 3,
      abcDescripcion: row[46] ?? 'No clasificado',
      fechaUltimaActualizacion: DateTime.parse(
        row[47] ?? DateTime.now().toIso8601String(),
      ),
      totalCount: row[48] ?? 0,
      resumenInventario:
          row.length > 37 && row[37] != null
              ? InventorySummary.fromJson(Map<String, dynamic>.from(row[37]))
              : null,
      infoPaginacion:
          row.length > 38 && row[38] != null
              ? PaginationInfo.fromJson(Map<String, dynamic>.from(row[38]))
              : null,
    );
  }

  // Convert to legacy InventoryItem for compatibility
  InventoryItem toInventoryItem() {
    return InventoryItem(
      id: id.toString(),
      productId: id.toString(),
      variantId: idVariante?.toString() ?? '',
      productName: nombreProducto,
      variantName: variante,
      presentation: presentacion,
      sku: skuProducto,
      warehouseId: idAlmacen.toString(),
      warehouseName: almacen,
      location: ubicacion,
      currentStock: cantidadFinal.toInt(),
      minStock: 10, // Virtual minimum stock
      maxStock: 100, // Virtual maximum stock
      unitCost: costoPromedio ?? 0.0,
      abcClassification:
          clasificacionAbc == 1
              ? 'A'
              : clasificacionAbc == 2
              ? 'B'
              : 'C',
      lastMovement: fechaUltimaActualizacion,
      needsRestock: cantidadFinal <= 10,
    );
  }
}

class InventoryItem {
  final String id;
  final String productId;
  final String variantId;
  final String productName;
  final String variantName;
  final String presentation;
  final String sku;
  final String warehouseId;
  final String warehouseName;
  final String location;
  final int currentStock;
  final int minStock;
  final int maxStock;
  final double unitCost;
  final String abcClassification; // A, B, C
  final DateTime lastMovement;
  final bool needsRestock;

  InventoryItem({
    required this.id,
    required this.productId,
    required this.variantId,
    required this.productName,
    required this.variantName,
    required this.presentation,
    required this.sku,
    required this.warehouseId,
    required this.warehouseName,
    required this.location,
    required this.currentStock,
    required this.minStock,
    required this.maxStock,
    required this.unitCost,
    required this.abcClassification,
    required this.lastMovement,
    required this.needsRestock,
  });

  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    return InventoryItem(
      id: json['id'] ?? '',
      productId: json['productId'] ?? '',
      variantId: json['variantId'] ?? '',
      productName: json['productName'] ?? '',
      variantName: json['variantName'] ?? '',
      presentation: json['presentation'] ?? '',
      sku: json['sku'] ?? '',
      warehouseId: json['warehouseId'] ?? '',
      warehouseName: json['warehouseName'] ?? '',
      location: json['location'] ?? '',
      currentStock: json['currentStock'] ?? 0,
      minStock: json['minStock'] ?? 0,
      maxStock: json['maxStock'] ?? 0,
      unitCost: (json['unitCost'] ?? 0.0).toDouble(),
      abcClassification: json['abcClassification'] ?? 'C',
      lastMovement: DateTime.parse(
        json['lastMovement'] ?? DateTime.now().toIso8601String(),
      ),
      needsRestock: json['needsRestock'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'productId': productId,
      'variantId': variantId,
      'productName': productName,
      'variantName': variantName,
      'presentation': presentation,
      'sku': sku,
      'warehouseId': warehouseId,
      'warehouseName': warehouseName,
      'location': location,
      'currentStock': currentStock,
      'minStock': minStock,
      'maxStock': maxStock,
      'unitCost': unitCost,
      'abcClassification': abcClassification,
      'lastMovement': lastMovement.toIso8601String(),
      'needsRestock': needsRestock,
    };
  }
}

class InventoryMovement {
  final String id;
  final String inventoryItemId;
  final String type; // entrada, salida, transferencia, ajuste
  final int quantity;
  final String reason;
  final String userId;
  final String userName;
  final DateTime timestamp;
  final String? fromWarehouse;
  final String? toWarehouse;
  final String? reference;

  InventoryMovement({
    required this.id,
    required this.inventoryItemId,
    required this.type,
    required this.quantity,
    required this.reason,
    required this.userId,
    required this.userName,
    required this.timestamp,
    this.fromWarehouse,
    this.toWarehouse,
    this.reference,
  });

  factory InventoryMovement.fromJson(Map<String, dynamic> json) {
    return InventoryMovement(
      id: json['id'] ?? '',
      inventoryItemId: json['inventoryItemId'] ?? '',
      type: json['type'] ?? '',
      quantity: json['quantity'] ?? 0,
      reason: json['reason'] ?? '',
      userId: json['userId'] ?? '',
      userName: json['userName'] ?? '',
      timestamp: DateTime.parse(
        json['timestamp'] ?? DateTime.now().toIso8601String(),
      ),
      fromWarehouse: json['fromWarehouse'],
      toWarehouse: json['toWarehouse'],
      reference: json['reference'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'inventoryItemId': inventoryItemId,
      'type': type,
      'quantity': quantity,
      'reason': reason,
      'userId': userId,
      'userName': userName,
      'timestamp': timestamp.toIso8601String(),
      'fromWarehouse': fromWarehouse,
      'toWarehouse': toWarehouse,
      'reference': reference,
    };
  }
}

// Response wrapper for paginated inventory data
class InventoryResponse {
  final List<InventoryProduct> products;
  final InventorySummary? summary;
  final PaginationInfo? pagination;

  InventoryResponse({required this.products, this.summary, this.pagination});
}

// Model for inventory summary by user from fn_inventario_resumen_por_usuario
class InventorySummaryByUser {
  final int idProducto;
  final String productoNombre;
  final String productoSku;
  final String? productoDescripcion;
  final int? idVariante;
  final String varianteValor;
  final int? idOpcionVariante;
  final String opcionVarianteValor;
  final double cantidadTotalEnUnidadesBase;
  final double cantidadTotalEnAlmacen;
  final int zonasDiferentes;
  final int presentacionesDiferentes;

  InventorySummaryByUser({
    required this.idProducto,
    required this.productoNombre,
    required this.productoSku,
    this.productoDescripcion,
    this.idVariante,
    required this.varianteValor,
    this.idOpcionVariante,
    required this.opcionVarianteValor,
    required this.cantidadTotalEnUnidadesBase,
    required this.cantidadTotalEnAlmacen,
    required this.zonasDiferentes,
    required this.presentacionesDiferentes,
  });

  // Helper methods for UI display
  bool get hasVariant => idVariante != null && varianteValor != 'N/A';
  bool get hasOptionVariant =>
      idOpcionVariante != null && opcionVarianteValor != 'N/A';
  bool get hasMultipleLocations => zonasDiferentes > 1;
  bool get hasMultiplePresentations => presentacionesDiferentes > 1;

  String get variantDisplay {
    if (!hasVariant && !hasOptionVariant) return '';
    if (hasVariant && hasOptionVariant) {
      return '$varianteValor → $opcionVarianteValor';
    }
    if (hasVariant) return varianteValor;
    if (hasOptionVariant) return opcionVarianteValor;
    return '';
  }

  // Virtual fields for stock level calculation
  String get stockLevel {
    if (cantidadTotalEnAlmacen <= 0) return 'Sin Stock';
    if (cantidadTotalEnAlmacen <= 10) return 'Stock Bajo';
    return 'Stock OK';
  }

  Color get stockLevelColor {
    switch (stockLevel) {
      case 'Sin Stock':
        return const Color(0xFFDC2626); // Red
      case 'Stock Bajo':
        return const Color(0xFFF59E0B); // Orange
      default:
        return const Color(0xFF10B981); // Green
    }
  }

  factory InventorySummaryByUser.fromMap(Map<String, dynamic> map) {
    return InventorySummaryByUser(
      idProducto: map['id_producto'] ?? 0,
      productoNombre: map['producto_nombre'] ?? '',
      productoSku: map['producto_sku'] ?? '',
      productoDescripcion: map['producto_descripcion'],
      idVariante: map['id_variante'],
      varianteValor: map['variante_valor'] ?? 'N/A',
      idOpcionVariante: map['id_opcion_variante'],
      opcionVarianteValor: map['opcion_variante_valor'] ?? 'N/A',
      cantidadTotalEnUnidadesBase:
          (map['cantidad_total_en_unidades_base'] ?? 0).toDouble(),
      cantidadTotalEnAlmacen:
          (map['cantidad_total_en_almacen'] ?? 0).toDouble(),
      zonasDiferentes: map['zonas_diferentes'] ?? 0,
      presentacionesDiferentes: map['presentaciones_diferentes'] ?? 0,
    );
  }

  factory InventorySummaryByUser.fromJson(Map<String, dynamic> json) {
    return InventorySummaryByUser(
      idProducto: json['prod_id'] ?? 0,
      productoNombre: json['prod_nombre'] ?? '',
      productoSku: json['prod_sku'] ?? '',
      productoDescripcion: json['prod_descripcion'],
      idVariante: json['variante_id'],
      varianteValor: json['variante_valor'] ?? 'N/A',
      idOpcionVariante: json['opcion_variante_id'],
      opcionVarianteValor: json['opcion_variante_valor'] ?? 'N/A',
      cantidadTotalEnUnidadesBase: (json['cant_unidades_base'] ?? 0).toDouble(),
      cantidadTotalEnAlmacen: (json['cant_almacen_total'] ?? 0).toDouble(),
      zonasDiferentes: (json['zonas_count'] ?? 0).toInt(),
      presentacionesDiferentes: (json['presentaciones_count'] ?? 1).toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id_producto': idProducto,
      'producto_nombre': productoNombre,
      'producto_sku': productoSku,
      'producto_descripcion': productoDescripcion,
      'id_variante': idVariante,
      'variante_valor': varianteValor,
      'id_opcion_variante': idOpcionVariante,
      'opcion_variante_valor': opcionVarianteValor,
      'cantidad_total_en_unidades_base': cantidadTotalEnUnidadesBase,
      'cantidad_total_en_almacen': cantidadTotalEnAlmacen,
      'zonas_diferentes': zonasDiferentes,
      'presentaciones_diferentes': presentacionesDiferentes,
    };
  }
}
