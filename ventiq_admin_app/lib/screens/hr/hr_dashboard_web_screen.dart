import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../config/app_colors.dart';
import '../../models/hr/hr_attendance.dart';
import '../../models/hr/hr_dashboard_data.dart';
import '../../services/hr/hr_attendance_service.dart';
import '../../services/hr/hr_dashboard_service.dart';
import '../../services/store_service.dart';
import '../../services/subscription_service.dart';
import '../../widgets/hr/hr_drawer.dart';
import '../../widgets/hr/hr_modalidad_badge.dart';

/// Ancho maximo del contenido principal en web
const double _kMaxContentWidth = 1400.0;

class HRDashboardWebScreen extends StatefulWidget {
  const HRDashboardWebScreen({super.key});

  @override
  State<HRDashboardWebScreen> createState() => _HRDashboardWebScreenState();
}

class _HRDashboardWebScreenState extends State<HRDashboardWebScreen> {
  bool _isLoading = true;
  int? _storeId;
  bool _fromGerente = false;

  HRDashboardSummary? _summary;
  List<HRTopWorker> _topWorkers = [];
  List<HRAttendance> _currentlyWorking = [];

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

  /// Vuelve al mes en curso desde cualquier posicion del historico.
  void _goToCurrentMonth() {
    final now = DateTime.now();
    final current = DateTime(now.year, now.month, 1);
    if (current == _selectedMonth) return;
    setState(() {
      _selectedMonth = current;
      _updateDateRange();
    });
    _loadData();
  }

