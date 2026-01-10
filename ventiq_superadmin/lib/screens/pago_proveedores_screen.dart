import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../config/app_colors.dart';
import '../models/supplier_payment_model.dart';
import '../services/supplier_payment_service.dart';
import '../utils/platform_utils.dart';
import '../utils/supplier_pdf_generator.dart';
import '../widgets/app_drawer.dart';

class PagoProveedoresScreen extends StatefulWidget {
  const PagoProveedoresScreen({super.key});

  @override
  State<PagoProveedoresScreen> createState() => _PagoProveedoresScreenState();
}

class _PagoProveedoresScreenState extends State<PagoProveedoresScreen> {
  DateTime _fechaInicio = DateTime.now().subtract(const Duration(days: 30));
  DateTime _fechaFin = DateTime.now();

  List<SupplierPaymentSummary> _suppliers = [];
  PaymentStats? _stats;
  bool _isLoading = false;
  String? _errorMessage;

  final Map<int, bool> _expandedSuppliers = {};
  final Map<int, List<OrderPaymentDetail>> _supplierOrders = {};
  final Map<int, bool> _loadingOrders = {};

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final suppliers = await SupplierPaymentService.getSupplierPayments(
        _fechaInicio,
        _fechaFin,
      );
      final stats = await SupplierPaymentService.getPaymentStats(
        _fechaInicio,
        _fechaFin,
      );

      if (mounted) {
        setState(() {
          _suppliers = suppliers;
          _stats = stats;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadOrderDetails(int supplierId) async {
    if (_supplierOrders.containsKey(supplierId)) {
      return; // Already loaded
    }

    setState(() {
      _loadingOrders[supplierId] = true;
    });

    try {
      final orders = await SupplierPaymentService.getSupplierOrders(
        supplierId,
        _fechaInicio,
        _fechaFin,
      );

      if (mounted) {
        setState(() {
          _supplierOrders[supplierId] = orders;
          _loadingOrders[supplierId] = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingOrders[supplierId] = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error cargando órdenes: $e')));
      }
    }
  }

  void _setDateRange(String range) {
    final now = DateTime.now();
    setState(() {
      switch (range) {
        case 'week':
          _fechaInicio = now.subtract(const Duration(days: 7));
          _fechaFin = now;
          break;
        case 'month':
          _fechaInicio = now.subtract(const Duration(days: 30));
          _fechaFin = now;
          break;
        case '3months':
          _fechaInicio = now.subtract(const Duration(days: 90));
          _fechaFin = now;
          break;
      }
    });
    _loadReport();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isDesktop = PlatformUtils.shouldUseDesktopLayout(screenSize.width);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isDesktop ? 'Reporte de Pago a Proveedores' : 'Pago a Proveedores',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadReport,
            tooltip: 'Actualizar',
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: const AppDrawer(),
      body: _buildBody(isDesktop),
    );
  }

  Widget _buildBody(bool isDesktop) {
    if (_isLoading && _suppliers.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Generando reporte...'),
          ],
        ),
      );
    }

    if (_errorMessage != null && _suppliers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              'Error al generar reporte',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(_errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadReport,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadReport,
      child: SingleChildScrollView(
        padding: EdgeInsets.all(PlatformUtils.getScreenPadding()),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDateFilters(),
            const SizedBox(height: 24),
            if (_stats != null) ...[
              _buildStatsSection(isDesktop),
              const SizedBox(height: 24),
              // _buildChartsSection(isDesktop),
              const SizedBox(height: 24),
            ],
            _buildSuppliersList(isDesktop),
          ],
        ),
      ),
    );
  }

