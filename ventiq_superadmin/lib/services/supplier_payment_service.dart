import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/supplier_payment_model.dart';

class _ExcludedInventtiaLine {
  final int orderId;
  final int? proveedorId;

  const _ExcludedInventtiaLine({
    required this.orderId,
    required this.proveedorId,
  });
}

class SupplierPaymentService {
  static final _supabase = Supabase.instance.client;

  /// Inventtia: 3 Devuelta, 4 Cancelada, 5 Anulada
  static const _estadosExcluidosInventtia = [3, 4, 5];

  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  /// `Orders.created_at` es DATE: filtrar por yyyy-MM-dd evita el desfase UTC.
  static String _toDateIso(DateTime d) {
    final day = _startOfDay(d);
    final y = day.year.toString().padLeft(4, '0');
    final m = day.month.toString().padLeft(2, '0');
    final dd = day.day.toString().padLeft(2, '0');
    return '$y-$m-$dd';
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static DateTime? _asDate(dynamic value) {
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is List && value.isNotEmpty) return _asMap(value.first);
    return null;
  }

  /// Carga los porcentajes de recargo aplicables a cada proveedor (tienda)
  /// usando la configuración de `app_dat_precio_general_tienda` con el piso
  /// global de `precio_global_productos_carnaval`.
  static Future<Map<int, ({double cashPct, double transferPct})>> _loadStorePricing(
    Set<int> carnavalProviderIds,
  ) async {
    if (carnavalProviderIds.isEmpty) {
      return {};
    }

    final globalResponse = await _supabase
        .from('precio_global_productos_carnaval')
        .select('porciento_efectivo, porciento_transferencia')
        .limit(1)
        .maybeSingle();

    final floorCash =
        (globalResponse?['porciento_efectivo'] as num?)?.toDouble() ?? 0.0;
    final floorTransfer =
        (globalResponse?['porciento_transferencia'] as num?)?.toDouble() ?? 0.0;

    final tiendasResponse = await _supabase
        .from('app_dat_tienda')
        .select('id, id_tienda_carnaval')
        .inFilter('id_tienda_carnaval', carnavalProviderIds.toList());

    final tiendaIdsByProvider = <int, int>{};
    for (final row in tiendasResponse as List) {
      final providerId = _asInt(row['id_tienda_carnaval']);
      final tiendaId = _asInt(row['id']);
      if (providerId != null && tiendaId != null) {
        tiendaIdsByProvider[providerId] = tiendaId;
      }
    }

    final pricingResponse = await _supabase
        .from('app_dat_precio_general_tienda')
        .select(
          'id_tienda, precio_venta_carnaval, precio_venta_carnaval_transferencia',
        )
        .inFilter('id_tienda', tiendaIdsByProvider.values.toList());

    final configsByTienda = <int, Map<String, double>>{};
    for (final row in pricingResponse as List) {
      final tiendaId = _asInt(row['id_tienda']);
      if (tiendaId == null) continue;
      configsByTienda[tiendaId] = {
        'cash':
            (row['precio_venta_carnaval'] as num?)?.toDouble() ?? floorCash,
        'transfer':
            (row['precio_venta_carnaval_transferencia'] as num?)?.toDouble() ??
                floorTransfer,
      };
    }

    final result = <int, ({double cashPct, double transferPct})>{};
    for (final providerId in carnavalProviderIds) {
      final tiendaId = tiendaIdsByProvider[providerId];
      final config = tiendaId != null ? configsByTienda[tiendaId] : null;
      final cash = config?['cash'] ?? floorCash;
      final transfer = config?['transfer'] ?? floorTransfer;
      result[providerId] = (
        cashPct: cash < floorCash ? floorCash : cash,
        transferPct: transfer < floorTransfer ? floorTransfer : transfer,
      );
    }
    return result;
  }

  /// Obtener resumen de pagos por proveedor en un rango de fechas
  static Future<List<SupplierPaymentSummary>> getSupplierPayments(
    DateTime fechaInicio,
    DateTime fechaFin,
  ) async {
    try {
      debugPrint('📊 Obteniendo pagos a proveedores...');
      debugPrint(
        '📅 Rango: ${fechaInicio.toIso8601String()} - ${fechaFin.toIso8601String()}',
      );

      return await _getSupplierPaymentsManual(fechaInicio, fechaFin);
    } catch (e) {
      debugPrint('❌ Error obteniendo pagos: $e');
      return [];
    }
  }

