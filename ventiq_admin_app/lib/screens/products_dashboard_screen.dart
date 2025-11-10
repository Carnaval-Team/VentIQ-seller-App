import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/products_analytics_service.dart';
import '../services/permissions_service.dart';
import '../widgets/products_kpi_cards.dart';
import '../widgets/products_charts_widget.dart';
import '../widgets/admin_bottom_navigation.dart';
import '../widgets/admin_drawer.dart';
import '../utils/number_formatter.dart';
import '../utils/navigation_guard.dart';

class ProductsDashboardScreen extends StatefulWidget {
  const ProductsDashboardScreen({super.key});

  @override
  State<ProductsDashboardScreen> createState() =>
      _ProductsDashboardScreenState();
}

class _ProductsDashboardScreenState extends State<ProductsDashboardScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;

  // Estados de carga
  bool _isLoadingKPIs = true;
  bool _isLoadingCharts = true;
  bool _isLoadingAlerts = true;

  // Permisos
  final PermissionsService _permissionsService = PermissionsService();
  bool _canCreateProduct = false;

  // Datos del dashboard
  Map<String, dynamic> _kpis = {};
  List<Map<String, dynamic>> _categoryDistribution = [];
  List<Map<String, dynamic>> _stockTrends = [];
  Map<String, dynamic> _abcAnalysis = {};
  List<Map<String, dynamic>> _topProducts = [];
  List<Map<String, dynamic>> _alerts = [];
  Map<String, dynamic> _bcgAnalysis = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _checkPermissions();
    _loadDashboardData();
  }

  void _checkPermissions() async {
    print('🔐 Verificando permisos en dashboard de productos...');
    final canCreate = await _permissionsService.canPerformAction(
      'product.create',
    );
    setState(() {
      _canCreateProduct = canCreate;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    print('📊 Iniciando carga de datos del dashboard de productos...');

    await Future.wait([_loadKPIs(), _loadChartsData(), _loadAlertsData()]);

    print('✅ Datos del dashboard cargados completamente');
  }

  Future<void> _loadKPIs() async {
    try {
      setState(() => _isLoadingKPIs = true);
      print('🔄 Iniciando carga de KPIs...');

      final kpis = await ProductsAnalyticsService.getProductsKPIs();
      print('📊 KPIs obtenidos: $kpis');

      if (mounted) {
        setState(() {
          _kpis = kpis;
          _isLoadingKPIs = false;
        });
        print('✅ KPIs actualizados en UI');
      }
    } catch (e) {
      print('❌ Error cargando KPIs: $e');
      if (mounted) setState(() => _isLoadingKPIs = false);
    }
  }

  Future<void> _loadChartsData() async {
    setState(() => _isLoadingCharts = true);

    try {
      // Cargar cada dato de forma independiente para que un error no afecte a los demás
      final categoryFuture = ProductsAnalyticsService.getCategoryDistribution()
          .catchError((e) {
            print('❌ Error cargando distribución de categorías: $e');
            return <Map<String, dynamic>>[];
          });

      final trendsFuture = ProductsAnalyticsService.getStockTrends(
        days: 7,
      ).catchError((e) {
        print('❌ Error cargando tendencias de stock: $e');
        return <Map<String, dynamic>>[];
      });

      final abcFuture = ProductsAnalyticsService.getABCAnalysis().catchError((
        e,
      ) {
        print('❌ Error cargando análisis ABC: $e');
        return <String, dynamic>{};
      });

      final topProductsFuture =
          ProductsAnalyticsService.getTopPerformingProducts(
            limit: 10,
          ).catchError((e) {
            print('❌ Error cargando productos top: $e');
            return <Map<String, dynamic>>[];
          });

      final bcgFuture = ProductsAnalyticsService.getBCGAnalysis().catchError((
        e,
      ) {
        print('❌ Error cargando análisis BCG: $e');
        return <String, dynamic>{
          'productos': [],
          'resumen': {
            'total_productos': 0,
            'estrellas': 0,
            'vacas_lecheras': 0,
            'interrogantes': 0,
            'perros': 0,
          },
          'umbrales': {},
        };
      });

      // Esperar a que todas terminen (incluso si algunas fallan)
      final results = await Future.wait([
        categoryFuture,
        trendsFuture,
        abcFuture,
        topProductsFuture,
        bcgFuture,
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
        print(
          '✅ Datos de gráficos cargados (algunos pueden tener valores por defecto)',
        );
      }
    } catch (e) {
      print('❌ Error crítico cargando datos de gráficos: $e');
      if (mounted) {
        setState(() {
          _isLoadingCharts = false;
          // Asegurar que todas las variables tengan valores por defecto
          _categoryDistribution =
              _categoryDistribution.isEmpty ? [] : _categoryDistribution;
          _stockTrends = _stockTrends.isEmpty ? [] : _stockTrends;
          _abcAnalysis = _abcAnalysis.isEmpty ? {} : _abcAnalysis;
          _topProducts = _topProducts.isEmpty ? [] : _topProducts;
          _bcgAnalysis =
              _bcgAnalysis.isEmpty
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
      print('❌ Error cargando alertas: $e');
      if (mounted) setState(() => _isLoadingAlerts = false);
    }
  }

  Future<void> _refreshData() async {
    await _loadDashboardData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dashboard actualizado'),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
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
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard, size: 20), text: 'Resumen'),
            Tab(
              icon: Icon(Icons.analytics, size: 20),
              text: 'Análisis',
            ), // Renombrado de BCG
            Tab(icon: Icon(Icons.warning, size: 20), text: 'Alertas'),
            Tab(icon: Icon(Icons.lightbulb, size: 20), text: 'Estrategia'),
          ],
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          labelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildResumenTab(),
          _buildBCGTab(),
          _buildAlertasTab(),
          _buildEstrategiaTab(),
        ],
      ),
      endDrawer: const AdminDrawer(),
      bottomNavigationBar: AdminBottomNavigation(
        currentRoute: '/products-dashboard',
        onTap: _onBottomNavTap,
      ),
      floatingActionButton:
          _tabController.index == 0 && _canCreateProduct
              ? FloatingActionButton.extended(
                onPressed: () => NavigationGuard.navigateWithPermission(context, '/add-product'),
                backgroundColor: AppColors.primary,
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text(
                  'Nuevo',
                  style: TextStyle(color: Colors.white),
                ),
              )
              : null,
    );
  }

  Widget _buildResumenTab() {
    return RefreshIndicator(
      onRefresh: _refreshData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProductsKPICards(kpis: _kpis, isLoading: _isLoadingKPIs),
            const SizedBox(height: 20),

            // Acciones Rápidas
            ProductsQuickActions(
              onAddProduct:
                  _canCreateProduct
                      ? () => NavigationGuard.navigateWithPermission(context, '/add-product')
                      : null,
              onViewAll: () => NavigationGuard.navigateWithPermission(context, '/products'),
              onViewAlerts:
                  () => _tabController.animateTo(2), // Cambiar de 2 a 3
              onViewReports: () => _tabController.animateTo(1), // Mantener en 1
            ),
            const SizedBox(height: 20),

            // Información adicional
            ProductsAdditionalInfo(kpis: _kpis, isLoading: _isLoadingKPIs),
            const SizedBox(height: 20),
            ProductsCategoryChart(
              categoryData: _categoryDistribution,
              isLoading: _isLoadingCharts,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBCGTab() {
    return RefreshIndicator(
      onRefresh: _refreshData,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              // Información sobre el análisis BCG
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[700]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Matriz BCG - Análisis de Portafolio de Productos',
                        style: TextStyle(
                          color: Colors.blue[900],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Matriz BCG con error boundary
              _buildChartWithErrorBoundary(
                () => ProductsBCGChart(
                  bcgData: _bcgAnalysis,
                  isLoading: _isLoadingCharts,
                ),
                'Matriz BCG',
              ),
            ],
          ),
        ),
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
      print('❌ Error renderizando $chartName: $e');
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red[200]!),
        ),
        child: Column(
          children: [
            Icon(Icons.error_outline, color: Colors.red[700], size: 48),
            const SizedBox(height: 8),
            Text(
              'Error al cargar $chartName',
              style: TextStyle(
                color: Colors.red[700],
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Por favor, intenta recargar la página',
              style: TextStyle(color: Colors.red[600], fontSize: 12),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildAlertasTab() {
    return RefreshIndicator(
      onRefresh: _refreshData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [_buildAlertsCard()]),
      ),
    );
  }

  Widget _buildEstrategiaTab() {
    return RefreshIndicator(
      onRefresh: _refreshData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildRecommendationsCard(),
            const SizedBox(height: 20),
            _buildStrategicActionsCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopProductsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.star, color: AppColors.warning, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Top 5 Productos',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => _tabController.animateTo(1),
                child: const Text('Ver todos'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isLoadingCharts)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (_topProducts.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'No hay datos de productos disponibles',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            Column(
              children:
                  _topProducts.take(5).map((product) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.inventory_2,
                              color: AppColors.primary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  product['denominacion'] ?? 'Producto',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'SKU: ${product['sku'] ?? 'N/A'}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${product['movimientos'] ?? 0} mov.',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.success,
                                ),
                              ),
                              Text(
                                'Stock: ${product['stockActual'] ?? 0}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildAlertsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning, color: AppColors.warning, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Alertas de Productos',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isLoadingAlerts)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (_alerts.isEmpty || _alerts.first['tipoAlerta'] == 'info')
            Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.check_circle, size: 48, color: AppColors.success),
                  const SizedBox(height: 12),
                  const Text(
                    'No hay alertas pendientes',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Todos los productos están en buen estado',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                ],
              ),
            )
          else
            Column(
              children: _alerts.map((alert) => _buildAlertItem(alert)).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildAlertItem(Map<String, dynamic> alert) {
    Color alertColor = AppColors.warning;
    IconData alertIcon = Icons.warning;

    switch (alert['prioridad']) {
      case 'alta':
        alertColor = AppColors.error;
        alertIcon = Icons.error;
        break;
      case 'media':
        alertColor = AppColors.warning;
        alertIcon = Icons.warning;
        break;
      case 'baja':
        alertColor = AppColors.info;
        alertIcon = Icons.info;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: alertColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: alertColor.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(alertIcon, color: alertColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert['denominacion'] ?? 'Producto',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  alert['descripcionAlerta'] ?? 'Alerta general',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: alertColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              alert['prioridad']?.toUpperCase() ?? 'MEDIA',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: alertColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb, color: AppColors.warning, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Recomendaciones Estratégicas',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  size: 48,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Próximamente',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sistema de recomendaciones inteligentes en desarrollo',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStrategicActionsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.rocket_launch, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Acciones Estratégicas',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildActionButton(
            'Ver Lista Completa',
            'Acceder a la gestión de productos',
            Icons.list,
            AppColors.primary,
            () => NavigationGuard.navigateWithPermission(context, '/products'),
          ),
          const SizedBox(height: 12),
          _buildActionButton(
            'Agregar Producto',
            'Crear un nuevo producto',
            Icons.add,
            AppColors.success,
            () => NavigationGuard.navigateWithPermission(context, '/add-product'),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: color, size: 16),
          ],
        ),
      ),
    );
  }

  void _onBottomNavTap(int index) {
    // El AdminBottomNavigation ya maneja la navegación automáticamente
    // Esta función se mantiene por compatibilidad pero no es necesaria
    // ya que AdminBottomNavigation usa _handleTap internamente
  }
}

// Agregar este widget en products_dashboard_screen.dart

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
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final productosSinStock = kpis['productosSinStock'] ?? 0;
    final productosNoElaborados = kpis['productosNoElaborados'] ?? 0;
    final diasSinMovimiento = kpis['diasSinMovimiento'] ?? 15;
    final valorPromedio = kpis['valorPromedioPorProducto'] ?? 0.0;
    final alertas = kpis['alertas'] as List? ?? [];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[600]),
                const SizedBox(width: 8),
                Expanded(
                  // Esto hace que el texto se ajuste al espacio disponible
                  child: Text(
                    'Información Adicional del Inventario',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[600],
                    ),
                    maxLines:
                        2, // Permite que se divida en 2 líneas si es necesario
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Información en filas
            _buildInfoRow(
              context,
              'Productos sin stock:',
              '$productosSinStock productos',
              productosSinStock > 0 ? Colors.red : Colors.green,
            ),
            const SizedBox(height: 8),

            _buildInfoRow(
              context,
              'Productos no elaborados:',
              '$productosNoElaborados productos',
              Colors.blue,
            ),
            const SizedBox(height: 8),

            _buildInfoRow(
              context,
              'Valor promedio por producto:',
              'CUP \$${NumberFormatter.formatCurrency(valorPromedio)}',
              Colors.green,
            ),
            const SizedBox(height: 8),

            _buildInfoRow(
              context,
              'Período sin movimiento:',
              '$diasSinMovimiento días',
              Colors.orange,
            ),

            // Alertas si existen
            if (alertas.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.orange[600]),
                  const SizedBox(width: 8),
                  Text(
                    'Alertas del Sistema',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange[600],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...alertas.map((alerta) => _buildAlertRow(context, alerta)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value,
    Color color,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAlertRow(BuildContext context, Map<String, dynamic> alerta) {
    final tipo = alerta['tipo'] ?? '';
    final mensaje = alerta['mensaje'] ?? '';
    final nivel = alerta['nivel'] ?? 'baja';

    Color alertColor;
    IconData alertIcon;

    switch (nivel) {
      case 'alta':
        alertColor = Colors.red;
        alertIcon = Icons.error;
        break;
      case 'media':
        alertColor = Colors.orange;
        alertIcon = Icons.warning;
        break;
      default:
        alertColor = Colors.blue;
        alertIcon = Icons.info;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: alertColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: alertColor.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(alertIcon, color: alertColor, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                mensaje,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: alertColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
