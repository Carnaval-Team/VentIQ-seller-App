import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../config/app_colors.dart';
import '../models/carnaval_provider_dashboard_data.dart';
import '../services/carnaval_service.dart';
import '../services/store_service.dart';

class CarnavalProviderDashboardScreen extends StatefulWidget {
  const CarnavalProviderDashboardScreen({super.key});

  @override
  State<CarnavalProviderDashboardScreen> createState() =>
      _CarnavalProviderDashboardScreenState();
}

class _CarnavalProviderDashboardScreenState
    extends State<CarnavalProviderDashboardScreen> {
  bool _isLoading = true;
  String? _error;
  CarnavalProviderDashboardData? _data;
  late DateTime _fromDate;
  late DateTime _toDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fromDate = DateTime(now.year, now.month, 1);
    _toDate = now;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final storeId = await StoreService.getCurrentStoreId();
      if (storeId == null) {
        throw Exception('No se pudo obtener el ID de la tienda');
      }
      final raw = await CarnavalService.getProviderDashboard(
        storeId: storeId,
        from: _fromDate,
        to: _toDate,
      );
      final parsed = CarnavalProviderDashboardData.fromJson(raw);
      if (parsed.hasError) {
        throw Exception(parsed.error ?? 'Error desconocido');
      }
      if (!mounted) return;
      setState(() {
        _data = parsed;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _fromDate, end: _toDate),
    );
    if (!mounted) return;
    if (picked != null) {
      setState(() {
        _fromDate = picked.start;
        _toDate = picked.end;
      });
      await _loadData();
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _fmtMoney(double v) => '\$${v.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Dashboard de Carnaval'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _data == null
                  ? const Center(child: Text('Sin datos'))
                  : RefreshIndicator(
                      onRefresh: _loadData,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _buildDateFilter(),
                          const SizedBox(height: 16),
                          _buildResumen(),
                          const SizedBox(height: 24),
                          _buildChart(),
                          const SizedBox(height: 24),
                          _buildPorEstado(),
                          const SizedBox(height: 24),
                          _buildPorMetodoPago(),
                          const SizedBox(height: 24),
                          _buildTopProductos(),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(
              'Error al cargar el dashboard',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.red[800],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.red[700]),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
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

  Widget _buildResumen() {
    final r = _data!.resumen;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Resumen',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildMetricCard('Órdenes', '${r.ordenesCount}', Colors.blue),
            _buildMetricCard(
                'Completadas', '${r.ordenesCompletadas}', Colors.green),
            _buildMetricCard('Productos vendidos',
                r.productosVendidos.toStringAsFixed(0), Colors.orange),
            _buildMetricCard(
                'Monto total', _fmtMoney(r.montoTotal), Colors.teal),
            _buildMetricCard(
                'Ticket promedio', _fmtMoney(r.ticketPromedio), Colors.purple),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricCard(String label, String value, Color color) {
    return SizedBox(
      width: (MediaQuery.of(context).size.width - 48) / 2,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                label,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChart() {
    final data = _data!.evolucionDiaria;
    if (data.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text('Sin datos en este rango')),
      );
    }

    final spots = <FlSpot>[];
    double maxY = 0;
    for (int i = 0; i < data.length; i++) {
      spots.add(FlSpot(i.toDouble(), data[i].monto));
      if (data[i].monto > maxY) maxY = data[i].monto;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Evolución diaria de ventas',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        SizedBox(
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
                    interval: data.length > 7
                        ? (data.length / 6).ceilToDouble()
                        : 1,
                    getTitlesWidget: (value, _) {
                      final idx = value.toInt();
                      if (idx < 0 || idx >= data.length) {
                        return const SizedBox.shrink();
                      }
                      final f = data[idx].fecha;
                      final parts = f.split('-');
                      if (parts.length >= 3) {
                        return Text('${parts[2]}/${parts[1]}',
                            style: const TextStyle(fontSize: 10));
                      }
                      return Text(f, style: const TextStyle(fontSize: 10));
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              minY: 0,
              maxY: maxY * 1.1,
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: AppColors.primary,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: AppColors.primary.withValues(alpha: 0.1),
                  ),
                ),
              ],
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (touched) => touched
                      .map((s) => LineTooltipItem(
                            _fmtMoney(s.y),
                            TextStyle(
                              color: AppColors.primary,
                              fontSize: 12,
                            ),
                          ))
                      .toList(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _shortMoney(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  Widget _buildPorEstado() {
    final estados = _data!.porEstado;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Órdenes por estado',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        if (estados.isEmpty)
          const Text('Sin datos')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: estados
                .map((e) => _buildTagCard(e.status, '${e.count}', _statusColor(e.status)))
                .toList(),
          ),
      ],
    );
  }

  Widget _buildPorMetodoPago() {
    final metodos = _data!.porMetodoPago;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Métodos de pago',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        if (metodos.isEmpty)
          const Text('Sin datos')
        else
          ...metodos.map((m) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.metodoPago,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            Text('${m.ordenesCount} órdenes',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                      Text(
                        _fmtMoney(m.monto),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              )),
      ],
    );
  }

  Widget _buildTopProductos() {
    final productos = _data!.topProductos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Top productos',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        if (productos.isEmpty)
          const Text('Sin datos')
        else
          ...productos.map((p) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.nombre,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            Text(
                                '${p.cantidad.toStringAsFixed(p.cantidad == p.cantidad.toInt() ? 0 : 2)} unidades',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                      Text(
                        _fmtMoney(p.monto),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              )),
      ],
    );
  }

  Widget _buildTagCard(String label, String value, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completado':
        return Colors.green;
      case 'cancelado':
        return Colors.red;
      case 'en revision':
      case 'en revisión':
        return Colors.blue;
      case 'asignado':
        return Colors.purple;
      case 'nuevo':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
}
