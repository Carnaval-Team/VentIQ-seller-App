import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../config/app_colors.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/admin_bottom_navigation.dart';
import '../services/dashboard_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isLoading = true;
  Map<String, dynamic> _dashboardData = {};
  String _selectedTimeFilter = '1 mes';
  final DashboardService _dashboardService = DashboardService();
  
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

  void _loadDashboardData() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Validar que el supervisor tenga id_tienda
      final hasValidStore = await _dashboardService.validateSupervisorStore();
      
      if (!hasValidStore) {
        print('❌ Supervisor no tiene id_tienda válido');
        // Fallback a datos mock si no hay id_tienda
        _loadMockData();
        return;
      }
      
      // Llamar a la función RPC con el período seleccionado
      print('🔄 Loading dashboard data for period: $_selectedTimeFilter');
      final realData = await _dashboardService.getStoreAnalysis(
        periodo: _selectedTimeFilter,
      );
      
      if (realData != null) {
        print('✅ Real data loaded successfully');
        setState(() {
          _dashboardData = realData;
          _isLoading = false;
        });
      } else {
        print('⚠️ No real data available, using mock data');
        _loadMockData();
      }
    } catch (e) {
      print('❌ Error loading dashboard data: $e');
      _loadMockData();
    }
  }
  
  void _loadMockData() {
    // Fallback con datos básicos cuando no hay datos reales
    Future.delayed(const Duration(milliseconds: 500), () {
      setState(() {
        _dashboardData = {
          'totalProducts': 0,
          'totalSales': 0.0,
          'totalOrders': 0,
          'totalExpenses': 0.0,
          'salesChange': 0.0,
          'ordersChange': 0.0,
          'productsChange': 0.0,
          'expensesChange': 0.0,
          'outOfStock': 0,
          'lowStock': 0,
          'okStock': 0,
          'salesData': <FlSpot>[],
          'categoryData': [{'name': 'Sin datos', 'value': 1, 'color': 0xFF9E9E9E}],
          'period': _selectedTimeFilter,
          'lastUpdated': DateTime.now().toIso8601String(),
        };
        _isLoading = false;
      });
    });
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
                subtitle: '${_dashboardData['salesChange']>=0 ?'+':'-'} ${_dashboardData['salesChange']?.toStringAsFixed(2) ?? '0.00'}% vs ayer',
                icon: Icons.trending_up,
                color: AppColors.success,
                onTap: () => Navigator.pushNamed(context, '/sales'),
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
    VoidCallback? onTap,
  }) {
    Widget cardContent = Container(
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

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: cardContent,
      );
    }

    return cardContent;
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
                horizontalInterval: _getYAxisInterval(),
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
                    interval: _getYAxisInterval(),
                    reservedSize: 60,
                    getTitlesWidget: (double value, TitleMeta meta) {
                      return Text(
                        _formatYAxisLabel(value),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                      );
                    },
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
    // Obtener el valor máximo de los datos reales
    final salesData = _dashboardData['salesData'] as List<FlSpot>? ?? [];
    if (salesData.isEmpty) {
      return 1000; // Valor por defecto
    }
    
    double maxValue = salesData.map((spot) => spot.y).reduce((a, b) => a > b ? a : b);
    
    // Agregar un 20% de margen superior para que el gráfico se vea mejor
    return maxValue * 1.2;
  }

  double _getYAxisInterval() {
    final maxY = _getMaxY();
    
    // Calcular intervalo dinámico para mostrar aproximadamente 5-6 etiquetas
    if (maxY <= 100) {
      return 20;
    } else if (maxY <= 500) {
      return 100;
    } else if (maxY <= 1000) {
      return 200;
    } else if (maxY <= 5000) {
      return 1000;
    } else if (maxY <= 10000) {
      return 2000;
    } else if (maxY <= 50000) {
      return 10000;
    } else if (maxY <= 100000) {
      return 20000;
    } else {
      return 50000;
    }
  }

  String _formatYAxisLabel(double value) {
    if (value == 0) return '0';
    
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(0)}K';
    } else {
      return value.toStringAsFixed(0);
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
