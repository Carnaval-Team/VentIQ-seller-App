import 'package:supabase_flutter/supabase_flutter.dart';

class ReferralPaymentsService {
  static final _supabase = Supabase.instance.client;

  /// Obtiene valor_usd y valor_euro desde configuraciones_admin (última fila)
  static Future<Map<String, double>> getCurrencyRates() async {
    try {
      final rows = await _supabase
          .schema('carnavalapp')
          .from('configuraciones_admin')
          .select('valor_usd, valor_euro')
          .order('id', ascending: false)
          .limit(1);
      if (rows.isEmpty) {
        return {'usd': 1.0, 'euro': 1.0};
      }
      final row = rows.first;
      final usd = (row['valor_usd'] as num?)?.toDouble() ?? 1.0;
      final euro = (row['valor_euro'] as num?)?.toDouble() ?? 1.0;
      return {
        'usd': usd <= 0 ? 1.0 : usd,
        'euro': euro <= 0 ? 1.0 : euro,
      };
    } catch (e) {
      print('❌ Error getCurrencyRates: $e');
      return {'usd': 1.0, 'euro': 1.0};
    }
  }

  /// Obtiene todos los referidores (Usuarios con referal_code != null)
  static Future<List<Map<String, dynamic>>> getReferrers() async {
    try {
      final response = await _supabase
          .schema('carnavalapp')
          .from('Usuarios')
          .select('id, name, email, telefono, referal_code, prefered_currency')
          .not('referal_code', 'is', null)
          .order('name', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error getReferrers: $e');
      return [];
    }
  }

  /// Cuenta usuarios referidos por un codigo (referal_from = code)
  static Future<int> countReferredUsers(String referalCode) async {
    try {
      final response = await _supabase
          .schema('carnavalapp')
          .from('Usuarios')
          .select('id')
          .eq('referal_from', referalCode);
      return (response as List).length;
    } catch (e) {
      print('❌ Error countReferredUsers($referalCode): $e');
      return 0;
    }
  }

  /// Conteo de referidos por código en una sola consulta.
  static Future<Map<String, int>> countReferredUsersByCode() async {
    try {
      final rows = await _supabase
          .schema('carnavalapp')
          .from('Usuarios')
          .select('referal_from')
          .not('referal_from', 'is', null);
      final counts = <String, int>{};
      for (final r in List<Map<String, dynamic>>.from(rows)) {
        final code = (r['referal_from'] as String?)?.trim();
        if (code == null || code.isEmpty) continue;
        counts[code] = (counts[code] ?? 0) + 1;
      }
      return counts;
    } catch (e) {
      print('❌ Error countReferredUsersByCode: $e');
      return {};
    }
  }

  /// Obtiene ordenes asociadas a un codigo de referido en un rango de fecha.
  /// Solo incluye órdenes Completado (las efectivamente cobradas).
  static Future<List<Map<String, dynamic>>> getOrdersByReferralCode({
    required String referalCode,
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final fromStr = _formatDate(from);
      final toExclusive =
          DateTime(to.year, to.month, to.day).add(const Duration(days: 1));
      final toStr = _formatDate(toExclusive);

      final response = await _supabase
          .schema('carnavalapp')
          .from('Orders')
          .select(
            'id, created_at, total, "totalUsd", "totalEuro", metodo_pago, moneda, status, user_id, referal_code',
          )
          .eq('referal_code', referalCode)
          .eq('status', 'Completado')
          .gte('created_at', fromStr)
          .lt('created_at', toStr)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response)
          .where(isCompletedOrder)
          .toList();
    } catch (e) {
      print('❌ Error getOrdersByReferralCode($referalCode): $e');
      return [];
    }
  }

  /// Todas las órdenes Completado con referal_code en el rango (paginado).
  static Future<List<Map<String, dynamic>>> getCompletedReferralOrdersInRange({
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final fromStr = _formatDate(from);
      final toExclusive =
          DateTime(to.year, to.month, to.day).add(const Duration(days: 1));
      final toStr = _formatDate(toExclusive);

      const pageSize = 1000;
      final all = <Map<String, dynamic>>[];
      var offset = 0;

      while (true) {
        final rows = await _supabase
            .schema('carnavalapp')
            .from('Orders')
            .select(
              'id, created_at, total, "totalUsd", "totalEuro", metodo_pago, moneda, status, user_id, referal_code',
            )
            .eq('status', 'Completado')
            .not('referal_code', 'is', null)
            .gte('created_at', fromStr)
            .lt('created_at', toStr)
            .order('created_at', ascending: false)
            .range(offset, offset + pageSize - 1);

        final page = List<Map<String, dynamic>>.from(rows)
            .where(isCompletedOrder)
            .toList();
        all.addAll(page);
        if (page.length < pageSize) break;
        offset += pageSize;
      }

      return all;
    } catch (e) {
      print('❌ Error getCompletedReferralOrdersInRange: $e');
      return [];
    }
  }

