import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../config/app_colors.dart';
import '../models/dashboard_data.dart';
import '../services/dashboard_service.dart';
import '../utils/platform_utils.dart';
import '../widgets/app_drawer.dart';
import '../widgets/kpi_card.dart';
import '../widgets/chart_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final DashboardService _dashboardService = DashboardService();
  DashboardData? _dashboardData;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final data = await _dashboardService.getDashboardData();
      
      if (mounted) {
        setState(() {
          _dashboardData = data;
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

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isDesktop = PlatformUtils.shouldUseDesktopLayout(screenSize.width);
    
    return Scaffold(
      appBar: AppBar(
        title: Text(
          isDesktop 
              ? 'Dashboard Ejecutivo - VentIQ Super Admin'
              : 'Dashboard Ejecutivo',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDashboardData,
            tooltip: 'Actualizar datos',
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: const AppDrawer(),
      body: _buildBody(isDesktop, screenSize.width),
    );
  }

  Widget _buildBody(bool isDesktop, double screenWidth) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Cargando datos del dashboard...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: AppColors.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Error al cargar los datos',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadDashboardData,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadDashboardData,
      child: SingleChildScrollView(
        padding: EdgeInsets.all(PlatformUtils.getScreenPadding()),
        child: isDesktop 
            ? _buildDesktopLayout(screenWidth)
            : _buildMobileLayout(),
      ),
    );
  }

  Widget _buildDesktopLayout(double screenWidth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildKPISection(isDesktop: true, screenWidth: screenWidth),
        const SizedBox(height: 24),
        _buildChartsSection(isDesktop: true),
        const SizedBox(height: 24),
        _buildActivitySection(),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildKPISection(isDesktop: false),
        const SizedBox(height: 16),
        _buildChartsSection(isDesktop: false),
        const SizedBox(height: 16),
        _buildActivitySection(),
      ],
    );
  }

  Widget _buildKPISection({required bool isDesktop, double? screenWidth}) {
    final kpis = _getKPICards();
    
    if (isDesktop && screenWidth != null && screenWidth > 1200) {
      // Layout de 4 columnas para pantallas grandes
      return Row(
        children: kpis.map((kpi) => 
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: KPICard(kpiData: kpi),
            ),
          ),
        ).toList(),
      );
    } else if (isDesktop) {
      // Layout de 2x2 para pantallas medianas
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: KPICard(kpiData: kpis[0])),
              const SizedBox(width: 16),
              Expanded(child: KPICard(kpiData: kpis[1])),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: KPICard(kpiData: kpis[2])),
              const SizedBox(width: 16),
              Expanded(child: KPICard(kpiData: kpis[3])),
            ],
          ),
        ],
      );
    } else {
      // Layout móvil - 2 columnas
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: KPICard(kpiData: kpis[0])),
              const SizedBox(width: 8),
              Expanded(child: KPICard(kpiData: kpis[1])),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: KPICard(kpiData: kpis[2])),
              const SizedBox(width: 8),
              Expanded(child: KPICard(kpiData: kpis[3])),
            ],
          ),
        ],
      );
    }
  }

  Widget _buildChartsSection({required bool isDesktop}) {
    if (isDesktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: ChartCard(
              title: 'Registro de Tiendas por Mes',
              chart: _buildRegistroTiendasChart(),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: ChartCard(
              title: 'Ventas Globales',
              chart: _buildVentasChart(),
            ),
          ),
        ],
      );
    } else {
      return Column(
        children: [
          ChartCard(
            title: 'Registro de Tiendas por Mes',
            chart: _buildRegistroTiendasChart(),
          ),
          const SizedBox(height: 16),
          ChartCard(
            title: 'Ventas Globales',
            chart: _buildVentasChart(),
          ),
        ],
      );
    }
  }

  Widget _buildActivitySection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.timeline,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Actividad Reciente',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildActivityItem(
              icon: Icons.store_outlined,
              title: 'Nueva tienda registrada',
              subtitle: 'Supermercado La Moderna - Santiago',
              time: 'Hace 2 horas',
              color: AppColors.success,
            ),
            _buildActivityItem(
              icon: Icons.warning_outlined,
              title: 'Licencia próxima a vencer',
              subtitle: 'Minimarket La Esquina - 15 días restantes',
              time: 'Hace 4 horas',
              color: AppColors.warning,
            ),
            _buildActivityItem(
              icon: Icons.person_add_outlined,
              title: 'Nuevo usuario registrado',
              subtitle: 'Ana García - Administrador de tienda',
              time: 'Hace 6 horas',
              color: AppColors.info,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required String time,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            time,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textHint,
            ),
          ),
        ],
      ),
    );
  }

  List<KPIData> _getKPICards() {
    return [
      KPIData(
        title: 'Total Tiendas',
        value: _dashboardData!.totalTiendas.toString(),
        subtitle: 'Tiendas registradas',
        icon: Icons.store,
        color: AppColors.primary,
        trend: '+8.5%',
        isPositiveTrend: true,
      ),
      KPIData(
        title: 'Tiendas Activas',
        value: _dashboardData!.tiendasActivas.toString(),
        subtitle: 'En funcionamiento',
        icon: Icons.check_circle,
        color: AppColors.success,
        trend: '+2.1%',
        isPositiveTrend: true,
      ),
      KPIData(
        title: 'Renovaciones',
        value: _dashboardData!.tiendasPendientesRenovacion.toString(),
        subtitle: 'Próximas a vencer',
        icon: Icons.schedule,
        color: AppColors.warning,
        trend: '-5.2%',
        isPositiveTrend: false,
      ),
      KPIData(
        title: 'Ventas Globales',
        value: '\$${(_dashboardData!.dineroTotalVendido / 1000).toStringAsFixed(0)}K',
        subtitle: 'Este mes',
        icon: Icons.trending_up,
        color: AppColors.info,
        trend: '+12.3%',
        isPositiveTrend: true,
      ),
    ];
  }

  Widget _buildRegistroTiendasChart() {
    return SizedBox(
      height: 300,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(show: true),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 40),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final months = ['E', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
                  if (value.toInt() >= 0 && value.toInt() < months.length) {
                    return Text(months[value.toInt()]);
                  }
                  return const Text('');
                },
              ),
            ),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: true),
          lineBarsData: [
            LineChartBarData(
              spots: _dashboardData!.registroTiendasChart
                  .asMap()
                  .entries
                  .map((e) => FlSpot(e.key.toDouble(), e.value.value))
                  .toList(),
              isCurved: true,
              color: AppColors.primary,
              barWidth: 3,
              dotData: FlDotData(show: true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVentasChart() {
    return SizedBox(
      height: 300,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: _dashboardData!.ventasChart
              .map((e) => e.value)
              .reduce((a, b) => a > b ? a : b) * 1.2,
          barTouchData: BarTouchData(enabled: true),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 50,
                getTitlesWidget: (value, meta) {
                  return Text('${(value / 1000).toInt()}K');
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final months = ['E', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
                  if (value.toInt() >= 0 && value.toInt() < months.length) {
                    return Text(months[value.toInt()]);
                  }
                  return const Text('');
                },
              ),
            ),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          barGroups: _dashboardData!.ventasChart
              .asMap()
              .entries
              .map((e) => BarChartGroupData(
                    x: e.key,
                    barRods: [
                      BarChartRodData(
                        toY: e.value.value,
                        color: AppColors.secondary,
                        width: 16,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          topRight: Radius.circular(4),
                        ),
                      ),
                    ],
                  ))
              .toList(),
        ),
      ),
    );
  }
}
