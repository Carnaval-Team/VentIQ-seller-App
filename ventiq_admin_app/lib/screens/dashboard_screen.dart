import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../config/app_colors.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/admin_bottom_navigation.dart';
import '../services/dashboard_service.dart';
import '../services/currency_service.dart';
import '../services/user_preferences_service.dart';

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
  final UserPreferencesService _userPreferencesService = UserPreferencesService();
  
  String _currentStoreName = 'Cargando...';
  List<Map<String, dynamic>> _userStores = [];
  
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
    _loadStoreInfo();
    _loadDashboardData();
  }

  Future<void> _loadStoreInfo() async {
    try {
      final stores = await _userPreferencesService.getUserStores();
      final currentStoreInfo = await _userPreferencesService.getCurrentStoreInfo();
      
      setState(() {
        _userStores = stores;
        _currentStoreName = currentStoreInfo?['denominacion'] ?? 'Tienda Principal';
      });
    } catch (e) {
      print('❌ Error loading store info: $e');
      setState(() {
        _currentStoreName = 'Tienda Principal';
      });
    }
  }

  void _loadDashboardData() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Fetch and update exchange rates first
      print('💱 Fetching exchange rates...');
      await CurrencyService.fetchAndUpdateExchangeRates();
      
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
          'categoryData': [
            {'name': 'Sin datos', 'value': 1, 'color': 0xFF9E9E9E}
          ],
          'period': _selectedTimeFilter,
          'lastUpdated': DateTime.now().toIso8601String(),
        };
        _isLoading = false;
      });
    });
  }

  Future<void> _showStoreSelectionDialog() async {
    if (_userStores.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay tiendas disponibles'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final selectedStore = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.store, color: AppColors.primary),
              SizedBox(width: 8),
              Text('Seleccionar Tienda'),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _userStores.length,
              itemBuilder: (context, index) {
                final store = _userStores[index];
                final isCurrentStore = store['denominacion'] == _currentStoreName;
                
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isCurrentStore 
                        ? AppColors.primary 
                        : AppColors.primary.withOpacity(0.1),
                    child: Icon(
                      Icons.store,
                      color: isCurrentStore ? Colors.white : AppColors.primary,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    store['denominacion'] ?? 'Tienda ${store['id_tienda']}',
                    style: TextStyle(
                      fontWeight: isCurrentStore ? FontWeight.bold : FontWeight.normal,
                      color: isCurrentStore ? AppColors.primary : null,
                    ),
                  ),
                  subtitle: Text('ID: ${store['id_tienda']}'),
                  trailing: isCurrentStore 
                      ? const Icon(Icons.check_circle, color: AppColors.primary)
                      : null,
                  onTap: () {
                    Navigator.of(context).pop(store);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    );

    if (selectedStore != null && selectedStore['denominacion'] != _currentStoreName) {
      await _switchStore(selectedStore);
    }
  }

  Future<void> _switchStore(Map<String, dynamic> store) async {
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Cambiando tienda...'),
            ],
          ),
        ),
      );

      // Update selected store in preferences
      await _userPreferencesService.updateSelectedStore(store['id_tienda']);
      
      // Update current store name
      setState(() {
        _currentStoreName = store['denominacion'] ?? 'Tienda ${store['id_tienda']}';
      });

      // Reload dashboard data for new store
      _loadDashboardData();

      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
        
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cambiado a: ${store['denominacion']}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('❌ Error switching store: $e');
      
      // Close loading dialog if still open
      if (mounted) {
        Navigator.of(context).pop();
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al cambiar tienda'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
          // Store selector button
          if (_userStores.length > 1)
            IconButton(
              icon: const Icon(Icons.store, color: Colors.white),
              onPressed: _showStoreSelectionDialog,
              tooltip: 'Seleccionar Tienda: $_currentStoreName',
            ),
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
                value: '\$${_formatCurrency(_dashboardData['totalSales']?.toDouble() ?? 0.0)}',
                subtitle: '${_dashboardData['salesChange']>=0 ?'+':'-'} ${_dashboardData['salesChange']?.toStringAsFixed(2) ?? '0.00'}% ${_getPreviousPeriodLabel()}',
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
                value: '\$${_formatCurrency(_dashboardData['totalExpenses']?.toDouble() ?? 0.0)}',
                subtitle: _getPeriodLabel(),
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
          height: 230,
          padding: const EdgeInsets.fromLTRB(0,12,12,0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Center(
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
                      reservedSize: 40,
                      interval: _getXAxisInterval(),
                      getTitlesWidget: (double value, TitleMeta meta) {
                        final label = _getChartLabel(value.toInt());
                        if (label.isEmpty) return const SizedBox.shrink();
                        
                        return SideTitleWidget(
                          axisSide: meta.axisSide,
                          child: Container(
                            width: 35,
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              label,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w500,
                                fontSize: 10,
                              ),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.visible,
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
                        return Container(
                          width: 55,
                          padding: const EdgeInsets.only(right: 6),
                          child: Text(
                            _formatYAxisLabel(value),
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                              fontSize: 10,
                            ),
                            textAlign: TextAlign.right,
                            overflow: TextOverflow.visible,
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
                clipData: FlClipData.none(),
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
        ),
      ],
    );
  }

  Widget _buildCategorySection() {
    final categoryData = _dashboardData['categoryData'] as List<Map<String, dynamic>>? ?? [];
    
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
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              // Pie Chart
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 200,
                  child: PieChart(
                    PieChartData(
                      sections: _buildPieSections(categoryData),
                      borderData: FlBorderData(show: false),
                      sectionsSpace: 2,
                      centerSpaceRadius: 50,
                      startDegreeOffset: -90,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Legend
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: categoryData.map((item) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Color(item['color'] ?? 0xFF9E9E9E),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item['name'] ?? 'Sin nombre',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<PieChartSectionData> _buildPieSections(List<Map<String, dynamic>> categoryData) {
    return categoryData.map((item) {
      return PieChartSectionData(
        color: Color(item['color'] ?? 0xFF9E9E9E),
        value: (item['value'] ?? 0).toDouble(),
        radius: 60,
        showTitle: false, // No mostrar títulos en el pie
      );
    }).toList();
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
    // Usar las etiquetas reales del servicio si están disponibles
    if (_dashboardData != null && 
        _dashboardData['salesLabels'] != null && 
        _dashboardData['salesLabels'] is List<String>) {
      final labels = _dashboardData['salesLabels'] as List<String>;
      return index < labels.length ? labels[index] : '';
    }
    
    // Fallback a etiquetas estáticas si no hay datos del servicio
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

  /// Obtiene el intervalo para mostrar etiquetas en el eje X
  double _getXAxisInterval() {
    final maxX = _getMaxX();
    
    // Para evitar sobreposición de etiquetas según el período
    switch (_selectedTimeFilter) {
      case 'Día':
        return 1; // Mostrar todas las horas
      case 'Semana':
        return 1; // Mostrar todos los días
      case '1 mes':
        // Para mes, mostrar cada 5 días para evitar sobreposición
        return maxX > 15 ? 5 : 3;
      case '3 meses':
      case '6 meses':
        return maxX > 10 ? 2 : 1;
      case '1 año':
      case '3 años':
      case '5 años':
        return 1;
      default:
        // Lógica general para otros casos
        if (maxX <= 6) {
          return 1;
        } else if (maxX <= 12) {
          return 2;
        } else {
          return (maxX / 5).ceilToDouble();
        }
    }
  }

  double _getMaxX() {
    // Usar el número real de datos si están disponibles
    if (_dashboardData != null && _dashboardData['salesData'] != null) {
      final salesData = _dashboardData['salesData'] as List<FlSpot>;
      if (salesData.isNotEmpty) {
        return salesData.length.toDouble() - 1;
      }
    }
    
    // Fallback a valores por defecto
    switch (_selectedTimeFilter) {
      case 'Día':
        return 5;
      case 'Semana':
        return 6;
      case '1 mes':
        return 30; // Cambiar de 3 a 30 para días del mes
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
    
    // Calcular intervalo dinámico para mostrar máximo 10 etiquetas
    // Dividir maxY entre 8-10 para obtener un intervalo apropiado
    double targetInterval = maxY / 8;
    
    // Redondear a números "bonitos"
    if (targetInterval <= 1) {
      return 1;
    } else if (targetInterval <= 2) {
      return 2;
    } else if (targetInterval <= 5) {
      return 5;
    } else if (targetInterval <= 10) {
      return 10;
    } else if (targetInterval <= 20) {
      return 20;
    } else if (targetInterval <= 50) {
      return 50;
    } else if (targetInterval <= 100) {
      return 100;
    } else if (targetInterval <= 200) {
      return 200;
    } else if (targetInterval <= 500) {
      return 500;
    } else if (targetInterval <= 1000) {
      return 1000;
    } else if (targetInterval <= 2000) {
      return 2000;
    } else if (targetInterval <= 5000) {
      return 5000;
    } else if (targetInterval <= 10000) {
      return 10000;
    } else if (targetInterval <= 20000) {
      return 20000;
    } else if (targetInterval <= 50000) {
      return 50000;
    } else if (targetInterval <= 100000) {
      return 100000;
    } else if (targetInterval <= 200000) {
      return 200000;
    } else if (targetInterval <= 500000) {
      return 500000;
    } else if (targetInterval <= 1000000) {
      return 1000000;
    } else if (targetInterval <= 2000000) {
      return 2000000;
    } else if (targetInterval <= 5000000) {
      return 5000000;
    } else {
      return 10000000;
    }
  }

  String _formatYAxisLabel(double value) {
    if (value == 0) return '0';
    
    if (value >= 1000000) {
      // Para millones, mostrar con 1 decimal si es necesario
      double millions = value / 1000000;
      if (millions == millions.roundToDouble()) {
        return '${millions.toStringAsFixed(0)}M';
      } else {
        return '${millions.toStringAsFixed(1)}M';
      }
    } else if (value >= 1000) {
      // Para miles, sin decimales
      return '${(value / 1000).toStringAsFixed(0)}K';
    } else {
      return value.toStringAsFixed(0);
    }
  }

  /// Formatea valores de moneda para mostrar K y M para números grandes
  String _formatCurrency(double value) {
    if (value == 0) return '0.00';
    
    if (value >= 1000000) {
      // Para millones, mostrar con 1 decimal
      double millions = value / 1000000;
      if (millions == millions.roundToDouble()) {
        return '${millions.toStringAsFixed(0)}M';
      } else {
        return '${millions.toStringAsFixed(1)}M';
      }
    } else if (value >= 100000) {
      // Para valores >= 100,000, mostrar en K sin decimales
      return '${(value / 1000).toStringAsFixed(0)}K';
    } else {
      // Para valores menores, mostrar con decimales normales
      return value.toStringAsFixed(2);
    }
  }

  /// Obtiene la etiqueta en español para mostrar en la UI según el período seleccionado
  String _getPeriodLabel() {
    switch (_selectedTimeFilter) {
      case 'Día':
        return 'Hoy';
      case 'Semana':
        return 'Esta semana';
      case '1 mes':
        return 'Este mes';
      case '3 meses':
        return 'Últimos 3 meses';
      case '6 meses':
        return 'Últimos 6 meses';
      case '1 año':
        return 'Este año';
      case '3 años':
        return 'Últimos 3 años';
      case '5 años':
        return 'Últimos 5 años';
      default:
        return 'Este período';
    }
  }

  /// Obtiene la etiqueta de comparación para el período anterior
  String _getPreviousPeriodLabel() {
    switch (_selectedTimeFilter) {
      case 'Día':
        return 'vs ayer';
      case 'Semana':
        return 'vs semana anterior';
      case '1 mes':
        return 'vs mes anterior';
      case '3 meses':
        return 'vs 3 meses anteriores';
      case '6 meses':
        return 'vs 6 meses anteriores';
      case '1 año':
        return 'vs año anterior';
      case '3 años':
        return 'vs 3 años anteriores';
      case '5 años':
        return 'vs 5 años anteriores';
      default:
        return 'vs período anterior';
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
