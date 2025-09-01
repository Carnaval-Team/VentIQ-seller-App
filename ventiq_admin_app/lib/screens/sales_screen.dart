import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../config/app_colors.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/admin_bottom_navigation.dart';
import '../models/sales.dart';
import '../services/mock_sales_service.dart';
import '../services/sales_service.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  List<Sale> _sales = [];
  List<TPV> _tpvs = [];
  List<ProductSalesReport> _productSalesReports = [];
  bool _isLoading = true;
  bool _isLoadingProducts = true;
  String _selectedPeriod = 'Hoy';
  String _selectedTPV = 'Todos';
  double _totalSales = 0.0;
  int _transactionCount = 0;
  bool _isLoadingMetrics = false;
  List<ProductAnalysis> _productAnalysis = [];
  bool _isLoadingAnalysis = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadSalesData();
    _loadProductAnalysis();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadSalesData() {
    setState(() => _isLoading = true);

    Future.delayed(const Duration(milliseconds: 800), () {
      setState(() {
        _sales = MockSalesService.getMockSales();
        _tpvs = MockSalesService.getMockTPVs();
        _isLoading = false;
      });
    });
    
    _loadProductSalesData();
  }

  void _loadProductSalesData() async {
    setState(() {
      _isLoadingProducts = true;
      _isLoadingMetrics = true;
    });

    try {
      // Get date range for the selected period
      final dateRange = _getDateRangeForPeriod(_selectedPeriod);
      
      // Load both product sales data and metrics
      final productSales = await SalesService.getProductSalesReport(
        fechaDesde: dateRange['start'],
        fechaHasta: dateRange['end'],
      );
      final metrics = await SalesService.getSalesMetrics(_selectedPeriod);
      
      setState(() {
        _productSalesReports = productSales;
        _totalSales = metrics['totalSales'] ?? 0.0;
        _transactionCount = metrics['transactionCount'] ?? 0;
        _isLoadingProducts = false;
        _isLoadingMetrics = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingProducts = false;
        _isLoadingMetrics = false;
      });
      print('Error loading sales data: $e');
    }
  }

  void _loadProductAnalysis() async {
    setState(() {
      _isLoadingAnalysis = true;
    });

    try {
      final dateRange = _getDateRangeForPeriod(_selectedPeriod);
      final analysis = await SalesService.getProductAnalysis(
        fechaDesde: dateRange['start'],
        fechaHasta: dateRange['end'],
      );
      
      setState(() {
        _productAnalysis = analysis;
        _isLoadingAnalysis = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingAnalysis = false;
      });
      print('Error loading product analysis: $e');
    }
  }

  Map<String, DateTime> _getDateRangeForPeriod(String period) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    switch (period) {
      case 'Hoy':
        return {
          'start': today,
          'end': today.add(const Duration(days: 1)).subtract(const Duration(seconds: 1)),
        };
      case 'Esta Semana':
        final startOfWeek = today.subtract(Duration(days: now.weekday - 1));
        return {
          'start': startOfWeek,
          'end': startOfWeek.add(const Duration(days: 7)).subtract(const Duration(seconds: 1)),
        };
      case 'Este Mes':
        final startOfMonth = DateTime(now.year, now.month, 1);
        final endOfMonth = DateTime(now.year, now.month + 1, 1).subtract(const Duration(seconds: 1));
        return {
          'start': startOfMonth,
          'end': endOfMonth,
        };
      case 'Este Año':
        final startOfYear = DateTime(now.year, 1, 1);
        final endOfYear = DateTime(now.year + 1, 1, 1).subtract(const Duration(seconds: 1));
        return {
          'start': startOfYear,
          'end': endOfYear,
        };
      default:
        return {
          'start': today,
          'end': today.add(const Duration(days: 1)).subtract(const Duration(seconds: 1)),
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Monitoreo de Ventas',
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
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadSalesData,
            tooltip: 'Actualizar',
          ),
          Builder(
            builder:
                (context) => IconButton(
                  icon: const Icon(Icons.menu, color: Colors.white),
                  onPressed: () => Scaffold.of(context).openEndDrawer(),
                  tooltip: 'Menú',
                ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Tiempo Real', icon: Icon(Icons.timeline, size: 18)),
            Tab(text: 'TPVs', icon: Icon(Icons.point_of_sale, size: 18)),
            Tab(text: 'Análisis', icon: Icon(Icons.analytics, size: 18)),
          ],
        ),
      ),
      body:
          _isLoading
              ? _buildLoadingState()
              : TabBarView(
                controller: _tabController,
                children: [
                  _buildRealTimeTab(),
                  _buildTPVsTab(),
                  _buildAnalyticsTab(),
                ],
              ),
      endDrawer: const AdminDrawer(),
      bottomNavigationBar: AdminBottomNavigation(
        currentIndex: 1,
        onTap: _onBottomNavTap,
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.primary),
    );
  }

  Widget _buildRealTimeTab() {
    final todaySales =
        _sales
            .where((sale) => sale.saleDate.day == DateTime.now().day)
            .toList();
    final totalToday = todaySales.fold(0.0, (sum, sale) => sum + sale.total);
    final salesCount = todaySales.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPeriodSelector(),
          const SizedBox(height: 16),
          _buildRealTimeMetrics(_totalSales, _transactionCount),
          const SizedBox(height: 20),
          _buildProductSalesReport(),
        ],
      ),
    );
  }

  Widget _buildTPVsTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _tpvs.length,
      itemBuilder: (context, index) => _buildTPVCard(_tpvs[index]),
    );
  }

  Widget _buildAnalyticsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProductAnalysisTable(),
        ],
      ),
    );
  }

  Widget _buildRealTimeMetrics(double totalSales, int salesCount) {
    String periodLabel = _selectedPeriod;
    if (_selectedPeriod == 'Hoy') {
      periodLabel = 'Hoy';
    } else if (_selectedPeriod == 'Esta Semana') {
      periodLabel = 'Esta Semana';
    } else if (_selectedPeriod == 'Este Mes') {
      periodLabel = 'Este Mes';
    } else if (_selectedPeriod == 'Este Año') {
      periodLabel = 'Este Año';
    }
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.attach_money,
                  color: AppColors.success,
                  size: 32,
                ),
                const SizedBox(height: 8),
                _isLoadingMetrics
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        '\$${totalSales.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.success,
                        ),
                      ),
                Text(
                  'Ventas $periodLabel',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                const Icon(Icons.receipt, color: AppColors.info, size: 32),
                const SizedBox(height: 8),
                _isLoadingMetrics
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        '$salesCount',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                Text(
                  'Productos $periodLabel',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProductSalesReport() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Reporte de Ventas por Producto',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          if (_isLoadingProducts)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (_productSalesReports.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'No hay datos de ventas para el período seleccionado',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 16,
                columns: const [
                  DataColumn(label: Text('Producto', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Total Vendido', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Precio Venta', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Costo USD', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Total Ventas', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Total Diferencia', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: _productSalesReports.map((report) {
                  return DataRow(
                    cells: [
                      DataCell(
                        SizedBox(
                          width: 120,
                          child: Text(
                            report.nombreProducto,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          '${report.totalVendido.toStringAsFixed(0)} uds',
                          style: const TextStyle(color: AppColors.info),
                        ),
                      ),
                      DataCell(
                        Text(
                          '\$${report.precioVentaCup.toStringAsFixed(2)}',
                          style: const TextStyle(color: AppColors.textPrimary),
                        ),
                      ),
                      DataCell(
                        Text(
                          '\$${report.precioCosto.toStringAsFixed(2)}',
                          style: const TextStyle(color: AppColors.warning),
                        ),
                      ),
                      DataCell(
                        Text(
                          '\$${report.ingresosTotales.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: AppColors.success,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          '\$${report.gananciaTotal.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: report.gananciaTotal >= 0 ? AppColors.success : AppColors.error,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProductAnalysisTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Análisis de Productos',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          if (_isLoadingAnalysis)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (_productAnalysis.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'No hay datos de productos disponibles',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 16,
                columns: const [
                  DataColumn(label: Text('Producto', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Precio Venta CUP', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Precio Venta USD', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Costo USD', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Valor USD', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Precio Costo CUP', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Ganancia', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('% Ganancia', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: _productAnalysis.map((analysis) {
                  return DataRow(
                    cells: [
                      DataCell(
                        SizedBox(
                          width: 120,
                          child: Text(
                            analysis.nombreProducto,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          '\$${analysis.precioVentaCup.toStringAsFixed(2)}',
                          style: const TextStyle(color: AppColors.success),
                        ),
                      ),
                      DataCell(
                        Text(
                          '\$${analysis.precioVentaUsd.toStringAsFixed(2)}',
                          style: const TextStyle(color: AppColors.info),
                        ),
                      ),
                      DataCell(
                        Text(
                          '\$${analysis.precioCosto.toStringAsFixed(2)}',
                          style: const TextStyle(color: AppColors.warning),
                        ),
                      ),
                      DataCell(
                        Text(
                          '\$${analysis.valorUsd.toStringAsFixed(2)}',
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                      DataCell(
                        Text(
                          '\$${analysis.precioCostoCup.toStringAsFixed(2)}',
                          style: const TextStyle(color: AppColors.textPrimary),
                        ),
                      ),
                      DataCell(
                        Text(
                          '\$${analysis.ganancia.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: analysis.ganancia >= 0 ? AppColors.success : AppColors.error,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          '${analysis.porcentajeGanancia.toStringAsFixed(1)}%',
                          style: TextStyle(
                            color: analysis.porcentajeGanancia >= 0 ? AppColors.success : AppColors.error,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.date_range, color: AppColors.primary),
          const SizedBox(width: 12),
          const Text(
            'Período: ',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          Expanded(
            child: DropdownButton<String>(
              value: _selectedPeriod,
              isExpanded: true,
              underline: Container(),
              items: ['Hoy', 'Esta Semana', 'Este Mes', 'Este Año'].map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (value) {
                setState(() => _selectedPeriod = value!);
                _loadProductSalesData();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTPVCard(TPV tpv) {
    final tpvSales = _sales.where((sale) => sale.tpvId == tpv.id).length;
    final tpvTotal = _sales
        .where((sale) => sale.tpvId == tpv.id)
        .fold(0.0, (sum, sale) => sum + sale.total);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              tpv.isActive
                  ? AppColors.success.withOpacity(0.1)
                  : AppColors.error.withOpacity(0.1),
          child: Icon(
            Icons.point_of_sale,
            color: tpv.isActive ? AppColors.success : AppColors.error,
          ),
        ),
        title: Text(
          tpv.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tienda: ${tpv.storeName}'),
            Text('$tpvSales ventas • \$${tpvTotal.toStringAsFixed(2)}'),
          ],
        ),
        trailing: Icon(
          tpv.isActive ? Icons.check_circle : Icons.cancel,
          color: tpv.isActive ? AppColors.success : AppColors.error,
        ),
      ),
    );
  }


  Widget _buildSalesChart() {
    return Container(
      height: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tendencia de Ventas',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: false),
                titlesData: FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: List.generate(
                      7,
                      (index) => FlSpot(
                        index.toDouble(),
                        (index * 100 + 200).toDouble(),
                      ),
                    ),
                    isCurved: true,
                    color: AppColors.primary,
                    barWidth: 3,
                    dotData: FlDotData(show: false),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopProducts() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Productos Más Vendidos',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          ...List.generate(
            5,
            (index) => ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withOpacity(0.1),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text('Producto ${index + 1}'),
              subtitle: Text('${50 - index * 5} unidades vendidas'),
              trailing: Text(
                '\$${(1000 - index * 100).toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onBottomNavTap(int index) {
    switch (index) {
      case 0: // Dashboard
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/dashboard',
          (route) => false,
        );
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
