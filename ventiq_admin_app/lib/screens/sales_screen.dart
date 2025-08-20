import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../config/app_colors.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/admin_bottom_navigation.dart';
import '../models/sales.dart';
import '../services/mock_sales_service.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  List<Sale> _sales = [];
  List<TPV> _tpvs = [];
  bool _isLoading = true;
  String _selectedPeriod = 'Hoy';
  String _selectedTPV = 'Todos';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadSalesData();
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
            builder: (context) => IconButton(
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
      body: _isLoading ? _buildLoadingState() : TabBarView(
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
    final todaySales = _sales.where((sale) => 
      sale.saleDate.day == DateTime.now().day).toList();
    final totalToday = todaySales.fold(0.0, (sum, sale) => sum + sale.total);
    final salesCount = todaySales.length;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRealTimeMetrics(totalToday, salesCount),
          const SizedBox(height: 20),
          _buildRecentSales(todaySales.take(10).toList()),
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
        children: [
          _buildPeriodSelector(),
          const SizedBox(height: 20),
          _buildSalesChart(),
          const SizedBox(height: 20),
          _buildTopProducts(),
        ],
      ),
    );
  }

  Widget _buildRealTimeMetrics(double totalToday, int salesCount) {
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
                const Icon(Icons.attach_money, color: AppColors.success, size: 32),
                const SizedBox(height: 8),
                Text('\$${totalToday.toStringAsFixed(2)}', 
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.success)),
                const Text('Ventas Hoy', style: TextStyle(color: AppColors.textSecondary)),
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
                Text('$salesCount', 
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.info)),
                const Text('Transacciones', style: TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentSales(List<Sale> recentSales) {
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
            child: Text('Ventas Recientes', 
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          ...recentSales.map((sale) => ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withOpacity(0.1),
              child: const Icon(Icons.receipt, color: AppColors.primary),
            ),
            title: Text('Venta #${sale.id.substring(0, 8)}'),
            subtitle: Text('${sale.customerName} • ${sale.tpvName}'),
            trailing: Text('\$${sale.total.toStringAsFixed(2)}', 
              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.success)),
          )),
        ],
      ),
    );
  }

  Widget _buildTPVCard(TPV tpv) {
    final tpvSales = _sales.where((sale) => sale.tpvId == tpv.id).length;
    final tpvTotal = _sales.where((sale) => sale.tpvId == tpv.id)
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
          backgroundColor: tpv.isActive ? AppColors.success.withOpacity(0.1) : AppColors.error.withOpacity(0.1),
          child: Icon(Icons.point_of_sale, 
            color: tpv.isActive ? AppColors.success : AppColors.error),
        ),
        title: Text(tpv.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tienda: ${tpv.storeName}'),
            Text('$tpvSales ventas • \$${tpvTotal.toStringAsFixed(2)}'),
          ],
        ),
        trailing: Icon(tpv.isActive ? Icons.check_circle : Icons.cancel,
          color: tpv.isActive ? AppColors.success : AppColors.error),
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
          const Text('Período: ', style: TextStyle(fontWeight: FontWeight.w600)),
          Expanded(
            child: DropdownButton<String>(
              value: _selectedPeriod,
              isExpanded: true,
              underline: Container(),
              items: ['Hoy', 'Esta Semana', 'Este Mes', 'Este Año'].map((String value) {
                return DropdownMenuItem<String>(value: value, child: Text(value));
              }).toList(),
              onChanged: (value) => setState(() => _selectedPeriod = value!),
            ),
          ),
        ],
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
          const Text('Tendencia de Ventas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: false),
                titlesData: FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: List.generate(7, (index) => 
                      FlSpot(index.toDouble(), (index * 100 + 200).toDouble())),
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
            child: Text('Productos Más Vendidos', 
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          ...List.generate(5, (index) => ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withOpacity(0.1),
              child: Text('${index + 1}', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
            ),
            title: Text('Producto ${index + 1}'),
            subtitle: Text('${50 - index * 5} unidades vendidas'),
            trailing: Text('\$${(1000 - index * 100).toStringAsFixed(2)}', 
              style: const TextStyle(fontWeight: FontWeight.bold)),
          )),
        ],
      ),
    );
  }

  void _onBottomNavTap(int index) {
    switch (index) {
      case 0: // Dashboard
        Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (route) => false);
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
