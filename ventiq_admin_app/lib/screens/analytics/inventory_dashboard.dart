import 'package:flutter/material.dart';
import '../../models/analytics/inventory_metrics.dart';
import '../../services/dashboard_service.dart';
import '../../widgets/analytics/metric_card.dart';
import 'stock_health_detail_screen.dart';
import 'rotation_detail_screen.dart';
import 'stock_alerts_detail_screen.dart';
import '../../utils/number_formatter.dart';

class InventoryDashboard extends StatefulWidget {
  const InventoryDashboard({super.key});

  @override
  State<InventoryDashboard> createState() => _InventoryDashboardState();
}

class _InventoryDashboardState extends State<InventoryDashboard> {
  Map<String, dynamic>? _dashboardData;
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final data = await DashboardService.getStoreAnalysis(periodo: 'mes');

      // ✅ Usar microtask para evitar bloquear UI
      await Future.microtask(() {});

      if (mounted) {
        // ✅ Verificar que el widget sigue montado
        setState(() {
          _dashboardData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
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

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(onRefresh: _loadDashboard, child: _buildContent());
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage.isNotEmpty) {
      return _buildErrorState();
    }

    if (_dashboardData == null) {
      return _buildEmptyState();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMetricsOverview(),
          const SizedBox(height: 24),
          _buildSuppliersSection(),
          const SizedBox(height: 24),
          _buildAlertsSection(),
          const SizedBox(height: 24),
          _buildTopProductsSection(),
        ],
      ),
    );
  }

  Widget _buildSuppliersSection() {
    final supplierDashboard =
        _dashboardData!['supplier_dashboard'] as Map<String, dynamic>? ?? {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Proveedores',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),

        Row(
          children: [
            Expanded(
              child: MetricCard(
                title: 'Total Proveedores',
                value: '${supplierDashboard['total_proveedores'] ?? 0}',
                icon: Icons.business,
                color: Colors.blue,
                subtitle:
                    '${supplierDashboard['proveedores_activos'] ?? 0} activos',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MetricCard(
                title: 'Compras del Mes',
                value:
                    'CUP \$${NumberFormatter.formatCurrency(supplierDashboard['valor_compras_mes'] ?? 0.0)}',
                icon: Icons.shopping_cart,
                color: Colors.green,
                subtitle: _buildComprasSubtitle(supplierDashboard),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricsOverview() {
    final metrics = _dashboardData!['inventory_metrics'] as InventoryMetrics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Resumen General',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),

        LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth > 600 ? 4 : 2;
            return GridView.count(
              crossAxisCount: crossAxisCount,
              childAspectRatio: 1.2, // ✅ Más ancho, menos alto
              crossAxisSpacing: 12, // ✅ Menos espacio
              mainAxisSpacing: 12, // ✅ Menos espacio
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                MetricCard(
                  title: 'Valor Total',
                  value: 'CUP \$${NumberFormatter.formatCurrency(metrics.totalValue)}',
                  icon: Icons.attach_money,
                  color: Colors.green,
                  changePercent: metrics.valueChangePercent,
                  unit: 'CUP',
                ),

                MetricCard(
                  title: 'Total Productos',
                  value: metrics.totalProducts.toString(),
                  icon: Icons.inventory,
                  color: Colors.blue,
                  subtitle:
                      '${metrics.totalProducts - metrics.outOfStockProducts} disponibles',
                ),

                InventoryMetricCard(
                  title: 'Estado Stock',
                  value: '${metrics.outOfStockProducts}',
                  icon: Icons.warning,
                  color: Colors.orange,
                  healthLevel: metrics.stockHealthLevel,
                  subtitle: 'productos sin stock',
                  onTap: _showStockHealthDetail,
                ),

                InventoryMetricCard(
                  title: 'Rotación',
                  value: metrics.averageRotation.toStringAsFixed(1),
                  icon: Icons.rotate_right,
                  color: Colors.purple,
                  healthLevel: metrics.rotationLevel,
                  subtitle: 'veces por año',
                  onTap: _showRotationDetail,
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildAlertsSection() {
    final alerts = _dashboardData!['stock_alerts'] as List;
    final criticalAlerts = alerts.where((a) => a.severity == 'critical').length;
    final warningAlerts = alerts.where((a) => a.severity == 'warning').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Alertas de Stock',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),

        Row(
          children: [
            Expanded(
              child: MetricCard(
                title: 'Alertas Críticas',
                value: criticalAlerts.toString(),
                icon: Icons.error,
                color: Colors.red,
                subtitle: 'requieren atención',
                onTap: () => _showAlertsDetail('critical'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MetricCard(
                title: 'Advertencias',
                value: warningAlerts.toString(),
                icon: Icons.warning,
                color: Colors.orange,
                subtitle: 'para revisar',
                onTap: () => _showAlertsDetail('warning'),
              ),
            ),
          ],
        ),

        if (alerts.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildRecentAlerts(alerts.take(3).toList()),
        ],
      ],
    );
  }

  Widget _buildRecentAlerts(List alerts) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Alertas Recientes',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                TextButton(
                  onPressed: () => _showAlertsDetail('all'),
                  child: const Text('Ver todas'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...alerts.map((alert) => _buildAlertTile(alert)),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertTile(dynamic alert) {
    Color alertColor;
    IconData alertIcon;

    // CORREGIR: Acceso a datos como Map en lugar de propiedades
    final severity = alert is Map ? alert['severity'] : alert.severity;
    final productName =
        alert is Map
            ? alert['product_name'] ?? alert['productName']
            : alert.productName;
    final message = alert is Map ? alert['message'] : alert.message;

    switch (severity) {
      case 'critical':
        alertColor = Colors.red;
        alertIcon = Icons.error;
        break;
      case 'warning':
        alertColor = Colors.orange;
        alertIcon = Icons.warning;
        break;
      default:
        alertColor = Colors.blue;
        alertIcon = Icons.info;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: alertColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: alertColor.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(alertIcon, color: alertColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  productName ?? 'Producto Desconocido',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  message ?? 'Sin mensaje',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopProductsSection() {
    final topProducts = _dashboardData!['top_products'] as List;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Productos Destacados',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),

        if (topProducts.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text('No hay datos de productos disponibles'),
              ),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children:
                    topProducts.take(5).map((product) {
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue.shade100,
                          child: Icon(
                            Icons.inventory_2,
                            color: Colors.blue.shade700,
                          ),
                        ),
                        title: Text(product.productName),
                        subtitle: Text(
                          'Rotación: ${product.rotationRate.toStringAsFixed(1)}x',
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            product.rotationLabel,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
          const SizedBox(height: 16),
          Text(
            _errorMessage,
            style: const TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadDashboard,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.dashboard, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text('No hay datos disponibles', style: TextStyle(fontSize: 16)),
        ],
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

  void _showAlertsDetail(String severity) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => StockAlertsDetailScreen(initialFilter: severity),
      ),
    );
  }
}
