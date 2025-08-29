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
  final double stockDisponible;
  final double stockReservado;
  final double stockDisponibleAjustado;
  final bool esVendible;
  final bool esInventariable;
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
    required this.stockDisponible,
    required this.stockReservado,
    required this.stockDisponibleAjustado,
    required this.esVendible,
    required this.esInventariable,
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
      throw ArgumentError('Invalid data type for InventoryProduct.fromSupabaseRpc');
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
        summary = InventorySummary.fromJson(map['resumen_inventario'] as Map<String, dynamic>);
      }
    }
    
    if (map['info_paginacion'] != null) {
      if (map['info_paginacion'] is String) {
        // Parse JSON string
        final paginationJson = map['info_paginacion'] as String;
        // Handle JSON parsing here if needed
      } else if (map['info_paginacion'] is Map) {
        pagination = PaginationInfo.fromJson(map['info_paginacion'] as Map<String, dynamic>);
      }
    }

    return InventoryProduct(
      id: map['id'] ?? 0,
      skuProducto: map['sku_producto'] ?? '',
      nombreProducto: map['nombre_producto'] ?? '',
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
      stockDisponible: (map['stock_disponible'] ?? 0).toDouble(),
      stockReservado: (map['stock_reservado'] ?? 0).toDouble(),
      stockDisponibleAjustado: (map['stock_disponible_ajustado'] ?? 0).toDouble(),
      esVendible: map['es_vendible'] ?? false,
      esInventariable: map['es_inventariable'] ?? false,
      precioVenta: map['precio_venta']?.toDouble(),
      costoPromedio: map['costo_promedio']?.toDouble(),
      margenActual: map['margen_actual']?.toDouble(),
      clasificacionAbc: map['clasificacion_abc'] ?? 3,
      abcDescripcion: map['abc_descripcion'] ?? 'No clasificado',
      fechaUltimaActualizacion: map['fecha_ultima_actualizacion'] != null 
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
      idCategoria: row[3] ?? 0,
      categoria: row[4] ?? '',
      idSubcategoria: row[5] ?? 0,
      subcategoria: row[6] ?? '',
      idTienda: row[7] ?? 0,
      tienda: row[8] ?? '',
      idAlmacen: row[9] ?? 0,
      almacen: row[10] ?? '',
      idUbicacion: row[11] ?? 0,
      ubicacion: row[12] ?? '',
      idVariante: row[13],
      variante: row[14] ?? 'Unidad',
      idOpcionVariante: row[15],
      opcionVariante: row[16] ?? 'Única',
      idPresentacion: row[17],
      presentacion: row[18] ?? 'Unidad',
      cantidadInicial: (row[19] ?? 0).toDouble(),
      cantidadFinal: (row[20] ?? 0).toDouble(),
      stockDisponible: (row[21] ?? 0).toDouble(),
      stockReservado: (row[22] ?? 0).toDouble(),
      stockDisponibleAjustado: (row[23] ?? 0).toDouble(),
      esVendible: row[24] ?? false,
      esInventariable: row[25] ?? false,
      precioVenta: row[26]?.toDouble(),
      costoPromedio: row[27]?.toDouble(),
      margenActual: row[28]?.toDouble(),
      clasificacionAbc: row[29] ?? 3,
      abcDescripcion: row[30] ?? 'No clasificado',
      fechaUltimaActualizacion: DateTime.parse(row[31] ?? DateTime.now().toIso8601String()),
      totalCount: row[32] ?? 0,
      resumenInventario: row.length > 33 && row[33] != null 
          ? InventorySummary.fromJson(Map<String, dynamic>.from(row[33]))
          : null,
      infoPaginacion: row.length > 34 && row[34] != null 
          ? PaginationInfo.fromJson(Map<String, dynamic>.from(row[34]))
          : null,
    );
  }
}
