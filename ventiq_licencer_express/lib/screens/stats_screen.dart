import 'dart:math';

import 'package:flutter/material.dart';

import '../models/license_models.dart';
import '../models/subscription_models.dart';
import '../services/subscription_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final SubscriptionService _subscriptionService = SubscriptionService();
  late Future<StatsData> _statsFuture;

  @override
  void initState() {
    super.initState();
    _statsFuture = _subscriptionService.fetchStatsData();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StatsData>(
      future: _statsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const AppBackground(
            child: Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            ),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return _buildErrorState(context);
        }
        return _buildContent(context, snapshot.data!);
      },
    );
  }

  Widget _buildContent(BuildContext context, StatsData data) {
    final textTheme = Theme.of(context).textTheme;
    final now = DateTime.now();
    final pendingCount = max(0, data.totalSubscriptions - data.paidThisMonth);
    final target = data.projectedRenewalRevenue > 0
        ? data.projectedRenewalRevenue
        : data.paidAmount;
    final progress = target <= 0
        ? 0.0
        : (data.paidAmount / target).clamp(0, 1).toDouble();

    return AppBackground(
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Stats', style: textTheme.headlineLarge),
                      Text(
                        'Resumen del mes en tiempo real',
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 16),
                        const SizedBox(width: 6),
                        Text(_monthLabel(now), style: textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _ProjectedRevenueCard(
                valueLabel: _formatCurrency(data.projectedRenewalRevenue),
                targetLabel: _formatCurrency(target),
                progress: progress,
                progressLabel:
                    '${(progress * 100).toStringAsFixed(0)}% completado',
              ),
              const SizedBox(height: 18),
              _StatsHighlightRow(
                paidLabel: '${data.paidThisMonth} licencias',
                paidSubtitle: '${_formatCurrency(data.paidAmount)} total',
                pendingLabel: '$pendingCount',
                pendingSubtitle: 'Renovaciones por cobrar',
              ),
              const SizedBox(height: 22),
              Text('Tendencia de ingresos', style: textTheme.titleLarge),
              const SizedBox(height: 12),
              _RevenueChartCard(points: data.revenueTrend),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Vencen hoy', style: textTheme.titleLarge),
                  Text(
                    '${data.dueTodayLicenses.length} tiendas',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (data.dueTodayLicenses.isEmpty)
                _EmptyState(message: 'Sin licencias que vencen hoy.')
              else
                ...data.dueTodayLicenses
                    .map((license) => _DueTodayCard(license: license))
                    .toList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    return AppBackground(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, color: AppColors.danger, size: 40),
              const SizedBox(height: 12),
              Text(
                'No pudimos cargar las estadisticas.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _statsFuture = _subscriptionService.fetchStatsData();
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentStrong,
                ),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatCurrency(double value) {
    return '\$${value.toStringAsFixed(0)}';
  }

  String _monthLabel(DateTime date) {
    const months = [
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withOpacity(0.6)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectedRevenueCard extends StatelessWidget {
  const _ProjectedRevenueCard({
    required this.valueLabel,
    required this.targetLabel,
    required this.progress,
    required this.progressLabel,
  });

  final String valueLabel;
  final String targetLabel;
  final double progress;
  final String progressLabel;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppGradients.cardBlue,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border.withOpacity(0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Ingresos proyectados', style: textTheme.bodySmall),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accentStrong.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '+12% vs mes pasado',
                  style: textTheme.bodySmall?.copyWith(color: AppColors.accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            valueLabel,
            style: textTheme.headlineSmall?.copyWith(fontSize: 28),
          ),
          const SizedBox(height: 8),
          Text(
            'Meta mensual: $targetLabel',
            style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              color: AppColors.accent,
              backgroundColor: AppColors.surfaceBright,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            progressLabel,
            style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _StatsHighlightRow extends StatelessWidget {
  const _StatsHighlightRow({
    required this.paidLabel,
    required this.paidSubtitle,
    required this.pendingLabel,
    required this.pendingSubtitle,
  });

  final String paidLabel;
  final String paidSubtitle;
  final String pendingLabel;
  final String pendingSubtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _HighlightCard(
            title: 'Pagadas este mes',
            value: paidLabel,
            subtitle: paidSubtitle,
            icon: Icons.verified_rounded,
            color: AppColors.success,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _HighlightCard(
            title: 'Pendientes',
            value: pendingLabel,
            subtitle: pendingSubtitle,
            icon: Icons.timelapse_rounded,
            color: AppColors.accentWarm,
          ),
        ),
      ],
    );
  }
}

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 14),
          Text(title, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _RevenueChartCard extends StatelessWidget {
  const _RevenueChartCard({required this.points});

  final List<RevenuePoint> points;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Proyeccion ultimos 6 meses', style: textTheme.titleMedium),
              Text(
                'Auto-refresh',
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            width: double.infinity,
            child: CustomPaint(
              painter: _RevenueLinePainter(
                points,
                labelStyle: textTheme.bodySmall?.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }
}

class _RevenueLinePainter extends CustomPainter {
  _RevenueLinePainter(this.points, {required this.labelStyle});

  final List<RevenuePoint> points;
  final TextStyle? labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) {
      return;
    }

    const double topPadding = 6;
    const double labelHeight = 20;
    final chartHeight = size.height - labelHeight - topPadding;
    final chartBottom = topPadding + chartHeight;

    final minValue = points.map((point) => point.value).reduce(min);
    final maxValue = points.map((point) => point.value).reduce(max);
    final range = maxValue - minValue == 0 ? 1 : maxValue - minValue;
    final stepX = size.width / points.length;
    final firstX = stepX / 2;
    final lastX = size.width - firstX;

    final path = Path();
    for (int index = 0; index < points.length; index++) {
      final point = points[index];
      final x = firstX + index * stepX;
      final y = chartBottom - ((point.value - minValue) / range) * chartHeight;
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final fillPath = Path.from(path)
      ..lineTo(lastX, chartBottom)
      ..lineTo(firstX, chartBottom)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [AppColors.accentStrong.withOpacity(0.25), Colors.transparent],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..shader = AppGradients.accentGlow.createShader(
        Rect.fromLTWH(0, 0, size.width, size.height),
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);

    final dotPaint = Paint()..color = AppColors.accent;
    for (int index = 0; index < points.length; index++) {
      final point = points[index];
      final x = firstX + index * stepX;
      final y = chartBottom - ((point.value - minValue) / range) * chartHeight;
      canvas.drawCircle(Offset(x, y), 3.5, dotPaint);
    }

    final resolvedLabelStyle =
        labelStyle ?? const TextStyle(fontSize: 12, color: AppColors.textMuted);
    final labelY = chartBottom + 4;
    for (int index = 0; index < points.length; index++) {
      final point = points[index];
      final textPainter = TextPainter(
        text: TextSpan(text: point.label, style: resolvedLabelStyle),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();
      final x = firstX + index * stepX;
      final maxOffsetX = max(0.0, size.width - textPainter.width);
      final offsetX = (x - textPainter.width / 2)
          .clamp(0.0, maxOffsetX)
          .toDouble();
      textPainter.paint(canvas, Offset(offsetX, labelY));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _DueTodayCard extends StatelessWidget {
  const _DueTodayCard({required this.license});

  final LicenseInfo license;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.surfaceBright,
                child: Text(
                  license.avatarLabel,
                  style: textTheme.titleMedium?.copyWith(fontSize: 13),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(license.storeName, style: textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Owner: ${license.owner}',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '\$${license.renewalAmount.toStringAsFixed(0)}',
                    style: textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Vence hoy',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentStrong,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Renovar licencia'),
            ),
          ),
        ],
      ),
    );
  }
}
