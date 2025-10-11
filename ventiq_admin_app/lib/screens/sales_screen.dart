import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_colors.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/admin_bottom_navigation.dart';
import '../models/sales.dart';
import '../services/sales_service.dart';
import '../services/user_preferences_service.dart';

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  List<Sale> _sales = [];
  List<SalesVendorReport> _vendorReports = [];
  List<ProductSalesReport> _productSalesReports = [];
  bool _isLoading = true;
  bool _isLoadingProducts = true;
  bool _isLoadingVendors = true;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  String _selectedTPV = 'Todos';
  double _totalSales = 0.0;
  int _totalProductsSold = 0;
  bool _isLoadingMetrics = false;
  List<ProductAnalysis> _productAnalysis = [];
  bool _isLoadingAnalysis = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initializeDateRange();
    _loadSalesData();
  }

  void _initializeDateRange() {
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, now.day, 0, 0, 0);
    _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadSalesData() {
    setState(() => _isLoading = true);
    _loadProductSalesData();
    _loadVendorReports();
    _loadProductAnalysis(); // Cargar análisis de productos automáticamente
  }

  void _loadProductSalesData() async {
    setState(() {
      _isLoadingProducts = true;
      _isLoadingMetrics = true;
    });

    try {
      // Use the selected date range
      final dateRange = {'start': _startDate, 'end': _endDate};

      // Load product sales data
      final productSales = await SalesService.getProductSalesReport(
        fechaDesde: dateRange['start'],
        fechaHasta: dateRange['end'],
      );

      setState(() {
        _productSalesReports = productSales;
        // Calculate total sales from product sales reports
        _totalSales = productSales.fold<double>(
          0.0,
          (sum, report) => sum + report.ingresosTotales,
        );
        // Calculate total products sold from product sales reports
        _totalProductsSold = productSales.fold<int>(
          0,
          (sum, report) => sum + report.totalVendido.toInt(),
        );
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

  void _loadVendorReports() async {
    setState(() {
      _isLoadingVendors = true;
    });

    try {
      final reports = await SalesService.getSalesVendorReport(
        fechaDesde: _startDate,
        fechaHasta: _endDate,
      );

      // Load egresos for each vendor
      final List<SalesVendorReport> reportsWithEgresos = [];
      for (final report in reports) {
        final totalEgresos = await SalesService.getTotalEgresosByVendor(
          fechaInicio: _startDate,
          fechaFin: _endDate,
          uuidUsuario: report.uuidUsuario,
        );

        final updatedReport = report.copyWith(totalEgresos: totalEgresos);
        reportsWithEgresos.add(updatedReport);
      }

      // Filtrar vendedores que tengan ventas reales (productos > 0 o dinero > 0)
      final filteredReports =
          reportsWithEgresos
              .where(
                (report) =>
                    report.totalProductosVendidos > 0 ||
                    report.totalDineroGeneral > 0,
              )
              .toList();

      setState(() {
        _vendorReports = filteredReports;
        _isLoadingVendors = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingVendors = false;
      });
      print('Error loading vendor reports: $e');
    }
  }

  void _loadProductAnalysis() async {
    setState(() {
      _isLoadingAnalysis = true;
    });

    try {
      final analysis = await SalesService.getProductAnalysis(
        fechaDesde: _startDate,
        fechaHasta: _endDate,
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
          (_isLoadingProducts || _isLoadingVendors || _isLoadingAnalysis)
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
          _buildRealTimeMetrics(_totalSales, _totalProductsSold),
          const SizedBox(height: 20),
          _buildProductSalesReport(),
        ],
      ),
    );
  }

  Widget _buildTPVsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ GESTIÓN DE TPVs
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  'Gestión de TPVs',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed:
                            () =>
                                Navigator.pushNamed(context, '/tpv-management'),
                        icon: Icon(Icons.devices),
                        label: Text('TPVs y Vendedores'),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed:
                            () => Navigator.pushNamed(context, '/tpv-prices'),
                        icon: Icon(Icons.attach_money),
                        label: Text('Precios TPV'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: 16),

          _buildPeriodSelector(),
          const SizedBox(height: 16),
          if (_isLoadingVendors)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (_vendorReports.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No hay datos de vendedores para el período seleccionado',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _vendorReports.length,
              itemBuilder:
                  (context, index) => _buildVendorCard(_vendorReports[index]),
            ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPeriodSelector(),
          const SizedBox(height: 16),
          _buildProductAnalysisTable(),
        ],
      ),
    );
  }

  String _formatDateRangeLabel() {
    final startFormatted =
        '${_startDate.day.toString().padLeft(2, '0')}/${_startDate.month.toString().padLeft(2, '0')}/${_startDate.year}';
    final endFormatted =
        '${_endDate.day.toString().padLeft(2, '0')}/${_endDate.month.toString().padLeft(2, '0')}/${_endDate.year}';

    if (_startDate.day == _endDate.day &&
        _startDate.month == _endDate.month &&
        _startDate.year == _endDate.year) {
      return startFormatted;
    } else {
      return '$startFormatted - $endFormatted';
    }
  }

  Widget _buildRealTimeMetrics(double totalSales, int totalProducts) {
    String periodLabel = _formatDateRangeLabel();
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
                  'Ventas',
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
                      '$totalProducts',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                Text(
                  'Productos',
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
                columnSpacing: 12,
                columns: const [
                  DataColumn(
                    label: Text(
                      'Producto',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Precio (u)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Cant Vendidos',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Total Venta',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Costo (u)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Total Costo',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Ganancias',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
                rows: [
                  // Product rows
                  ..._productSalesReports.map((report) {
                    // Calculate total cost CUP and profit
                    final totalCostoCup =
                        report.precioCostoCup * report.totalVendido;
                    final ganancias = report.ingresosTotales - totalCostoCup;

                    return DataRow(
                      cells: [
                        DataCell(
                          SizedBox(
                            width: 180,
                            child: Text(
                              report.nombreProducto,
                              overflow: TextOverflow.visible,
                              softWrap: true,
                              maxLines: 2,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            '\$${report.precioVentaCup.toStringAsFixed(0)}',
                            style: const TextStyle(color: AppColors.info),
                          ),
                        ),
                        DataCell(
                          Text(
                            '${report.totalVendido.toStringAsFixed(0)}',
                            style: const TextStyle(color: AppColors.primary),
                          ),
                        ),
                        DataCell(
                          Text(
                            '\$${report.ingresosTotales.toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: AppColors.success,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            '\$${report.precioCostoCup.toStringAsFixed(0)}',
                            style: const TextStyle(color: AppColors.warning),
                          ),
                        ),
                        DataCell(
                          Text(
                            '\$${totalCostoCup.toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: AppColors.warning,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            '\$${ganancias.toStringAsFixed(0)}',
                            style: TextStyle(
                              color:
                                  ganancias >= 0
                                      ? AppColors.success
                                      : AppColors.error,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                  // Totals row
                  if (_productSalesReports.isNotEmpty)
                    DataRow(
                      color: MaterialStateProperty.all(
                        AppColors.primary.withOpacity(0.1),
                      ),
                      cells: [
                        const DataCell(
                          Text(
                            'TOTALES',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        const DataCell(Text('-')), // No average price
                        DataCell(
                          Text(
                            '${_productSalesReports.fold(0.0, (sum, report) => sum + report.totalVendido).toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            '\$${_productSalesReports.fold(0.0, (sum, report) => sum + report.ingresosTotales).toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.success,
                            ),
                          ),
                        ),
                        const DataCell(Text('-')), // No average cost
                        DataCell(
                          Text(
                            '\$${_productSalesReports.fold(0.0, (sum, report) => sum + (report.precioCostoCup * report.totalVendido)).toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.warning,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            '\$${(_productSalesReports.fold(0.0, (sum, report) => sum + report.ingresosTotales) - _productSalesReports.fold(0.0, (sum, report) => sum + (report.precioCostoCup * report.totalVendido))).toStringAsFixed(0)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color:
                                  (_productSalesReports.fold(
                                                0.0,
                                                (sum, report) =>
                                                    sum +
                                                    report.ingresosTotales,
                                              ) -
                                              _productSalesReports.fold(
                                                0.0,
                                                (sum, report) =>
                                                    sum +
                                                    (report.precioCostoCup *
                                                        report.totalVendido),
                                              )) >=
                                          0
                                      ? AppColors.success
                                      : AppColors.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
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
                  DataColumn(
                    label: Text(
                      'Producto',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Precio Venta CUP',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Precio Venta USD',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Costo USD',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Valor USD',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Precio Costo CUP',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Ganancia',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      '% Ganancia',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
                rows:
                    _productAnalysis.map((analysis) {
                      return DataRow(
                        cells: [
                          DataCell(
                            SizedBox(
                              width: 200,
                              child: Text(
                                analysis.nombreProducto,
                                overflow: TextOverflow.visible,
                                softWrap: true,
                                maxLines: 2,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                ),
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
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              '\$${analysis.precioCostoCup.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              '\$${analysis.ganancia.toStringAsFixed(2)}',
                              style: TextStyle(
                                color:
                                    analysis.ganancia >= 0
                                        ? AppColors.success
                                        : AppColors.error,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              '${analysis.porcentajeGanancia.toStringAsFixed(1)}%',
                              style: TextStyle(
                                color:
                                    analysis.porcentajeGanancia >= 0
                                        ? AppColors.success
                                        : AppColors.error,
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

  Widget _buildVendorCard(SalesVendorReport vendor) {
    final statusColor = _getVendorStatusColor(vendor.status);
    final statusIcon = _getVendorStatusIcon(vendor.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withOpacity(0.1),
          child: Icon(Icons.person, color: statusColor),
        ),
        title: Text(
          vendor.nombreCompleto,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${vendor.totalVentas} ventas • \$${vendor.totalDineroGeneral.toStringAsFixed(2)}',
            ),
            Text(
              '${vendor.totalProductosVendidos.toStringAsFixed(0)} productos vendidos',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        trailing: Icon(statusIcon, color: statusColor),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildVendorDetailRow(
                  'Efectivo en Caja',
                  '\$${(vendor.totalDineroEfectivo - vendor.totalEgresos).toStringAsFixed(2)}',
                  AppColors.success,
                ),
                _buildVendorDetailRow(
                  'Transferencia',
                  '\$${vendor.totalDineroTransferencia.toStringAsFixed(2)}',
                  AppColors.info,
                ),
                _buildVendorDetailRow(
                  'Productos diferentes',
                  '${vendor.productosDiferentesVendidos}',
                  AppColors.primary,
                ),
                _buildVendorDetailRow(
                  'Primera venta',
                  _formatDateTime(vendor.primeraVenta),
                  AppColors.textSecondary,
                ),
                _buildVendorDetailRow(
                  'Última venta',
                  _formatDateTime(vendor.ultimaVenta),
                  AppColors.textSecondary,
                ),
                _buildVendorDetailRow(
                  'Total Egresos',
                  '\$${vendor.totalEgresos.toStringAsFixed(2)}',
                  AppColors.error,
                ),
                const SizedBox(height: 8),
                // Primera fila de botones
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _showVendorEgresosDetail(vendor),
                        icon: const Icon(Icons.receipt_long, size: 16),
                        label: const Text(
                          'Egresos',
                          style: TextStyle(fontSize: 12),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _showVendorOrdersDetail(vendor),
                        icon: const Icon(Icons.shopping_cart, size: 16),
                        label: const Text(
                          'Órdenes',
                          style: TextStyle(fontSize: 12),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.info,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Segunda fila - botones de transferencias y órdenes pendientes
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed:
                            () => _showVendorTransferenciasDetail(vendor),
                        icon: const Icon(Icons.account_balance, size: 16),
                        label: const Text(
                          'Transferencias',
                          style: TextStyle(fontSize: 12),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed:
                            () => _showVendorOrdenesPendientesDetail(vendor),
                        icon: const Icon(Icons.pending_actions, size: 16),
                        label: const Text(
                          'Órdenes Pendientes',
                          style: TextStyle(fontSize: 12),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.warning,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVendorDetailRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }

  Color _getVendorStatusColor(String status) {
    switch (status) {
      case 'activo':
        return AppColors.success;
      case 'reciente':
        return AppColors.warning;
      case 'inactivo':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  IconData _getVendorStatusIcon(String status) {
    switch (status) {
      case 'activo':
        return Icons.check_circle;
      case 'reciente':
        return Icons.schedule;
      case 'inactivo':
        return Icons.cancel;
      default:
        return Icons.help_outline;
    }
  }

  String _formatDateTime(DateTime dateTime) {
    // Convert to local timezone
    final localDateTime = dateTime.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateToCheck = DateTime(
      localDateTime.year,
      localDateTime.month,
      localDateTime.day,
    );

    if (dateToCheck == today) {
      return 'Hoy ${localDateTime.hour.toString().padLeft(2, '0')}:${localDateTime.minute.toString().padLeft(2, '0')}';
    } else if (dateToCheck == today.subtract(const Duration(days: 1))) {
      return 'Ayer ${localDateTime.hour.toString().padLeft(2, '0')}:${localDateTime.minute.toString().padLeft(2, '0')}';
    } else {
      return '${localDateTime.day.toString().padLeft(2, '0')}/${localDateTime.month.toString().padLeft(2, '0')}/${localDateTime.year} ${localDateTime.hour.toString().padLeft(2, '0')}:${localDateTime.minute.toString().padLeft(2, '0')}';
    }
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
          const Text('Fecha: ', style: TextStyle(fontWeight: FontWeight.w600)),
          Expanded(
            child: GestureDetector(
              onTap: _showDateRangePicker,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 12,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDateRangeLabel(),
                      style: const TextStyle(fontSize: 14),
                    ),
                    const Icon(Icons.arrow_drop_down, color: AppColors.primary),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDateRangePicker() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(primary: AppColors.primary),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        // Ensure start date is at 00:00:00
        _startDate = DateTime(
          picked.start.year,
          picked.start.month,
          picked.start.day,
          0,
          0,
          0,
        );
        // Ensure end date is at 23:59:59
        _endDate = DateTime(
          picked.end.year,
          picked.end.month,
          picked.end.day,
          23,
          59,
          59,
        );
      });

      // Reload data with new date range
      _loadProductSalesData();
      _loadVendorReports();
      _loadProductAnalysis();
    }
  }

  void _showVendorEgresosDetail(SalesVendorReport vendor) async {
    try {
      final deliveries = await SalesService.getCashDeliveries(
        fechaInicio: _startDate,
        fechaFin: _endDate,
        uuidUsuario: vendor.uuidUsuario,
      );

      if (!mounted) return;

      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Text(
                'Egresos de ${vendor.nombreCompleto}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child:
                    deliveries.isEmpty
                        ? const Center(
                          child: Text(
                            'No hay egresos registrados para este vendedor en el período seleccionado',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                        : ListView.builder(
                          itemCount: deliveries.length,
                          itemBuilder: (context, index) {
                            final delivery = deliveries[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppColors.error.withOpacity(
                                    0.1,
                                  ),
                                  child: const Icon(
                                    Icons.money_off,
                                    color: AppColors.error,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  '\$${delivery.montoEntrega.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.error,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      delivery.motivoEntrega,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      'Recibe: ${delivery.nombreRecibe}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    Text(
                                      'Autoriza: ${delivery.nombreAutoriza}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: Text(
                                  _formatDateTime(delivery.fechaEntrega),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cerrar'),
                ),
              ],
            ),
      );
    } catch (e) {
      print('Error loading vendor egresos detail: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al cargar los egresos del vendedor'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showVendorOrdersDetail(SalesVendorReport vendor) async {
    try {
      final dateRange = _getDateRange();
      final orders = await SalesService.getVendorOrders(
        fechaDesde: dateRange['start']!,
        fechaHasta: dateRange['end']!,
        uuidUsuario: vendor.uuidUsuario,
      );

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder:
            (context) => DraggableScrollableSheet(
              initialChildSize: 0.8,
              maxChildSize: 0.95,
              minChildSize: 0.5,
              builder:
                  (context, scrollController) => Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                    child: Column(
                      children: [
                        // Handle
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        // Header
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Órdenes de ${vendor.nombreCompleto}',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1F2937),
                                      ),
                                    ),
                                    Text(
                                      '${orders.length} órdenes encontradas',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        // Content
                        Expanded(
                          child:
                              orders.isEmpty
                                  ? const Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.shopping_cart_outlined,
                                          size: 64,
                                          color: Colors.grey,
                                        ),
                                        SizedBox(height: 16),
                                        Text(
                                          'No hay órdenes',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          'No se encontraron órdenes para este vendedor\nen el período seleccionado',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                  )
                                  : ListView.builder(
                                    controller: scrollController,
                                    padding: const EdgeInsets.all(16),
                                    itemCount: orders.length,
                                    itemBuilder: (context, index) {
                                      final order = orders[index];
                                      return Container(
                                        margin: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: Colors.grey[200]!,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(
                                                0.05,
                                              ),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: ExpansionTile(
                                          tilePadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 8,
                                              ),
                                          childrenPadding:
                                              const EdgeInsets.fromLTRB(
                                                16,
                                                0,
                                                16,
                                                16,
                                              ),
                                          title: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  'Orden #${order.idOperacion}',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                              ),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: _getStatusColor(
                                                    order.estadoNombre,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  order.estadoNombre,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          subtitle: Padding(
                                            padding: const EdgeInsets.only(
                                              top: 8,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Row(
                                                        children: [
                                                          Icon(
                                                            Icons.attach_money,
                                                            size: 16,
                                                            color:
                                                                AppColors
                                                                    .success,
                                                          ),
                                                          const SizedBox(
                                                            width: 4,
                                                          ),
                                                          Text(
                                                            '\$${order.totalOperacion.toStringAsFixed(2)}',
                                                            style:
                                                                const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  fontSize: 15,
                                                                ),
                                                          ),
                                                          const SizedBox(
                                                            width: 16,
                                                          ),
                                                          Icon(
                                                            Icons.shopping_bag,
                                                            size: 16,
                                                            color:
                                                                AppColors.info,
                                                          ),
                                                          const SizedBox(
                                                            width: 4,
                                                          ),
                                                          Text(
                                                            '${order.cantidadItems} prod.',
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 14,
                                                                ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    Text(
                                                      _formatOrderDate(
                                                        order.fechaOperacion,
                                                      ),
                                                      style: TextStyle(
                                                        color: Colors.grey[600],
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                // Medios de pago
                                                if (order.detalles['pagos'] !=
                                                        null &&
                                                    (order.detalles['pagos']
                                                            as List)
                                                        .isNotEmpty) ...[
                                                  const SizedBox(height: 8),
                                                  Wrap(
                                                    spacing: 6,
                                                    runSpacing: 4,
                                                    children:
                                                        _buildPaymentMethodChips(
                                                          order.detalles['pagos']
                                                              as List,
                                                        ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          children: [
                                            const Divider(),
                                            const SizedBox(height: 8),

                                            // Cliente
                                            if (order.detalles['cliente'] !=
                                                null) ...[
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Icon(
                                                    Icons.person,
                                                    size: 20,
                                                    color: AppColors.primary,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        const Text(
                                                          'Cliente:',
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            fontSize: 14,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 2,
                                                        ),
                                                        Text(
                                                          order.detalles['cliente']['nombre_completo'] ??
                                                              'N/A',
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 14,
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 16),
                                            ],

                                            // Productos
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Icon(
                                                  Icons.inventory_2,
                                                  size: 20,
                                                  color: AppColors.primary,
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      const Text(
                                                        'Productos:',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          fontSize: 14,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 8),
                                                      if (order
                                                              .detalles['items'] !=
                                                          null)
                                                        ...List.generate(
                                                              (order.detalles['items']
                                                                      as List)
                                                                  .length,
                                                              (itemIndex) {
                                                                final item =
                                                                    order
                                                                        .detalles['items'][itemIndex];
                                                                // Filtrar productos con precio_unitario = 0.0 o 0
                                                                final precioUnitario =
                                                                    (item['precio_unitario'] ??
                                                                            0.0)
                                                                        .toDouble();
                                                                if (precioUnitario ==
                                                                    0.0) {
                                                                  return const SizedBox.shrink(); // No mostrar el producto
                                                                }

                                                                return Container(
                                                                  margin:
                                                                      const EdgeInsets.only(
                                                                        bottom:
                                                                            6,
                                                                      ),
                                                                  padding:
                                                                      const EdgeInsets.all(
                                                                        12,
                                                                      ),
                                                                  decoration: BoxDecoration(
                                                                    color:
                                                                        Colors
                                                                            .grey[50],
                                                                    borderRadius:
                                                                        BorderRadius.circular(
                                                                          8,
                                                                        ),
                                                                    border: Border.all(
                                                                      color:
                                                                          Colors
                                                                              .grey[200]!,
                                                                    ),
                                                                  ),
                                                                  child: Row(
                                                                    children: [
                                                                      Expanded(
                                                                        flex: 3,
                                                                        child: Text(
                                                                          item['producto_nombre'] ??
                                                                              item['nombre'] ??
                                                                              'Producto',
                                                                          style: const TextStyle(
                                                                            fontSize:
                                                                                13,
                                                                            fontWeight:
                                                                                FontWeight.w500,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                      Expanded(
                                                                        flex: 1,
                                                                        child: Text(
                                                                          'x${item['cantidad']}',
                                                                          textAlign:
                                                                              TextAlign.center,
                                                                          style: TextStyle(
                                                                            fontSize:
                                                                                13,
                                                                            color:
                                                                                Colors.grey[600],
                                                                          ),
                                                                        ),
                                                                      ),
                                                                      Expanded(
                                                                        flex: 1,
                                                                        child: Text(
                                                                          '\$${(item['importe'] ?? 0.0).toStringAsFixed(2)}',
                                                                          textAlign:
                                                                              TextAlign.right,
                                                                          style: const TextStyle(
                                                                            fontWeight:
                                                                                FontWeight.w600,
                                                                            fontSize:
                                                                                13,
                                                                            color: Color(
                                                                              0xFF4A90E2,
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                );
                                                              },
                                                            )
                                                            .where(
                                                              (widget) =>
                                                                  widget
                                                                      is! SizedBox,
                                                            )
                                                            .toList(),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),

                                            // Desglose de Pagos
                                            if (order.detalles['pagos'] !=
                                                    null &&
                                                (order.detalles['pagos']
                                                        as List)
                                                    .isNotEmpty) ...[
                                              const SizedBox(height: 16),
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Icon(
                                                    Icons.payment,
                                                    size: 20,
                                                    color: AppColors.primary,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        const Text(
                                                          'Desglose de Pagos:',
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            fontSize: 14,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 8,
                                                        ),
                                                        ...List.generate(
                                                          (order.detalles['pagos']
                                                                  as List)
                                                              .length,
                                                          (paymentIndex) {
                                                            final payment =
                                                                order
                                                                    .detalles['pagos'][paymentIndex];
                                                            return Container(
                                                              margin:
                                                                  const EdgeInsets.only(
                                                                    bottom: 6,
                                                                  ),
                                                              padding:
                                                                  const EdgeInsets.all(
                                                                    12,
                                                                  ),
                                                              decoration: BoxDecoration(
                                                                color: _getPaymentColorByType(
                                                                  payment['es_efectivo'] ??
                                                                      false,
                                                                  payment['es_digital'] ??
                                                                      false,
                                                                ).withOpacity(
                                                                  0.1,
                                                                ),
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      8,
                                                                    ),
                                                                border: Border.all(
                                                                  color: _getPaymentColorByType(
                                                                    payment['es_efectivo'] ??
                                                                        false,
                                                                    payment['es_digital'] ??
                                                                        false,
                                                                  ).withOpacity(
                                                                    0.3,
                                                                  ),
                                                                ),
                                                              ),
                                                              child: Row(
                                                                children: [
                                                                  Icon(
                                                                    _getPaymentIconByType(
                                                                      payment['es_efectivo'] ??
                                                                          false,
                                                                      payment['es_digital'] ??
                                                                          false,
                                                                    ),
                                                                    size: 16,
                                                                    color: _getPaymentColorByType(
                                                                      payment['es_efectivo'] ??
                                                                          false,
                                                                      payment['es_digital'] ??
                                                                          false,
                                                                    ),
                                                                  ),
                                                                  const SizedBox(
                                                                    width: 8,
                                                                  ),
                                                                  Expanded(
                                                                    child: Text(
                                                                      payment['medio_pago'] ??
                                                                          'N/A',
                                                                      style: TextStyle(
                                                                        fontSize:
                                                                            13,
                                                                        fontWeight:
                                                                            FontWeight.w500,
                                                                        color: _getPaymentColorByType(
                                                                          payment['es_efectivo'] ??
                                                                              false,
                                                                          payment['es_digital'] ??
                                                                              false,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  Text(
                                                                    '\$${(payment['total'] ?? 0.0).toStringAsFixed(2)}',
                                                                    style: TextStyle(
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600,
                                                                      fontSize:
                                                                          13,
                                                                      color: _getPaymentColorByType(
                                                                        payment['es_efectivo'] ??
                                                                            false,
                                                                        payment['es_digital'] ??
                                                                            false,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            );
                                                          },
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],

                                            // Observaciones
                                            if (order.observaciones != null &&
                                                order
                                                    .observaciones!
                                                    .isNotEmpty) ...[
                                              const SizedBox(height: 16),
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Icon(
                                                    Icons.note,
                                                    size: 20,
                                                    color: AppColors.primary,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        const Text(
                                                          'Observaciones:',
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            fontSize: 14,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 4,
                                                        ),
                                                        Container(
                                                          width:
                                                              double.infinity,
                                                          padding:
                                                              const EdgeInsets.all(
                                                                12,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color:
                                                                Colors.blue[50],
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  8,
                                                                ),
                                                            border: Border.all(
                                                              color:
                                                                  Colors
                                                                      .blue[200]!,
                                                            ),
                                                          ),
                                                          child: Text(
                                                            order.observaciones ??
                                                                '',
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 13,
                                                                ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                        ),
                      ],
                    ),
                  ),
            ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar órdenes: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Color _getStatusColor(String estadoNombre) {
    switch (estadoNombre) {
      case 'Pendiente':
        return AppColors.warning;
      case 'Completado':
      case 'Completada':
        return AppColors.success;
      case 'Cancelado':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  String _formatOrderDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Map<String, DateTime> _getDateRange() {
    return {'start': _startDate, 'end': _endDate};
  }

  List<Widget> _buildPaymentMethodChips(List<dynamic> pagos) {
    // Agrupar pagos por método de pago y tipo
    Map<String, Map<String, dynamic>> paymentSummary = {};
    for (var pago in pagos) {
      String metodoPago = pago['medio_pago'] ?? 'N/A';
      double monto = (pago['total'] ?? 0.0).toDouble();
      bool esEfectivo = pago['es_efectivo'] ?? false;
      bool esDigital = pago['es_digital'] ?? false;

      String key = '$metodoPago-$esEfectivo-$esDigital';
      if (paymentSummary.containsKey(key)) {
        paymentSummary[key]!['total'] += monto;
      } else {
        paymentSummary[key] = {
          'medio_pago': metodoPago,
          'total': monto,
          'es_efectivo': esEfectivo,
          'es_digital': esDigital,
        };
      }
    }

    return paymentSummary.values.map((payment) {
      Color color = _getPaymentColorByType(
        payment['es_efectivo'],
        payment['es_digital'],
      );
      IconData icon = _getPaymentIconByType(
        payment['es_efectivo'],
        payment['es_digital'],
      );

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              payment['medio_pago'],
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  // Nuevos métodos basados en los campos es_efectivo y es_digital
  Color _getPaymentColorByType(bool esEfectivo, bool esDigital) {
    if (esEfectivo) {
      return AppColors.success; // Verde para efectivo
    } else if (esDigital) {
      return Colors.teal; // Verde azulado para pagos digitales
    } else {
      return AppColors.info; // Azul para transferencias/otros
    }
  }

  IconData _getPaymentIconByType(bool esEfectivo, bool esDigital) {
    if (esEfectivo) {
      return Icons.money; // Ícono de dinero en efectivo
    } else if (esDigital) {
      return Icons.smartphone; // Ícono de smartphone para pagos digitales
    } else {
      return Icons.account_balance; // Ícono de banco para transferencias
    }
  }

  // Métodos legacy mantenidos por compatibilidad
  Color _getPaymentMethodColor(String? metodoPago) {
    switch (metodoPago?.toLowerCase()) {
      case 'efectivo':
        return AppColors.success;
      case 'transferencia':
      case 'transferencia bancaria':
        return AppColors.info;
      case 'tarjeta de crédito':
      case 'tarjeta de credito':
      case 'tarjeta credito':
        return AppColors.warning;
      case 'tarjeta de débito':
      case 'tarjeta de debito':
      case 'tarjeta debito':
        return AppColors.primary;
      case 'cheque':
        return Colors.purple;
      case 'digital':
      case 'pago digital':
        return Colors.teal;
      default:
        return AppColors.textSecondary;
    }
  }

  IconData _getPaymentMethodIcon(String? metodoPago) {
    switch (metodoPago?.toLowerCase()) {
      case 'efectivo':
        return Icons.money;
      case 'transferencia':
      case 'transferencia bancaria':
        return Icons.account_balance;
      case 'tarjeta de crédito':
      case 'tarjeta de credito':
      case 'tarjeta credito':
        return Icons.credit_card;
      case 'tarjeta de débito':
      case 'tarjeta de debito':
      case 'tarjeta debito':
        return Icons.payment;
      case 'cheque':
        return Icons.receipt;
      case 'digital':
      case 'pago digital':
        return Icons.smartphone;
      default:
        return Icons.payment;
    }
  }

  void _showVendorOrdenesPendientesDetail(SalesVendorReport vendor) async {
    try {
      final dateRange = _getDateRange();
      
      // Llamar al método getVendorOrders con id_estado_param = 1 para órdenes pendientes
      final response = await Supabase.instance.client.rpc(
        'listar_ordenes',
        params: {
          'con_inventario_param': false,
          'fecha_desde_param': dateRange['start']!.toIso8601String().split('T')[0],
          'fecha_hasta_param': dateRange['end']!.toIso8601String().split('T')[0],
          'id_estado_param': 1, // Solo órdenes pendientes
          'id_tienda_param': await UserPreferencesService().getIdTienda(),
          'id_tipo_operacion_param': null,
          'id_tpv_param': null,
          'id_usuario_param': vendor.uuidUsuario,
          'limite_param': null,
          'pagina_param': null,
          'solo_pendientes_param': false,
        },
      );

      if (!mounted) return;

      final List<VendorOrder> pendingOrders = [];
      if (response != null) {
        for (final item in response) {
          try {
            final order = VendorOrder.fromJson(item);
            print(order.detalles);
            // Filtrar solo órdenes que contengan "Venta" en tipo_operacion
            final tipoOperacion = item['tipo_operacion']?.toString() ?? '';
            if (tipoOperacion.toLowerCase().contains('venta')) {
              pendingOrders.add(order);
            }
          } catch (e) {
            print('Error parsing pending order: $e');
          }
        }
      }

      // Calcular totales
      double totalEfectivo = 0.0;
      double totalTransferencias = 0.0;
      
      for (final order in pendingOrders) {
        if (order.detalles['pagos'] != null) {
          final pagos = order.detalles['pagos'] as List;
          for (final pago in pagos) {
            final metodoPago = pago['medio_pago']?.toString().toLowerCase() ?? '';
            final total = (pago['total'] ?? 0.0).toDouble();
            
            if (metodoPago.contains('efectivo')) {
              totalEfectivo += total;
            } else if (metodoPago.contains('transferencia')) {
              totalTransferencias += total;
            }
          }
        }
      }

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => DraggableScrollableSheet(
          initialChildSize: 0.8,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (context, scrollController) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                // Handle
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Órdenes Pendientes de ${vendor.nombreCompleto}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                            Text(
                              '${pendingOrders.length} órdenes pendientes',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Totales
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.success.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: AppColors.success.withOpacity(0.3),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.attach_money,
                                        size: 16,
                                        color: AppColors.success,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Efectivo: \$${totalEfectivo.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.success,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.info.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: AppColors.info.withOpacity(0.3),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.account_balance,
                                        size: 16,
                                        color: AppColors.info,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Transfer: \$${totalTransferencias.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.info,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Content
                Expanded(
                  child: pendingOrders.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.pending_actions_outlined,
                                size: 64,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'No hay órdenes pendientes',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'No se encontraron órdenes pendientes\npara este vendedor en el período seleccionado',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: pendingOrders.length,
                          itemBuilder: (context, index) {
                            final order = pendingOrders[index];

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.warning.withOpacity(0.3),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.grey.withOpacity(0.1),
                                    spreadRadius: 1,
                                    blurRadius: 3,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Orden #${order.idOperacion}',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF1F2937),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.warning
                                              .withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                            color: AppColors.warning
                                                .withOpacity(0.3),
                                          ),
                                        ),
                                        child: Text(
                                          order.estadoNombre,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: AppColors.warning,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.access_time,
                                        size: 16,
                                        color: Colors.grey[600],
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _formatDateTime(order.fechaOperacion),
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Icon(
                                        Icons.shopping_cart,
                                        size: 16,
                                        color: Colors.grey[600],
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${order.cantidadItems} items',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'TPV: ${order.tpvNombre}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                      Text(
                                        '\$${order.totalOperacion.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  // Fila con observaciones y botón de productos
                                  Row(
                                    children: [
                                      // Observaciones (si existen)
                                      if (order.observaciones != null &&
                                          order.observaciones!.isNotEmpty)
                                        Expanded(
                                          child: Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: Colors.grey[100],
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'Obs: ${order.observaciones}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[700],
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                          ),
                                        ),
                                      
                                      // Espaciado si hay observaciones
                                      if (order.observaciones != null &&
                                          order.observaciones!.isNotEmpty)
                                        const SizedBox(width: 8),
                                      
                                      // Botón de productos
                                      ElevatedButton.icon(
                                        onPressed: () => _showOrderProductsDetail(order),
                                        icon: const Icon(Icons.inventory_2, size: 16),
                                        label: const Text(
                                          'Productos',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.primary,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          minimumSize: Size.zero,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      print('Error loading pending orders: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar órdenes pendientes: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showOrderProductsDetail(VendorOrder order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Productos - Orden #${order.idOperacion}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                          Text(
                            'TPV: ${order.tpvNombre}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppColors.primary.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.attach_money,
                                  size: 16,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Total: \$${order.totalOperacion.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Content
              Expanded(
                child: _buildOrderProductsAccordion(order, scrollController),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrderProductsAccordion(VendorOrder order, ScrollController scrollController) {
    // Extraer productos de order.detalles
    final items = order.detalles['items'] as List<dynamic>? ?? [];
    final pagos = order.detalles['pagos'] as List<dynamic>? ?? [];
    final cliente = order.detalles['cliente'] as Map<String, dynamic>? ?? {};

    if (items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              'No hay productos',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'No se encontraron productos en esta orden',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Información del cliente
          if (cliente.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.info.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.info.withOpacity(0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.person,
                        size: 16,
                        color: AppColors.info,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Cliente',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.info,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    cliente['nombre_completo']?.toString() ?? 'Sin nombre',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (cliente['telefono'] != null && cliente['telefono'].toString().isNotEmpty)
                    Text(
                      'Tel: ${cliente['telefono']}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Productos
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: ExpansionTile(
              initiallyExpanded: true,
              leading: Icon(
                Icons.inventory_2,
                color: AppColors.primary,
              ),
              title: Text(
                'Productos (${items.length})',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              children: [
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = items[index] as Map<String, dynamic>;
                    final cantidad = (item['cantidad'] ?? 0).toDouble();
                    final precioUnitario = (item['precio_unitario'] ?? 0.0).toDouble();
                    final importe = (item['importe'] ?? 0.0).toDouble();
                    final productoNombre = item['producto_nombre']?.toString() ?? 'Producto sin nombre';
                    final variante = item['variante']?.toString();
                    final presentacion = item['presentacion']?.toString();

                    return Container(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Cantidad en círculo
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                cantidad.toInt().toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Información del producto
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  productoNombre,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1F2937),
                                  ),
                                ),
                                if (variante != null && variante.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Variante: $variante',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                                if (presentacion != null && presentacion.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Presentación: $presentacion',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Precio unitario: \$${precioUnitario.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                    Text(
                                      '\$${importe.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Métodos de pago
          if (pagos.isNotEmpty) ...[
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: ExpansionTile(
                leading: Icon(
                  Icons.payment,
                  color: AppColors.success,
                ),
                title: Text(
                  'Métodos de Pago (${pagos.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                children: [
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: pagos.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final pago = pagos[index] as Map<String, dynamic>;
                      final total = (pago['total'] ?? 0.0).toDouble();
                      final medioPago = pago['medio_pago']?.toString() ?? 'Sin especificar';
                      final esEfectivo = pago['es_efectivo'] == true;
                      final esDigital = pago['es_digital'] == true;
                      final referencia = pago['referencia_pago']?.toString();
                      final fechaPago = pago['fecha_pago']?.toString();

                      return Container(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            // Ícono del método de pago
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: esEfectivo 
                                  ? AppColors.success.withOpacity(0.1)
                                  : esDigital 
                                    ? AppColors.info.withOpacity(0.1)
                                    : AppColors.warning.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                esEfectivo 
                                  ? Icons.attach_money
                                  : esDigital 
                                    ? Icons.smartphone
                                    : Icons.account_balance,
                                color: esEfectivo 
                                  ? AppColors.success
                                  : esDigital 
                                    ? AppColors.info
                                    : AppColors.warning,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Información del pago
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    medioPago,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (referencia != null && referencia.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      'Ref: $referencia',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                  if (fechaPago != null && fechaPago.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      'Fecha: ${_formatDateTime(DateTime.parse(fechaPago))}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            // Total del pago
                            Text(
                              '\$${total.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showVendorTransferenciasDetail(SalesVendorReport vendor) async {
    try {
      final dateRange = _getDateRange();
      final orders = await SalesService.getVendorOrders(
        fechaDesde: dateRange['start']!,
        fechaHasta: dateRange['end']!,
        uuidUsuario: vendor.uuidUsuario,
      );

      if (!mounted) return;

      // Filtrar solo órdenes que tengan transferencias como método de pago
      final transferOrders =
          orders.where((order) {
            if (order.detalles['pagos'] == null) return false;
            final pagos = order.detalles['pagos'] as List;
            return pagos.any((pago) {
              final metodoPago =
                  pago['medio_pago']?.toString().toLowerCase() ?? '';
              return metodoPago.contains('transferencia');
            });
          }).toList();

      // Calcular total de transferencias
      double totalTransferencias = 0.0;
      for (final order in transferOrders) {
        if (order.detalles['pagos'] != null) {
          final pagos = order.detalles['pagos'] as List;
          for (final pago in pagos) {
            final metodoPago =
                pago['medio_pago']?.toString().toLowerCase() ?? '';
            if (metodoPago.contains('transferencia')) {
              totalTransferencias += (pago['total'] ?? 0.0).toDouble();
            }
          }
        }
      }

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder:
            (context) => DraggableScrollableSheet(
              initialChildSize: 0.8,
              maxChildSize: 0.95,
              minChildSize: 0.5,
              builder:
                  (context, scrollController) => Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                    child: Column(
                      children: [
                        // Handle
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        // Header
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Transferencias de ${vendor.nombreCompleto}',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1F2937),
                                      ),
                                    ),
                                    Text(
                                      '${transferOrders.length} órdenes con transferencias',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.success.withOpacity(
                                          0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: AppColors.success.withOpacity(
                                            0.3,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.account_balance,
                                            size: 16,
                                            color: AppColors.success,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Total: \$${totalTransferencias.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.success,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        // Content
                        Expanded(
                          child:
                              transferOrders.isEmpty
                                  ? const Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.account_balance_outlined,
                                          size: 64,
                                          color: Colors.grey,
                                        ),
                                        SizedBox(height: 16),
                                        Text(
                                          'No hay transferencias',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          'No se encontraron órdenes con transferencias\npara este vendedor en el período seleccionado',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                  )
                                  : ListView.builder(
                                    controller: scrollController,
                                    padding: const EdgeInsets.all(16),
                                    itemCount: transferOrders.length,
                                    itemBuilder: (context, index) {
                                      final order = transferOrders[index];

                                      // Calcular total de transferencias para esta orden
                                      double orderTransferTotal = 0.0;
                                      if (order.detalles['pagos'] != null) {
                                        final pagos =
                                            order.detalles['pagos'] as List;
                                        for (final pago in pagos) {
                                          final metodoPago =
                                              pago['medio_pago']
                                                  ?.toString()
                                                  .toLowerCase() ??
                                              '';
                                          if (metodoPago.contains(
                                            'transferencia',
                                          )) {
                                            orderTransferTotal +=
                                                (pago['total'] ?? 0.0)
                                                    .toDouble();
                                          }
                                        }
                                      }

                                      return Container(
                                        margin: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: Colors.grey[200]!,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(
                                                0.05,
                                              ),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: ExpansionTile(
                                          tilePadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 8,
                                              ),
                                          childrenPadding:
                                              const EdgeInsets.fromLTRB(
                                                16,
                                                0,
                                                16,
                                                16,
                                              ),
                                          title: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  'Orden #${order.idOperacion}',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                              ),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: AppColors.success,
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    const Icon(
                                                      Icons.account_balance,
                                                      size: 12,
                                                      color: Colors.white,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      '\$${orderTransferTotal.toStringAsFixed(2)}',
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          subtitle: Padding(
                                            padding: const EdgeInsets.only(
                                              top: 8,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                // Primera fila: Total y productos
                                                Row(
                                                  children: [
                                                    Icon(
                                                      Icons.attach_money,
                                                      size: 16,
                                                      color: AppColors.textSecondary,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      'Total: \$${order.totalOperacion.toStringAsFixed(2)}',
                                                      style: const TextStyle(
                                                        fontWeight: FontWeight.w600,
                                                        fontSize: 15,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 16),
                                                    Icon(
                                                      Icons.shopping_bag,
                                                      size: 16,
                                                      color: AppColors.info,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      '${order.cantidadItems} prod.',
                                                      style: const TextStyle(fontSize: 14),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 6),
                                                // Segunda fila: Fecha
                                                Row(
                                                  children: [
                                                    Icon(
                                                      Icons.access_time,
                                                      size: 14,
                                                      color: Colors.grey[600],
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      _formatOrderDate(order.fechaOperacion),
                                                      style: TextStyle(
                                                        color: Colors.grey[600],
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                // Solo mostrar chips de transferencias
                                                if (order.detalles['pagos'] !=
                                                    null) ...[
                                                  const SizedBox(height: 8),
                                                  Wrap(
                                                    spacing: 6,
                                                    runSpacing: 4,
                                                    children:
                                                        _buildTransferPaymentChips(
                                                          order.detalles['pagos']
                                                              as List,
                                                        ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          children: [
                                            // Aquí se puede agregar más detalle de la orden si es necesario
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: Colors.grey[50],
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Estado: ${order.estadoNombre}',
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'TPV: ${order.tpvNombre}',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      color: Colors.grey[600],
                                                    ),
                                                  ),
                                                  if (order.observaciones !=
                                                      null) ...[
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      'Observaciones: ${order.observaciones}',
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        color: Colors.grey[600],
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                        ),
                      ],
                    ),
                  ),
            ),
      );
    } catch (e) {
      print('Error loading vendor transferencias detail: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al cargar las transferencias del vendedor'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // Método para construir chips solo de transferencias
  List<Widget> _buildTransferPaymentChips(List pagos) {
    final transferPayments =
        pagos.where((pago) {
          final metodoPago = pago['medio_pago']?.toString().toLowerCase() ?? '';
          return metodoPago.contains('transferencia');
        }).toList();

    return transferPayments.map<Widget>((payment) {
      final metodoPago = payment['medio_pago'] ?? 'N/A';
      final total = (payment['total'] ?? 0.0).toDouble();

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.success.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.success.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_balance, size: 12, color: AppColors.success),
            const SizedBox(width: 4),
            Text(
              metodoPago,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.success,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '\$${total.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.success,
              ),
            ),
          ],
        ),
      );
    }).toList();
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
      case 1: // Ventas (current)
        break;
      case 2: // Productos
        Navigator.pushNamed(context, '/products-dashboard');
        break;
      case 3: // Inventario
        Navigator.pushNamed(context, '/inventory');
        break;
      case 4: // Configuración
        Navigator.pushNamed(context, '/settings');
        break;
    }
  }
}
