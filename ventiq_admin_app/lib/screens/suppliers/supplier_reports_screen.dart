import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../config/app_colors.dart';
import '../../services/supplier_service.dart';
import '../../widgets/supplier/supplier_performance_widget.dart';
import '../../widgets/supplier/supplier_alerts_widget.dart';

class SupplierReportsScreen extends StatefulWidget {
  const SupplierReportsScreen({super.key});

  @override
  State<SupplierReportsScreen> createState() => _SupplierReportsScreenState();
}

class _SupplierReportsScreenState extends State<SupplierReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  Map<String, dynamic> _dashboardData = {};
  String _selectedPeriod = '30';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadDashboardData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    try {
      final data = await SupplierService.getSuppliersDashboard(
        periodo: int.parse(_selectedPeriod),
      );
      setState(() {
        _dashboardData = data;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading dashboard data: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reportes de Proveedores'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          _buildPeriodSelector(),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard), text: 'Overview'),
            Tab(icon: Icon(Icons.analytics), text: 'Performance'),
            Tab(icon: Icon(Icons.warning), text: 'Alertas'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(),
          _buildPerformanceTab(),
          _buildAlertsTab(),
        ],
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return PopupMenuButton<String>(
      initialValue: _selectedPeriod,
      onSelected: (value) {
        setState(() => _selectedPeriod = value);
        _loadDashboardData();
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: '7', child: Text('Últimos 7 días')),
        const PopupMenuItem(value: '30', child: Text('Últimos 30 días')),
        const PopupMenuItem(value: '90', child: Text('Últimos 90 días')),
        const PopupMenuItem(value: '365', child: Text('Último año')),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _getPeriodLabel(),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, color: Colors.white, size: 16),
          ],
        ),
      ),
    );
  }

  String _getPeriodLabel() {
    switch (_selectedPeriod) {
      case '7': return '7d';
      case '30': return '30d';
      case '90': return '90d';
      case '365': return '1a';
      default: return '30d';
    }
  }

  Widget _buildOverviewTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final kpis = _dashboardData['kpis_principales'] ?? {};
    final financieras = _dashboardData['metricas_financieras'] ?? {};
    final operativas = _dashboardData['metricas_operativas'] ?? {};

    return RefreshIndicator(
      onRefresh: _loadDashboardData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildKPICards(kpis),
            const SizedBox(height: 24),
            _buildFinancialMetrics(financieras),
            const SizedBox(height: 24),
            _buildOperationalMetrics(operativas),
            const SizedBox(height: 24),
            _buildTopSuppliersChart(),
          ],
        ),
      ),
    );
  }

  Widget _buildKPICards(Map<String, dynamic> kpis) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'KPIs Principales',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildKPICard(
                'Total Proveedores',
                '${kpis['total_proveedores'] ?? 0}',
                Icons.business,
                AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildKPICard(
                'Activos',
                '${kpis['proveedores_activos'] ?? 0}',
                Icons.trending_up,
                AppColors.success,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildKPICard(
                'Nuevos',
                '${kpis['nuevos_proveedores'] ?? 0}',
                Icons.add_business,
                AppColors.warning,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildKPICard(
                'Tasa Actividad',
                '${(kpis['tasa_actividad'] ?? 0.0).toStringAsFixed(1)}%',
                Icons.show_chart,
                AppColors.secondary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKPICard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const Spacer(),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinancialMetrics(Map<String, dynamic> financieras) {
    final valorTotal = financieras['valor_compras_total'] ?? 0.0;
    final crecimiento = financieras['crecimiento_compras'] ?? 0.0;
    final valorPromedio = financieras['valor_promedio_por_proveedor'] ?? 0.0;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.attach_money, color: AppColors.primary, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'Métricas Financieras',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildFinancialItem(
                    'Valor Total Compras',
                    '\$${valorTotal.toStringAsFixed(2)}',
                    AppColors.primary,
                  ),
                ),
                Expanded(
                  child: _buildFinancialItem(
                    'Crecimiento',
                    '${crecimiento >= 0 ? '+' : ''}${crecimiento.toStringAsFixed(1)}%',
                    crecimiento >= 0 ? AppColors.success : AppColors.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildFinancialItem(
              'Valor Promedio por Proveedor',
              '\$${valorPromedio.toStringAsFixed(2)}',
              AppColors.secondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinancialItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildOperationalMetrics(Map<String, dynamic> operativas) {
    final leadTime = operativas['lead_time_promedio'] ?? 0.0;
    final productosPorProveedor = operativas['productos_por_proveedor'] ?? 0.0;
    final diversificacionScore = operativas['diversificacion_score'] ?? 0.0;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.settings, color: AppColors.primary, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'Métricas Operativas',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildOperationalItem(
                    'Lead Time Promedio',
                    '${leadTime.toStringAsFixed(1)} días',
                    Icons.schedule,
                    AppColors.warning,
                  ),
                ),
                Expanded(
                  child: _buildOperationalItem(
                    'Productos/Proveedor',
                    productosPorProveedor.toStringAsFixed(1),
                    Icons.inventory,
                    AppColors.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildDiversificationScore(diversificacionScore),
          ],
        ),
      ),
    );
  }

  Widget _buildOperationalItem(String label, String value, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDiversificationScore(double score) {
    Color scoreColor = AppColors.success;
    if (score < 30) scoreColor = AppColors.error;
    else if (score < 60) scoreColor = AppColors.warning;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scoreColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scoreColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.diversity_3, color: scoreColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Score de Diversificación',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                Text(
                  '${score.toStringAsFixed(0)}/100',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: scoreColor,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(
              value: score / 100,
              strokeWidth: 6,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopSuppliersChart() {
    final topSuppliers = _dashboardData['top_proveedores'] as List? ?? [];
    
    if (topSuppliers.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(Icons.info, color: Colors.grey.shade400, size: 48),
              const SizedBox(height: 8),
              const Text(
                'No hay datos de proveedores disponibles',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Top Proveedores por Valor',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...topSuppliers.take(5).map((supplier) => _buildSupplierItem(supplier)),
          ],
        ),
      ),
    );
  }

  Widget _buildSupplierItem(Map<String, dynamic> supplier) {
    final denominacion = supplier['denominacion'] ?? 'Sin nombre';
    final valorTotal = (supplier['valor_total'] ?? 0.0).toDouble();
    final totalOrdenes = supplier['total_ordenes'] ?? 0;
    final performanceScore = (supplier['performance_score'] ?? 0.0).toDouble();

    Color performanceColor = AppColors.success;
    if (performanceScore < 70) performanceColor = AppColors.error;
    else if (performanceScore < 85) performanceColor = AppColors.warning;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  denominacion,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '\$${valorTotal.toStringAsFixed(2)} • $totalOrdenes órdenes',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: performanceColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${performanceScore.toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: performanceColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceTab() {
    return const Center(
      child: Text('Performance Tab - En desarrollo'),
    );
  }

  Widget _buildAlertsTab() {
    final alertas = _dashboardData['alertas'] as List? ?? [];
    
    return SupplierAlertsWidget(
      alerts: alertas,
      isLoading: _isLoading,
    );
  }
}
