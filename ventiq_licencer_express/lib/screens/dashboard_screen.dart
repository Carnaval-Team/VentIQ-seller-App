import 'package:flutter/material.dart';

import '../models/license_models.dart';
import '../models/subscription_models.dart';
import '../services/subscription_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final SubscriptionService _subscriptionService = SubscriptionService();
  late Future<DashboardData> _dashboardFuture;

  @override
  void initState() {
    super.initState();
    _dashboardFuture = _subscriptionService.fetchDashboardData();
  }

  Future<void> _refreshDashboard() async {
    final future = _subscriptionService.fetchDashboardData();
    setState(() {
      _dashboardFuture = future;
    });
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DashboardData>(
      future: _dashboardFuture,
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

  Widget _buildContent(BuildContext context, DashboardData data) {
    final textTheme = Theme.of(context).textTheme;
    final activeRatio = data.totalStores == 0
        ? 0
        : (data.activeStores / data.totalStores) * 100;
    final revenueChange = _percentageChange(
      data.revenueLastMonth,
      data.revenueThisMonth,
    );

    return AppBackground(
      child: SafeArea(
        child: RefreshIndicator(
          color: AppColors.accent,
          onRefresh: _refreshDashboard,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _DashboardHeader(),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _KpiCard(
                        title: 'Tiendas activas',
                        value: '${data.activeStores}/${data.totalStores}',
                        change: '${activeRatio.toStringAsFixed(0)}%',
                        icon: Icons.storefront_rounded,
                        gradient: AppGradients.cardBlue,
                        isPositive: activeRatio >= 80,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _KpiCard(
                        title: 'Renovaciones',
                        value: _formatCurrency(data.renewalRevenue),
                        change:
                            '${revenueChange >= 0 ? '+' : ''}${revenueChange.toStringAsFixed(1)}%',
                        icon: Icons.payments_rounded,
                        gradient: AppGradients.cardCyan,
                        isPositive: revenueChange >= 0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Licencias recientes', style: textTheme.titleLarge),
                    TextButton(
                      onPressed: () {},
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.accent,
                      ),
                      child: const Text('Ver todo'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (data.recentLicenses.isEmpty)
                  _EmptyState(message: 'Sin licencias recientes por mostrar.')
                else
                  ...data.recentLicenses
                      .map((license) => _LicenseCard(license: license))
                      .toList(),
              ],
            ),
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
                'No pudimos cargar el dashboard.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _dashboardFuture = _subscriptionService
                        .fetchDashboardData();
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

  double _percentageChange(double previous, double current) {
    if (previous == 0) {
      return current > 0 ? 100 : 0;
    }
    return ((current - previous) / previous) * 100;
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Stack(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppGradients.accentGlow,
              ),
              alignment: Alignment.center,
              child: Text(
                'VA',
                style: textTheme.titleMedium?.copyWith(fontSize: 16),
              ),
            ),
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.background, width: 2),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Dashboard', style: textTheme.headlineLarge),
            Text(
              'Bienvenido, Admin',
              style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: const Icon(Icons.notifications_none_rounded),
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.value,
    required this.change,
    required this.icon,
    required this.gradient,
    required this.isPositive,
  });

  final String title;
  final String value;
  final String change;
  final IconData icon;
  final LinearGradient gradient;
  final bool isPositive;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final changeColor = isPositive ? AppColors.success : AppColors.danger;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: gradient,
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
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceBright.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppColors.accent),
              ),
              const Spacer(),
              Icon(
                isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                size: 18,
                color: changeColor,
              ),
              const SizedBox(width: 4),
              Text(
                change,
                style: textTheme.bodySmall?.copyWith(
                  color: changeColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(title, style: textTheme.bodySmall),
          const SizedBox(height: 6),
          Text(value, style: textTheme.headlineSmall),
        ],
      ),
    );
  }
}

class _LicenseCard extends StatelessWidget {
  const _LicenseCard({required this.license});

  final LicenseInfo license;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final statusColor = _statusColor(license.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.surfaceBright,
            child: Text(
              license.avatarLabel,
              style: textTheme.titleMedium?.copyWith(fontSize: 14),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(license.storeName, style: textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  license.plan,
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
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _daysLeftLabel(license),
                  style: textTheme.bodySmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                license.statusLabel,
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _daysLeftLabel(LicenseInfo license) {
    if (license.daysLeft == 0) {
      return 'Vence hoy';
    }
    return '${license.daysLeft} dias';
  }

  Color _statusColor(LicenseStatus status) {
    switch (status) {
      case LicenseStatus.active:
        return AppColors.success;
      case LicenseStatus.expiringSoon:
        return AppColors.accentWarm;
      case LicenseStatus.dueToday:
        return AppColors.accentStrong;
      case LicenseStatus.overdue:
        return AppColors.danger;
    }
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