  Future<void> _initializeData() async {
    try {
      // Verificar que tiene plan Pro o Avanzado
      final hasPlan = await SubscriptionService().hasProPlanInAnyStore();
      if (!hasPlan) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'El módulo de Recursos Humanos requiere plan Pro o Avanzado',
              ),
              backgroundColor: Colors.orange,
            ),
          );
          Navigator.pop(context);
        }
        return;
      }

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
        HRAttendanceService.getWorkersCurrentlyWorking(_storeId!),
      ]);

      if (mounted) {
        setState(() {
          _summary = results[0] as HRDashboardSummary;
          _topWorkers = results[1] as List<HRTopWorker>;
          _currentlyWorking = results[2] as List<HRAttendance>;
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

  // =====================================================
  // BUILD
  // =====================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: _buildWebAppBar(),
      endDrawer: HRDrawer(isFromGerente: _fromGerente),
      body: _isLoading
          ? const Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                  strokeWidth: 2.5,
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadData,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: _kMaxContentWidth,
                  ),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildKPIRow(),
                        const SizedBox(height: 14),
                        _buildHoursChart(),
                        const SizedBox(height: 14),
                        _buildSalaryChart(),
                        const SizedBox(height: 14),
                        _buildTopWorkersSection(),
                        const SizedBox(height: 14),
                        _buildCurrentlyWorkingSection(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  PreferredSizeWidget _buildWebAppBar() {
    final monthName = DateFormat('MMMM yyyy').format(_selectedMonth);
    final monthLabel =
        monthName.substring(0, 1).toUpperCase() + monthName.substring(1);
    final isCurrentMonth = _selectedMonth ==
        DateTime(DateTime.now().year, DateTime.now().month, 1);

    return AppBar(
      backgroundColor: AppColors.primary,
      elevation: 0,
      centerTitle: false,
      iconTheme: const IconThemeData(color: Colors.white),
      title: const Text(
        'Dashboard RR.HH.',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),
      actions: [
        // Selector de mes integrado en la barra: evita una tarjeta entera
        // solo para navegar el periodo.
        Container(
          height: 34,
          margin: const EdgeInsets.symmetric(vertical: 7),
          padding: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: Colors.white12,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              _appBarIconBtn(
                Icons.chevron_left,
                'Mes anterior',
                () => _changeMonth(-1),
                size: 18,
              ),
              Container(
                constraints: const BoxConstraints(minWidth: 118),
                alignment: Alignment.center,
                child: Text(
                  monthLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _appBarIconBtn(
                Icons.chevron_right,
                'Mes siguiente',
                () => _changeMonth(1),
                size: 18,
              ),
            ],
          ),
        ),
        if (!isCurrentMonth)
          _appBarIconBtn(Icons.today, 'Ir al mes actual', _goToCurrentMonth),
        const SizedBox(width: 4),
        _appBarIconBtn(Icons.refresh, 'Actualizar', _loadData),
        Builder(
          builder: (context) => _appBarIconBtn(
            Icons.menu,
            'Menú',
            () => Scaffold.of(context).openEndDrawer(),
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _appBarIconBtn(
    IconData icon,
    String tooltip,
    VoidCallback onPressed, {
    double size = 20,
  }) {
    return IconButton(
      icon: Icon(icon, color: Colors.white, size: size),
      onPressed: onPressed,
      tooltip: tooltip,
      splashRadius: 18,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
    );
  }

  // =====================================================
  // KPIs
  // =====================================================

  /// KPIs en una sola fila compacta: en web una rejilla 2x2 desperdicia
  /// media pantalla de alto para cuatro numeros.
  Widget _buildKPIRow() {
    // KPI de tiempo: se adapta a la modalidad predominante del período.
    // Con plantilla mixta se muestran días arriba y horas como subtítulo,
    // porque los días sí son sumables entre ambas modalidades.
    final Widget tiempoKpi = (_summary?.tieneDias ?? false)
        ? _kpiCard(
            title: 'Total Días',
            value: _formatDias(_summary?.totalDias ?? 0),
            icon: Icons.today,
            color: AppColors.info,
            subtitle: (_summary?.esMixto ?? false)
                ? '+ ${_summary!.totalHoras.toStringAsFixed(1)}h por hora'
                : '${_summary?.totalRegistros ?? 0} registros',
          )
        : _kpiCard(
            title: 'Total Horas',
            value: '${_summary?.totalHoras.toStringAsFixed(1) ?? "0"}h',
            icon: Icons.access_time,
            color: AppColors.info,
            subtitle: '${_summary?.totalRegistros ?? 0} registros',
          );

    // IntrinsicHeight acota la altura antes de estirar las tarjetas: dentro de
    // un scroll vertical el alto es ilimitado y `stretch` lo propagaria como
    // infinito. Asi las cuatro igualan a la mas alta (la del subtitulo).
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: tiempoKpi),
          const SizedBox(width: 12),
          Expanded(
            child: _kpiCard(
              title: 'Salario Base',
              value:
                  '\$${_currencyFormat.format(_summary?.totalSalarioBase ?? 0)}',
              icon: Icons.attach_money,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _kpiCard(
              title: 'PPR Total',
              value: '\$${_currencyFormat.format(_summary?.totalPPR ?? 0)}',
              icon: Icons.emoji_events,
              color: AppColors.warning,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _kpiCard(
              title: 'Total General',
              value: '\$${_currencyFormat.format(_summary?.totalGeneral ?? 0)}',
              icon: Icons.account_balance_wallet,
              color: AppColors.success,
            ),
          ),
        ],
      ),
    );
  }

  /// Version web del HRKpiCard: icono y titulo en linea, valor a la derecha,
  /// sin el alto fijo que impone el aspect ratio del grid en movil.
  Widget _kpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: color,
                      height: 1.1,
                    ),
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Formatea una cantidad de días sin decimales innecesarios: 12 / 12.5
  String _formatDias(double dias) => dias == dias.roundToDouble()
      ? dias.toStringAsFixed(0)
      : dias.toStringAsFixed(2);

  // =====================================================
  // CHARTS
  // =====================================================

  Widget _buildHoursChart() {
    final dailyData = _summary?.dailyData ?? [];
    // Si en el período hay jornadas por día, el gráfico pasa a medir días:
    // sumar horas de quien cobra por día sugeriría que de ahí sale su pago.
    final porDia = _summary?.tieneDias ?? false;
    final titulo =
        porDia ? 'Días Trabajados por Fecha' : 'Horas Trabajadas por Día';
    final sufijo = porDia ? 'd' : 'h';
    double valorDe(HRDailyData d) => porDia ? d.dias : d.horas;

    if (dailyData.isEmpty) {
      return _buildEmptyChartCard(titulo, 'Sin datos para este periodo');
    }

    final maxValor =
        dailyData.map(valorDe).fold(0.0, (a, b) => a > b ? a : b);

    return _buildPanel(
      title: titulo,
      icon: Icons.bar_chart,
      trailing: _panelChip(
        '${dailyData.length} día${dailyData.length != 1 ? 's' : ''} con registro',
        AppColors.info,
      ),
      child: SizedBox(
        height: 190,
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxValor * 1.2,
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final d = dailyData[groupIndex];
                  return BarTooltipItem(
                    '${d.fecha}\n${valorDe(d).toStringAsFixed(1)}$sufijo',
                    const TextStyle(color: Colors.white, fontSize: 11),
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
                        child:
                            Text(day, style: const TextStyle(fontSize: 9)),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                  reservedSize: 22,
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 32,
                  getTitlesWidget: (value, meta) {
                    return Text(
                      '${value.toInt()}$sufijo',
                      style: const TextStyle(fontSize: 10),
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
                    toY: valorDe(dailyData[index]),
                    color: AppColors.info,
                    // En web hay mucho mas ancho disponible que en movil, asi
                    // que las barras pueden ser mas gruesas y legibles.
                    width: dailyData.length > 24 ? 10 : 16,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildSalaryChart() {
    final dailyData = _summary?.dailyData ?? [];
    if (dailyData.isEmpty) {
      return _buildEmptyChartCard(
        'Salario Acumulado del Mes',
        'Sin datos para este periodo',
      );
    }

    // Calcular acumulados
    double acumulado = 0;
    final acumulados = <double>[];
    for (final d in dailyData) {
      acumulado += d.total;
      acumulados.add(acumulado);
    }
    final maxY = acumulados.isEmpty ? 100.0 : acumulados.last * 1.1;

    return _buildPanel(
      title: 'Salario Acumulado del Mes',
      icon: Icons.show_chart,
      trailing: _panelChip(
        'Cierre: \$${_currencyFormat.format(acumulados.last)}',
        AppColors.success,
      ),
      child: SizedBox(
        height: 190,
        child: LineChart(
          LineChartData(
            minY: 0,
            maxY: maxY,
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (spots) {
                  return spots.map((spot) {
                    final idx = spot.x.toInt();
                    final fecha = idx >= 0 && idx < dailyData.length
                        ? '${dailyData[idx].fecha}\n'
                        : '';
                    return LineTooltipItem(
                      '$fecha\$${_currencyFormat.format(spot.y)}',
                      const TextStyle(color: Colors.white, fontSize: 11),
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
                        child:
                            Text(day, style: const TextStyle(fontSize: 9)),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                  reservedSize: 22,
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 52,
                  getTitlesWidget: (value, meta) {
                    return Text(
                      '\$${_currencyFormat.format(value)}',
                      style: const TextStyle(fontSize: 9),
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
    );
  }

  Widget _buildEmptyChartCard(String title, String message) {
    return _buildPanel(
      title: title,
      icon: Icons.bar_chart,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 26),
        child: Column(
          children: [
            Icon(Icons.bar_chart, size: 40, color: Colors.grey[300]),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // SHARED WEB CHROME
  // =====================================================

  /// Tarjeta blanca con cabecera compacta: base de cada bloque del dashboard.
  Widget _buildPanel({
    required String title,
    required IconData icon,
    required Widget child,
    Widget? trailing,
    List<Widget> stats = const [],
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Row(
              children: [
                Icon(icon, size: 17, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
          if (stats.isNotEmpty)
            Container(
              color: const Color(0xFFF8FAFC),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 9,
              ),
              child: Row(children: stats),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _panelChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
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

  Widget _buildEmptyBlock(IconData icon, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 26),
        child: Column(
          children: [
            Icon(icon, size: 40, color: Colors.grey[300]),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(double hours) {
    final h = hours.floor();
    final m = ((hours - h) * 60).round();
    return '${h}h ${m}m';
  }

  // =====================================================
  // TOP WORKERS (tabla identica a la version movil)
  // =====================================================

  Widget _buildTopWorkersSection() {
    // Calcular promedios para datos de interes
    final totalWorkers = _topWorkers.length;
    double avgDiasPerWorker = 0;
    double avgSalarioPerDia = 0;
    double avgHorasPerWorker = 0;
    double avgSalarioPerHour = 0;
    // Con plantilla mixta los promedios por hora solo se calculan sobre quienes
    // realmente cobran por hora; mezclarlos falsearía la tarifa media.
    final workersPorHora = _topWorkers.where((w) => !w.esPorDia).toList();
    if (totalWorkers > 0) {
      final sumDias = _topWorkers.fold<double>(0, (a, w) => a + w.totalDias);
      final sumBase =
          _topWorkers.fold<double>(0, (a, w) => a + w.totalSalarioBase);
      avgDiasPerWorker = sumDias / totalWorkers;
      avgSalarioPerDia = sumDias > 0 ? sumBase / sumDias : 0;
    }
    if (workersPorHora.isNotEmpty) {
      final sumHoras =
          workersPorHora.fold<double>(0, (a, w) => a + w.totalHoras);
      final sumBaseHora =
          workersPorHora.fold<double>(0, (a, w) => a + w.totalSalarioBase);
      avgHorasPerWorker = sumHoras / workersPorHora.length;
      avgSalarioPerHour = sumHoras > 0 ? sumBaseHora / sumHoras : 0;
    }
    final hayPorDia = _topWorkers.any((w) => w.esPorDia);

    return _buildPanel(
      title: 'Trabajadores Destacados',
      icon: Icons.emoji_events,
      trailing: totalWorkers > 0
          ? _panelChip('$totalWorkers trabajadores', AppColors.info)
          : null,
      // Los promedios se expresan en la unidad predominante para que el
      // número tenga un significado real y no una mezcla de ambas.
      stats: totalWorkers == 0
          ? const []
          : [
              if (hayPorDia) ...[
                _buildMiniStat(
                  'Prom. días/persona',
                  _formatDias(avgDiasPerWorker),
                ),
                const SizedBox(width: 16),
                _buildMiniStat(
                  'Prom. \$/día',
                  '\$${_currencyFormat.format(avgSalarioPerDia)}',
                ),
              ] else ...[
                _buildMiniStat(
                  'Prom. horas/persona',
                  '${avgHorasPerWorker.toStringAsFixed(1)}h',
                ),
                const SizedBox(width: 16),
                _buildMiniStat(
                  'Prom. \$/hora',
                  '\$${_currencyFormat.format(avgSalarioPerHour)}',
                ),
              ],
              const SizedBox(width: 16),
              _buildMiniStat(
                'Costo total',
                '\$${_currencyFormat.format(_summary?.totalGeneral ?? 0)}',
              ),
            ],
      child: _topWorkers.isEmpty
          ? _buildEmptyBlock(
              Icons.people_outline,
              'Sin datos para este periodo',
            )
          : _buildTopWorkersTable(),
    );
  }

  Widget _buildTopWorkersTable() {
    // Tabla intacta respecto a movil; solo el minWidth pasa a medirse contra
    // el ancho real del panel en vez del ancho de la ventana.
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
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
                DataColumn(label: Text('Mod.')),
                DataColumn(label: Text('Dias'), numeric: true),
                DataColumn(label: Text('Horas'), numeric: true),
                DataColumn(label: Text('Base'), numeric: true),
                DataColumn(label: Text('PPR'), numeric: true),
                DataColumn(label: Text('Total'), numeric: true),
                DataColumn(label: Text('Prom.'), numeric: true),
                DataColumn(label: Text('')),
              ],
              rows: List.generate(_topWorkers.length, (i) {
                final w = _topWorkers[i];
                // El promedio se expresa en la unidad de SU modalidad:
                // $/día para quien cobra por día, $/hora para el resto.
                final avgPorUnidad = w.esPorDia
                    ? (w.totalDias > 0 ? w.totalGeneral / w.totalDias : 0.0)
                    : (w.totalHoras > 0 ? w.totalGeneral / w.totalHoras : 0.0);
                return DataRow(
                  color: i == 0
                      ? WidgetStateProperty.all(
                          AppColors.success.withOpacity(0.05),
                        )
                      : null,
                  cells: [
                    DataCell(Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontWeight:
                            i < 3 ? FontWeight.w700 : FontWeight.normal,
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
                    DataCell(HRModalidadBadge(
                      tipoSalario: w.tipoSalario,
                      fontSize: 8,
                    )),
                    DataCell(Text(w.diasFormatted)),
                    DataCell(Text(
                      w.horasFormatted,
                      style:
                          w.esPorDia ? TextStyle(color: Colors.grey[400]) : null,
                    )),
                    DataCell(
                      Text('\$${_currencyFormat.format(w.totalSalarioBase)}'),
                    ),
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
                      '\$${avgPorUnidad.toStringAsFixed(2)}'
                      '${w.tipoSalario.tarifaSufijo}',
                      style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                    )),
                    DataCell(
                      w.tienePPR
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
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
        );
      },
    );
  }

  // =====================================================
  // CURRENTLY WORKING (tabla identica a la version movil)
  // =====================================================

  Widget _buildCurrentlyWorkingSection() {
    final totalWorking = _currentlyWorking.length;

    // Acumulados
    double totalHorasAcum = 0;
    double totalGanadoAcum = 0;
    double totalProyectado = 0; // suponiendo hasta 8h tope (solo por hora)
    for (final w in _currentlyWorking) {
      final horas = w.horasTranscurridas ?? 0;
      totalHorasAcum += horas;
      if (w.esPorDia) {
        // Quien cobra por día devenga la jornada completa desde que ficha:
        // sus horas transcurridas no modifican el importe.
        totalGanadoAcum += w.salarioHora;
        totalProyectado += w.salarioHora + w.pagoPorResultado;
      } else {
        totalGanadoAcum += horas * w.salarioHora;
        final horasProyectadas = horas.clamp(0, 8).toDouble();
        totalProyectado += horasProyectadas * w.salarioHora +
            (w.pagoPorResultado > 0 ? w.pagoPorResultado : 0);
      }
    }

    return _buildPanel(
      title: 'Trabajadores Activos Ahora',
      icon: Icons.work_history,
      trailing: totalWorking > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '$totalWorking activos',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.success,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
          : null,
      stats: totalWorking == 0
          ? const []
          : [
              _buildMiniStat('Horas acum.', _formatDuration(totalHorasAcum)),
              const SizedBox(width: 16),
              _buildMiniStat(
                'Ganado ahora',
                '\$${_currencyFormat.format(totalGanadoAcum)}',
              ),
              const SizedBox(width: 16),
              _buildMiniStat(
                'Proy. (8h+PPR)',
                '\$${_currencyFormat.format(totalProyectado)}',
              ),
            ],
      child: _currentlyWorking.isEmpty
          ? _buildEmptyBlock(
              Icons.person_off,
              'No hay trabajadores activos en este momento',
            )
          : _buildCurrentlyWorkingTable(),
    );
  }

  Widget _buildCurrentlyWorkingTable() {
    final timeFormat = DateFormat('HH:mm');

    // Tabla intacta respecto a movil; solo el minWidth pasa a medirse contra
    // el ancho real del panel en vez del ancho de la ventana.
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              columnSpacing: 12,
              headingTextStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 11,
                color: AppColors.textPrimary,
              ),
              dataTextStyle: const TextStyle(fontSize: 11),
              headingRowColor: WidgetStateProperty.all(
                AppColors.success.withOpacity(0.05),
              ),
              columns: const [
                DataColumn(label: Text('Nombre')),
                DataColumn(label: Text('Rol')),
                DataColumn(label: Text('Mod.')),
                DataColumn(label: Text('Entrada')),
                DataColumn(label: Text('Tiempo'), numeric: true),
                DataColumn(label: Text('Tarifa'), numeric: true),
                DataColumn(label: Text('Ganado'), numeric: true),
                DataColumn(label: Text('Proy.'), numeric: true),
                DataColumn(label: Text('PPR'), numeric: true),
                DataColumn(label: Text('Total proy.'), numeric: true),
              ],
              rows: List.generate(_currentlyWorking.length, (i) {
                final w = _currentlyWorking[i];
                final horas = w.horasTranscurridas ?? 0;
                // Por día: la jornada completa se devenga al fichar, así
                // que ganado y proyectado coinciden con la tarifa diaria.
                final ganado =
                    w.esPorDia ? w.salarioHora : horas * w.salarioHora;
                final proyBase = w.esPorDia
                    ? w.salarioHora
                    : horas.clamp(0, 8).toDouble() * w.salarioHora;
                final totalProy = proyBase +
                    (w.pagoPorResultado > 0 ? w.pagoPorResultado : 0);
                return DataRow(
                  cells: [
                    DataCell(Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 10,
                          backgroundColor: AppColors.primary.withOpacity(0.1),
                          child: Text(
                            w.nombres.isNotEmpty
                                ? w.nombres[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          w.nombreCompleto,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ],
                    )),
                    DataCell(Text(
                      w.rolNombre ?? '-',
                      style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                    )),
                    DataCell(HRModalidadBadge(
                      tipoSalario: w.tipoSalario,
                      fontSize: 8,
                    )),
                    DataCell(Text(
                      w.horaEntrada != null
                          ? timeFormat.format(w.horaEntrada!)
                          : '--:--',
                    )),
                    DataCell(Text(_formatDuration(horas))),
                    DataCell(Text(w.tarifaFormatted)),
                    DataCell(Text(
                      '\$${_currencyFormat.format(ganado)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.success,
                      ),
                    )),
                    DataCell(Text('\$${_currencyFormat.format(proyBase)}')),
                    DataCell(
                      w.pagoPorResultado > 0
                          ? Text(
                              '\$${_currencyFormat.format(w.pagoPorResultado)}',
                              style: const TextStyle(
                                color: AppColors.warning,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          : Text(
                              '-',
                              style: TextStyle(color: Colors.grey[400]),
                            ),
                    ),
                    DataCell(Text(
                      '\$${_currencyFormat.format(totalProy)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    )),
                  ],
                );
              }),
            ),
          ),
        );
      },
    );
  }
}
