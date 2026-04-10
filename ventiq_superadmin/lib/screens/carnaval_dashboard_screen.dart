import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import '../config/app_colors.dart';
import '../models/carnaval_dashboard_data.dart';
import '../services/carnaval_dashboard_service.dart';
import '../services/carnaval_ai_summary_service.dart';
import '../utils/platform_utils.dart';
import '../widgets/app_drawer.dart';
import '../widgets/chart_card.dart';

class CarnavalDashboardScreen extends StatefulWidget {
  const CarnavalDashboardScreen({super.key});

  @override
  State<CarnavalDashboardScreen> createState() =>
      _CarnavalDashboardScreenState();
}

class _CarnavalDashboardScreenState extends State<CarnavalDashboardScreen> {
  final CarnavalDashboardService _service = CarnavalDashboardService();
  final _currencyFmt = NumberFormat('#,##0.00');

  CarnavalDashboardData? _data;
  bool _isLoading = true;
  String? _errorMessage;

  String? _aiSummary;
  bool _aiLoading = false;

  late DateTime _fechaInicio;
  late DateTime _fechaFin;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fechaInicio = DateTime(now.year, now.month, 1);
    _fechaFin = now;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _aiSummary = null;
    });
    try {
      final data =
          await _service.loadDashboardData(_fechaInicio, _fechaFin);
      if (!mounted) return;
      setState(() {
        _data = data;
        _isLoading = false;
      });
      _loadAiSummary(data);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error al cargar datos: $e';
      });
    }
  }

  Future<void> _loadAiSummary(CarnavalDashboardData data) async {
    setState(() => _aiLoading = true);
    try {
      final summary = await CarnavalAiSummaryService.generateSummary(
        data,
        from: _fechaInicio,
        to: _fechaFin,
      );
      if (!mounted) return;
      setState(() {
        _aiSummary = summary;
        _aiLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aiSummary = 'No se pudo generar el resumen IA: $e';
        _aiLoading = false;
      });
    }
  }

  Future<void> _showDateFilterDialog() async {
    DateTime tempInicio = _fechaInicio;
    DateTime tempFin = _fechaFin;

    final result = await showDialog<DateTimeRange>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final fmt = DateFormat('dd MMM yyyy', 'es');

            Future<void> pickDate({required bool isStart}) async {
              final initial = isStart ? tempInicio : tempFin;
              final picked = await showDatePicker(
                context: ctx,
                initialDate: initial,
                firstDate: DateTime(2023),
                lastDate: DateTime.now(),
                locale: const Locale('es'),
                builder: (context, child) => Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: const ColorScheme.light(
                      primary: AppColors.primary,
                      onPrimary: Colors.white,
                      surface: Colors.white,
                    ),
                    datePickerTheme: DatePickerThemeData(
                      headerBackgroundColor: AppColors.primary,
                      headerForegroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  child: child!,
                ),
              );
              if (picked != null) {
                setDialogState(() {
                  if (isStart) {
                    tempInicio = picked;
                    if (tempInicio.isAfter(tempFin)) tempFin = tempInicio;
                  } else {
                    tempFin = picked;
                    if (tempFin.isBefore(tempInicio)) tempInicio = tempFin;
                  }
                });
              }
            }

            void applyPreset(DateTime start, DateTime end) {
              setDialogState(() {
                tempInicio = start;
                tempFin = end;
              });
            }

            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);

            return Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.date_range,
                                color: AppColors.primary, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Filtrar por Fecha',
                            style: Theme.of(ctx)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Quick presets
                      Text('Acceso rápido',
                          style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _presetChip('Hoy', () {
                            applyPreset(today, today);
                          }),
                          _presetChip('Últimos 7 días', () {
                            applyPreset(
                                today.subtract(const Duration(days: 6)),
                                today);
                          }),
                          _presetChip('Últimos 30 días', () {
                            applyPreset(
                                today.subtract(const Duration(days: 29)),
                                today);
                          }),
                          _presetChip('Este mes', () {
                            applyPreset(
                                DateTime(now.year, now.month, 1), today);
                          }),
                          _presetChip('Mes anterior', () {
                            final firstPrev =
                                DateTime(now.year, now.month - 1, 1);
                            final lastPrev =
                                DateTime(now.year, now.month, 0);
                            applyPreset(firstPrev, lastPrev);
                          }),
                          _presetChip('Este año', () {
                            applyPreset(DateTime(now.year, 1, 1), today);
                          }),
                          _presetChip('Todo', () {
                            applyPreset(DateTime(2023, 1, 1), today);
                          }),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Divider(height: 1),
                      const SizedBox(height: 20),

                      // Date selectors
                      Text('Rango personalizado',
                          style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _datePickerButton(
                              label: 'Desde',
                              date: fmt.format(tempInicio),
                              onTap: () => pickDate(isStart: true),
                            ),
                          ),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12),
                            child: Icon(Icons.arrow_forward,
                                color: AppColors.textSecondary, size: 20),
                          ),
                          Expanded(
                            child: _datePickerButton(
                              label: 'Hasta',
                              date: fmt.format(tempFin),
                              onTap: () => pickDate(isStart: false),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Days count
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.info.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${tempFin.difference(tempInicio).inDays + 1} días seleccionados',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.info,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Actions
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(ctx),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                side: BorderSide(color: AppColors.divider),
                              ),
                              child: const Text('Cancelar'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton.icon(
                              onPressed: () => Navigator.pop(
                                ctx,
                                DateTimeRange(
                                    start: tempInicio, end: tempFin),
                              ),
                              icon: const Icon(Icons.check, size: 18),
                              label: const Text('Aplicar filtro'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (result != null) {
      setState(() {
        _fechaInicio = result.start;
        _fechaFin = result.end;
      });
      _loadData();
    }
  }

  Widget _presetChip(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.divider),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      ),
    );
  }

  Widget _datePickerButton({
    required String label,
    required String date,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.divider),
          borderRadius: BorderRadius.circular(12),
          color: AppColors.surfaceVariant,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.calendar_today,
                    size: 15, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(date,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = PlatformUtils.shouldUseDesktopLayout(width);
    final pad = PlatformUtils.getScreenPadding();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Info de Carnaval'),
        actions: [
          _buildDateFilterChip(),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recargar',
            onPressed: _loadData,
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: isDesktop ? null : const AppDrawer(),
      body: Row(
        children: [
          if (isDesktop) const AppDrawer(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline,
                                size: 48, color: AppColors.error),
                            const SizedBox(height: 16),
                            Text(_errorMessage!,
                                textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _loadData,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Reintentar'),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.all(pad),
                          child: isDesktop
                              ? _buildDesktopLayout()
                              : _buildMobileLayout(),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateFilterChip() {
    final fmt = DateFormat('dd/MM/yyyy');
    return InkWell(
      onTap: _showDateFilterDialog,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.primary.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.date_range,
                size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              '${fmt.format(_fechaInicio)}  -  ${fmt.format(_fechaFin)}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.expand_more,
                size: 18, color: AppColors.primary),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // DESKTOP LAYOUT
  // ============================================================
  Widget _buildDesktopLayout() {
    final d = _data!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // KPI Row 1 - Main metrics
        _sectionTitle('Resumen General'),
        const SizedBox(height: 12),
        Row(
          children: [
            _kpi(Icons.people, 'Usuarios Registrados',
                d.totalUsuarios.toString(), AppColors.secondary),
            const SizedBox(width: 16),
            _kpi(Icons.shopping_cart, 'Total Ordenes',
                d.totalOrdenes.toString(), AppColors.primary),
            const SizedBox(width: 16),
            _kpi(Icons.attach_money, 'Dinero Recaudado',
                _currencyFmt.format(d.dineroRecaudado), AppColors.success),
            const SizedBox(width: 16),
            _kpi(Icons.check_circle, 'Completadas',
                d.ordenesCompletadas.toString(), const Color(0xFF00897B)),
          ],
        ),
        const SizedBox(height: 16),
        // KPI Row 2
        Row(
          children: [
            _kpi(Icons.cancel, 'Canceladas',
                d.ordenesCanceladas.toString(), AppColors.error),
            const SizedBox(width: 16),
            _kpi(Icons.store, 'Proveedores',
                d.totalProveedores.toString(), AppColors.warning),
            const SizedBox(width: 16),
            _kpi(
                Icons.percent,
                'Tasa Completación',
                d.totalOrdenes > 0
                    ? '${(d.ordenesCompletadas / d.totalOrdenes * 100).toStringAsFixed(1)}%'
                    : '0%',
                AppColors.info),
            const SizedBox(width: 16),
            _kpi(
                Icons.monetization_on,
                'Ticket Promedio',
                d.ordenesCompletadas > 0
                    ? _currencyFmt
                        .format(d.dineroRecaudado / d.ordenesCompletadas)
                    : '0',
                const Color(0xFF6A1B9A)),
          ],
        ),
        const SizedBox(height: 32),

        // Charts Row 1: Usuarios + Ordenes por método pago
        _sectionTitle('Tendencias'),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildUsuariosPorDiaChart(d)),
            const SizedBox(width: 16),
            Expanded(child: _buildOrdenesPorMetodoPagoChart(d)),
          ],
        ),
        const SizedBox(height: 16),

        // Charts Row 2: Dinero por método pago + Dinero por moneda
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildDineroPorMetodoPagoChart(d)),
            const SizedBox(width: 16),
            Expanded(child: _buildDineroPorMonedaChart(d)),
          ],
        ),
        const SizedBox(height: 32),

        // Charts Row 3: Productos por proveedor + Vendidos por proveedor
        _sectionTitle('Proveedores'),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildProductosPorProveedorChart(d)),
            const SizedBox(width: 16),
            Expanded(child: _buildVendidosPorProveedorChart(d)),
          ],
        ),
        const SizedBox(height: 32),

        // Top 5 Tables
        _sectionTitle('Rankings'),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildTop5ProductosTable(d)),
            const SizedBox(width: 16),
            Expanded(child: _buildTop5CompradoresTable(d)),
            const SizedBox(width: 16),
            Expanded(child: _buildTop5ProveedoresTable(d)),
          ],
        ),
        const SizedBox(height: 32),

        // AI Summary
        _buildAiSummaryCard(),
        const SizedBox(height: 32),
      ],
    );
  }

  // ============================================================
  // MOBILE LAYOUT
  // ============================================================
  Widget _buildMobileLayout() {
    final d = _data!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Resumen General'),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: [
            _kpiCompact(Icons.people, 'Usuarios',
                d.totalUsuarios.toString(), AppColors.secondary),
            _kpiCompact(Icons.shopping_cart, 'Ordenes',
                d.totalOrdenes.toString(), AppColors.primary),
            _kpiCompact(Icons.attach_money, 'Recaudado',
                _currencyFmt.format(d.dineroRecaudado), AppColors.success),
            _kpiCompact(Icons.check_circle, 'Completadas',
                d.ordenesCompletadas.toString(), const Color(0xFF00897B)),
            _kpiCompact(Icons.cancel, 'Canceladas',
                d.ordenesCanceladas.toString(), AppColors.error),
            _kpiCompact(Icons.store, 'Proveedores',
                d.totalProveedores.toString(), AppColors.warning),
          ],
        ),
        const SizedBox(height: 24),
        _sectionTitle('Tendencias'),
        const SizedBox(height: 12),
        _buildUsuariosPorDiaChart(d),
        const SizedBox(height: 16),
        _buildOrdenesPorMetodoPagoChart(d),
        const SizedBox(height: 16),
        _buildDineroPorMetodoPagoChart(d),
        const SizedBox(height: 16),
        _buildDineroPorMonedaChart(d),
        const SizedBox(height: 24),
        _sectionTitle('Proveedores'),
        const SizedBox(height: 12),
        _buildProductosPorProveedorChart(d),
        const SizedBox(height: 16),
        _buildVendidosPorProveedorChart(d),
        const SizedBox(height: 24),
        _sectionTitle('Rankings'),
        const SizedBox(height: 12),
        _buildTop5ProductosTable(d),
        const SizedBox(height: 16),
        _buildTop5CompradoresTable(d),
        const SizedBox(height: 16),
        _buildTop5ProveedoresTable(d),
        const SizedBox(height: 24),
        _buildAiSummaryCard(),
        const SizedBox(height: 24),
      ],
    );
  }

  // ============================================================
  // COMMON WIDGETS
  // ============================================================

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
    );
  }

  // Desktop KPI card - expanded in Row
  Widget _kpi(IconData icon, String title, String value, Color color) {
    return Expanded(
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: [Colors.white, color.withOpacity(0.04)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 16),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Mobile compact KPI
  Widget _kpiCompact(
      IconData icon, String title, String value, Color color) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Text(title,
                style: TextStyle(
                    fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // CHARTS
  // ============================================================

  // 2: Usuarios registrados por día (LineChart)
  Widget _buildUsuariosPorDiaChart(CarnavalDashboardData d) {
    final spots = d.usuariosPorDia.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.count.toDouble()))
        .toList();
    final labels = d.usuariosPorDia
        .map((e) => DateFormat('dd/MM').format(e.date))
        .toList();

    return ChartCard(
      title: 'Usuarios Registrados por Día',
      subtitle: '${d.totalUsuarios} usuarios en el período',
      chart: SizedBox(
        height: 280,
        child: spots.isEmpty
            ? _emptyChart()
            : LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: _calcInterval(
                        spots.map((s) => s.y).reduce((a, b) => a > b ? a : b)),
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: AppColors.divider,
                      strokeWidth: 0.8,
                    ),
                  ),
                  titlesData: _buildTitles(labels, spots),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: AppColors.secondary,
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                          show: spots.length <= 15),
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppColors.secondary.withOpacity(0.1),
                      ),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => spots
                          .map((s) => LineTooltipItem(
                                '${labels[s.x.toInt()]}\n${s.y.toInt()} usuarios',
                                const TextStyle(
                                    color: Colors.white, fontSize: 12),
                              ))
                          .toList(),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  // 7: Ordenes por método de pago (multi-line)
  Widget _buildOrdenesPorMetodoPagoChart(CarnavalDashboardData d) {
    return _buildMultiLineChart(
      title: 'Ordenes por Método de Pago',
      subtitle: 'Distribución diaria',
      dataMap: d.ordenesPorMetodoPago,
      valueExtractor: (dates) =>
          dates.map((dc) => FlSpot(0, dc.count.toDouble())).toList(),
      isCount: true,
    );
  }

  // 8: Dinero por método de pago (multi-line)
  Widget _buildDineroPorMetodoPagoChart(CarnavalDashboardData d) {
    return _buildMultiLineChartValue(
      title: 'Ingresos por Método de Pago',
      subtitle: 'Dinero recaudado por día',
      dataMap: d.dineroPorMetodoPago,
    );
  }

  // 9: Dinero por moneda (PieChart)
  Widget _buildDineroPorMonedaChart(CarnavalDashboardData d) {
    final entries = d.dineroPorMoneda.entries.toList();
    if (entries.isEmpty) {
      return ChartCard(
        title: 'Recaudación por Moneda',
        chart: SizedBox(height: 280, child: _emptyChart()),
      );
    }
    final total = entries.fold(0.0, (sum, e) => sum + e.value);

    return ChartCard(
      title: 'Recaudación por Moneda',
      subtitle: 'Distribución de ingresos',
      chart: SizedBox(
        height: 280,
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: PieChart(
                PieChartData(
                  sections: entries.asMap().entries.map((e) {
                    final color =
                        AppColors.chartColors[e.key % AppColors.chartColors.length];
                    final pct = total > 0 ? (e.value.value / total * 100) : 0;
                    return PieChartSectionData(
                      color: color,
                      value: e.value.value,
                      title: '${pct.toStringAsFixed(1)}%',
                      radius: 80,
                      titleStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    );
                  }).toList(),
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: entries.asMap().entries.map((e) {
                  final color =
                      AppColors.chartColors[e.key % AppColors.chartColors.length];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${e.value.key}: ${_currencyFmt.format(e.value.value)}',
                            style: const TextStyle(fontSize: 13),
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
    );
  }

  // 11: Productos por proveedor (BarChart horizontal)
  Widget _buildProductosPorProveedorChart(CarnavalDashboardData d) {
    return _buildHorizontalBarChart(
      title: 'Productos por Proveedor',
      subtitle: 'Catálogo actual',
      items: d.productosPorProveedor.take(10).toList(),
      color: AppColors.secondary,
    );
  }

  // 12: Productos vendidos por proveedor
  Widget _buildVendidosPorProveedorChart(CarnavalDashboardData d) {
    return _buildHorizontalBarChart(
      title: 'Productos Vendidos por Proveedor',
      subtitle: 'Unidades vendidas en el período',
      items: d.productosVendidosPorProveedor.take(10).toList(),
      color: AppColors.primary,
    );
  }

  // ============================================================
  // TOP 5 TABLES
  // ============================================================

  Widget _buildTop5ProductosTable(CarnavalDashboardData d) {
    return _buildRankingCard(
      title: 'Top 5 Productos',
      icon: Icons.star,
      color: AppColors.warning,
      items: d.top5Productos
          .map((e) => _RankItem(e.name, '${e.count} uds'))
          .toList(),
    );
  }

  Widget _buildTop5CompradoresTable(CarnavalDashboardData d) {
    return _buildRankingCard(
      title: 'Top 5 Compradores',
      icon: Icons.person,
      color: AppColors.secondary,
      items: d.top5Compradores
          .map((e) => _RankItem(e.name, _currencyFmt.format(e.value)))
          .toList(),
    );
  }

  Widget _buildTop5ProveedoresTable(CarnavalDashboardData d) {
    return _buildRankingCard(
      title: 'Top 5 Proveedores',
      icon: Icons.local_shipping,
      color: AppColors.primary,
      items: d.top5Proveedores
          .map((e) => _RankItem(e.name, '${e.count} uds'))
          .toList(),
    );
  }

  Widget _buildRankingCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<_RankItem> items,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 8),
                Text(title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const Divider(height: 24),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Sin datos',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            ...items.asMap().entries.map((e) {
              final rank = e.key + 1;
              final item = e.value;
              final medalColor = rank == 1
                  ? const Color(0xFFFFD700)
                  : rank == 2
                      ? const Color(0xFFC0C0C0)
                      : rank == 3
                          ? const Color(0xFFCD7F32)
                          : AppColors.textSecondary;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: medalColor.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '$rank',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: medalColor,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(item.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14)),
                    ),
                    Text(item.value,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: color,
                          fontSize: 14,
                        )),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // AI SUMMARY
  // ============================================================

  Widget _buildAiSummaryCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [
              const Color(0xFF6A1B9A).withOpacity(0.03),
              const Color(0xFF1976D2).withOpacity(0.03),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6A1B9A), Color(0xFF1976D2)],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.auto_awesome,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Text(
                  'Análisis IA del Negocio',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                if (!_aiLoading && _data != null)
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    tooltip: 'Regenerar análisis',
                    onPressed: () => _loadAiSummary(_data!),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_aiLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Analizando datos...',
                          style: TextStyle(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              )
            else if (_aiSummary != null)
              MarkdownBody(
                data: _aiSummary!,
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  p: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        height: 1.6,
                        color: AppColors.textPrimary,
                      ),
                  h1: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                  h2: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                  h3: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                  strong: const TextStyle(fontWeight: FontWeight.bold),
                  listBullet: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.textPrimary,
                      ),
                  blockSpacing: 12,
                ),
              )
            else
              const Text('El análisis se generará cuando los datos estén listos.',
                  style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // CHART HELPERS
  // ============================================================

  Widget _emptyChart() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bar_chart, size: 48, color: AppColors.textHint),
          const SizedBox(height: 8),
          Text('Sin datos en este período',
              style: TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildMultiLineChart({
    required String title,
    required String subtitle,
    required Map<String, List<DateCount>> dataMap,
    required List<FlSpot> Function(List<DateCount>) valueExtractor,
    required bool isCount,
  }) {
    if (dataMap.isEmpty) {
      return ChartCard(
        title: title,
        subtitle: subtitle,
        chart: SizedBox(height: 280, child: _emptyChart()),
      );
    }

    // Collect all unique dates sorted
    final allDates = <DateTime>{};
    for (final entry in dataMap.values) {
      for (final dc in entry) {
        allDates.add(dc.date);
      }
    }
    final sortedDates = allDates.toList()..sort();
    final dateIndex = {
      for (var i = 0; i < sortedDates.length; i++) sortedDates[i]: i
    };
    final labels =
        sortedDates.map((d) => DateFormat('dd/MM').format(d)).toList();

    final lines = <LineChartBarData>[];
    var colorIdx = 0;
    for (final entry in dataMap.entries) {
      final color =
          AppColors.chartColors[colorIdx % AppColors.chartColors.length];
      final spots = <FlSpot>[];
      for (final dc in entry.value) {
        final idx = dateIndex[dc.date];
        if (idx != null) {
          spots.add(FlSpot(idx.toDouble(), dc.count.toDouble()));
        }
      }
      spots.sort((a, b) => a.x.compareTo(b.x));
      lines.add(LineChartBarData(
        spots: spots,
        isCurved: true,
        color: color,
        barWidth: 2.5,
        isStrokeCapRound: true,
        dotData: FlDotData(show: spots.length <= 10),
        belowBarData: BarAreaData(
            show: true, color: color.withOpacity(0.05)),
      ));
      colorIdx++;
    }

    return ChartCard(
      title: title,
      subtitle: subtitle,
      chart: Column(
        children: [
          SizedBox(
            height: 280,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: AppColors.divider,
                    strokeWidth: 0.8,
                  ),
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: _labelInterval(labels.length),
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= labels.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(labels[i],
                              style: const TextStyle(fontSize: 10)),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) => Text(
                        _shortNumber(value),
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: lines,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _buildLegend(dataMap.keys.toList()),
        ],
      ),
    );
  }

  Widget _buildMultiLineChartValue({
    required String title,
    required String subtitle,
    required Map<String, List<DateValue>> dataMap,
  }) {
    if (dataMap.isEmpty) {
      return ChartCard(
        title: title,
        subtitle: subtitle,
        chart: SizedBox(height: 280, child: _emptyChart()),
      );
    }

    final allDates = <DateTime>{};
    for (final entry in dataMap.values) {
      for (final dv in entry) {
        allDates.add(dv.date);
      }
    }
    final sortedDates = allDates.toList()..sort();
    final dateIndex = {
      for (var i = 0; i < sortedDates.length; i++) sortedDates[i]: i
    };
    final labels =
        sortedDates.map((d) => DateFormat('dd/MM').format(d)).toList();

    final lines = <LineChartBarData>[];
    var colorIdx = 0;
    for (final entry in dataMap.entries) {
      final color =
          AppColors.chartColors[colorIdx % AppColors.chartColors.length];
      final spots = <FlSpot>[];
      for (final dv in entry.value) {
        final idx = dateIndex[dv.date];
        if (idx != null) {
          spots.add(FlSpot(idx.toDouble(), dv.value));
        }
      }
      spots.sort((a, b) => a.x.compareTo(b.x));
      lines.add(LineChartBarData(
        spots: spots,
        isCurved: true,
        color: color,
        barWidth: 2.5,
        isStrokeCapRound: true,
        dotData: FlDotData(show: spots.length <= 10),
        belowBarData: BarAreaData(
            show: true, color: color.withOpacity(0.05)),
      ));
      colorIdx++;
    }

    return ChartCard(
      title: title,
      subtitle: subtitle,
      chart: Column(
        children: [
          SizedBox(
            height: 280,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: AppColors.divider,
                    strokeWidth: 0.8,
                  ),
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: _labelInterval(labels.length),
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= labels.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(labels[i],
                              style: const TextStyle(fontSize: 10)),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 50,
                      getTitlesWidget: (value, meta) => Text(
                        _shortNumber(value),
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: lines,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _buildLegend(dataMap.keys.toList()),
        ],
      ),
    );
  }

  Widget _buildHorizontalBarChart({
    required String title,
    required String subtitle,
    required List<NameCount> items,
    required Color color,
  }) {
    if (items.isEmpty) {
      return ChartCard(
        title: title,
        subtitle: subtitle,
        chart: SizedBox(height: 280, child: _emptyChart()),
      );
    }
    final maxVal =
        items.map((e) => e.count).reduce((a, b) => a > b ? a : b).toDouble();

    return ChartCard(
      title: title,
      subtitle: subtitle,
      chart: SizedBox(
        height: (items.length * 44.0).clamp(150, 400),
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxVal * 1.15,
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  return BarTooltipItem(
                    '${items[group.x].name}\n${rod.toY.toInt()}',
                    const TextStyle(color: Colors.white, fontSize: 12),
                  );
                },
              ),
            ),
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 60,
                  getTitlesWidget: (value, meta) {
                    final i = value.toInt();
                    if (i < 0 || i >= items.length) {
                      return const SizedBox.shrink();
                    }
                    final name = items[i].name;
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: RotatedBox(
                        quarterTurns: -1,
                        child: Text(
                          name.length > 12
                              ? '${name.substring(0, 12)}...'
                              : name,
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    );
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 40,
                  getTitlesWidget: (value, meta) => Text(
                    _shortNumber(value),
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
              ),
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (value) => FlLine(
                color: AppColors.divider,
                strokeWidth: 0.8,
              ),
            ),
            barGroups: items.asMap().entries.map((e) {
              return BarChartGroupData(
                x: e.key,
                barRods: [
                  BarChartRodData(
                    toY: e.value.count.toDouble(),
                    color: color.withOpacity(0.8),
                    width: 20,
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4)),
                    backDrawRodData: BackgroundBarChartRodData(
                      show: true,
                      toY: maxVal * 1.15,
                      color: color.withOpacity(0.04),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildLegend(List<String> labels) {
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: labels.asMap().entries.map((e) {
        final color =
            AppColors.chartColors[e.key % AppColors.chartColors.length];
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 6),
            Text(e.value, style: const TextStyle(fontSize: 12)),
          ],
        );
      }).toList(),
    );
  }

  FlTitlesData _buildTitles(List<String> labels, List<FlSpot> spots) {
    return FlTitlesData(
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 28,
          interval: _labelInterval(labels.length),
          getTitlesWidget: (value, meta) {
            final i = value.toInt();
            if (i < 0 || i >= labels.length) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(labels[i], style: const TextStyle(fontSize: 10)),
            );
          },
        ),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 40,
          getTitlesWidget: (value, meta) => Text(
            _shortNumber(value),
            style: const TextStyle(fontSize: 10),
          ),
        ),
      ),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles:
          const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    );
  }

  double _labelInterval(int count) {
    if (count <= 7) return 1;
    if (count <= 15) return 2;
    if (count <= 30) return 5;
    return (count / 6).ceilToDouble();
  }

  double _calcInterval(double maxVal) {
    if (maxVal <= 5) return 1;
    if (maxVal <= 20) return 5;
    if (maxVal <= 100) return 20;
    return (maxVal / 5).ceilToDouble();
  }

  String _shortNumber(double value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    if (value == value.toInt()) return value.toInt().toString();
    return value.toStringAsFixed(1);
  }
}

class _RankItem {
  final String name;
  final String value;
  const _RankItem(this.name, this.value);
}
