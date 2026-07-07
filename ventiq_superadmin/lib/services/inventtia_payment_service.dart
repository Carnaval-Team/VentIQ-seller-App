import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/inventtia_payment_model.dart';

class InventtiaPaymentService {
  static final _supabase = Supabase.instance.client;

  /// Obtener tipos de cambio desde configuraciones_admin y tasas_conversion
  static Future<ExchangeRates> getExchangeRates() async {
    try {
      // Obtener EUR desde configuraciones_admin
      final configResponse =
          await _supabase
              .schema('carnavalapp')
              .from('configuraciones_admin')
              .select('valor_euro')
              .limit(1)
              .maybeSingle();

      // Obtener USD desde tasas_conversion
      final usdResponse =
          await _supabase
              .from('tasas_conversion')
              .select('tasa')
              .eq('moneda_origen', 'USD')
              .limit(1)
              .maybeSingle();

      final valorEuro =
          configResponse != null
              ? (configResponse['valor_euro'] as num?)?.toDouble() ?? 1.0
              : 1.0;

      final valorUsd =
          usdResponse != null
              ? (usdResponse['tasa'] as num?)?.toDouble() ?? 1.0
              : 1.0;

      debugPrint(
        '✅ Tipos de cambio: USD=$valorUsd (tasas_conversion), EUR=$valorEuro (config_admin)',
      );
      return ExchangeRates(valorUsd: valorUsd, valorEuro: valorEuro);
    } catch (e) {
      debugPrint('❌ Error obteniendo tipos de cambio: $e');
      return ExchangeRates(valorUsd: 1.0, valorEuro: 1.0);
    }
  }

  /// Obtener porcentaje de comisión para Inventtia desde precio_global_productos_carnaval
  static Future<double> getInventtiaCommissionPercentage() async {
    try {
      final response =
          await _supabase
              .from('precio_global_productos_carnaval')
              .select('porciento_inventtia')
              .limit(1)
              .maybeSingle();

      if (response == null) {
        debugPrint(
          '⚠️ No se encontró porcentaje de Inventtia, usando 1% por defecto',
        );
        return 1.0;
      }

      final percentage =
          (response['porciento_inventtia'] as num?)?.toDouble() ?? 1.0;
      debugPrint('✅ Porcentaje Inventtia: $percentage%');
      return percentage;
    } catch (e) {
      debugPrint('❌ Error obteniendo porcentaje Inventtia: $e');
      return 1.0;
    }
  }

  /// Actualizar porcentaje de comisión para Inventtia
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
      debugPrint('✅ Porcentaje Inventtia actualizado a $percentage%');
      return true;
    } catch (e) {
      debugPrint('❌ Error actualizando porcentaje Inventtia: $e');
      return false;
    }
  }

  /// Obtener reporte de pagos a Inventtia
  static Future<InventtiaPaymentModel> getInventtiaPayments(
    DateTime fechaInicio,
    DateTime fechaFin,
  ) async {
    try {
      debugPrint('💰 Obteniendo pagos a Inventtia...');
      debugPrint(
        '📅 Rango: ${fechaInicio.toIso8601String()} - ${fechaFin.toIso8601String()}',
      );

      // Obtener tipos de cambio y porcentaje de comisión
      final exchangeRates = await getExchangeRates();
      final commissionPercentage = await getInventtiaCommissionPercentage();
      final commissionDecimal =
          commissionPercentage / 100; // Convertir % a decimal

      // Consultar órdenes que cumplan los criterios
      final ordersResponse = await _supabase
          .schema('carnavalapp')
          .from('Orders')
          .select(
            'id, created_at, total, totalUsd, totalEuro, moneda, metodo_pago, status',
          )
          .inFilter('metodo_pago', ['Stripe', 'Tropipay'])
          .inFilter('status', ['Entregando', 'Completado', 'Asignado'])
          .gte('created_at', fechaInicio.toIso8601String())
          .lte('created_at', fechaFin.toIso8601String())
          .order('created_at', ascending: false);

      debugPrint('📦 ${ordersResponse.length} órdenes encontradas');

      double totalUsd = 0.0;
      double totalEuro = 0.0;
      final List<OrderDetail> orders = [];

      for (var order in ordersResponse) {
        final moneda = (order['moneda'] as String?)?.toUpperCase() ?? 'CUP';
        final metodoPago = order['metodo_pago'] as String? ?? '';
        final status = order['status'] as String? ?? '';

        double totalInCurrency = 0.0;
        double totalOriginal = 0.0;

        if (moneda == 'USD') {
          totalInCurrency = (order['totalUsd'] as num?)?.toDouble() ?? 0.0;
          totalOriginal = totalInCurrency;
          totalUsd += totalInCurrency;
        } else if (moneda == 'EUR') {
          totalInCurrency = (order['totalEuro'] as num?)?.toDouble() ?? 0.0;
          totalOriginal = totalInCurrency;
          totalEuro += totalInCurrency;
        } else {
          // Si no es USD ni EUR, asumimos que es CUP pero no lo contamos
          totalOriginal = (order['total'] as num?)?.toDouble() ?? 0.0;
          continue;
        }

        final createdAtStr = order['created_at'] as String?;
        final createdAt =
            createdAtStr != null
                ? DateTime.parse(createdAtStr)
                : DateTime.now();

        orders.add(
          OrderDetail(
            orderId: order['id'] as int,
            createdAt: createdAt,
            moneda: moneda,
            totalOriginal: totalOriginal,
            totalInCurrency: totalInCurrency,
            metodoPago: metodoPago,
            status: status,
          ),
        );
      }

      // Calcular comisión con el porcentaje variable
      final commissionUsd = totalUsd * commissionDecimal;
      final commissionEuro = totalEuro * commissionDecimal;

      // Convertir a CUP
      final totalCup =
          (totalUsd * exchangeRates.valorUsd) +
          (totalEuro * exchangeRates.valorEuro);
      final commissionCup =
          (commissionUsd * exchangeRates.valorUsd) +
          (commissionEuro * exchangeRates.valorEuro);

      debugPrint('✅ Total USD: \$${totalUsd.toStringAsFixed(2)}');
      debugPrint('✅ Total EUR: €${totalEuro.toStringAsFixed(2)}');
      debugPrint('✅ Comisión USD: \$${commissionUsd.toStringAsFixed(2)}');
      debugPrint('✅ Comisión EUR: €${commissionEuro.toStringAsFixed(2)}');
      debugPrint('✅ Comisión CUP: \$${commissionCup.toStringAsFixed(2)}');

      return InventtiaPaymentModel(
        totalUsd: totalUsd,
        totalEuro: totalEuro,
        totalCup: totalCup,
        commissionUsd: commissionUsd,
        commissionEuro: commissionEuro,
        commissionCup: commissionCup,
        commissionPercentage: commissionPercentage,
        ordersCount: orders.length,
        orders: orders,
      );
    } catch (e) {
      debugPrint('❌ Error obteniendo pagos a Inventtia: $e');
      rethrow;
    }
  }
}
