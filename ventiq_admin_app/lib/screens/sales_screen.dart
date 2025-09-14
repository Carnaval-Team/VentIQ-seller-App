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
  List<SalesVendorReport> _vendorReports = [];
  List<ProductSalesReport> _productSalesReports = [];
  bool _isLoading = true;
  bool _isLoadingProducts = true;
  bool _isLoadingVendors = true;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
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
    _initializeDateRange();
    _loadSalesData();
    _loadProductAnalysis();
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

    Future.delayed(const Duration(milliseconds: 800), () {
      setState(() {
        _sales = MockSalesService.getMockSales();
        _isLoading = false;
      });
    });

    _loadProductSalesData();
    _loadVendorReports();
  }

  void _loadProductSalesData() async {
    setState(() {
      _isLoadingProducts = true;
      _isLoadingMetrics = true;
    });

    try {
      // Use the selected date range
      final dateRange = {'start': _startDate, 'end': _endDate};

      // Load both product sales data and metrics
      final productSales = await SalesService.getProductSalesReport(
        fechaDesde: dateRange['start'],
        fechaHasta: dateRange['end'],
      );
      final metrics = await SalesService.getSalesMetrics('custom');

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

      setState(() {
        _vendorReports = reportsWithEgresos;
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
        children: [_buildProductAnalysisTable()],
      ),
    );
  }

  String _formatDateRangeLabel() {
    final startFormatted = '${_startDate.day.toString().padLeft(2, '0')}/${_startDate.month.toString().padLeft(2, '0')}/${_startDate.year}';
    final endFormatted = '${_endDate.day.toString().padLeft(2, '0')}/${_endDate.month.toString().padLeft(2, '0')}/${_endDate.year}';
    
    if (_startDate.day == _endDate.day && _startDate.month == _endDate.month && _startDate.year == _endDate.year) {
      return startFormatted;
    } else {
      return '$startFormatted - $endFormatted';
    }
  }

  Widget _buildRealTimeMetrics(double totalSales, int salesCount) {
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
                      '$salesCount',
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
                            width: 100,
                            child: Text(
                              report.nombreProducto,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
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
                              width: 120,
                              child: Text(
                                analysis.nombreProducto,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
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
                  'Efectivo',
                  '\$${vendor.totalDineroEfectivo.toStringAsFixed(2)}',
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
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _showVendorEgresosDetail(vendor),
                    icon: const Icon(Icons.receipt_long, size: 18),
                    label: const Text('Ver Egresos Detallados'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
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
    final dateToCheck = DateTime(localDateTime.year, localDateTime.month, localDateTime.day);

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
          const Text(
            'Fecha: ',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          Expanded(
            child: GestureDetector(
              onTap: _showDateRangePicker,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
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
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: AppColors.primary,
            ),
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
        builder: (context) => AlertDialog(
          title: Text(
            'Egresos de ${vendor.nombreCompleto}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: deliveries.isEmpty
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
                            backgroundColor: AppColors.error.withOpacity(0.1),
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
