import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_preferences_service.dart';

/// Service that wraps the warehouse valuation RPCs:
///  - fn_warehouses_valuation_summary  (tienda level)
///  - fn_warehouse_valuation_zones     (warehouse level)
///  - fn_zone_valuation_products       (zone level)
class WarehouseValuationService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final UserPreferencesService _prefs = UserPreferencesService();

  /// Summary for the whole tienda plus per-warehouse breakdown.
  Future<WarehousesValuationSummary> getTiendaSummary() async {
    final idTienda = await _prefs.getIdTienda();
    if (idTienda == null) {
      throw Exception('No se encontró el ID de tienda');
    }

    final response = await _supabase.rpc(
      'fn_warehouses_valuation_summary',
      params: {'p_id_tienda': idTienda},
    );

    if (response == null) {
      throw Exception('Respuesta vacía de fn_warehouses_valuation_summary');
    }

    return WarehousesValuationSummary.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  /// Zones breakdown for a single warehouse.
  Future<WarehouseZonesValuation> getWarehouseZones(int idAlmacen) async {
    final idTienda = await _prefs.getIdTienda();
    if (idTienda == null) {
      throw Exception('No se encontró el ID de tienda');
    }

    final response = await _supabase.rpc(
      'fn_warehouse_valuation_zones',
      params: {
        'p_id_tienda': idTienda,
        'p_id_almacen': idAlmacen,
      },
    );

    if (response == null) {
      throw Exception('Respuesta vacía de fn_warehouse_valuation_zones');
    }

    return WarehouseZonesValuation.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  /// Products breakdown for a single zone (layout).
  Future<ZoneProductsValuation> getZoneProducts(int idLayout) async {
    final idTienda = await _prefs.getIdTienda();
    if (idTienda == null) {
      throw Exception('No se encontró el ID de tienda');
    }

    final response = await _supabase.rpc(
      'fn_zone_valuation_products',
      params: {
        'p_id_tienda': idTienda,
        'p_id_layout': idLayout,
      },
    );

    if (response == null) {
      throw Exception('Respuesta vacía de fn_zone_valuation_products');
    }

    return ZoneProductsValuation.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }
}

// ============================================================================
// DTOs
// ============================================================================

double _asDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

int _asInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

class ValuationTotals {
  final double valorCostoUsd;
  final double valorCostoCup;
  final double valorVentaUsd;
  final double valorVentaCup;
  final double gananciaUsd;
  final double gananciaCup;
  final int productos;

  const ValuationTotals({
    required this.valorCostoUsd,
    required this.valorCostoCup,
    required this.valorVentaUsd,
    required this.valorVentaCup,
    required this.gananciaUsd,
    required this.gananciaCup,
    required this.productos,
  });

  factory ValuationTotals.fromJson(Map<String, dynamic> json) {
    return ValuationTotals(
      valorCostoUsd: _asDouble(json['valor_costo_usd']),
      valorCostoCup: _asDouble(json['valor_costo_cup']),
      valorVentaUsd: _asDouble(json['valor_venta_usd']),
      valorVentaCup: _asDouble(json['valor_venta_cup']),
      gananciaUsd: _asDouble(json['ganancia_usd']),
      gananciaCup: _asDouble(json['ganancia_cup']),
      productos: _asInt(json['productos']),
    );
  }

  static const empty = ValuationTotals(
    valorCostoUsd: 0,
    valorCostoCup: 0,
    valorVentaUsd: 0,
    valorVentaCup: 0,
    gananciaUsd: 0,
    gananciaCup: 0,
    productos: 0,
  );
}

class WarehouseValuation {
  final int idAlmacen;
  final String nombre;
  final int totalProductos;
  final double valorCostoUsd;
  final double valorCostoCup;
  final double valorVentaUsd;
  final double valorVentaCup;
  final double gananciaUsd;
  final double gananciaCup;

  WarehouseValuation({
    required this.idAlmacen,
    required this.nombre,
    required this.totalProductos,
    required this.valorCostoUsd,
    required this.valorCostoCup,
    required this.valorVentaUsd,
    required this.valorVentaCup,
    required this.gananciaUsd,
    required this.gananciaCup,
  });

  factory WarehouseValuation.fromJson(Map<String, dynamic> json) {
    return WarehouseValuation(
      idAlmacen: _asInt(json['id_almacen']),
      nombre: (json['nombre'] ?? '').toString(),
      totalProductos: _asInt(json['total_productos']),
      valorCostoUsd: _asDouble(json['valor_costo_usd']),
      valorCostoCup: _asDouble(json['valor_costo_cup']),
      valorVentaUsd: _asDouble(json['valor_venta_usd']),
      valorVentaCup: _asDouble(json['valor_venta_cup']),
      gananciaUsd: _asDouble(json['ganancia_usd']),
      gananciaCup: _asDouble(json['ganancia_cup']),
    );
  }
}

class WarehousesValuationSummary {
  final double tasa;
  final ValuationTotals totales;
  final List<WarehouseValuation> almacenes;

  WarehousesValuationSummary({
    required this.tasa,
    required this.totales,
    required this.almacenes,
  });

  factory WarehousesValuationSummary.fromJson(Map<String, dynamic> json) {
    final totales = json['totales'];
    final almacenes = (json['almacenes'] as List?) ?? const [];
    return WarehousesValuationSummary(
      tasa: _asDouble(json['tasa']),
      totales: totales is Map
          ? ValuationTotals.fromJson(Map<String, dynamic>.from(totales))
          : ValuationTotals.empty,
      almacenes: almacenes
          .map((e) => WarehouseValuation.fromJson(
                Map<String, dynamic>.from(e as Map),
              ))
          .toList(),
    );
  }
}

class ZoneValuation {
  final int idLayout;
  final String nombre;
  final int? idLayoutPadre;
  final int totalProductos;
  final double valorCostoUsd;
  final double valorCostoCup;
  final double valorVentaUsd;
  final double valorVentaCup;
  final double gananciaUsd;
  final double gananciaCup;

  ZoneValuation({
    required this.idLayout,
    required this.nombre,
    required this.idLayoutPadre,
    required this.totalProductos,
    required this.valorCostoUsd,
    required this.valorCostoCup,
    required this.valorVentaUsd,
    required this.valorVentaCup,
    required this.gananciaUsd,
    required this.gananciaCup,
  });

  factory ZoneValuation.fromJson(Map<String, dynamic> json) {
    return ZoneValuation(
      idLayout: _asInt(json['id_layout']),
      nombre: (json['nombre'] ?? '').toString(),
      idLayoutPadre: json['id_layout_padre'] == null
          ? null
          : _asInt(json['id_layout_padre']),
      totalProductos: _asInt(json['total_productos']),
      valorCostoUsd: _asDouble(json['valor_costo_usd']),
      valorCostoCup: _asDouble(json['valor_costo_cup']),
      valorVentaUsd: _asDouble(json['valor_venta_usd']),
      valorVentaCup: _asDouble(json['valor_venta_cup']),
      gananciaUsd: _asDouble(json['ganancia_usd']),
      gananciaCup: _asDouble(json['ganancia_cup']),
    );
  }
}

class WarehouseZonesValuation {
  final double tasa;
  final int? idAlmacen;
  final String almacenNombre;
  final ValuationTotals totales;
  final List<ZoneValuation> zonas;

  WarehouseZonesValuation({
    required this.tasa,
    required this.idAlmacen,
    required this.almacenNombre,
    required this.totales,
    required this.zonas,
  });

  factory WarehouseZonesValuation.fromJson(Map<String, dynamic> json) {
    final almacen = json['almacen'];
    final totales = json['totales'];
    final zonas = (json['zonas'] as List?) ?? const [];
    return WarehouseZonesValuation(
      tasa: _asDouble(json['tasa']),
      idAlmacen: almacen is Map ? _asInt(almacen['id']) : null,
      almacenNombre: almacen is Map ? (almacen['nombre'] ?? '').toString() : '',
      totales: totales is Map
          ? ValuationTotals.fromJson(Map<String, dynamic>.from(totales))
          : ValuationTotals.empty,
      zonas: zonas
          .map((e) =>
              ZoneValuation.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}

class ProductValuation {
  final int idProducto;
  final String nombre;
  final String sku;
  final double cantidad;
  final double precioCostoUsd;
  final double precioCostoCup;
  final double precioVentaUsd;
  final double precioVentaCup;
  final double valorCostoUsd;
  final double valorCostoCup;
  final double valorVentaUsd;
  final double valorVentaCup;
  final double gananciaUsd;
  final double gananciaCup;

  ProductValuation({
    required this.idProducto,
    required this.nombre,
    required this.sku,
    required this.cantidad,
    required this.precioCostoUsd,
    required this.precioCostoCup,
    required this.precioVentaUsd,
    required this.precioVentaCup,
    required this.valorCostoUsd,
    required this.valorCostoCup,
    required this.valorVentaUsd,
    required this.valorVentaCup,
    required this.gananciaUsd,
    required this.gananciaCup,
  });

  factory ProductValuation.fromJson(Map<String, dynamic> json) {
    return ProductValuation(
      idProducto: _asInt(json['id_producto']),
      nombre: (json['nombre'] ?? '').toString(),
      sku: (json['sku'] ?? '').toString(),
      cantidad: _asDouble(json['cantidad']),
      precioCostoUsd: _asDouble(json['precio_costo_usd']),
      precioCostoCup: _asDouble(json['precio_costo_cup']),
      precioVentaUsd: _asDouble(json['precio_venta_usd']),
      precioVentaCup: _asDouble(json['precio_venta_cup']),
      valorCostoUsd: _asDouble(json['valor_costo_usd']),
      valorCostoCup: _asDouble(json['valor_costo_cup']),
      valorVentaUsd: _asDouble(json['valor_venta_usd']),
      valorVentaCup: _asDouble(json['valor_venta_cup']),
      gananciaUsd: _asDouble(json['ganancia_usd']),
      gananciaCup: _asDouble(json['ganancia_cup']),
    );
  }
}

class ZoneProductsValuation {
  final double tasa;
  final int? idLayout;
  final String zonaNombre;
  final int? idAlmacen;
  final String almacenNombre;
  final ValuationTotals totales;
  final List<ProductValuation> productos;

  ZoneProductsValuation({
    required this.tasa,
    required this.idLayout,
    required this.zonaNombre,
    required this.idAlmacen,
    required this.almacenNombre,
    required this.totales,
    required this.productos,
  });

  factory ZoneProductsValuation.fromJson(Map<String, dynamic> json) {
    final zona = json['zona'];
    final totales = json['totales'];
    final productos = (json['productos'] as List?) ?? const [];
    return ZoneProductsValuation(
      tasa: _asDouble(json['tasa']),
      idLayout: zona is Map ? _asInt(zona['id_layout']) : null,
      zonaNombre: zona is Map ? (zona['nombre'] ?? '').toString() : '',
      idAlmacen: zona is Map ? _asInt(zona['id_almacen']) : null,
      almacenNombre:
          zona is Map ? (zona['almacen_nombre'] ?? '').toString() : '',
      totales: totales is Map
          ? ValuationTotals.fromJson(Map<String, dynamic>.from(totales))
          : ValuationTotals.empty,
      productos: productos
          .map((e) =>
              ProductValuation.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}
