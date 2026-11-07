import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/inventtia_payment_model.dart';
import 'referral_payments_service.dart';
import 'supplier_payment_service.dart';

class InventtiaPaymentService {
  static final _supabase = Supabase.instance.client;

  /// % fijo de comisión a agentes sobre ventas de sus tiendas.
  static const double agentCommissionPercentage = 1.0;

  static const _agentSelect =
      'id, nombre, apellidos, activo, inventtia_agente_tiendas(proveedor_id, proveedores(name))';

  static Future<ExchangeRates> getExchangeRates() async {
    try {
      final configResponse = await _supabase
          .schema('carnavalapp')
          .from('configuraciones_admin')
          .select('valor_euro')
          .limit(1)
          .maybeSingle();

      final usdResponse = await _supabase
          .from('tasas_conversion')
          .select('tasa')
          .eq('moneda_origen', 'USD')
          .limit(1)
          .maybeSingle();

      final valorEuro = configResponse != null
          ? (configResponse['valor_euro'] as num?)?.toDouble() ?? 1.0
          : 1.0;

      final valorUsd = usdResponse != null
          ? (usdResponse['tasa'] as num?)?.toDouble() ?? 1.0
          : 1.0;

      return ExchangeRates(valorUsd: valorUsd, valorEuro: valorEuro);
    } catch (e) {
      debugPrint('❌ Error obteniendo tipos de cambio: $e');
      return ExchangeRates(valorUsd: 1.0, valorEuro: 1.0);
    }
  }

  static Future<double> getInventtiaCommissionPercentage() async {
    try {
      final response = await _supabase
          .from('precio_global_productos_carnaval')
          .select('porciento_inventtia')
          .limit(1)
          .maybeSingle();

      if (response == null) return 1.0;
      return (response['porciento_inventtia'] as num?)?.toDouble() ?? 1.0;
    } catch (e) {
      debugPrint('❌ Error obteniendo porcentaje Inventtia: $e');
      return 1.0;
    }
  }

