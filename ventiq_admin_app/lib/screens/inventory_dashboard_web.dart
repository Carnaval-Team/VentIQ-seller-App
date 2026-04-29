import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../models/analytics/inventory_metrics.dart';
import '../services/dashboard_service.dart';
import '../utils/number_formatter.dart';
import 'analytics/stock_health_detail_screen.dart';
import 'analytics/rotation_detail_screen.dart';
import 'analytics/stock_alerts_detail_screen.dart';

/// Vista web del Inventory Dashboard con diseño moderno (Senior Web Designer)
/// Mantiene la misma lógica/datos que `inventory_dashboard.dart` pero optimizada
/// para layouts anchos (≥ 900px).
class InventoryDashboardWeb extends StatefulWidget {
  const InventoryDashboardWeb({super.key});

  @override
  State<InventoryDashboardWeb> createState() => _InventoryDashboardWebState();
}

class _InventoryDashboardWebState extends State<InventoryDashboardWeb> {
  Map<String, dynamic>? _dashboardData;
  bool _isLoading = true;
  String _errorMessage = '';

  static const double _kMaxContentWidth = 1400;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final data = await DashboardService.getCompleteStoreAnalysis(
        periodo: 'mes',
      );
      await Future.microtask(() {});
      if (!mounted) return;
      setState(() {
        _dashboardData = data;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error al cargar dashboard: $e';
      });
    }
  }

  void _showStockHealthDetail() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const StockHealthDetailScreen()),
    );
  }

  void _showRotationDetail() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const RotationDetailScreen()),
    );
  }

  void _showAlertsDetail(String severity) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => StockAlertsDetailScreen(initialFilter: severity),
      ),
    );
  }

  // =====================================================
  // BUILD
  // =====================================================
  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadDashboard,
      color: AppColors.primary,
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return _buildErrorState();
    }

    if (_dashboardData == null) {
      return _buildEmptyState();
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kMaxContentWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildOverviewSection(),
              const SizedBox(height: 24),
              _buildSuppliersSection(),
              const SizedBox(height: 20),
              _buildAlertsSection(),
              const SizedBox(height: 24),
              _buildTopProductsSection(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // =====================================================
  // SECTION CARD (reutilizable)
  // =====================================================
  Widget _buildSectionCard({
    required String title,
    String? subtitle,
    required IconData icon,
    required Color iconColor,
    required Widget child,
    EdgeInsetsGeometry? padding,
    Widget? action,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          letterSpacing: 0.2,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (action != null) action,
              ],
            ),
          ),
          Container(height: 1, color: AppColors.border),
          Padding(
            padding: padding ?? const EdgeInsets.all(20),
            child: child,
          ),
        ],
      ),
    );
  }

  // =====================================================
  // OVERVIEW: stacks de métricas principales
  // =====================================================
  Widget _buildOverviewSection() {
    final metrics = _dashboardData!['inventory_metrics'] as InventoryMetrics;
    final alerts = _dashboardData!['stock_alerts'] as List;

    int criticalAlerts = 0;
    int warningAlerts = 0;
    for (final alert in alerts) {
      final severity =
          (alert is Map ? alert['severity'] : alert.severity)?.toString().toLowerCase() ??
              '';
      if (severity == 'critical') {
        criticalAlerts++;
      } else if (severity == 'warning') {
        warningAlerts++;
      }
    }
    final totalAlerts = criticalAlerts + warningAlerts;
    final alertRatio =
        metrics.totalProducts > 0 ? totalAlerts / metrics.totalProducts : 0;

    String healthLevel;
    Color healthColor;
    if (criticalAlerts > 0 || alertRatio > 0.2) {
      healthLevel = 'Crítico';
      healthColor = AppColors.error;
    } else if (alertRatio > 0.1) {
      healthLevel = 'Alerta';
      healthColor = AppColors.warning;
    } else if (alertRatio > 0.05) {
      healthLevel = 'Precaución';
      healthColor = Colors.amber.shade700;
    } else {
      healthLevel = 'Saludable';
      healthColor = AppColors.success;
    }

    final stacks = <_MetricStackData>[
      _MetricStackData(
        title: 'Valor Total Inventario',
        value:
            'CUP \$${NumberFormatter.formatCurrency(metrics.totalValue)}',
        icon: Icons.account_balance_wallet_outlined,
        color: AppColors.success,
        changePercent: metrics.valueChangePercent,
      ),
      _MetricStackData(
        title: 'Total Productos',
        value: metrics.totalProducts.toString(),
        icon: Icons.inventory_2_outlined,
        color: AppColors.primary,
        subtitle:
            '${(metrics.totalProducts - totalAlerts).clamp(0, metrics.totalProducts)} saludables',
      ),
      _MetricStackData(
        title: 'Estado de Stock',
        value: '$criticalAlerts',
        icon: criticalAlerts > 0
            ? Icons.error_outline
            : Icons.check_circle_outline,
        color: healthColor,
        badgeText: healthLevel,
        subtitle: criticalAlerts > 0
            ? 'productos sin stock'
            : '$totalAlerts con alertas',
        onTap: _showStockHealthDetail,
      ),
      _MetricStackData(
        title: 'Rotación Promedio',
        value: metrics.averageRotation.toStringAsFixed(1),
        icon: Icons.rotate_right_outlined,
        color: AppColors.info,
        badgeText: metrics.rotationLevel,
        subtitle: 'veces por año',
        onTap: _showRotationDetail,
      ),
    ];

    return _buildSectionCard(
      title: 'Resumen General',
      subtitle: 'Indicadores clave del inventario',
      icon: Icons.speed_outlined,
      iconColor: AppColors.primary,
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 12.0;
          final maxW = constraints.maxWidth;
          final cols = maxW >= 1100
              ? 4
              : maxW >= 700
                  ? 2
                  : 1;
          final tileWidth = (maxW - gap * (cols - 1)) / cols;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: stacks
                .map((s) =>
                    SizedBox(width: tileWidth, child: _buildMetricStack(s)))
                .toList(),
          );
        },
      ),
    );
  }

  Widget _buildMetricStack(_MetricStackData s) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: s.color.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: s.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(s.icon, color: s.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  s.title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.3,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (s.badgeText != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: s.color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    s.badgeText!,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: s.color,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 26,
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                s.value,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: s.color,
                  height: 1.1,
                ),
              ),
            ),
          ),
          if (s.subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              s.subtitle!,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (s.changePercent != null) ...[
            const SizedBox(height: 8),
            _buildChangeChip(s.changePercent!),
          ],
        ],
      ),
    );

    if (s.onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: s.onTap,
        borderRadius: BorderRadius.circular(12),
        child: content,
      ),
    );
  }

  Widget _buildChangeChip(double pct) {
    final isUp = pct >= 0;
    final color = isUp ? AppColors.success : AppColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isUp ? Icons.trending_up : Icons.trending_down,
            color: color,
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            '${isUp ? '+' : ''}${pct.toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // SUPPLIERS
  // =====================================================
  Widget _buildSuppliersSection() {
    final supplierDashboard =
        _dashboardData!['supplier_dashboard'] as Map<String, dynamic>? ?? {};

    return _buildSectionCard(
      title: 'Proveedores',
      subtitle: 'Visión general del mes',
      icon: Icons.local_shipping_outlined,
      iconColor: AppColors.info,
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 12.0;
          final maxW = constraints.maxWidth;
          final cols = maxW >= 520 ? 2 : 1;
          final tileWidth = (maxW - gap * (cols - 1)) / cols;

          final items = [
            _MetricStackData(
              title: 'Total Proveedores',
              value: '${supplierDashboard['total_proveedores'] ?? 0}',
              icon: Icons.business_outlined,
              color: AppColors.info,
              subtitle:
                  '${supplierDashboard['proveedores_activos'] ?? 0} activos',
            ),
            _MetricStackData(
              title: 'Compras del Mes',
              value:
                  'CUP \$${NumberFormatter.formatCurrency(supplierDashboard['valor_compras_mes'] ?? 0.0)}',
              icon: Icons.shopping_cart_outlined,
              color: AppColors.success,
              subtitle: _buildComprasSubtitle(supplierDashboard),
            ),
          ];
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: items
                .map((s) =>
                    SizedBox(width: tileWidth, child: _buildMetricStack(s)))
                .toList(),
          );
        },
      ),
    );
  }

  String _buildComprasSubtitle(Map<String, dynamic> supplierDashboard) {
    final comprasDetalle =
        supplierDashboard['compras_detalle'] as Map<String, dynamic>?;
    if (comprasDetalle != null) {
      final totalUSD = (comprasDetalle['total_usd'] ?? 0.0) as double;
      final numOperaciones = comprasDetalle['numero_operaciones'] ?? 0;
      return 'USD \$${totalUSD.toStringAsFixed(2)} • $numOperaciones ops';
    }
    return 'Sin datos de compras';
  }

  // =====================================================
  // ALERTS
  // =====================================================
  Widget _buildAlertsSection() {
    final alerts = _dashboardData!['stock_alerts'] as List;
    final criticalAlerts =
        alerts.where((a) => _severityOf(a) == 'critical').length;
    final warningAlerts =
        alerts.where((a) => _severityOf(a) == 'warning').length;

    return _buildSectionCard(
      title: 'Alertas de Stock',
      subtitle: 'Monitoreo de productos en riesgo',
      icon: Icons.warning_amber_outlined,
      iconColor: AppColors.warning,
      padding: const EdgeInsets.all(16),
      action: TextButton.icon(
        onPressed: () => _showAlertsDetail('all'),
        icon: const Icon(Icons.open_in_new, size: 16),
        label: const Text('Ver todas'),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 12.0;
              final maxW = constraints.maxWidth;
              final cols = maxW >= 520 ? 2 : 1;
              final tileWidth = (maxW - gap * (cols - 1)) / cols;
              final items = [
                _MetricStackData(
                  title: 'Alertas Críticas',
                  value: criticalAlerts.toString(),
                  icon: Icons.error_outline,
                  color: AppColors.error,
                  subtitle: 'requieren atención',
                  onTap: () => _showAlertsDetail('critical'),
                ),
                _MetricStackData(
                  title: 'Advertencias',
                  value: warningAlerts.toString(),
                  icon: Icons.warning_amber_outlined,
                  color: AppColors.warning,
                  subtitle: 'para revisar',
                  onTap: () => _showAlertsDetail('warning'),
                ),
              ];
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: items
                    .map((s) =>
                        SizedBox(width: tileWidth, child: _buildMetricStack(s)))
                    .toList(),
              );
            },
          ),
          if (alerts.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant.withOpacity(0.4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 8),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.notifications_active_outlined,
                          size: 16,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Alertas Recientes',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...alerts.take(3).map((a) => _buildAlertTile(a)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _severityOf(dynamic a) =>
      (a is Map ? a['severity'] : a.severity)?.toString().toLowerCase() ?? '';

  Widget _buildAlertTile(dynamic alert) {
    final severity = _severityOf(alert);
    final productName = alert is Map
        ? (alert['product_name'] ?? alert['productName'])
        : alert.productName;
    final message = alert is Map ? alert['message'] : alert.message;

    Color color;
    IconData icon;
    switch (severity) {
      case 'critical':
        color = AppColors.error;
        icon = Icons.error_outline;
        break;
      case 'warning':
        color = AppColors.warning;
        icon = Icons.warning_amber_outlined;
        break;
      default:
        color = AppColors.info;
        icon = Icons.info_outline;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  productName ?? 'Producto Desconocido',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  message ?? 'Sin mensaje',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // TOP PRODUCTS
  // =====================================================
  Widget _buildTopProductsSection() {
    final topProducts = _dashboardData!['top_products'] as List;

    return _buildSectionCard(
      title: 'Productos Destacados',
      subtitle: 'Top por rotación de inventario',
      icon: Icons.star_outline,
      iconColor: AppColors.warning,
      padding: const EdgeInsets.all(12),
      child: topProducts.isEmpty
          ? _buildEmptyInline(
              icon: Icons.inventory_2_outlined,
              title: 'Sin datos',
              description: 'No hay datos de productos disponibles.',
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                const gap = 12.0;
                final maxW = constraints.maxWidth;
                final cols = maxW >= 1100
                    ? 3
                    : maxW >= 720
                        ? 2
                        : 1;
                final tileWidth = (maxW - gap * (cols - 1)) / cols;
                final list = topProducts.take(6).toList();
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: list
                      .asMap()
                      .entries
                      .map((e) => SizedBox(
                            width: tileWidth,
                            child: _buildTopProductTile(e.value, e.key + 1),
                          ))
                      .toList(),
                );
              },
            ),
    );
  }

  Widget _buildTopProductTile(dynamic product, int rank) {
    final name = product.productName as String? ?? 'Producto';
    final rotationRate = (product.rotationRate as num?)?.toDouble() ?? 0.0;
    final rotationLabel = product.rotationLabel as String? ?? '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withOpacity(0.9),
                  AppColors.primaryDark,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                '#$rank',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'Rotación: ${rotationRate.toStringAsFixed(1)}x',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (rotationLabel.isNotEmpty)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                rotationLabel,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppColors.success,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // =====================================================
  // STATES
  // =====================================================
  Widget _buildErrorState() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.error_outline,
                  size: 32,
                  color: AppColors.error,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _loadDashboard,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: _buildEmptyInline(
        icon: Icons.dashboard_outlined,
        title: 'Sin datos',
        description: 'No hay datos disponibles para mostrar.',
      ),
    );
  }

  Widget _buildEmptyInline({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 28, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================
// MODEL
// =====================================================
class _MetricStackData {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;
  final String? badgeText;
  final double? changePercent;
  final VoidCallback? onTap;

  _MetricStackData({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
    this.badgeText,
    this.changePercent,
    this.onTap,
  });
}