  /// Carga dashboard: referidores + conteos + órdenes enriquecidas.
  /// De ~2N+2 requests a ~4–6 independientes del nº de referidores.
  /// Si [valorUsd]/[valorEuro] son null, carga tasas en paralelo.
  static Future<ReferralDashboardResult> loadReferrerDashboard({
    required DateTime from,
    required DateTime to,
    required double pctNacional,
    required double pctInternacional,
    double? valorUsd,
    double? valorEuro,
  }) async {
    final needRates = valorUsd == null || valorEuro == null;
    final parallel = await Future.wait([
      getReferrers(),
      getExcludedProductIds(),
      countReferredUsersByCode(),
      getCompletedReferralOrdersInRange(from: from, to: to),
      if (needRates) getCurrencyRates(),
    ]);

    final referrers = parallel[0] as List<Map<String, dynamic>>;
    final excludedIds = parallel[1] as Set<int>;
    final referredCounts = parallel[2] as Map<String, int>;
    final allOrders = parallel[3] as List<Map<String, dynamic>>;
    final rates = needRates
        ? parallel[4] as Map<String, double>
        : <String, double>{
            'usd': valorUsd!,
            'euro': valorEuro!,
          };
    final usd = rates['usd'] ?? 1.0;
    final euro = rates['euro'] ?? 1.0;

    final enrichedAll = await enrichOrdersWithEligibleTotals(
      allOrders,
      excludedProductIds: excludedIds,
    );

    final ordersByCode = <String, List<Map<String, dynamic>>>{};
    for (final o in enrichedAll) {
      final code = (o['referal_code'] as String?)?.trim();
      if (code == null || code.isEmpty) continue;
      ordersByCode.putIfAbsent(code, () => []).add(o);
    }

    final rows = <ReferralReferrerData>[];
    for (final u in referrers) {
      final code = (u['referal_code'] as String?)?.trim();
      if (code == null || code.isEmpty) continue;
      final orders = ordersByCode[code] ?? const <Map<String, dynamic>>[];
      final summary = computeSummary(
        orders: orders,
        pctNacional: pctNacional,
        pctInternacional: pctInternacional,
        valorUsd: usd,
        valorEuro: euro,
      );
      rows.add(ReferralReferrerData(
        user: u,
        referralCode: code,
        referredCount: referredCounts[code] ?? 0,
        summary: summary,
        orders: orders,
      ));
    }

    rows.sort((a, b) {
      final byAmount = b.summary.comisionCup.compareTo(a.summary.comisionCup);
      if (byAmount != 0) return byAmount;
      return b.referredCount.compareTo(a.referredCount);
    });

    return ReferralDashboardResult(
      referrers: rows,
      excludedProductIds: excludedIds,
      valorUsd: usd,
      valorEuro: euro,
    );
  }

  /// True solo para órdenes efectivamente cobradas (comisionables).
  static bool isCompletedOrder(Map<String, dynamic> order) {
    final status = (order['status'] as String? ?? '').trim();
    return status.toLowerCase() == 'completado';
  }

  /// Clasifica una orden como nacional o internacional segun reglas:
  /// - Efectivo + CUP => Nacional
  /// - Efectivo + USD/EUR => Internacional
  /// - Transferencia => Nacional (sin importar moneda)
  /// - Tropipay / Stripe => Internacional
  static bool isInternationalOrder(Map<String, dynamic> order) {
    final metodo = (order['metodo_pago'] as String? ?? '').toLowerCase().trim();
    final moneda = (order['moneda'] as String? ?? 'CUP').toUpperCase().trim();

    if (metodo.contains('tropipay') || metodo.contains('stripe')) {
      return true;
    }
    if (metodo.contains('transferencia')) {
      return false;
    }
    if (metodo.contains('efectivo')) {
      if (moneda == 'CUP') return false;
      if (moneda == 'USD' || moneda == 'EUR' || moneda == 'EURO') return true;
    }
    // Por defecto, si moneda no es CUP, lo tratamos como internacional
    return moneda != 'CUP';
  }

