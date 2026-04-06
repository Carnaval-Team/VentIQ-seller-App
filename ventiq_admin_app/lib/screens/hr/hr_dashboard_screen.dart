import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
import '../../models/hr/hr_dashboard_data.dart';
import '../../services/hr/hr_dashboard_service.dart';
import '../../services/store_service.dart';
import '../../widgets/hr/hr_drawer.dart';
import '../../widgets/hr/hr_kpi_card.dart';

class HRDashboardScreen extends StatefulWidget {
  const HRDashboardScreen({super.key});

  @override
  State<HRDashboardScreen> createState() => _HRDashboardScreenState();
}

class _HRDashboardScreenState extends State<HRDashboardScreen> {
  bool _isLoading = true;
  int? _storeId;
  bool _fromGerente = false;

  HRDashboardSummary? _summary;
  List<HRTopWorker> _topWorkers = [];

  // Selector de mes
  late DateTime _selectedMonth;
  late DateTime _fechaDesde;
  late DateTime _fechaHasta;

  final _currencyFormat = NumberFormat('#,##0.00');

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month, 1);
    _updateDateRange();
    _initializeData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      _fromGerente = args['fromGerente'] as bool? ?? false;
    }
  }

  void _updateDateRange() {
    _fechaDesde = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    _fechaHasta = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
  }

  void _changeMonth(int delta) {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + delta,
        1,
      );
      _updateDateRange();
    });
    _loadData();
  }

  Future<void> _initializeData() async {
    try {
      final storeData = await StoreService.getWorkerRequiredData();
      if (storeData == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      setState(() {
        _storeId = storeData['storeId'] as int?;
      });
      await _loadData();
    } catch (e) {
      print('❌ Error inicializando datos HR: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadData() async {
    if (_storeId == null) return;
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        HRDashboardService.getDashboardSummary(
          storeId: _storeId!,
          fechaDesde: _fechaDesde,
          fechaHasta: _fechaHasta,
        ),
        HRDashboardService.getTopWorkersByPay(
          storeId: _storeId!,
          fechaDesde: _fechaDesde,
          fechaHasta: _fechaHasta,
        ),
      ]);

      if (mounted) {
        setState(() {
          _summary = results[0] as HRDashboardSummary;
          _topWorkers = results[1] as List<HRTopWorker>;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error cargando datos HR: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar datos: $e'),
            backgroundColor: AppColors.error,
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
          'Dashboard RR.HH.',
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
            onPressed: _loadData,
            tooltip: 'Actualizar',
          ),
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => Scaffold.of(context).openEndDrawer(),
              tooltip: 'Menu',
            ),
          ),
        ],
      ),
      endDrawer: HRDrawer(isFromGerente: _fromGerente),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildMonthSelector(),
                    const SizedBox(height: 16),
                    _buildKPICards(),
                    const SizedBox(height: 20),
                    _buildHoursChart(),
                    const SizedBox(height: 20),
                    _buildSalaryChart(),
                    const SizedBox(height: 20),
                    _buildTopWorkersSection(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildMonthSelector() {
    final monthName = DateFormat('MMMM yyyy').format(_selectedMonth);
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => _changeMonth(-1),
            ),
            Text(
              monthName.substring(0, 1).toUpperCase() + monthName.substring(1),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => _changeMonth(1),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKPICards() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.5,
      children: [
        HRKpiCard(
          title: 'Total Horas',
          value: '${_summary?.totalHoras.toStringAsFixed(1) ?? "0"}h',
          icon: Icons.access_time,
          color: AppColors.info,
          subtitle: '${_summary?.totalRegistros ?? 0} registros',
        ),
        HRKpiCard(
          title: 'Salario Base',
          value: '\$${_currencyFormat.format(_summary?.totalSalarioBase ?? 0)}',
          icon: Icons.attach_money,
          color: AppColors.primary,
        ),
        HRKpiCard(
          title: 'PPR Total',
          value: '\$${_currencyFormat.format(_summary?.totalPPR ?? 0)}',
          icon: Icons.emoji_events,
          color: AppColors.warning,
        ),
        HRKpiCard(
          title: 'Total General',
          value: '\$${_currencyFormat.format(_summary?.totalGeneral ?? 0)}',
          icon: Icons.account_balance_wallet,
          color: AppColors.success,
        ),
      ],
    );
  }

  Widget _buildHoursChart() {
    final dailyData = _summary?.dailyData ?? [];
    if (dailyData.isEmpty) {
      return _buildEmptyChartCard('Horas Trabajadas por Dia', 'Sin datos para este periodo');
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Horas Trabajadas por Dia',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: dailyData.map((d) => d.horas).fold(0.0, (a, b) => a > b ? a : b) * 1.2,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        return BarTooltipItem(
                          '${dailyData[groupIndex].horas.toStringAsFixed(1)}h',
                          const TextStyle(color: Colors.white, fontSize: 12),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx >= 0 && idx < dailyData.length) {
                            final day = dailyData[idx].fecha.split('-').last;
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(day, style: const TextStyle(fontSize: 9)),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                        reservedSize: 24,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '${value.toInt()}h',
                            style: const TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 2,
                  ),
                  barGroups: List.generate(dailyData.length, (index) {
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: dailyData[index].horas,
                          color: AppColors.info,
                          width: dailyData.length > 20 ? 6 : 12,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSalaryChart() {
    final dailyData = _summary?.dailyData ?? [];
    if (dailyData.isEmpty) {
      return _buildEmptyChartCard('Salario Acumulado', 'Sin datos para este periodo');
    }

    // Calcular acumulados
    double acumulado = 0;
    final acumulados = <double>[];
    for (final d in dailyData) {
      acumulado += d.total;
      acumulados.add(acumulado);
    }
    final maxY = acumulados.isEmpty ? 100.0 : acumulados.last * 1.1;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Salario Acumulado del Mes',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: maxY,
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) {
                        return spots.map((spot) {
                          return LineTooltipItem(
                            '\$${_currencyFormat.format(spot.y)}',
                            const TextStyle(color: Colors.white, fontSize: 12),
                          );
                        }).toList();
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx >= 0 && idx < dailyData.length) {
                            final day = dailyData[idx].fecha.split('-').last;
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(day, style: const TextStyle(fontSize: 9)),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                        reservedSize: 24,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 48,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '\$${_currencyFormat.format(value)}',
                            style: const TextStyle(fontSize: 9),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(show: true, drawVerticalLine: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: List.generate(acumulados.length, (i) {
                        return FlSpot(i.toDouble(), acumulados[i]);
                      }),
                      isCurved: true,
                      color: AppColors.success,
                      barWidth: 3,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppColors.success.withOpacity(0.1),
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

  Widget _buildEmptyChartCard(String title, String message) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            Icon(Icons.bar_chart, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 8),
            Text(message, style: TextStyle(color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }

  Widget _buildTopWorkersSection() {
    // Calcular promedios para datos de interes
    final totalWorkers = _topWorkers.length;
    double avgHorasPerWorker = 0;
    double avgSalarioPerHour = 0;
    if (totalWorkers > 0) {
      final sumHoras = _topWorkers.fold<double>(0, (a, w) => a + w.totalHoras);
      final sumBase = _topWorkers.fold<double>(0, (a, w) => a + w.totalSalarioBase);
      avgHorasPerWorker = sumHoras / totalWorkers;
      avgSalarioPerHour = sumHoras > 0 ? sumBase / sumHoras : 0;
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Trabajadores Destacados',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                if (totalWorkers > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.info.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$totalWorkers trabajadores',
                      style: const TextStyle(fontSize: 11, color: AppColors.info, fontWeight: FontWeight.w500),
                    ),
                  ),
              ],
            ),
            // Stats resumen
            if (totalWorkers > 0) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  _buildMiniStat('Prom. horas/persona', '${avgHorasPerWorker.toStringAsFixed(1)}h'),
                  const SizedBox(width: 16),
                  _buildMiniStat('Prom. \$/hora', '\$${_currencyFormat.format(avgSalarioPerHour)}'),
                  const SizedBox(width: 16),
                  _buildMiniStat('Costo total', '\$${_currencyFormat.format(_summary?.totalGeneral ?? 0)}'),
                ],
              ),
            ],
            const SizedBox(height: 12),
            if (_topWorkers.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(Icons.people_outline, size: 48, color: Colors.grey[300]),
                      const SizedBox(height: 8),
                      Text(
                        'Sin datos para este periodo',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: MediaQuery.of(context).size.width - 64,
                  ),
                  child: DataTable(
                    columnSpacing: 12,
                    headingTextStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                      color: AppColors.textPrimary,
                    ),
                    dataTextStyle: const TextStyle(fontSize: 11),
                    headingRowColor: WidgetStateProperty.all(
                      AppColors.primary.withOpacity(0.05),
                    ),
                    columns: const [
                      DataColumn(label: Text('#')),
                      DataColumn(label: Text('Nombre')),
                      DataColumn(label: Text('Rol')),
                      DataColumn(label: Text('Horas'), numeric: true),
                      DataColumn(label: Text('Base'), numeric: true),
                      DataColumn(label: Text('PPR'), numeric: true),
                      DataColumn(label: Text('Total'), numeric: true),
                      DataColumn(label: Text('\$/h Prom.'), numeric: true),
                      DataColumn(label: Text('')),
                    ],
                    rows: List.generate(_topWorkers.length, (i) {
                      final w = _topWorkers[i];
                      final avgPerHour = w.totalHoras > 0 ? w.totalGeneral / w.totalHoras : 0.0;
                      return DataRow(
                        color: i == 0
                            ? WidgetStateProperty.all(AppColors.success.withOpacity(0.05))
                            : null,
                        cells: [
                          DataCell(Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontWeight: i < 3 ? FontWeight.w700 : FontWeight.normal,
                              color: i == 0 ? AppColors.success : null,
                            ),
                          )),
                          DataCell(Text(
                            w.nombreCompleto,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          )),
                          DataCell(Text(
                            w.rolNombre ?? '-',
                            style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                          )),
                          DataCell(Text('${w.totalHoras.toStringAsFixed(1)}h')),
                          DataCell(Text('\$${_currencyFormat.format(w.totalSalarioBase)}')),
                          DataCell(Text(
                            '\$${_currencyFormat.format(w.totalPPR)}',
                            style: TextStyle(
                              color: w.totalPPR > 0 ? AppColors.success : null,
                            ),
                          )),
                          DataCell(Text(
                            '\$${_currencyFormat.format(w.totalGeneral)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          )),
                          DataCell(Text(
                            '\$${avgPerHour.toStringAsFixed(2)}',
                            style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                          )),
                          DataCell(
                            w.tienePPR
                                ? Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.success.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'PPR',
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: AppColors.success,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      );
                    }),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniStat(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 10, color: Colors.grey[500]),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