  static Future<List<SupplierPaymentSummary>> _getSupplierPaymentsManual(
    DateTime fechaInicio,
    DateTime fechaFin,
  ) async {
    try {
      debugPrint(
        '📊 Filtrando órdenes creadas en el periodo, sin canceladas ni devueltas...',
      );

      final lines = await _fetchPaymentLines(
        fechaInicio: fechaInicio,
        fechaFin: fechaFin,
      );

      final carnavalProviderIds =
          lines.map((order) => _asInt(order['proveedor']) ?? 3).toSet();
      final pricingByProvider = await _loadStorePricing(carnavalProviderIds);

      final Map<int, Map<String, dynamic>> supplierTotals = {};

      for (final order in lines) {
        final proveedorId = _asInt(order['proveedor']) ?? 3;
        final price = (order['price'] as num?)?.toDouble() ?? 0.0;
        final quantity = _asInt(order['quantity']) ?? 0;
        final precioUsd = (order['precio_usd'] as num?)?.toDouble() ?? 1.0;
        final precioEuro = (order['precio_euro'] as num?)?.toDouble() ?? 1.0;
        final isTransfer = order['transferencia'] as bool? ?? false;

        final totalRow = price * quantity;
        final pricing = pricingByProvider[proveedorId] ??
            (cashPct: 0.0, transferPct: 0.0);
        final pct = isTransfer ? pricing.transferPct : pricing.cashPct;
        final netRow = totalRow * (1 - pct / 100);

        supplierTotals.putIfAbsent(proveedorId, () {
          return {
            'total_cup': 0.0,
            'total_usd': 0.0,
            'total_euro': 0.0,
            'total_cash': 0.0,
            'total_transfer': 0.0,
            'net_cash': 0.0,
            'net_transfer': 0.0,
            'total_orders': 0,
          };
        });

        supplierTotals[proveedorId]!['total_cup'] += totalRow;
        supplierTotals[proveedorId]!['total_usd'] += precioUsd * quantity;
        supplierTotals[proveedorId]!['total_euro'] += precioEuro * quantity;

        if (isTransfer) {
          supplierTotals[proveedorId]!['total_transfer'] += totalRow;
          supplierTotals[proveedorId]!['net_transfer'] += netRow;
        } else {
          supplierTotals[proveedorId]!['total_cash'] += totalRow;
          supplierTotals[proveedorId]!['net_cash'] += netRow;
        }

        supplierTotals[proveedorId]!['total_orders'] += 1;
      }

      final proveedorIds = supplierTotals.keys.toList();
      if (proveedorIds.isEmpty) {
        return [];
      }

      final proveedoresResponse = await _supabase
          .schema('carnavalapp')
          .from('proveedores')
          .select('*')
          .inFilter('id', proveedorIds);

      final List<SupplierPaymentSummary> suppliers = [];
      for (final proveedor in proveedoresResponse) {
        final id = proveedor['id'] as int;
        final totals = supplierTotals[id]!;

        suppliers.add(
          SupplierPaymentSummary(
            id: id,
            name: proveedor['name'] as String? ?? 'Sin nombre',
            logo: proveedor['logo'] as String?,
            banner: proveedor['banner'] as String?,
            ubicacion: proveedor['ubicacion'] as String?,
            contacto:
                proveedor['contacto'] != null
                    ? (proveedor['contacto'] as num).toDouble()
                    : null,
            direccion: proveedor['direccion'] as String?,
            categoria: proveedor['categoria'] as String?,
            status: proveedor['status'] as bool? ?? true,
            totalCup: totals['total_cup'] as double,
            totalUsd: totals['total_usd'] as double,
            totalEuro: totals['total_euro'] as double,
            totalCash: totals['total_cash'] as double,
            totalTransfer: totals['total_transfer'] as double,
            netCash: totals['net_cash'] as double,
            netTransfer: totals['net_transfer'] as double,
            totalOrders: totals['total_orders'] as int,
          ),
        );
      }

      suppliers.sort((a, b) => b.totalCup.compareTo(a.totalCup));

      debugPrint('✅ ${suppliers.length} proveedores procesados');
      return suppliers;
    } catch (e) {
      debugPrint('❌ Error en método manual: $e');
      return [];
    }
  }

