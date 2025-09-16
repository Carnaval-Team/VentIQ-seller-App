import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/financial_dashboard_service.dart';
import '../services/user_preferences_service.dart';

class FinancialDashboardScreen extends StatefulWidget {
  const FinancialDashboardScreen({Key? key}) : super(key: key);

  @override
  State<FinancialDashboardScreen> createState() => _FinancialDashboardScreenState();
}

class _FinancialDashboardScreenState extends State<FinancialDashboardScreen> {
  final FinancialDashboardService _dashboardService = FinancialDashboardService();
  
  String _selectedPeriod = 'month';
  Map<String, dynamic> _keyMetrics = {};
  Map<String, dynamic> _profitAndLoss = {};
  List<Map<String, dynamic>> _productProfitability = [];
  List<Map<String, dynamic>> _alerts = [];
  bool _isLoading = true;

  final List<String> _periods = [
    'today',
    'week', 
    'month',
    'quarter',
    'year'
  ];

  final Map<String, String> _periodLabels = {
    'today': 'Hoy',
    'week': 'Esta Semana',
    'month': 'Este Mes',
    'quarter': 'Este Trimestre',
    'year': 'Este Año',
  };

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    
    try {
      final userPrefs = UserPreferencesService();
      final storeId = await userPrefs.getIdTienda() ?? 1;
      
      // Cargar datos en paralelo
      final futures = await Future.wait([
        _dashboardService.getKeyMetrics(storeId: storeId, period: _selectedPeriod),
        _dashboardService.getProfitAndLoss(
          storeId: storeId,
          startDate: _getPeriodStartDate(),
          endDate: _getPeriodEndDate(),
        ),
        _dashboardService.getProductProfitability(
          storeId: storeId,
          period: _selectedPeriod,
          limit: 10,
        ),
        _dashboardService.getFinancialAlerts(storeId: storeId),
      ]);

      setState(() {
        _keyMetrics = futures[0] as Map<String, dynamic>;
        _profitAndLoss = futures[1] as Map<String, dynamic>;
        _productProfitability = futures[2] as List<Map<String, dynamic>>;
        _alerts = futures[3] as List<Map<String, dynamic>>;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading dashboard data: $e');
      setState(() => _isLoading = false);
    }
  }

  String _getPeriodStartDate() {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case 'today':
        return DateTime(now.year, now.month, now.day).toIso8601String().split('T')[0];
      case 'week':
        return now.subtract(Duration(days: now.weekday - 1)).toIso8601String().split('T')[0];
      case 'month':
        return DateTime(now.year, now.month, 1).toIso8601String().split('T')[0];
      case 'quarter':
        final quarterStart = ((now.month - 1) ~/ 3) * 3 + 1;
        return DateTime(now.year, quarterStart, 1).toIso8601String().split('T')[0];
      case 'year':
        return DateTime(now.year, 1, 1).toIso8601String().split('T')[0];
      default:
        return DateTime(now.year, now.month, 1).toIso8601String().split('T')[0];
    }
  }

