import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/carnaval_service.dart';

class CarnavalOrdersDashboardScreen extends StatefulWidget {
  const CarnavalOrdersDashboardScreen({Key? key}) : super(key: key);

  @override
  State<CarnavalOrdersDashboardScreen> createState() =>
      _CarnavalOrdersDashboardScreenState();
}

class _CarnavalOrdersDashboardScreenState
    extends State<CarnavalOrdersDashboardScreen> {
  bool _isLoading = true;
  late DateTime _fromDate;
  late DateTime _toDate;

  // Status counts
  Map<String, int> _statusCounts = {};

  // Completed orders data
  List<Map<String, dynamic>> _completedOrders = [];

  // Daily aggregated data for chart
  List<_DayData> _dailyData = [];

  // Totals
  double _totalEfectivo = 0;
  double _totalTransferencia = 0;

  // Provider breakdown
  List<_ProveedorData> _proveedorData = [];

  // Dynamic percentages
  double _pctEfectivo = 5.0;
  double _pctTransferencia = 15.0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fromDate = DateTime(now.year, now.month, 1);
    _toDate = now;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final pcts = await CarnavalService.getGlobalPercentages();
    _pctEfectivo = pcts['efectivo']!;
    _pctTransferencia = pcts['transferencia']!;

    final counts = await CarnavalService.getOrderStatusCounts();
    final completed = await CarnavalService.getCompletedOrdersForDashboard(
      from: _fromDate,
      to: _toDate,
    );

    // Aggregate by day
    final dayMap = <String, _DayData>{};
    double totalEfectivo = 0;
    double totalTransferencia = 0;

    // Provider aggregation
    final provMap = <String, _ProveedorData>{};

    for (final o in completed) {
      final date = o['created_at'] as String? ?? '';
      final total = (o['total'] as num?)?.toDouble() ?? 0;
      final metodo = o['metodo_pago'] as String? ?? '';
      final isEfectivo = metodo.toLowerCase().contains('efectivo');

      // Daily
      final day = dayMap.putIfAbsent(date, () => _DayData(date: date));
      if (isEfectivo) {
        day.efectivo += total;
        totalEfectivo += total;
      } else {
        day.transferencia += total;
        totalTransferencia += total;
      }

      // Provider — from proveedores array
      final proveedores = o['proveedores'] as List<dynamic>?;
      if (proveedores != null) {
        // Get unique provider IDs in this order
        final uniqueProvs = proveedores.toSet();
        for (final pId in uniqueProvs) {
          final key = pId.toString();
          final prov = provMap.putIfAbsent(
              key, () => _ProveedorData(id: key, name: 'Proveedor #$key'));
          if (isEfectivo) {
            prov.efectivo += total;
          } else {
            prov.transferencia += total;
          }
        }
      } else {
        // Use proveedor_id
        final pId = o['proveedor_id']?.toString() ?? '0';
        final prov = provMap.putIfAbsent(
            pId, () => _ProveedorData(id: pId, name: 'Proveedor #$pId'));
        if (isEfectivo) {
          prov.efectivo += total;
        } else {
          prov.transferencia += total;
        }
      }
    }

    // Fetch provider names
    final provIds = provMap.keys.map((k) => int.tryParse(k)).whereType<int>().toList();
    final names = await CarnavalService.getProveedoresNames(provIds);
    for (final entry in provMap.entries) {
      final id = int.tryParse(entry.key);
      if (id != null && names.containsKey(id)) {
        entry.value.name = names[id]!;
      }
    }

    final dailyList = dayMap.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final provList = provMap.values.toList()
      ..sort((a, b) => (b.efectivo + b.transferencia)
          .compareTo(a.efectivo + a.transferencia));

    setState(() {
      _statusCounts = counts;
      _completedOrders = completed;
      _dailyData = dailyList;
      _totalEfectivo = totalEfectivo;
      _totalTransferencia = totalTransferencia;
      _proveedorData = provList;
      _isLoading = false;
    });
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _fromDate, end: _toDate),
    );
    if (picked != null) {
      _fromDate = picked.start;
      _toDate = picked.end;
      _loadData();
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _fmtMoney(double v) => '\$${v.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard Órdenes')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Date filter
                  _buildDateFilter(),
                  const SizedBox(height: 16),
                  // Status summary
                  _buildStatusSummary(),
                  const SizedBox(height: 20),
                  // Money cards
                  _buildMoneyCards(),
                  const SizedBox(height: 20),
                  // Chart
                  const Text('Ingresos por día (Completadas)',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  _buildChart(),
                  const SizedBox(height: 24),
                  // Providers breakdown
                  const Text('Proveedores - Ingresos Completadas',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  _buildProveedoresList(),
                ],
              ),
            ),
    );
  }

  Widget _buildDateFilter() {
    return InkWell(
      onTap: _pickDateRange,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[400]!),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.date_range, size: 20),
            const SizedBox(width: 8),
            Text(
              '${_fmtDate(_fromDate)}  —  ${_fmtDate(_toDate)}',
              style: const TextStyle(fontSize: 14),
            ),
            const Spacer(),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusSummary() {
    final items = [
      _StatusItem('Completadas', _statusCounts['Completado'] ?? 0, Colors.teal),
      _StatusItem('Canceladas', _statusCounts['Cancelado'] ?? 0, Colors.red),
      _StatusItem('En Revisión', _statusCounts['En Revision'] ?? 0, Colors.blue),
      _StatusItem('Asignadas', _statusCounts['Asignado'] ?? 0, Colors.purple),
    ];

    return Row(
      children: items
          .map((item) => Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 8),
                    child: Column(
                      children: [
                        Text(
                          '${item.count}',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: item.color,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.label,
                          style:
                              const TextStyle(fontSize: 11, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ))
          .toList(),
    );
  }

  Widget _buildMoneyCards() {
    final gananciaEfectivo = _totalEfectivo * (_pctEfectivo / 100);
    final gananciaTransferencia = _totalTransferencia * (_pctTransferencia / 100);

    return Row(
      children: [
        Expanded(
          child: Card(
            color: Colors.green[50],
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.money, color: Colors.green[700], size: 20),
                      const SizedBox(width: 6),
                      Text('Efectivo',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.green[800])),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(_fmtMoney(_totalEfectivo),
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green[900])),
                  const SizedBox(height: 4),
                  Text('Ganancia (${_pctEfectivo.toStringAsFixed(0)}%): ${_fmtMoney(gananciaEfectivo)}',
                      style: TextStyle(
                          fontSize: 12, color: Colors.green[700])),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Card(
            color: Colors.blue[50],
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.account_balance, color: Colors.blue[700],
                          size: 20),
                      const SizedBox(width: 6),
                      Text('Transferencia',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.blue[800])),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(_fmtMoney(_totalTransferencia),
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[900])),
                  const SizedBox(height: 4),
                  Text('Ganancia (${_pctTransferencia.toStringAsFixed(0)}%): ${_fmtMoney(gananciaTransferencia)}',
                      style:
                          TextStyle(fontSize: 12, color: Colors.blue[700])),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChart() {
    if (_dailyData.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text('Sin datos en este rango')),
      );
    }

    final efectivoSpots = <FlSpot>[];
    final transferenciaSpots = <FlSpot>[];
    double maxY = 0;

    for (int i = 0; i < _dailyData.length; i++) {
      efectivoSpots.add(FlSpot(i.toDouble(), _dailyData[i].efectivo));
      transferenciaSpots
          .add(FlSpot(i.toDouble(), _dailyData[i].transferencia));
      final dayMax = _dailyData[i].efectivo > _dailyData[i].transferencia
          ? _dailyData[i].efectivo
          : _dailyData[i].transferencia;
      if (dayMax > maxY) maxY = dayMax;
    }

    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY > 0 ? maxY / 4 : 1,
          ),
          titlesData: FlTitlesData(
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 50,
                getTitlesWidget: (value, _) => Text(
                  _shortMoney(value),
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: _dailyData.length > 7
                    ? (_dailyData.length / 6).ceilToDouble()
                    : 1,
                getTitlesWidget: (value, _) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= _dailyData.length) {
                    return const SizedBox.shrink();
                  }
                  final d = _dailyData[idx].date;
                  final parts = d.split('-');
                  if (parts.length >= 3) {
                    return Text('${parts[2]}/${parts[1]}',
                        style: const TextStyle(fontSize: 10));
                  }
                  return Text(d, style: const TextStyle(fontSize: 10));
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          minY: 0,
          maxY: maxY * 1.1,
          lineBarsData: [
            LineChartBarData(
              spots: efectivoSpots,
              isCurved: true,
              color: Colors.green,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: Colors.green.withValues(alpha: 0.1),
              ),
            ),
            LineChartBarData(
              spots: transferenciaSpots,
              isCurved: true,
              color: Colors.blue,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: Colors.blue.withValues(alpha: 0.1),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots.map((s) {
                final color = s.barIndex == 0 ? Colors.green : Colors.blue;
                final label = s.barIndex == 0 ? 'Efectivo' : 'Transferencia';
                return LineTooltipItem(
                  '$label: ${_fmtMoney(s.y)}',
                  TextStyle(color: color, fontSize: 12),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  String _shortMoney(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  Widget _buildProveedoresList() {
    if (_proveedorData.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: Text('Sin datos de proveedores')),
      );
    }

    return Column(
      children: _proveedorData.map((p) {
        final total = p.efectivo + p.transferencia;
        final ganancia = p.efectivo * (_pctEfectivo / 100) + p.transferencia * (_pctTransferencia / 100);
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Total: ${_fmtMoney(total)}',
                              style: const TextStyle(fontSize: 13)),
                          const SizedBox(height: 2),
                          Text(
                              'Efectivo: ${_fmtMoney(p.efectivo)}  |  Transfer: ${_fmtMoney(p.transferencia)}',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[600])),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.teal.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          const Text('Ganancia',
                              style:
                                  TextStyle(fontSize: 10, color: Colors.teal)),
                          Text(_fmtMoney(ganancia),
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _DayData {
  final String date;
  double efectivo;
  double transferencia;

  _DayData({required this.date, this.efectivo = 0, this.transferencia = 0});
}

class _ProveedorData {
  final String id;
  String name;
  double efectivo;
  double transferencia;

  _ProveedorData({
    required this.id,
    required this.name,
    this.efectivo = 0,
    this.transferencia = 0,
  });
}

class _StatusItem {
  final String label;
  final int count;
  final Color color;

  _StatusItem(this.label, this.count, this.color);
}
