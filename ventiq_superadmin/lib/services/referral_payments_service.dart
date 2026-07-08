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

  /// Obtiene ordenes asociadas a un codigo de referido en un rango de fecha.
  /// Solo incluye órdenes Completado (las efectivamente cobradas).
  static Future<List<Map<String, dynamic>>> getOrdersByReferralCode({
    required String referalCode,
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final fromStr = _formatDate(from);
      // Incluir el día completo hasta 23:59:59
      final toExclusive = DateTime(to.year, to.month, to.day)
          .add(const Duration(days: 1));
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
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error getOrdersByReferralCode($referalCode): $e');
      return [];
    }
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

  /// Calcula totales y comisiones para un referidor
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
      final total = (o['total'] as num?)?.toDouble() ?? 0;
      final tUsd = (o['totalUsd'] as num?)?.toDouble() ?? 0;
      final tEuro = (o['totalEuro'] as num?)?.toDouble() ?? 0;

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