  String _getPeriodEndDate() {
    return DateTime.now().toIso8601String().split('T')[0];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Dashboard Financiero',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedPeriod,
                dropdownColor: Colors.blue[700],
                style: const TextStyle(color: Colors.white),
                items: _periods.map((period) {
                  return DropdownMenuItem(
                    value: period,
                    child: Text(_periodLabels[period]!),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedPeriod = value);
                    _loadDashboardData();
                  }
                },
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDashboardData,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Alertas
                    if (_alerts.isNotEmpty) _buildAlertsSection(),
                    
                    // KPIs principales
                    _buildKPICards(),
                    
                    const SizedBox(height: 24),
                    
                    // P&L y gráficos
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 2, child: _buildProfitLossCard()),
                        const SizedBox(width: 16),
                        Expanded(flex: 1, child: _buildRevenueChart()),
                      ],
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Análisis de rentabilidad
                    _buildProfitabilityAnalysis(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildAlertsSection() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.orange[700]),
              const SizedBox(width: 8),
              Text(
                'Alertas Financieras',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...(_alerts.take(3).map((alert) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '• ${alert['message'] ?? 'Alerta financiera'}',
              style: TextStyle(color: Colors.orange[800]),
            ),
          ))),
        ],
      ),
    );
  }

  Widget _buildKPICards() {
    final kpis = [
      {
        'title': 'Ingresos',
        'value': _formatCurrency(_keyMetrics['revenue'] ?? 0.0),
        'icon': Icons.trending_up,
        'color': Colors.green,
        'subtitle': 'Total del período',
      },
      {
        'title': 'Utilidad Neta',
        'value': _formatCurrency(_keyMetrics['net_profit'] ?? 0.0),
        'icon': Icons.account_balance_wallet,
        'color': Colors.blue,
        'subtitle': '${_formatPercentage(_keyMetrics['net_margin'] ?? 0.0)} margen',
      },
      {
        'title': 'ROI',
        'value': '${_formatPercentage(_keyMetrics['roi'] ?? 0.0)}',
        'icon': Icons.show_chart,
        'color': Colors.purple,
        'subtitle': 'Retorno inversión',
      },
      {
        'title': 'Rotación Inventario',
        'value': '${(_keyMetrics['inventory_turnover'] ?? 0.0).toStringAsFixed(1)}x',
        'icon': Icons.inventory,
        'color': Colors.orange,
        'subtitle': 'Veces por período',
      },
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.5,
      ),
      itemCount: kpis.length,
      itemBuilder: (context, index) {
        final kpi = kpis[index];
        return Container(
          padding: const EdgeInsets.all(16),
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
                children: [
                  Icon(
                    kpi['icon'] as IconData,
                    color: kpi['color'] as Color,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      kpi['title'] as String,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                kpi['value'] as String,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                kpi['subtitle'] as String,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProfitLossCard() {
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
            'Estado de Resultados (P&L)',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _buildPLItem('Ingresos', _profitAndLoss['revenue'] ?? 0.0, isRevenue: true),
          _buildPLItem('Costo de Ventas', _profitAndLoss['cost_of_goods_sold'] ?? 0.0),
          const Divider(),
          _buildPLItem('Utilidad Bruta', _profitAndLoss['gross_profit'] ?? 0.0, isBold: true),
          _buildPLItem('Gastos Operativos', _profitAndLoss['operational_expenses'] ?? 0.0),
          _buildPLItem('Gastos Administrativos', _profitAndLoss['administrative_expenses'] ?? 0.0),
          _buildPLItem('Gastos Financieros', _profitAndLoss['financial_expenses'] ?? 0.0),
          const Divider(),
          _buildPLItem('Utilidad Neta', _profitAndLoss['net_profit'] ?? 0.0, 
                      isBold: true, isProfit: true),
        ],
      ),
    );
  }

  Widget _buildPLItem(String label, double amount, {bool isBold = false, bool isRevenue = false, bool isProfit = false}) {
    Color color = Colors.black87;
    if (isRevenue) color = Colors.green[700]!;
    if (isProfit) color = amount >= 0 ? Colors.green[700]! : Colors.red[700]!;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: color,
            ),
          ),
          Text(
            _formatCurrency(amount),
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueChart() {
    return Container(
      height: 300,
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
            'Distribución de Ingresos',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: PieChart(
              PieChartData(
                sections: [
                  PieChartSectionData(
                    value: (_profitAndLoss['gross_profit'] ?? 0.0).toDouble(),
                    title: 'Utilidad\nBruta',
                    color: Colors.green[400],
                    radius: 60,
                    titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  PieChartSectionData(
                    value: (_profitAndLoss['cost_of_goods_sold'] ?? 0.0).toDouble(),
                    title: 'Costo\nVentas',
                    color: Colors.red[400],
                    radius: 60,
                    titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  PieChartSectionData(
                    value: (_profitAndLoss['total_expenses'] ?? 0.0 - (_profitAndLoss['cost_of_goods_sold'] ?? 0.0)).toDouble(),
                    title: 'Gastos\nOperativos',
                    color: Colors.orange[400],
                    radius: 60,
                    titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
                sectionsSpace: 2,
                centerSpaceRadius: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfitabilityAnalysis() {
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
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          if (_productProfitability.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No hay datos de rentabilidad disponibles',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _productProfitability.length,
              itemBuilder: (context, index) {
                final product = _productProfitability[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue[100],
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: Colors.blue[700],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    product['product_name'] ?? 'Producto ${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    'Margen: ${_formatPercentage(product['profit_margin'] ?? 0.0)}',
                  ),
                  trailing: Text(
                    _formatCurrency(product['total_profit'] ?? 0.0),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green[700],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  String _formatCurrency(double amount) {
    return '\$${amount.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    )}';
  }

  String _formatPercentage(double percentage) {
    return '${percentage.toStringAsFixed(1)}%';
  }
}