  // ---------------------------------------------------------------------------
  // Exclusiones de productos (no acumulan para pago a referidos)
  // ---------------------------------------------------------------------------

  static Future<Set<int>> getExcludedProductIds() async {
    try {
      final rows = await _supabase
          .schema('carnavalapp')
          .from('referral_excluded_products')
          .select('product_id');
      return List<Map<String, dynamic>>.from(rows)
          .map((r) => (r['product_id'] as num?)?.toInt())
          .whereType<int>()
          .toSet();
    } catch (e) {
      print('❌ Error getExcludedProductIds: $e');
      return {};
    }
  }

  static Future<List<Map<String, dynamic>>> getExcludedProducts() async {
    try {
      final rows = await _supabase
          .schema('carnavalapp')
          .from('referral_excluded_products')
          .select('product_id, created_at, note, Productos(id, name)')
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(rows).map((r) {
        final product = r['Productos'];
        final name = product is Map
            ? (product['name'] as String? ?? 'Producto #${r['product_id']}')
            : 'Producto #${r['product_id']}';
        return {
          'product_id': r['product_id'],
          'created_at': r['created_at'],
          'note': r['note'],
          'name': name,
        };
      }).toList();
    } catch (e) {
      print('❌ Error getExcludedProducts: $e');
      return [];
    }
  }

