import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/app_colors.dart';

class SalesTotalsSummary extends StatelessWidget {
  final double ventas;
  final double costo;
  final double ganancia;
  final bool showProfit;
  final String? currency;

  const SalesTotalsSummary({
    super.key,
    required this.ventas,
    required this.costo,
    required this.ganancia,
    required this.showProfit,
    this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = <(String, double, Color)>[
      ('Ventas Totales', ventas, AppColors.success),
      if (showProfit) ...[
        ('Costo Total', costo, AppColors.warning),
        ('Ganancia Total', ganancia, AppColors.primary),
      ],
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(28) / 28;
        final stacked = constraints.maxWidth / metrics.length < 280 * scale;
        return Wrap(
          spacing: 16,
          runSpacing: 20,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: stacked
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 16 * (metrics.length - 1)) /
                          metrics.length,
                child: Column(
                  children: [
                    Text(
                      metric.$1,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      currency == null
                          ? '\$${NumberFormat('#,##0.00').format(metric.$2)}'
                          : '${NumberFormat('#,##0.00').format(metric.$2)} $currency',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: metric.$3,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