  Widget _buildDateFilters() {
    final dateFormat = DateFormat('dd/MM/yyyy');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Filtros de Fecha',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: const Text('Última semana'),
                  selected: false,
                  onSelected: (_) => _setDateRange('week'),
                ),
                FilterChip(
                  label: const Text('Último mes'),
                  selected: false,
                  onSelected: (_) => _setDateRange('month'),
                ),
                FilterChip(
                  label: const Text('Últimos 3 meses'),
                  selected: false,
                  onSelected: (_) => _setDateRange('3months'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _fechaInicio,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        setState(() => _fechaInicio = date);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Fecha Inicio',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.calendar_today),
                      ),
                      child: Text(dateFormat.format(_fechaInicio)),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _fechaFin,
                        firstDate: _fechaInicio,
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        setState(() => _fechaFin = date);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Fecha Fin',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.calendar_today),
                      ),
                      child: Text(dateFormat.format(_fechaFin)),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _loadReport,
                  icon: const Icon(Icons.bar_chart),
                  label: const Text('Generar'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 20,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsSection(bool isDesktop) {
    final numberFormat = NumberFormat('#,##0.00', 'es');

    return isDesktop
        ? Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Total Ingresos (CUP)',
                '\$${numberFormat.format(_stats!.totalCup)}',
                Icons.attach_money,
                AppColors.primary,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildStatCard(
                'Total Proveedores',
                '${_stats!.totalSuppliers}',
                Icons.store,
                AppColors.success,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildStatCard(
                'Promedio por Proveedor',
                '\$${numberFormat.format(_stats!.averagePerSupplier)}',
                Icons.trending_up,
                AppColors.info,
              ),
            ),
          ],
        )
        : Column(
          children: [
            _buildStatCard(
              'Total Ingresos (CUP)',
              '\$${numberFormat.format(_stats!.totalCup)}',
              Icons.attach_money,
              AppColors.primary,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Total Proveedores',
                    '${_stats!.totalSuppliers}',
                    Icons.store,
                    AppColors.success,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatCard(
                    'Promedio',
                    '\$${numberFormat.format(_stats!.averagePerSupplier)}',
                    Icons.trending_up,
                    AppColors.info,
                  ),
                ),
              ],
            ),
          ],
        );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartsSection(bool isDesktop) {
    return isDesktop
        ? Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: _buildTopSuppliersChart()),
            const SizedBox(width: 16),
            Expanded(child: _buildCurrencyDistributionChart()),
          ],
        )
        : Column(
          children: [
            _buildTopSuppliersChart(),
            const SizedBox(height: 16),
            _buildCurrencyDistributionChart(),
          ],
        );
  }

  Widget _buildTopSuppliersChart() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bar_chart, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Top 10 Proveedores por Ingreso',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 300,
              child:
                  _stats!.topSuppliers.isEmpty
                      ? const Center(child: Text('Sin datos'))
                      : BarChart(
                        BarChartData(
                          alignment: BarChartAlignment.spaceAround,
                          maxY: _stats!.topSuppliers.first.totalCup * 1.2,
                          barTouchData: BarTouchData(
                            enabled: true,
                            touchTooltipData: BarTouchTooltipData(
                              getTooltipItem: (
                                group,
                                groupIndex,
                                rod,
                                rodIndex,
                              ) {
                                final supplier = _stats!.topSuppliers[group.x];
                                return BarTooltipItem(
                                  '${supplier.name}\n\$${NumberFormat('#,##0.00').format(rod.toY)}',
                                  const TextStyle(color: Colors.white),
                                );
                              },
                            ),
                          ),
                          titlesData: FlTitlesData(
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 60,
                                getTitlesWidget: (value, meta) {
                                  return Text(
                                    '\$${(value / 1000).toInt()}K',
                                    style: const TextStyle(fontSize: 10),
                                  );
                                },
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) {
                                  if (value.toInt() >=
                                      _stats!.topSuppliers.length) {
                                    return const Text('');
                                  }
                                  final name =
                                      _stats!.topSuppliers[value.toInt()].name;
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      name.length > 10
                                          ? '${name.substring(0, 10)}...'
                                          : name,
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  );
                                },
                              ),
                            ),
                            topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                          ),
                          borderData: FlBorderData(show: false),
                          barGroups:
                              _stats!.topSuppliers
                                  .asMap()
                                  .entries
                                  .map(
                                    (e) => BarChartGroupData(
                                      x: e.key,
                                      barRods: [
                                        BarChartRodData(
                                          toY: e.value.totalCup,
                                          color: AppColors.primary,
                                          width: 20,
                                          borderRadius: const BorderRadius.only(
                                            topLeft: Radius.circular(6),
                                            topRight: Radius.circular(6),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                  .toList(),
                        ),
                      ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrencyDistributionChart() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.pie_chart, color: AppColors.secondary),
                const SizedBox(width: 8),
                Text(
                  'Distribución por Moneda',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 300,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 60,
                  sections: [
                    PieChartSectionData(
                      value: _stats!.totalCup,
                      title: 'CUP',
                      color: AppColors.primary,
                      radius: 100,
                      titleStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    PieChartSectionData(
                      value: _stats!.totalUsd,
                      title: 'USD',
                      color: AppColors.success,
                      radius: 100,
                      titleStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    PieChartSectionData(
                      value: _stats!.totalEuro,
                      title: 'EUR',
                      color: AppColors.warning,
                      radius: 100,
                      titleStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuppliersList(bool isDesktop) {
    if (_suppliers.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.inbox_outlined, size: 64, color: AppColors.textHint),
                const SizedBox(height: 16),
                Text(
                  'No hay datos para el rango seleccionado',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.list, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Proveedores (${_suppliers.length})',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _suppliers.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final supplier = _suppliers[index];
              final isExpanded = _expandedSuppliers[supplier.id] ?? false;

              return _buildSupplierItem(supplier, isExpanded);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSupplierItem(SupplierPaymentSummary supplier, bool isExpanded) {
    final numberFormat = NumberFormat('#,##0.00', 'es');

    // Calculate discounts and net amounts
    final cashDiscount = supplier.totalCash * 0.05;
    final netCash = supplier.totalCash - cashDiscount;

    final transferDiscount = supplier.totalTransfer * 0.15;
    final netTransfer = supplier.totalTransfer - transferDiscount;

    final totalToPay = netCash + netTransfer;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        leading:
            supplier.logo != null
                ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    supplier.logo!,
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: 50,
                        height: 50,
                        color: AppColors.primary.withOpacity(0.1),
                        child: const Icon(
                          Icons.store,
                          color: AppColors.primary,
                        ),
                      );
                    },
                  ),
                )
                : Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.store, color: AppColors.primary),
                ),
        title: Text(
          supplier.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              supplier.categoria ?? 'Sin categoría',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            if (!isExpanded) ...[
              const SizedBox(height: 4),
              Text(
                'Total a pagar: \$${numberFormat.format(totalToPay)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.success,
                ),
              ),
            ],
          ],
        ),
        trailing:
            isExpanded
                ? null
                : _buildCurrencyChip(
                  'CUP',
                  supplier.totalCup,
                  AppColors.primary,
                ),
        onExpansionChanged: (expanded) {
          setState(() {
            _expandedSuppliers[supplier.id] = expanded;
          });
          if (expanded) {
            _loadOrderDetails(supplier.id);
          }
        },
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                children: [
                  _buildPaymentRow(
                    'Efectivo',
                    supplier.totalCash,
                    '5%',
                    cashDiscount,
                    netCash,
                  ),
                  const Divider(),
                  _buildPaymentRow(
                    'Transferencia',
                    supplier.totalTransfer,
                    '15%',
                    transferDiscount,
                    netTransfer,
                  ),
                  const Divider(thickness: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'TOTAL A PAGAR',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '\$${numberFormat.format(totalToPay)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _generatePdf(supplier),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Exportar Reporte PDF'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          _buildOrderDetails(supplier.id),
        ],
      ),
    );
  }

  Widget _buildCurrencyChip(String currency, double value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$currency: \$${NumberFormat('#,##0').format(value)}',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildOrderDetails(int supplierId) {
    final isLoading = _loadingOrders[supplierId] ?? false;
    final orders = _supplierOrders[supplierId];

    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (orders == null || orders.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No hay ventas en este período'),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final order = orders[index];
        return _buildOrderItem(order);
      },
    );
  }

  Widget _buildPaymentRow(
    String method,
    double total,
    String discountLabel,
    double discountAmount,
    double netTotal,
  ) {
    final numberFormat = NumberFormat('#,##0.00', 'es');
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(method, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                'Total: \$${numberFormat.format(total)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Desc. ($discountLabel)',
                style: TextStyle(color: AppColors.error, fontSize: 12),
              ),
              Text(
                '-\$${numberFormat.format(discountAmount)}',
                style: const TextStyle(color: AppColors.error),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'Neto',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
              Text(
                '\$${numberFormat.format(netTotal)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOrderItem(OrderPaymentDetail order) {
    final numberFormat = NumberFormat('#,##0.00', 'es');
    final dateFormat = DateFormat('dd/MM HH:mm');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ExpansionTile(
        title: Text('Orden #${order.orderId}'),
        subtitle: Row(
          children: [
            Text(
              dateFormat.format(order.createdAt),
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(width: 8),
            _buildPaymentMethodChip(order.isTransfer),
          ],
        ),
        trailing: Text(
          '\$${numberFormat.format(order.total)}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        children: [
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: order.products.length,
            itemBuilder: (context, index) {
              final product = order.products[index];
              return ListTile(
                leading:
                    product.productImage != null
                        ? ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.network(
                            product.productImage!,
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                          ),
                        )
                        : const Icon(Icons.image_not_supported),
                title: Text(
                  product.productName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(
                  '${product.quantity} x \$${numberFormat.format(product.price)} = \$${numberFormat.format(product.subtotal)}',
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodChip(bool isTransfer) {
    final color = isTransfer ? Colors.blue : Colors.green;
    final label = isTransfer ? 'Transferencia' : 'Efectivo';
    final icon = isTransfer ? Icons.credit_card : Icons.money;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _generatePdf(SupplierPaymentSummary supplier) async {
    try {
      // Ensure orders are loaded
      List<OrderPaymentDetail> orders = _supplierOrders[supplier.id] ?? [];

      if (orders.isEmpty) {
        // Show loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Obteniendo detalles para PDF...')),
        );

        orders = await SupplierPaymentService.getSupplierOrders(
          supplier.id,
          _fechaInicio,
          _fechaFin,
        );

        if (mounted) {
          setState(() {
            _supplierOrders[supplier.id] = orders;
          });
        }
      }

      if (orders.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No hay órdenes para generar reporte'),
            ),
          );
        }
        return;
      }

      await SupplierPdfGenerator.generateAndDownloadPdf(
        supplier: supplier,
        fechaInicio: _fechaInicio,
        fechaFin: _fechaFin,
        orders: orders,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error generando PDF: $e')));
      }
    }
  }
}