  static Future<void> addExcludedProduct(int productId, {String? note}) async {
    await _supabase.schema('carnavalapp').from('referral_excluded_products').upsert({
      'product_id': productId,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
  }

  static Future<void> removeExcludedProduct(int productId) async {
    await _supabase
        .schema('carnavalapp')
        .from('referral_excluded_products')
        .delete()
        .eq('product_id', productId);
  }

  static Future<List<Map<String, dynamic>>> searchProducts(String query) async {
    try {
      final q = query.trim();
      if (q.isEmpty) {
        final rows = await _supabase
            .schema('carnavalapp')
            .from('Productos')
            .select('id, name')
            .order('name', ascending: true)
            .limit(40);
        return List<Map<String, dynamic>>.from(rows);
      }
      final rows = await _supabase
          .schema('carnavalapp')
          .from('Productos')
          .select('id, name')
          .ilike('name', '%$q%')
          .order('name', ascending: true)
          .limit(40);
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      print('❌ Error searchProducts: $e');
      return [];
    }
  }

  /// Líneas de una orden con flag de exclusión e importes.
  static Future<List<ReferralOrderLine>> getOrderLines(
    int orderId, {
    Set<int>? excludedProductIds,
  }) async {
    try {
      final excluded = excludedProductIds ?? await getExcludedProductIds();
      final rows = await _supabase
          .schema('carnavalapp')
          .from('OrderDetails')
          .select(
            'id, order_id, product_id, quantity, price, precio_usd, precio_euro, extra, Productos(name)',
          )
          .eq('order_id', orderId);

      return List<Map<String, dynamic>>.from(rows).map((r) {
        final productId = (r['product_id'] as num?)?.toInt();
        final qty = (r['quantity'] as num?)?.toDouble() ?? 0;
        final price = (r['price'] as num?)?.toDouble() ?? 0;
        final priceUsd = (r['precio_usd'] as num?)?.toDouble() ?? 0;
        final priceEuro = (r['precio_euro'] as num?)?.toDouble() ?? 0;
        final extra = (r['extra'] as num?)?.toDouble() ?? 0;
        final product = r['Productos'];
        final name = product is Map
            ? (product['name'] as String? ?? 'Producto #${productId ?? '?'}')
            : 'Producto #${productId ?? '?'}';
        final isExcluded =
            productId != null && excluded.contains(productId);
        return ReferralOrderLine(
          id: (r['id'] as num?)?.toInt() ?? 0,
          orderId: orderId,
          productId: productId,
          productName: name,
          quantity: qty,
          unitPriceCup: price,
          unitPriceUsd: priceUsd,
          unitPriceEuro: priceEuro,
          extra: extra,
          lineCup: qty * price + extra,
          lineUsd: qty * priceUsd,
          lineEuro: qty * priceEuro,
          isExcluded: isExcluded,
        );
      }).toList();
    } catch (e) {
      print('❌ Error getOrderLines($orderId): $e');
      return [];
    }
  }

  /// Resta del total de cada orden el importe de líneas con productos excluidos.
  /// Deja `_eligible_total*` para [computeSummary] y el listado.
  static Future<List<Map<String, dynamic>>> enrichOrdersWithEligibleTotals(
    List<Map<String, dynamic>> orders, {
    Set<int>? excludedProductIds,
  }) async {
    if (orders.isEmpty) return orders;

    final excluded = excludedProductIds ?? await getExcludedProductIds();
    if (excluded.isEmpty) {
      return orders.map((o) {
        final total = (o['total'] as num?)?.toDouble() ?? 0;
        final tUsd = (o['totalUsd'] as num?)?.toDouble() ?? 0;
        final tEuro = (o['totalEuro'] as num?)?.toDouble() ?? 0;
        return {
          ...o,
          '_eligible_total': total,
          '_eligible_totalUsd': tUsd,
          '_eligible_totalEuro': tEuro,
          '_excluded_cup': 0.0,
          '_excluded_usd': 0.0,
          '_excluded_euro': 0.0,
          '_has_exclusions': false,
        };
      }).toList();
    }

    final orderIds = orders
        .map((o) => (o['id'] as num?)?.toInt())
        .whereType<int>()
        .toList();
    if (orderIds.isEmpty) return orders;

    // Solo líneas de productos excluidos (payload mucho menor).
    final excludedList = excluded.toList();
    final details = <Map<String, dynamic>>[];
    const chunkSize = 200;
    for (var i = 0; i < orderIds.length; i += chunkSize) {
      final end =
          i + chunkSize > orderIds.length ? orderIds.length : i + chunkSize;
      final chunk = orderIds.sublist(i, end);
      try {
        final rows = await _supabase
            .schema('carnavalapp')
            .from('OrderDetails')
            .select(
              'order_id, product_id, quantity, price, precio_usd, precio_euro, extra',
            )
            .inFilter('order_id', chunk)
            .inFilter('product_id', excludedList);
        details.addAll(List<Map<String, dynamic>>.from(rows));
      } catch (e) {
        print('❌ Error enrichOrders chunk: $e');
      }
    }

    final exclByOrder = <int, _ExcludedAmounts>{};
    for (final d in details) {
      final orderId = (d['order_id'] as num?)?.toInt();
      final productId = (d['product_id'] as num?)?.toInt();
      if (orderId == null || productId == null) continue;
      if (!excluded.contains(productId)) continue;

      final qty = (d['quantity'] as num?)?.toDouble() ?? 0;
      final price = (d['price'] as num?)?.toDouble() ?? 0;
      final priceUsd = (d['precio_usd'] as num?)?.toDouble() ?? 0;
      final priceEuro = (d['precio_euro'] as num?)?.toDouble() ?? 0;
      final extra = (d['extra'] as num?)?.toDouble() ?? 0;

      final acc = exclByOrder.putIfAbsent(orderId, _ExcludedAmounts.new);
      acc.cup += qty * price + extra;
      acc.usd += qty * priceUsd;
      acc.euro += qty * priceEuro;
    }

    return orders.map((o) {
      final orderId = (o['id'] as num?)?.toInt();
      final excl = orderId != null
          ? (exclByOrder[orderId] ?? _ExcludedAmounts())
          : _ExcludedAmounts();
      final total = (o['total'] as num?)?.toDouble() ?? 0;
      final tUsd = (o['totalUsd'] as num?)?.toDouble() ?? 0;
      final tEuro = (o['totalEuro'] as num?)?.toDouble() ?? 0;
      final eligibleCup = (total - excl.cup).clamp(0.0, double.infinity);
      final eligibleUsd = (tUsd - excl.usd).clamp(0.0, double.infinity);
      final eligibleEuro = (tEuro - excl.euro).clamp(0.0, double.infinity);
      return {
        ...o,
        '_eligible_total': eligibleCup,
        '_eligible_totalUsd': eligibleUsd,
        '_eligible_totalEuro': eligibleEuro,
        '_excluded_cup': excl.cup,
        '_excluded_usd': excl.usd,
        '_excluded_euro': excl.euro,
        '_has_exclusions': excl.cup > 0 || excl.usd > 0 || excl.euro > 0,
      };
    }).toList();
  }

  /// Calcula totales y comisiones para un referidor.
  /// Usa `_eligible_total*` si existen (tras restar productos excluidos).
  static ReferralSummary computeSummary({
    required List<Map<String, dynamic>> orders,
    required double pctNacional,
    required double pctInternacional,
    required double valorUsd,
    required double valorEuro,
  }) {
    double totalCup = 0;
    double totalUsd = 0;
    double totalEuro = 0;
    int nacionalCount = 0;
    int internacionalCount = 0;

    double comisionCup = 0;
    double comisionUsd = 0;
    double comisionEuro = 0;

    for (final o in orders) {
      if (!isCompletedOrder(o)) continue;

      final total = (o['_eligible_total'] as num?)?.toDouble() ??
          (o['total'] as num?)?.toDouble() ??
          0;
      final tUsd = (o['_eligible_totalUsd'] as num?)?.toDouble() ??
          (o['totalUsd'] as num?)?.toDouble() ??
          0;
      final tEuro = (o['_eligible_totalEuro'] as num?)?.toDouble() ??
          (o['totalEuro'] as num?)?.toDouble() ??
          0;

      totalCup += total;
      totalUsd += tUsd;
      totalEuro += tEuro;

      final isIntl = isInternationalOrder(o);
      final pct = (isIntl ? pctInternacional : pctNacional) / 100.0;

      if (isIntl) {
        internacionalCount++;
      } else {
        nacionalCount++;
      }

      comisionCup += total * pct;
      comisionUsd += tUsd * pct;
      comisionEuro += tEuro * pct;
    }

    // Conversion final del total referido (CUP) a USD y EUR usando tasas
    final totalRefUsdFromCup = valorUsd > 0 ? comisionCup / valorUsd : 0;
    final totalRefEurFromCup = valorEuro > 0 ? comisionCup / valorEuro : 0;

    return ReferralSummary(
      totalCup: totalCup,
      totalUsd: totalUsd,
      totalEuro: totalEuro,
      nacionalCount: nacionalCount,
      internacionalCount: internacionalCount,
      comisionCup: comisionCup,
      comisionUsd: comisionUsd,
      comisionEuro: comisionEuro,
      totalReferidoUsd: totalRefUsdFromCup.toDouble(),
      totalReferidoEuro: totalRefEurFromCup.toDouble(),
    );
  }

  static String _formatDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }
}

class _ExcludedAmounts {
  double cup = 0;
  double usd = 0;
  double euro = 0;
}

class ReferralOrderLine {
  final int id;
  final int orderId;
  final int? productId;
  final String productName;
  final double quantity;
  final double unitPriceCup;
  final double unitPriceUsd;
  final double unitPriceEuro;
  final double extra;
  final double lineCup;
  final double lineUsd;
  final double lineEuro;
  final bool isExcluded;