  /// Obtener detalles de órdenes para un proveedor específico
  static Future<List<OrderPaymentDetail>> getSupplierOrders(
    int proveedorId,
    DateTime fechaInicio,
    DateTime fechaFin,
  ) async {
    try {
      debugPrint('📦 Obteniendo órdenes para proveedor $proveedorId...');

      final response = await _fetchPaymentLines(
        fechaInicio: fechaInicio,
        fechaFin: fechaFin,
        proveedorId: proveedorId,
      );

      final pricingByProvider = await _loadStorePricing({proveedorId});
      final pricing = pricingByProvider[proveedorId] ??
          (cashPct: 0.0, transferPct: 0.0);

      final Map<int, OrderPaymentDetail> ordersMap = {};
      final Map<int, List<ProductPaymentDetail>> orderProductsMap = {};

      for (final item in response) {
        final orderId = _asInt(item['order_id']);
        if (orderId == null) continue;

        final productId = _asInt(item['product_id']) ?? 0;
        final quantity = _asInt(item['quantity']) ?? 0;
        final price = (item['price'] as num?)?.toDouble() ?? 0.0;
        final isTransfer = item['transferencia'] as bool? ?? false;

        final product = ProductPaymentDetail(
          productId: productId,
          productName: item['product_name'] as String? ?? 'Sin nombre',
          productImage: item['product_image'] as String?,
          quantity: quantity,
          price: price,
          subtotal: price * quantity,
        );

        if (!orderProductsMap.containsKey(orderId)) {
          orderProductsMap[orderId] = [];

          ordersMap[orderId] = OrderPaymentDetail(
            orderId: orderId,
            createdAt: _asDate(item['fecha_creacion']) ??
                _asDate(item['fecha_completado']) ??
                DateTime.now(),
            total: 0.0,
            isTransfer: isTransfer,
            cashPct: pricing.cashPct,
            transferPct: pricing.transferPct,
            products: [],
          );
        }

        orderProductsMap[orderId]!.add(product);

        final currentOrder = ordersMap[orderId]!;
        ordersMap[orderId] = OrderPaymentDetail(
          orderId: currentOrder.orderId,
          createdAt: currentOrder.createdAt,
          total: currentOrder.total + product.subtotal,
          isTransfer: isTransfer,
          cashPct: currentOrder.cashPct,
          transferPct: currentOrder.transferPct,
          products: [],
        );
      }

      final List<OrderPaymentDetail> result = [];
      for (final orderId in ordersMap.keys) {
        final orderBase = ordersMap[orderId]!;
        result.add(
          OrderPaymentDetail(
            orderId: orderBase.orderId,
            createdAt: orderBase.createdAt,
            total: orderBase.total,
            isTransfer: orderBase.isTransfer,
            cashPct: orderBase.cashPct,
            transferPct: orderBase.transferPct,
            products: orderProductsMap[orderId]!,
          ),
        );
      }

      result.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      debugPrint('✅ ${result.length} órdenes encontradas');
      return result;
    } catch (e) {
      debugPrint('❌ Error obteniendo órdenes: $e');
      return [];
    }
  }

  /// Órdenes Carnaval creadas en el rango, excluyendo canceladas/devueltas
  /// (Carnaval status y estado actual Inventtia 3/4/5).
  static Future<List<Map<String, dynamic>>> _fetchPaymentLines({
    required DateTime fechaInicio,
    required DateTime fechaFin,
    int? proveedorId,
  }) async {
    final from = _toDateIso(fechaInicio);
    final to = _toDateIso(fechaFin);

    return _fetchPaymentLinesClient(
      fromDate: from,
      toDate: to,
      proveedorId: proveedorId,
    );
  }

  static Future<List<Map<String, dynamic>>> _fetchPaymentLinesClient({
    required String fromDate,
    required String toDate,
    int? proveedorId,
  }) async {
    var query = _supabase
        .schema('carnavalapp')
        .from('OrderDetails')
        .select('''
            order_id,
            proveedor,
            product_id,
            quantity,
            price,
            precio_usd,
            precio_euro,
            transferencia,
            Orders!inner(status, created_at),
            Productos(name, image)
          ''')
        .gte('Orders.created_at', fromDate)
        .lte('Orders.created_at', toDate)
        .not(
          'Orders.status',
          'in',
          '(Cancelado,Cancelada,Devuelto,Devuelta)',
        );

    if (proveedorId != null) {
      query = query.eq('proveedor', proveedorId);
    }

    final details = List<Map<String, dynamic>>.from(await query as List);
    if (details.isEmpty) return [];

    final orderIds =
        details.map((d) => _asInt(d['order_id'])).whereType<int>().toSet();
    final excluded = await _inventtiaExcludedLines(orderIds);

    final result = <Map<String, dynamic>>[];
    for (final detail in details) {
      final orderId = _asInt(detail['order_id']);
      final detailProveedor = _asInt(detail['proveedor']);
      if (orderId == null) continue;

      final isExcluded = excluded.any((e) {
        if (e.orderId != orderId) return false;
        if (e.proveedorId == null || detailProveedor == null) return true;
        return e.proveedorId == detailProveedor;
      });
      if (isExcluded) continue;

      final order = _asMap(detail['Orders']);
      final product = _asMap(detail['Productos']);
      result.add({
        'order_id': orderId,
        'proveedor': detailProveedor,
        'product_id': _asInt(detail['product_id']),
        'product_name': product?['name'] ?? 'Sin nombre',
        'product_image': product?['image'],
        'quantity': _asInt(detail['quantity']) ?? 0,
        'price': (detail['price'] as num?)?.toDouble() ?? 0.0,
        'precio_usd': (detail['precio_usd'] as num?)?.toDouble() ?? 1.0,
        'precio_euro': (detail['precio_euro'] as num?)?.toDouble() ?? 1.0,
        'transferencia': detail['transferencia'] as bool? ?? false,
        'fecha_creacion': order?['created_at'],
      });
    }

    debugPrint('✅ ${result.length} líneas (creadas, no canceladas/devueltas)');
    return result;
  }

