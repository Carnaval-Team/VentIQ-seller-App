import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/financial_reports_service.dart';
import '../services/user_preferences_service.dart';

class FinancialReportsScreen extends StatefulWidget {
  const FinancialReportsScreen({Key? key}) : super(key: key);

  @override
  State<FinancialReportsScreen> createState() => _FinancialReportsScreenState();
}

class _FinancialReportsScreenState extends State<FinancialReportsScreen> with SingleTickerProviderStateMixin {
  final FinancialReportsService _reportsService = FinancialReportsService();
  
  late TabController _tabController;
  bool _isLoading = false;
  
  // Data containers
  Map<String, dynamic> _profitabilityReport = {};
  List<Map<String, dynamic>> _categoryAnalysis = [];
  Map<String, dynamic> _cashFlowProjections = {};
  Map<String, dynamic> _budgetVariance = {};
  List<Map<String, dynamic>> _pendingApprovals = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadReportsData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadReportsData() async {
    setState(() => _isLoading = true);
    
    try {
      final userPrefs = UserPreferencesService();
      final storeId = await userPrefs.getIdTienda() ?? 1;
      final now = DateTime.now();
      final startDate = DateTime(now.year, now.month, 1).toIso8601String().split('T')[0];
      final endDate = now.toIso8601String().split('T')[0];
      final period = '${now.year}-${now.month.toString().padLeft(2, '0')}';

      final futures = await Future.wait([
        _reportsService.generateProfitabilityReport(
          storeId: storeId,
          startDate: startDate,
          endDate: endDate,
        ),
        _reportsService.getCategoryProfitabilityAnalysis(
          storeId: storeId,
          period: 'month',
        ),
        _reportsService.generateCashFlowProjections(
          storeId: storeId,
          monthsAhead: 6,
        ),
        _reportsService.getBudgetVarianceAnalysis(
          storeId: storeId,
          period: period,
        ),
        _reportsService.getPendingApprovals(storeId: storeId),
      ]);

      setState(() {
        _profitabilityReport = futures[0] as Map<String, dynamic>;
        _categoryAnalysis = futures[1] as List<Map<String, dynamic>>;
        _cashFlowProjections = futures[2] as Map<String, dynamic>;
        _budgetVariance = futures[3] as Map<String, dynamic>;
        _pendingApprovals = futures[4] as List<Map<String, dynamic>>;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading reports data: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Reportes Financieros',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.indigo[700],
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.analytics), text: 'Rentabilidad'),
            Tab(icon: Icon(Icons.trending_up), text: 'Proyecciones'),
            Tab(icon: Icon(Icons.account_balance), text: 'Presupuestos'),
            Tab(icon: Icon(Icons.approval), text: 'Aprobaciones'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildProfitabilityTab(),
                _buildProjectionsTab(),
                _buildBudgetTab(),
                _buildApprovalsTab(),
              ],
            ),
    );
  }

  Widget _buildProfitabilityTab() {
    return RefreshIndicator(
      onRefresh: _loadReportsData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProfitabilitySummary(),
            const SizedBox(height: 24),
            _buildCategoryAnalysisChart(),
            const SizedBox(height: 24),
            _buildTopPerformersCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildProfitabilitySummary() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Resumen de Rentabilidad',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  'Total Productos',
                  '${_profitabilityReport['total_products'] ?? 0}',
                  Icons.inventory,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricCard(
                  'Rentables',
                  '${_profitabilityReport['profitable_products'] ?? 0}',
                  Icons.trending_up,
                  Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  'Con Pérdidas',
                  '${_profitabilityReport['loss_making_products'] ?? 0}',
                  Icons.trending_down,
                  Colors.red,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricCard(
                  'Margen Promedio',
                  '${(_profitabilityReport['average_margin'] ?? 0.0).toStringAsFixed(1)}%',
                  Icons.percent,
                  Colors.orange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryAnalysisChart() {
    if (_categoryAnalysis.isEmpty) {
      return Container(
        height: 200,
        child: const Center(child: Text('No hay datos de categorías disponibles')),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Rentabilidad por Categoría',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 300,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: _categoryAnalysis.map((c) => (c['margin'] ?? 0.0).toDouble()).reduce((a, b) => a > b ? a : b) + 10,
                barTouchData: BarTouchData(enabled: true),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index >= 0 && index < _categoryAnalysis.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              _categoryAnalysis[index]['category'] ?? '',
                              style: const TextStyle(fontSize: 10),
                            ),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) => Text('${value.toInt()}%'),
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                barGroups: _categoryAnalysis.asMap().entries.map((entry) {
                  return BarChartGroupData(
                    x: entry.key,
                    barRods: [
                      BarChartRodData(
                        toY: (entry.value['margin'] ?? 0.0).toDouble(),
                        color: Colors.indigo[400],
                        width: 20,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopPerformersCard() {
    final topPerformers = _profitabilityReport['top_performers'] as List<dynamic>? ?? [];
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Productos Más Rentables',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ...topPerformers.map((product) => ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.green[100],
              child: Text(
                '${topPerformers.indexOf(product) + 1}',
                style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(product['product_name'] ?? 'Producto'),
            subtitle: Text('Margen: ${(product['margin'] ?? 0.0).toStringAsFixed(1)}%'),
            trailing: Text(
              '\$${(product['profit'] ?? 0.0).toStringAsFixed(0)}',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green[700]),
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildProjectionsTab() {
    final projections = _cashFlowProjections['projections'] as List<dynamic>? ?? [];
    
    return RefreshIndicator(
      onRefresh: _loadReportsData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Proyecciones de Flujo de Efectivo',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.blue[100],
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          'Confianza: ${((_cashFlowProjections['confidence_level'] ?? 0.0) * 100).toInt()}%',
                          style: TextStyle(color: Colors.blue[700], fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ...projections.map((projection) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(projection['month'] ?? ''),
                        Text(
                          '\$${(projection['projected_cash_flow'] ?? 0.0).toStringAsFixed(0)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: (projection['projected_cash_flow'] ?? 0.0) >= 0 
                                ? Colors.green[700] 
                                : Colors.red[700],
                          ),
                        ),
                      ],
                    ),
                  )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBudgetTab() {
    return RefreshIndicator(
      onRefresh: _loadReportsData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    spreadRadius: 1,
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Análisis de Variaciones Presupuestarias',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Presupuesto Total:'),
                      Text('\$${(_budgetVariance['total_budget'] ?? 0.0).toStringAsFixed(0)}'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Gasto Real:'),
                      Text('\$${(_budgetVariance['total_actual'] ?? 0.0).toStringAsFixed(0)}'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Variación:'),
                      Text(
                        '${(_budgetVariance['variance_percent'] ?? 0.0).toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: (_budgetVariance['variance_percent'] ?? 0.0) > 0 
                              ? Colors.red[700] 
                              : Colors.green[700],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApprovalsTab() {
    return RefreshIndicator(
      onRefresh: _loadReportsData,
      child: _pendingApprovals.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, size: 64, color: Colors.green),
                  SizedBox(height: 16),
                  Text('No hay aprobaciones pendientes'),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _pendingApprovals.length,
              itemBuilder: (context, index) {
                final approval = _pendingApprovals[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.orange[100],
                      child: Icon(Icons.pending, color: Colors.orange[700]),
                    ),
                    title: Text(approval['descripcion'] ?? 'Gasto pendiente'),
                    subtitle: Text(approval['justificacion'] ?? ''),
                    trailing: Text(
                      '\$${(approval['monto'] ?? 0.0).toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