  const ReferralOrderLine({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPriceCup,
    required this.unitPriceUsd,
    required this.unitPriceEuro,
    required this.extra,
    required this.lineCup,
    required this.lineUsd,
    required this.lineEuro,
    required this.isExcluded,
  });
}

class ReferralSummary {
  final double totalCup;
  final double totalUsd;
  final double totalEuro;
  final int nacionalCount;
  final int internacionalCount;
  final double comisionCup;
  final double comisionUsd;
  final double comisionEuro;
  // Comision total convertida desde CUP usando las tasas
  final double totalReferidoUsd;
  final double totalReferidoEuro;

  ReferralSummary({
    required this.totalCup,
    required this.totalUsd,
    required this.totalEuro,
    required this.nacionalCount,
    required this.internacionalCount,
    required this.comisionCup,
    required this.comisionUsd,
    required this.comisionEuro,
    required this.totalReferidoUsd,
    required this.totalReferidoEuro,
  });

  int get totalOrders => nacionalCount + internacionalCount;
}

class ReferralReferrerData {
  final Map<String, dynamic> user;
  final String referralCode;
  final int referredCount;
  final ReferralSummary summary;
  final List<Map<String, dynamic>> orders;

  const ReferralReferrerData({
    required this.user,
    required this.referralCode,
    required this.referredCount,
    required this.summary,
    required this.orders,
  });
}

class ReferralDashboardResult {
  final List<ReferralReferrerData> referrers;
  final Set<int> excludedProductIds;
  final double valorUsd;
  final double valorEuro;

  const ReferralDashboardResult({
    required this.referrers,
    required this.excludedProductIds,
    required this.valorUsd,
    required this.valorEuro,
  });
}
