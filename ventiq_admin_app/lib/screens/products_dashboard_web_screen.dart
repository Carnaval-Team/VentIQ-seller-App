import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../config/app_colors.dart';
import '../services/products_analytics_service.dart';
import '../services/permissions_service.dart';
import '../widgets/products_kpi_cards.dart';
import '../widgets/products_charts_widget.dart';
import '../widgets/admin_drawer.dart';
import '../utils/number_formatter.dart';
import '../utils/navigation_guard.dart';

class ProductsDashboardWebScreen extends StatefulWidget {
  const ProductsDashboardWebScreen({super.key});

  @override
  State<ProductsDashboardWebScreen> createState() =>
      _ProductsDashboardWebScreenState();
}

class _ProductsDashboardWebScreenState
    extends State<ProductsDashboardWebScreen> with TickerProviderStateMixin {
  late TabController _tabController;

  bool _isLoadingKPIs = true;
  bool _isLoadingCharts = true;
  bool _isLoadingAlerts = true;

  final PermissionsService _permissionsService = PermissionsService();
  bool _canCreateProduct = false;

  Map<String, dynamic> _kpis = {};
  List<Map<String, dynamic>> _categoryDistribution = [];
  List<Map<String, dynamic>> _stockTrends = [];
  Map<String, dynamic> _abcAnalysis = {};
  List<Map<String, dynamic>> _topProducts = [];
  List<Map<String, dynamic>> _alerts = [];
  Map<String, dynamic> _bcgAnalysis = {};

  int _pieTouchedIndex = -1;

  static const double _kMaxContentWidth = 1400;

  static const List<Color> _categoryPalette = [
    AppColors.primary,
    AppColors.success,
    AppColors.warning,
    AppColors.info,
    Color(0xFFEF4444),
    Color(0xFF8B5CF6),
    Color(0xFF0EA5E9),
    Color(0xFF14B8A6),
    Color(0xFFF59E0B),
    Color(0xFFEC4899),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _checkPermissions();
    _loadDashboardData();
  }

  void _checkPermissions() async {
    final canCreate =
        await _permissionsService.canPerformAction('product.create');
    if (mounted) setState(() => _canCreateProduct = canCreate);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    await Future.wait([_loadKPIs(), _loadChartsData(), _loadAlertsData()]);
  }

  Future<void> _loadKPIs() async {
    try {
      setState(() => _isLoadingKPIs = true);
      final kpis = await ProductsAnalyticsService.getProductsKPIs();
      if (mounted) {
        setState(() {
          _kpis = kpis;
          _isLoadingKPIs = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingKPIs = false);
    }
  }

  Future<void> _loadChartsData() async {
    setState(() => _isLoadingCharts = true);
    try {
      final results = await Future.wait([
        ProductsAnalyticsService.getCategoryDistribution()
            .catchError((_) => <Map<String, dynamic>>[]),
        ProductsAnalyticsService.getStockTrends(days: 7)
            .catchError((_) => <Map<String, dynamic>>[]),
        ProductsAnalyticsService.getABCAnalysis()
            .catchError((_) => <String, dynamic>{}),
        ProductsAnalyticsService.getTopPerformingProducts(limit: 10)
            .catchError((_) => <Map<String, dynamic>>[]),
        ProductsAnalyticsService.getBCGAnalysis().catchError(
            (_) => <String, dynamic>{
                  'productos': [],
                  'resumen': {},
                  'umbrales': {},
                }),
      ]);

      if (mounted) {
        setState(() {
          _categoryDistribution = results[0] as List<Map<String, dynamic>>;
          _stockTrends = results[1] as List<Map<String, dynamic>>;
          _abcAnalysis = results[2] as Map<String, dynamic>;
          _topProducts = results[3] as List<Map<String, dynamic>>;
          _bcgAnalysis = results[4] as Map<String, dynamic>;
          _isLoadingCharts = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingCharts = false;
          _bcgAnalysis = _bcgAnalysis.isEmpty
              ? {'productos': [], 'resumen': {}, 'umbrales': {}}
              : _bcgAnalysis;
        });
      }
    }
  }

  Future<void> _loadAlertsData() async {
    try {
      setState(() => _isLoadingAlerts = true);
      final alerts = await ProductsAnalyticsService.getProductsAlerts();
      if (mounted) {
        setState(() {
          _alerts = alerts;
          _isLoadingAlerts = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingAlerts = false);
    }
  }

  Future<void> _refreshData() async {
    await _loadDashboardData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Dashboard actualizado'),
            ],
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Dashboard de Productos',
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
            onPressed: _refreshData,
            tooltip: 'Actualizar datos',
          ),
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => Scaffold.of(context).openEndDrawer(),
              tooltip: 'Menú',
            ),
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Container(
            color: AppColors.primary,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _kMaxContentWidth),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: false,
                    tabs: const [
                      Tab(
                        height: 48,
                        child: _TabLabel(
                          icon: Icons.dashboard_outlined,
                          text: 'Resumen',
                        ),
                      ),
                      Tab(
                        height: 48,
                        child: _TabLabel(
                          icon: Icons.analytics_outlined,
                          text: 'Análisis',
                        ),
                      ),
                      Tab(
                        height: 48,
                        child: _TabLabel(
                          icon: Icons.warning_amber_outlined,
                          text: 'Alertas',
                        ),
                      ),
                      Tab(
                        height: 48,
                        child: _TabLabel(
                          icon: Icons.lightbulb_outline,
                          text: 'Estrategia',
                        ),
                      ),
                    ],
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white70,
                    indicator: const UnderlineTabIndicator(
                      borderSide:
                          BorderSide(width: 3, color: Colors.white),
                      insets: EdgeInsets.symmetric(horizontal: 20),
                    ),
                    labelStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    overlayColor: MaterialStateProperty.resolveWith(
                      (states) => Colors.white.withOpacity(0.08),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildResumenTabWeb(),
          _buildBCGTab(),
          _buildAlertasTab(),
          _buildEstrategiaTab(),
        ],
      ),
      endDrawer: const AdminDrawer(),
      floatingActionButton: _tabController.index == 0 && _canCreateProduct
          ? FloatingActionButton.extended(
              onPressed: () => NavigationGuard.navigateWithPermission(
                  context, '/add-product'),
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Nuevo Producto',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              elevation: 3,
            )
          : null,
    );
  }

  // =====================================================
  // PAGE HEADER (reutilizable por tab)
  // =====================================================
  Widget _buildPageHeader({
    required IconData icon,
    required String title,
    required String subtitle,
    Color? accentColor,
  }) {
    final color = accentColor ?? AppColors.primary;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withOpacity(0.08),
            color.withOpacity(0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // SECTION CARD (contenedor estético para secciones)
  // =====================================================
  Widget _buildSectionCard({
    required String title,
    String? subtitle,
    required IconData icon,
    Color? iconColor,
    Widget? action,
    required Widget child,
    EdgeInsets? padding,
  }) {
    final color = iconColor ?? AppColors.primary;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          height: 1.2,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (action != null) action,
              ],
            ),
          ),
          Container(height: 1, color: AppColors.border),
          Padding(
            padding: padding ?? const EdgeInsets.all(20),
            child: child,
          ),
        ],
      ),
    );
  }

  // =====================================================
  // RESUMEN TAB
  // =====================================================
  Widget _buildResumenTabWeb() {
    return RefreshIndicator(
      onRefresh: _refreshData,
      color: AppColors.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kMaxContentWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Acciones rápidas (icono + texto en línea)
                _buildQuickActionsCard(),
                const SizedBox(height: 20),

                // Indicadores Clave dentro de un card
                _buildSectionCard(
                  title: 'Indicadores Clave',
                  subtitle: 'Métricas principales del inventario',
                  icon: Icons.speed_outlined,
                  iconColor: AppColors.primary,
                  padding: const EdgeInsets.all(16),
                  child: _buildKpiGrid(),
                ),
                const SizedBox(height: 24),

                // Info adicional + Distribución categorías en una sola columna
                _buildSectionCard(
                  title: 'Información del Inventario',
                  subtitle: 'Detalles y alertas relevantes',
                  icon: Icons.insights_outlined,
                  iconColor: AppColors.info,
                  child: ProductsAdditionalInfo(
                    kpis: _kpis,
                    isLoading: _isLoadingKPIs,
                  ),
                ),
                const SizedBox(height: 20),
                _buildCategoryChartCard(),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =====================================================
  // QUICK ACTIONS (icono + texto en la misma línea)
  // =====================================================
  Widget _buildQuickActionsCard() {
    final actions = <_QuickActionData>[
      _QuickActionData(
        icon: Icons.add,
        label: 'Agregar Producto',
        color: AppColors.primary,
        onTap: _canCreateProduct
            ? () => NavigationGuard.navigateWithPermission(
                context, '/add-product')
            : null,
      ),
      _QuickActionData(
        icon: Icons.list_alt_outlined,
        label: 'Ver Todos',
        color: AppColors.info,
        onTap: () =>
            NavigationGuard.navigateWithPermission(context, '/products'),
      ),
      _QuickActionData(
        icon: Icons.warning_amber_outlined,
        label: 'Alertas',
        color: AppColors.warning,
        onTap: () {
          if (!mounted) return;
          _tabController.animateTo(2);
        },
      ),
      _QuickActionData(
        icon: Icons.analytics_outlined,
        label: 'Análisis',
        color: AppColors.success,
        onTap: () {
          if (!mounted) return;
          _tabController.animateTo(1);
        },
      ),
    ];

    return _buildSectionCard(
      title: 'Acciones Rápidas',
      subtitle: 'Atajos frecuentes del módulo',
      icon: Icons.flash_on_outlined,
      iconColor: AppColors.primary,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          for (int i = 0; i < actions.length; i++) ...[
            Expanded(child: _buildQuickActionButton(actions[i])),
            if (i < actions.length - 1) const SizedBox(width: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickActionButton(_QuickActionData action) {
    final enabled = action.onTap != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            color: action.color.withOpacity(enabled ? 0.08 : 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: action.color.withOpacity(enabled ? 0.25 : 0.12),
            ),
          ),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                action.icon,
                color: action.color.withOpacity(enabled ? 1 : 0.5),
                size: 18,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  action.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: action.color.withOpacity(enabled ? 1 : 0.5),
                    letterSpacing: 0.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =====================================================
  // KPI GRID (stacks individuales bonitos dentro del card)
  // =====================================================
  Widget _buildKpiGrid() {
    final kpis = [
      _CompactKpi(
        title: 'Total Productos',
        value: '${_kpis['totalProductos'] ?? 0}',
        icon: Icons.inventory_2_outlined,
        color: AppColors.primary,
      ),
      _CompactKpi(
        title: 'Productos con Stock',
        value: '${_kpis['productosConStock'] ?? 0}',
        percentage: (_kpis['porcentajeConStock'] as num?)?.toDouble(),
        icon: Icons.check_circle_outline,
        color: AppColors.success,
      ),
      _CompactKpi(
        title: 'Productos Stock Bajo',
        value: '${_kpis['productosStockBajo'] ?? 0}',
        percentage: (_kpis['porcentajeStockBajo'] as num?)?.toDouble(),
        icon: Icons.warning_amber_outlined,
        color: AppColors.error,
      ),
      _CompactKpi(
        title: 'Valor Inventario',
        value:
            'CUP \$${NumberFormatter.formatCurrency(_kpis['valorTotalInventario'] ?? 0.0)}',
        icon: Icons.account_balance_wallet_outlined,
        color: AppColors.success,
      ),
      _CompactKpi(
        title: 'Productos Elaborados',
        value: '${_kpis['productosElaborados'] ?? 0}',
        icon: Icons.construction_outlined,
        color: AppColors.warning,
      ),
      _CompactKpi(
        title: 'Sin Movimiento',
        value: '${_kpis['productosSinMovimiento'] ?? 0}',
        percentage: (_kpis['porcentajeSinMovimiento'] as num?)?.toDouble(),
        icon: Icons.pause_circle_outline,
        color: AppColors.textSecondary,
      ),
    ];

    final tiles =
        _isLoadingKPIs ? List.generate(6, (_) => _buildKpiTileSkeleton()) : kpis.map(_buildKpiTile).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final maxW = constraints.maxWidth;
        final cols = maxW >= 1100
            ? 6
            : maxW >= 800
                ? 3
                : 2;
        final totalGaps = gap * (cols - 1);
        final tileWidth = (maxW - totalGaps) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: tiles
              .map((t) => SizedBox(width: tileWidth, child: t))
              .toList(),
        );
      },
    );
  }

  Widget _buildKpiTile(_CompactKpi kpi) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: kpi.color.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: kpi.color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(kpi.icon, color: kpi.color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  kpi.title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.2,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (kpi.percentage != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: kpi.color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${kpi.percentage!.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: kpi.color,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 24,
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                kpi.value,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: kpi.color,
                  height: 1.1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiTileSkeleton() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: 90,
            height: 18,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // KPI COMPACTO (una sola fila, estético) — legacy (sin uso)
  // =====================================================
  // ignore: unused_element
  Widget _buildCompactKpiRowLegacy() {
    final kpis = [
      _CompactKpi(
        title: 'Total',
        value: '${_kpis['totalProductos'] ?? 0}',
        icon: Icons.inventory_2_outlined,
        color: AppColors.primary,
      ),
      _CompactKpi(
        title: 'Con Stock',
        value: '${_kpis['productosConStock'] ?? 0}',
        percentage: (_kpis['porcentajeConStock'] as num?)?.toDouble(),
        icon: Icons.check_circle_outline,
        color: AppColors.success,
      ),
      _CompactKpi(
        title: 'Stock Bajo',
        value: '${_kpis['productosStockBajo'] ?? 0}',
        percentage: (_kpis['porcentajeStockBajo'] as num?)?.toDouble(),
        icon: Icons.warning_amber_outlined,
        color: AppColors.error,
      ),
      _CompactKpi(
        title: 'Valor',
        value:
            'CUP \$${NumberFormatter.formatCurrency(_kpis['valorTotalInventario'] ?? 0.0)}',
        icon: Icons.account_balance_wallet_outlined,
        color: AppColors.success,
      ),
      _CompactKpi(
        title: 'Elaborados',
        value: '${_kpis['productosElaborados'] ?? 0}',
        icon: Icons.construction_outlined,
        color: AppColors.warning,
      ),
      _CompactKpi(
        title: 'Sin Mov.',
        value: '${_kpis['productosSinMovimiento'] ?? 0}',
        percentage: (_kpis['porcentajeSinMovimiento'] as num?)?.toDouble(),
        icon: Icons.pause_circle_outline,
        color: AppColors.textSecondary,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: _isLoadingKPIs
          ? _buildCompactKpiSkeleton()
          : Row(
              children: kpis.asMap().entries.expand((entry) {
                final idx = entry.key;
                final kpi = entry.value;
                return [
                  Expanded(child: _buildCompactKpiTile(kpi)),
                  if (idx < kpis.length - 1)
                    Container(
                      width: 1,
                      height: 44,
                      margin:
                          const EdgeInsets.symmetric(horizontal: 4),
                      color: AppColors.border,
                    ),
                ];
              }).toList(),
            ),
    );
  }

  Widget _buildCompactKpiTile(_CompactKpi kpi) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: kpi.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(kpi.icon, color: kpi.color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        kpi.title,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (kpi.percentage != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: kpi.color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${kpi.percentage!.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: kpi.color,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    kpi.value,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: kpi.color,
                      height: 1.1,
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

  Widget _buildCompactKpiSkeleton() {
    return Row(
      children: List.generate(6, (index) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 50,
                        height: 8,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: 40,
                        height: 14,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  // =====================================================
  // CATEGORY CHART (rediseño custom, sin doble título)
  // =====================================================
  Widget _buildCategoryChartCard() {
    return _buildSectionCard(
      title: 'Distribución por Categoría',
      subtitle: 'Composición del catálogo por tipo de producto',
      icon: Icons.pie_chart_outline,
      iconColor: AppColors.primary,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      child: _buildCategoryChartContent(),
    );
  }

  Widget _buildCategoryChartContent() {
    if (_isLoadingCharts) {
      return const SizedBox(
        height: 260,
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    if (_categoryDistribution.isEmpty ||
        (_categoryDistribution.first['cantidad'] ?? 0) == 0) {
      return SizedBox(
        height: 260,
        child: _buildEmptyState(
          icon: Icons.pie_chart_outline,
          title: 'Sin datos',
          description: 'Aún no hay productos clasificados por categoría.',
        ),
      );
    }

    final totalProductos = _categoryDistribution.fold<int>(
      0,
      (sum, e) => sum + ((e['cantidad'] ?? 0) as num).toInt(),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final chart = AspectRatio(
          aspectRatio: 1,
          child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sections: _buildPieSections(),
                    centerSpaceRadius: 56,
                    sectionsSpace: 3,
                    startDegreeOffset: -90,
                    pieTouchData: PieTouchData(
                      touchCallback: (event, response) {
                        setState(() {
                          if (!event.isInterestedForInteractions ||
                              response == null ||
                              response.touchedSection == null) {
                            _pieTouchedIndex = -1;
                            return;
                          }
                          _pieTouchedIndex =
                              response.touchedSection!.touchedSectionIndex;
                        });
                      },
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$totalProductos',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'productos',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 240, child: Center(child: chart)),
            const SizedBox(height: 16),
            _buildCategoryLegend(),
          ],
        );
      },
    );
  }

  List<PieChartSectionData> _buildPieSections() {
    return _categoryDistribution.asMap().entries.map((entry) {
      final index = entry.key;
      final data = entry.value;
      final porcentaje = (data['porcentaje'] ?? 0.0) as double;
      final isTouched = index == _pieTouchedIndex;
      final color = _categoryPalette[index % _categoryPalette.length];

      return PieChartSectionData(
        color: color,
        value: porcentaje,
        title: '${porcentaje.toStringAsFixed(1)}%',
        radius: isTouched ? 72 : 62,
        titleStyle: TextStyle(
          fontSize: isTouched ? 13 : 11,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          shadows: [
            Shadow(color: Colors.black.withOpacity(0.25), blurRadius: 3),
          ],
        ),
        borderSide: BorderSide(
          color: Colors.white.withOpacity(isTouched ? 0.9 : 0.7),
          width: isTouched ? 2.5 : 1.5,
        ),
      );
    }).toList();
  }

  Widget _buildCategoryLegend() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: _categoryDistribution.asMap().entries.map((entry) {
          final index = entry.key;
          final data = entry.value;
          final color = _categoryPalette[index % _categoryPalette.length];
          final cantidad = data['cantidad'] ?? 0;
          final porcentaje = (data['porcentaje'] ?? 0.0) as double;
          final categoria = data['categoria'] ?? 'Sin categoría';
          final isHighlighted = index == _pieTouchedIndex;

          return MouseRegion(
            onEnter: (_) => setState(() => _pieTouchedIndex = index),
            onExit: (_) => setState(() => _pieTouchedIndex = -1),
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isHighlighted
                    ? color.withOpacity(0.08)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isHighlighted
                      ? color.withOpacity(0.3)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      categoria,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '$cantidad',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${porcentaje.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
    );
  }

  // =====================================================
  // ANÁLISIS (BCG) TAB
  // =====================================================
  Widget _buildBCGTab() {
    return RefreshIndicator(
      onRefresh: _refreshData,
      color: AppColors.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kMaxContentWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPageHeader(
                  icon: Icons.analytics_outlined,
                  title: 'Análisis Estratégico',
                  subtitle:
                      'Matriz BCG para entender el portafolio de productos',
                  accentColor: AppColors.info,
                ),
                const SizedBox(height: 20),
                _buildBCGLegend(),
                const SizedBox(height: 20),
                _buildSectionCard(
                  title: 'Matriz BCG',
                  subtitle:
                      'Clasificación por participación de mercado y crecimiento',
                  icon: Icons.grid_view_outlined,
                  iconColor: AppColors.primary,
                  padding: const EdgeInsets.all(12),
                  child: _buildChartWithErrorBoundary(
                    () => ProductsBCGChart(
                      bcgData: _bcgAnalysis,
                      isLoading: _isLoadingCharts,
                    ),
                    'Matriz BCG',
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBCGLegend() {
    final quadrants = [
      _BCGQuadrant(
        label: 'Estrellas',
        description: 'Alto crecimiento, alta participación',
        icon: Icons.star_rounded,
        color: AppColors.warning,
      ),
      _BCGQuadrant(
        label: 'Vacas Lecheras',
        description: 'Bajo crecimiento, alta participación',
        icon: Icons.savings_outlined,
        color: AppColors.success,
      ),
      _BCGQuadrant(
        label: 'Interrogantes',
        description: 'Alto crecimiento, baja participación',
        icon: Icons.help_outline,
        color: AppColors.info,
      ),
      _BCGQuadrant(
        label: 'Perros',
        description: 'Bajo crecimiento, baja participación',
        icon: Icons.trending_down,
        color: AppColors.textSecondary,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 900;
        final crossAxisCount = isWide ? 4 : 2;
        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: isWide ? 2.6 : 2.4,
          children: quadrants.map((q) => _buildBCGQuadrantCard(q)).toList(),
        );
      },
    );
  }

  Widget _buildBCGQuadrantCard(_BCGQuadrant q) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: q.color.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: q.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(q.icon, color: q.color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  q.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: q.color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  q.description,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartWithErrorBoundary(
    Widget Function() builder,
    String chartName,
  ) {
    try {
      return builder();
    } catch (e) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.error.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.error.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(Icons.error_outline, color: AppColors.error, size: 48),
            const SizedBox(height: 12),
            Text(
              'Error al cargar $chartName',
              style: const TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Por favor, intenta recargar la página',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }
  }

  // =====================================================
  // ALERTAS TAB
  // =====================================================
  Widget _buildAlertasTab() {
    return RefreshIndicator(
      onRefresh: _refreshData,
      color: AppColors.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kMaxContentWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPageHeader(
                  icon: Icons.warning_amber_outlined,
                  title: 'Centro de Alertas',
                  subtitle:
                      'Monitorea los productos que requieren tu atención inmediata',
                  accentColor: AppColors.warning,
                ),
                const SizedBox(height: 20),
                _buildAlertsStats(),
                const SizedBox(height: 20),
                _buildSectionCard(
                  title: 'Alertas Activas',
                  subtitle:
                      _isLoadingAlerts ? 'Cargando...' : '${_alerts.length} alertas registradas',
                  icon: Icons.notifications_active_outlined,
                  iconColor: AppColors.warning,
                  child: _buildAlertsList(),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAlertsStats() {
    final high = _alerts.where((a) => a['prioridad'] == 'alta').length;
    final medium = _alerts.where((a) => a['prioridad'] == 'media').length;
    final low = _alerts.where((a) => a['prioridad'] == 'baja').length;

    final stats = [
      _AlertStat('Alta', high, AppColors.error, Icons.error_outline),
      _AlertStat('Media', medium, AppColors.warning, Icons.warning_amber_outlined),
      _AlertStat('Baja', low, AppColors.info, Icons.info_outline),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          children: stats.asMap().entries.map((entry) {
            final isLast = entry.key == stats.length - 1;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: isLast ? 0 : 12),
                child: _buildAlertStatCard(entry.value),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildAlertStatCard(_AlertStat stat) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: stat.color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: stat.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(stat.icon, color: stat.color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Prioridad ${stat.label}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${stat.count}',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: stat.color,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertsList() {
    if (_isLoadingAlerts) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    if (_alerts.isEmpty || _alerts.first['tipoAlerta'] == 'info') {
      return _buildEmptyState(
        icon: Icons.check_circle_outline,
        title: 'Todo en orden',
        description: 'No hay alertas pendientes. Los productos están en buen estado.',
        color: AppColors.success,
      );
    }

    return Column(
      children: _alerts
          .map((alert) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildAlertItem(alert),
              ))
          .toList(),
    );
  }

  Widget _buildAlertItem(Map<String, dynamic> alert) {
    Color alertColor = AppColors.warning;
    IconData alertIcon = Icons.warning_amber_outlined;

    switch (alert['prioridad']) {
      case 'alta':
        alertColor = AppColors.error;
        alertIcon = Icons.error_outline;
        break;
      case 'media':
        alertColor = AppColors.warning;
        alertIcon = Icons.warning_amber_outlined;
        break;
      case 'baja':
        alertColor = AppColors.info;
        alertIcon = Icons.info_outline;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: alertColor.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: alertColor.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: alertColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(alertIcon, color: alertColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert['denominacion'] ?? 'Producto',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  alert['descripcionAlerta'] ?? 'Alerta general',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: alertColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              (alert['prioridad'] ?? 'media').toString().toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: alertColor,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // ESTRATEGIA TAB
  // =====================================================
  Widget _buildEstrategiaTab() {
    return RefreshIndicator(
      onRefresh: _refreshData,
      color: AppColors.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kMaxContentWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPageHeader(
                  icon: Icons.lightbulb_outline,
                  title: 'Estrategia',
                  subtitle:
                      'Acciones y recomendaciones para optimizar tu catálogo',
                  accentColor: AppColors.warning,
                ),
                const SizedBox(height: 20),
                _buildSectionCard(
                  title: 'Recomendaciones Estratégicas',
                  subtitle: 'Sugerencias inteligentes basadas en datos',
                  icon: Icons.auto_awesome_outlined,
                  iconColor: AppColors.warning,
                  child: _buildRecommendationsContent(),
                ),
                const SizedBox(height: 20),
                _buildSectionCard(
                  title: 'Acciones Rápidas',
                  subtitle: 'Tareas clave para la gestión de productos',
                  icon: Icons.rocket_launch_outlined,
                  iconColor: AppColors.primary,
                  child: _buildStrategicActionsContent(),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecommendationsContent() {
    return _buildEmptyState(
      icon: Icons.tips_and_updates_outlined,
      title: 'Próximamente',
      description:
          'Sistema de recomendaciones inteligentes en desarrollo. Muy pronto dispondrás de insights automáticos.',
      color: AppColors.warning,
    );
  }

  Widget _buildStrategicActionsContent() {
    return Column(
      children: [
        _buildActionButton(
          'Ver Lista Completa',
          'Acceder a la gestión de productos',
          Icons.list_alt_outlined,
          AppColors.primary,
          () => NavigationGuard.navigateWithPermission(context, '/products'),
        ),
        const SizedBox(height: 12),
        _buildActionButton(
          'Agregar Producto',
          'Crear un nuevo producto en el catálogo',
          Icons.add_circle_outline,
          AppColors.success,
          () => NavigationGuard.navigateWithPermission(
              context, '/add-product'),
        ),
      ],
    );
  }

  Widget _buildActionButton(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            color: color.withOpacity(0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, color: color, size: 14),
            ],
          ),
        ),
      ),
    );
  }

  // =====================================================
  // EMPTY STATE (reusable)
  // =====================================================
  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String description,
    Color? color,
  }) {
    final c = color ?? AppColors.textSecondary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: c.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, color: c, size: 32),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================
// MODELS internos
// =====================================================
class _BCGQuadrant {
  final String label;
  final String description;
  final IconData icon;
  final Color color;

  _BCGQuadrant({
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
  });
}

class _AlertStat {
  final String label;
  final int count;
  final Color color;
  final IconData icon;

  _AlertStat(this.label, this.count, this.color, this.icon);
}

class _TabLabel extends StatelessWidget {
  final IconData icon;
  final String text;

  const _TabLabel({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Text(text),
      ],
    );
  }
}

class _CompactKpi {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final double? percentage;

  _CompactKpi({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.percentage,
  });
}

class _QuickActionData {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  _QuickActionData({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}

// =====================================================
// ProductsAdditionalInfo (rediseñado)
// =====================================================
class ProductsAdditionalInfo extends StatelessWidget {
  final Map<String, dynamic> kpis;
  final bool isLoading;

  const ProductsAdditionalInfo({
    Key? key,
    required this.kpis,
    required this.isLoading,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    final productosSinStock = kpis['productosSinStock'] ?? 0;
    final productosNoElaborados = kpis['productosNoElaborados'] ?? 0;
    final diasSinMovimiento = kpis['diasSinMovimiento'] ?? 15;
    final valorPromedio = kpis['valorPromedioPorProducto'] ?? 0.0;
    final alertas = kpis['alertas'] as List? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoRow(
          context,
          'Productos sin stock',
          '$productosSinStock productos',
          productosSinStock > 0 ? AppColors.error : AppColors.success,
          icon: Icons.inventory_2_outlined,
        ),
        const SizedBox(height: 10),
        _buildInfoRow(
          context,
          'Productos no elaborados',
          '$productosNoElaborados productos',
          AppColors.info,
          icon: Icons.construction_outlined,
        ),
        const SizedBox(height: 10),
        _buildInfoRow(
          context,
          'Valor promedio por producto',
          'CUP \$${NumberFormatter.formatCurrency(valorPromedio)}',
          AppColors.success,
          icon: Icons.attach_money_outlined,
        ),
        const SizedBox(height: 10),
        _buildInfoRow(
          context,
          'Período sin movimiento',
          '$diasSinMovimiento días',
          AppColors.warning,
          icon: Icons.schedule_outlined,
        ),
        if (alertas.isNotEmpty) ...[
          const SizedBox(height: 18),
          Container(height: 1, color: AppColors.border),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.warning_amber_outlined,
                  color: AppColors.warning, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Alertas del Sistema',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...alertas.map((alerta) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildAlertRow(context, alerta),
              )),
        ],
      ],
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value,
    Color color, {
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertRow(BuildContext context, Map<String, dynamic> alerta) {
    final mensaje = alerta['mensaje'] ?? '';
    final nivel = alerta['nivel'] ?? 'baja';

    Color alertColor;
    IconData alertIcon;

    switch (nivel) {
      case 'alta':
        alertColor = AppColors.error;
        alertIcon = Icons.error_outline;
        break;
      case 'media':
        alertColor = AppColors.warning;
        alertIcon = Icons.warning_amber_outlined;
        break;
      default:
        alertColor = AppColors.info;
        alertIcon = Icons.info_outline;
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: alertColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: alertColor.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(alertIcon, color: alertColor, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              mensaje,
              style: TextStyle(
                fontSize: 12,
                color: alertColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
