import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../config/app_colors.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/admin_bottom_navigation.dart';
import '../services/mock_data_service.dart';
import '../services/mock_sales_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isLoading = true;
  Map<String, dynamic> _dashboardData = {};
  String _selectedTimeFilter = '1 mes';
  
  final List<String> _timeFilterOptions = [
    '5 años',
    '3 años', 
    '1 año',
    '6 meses',
    '3 meses',
    '1 mes',
    'Semana',
    'Día'
  ];

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  void _loadDashboardData() {
    setState(() {
      _isLoading = true;
    });
    
    // Simular carga de datos del dashboard con filtro de tiempo
    Future.delayed(const Duration(milliseconds: 1000), () {
      final products = MockDataService.getMockProducts();
      final inventory = MockDataService.getMockInventory();
      final sales = MockSalesService.getMockSales();
      final expenses = MockSalesService.getMockExpenses();
      
      setState(() {
        _dashboardData = {
          'totalProducts': products.length,
          'totalSales': sales.fold(0.0, (sum, sale) => sum + sale.total),
          'totalOrders': sales.length,
          'totalExpenses': expenses.fold(0.0, (sum, expense) => sum + expense.amount),
          'outOfStock': inventory.where((item) => item.currentStock == 0).length,
          'lowStock': inventory.where((item) => item.needsRestock).length,
          'okStock': inventory.where((item) => !item.needsRestock && item.currentStock > 0).length,
          'salesData': _generateSalesData(_selectedTimeFilter),
          'categoryData': _generateCategoryData(products),
        };
        _isLoading = false;
      });
    });
  }

  List<FlSpot> _generateSalesData(String timeFilter) {
    // Generar datos basados en el filtro de tiempo seleccionado
    switch (timeFilter) {
      case 'Día':
        return [
          const FlSpot(0, 150),   // 6 AM
          const FlSpot(1, 280),   // 9 AM
          const FlSpot(2, 420),   // 12 PM
          const FlSpot(3, 380),   // 3 PM
          const FlSpot(4, 520),   // 6 PM
          const FlSpot(5, 340),   // 9 PM
        ];
      case 'Semana':
        return [
          const FlSpot(0, 1200),  // Lun
          const FlSpot(1, 1800),  // Mar
          const FlSpot(2, 1500),  // Mié
          const FlSpot(3, 2200),  // Jue
          const FlSpot(4, 1900),  // Vie
          const FlSpot(5, 2800),  // Sáb
          const FlSpot(6, 2400),  // Dom
        ];
      case '1 mes':
        return [
          const FlSpot(0, 8500),   // Semana 1
          const FlSpot(1, 12300),  // Semana 2
          const FlSpot(2, 10800),  // Semana 3
          const FlSpot(3, 15200),  // Semana 4
        ];
      case '3 meses':
        return [
          const FlSpot(0, 35000),  // Mes 1
          const FlSpot(1, 42000),  // Mes 2
          const FlSpot(2, 38500),  // Mes 3
        ];
      case '6 meses':
        return [
          const FlSpot(0, 35000),
          const FlSpot(1, 42000),
          const FlSpot(2, 38500),
          const FlSpot(3, 45200),
          const FlSpot(4, 41800),
          const FlSpot(5, 48300),
        ];
      case '1 año':
        return [
          const FlSpot(0, 120000), // Ene-Mar
          const FlSpot(1, 135000), // Abr-Jun
          const FlSpot(2, 142000), // Jul-Sep
          const FlSpot(3, 158000), // Oct-Dic
        ];
      case '3 años':
        return [
          const FlSpot(0, 480000), // Año 1
          const FlSpot(1, 520000), // Año 2
          const FlSpot(2, 580000), // Año 3
        ];
      case '5 años':
        return [
          const FlSpot(0, 480000), // Año 1
          const FlSpot(1, 520000), // Año 2
          const FlSpot(2, 580000), // Año 3
          const FlSpot(3, 620000), // Año 4
          const FlSpot(4, 680000), // Año 5
        ];
      default:
        return [
          const FlSpot(0, 1200),
          const FlSpot(1, 1800),
          const FlSpot(2, 1500),
          const FlSpot(3, 2200),
          const FlSpot(4, 1900),
          const FlSpot(5, 2800),
          const FlSpot(6, 2400),
        ];
    }
  }

  List<PieChartSectionData> _generateCategoryData(products) {
    final categoryCount = <String, int>{};
    for (var product in products) {
      categoryCount[product.categoryName] = (categoryCount[product.categoryName] ?? 0) + 1;
    }
    
    final colors = [AppColors.primary, AppColors.success, AppColors.warning, AppColors.error, AppColors.info];
    int colorIndex = 0;
    
    return categoryCount.entries.map((entry) {
      final color = colors[colorIndex % colors.length];
      colorIndex++;
      return PieChartSectionData(
        color: color,
        value: entry.value.toDouble(),
        title: '${entry.key}\n${entry.value}',
        radius: 50,
        titleStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Dashboard Ejecutivo',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        backgroundColor: AppColors.primary,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => Scaffold.of(context).openEndDrawer(),
              tooltip: 'Menú',
            ),
          ),
        ],
      ),
      body: _isLoading ? _buildLoadingState() : _buildDashboard(),
      endDrawer: const AdminDrawer(),
      bottomNavigationBar: AdminBottomNavigation(
        currentIndex: 0,
        onTap: _onBottomNavTap,
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppColors.primary),
          SizedBox(height: 16),
          Text(
            'Cargando dashboard...',
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filtro de tiempo
          _buildTimeFilterSection(),
          const SizedBox(height: 24),
          
          // KPIs principales
          _buildKPISection(),
          const SizedBox(height: 24),
          
          // Métricas de ventas
          _buildSalesSection(),
          const SizedBox(height: 24),
          
          // Distribución por categorías
          _buildCategorySection(),
          const SizedBox(height: 24),
          
          // Estado del inventario
          _buildInventorySection(),
          const SizedBox(height: 24),
          
          // Accesos rápidos
          _buildQuickActionsSection(),
        ],
      ),
    );
  }

  Widget _buildTimeFilterSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.filter_list,
            color: AppColors.primary,
            size: 24,
          ),
          const SizedBox(width: 12),
          const Text(
            'Período:',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(8),
                color: AppColors.background,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedTimeFilter,
                  isExpanded: true,
                  icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.primary),
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                  items: _timeFilterOptions.map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    if (newValue != null && newValue != _selectedTimeFilter) {
                      setState(() {
                        _selectedTimeFilter = newValue;
                      });
                      _loadDashboardData();
                    }
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKPISection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'KPIs Principales',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: AppColors.primary),
              onPressed: _loadDashboardData,
              tooltip: 'Actualizar datos',
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildKPICard(
                title: 'Ventas Total',
                value: '\$${_dashboardData['totalSales']?.toStringAsFixed(2) ?? '0.00'}',
                subtitle: '+15% vs ayer',
                icon: Icons.trending_up,
                color: AppColors.success,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildKPICard(
                title: 'Productos',
                value: '${_dashboardData['totalProducts'] ?? 0}',
                subtitle: '${_dashboardData['outOfStock'] ?? 0} sin stock',
                icon: Icons.inventory,
                color: AppColors.warning,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildKPICard(
                title: 'Órdenes',
                value: '${_dashboardData['totalOrders'] ?? 0}',
                subtitle: 'Completadas',
                icon: Icons.receipt_long,
                color: AppColors.info,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildKPICard(
                title: 'Gastos',
                value: '\$${_dashboardData['totalExpenses']?.toStringAsFixed(2) ?? '0.00'}',
                subtitle: 'Este mes',
                icon: Icons.money_off,
                color: AppColors.error,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKPICard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Icon(
                icon,
                size: 20,
                color: color,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tendencia de Ventas ($_selectedTimeFilter)',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          height: 200,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 500,
                getDrawingHorizontalLine: (value) {
                  return FlLine(
                    color: AppColors.border,
                    strokeWidth: 1,
                  );
                },
              ),
              titlesData: FlTitlesData(
                show: true,
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: 1,
                    getTitlesWidget: (double value, TitleMeta meta) {
                      return SideTitleWidget(
                        axisSide: meta.axisSide,
                        child: Text(
                          _getChartLabel(value.toInt()),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 500,
                    getTitlesWidget: (double value, TitleMeta meta) {
                      return Text(
                        '\$${(value / 1000).toStringAsFixed(1)}K',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                      );
                    },
                    reservedSize: 42,
                  ),
                ),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border.all(color: AppColors.border, width: 1),
              ),
              minX: 0,
              maxX: _getMaxX(),
              minY: 0,
              maxY: _getMaxY(),
              lineBarsData: [
                LineChartBarData(
                  spots: _dashboardData['salesData'] ?? [],
                  isCurved: true,
                  gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.primary.withOpacity(0.3)],
                  ),
                  barWidth: 3,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(
                    show: true,
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary.withOpacity(0.3),
                        AppColors.primary.withOpacity(0.1),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Distribución por Categorías',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          height: 250,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: PieChart(
            PieChartData(
              sections: _dashboardData['categoryData'] ?? [],
              borderData: FlBorderData(show: false),
              sectionsSpace: 2,
              centerSpaceRadius: 60,
              startDegreeOffset: -90,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInventorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Estado del Inventario',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildInventoryItem(
                  'Sin Stock',
                  '${_dashboardData['outOfStock'] ?? 0}',
                  Icons.warning,
                  AppColors.error,
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: AppColors.border,
              ),
              Expanded(
                child: _buildInventoryItem(
                  'Stock Bajo',
                  '${_dashboardData['lowStock'] ?? 0}',
                  Icons.inventory_2,
                  AppColors.warning,
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: AppColors.border,
              ),
              Expanded(
                child: _buildInventoryItem(
                  'Stock OK',
                  '${_dashboardData['okStock'] ?? 0}',
                  Icons.check_circle,
                  AppColors.success,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInventoryItem(String title, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(
          icon,
          size: 24,
          color: color,
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildQuickActionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Accesos Rápidos',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 2.5,
          children: [
            _buildQuickActionCard(
              'Productos',
              Icons.inventory_2,
              AppColors.primary,
              () => Navigator.pushNamed(context, '/products'),
            ),
            _buildQuickActionCard(
              'Categorías',
              Icons.category,
              AppColors.success,
              () => Navigator.pushNamed(context, '/categories'),
            ),
            _buildQuickActionCard(
              'Inventario',
              Icons.warehouse,
              AppColors.warning,
              () => Navigator.pushNamed(context, '/inventory'),
            ),
            _buildQuickActionCard(
              'Ventas',
              Icons.point_of_sale,
              AppColors.info,
              () => Navigator.pushNamed(context, '/sales'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickActionCard(String title, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: double.infinity,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Icon(
              icon,
              size: 24,
              color: color,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getChartLabel(int index) {
    switch (_selectedTimeFilter) {
      case 'Día':
        const labels = ['6AM', '9AM', '12PM', '3PM', '6PM', '9PM'];
        return index < labels.length ? labels[index] : '';
      case 'Semana':
        const labels = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
        return index < labels.length ? labels[index] : '';
      case '1 mes':
        const labels = ['S1', 'S2', 'S3', 'S4'];
        return index < labels.length ? labels[index] : '';
      case '3 meses':
        const labels = ['Mes 1', 'Mes 2', 'Mes 3'];
        return index < labels.length ? labels[index] : '';
      case '6 meses':
        const labels = ['M1', 'M2', 'M3', 'M4', 'M5', 'M6'];
        return index < labels.length ? labels[index] : '';
      case '1 año':
        const labels = ['Q1', 'Q2', 'Q3', 'Q4'];
        return index < labels.length ? labels[index] : '';
      case '3 años':
        const labels = ['Año 1', 'Año 2', 'Año 3'];
        return index < labels.length ? labels[index] : '';
      case '5 años':
        const labels = ['A1', 'A2', 'A3', 'A4', 'A5'];
        return index < labels.length ? labels[index] : '';
      default:
        return '';
    }
  }

  double _getMaxX() {
    switch (_selectedTimeFilter) {
      case 'Día':
        return 5;
      case 'Semana':
        return 6;
      case '1 mes':
        return 3;
      case '3 meses':
        return 2;
      case '6 meses':
        return 5;
      case '1 año':
        return 3;
      case '3 años':
        return 2;
      case '5 años':
        return 4;
      default:
        return 6;
    }
  }

  double _getMaxY() {
    switch (_selectedTimeFilter) {
      case 'Día':
        return 600;
      case 'Semana':
        return 3000;
      case '1 mes':
        return 20000;
      case '3 meses':
        return 50000;
      case '6 meses':
        return 60000;
      case '1 año':
        return 200000;
      case '3 años':
        return 700000;
      case '5 años':
        return 800000;
      default:
        return 3000;
    }
  }

  void _onBottomNavTap(int index) {
    switch (index) {
      case 0: // Dashboard (current)
        break;
      case 1: // Productos
        Navigator.pushNamed(context, '/products');
        break;
      case 2: // Inventario
        Navigator.pushNamed(context, '/inventory');
        break;
      case 3: // Configuración
        Navigator.pushNamed(context, '/settings');
        break;
    }
  }
}