  static Future<bool> updateInventtiaCommissionPercentage(
    double percentage,
  ) async {
    try {
      await _supabase
          .from('precio_global_productos_carnaval')
          .update({
            'porciento_inventtia': percentage,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', 1);
      return true;
    } catch (e) {
      debugPrint('❌ Error actualizando porcentaje Inventtia: $e');
      return false;
    }
  }

  /// Pago a Inventtia = % sobre precio costo (excluye productos de referidos).
  static Future<InventtiaPaymentModel> getInventtiaPayments(
    DateTime fechaInicio,
    DateTime fechaFin,
  ) async {
    try {
      final exchangeRates = await getExchangeRates();
      final commissionPercentage = await getInventtiaCommissionPercentage();
      final commissionDecimal = commissionPercentage / 100.0;
      final excluded =
          await ReferralPaymentsService.getExcludedProductIds();

      final lines = await SupplierPaymentService.getCostPaymentLines(
        fechaInicio: fechaInicio,
        fechaFin: fechaFin,
      );

      final byOrder = <int, _OrderAcc>{};
      double costCup = 0;
      var includedLines = 0;

      for (final line in lines) {
        final productId = _asInt(line['product_id']);
        if (productId != null && excluded.contains(productId)) continue;

        final orderId = _asInt(line['order_id']);
        if (orderId == null) continue;
        final qty = (_asInt(line['quantity']) ?? 0).toDouble();
        final unit = (line['price'] as num?)?.toDouble() ?? 0.0;
        final lineCost = unit * qty;
        costCup += lineCost;
        includedLines++;

        final acc = byOrder.putIfAbsent(orderId, _OrderAcc.new);
        acc.costCup += lineCost;
        acc.linesCount += 1;
        final fecha = line['fecha_creacion'];
        if (fecha != null && acc.createdAt == null) {
          acc.createdAt = DateTime.tryParse(fecha.toString());
        }
      }

      final costUsd =
          exchangeRates.valorUsd > 0 ? costCup / exchangeRates.valorUsd : 0.0;
      final costEuro =
          exchangeRates.valorEuro > 0 ? costCup / exchangeRates.valorEuro : 0.0;

      final commissionCup = costCup * commissionDecimal;
      final commissionUsd = costUsd * commissionDecimal;
      final commissionEuro = costEuro * commissionDecimal;

      final orders = byOrder.entries.map((e) {
        final acc = e.value;
        return OrderDetail(
          orderId: e.key,
          createdAt: acc.createdAt ?? DateTime.now(),
          costCup: acc.costCup,
          commissionCup: acc.costCup * commissionDecimal,
          linesCount: acc.linesCount,
        );
      }).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return InventtiaPaymentModel(
        costBaseCup: costCup,
        costBaseUsd: costUsd,
        costBaseEuro: costEuro,
        commissionUsd: commissionUsd,
        commissionEuro: commissionEuro,
        commissionCup: commissionCup,
        commissionPercentage: commissionPercentage,
        ordersCount: orders.length,
        linesCount: includedLines,
        orders: orders,
      );
    } catch (e) {
      debugPrint('❌ Error obteniendo pagos a Inventtia: $e');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Agentes
  // ---------------------------------------------------------------------------

  static Future<List<Map<String, dynamic>>> getProveedores() async {
    try {
      final rows = await _supabase
          .schema('carnavalapp')
          .from('proveedores')
          .select('id, name')
          .order('name', ascending: true);
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      debugPrint('❌ Error getProveedores: $e');
      return [];
    }
  }

  static Future<List<InventtiaAgent>> getAgents({bool onlyActive = false}) async {
    try {
      final select = _supabase
          .schema('carnavalapp')
          .from('inventtia_agentes')
          .select(_agentSelect);

      final rows = onlyActive
          ? await select.eq('activo', true).order('apellidos', ascending: true)
          : await select.order('apellidos', ascending: true);

      return List<Map<String, dynamic>>.from(rows)
          .map(InventtiaAgent.fromMap)
          .toList();
    } catch (e) {
      debugPrint('❌ Error getAgents: $e');
      return [];
    }
  }

  static Future<void> _replaceAgentTiendas(
    int agenteId,
    List<int> proveedorIds,
  ) async {
    await _supabase
        .schema('carnavalapp')
        .from('inventtia_agente_tiendas')
        .delete()
        .eq('agente_id', agenteId);

    final unique = proveedorIds.toSet().toList();
    if (unique.isEmpty) return;

    await _supabase.schema('carnavalapp').from('inventtia_agente_tiendas').insert(
      unique
          .map((pid) => {'agente_id': agenteId, 'proveedor_id': pid})
          .toList(),
    );
  }

  static Future<InventtiaAgent> createAgent({
    required String nombre,
    required String apellidos,
    required List<int> proveedorIds,
  }) async {
    if (proveedorIds.isEmpty) {
      throw ArgumentError('El agente debe tener al menos una tienda');
    }

    final row = await _supabase
        .schema('carnavalapp')
        .from('inventtia_agentes')
        .insert({
          'nombre': nombre.trim(),
          'apellidos': apellidos.trim(),
          'activo': true,
        })
        .select('id')
        .single();

    final id = (row['id'] as num).toInt();
    await _replaceAgentTiendas(id, proveedorIds);

    final full = await _supabase
        .schema('carnavalapp')
        .from('inventtia_agentes')
        .select(_agentSelect)
        .eq('id', id)
        .single();
    return InventtiaAgent.fromMap(Map<String, dynamic>.from(full));
  }

  static Future<InventtiaAgent> updateAgent({
    required int id,
    required String nombre,
    required String apellidos,
    required List<int> proveedorIds,
    required bool activo,
  }) async {
    if (proveedorIds.isEmpty) {
      throw ArgumentError('El agente debe tener al menos una tienda');
    }

    await _supabase
        .schema('carnavalapp')
        .from('inventtia_agentes')
        .update({
          'nombre': nombre.trim(),
          'apellidos': apellidos.trim(),
          'activo': activo,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id);

    await _replaceAgentTiendas(id, proveedorIds);

    final full = await _supabase
        .schema('carnavalapp')
        .from('inventtia_agentes')
        .select(_agentSelect)
        .eq('id', id)
        .single();
    return InventtiaAgent.fromMap(Map<String, dynamic>.from(full));
  }

  static Future<void> deleteAgent(int id) async {
    await _supabase
        .schema('carnavalapp')
        .from('inventtia_agentes')
        .delete()
        .eq('id', id);
  }

  /// Ventas en CUP por proveedor. [elegible] ya resta los productos excluidos.
  static Future<({Map<int, double> elegible, Map<int, double> excluido})>
      salesCupByProveedor(
    DateTime from,
    DateTime to,
  ) async {
    final excluded = await ReferralPaymentsService.getExcludedProductIds();
    final sales = await _salesByProveedor(
      from,
      to,
      excludedProductIds: excluded,
    );
    return (
      elegible: sales.map((id, store) => MapEntry(id, store.salesCup)),
      excluido: sales.map((id, store) => MapEntry(id, store.excludedCup)),
    );
  }

  /// Ventas Carnaval por proveedor (sin canceladas ni productos excluidos).
  static Future<Map<int, _StoreSales>> _salesByProveedor(
    DateTime from,
    DateTime to, {
    required Set<int> excludedProductIds,
  }) async {
    final fromStr = _toDateIso(from);
    final toStr = _toDateIso(to);

    final rows = await _supabase
        .schema('carnavalapp')
        .from('OrderDetails')
        .select('''
            order_id,
            product_id,
            proveedor,
            quantity,
            price,
            Orders!inner(status, created_at)
          ''')
        .gte('Orders.created_at', fromStr)
        .lte('Orders.created_at', toStr)
        .not('Orders.status', 'in', '(Cancelado,Cancelada,Devuelto,Devuelta)');

    final result = <int, _StoreSales>{};
    for (final r in List<Map<String, dynamic>>.from(rows as List)) {
      final proveedorId = _asInt(r['proveedor']);
      if (proveedorId == null) continue;

      final qty = (_asInt(r['quantity']) ?? 0).toDouble();
      final price = (r['price'] as num?)?.toDouble() ?? 0.0;
      final lineSales = qty * price;
      final productId = _asInt(r['product_id']);
      final store = result.putIfAbsent(proveedorId, _StoreSales.new);
      if (productId != null && excludedProductIds.contains(productId)) {
        store.excludedCup += lineSales;
        continue;
      }

      final orderId = _asInt(r['order_id']);
      store.salesCup += lineSales;

      if (orderId != null) {
        final orderAcc = store.orders.putIfAbsent(orderId, _OrderSales.new);
        orderAcc.salesCup += lineSales;
        final orderMap = r['Orders'];
        if (orderMap is Map && orderAcc.createdAt == null) {
          orderAcc.createdAt =
              DateTime.tryParse(orderMap['created_at']?.toString() ?? '');
        }
      }
    }
    return result;
  }

  /// Comisión = 1% de la suma de ventas de todas las tiendas del agente.
  static Future<List<AgentPaymentSummary>> getAgentPayments(
    DateTime fechaInicio,
    DateTime fechaFin,
  ) async {
    final agents = await getAgents(onlyActive: true);
    if (agents.isEmpty) return [];

    final rates = await getExchangeRates();
    final excluded = await ReferralPaymentsService.getExcludedProductIds();
    final sales = await _salesByProveedor(
      fechaInicio,
      fechaFin,
      excludedProductIds: excluded,
    );
    final pct = agentCommissionPercentage / 100.0;

    final nameByProveedor = <int, String>{};
    for (final a in agents) {
      for (final t in a.tiendas) {
        if (t.name != null) nameByProveedor[t.proveedorId] = t.name!;
      }
    }

    final list = <AgentPaymentSummary>[];
    for (final agent in agents) {
      final breakdowns = <AgentStoreBreakdown>[];
      double salesCup = 0;

      for (final tienda in agent.tiendas) {
        final store = sales[tienda.proveedorId];
        final storeSales = store?.salesCup ?? 0.0;
        salesCup += storeSales;

        final orders = (store?.orders.entries.toList() ?? [])
          ..sort((a, b) {
            final da = a.value.createdAt;
            final db = b.value.createdAt;
            if (da == null && db == null) return b.key.compareTo(a.key);
            if (da == null) return 1;
            if (db == null) return -1;
            return db.compareTo(da);
          });

        breakdowns.add(
          AgentStoreBreakdown(
            proveedorId: tienda.proveedorId,
            proveedorName:
                tienda.name ?? nameByProveedor[tienda.proveedorId],
            salesCup: storeSales,
            commissionCup: storeSales * pct,
            orders: orders
                .map(
                  (e) => AgentOrderSummary(
                    orderId: e.key,
                    createdAt: e.value.createdAt,
                    salesCup: e.value.salesCup,
                    commissionCup: e.value.salesCup * pct,
                  ),
                )
                .toList(),
          ),
        );
      }

      breakdowns.sort((a, b) => b.commissionCup.compareTo(a.commissionCup));

      final commissionCup = salesCup * pct;
      list.add(
        AgentPaymentSummary(
          agent: agent,
          salesCup: salesCup,
          commissionCup: commissionCup,
          commissionUsd:
              rates.valorUsd > 0 ? commissionCup / rates.valorUsd : 0.0,
          commissionEuro:
              rates.valorEuro > 0 ? commissionCup / rates.valorEuro : 0.0,
          commissionPercentage: agentCommissionPercentage,
          byStore: breakdowns,
        ),
      );
    }

    list.sort((a, b) => b.commissionCup.compareTo(a.commissionCup));
    return list;
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static String _toDateIso(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    final y = day.year.toString().padLeft(4, '0');
    final m = day.month.toString().padLeft(2, '0');
    final dd = day.day.toString().padLeft(2, '0');
    return '$y-$m-$dd';
  }
}

class _OrderAcc {
  double costCup = 0;
  int linesCount = 0;
  DateTime? createdAt;
}

class _StoreSales {
  double salesCup = 0;
  double excludedCup = 0;
  final Map<int, _OrderSales> orders = {};
}

class _OrderSales {
  double salesCup = 0;
  DateTime? createdAt;
}