  static Future<List<_ExcludedInventtiaLine>> _inventtiaExcludedLines(
    Set<int> orderIds,
  ) async {
    if (orderIds.isEmpty) return [];

    final ops = await _supabase
        .from('app_dat_operaciones')
        .select('id, id_carnaval_order, id_tienda')
        .inFilter('id_carnaval_order', orderIds.toList());

    final opRows = List<Map<String, dynamic>>.from(ops as List);
    if (opRows.isEmpty) return [];

    final opIds =
        opRows.map((r) => _asInt(r['id'])).whereType<int>().toSet();
    final latestByOp = await _latestEstadoByOperacion(opIds);

    final tiendaIds = opRows
        .map((r) => _asInt(r['id_tienda']))
        .whereType<int>()
        .toSet();
    final proveedorByTienda = await _proveedorByTienda(tiendaIds);

    final excluded = <_ExcludedInventtiaLine>[];
    for (final row in opRows) {
      final opId = _asInt(row['id']);
      final orderId = _asInt(row['id_carnaval_order']);
      if (opId == null || orderId == null) continue;

      final latest = latestByOp[opId];
      if (latest == null) continue;
      if (!_estadosExcluidosInventtia.contains(latest.estado)) continue;

      final tiendaId = _asInt(row['id_tienda']);
      excluded.add(
        _ExcludedInventtiaLine(
          orderId: orderId,
          proveedorId: tiendaId != null ? proveedorByTienda[tiendaId] : null,
        ),
      );
    }
    return excluded;
  }

  static Future<Map<int, ({int estado, DateTime createdAt})>>
      _latestEstadoByOperacion(Set<int> operacionIds) async {
    if (operacionIds.isEmpty) return {};

    final rows = await _supabase
        .from('app_dat_estado_operacion')
        .select('id, id_operacion, estado, created_at')
        .inFilter('id_operacion', operacionIds.toList())
        .order('id', ascending: false);

    final latest = <int, ({int estado, DateTime createdAt})>{};
    for (final row in List<Map<String, dynamic>>.from(rows as List)) {
      final opId = _asInt(row['id_operacion']);
      final estado = _asInt(row['estado']);
      final createdAt = _asDate(row['created_at']);
      if (opId == null || estado == null || createdAt == null) continue;
      latest.putIfAbsent(
        opId,
        () => (estado: estado, createdAt: createdAt),
      );
    }
    return latest;
  }

  static Future<Map<int, int>> _proveedorByTienda(Set<int> tiendaIds) async {
    if (tiendaIds.isEmpty) return {};

    final rows = await _supabase
        .from('app_dat_tienda')
        .select('id, id_tienda_carnaval')
        .inFilter('id', tiendaIds.toList());

    final map = <int, int>{};
    for (final row in List<Map<String, dynamic>>.from(rows as List)) {
      final id = _asInt(row['id']);
      final proveedor = _asInt(row['id_tienda_carnaval']);
      if (id != null && proveedor != null) {
        map[id] = proveedor;
      }
    }
    return map;
  }

  /// Obtener estadísticas generales de pagos
  static Future<PaymentStats> getPaymentStats(
    DateTime fechaInicio,
    DateTime fechaFin,
  ) async {
    try {
      final suppliers = await getSupplierPayments(fechaInicio, fechaFin);
      return PaymentStats.fromSuppliers(suppliers);
    } catch (e) {
      debugPrint('❌ Error obteniendo estadísticas: $e');
      return PaymentStats(
        totalCup: 0.0,
        totalUsd: 0.0,
        totalEuro: 0.0,
        totalSuppliers: 0,
        averagePerSupplier: 0.0,
        topSuppliers: [],
      );
    }
  }
}
