import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/admin_bottom_navigation.dart';
import 'inventory_reception_screen.dart';
import 'inventory_reception_web_screen.dart';
import 'inventory_operations_web_screen.dart';
import 'inventory_warehouse_web_screen.dart';
import 'warehouse_web_screen.dart';
import 'inventory_stock_web_screen.dart';
import 'inventory_transfer_screen.dart';
import 'inventory_extraction_screen.dart';
import 'inventory_adjustment_screen.dart';
import 'inventory_adjustment_web_screen.dart';
import 'elaborated_products_extraction_screen.dart';
import 'inventory_extractionbysale_screen.dart';
import 'inventory_dashboard.dart';
import 'inventory_dashboard_web.dart';
import '../utils/platform_utils.dart';
import 'consignacion_screen.dart';
import 'inventory_ipv_report_screen.dart';
import '../widgets/notification_widget.dart';
import '../widgets/inventory_export_dialog_web.dart';
import '../services/permissions_service.dart';

class InventoryWebScreen extends StatefulWidget {
  const InventoryWebScreen({super.key});

  @override
  State<InventoryWebScreen> createState() => _InventoryWebScreenState();
}

class _InventoryWebScreenState extends State<InventoryWebScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  String _errorMessage = '';
  final PermissionsService _permissionsService = PermissionsService();
  bool _canCreateInventoryOperations = false;
  bool _canCreateReception = false;
  bool _canCreateTransfer = false;
  bool _canCreateAdjustment = false;
  bool _canCreateExtraction = false;
  bool _isAlmacenero = false;
  int? _assignedWarehouseId;

  static const double _kMaxContentWidth = 1400;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    _checkUserRole();
    _checkPermissions();
    _loadInitialData();
  }

  Future<void> _checkUserRole() async {
    final role = await _permissionsService.getUserRole();
    final isAlmacenero = role == UserRole.almacenero;

    if (isAlmacenero) {
      final warehouseId = await _permissionsService.getAssignedWarehouse();
      if (mounted) {
        setState(() {
          _isAlmacenero = isAlmacenero;
          _assignedWarehouseId = warehouseId;
        });
      }
    }
  }

  Future<void> _checkPermissions() async {
    final permissions = await Future.wait([
      _permissionsService.canPerformAction('inventory.create_reception'),
      _permissionsService.canPerformAction('inventory.create_transfer'),
      _permissionsService.canPerformAction('inventory.create_adjustment'),
      _permissionsService.canPerformAction('inventory.create_extraction'),
    ]);

    final canCreate = permissions.any((p) => p);
    if (!mounted) return;
    setState(() {
      _canCreateInventoryOperations = canCreate;
      _canCreateReception = permissions[0];
      _canCreateTransfer = permissions[1];
      _canCreateAdjustment = permissions[2];
      _canCreateExtraction = permissions[3];
    });
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    setState(() {});
  }

  void _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      await Future.delayed(const Duration(milliseconds: 500));
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error al cargar datos iniciales: $e';
      });
    }
  }

  // =====================================================
  // FAB OPTIONS DIALOG (responsive, web-friendly)
  // =====================================================
  void _showFabOptions() {
    showDialog(
      context: context,
      builder: (context) {
        final screenW = MediaQuery.of(context).size.width;
        final dialogW = screenW < 600 ? screenW * 0.94 : 760.0;
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: dialogW,
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 16, 16),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.inventory_rounded,
                          color: AppColors.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Text(
                          'Opciones de inventario',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                        color: AppColors.textSecondary,
                        tooltip: 'Cerrar',
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.border),
                Flexible(
                  child: SingleChildScrollView(
                    padding:
                        const EdgeInsets.fromLTRB(20, 18, 20, 18),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 600;
                        final colCount = isWide ? 2 : 1;
                        final spacing = 10.0;
                        final itemWidth = (constraints.maxWidth -
                                spacing * (colCount - 1)) /
                            colCount;
                        final options = _buildOptionList();
                        return Wrap(
                          spacing: spacing,
                          runSpacing: spacing,
                          children: options
                              .map(
                                (o) => SizedBox(
                                  width: itemWidth,
                                  child: _menuOptionTile(o),
                                ),
                              )
                              .toList(),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<_InventoryOption> _buildOptionList() {
    final options = <_InventoryOption>[];
    if (_canCreateReception) {
      options.add(_InventoryOption(
        icon: Icons.input_rounded,
        title: 'Recepción de Productos',
        subtitle: 'Registrar entrada de mercancía',
        color: const Color(0xFF10B981),
        onTap: _navigateToReception,
      ));
    }
    if (_canCreateTransfer) {
      options.add(_InventoryOption(
        icon: Icons.swap_horiz_rounded,
        title: 'Transferencia entre Almacenes',
        subtitle: 'Mover productos entre ubicaciones',
        color: const Color(0xFF4A90E2),
        onTap: _navigateToTransfer,
      ));
    }
    if (_canCreateAdjustment) {
      options.add(_InventoryOption(
        icon: Icons.trending_up_rounded,
        title: 'Ajuste por Exceso',
        subtitle: 'Reducir inventario por sobrante',
        color: const Color(0xFFFF6B35),
        onTap: _navigateToExcessAdjustment,
      ));
      options.add(_InventoryOption(
        icon: Icons.trending_down_rounded,
        title: 'Ajuste por Faltante',
        subtitle: 'Aumentar inventario por faltante',
        color: const Color(0xFFFF8C42),
        onTap: _navigateToShortageAdjustment,
      ));
    }
    if (_canCreateExtraction) {
      options.add(_InventoryOption(
        icon: Icons.output_rounded,
        title: 'Extracción de Productos',
        subtitle: 'Registrar salida de mercancía',
        color: const Color(0xFFEF4444),
        onTap: _navigateToExtraction,
      ));
      options.add(_InventoryOption(
        icon: Icons.outbox_rounded,
        title: 'Productos Elaborados',
        subtitle: 'Salida de productos elaborados',
        color: const Color(0xFFEF4444),
        onTap: _navigateToElaboratedProductsExtraction,
      ));
      options.add(_InventoryOption(
        icon: Icons.point_of_sale_rounded,
        title: 'Venta por Acuerdo',
        subtitle: 'Venta directa con precio personalizado',
        color: const Color(0xFF10B981),
        onTap: _navigateToSaleByAgreement,
      ));
    }
    if (_canCreateTransfer) {
      options.add(_InventoryOption(
        icon: Icons.handshake_rounded,
        title: 'Consignación',
        subtitle: 'Asignar productos a otra tienda',
        color: const Color(0xFF9333EA),
        onTap: _navigateToConsignacion,
      ));
    }
    options.add(_InventoryOption(
      icon: Icons.assessment_rounded,
      title: 'Consultar IPV',
      subtitle: 'Reporte de inventario, precios y ventas',
      color: const Color(0xFF06B6D4),
      onTap: _navigateToIPVReport,
    ));
    options.add(_InventoryOption(
      icon: Icons.filter_list_rounded,
      title: 'Filtro de Búsqueda',
      subtitle: 'Filtrar y buscar productos',
      color: const Color(0xFF8B5CF6),
      onTap: _showSearchFilter,
    ));
    return options;
  }

  Widget _menuOptionTile(_InventoryOption o) {
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        o.onTap();
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant.withOpacity(0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: o.color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(o.icon, color: o.color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    o.title,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      letterSpacing: 0.1,
                      height: 1.25,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    o.subtitle,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textLight,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // NAVIGATION
  // =====================================================
  void _navigateToReception() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlatformUtils.isWeb
            ? const InventoryReceptionWebScreen()
            : const InventoryReceptionScreen(),
      ),
    );
  }

  void _navigateToTransfer() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const InventoryTransferScreen(),
      ),
    );
  }

  void _navigateToExtraction() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const InventoryExtractionScreen(),
      ),
    );
  }

  void _navigateToElaboratedProductsExtraction() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ElaboratedProductsExtractionScreen(),
      ),
    );
  }

  void _navigateToSaleByAgreement() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const InventoryExtractionBySaleScreen(),
      ),
    );
  }

  void _navigateToConsignacion() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ConsignacionScreen()),
    );
  }

  void _navigateToIPVReport() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const InventoryIPVReportScreen(),
      ),
    );
  }

  void _navigateToExcessAdjustment() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlatformUtils.isWeb
            ? const InventoryAdjustmentWebScreen(
                operationType: 4,
                adjustmentType: 'excess',
              )
            : const InventoryAdjustmentScreen(
                operationType: 4,
                adjustmentType: 'excess',
              ),
      ),
    );
  }

  void _navigateToWarehouseManagement() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const WarehouseWebScreen(),
      ),
    );
  }

  void _navigateToShortageAdjustment() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlatformUtils.isWeb
            ? const InventoryAdjustmentWebScreen(
                operationType: 3,
                adjustmentType: 'shortage',
              )
            : const InventoryAdjustmentScreen(
                operationType: 3,
                adjustmentType: 'shortage',
              ),
      ),
    );
  }

  void _showSearchFilter() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        title: const Text('Filtro de Búsqueda'),
        content: const Text(
          'La funcionalidad de filtro avanzado estará disponible próximamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Widget? _buildFloatingActionButton() {
    final showOperations = _canCreateInventoryOperations;
    final isStockTab = _tabController.index == 1;
    final isWarehouseTab = _tabController.index == 3;

    if (!showOperations && !isStockTab && !isWarehouseTab) {
      return null;
    }

    final children = <Widget>[];

    if (isStockTab) {
      children.add(
        _CompactActionButton(
          heroTag: 'inv_export_fab',
          icon: Icons.file_download_outlined,
          label: 'Exportar',
          tooltip: 'Exportar inventario',
          backgroundColor: const Color(0xFF10B981),
          onPressed: () => showInventoryExportDialogWeb(context),
        ),
      );
    }

    if (isWarehouseTab) {
      children.add(
        _CompactActionButton(
          heroTag: 'inv_manage_warehouse_fab',
          icon: Icons.settings_rounded,
          label: 'Gestionar',
          tooltip: 'Gestionar almacenes',
          backgroundColor: AppColors.primary,
          onPressed: _navigateToWarehouseManagement,
        ),
      );
    } else if (showOperations) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 10));
      children.add(
        _CompactActionButton(
          heroTag: 'inv_operations_fab',
          icon: Icons.add_rounded,
          label: 'Operaciones',
          tooltip: 'Opciones de inventario',
          backgroundColor: AppColors.primary,
          onPressed: _showFabOptions,
        ),
      );
    }

    if (children.isEmpty) return null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: children,
    );
  }

  // =====================================================
  // BUILD
  // =====================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Control de Inventario',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 20,
            letterSpacing: 0.2,
          ),
        ),
        centerTitle: true,
        backgroundColor: AppColors.primary,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          const NotificationWidget(),
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => Scaffold.of(context).openEndDrawer(),
              tooltip: 'Menú',
            ),
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: AppColors.primary,
            child: Center(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: _kMaxContentWidth),
                child: _buildTabBar(),
              ),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : _errorMessage.isNotEmpty
              ? _buildErrorState()
              : Center(
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: _kMaxContentWidth),
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        const _PlatformAwareInventoryDashboard(),
                        InventoryStockWebScreen(
                          isAlmacenero: _isAlmacenero,
                          assignedWarehouseId: _assignedWarehouseId,
                        ),
                        const InventoryOperationsWebScreen(),
                        const InventoryWarehouseWebScreen(),
                      ],
                    ),
                  ),
                ),
      floatingActionButton: _buildFloatingActionButton(),
      endDrawer: const AdminDrawer(),
      bottomNavigationBar: AdminBottomNavigation(
        currentRoute: '/inventory',
        onTap: (index) {},
      ),
    );
  }

  Widget _buildTabBar() {
    final tabs = const [
      _TabData('Dashboard', Icons.dashboard_rounded),
      _TabData('Stock', Icons.inventory_2_rounded),
      _TabData('Movimientos', Icons.swap_horiz_rounded),
      _TabData('Almacenes', Icons.warehouse_rounded),
    ];

    return TabBar(
      controller: _tabController,
      isScrollable: false,
      labelColor: Colors.white,
      unselectedLabelColor: Colors.white.withOpacity(0.72),
      labelStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
      unselectedLabelStyle: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      indicatorColor: Colors.white,
      indicatorWeight: 3,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      overlayColor: WidgetStateProperty.resolveWith(
        (states) => Colors.white.withOpacity(0.08),
      ),
      tabs: tabs
          .map(
            (t) => Tab(
              height: 48,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(t.icon, size: 18),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      t.label,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: const Icon(
                    Icons.error_outline_rounded,
                    size: 32,
                    color: AppColors.error,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'No se pudieron cargar los datos',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _errorMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  onPressed: _loadInitialData,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Reintentar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlatformAwareInventoryDashboard extends StatelessWidget {
  const _PlatformAwareInventoryDashboard();

  @override
  Widget build(BuildContext context) {
    final isWeb =
        PlatformUtils.isWeb && MediaQuery.of(context).size.width >= 900;
    return isWeb ? const InventoryDashboardWeb() : const InventoryDashboard();
  }
}

class _TabData {
  final String label;
  final IconData icon;
  const _TabData(this.label, this.icon);
}

class _InventoryOption {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  _InventoryOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
}

class _CompactActionButton extends StatelessWidget {
  final String heroTag;
  final IconData icon;
  final String label;
  final String tooltip;
  final Color backgroundColor;
  final VoidCallback onPressed;

  const _CompactActionButton({
    required this.heroTag,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.backgroundColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: backgroundColor,
        elevation: 3,
        shadowColor: backgroundColor.withOpacity(0.35),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
