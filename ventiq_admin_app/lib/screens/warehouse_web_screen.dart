import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/admin_bottom_navigation.dart';
import '../models/warehouse.dart';
import '../services/user_preferences_service.dart';
import '../services/warehouse_service.dart';
import 'add_warehouse_screen.dart';
import 'add_warehouse_web_screen.dart';
import '../utils/platform_utils.dart';
import 'warehouse_detail_screen.dart';
import 'warehouse_detail_web_screen.dart';
import '../utils/navigation_guard.dart';

class WarehouseWebScreen extends StatefulWidget {
  const WarehouseWebScreen({super.key});

  @override
  State<WarehouseWebScreen> createState() => _WarehouseWebScreenState();
}

class _WarehouseWebScreenState extends State<WarehouseWebScreen> {
  final _service = WarehouseService();
  final _prefsService = UserPreferencesService();
  List<Warehouse> _warehouses = [];
  String _search = '';
  String _direccionFilter = '';
  bool _loading = true;
  DateTime? _lastSearchAt;

  bool _canCreateWarehouse = false;
  bool _canEditWarehouse = false;

  WarehousePagination? _pagination;
  int _currentPage = 1;
  final int _itemsPerPage = 10;
  bool _loadingMore = false;

  static const double _kMaxContentWidth = 1400;

  @override
  void initState() {
    super.initState();
    _loadPermissions();
    _loadData();
  }

  Future<void> _loadPermissions() async {
    final permissions = await Future.wait([
      NavigationGuard.canPerformAction('warehouse.create'),
      NavigationGuard.canPerformAction('warehouse.edit'),
    ]);

    if (!mounted) return;
    setState(() {
      _canCreateWarehouse = permissions[0];
      _canEditWarehouse = permissions[1];
    });
  }

  Future<void> _loadData({bool isRefresh = true}) async {
    if (isRefresh) {
      setState(() {
        _loading = true;
        _currentPage = 1;
      });
    } else {
      setState(() => _loadingMore = true);
    }

    try {
      final selectedStoreId = await _prefsService.getIdTienda();
      if (selectedStoreId == null) {
        setState(() {
          if (isRefresh) {
            _warehouses = [];
            _currentPage = 1;
          }
          _pagination = null;
          _loading = false;
          _loadingMore = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Selecciona una tienda en el dashboard'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      await _service.listStores();

      final response = await _service.listWarehousesWithPagination(
        denominacionFilter: _search.isNotEmpty ? _search : null,
        direccionFilter: _direccionFilter.isNotEmpty ? _direccionFilter : null,
        tiendaFilter: selectedStoreId,
        pagina: isRefresh ? 1 : _currentPage,
        porPagina: _itemsPerPage,
      );

      setState(() {
        if (isRefresh) {
          _warehouses = response.almacenes;
          _currentPage = 1;
        } else {
          _warehouses.addAll(response.almacenes);
        }

        _pagination = response.paginacion;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      print('❌ Error loading warehouses: $e');
      setState(() {
        _loading = false;
        _loadingMore = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar almacenes: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadMoreData() async {
    if (_pagination != null && _pagination!.tieneSiguiente && !_loadingMore) {
      _currentPage++;
      await _loadData(isRefresh: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Gestión de Almacenes',
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
          IconButton(
            tooltip: 'Refrescar',
            onPressed: () => _loadData(isRefresh: true),
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => Scaffold.of(context).openEndDrawer(),
              tooltip: 'Menú',
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () => _loadData(isRefresh: true),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: _kMaxContentWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildFiltersRow(),
                        const SizedBox(height: 16),
                        _buildStatsRow(),
                        const SizedBox(height: 20),
                        _buildWarehousesCard(),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      endDrawer: const AdminDrawer(),
      bottomNavigationBar: AdminBottomNavigation(
        currentRoute: '/warehouse',
        onTap: _onBottomNavTap,
      ),
    );
  }

  void _onBottomNavTap(int index) {}

  // =====================================================
  // STATS ROW (3 stacks alineados horizontalmente)
  // =====================================================
  Widget _buildStatsRow() {
    final totalWarehouses = _pagination?.totalAlmacenes ?? _warehouses.length;
    final totalLayouts = _warehouses.fold<int>(
      0,
      (sum, w) => sum + w.zones.length,
    );
    // Límites de stock ocultos temporalmente
    // final totalLimits = _warehouses.fold<int>(
    //   0,
    //   (sum, w) => sum + w.limitesStockCount,
    // );

    final stats = [
      _StatData(
        icon: Icons.warehouse_rounded,
        value: '$totalWarehouses',
        label: 'Almacenes',
        color: AppColors.primary,
      ),
      _StatData(
        icon: Icons.layers_rounded,
        value: '$totalLayouts',
        label: 'Layouts / Zonas',
        color: Colors.orange,
      ),
      // Stat de Límites de stock oculto temporalmente
      // _StatData(
      //   icon: Icons.tune_rounded,
      //   value: '$totalLimits',
      //   label: 'Límites de stock',
      //   color: Colors.green,
      // ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;
        if (isWide) {
          return Row(
            children: [
              for (var i = 0; i < stats.length; i++) ...[
                Expanded(child: _statTile(stats[i])),
                if (i < stats.length - 1) const SizedBox(width: 12),
              ],
            ],
          );
        }
        return Column(
          children: [
            for (var i = 0; i < stats.length; i++) ...[
              SizedBox(width: double.infinity, child: _statTile(stats[i])),
              if (i < stats.length - 1) const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }

  Widget _statTile(_StatData s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.025),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: s.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(s.icon, color: s.color, size: 22),
          ),
          const SizedBox(width: 14),
          Text(
            s.value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              s.label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // SECTION CARD reutilizable
  // =====================================================
  Widget _buildSectionCard({
    required String title,
    String? subtitle,
    required IconData icon,
    Color? iconColor,
    required Widget child,
    Widget? action,
    EdgeInsetsGeometry? bodyPadding,
  }) {
    final color = iconColor ?? AppColors.primary;
    return Container(
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
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          letterSpacing: 0.2,
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
          const Divider(height: 1, color: AppColors.border),
          Padding(
            padding: bodyPadding ?? const EdgeInsets.all(20),
            child: child,
          ),
        ],
      ),
    );
  }

  // =====================================================
  // FILTROS (sin card, arriba)
  // =====================================================
  Widget _buildFiltersRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;
        final spacing = 12.0;
        final fieldWidth = isWide
            ? (constraints.maxWidth - spacing) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            SizedBox(
              width: fieldWidth,
              child: _buildSearchField(
                label: 'Buscar por nombre',
                icon: Icons.search_rounded,
                onChanged: (v) async {
                  _search = v;
                  final now = DateTime.now();
                  _lastSearchAt = now;
                  await Future.delayed(const Duration(milliseconds: 500));
                  if (_lastSearchAt == now) {
                    await _loadData(isRefresh: true);
                  }
                },
              ),
            ),
            SizedBox(
              width: fieldWidth,
              child: _buildSearchField(
                label: 'Buscar por dirección',
                icon: Icons.location_on_rounded,
                onChanged: (v) async {
                  _direccionFilter = v;
                  final now = DateTime.now();
                  _lastSearchAt = now;
                  await Future.delayed(const Duration(milliseconds: 500));
                  if (_lastSearchAt == now) {
                    await _loadData(isRefresh: true);
                  }
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSearchField({
    required String label,
    required IconData icon,
    required Function(String) onChanged,
  }) {
    return TextField(
      onChanged: onChanged,
      style: const TextStyle(
        fontSize: 14,
        color: AppColors.textPrimary,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
        prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
        filled: true,
        fillColor: AppColors.surfaceVariant.withOpacity(0.5),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }

  // =====================================================
  // LISTA DE ALMACENES
  // =====================================================
  Widget _buildWarehousesCard() {
    final totalText = _pagination != null
        ? '${_pagination!.totalAlmacenes} almacenes'
        : '${_warehouses.length} almacenes';

    return _buildSectionCard(
      title: 'Almacenes',
      subtitle: totalText,
      icon: Icons.warehouse_rounded,
      action: _canCreateWarehouse
          ? ElevatedButton.icon(
              onPressed: _onAddWarehouse,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Agregar almacén'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            )
          : null,
      child: _warehouses.isEmpty
          ? _buildEmptyState()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 900;
                    final colCount = isWide ? 2 : 1;
                    final spacing = 12.0;
                    final itemWidth = (constraints.maxWidth -
                            spacing * (colCount - 1)) /
                        colCount;
                    return Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: _warehouses
                          .map(
                            (w) => SizedBox(
                              width: itemWidth,
                              child: _WarehouseCard(
                                warehouse: w,
                                onEdit: _canEditWarehouse
                                    ? () => _onEditWarehouse(w)
                                    : null,
                                onView: () => _onViewWarehouse(w),
                              ),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
                if (_pagination?.tieneSiguiente == true) ...[
                  const SizedBox(height: 16),
                  Center(
                    child: _loadingMore
                        ? const Padding(
                            padding: EdgeInsets.all(8),
                            child: CircularProgressIndicator(
                              color: AppColors.primary,
                            ),
                          )
                        : OutlinedButton.icon(
                            onPressed: _loadMoreData,
                            icon: const Icon(Icons.expand_more_rounded,
                                size: 18),
                            label: const Text('Cargar más'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side:
                                  const BorderSide(color: AppColors.primary),
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
                  ),
                ],
                if (_pagination != null) ...[
                  const SizedBox(height: 16),
                  _buildPaginationInfo(),
                ],
              ],
            ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(32),
            ),
            child: const Icon(
              Icons.warehouse_outlined,
              size: 32,
              color: AppColors.textLight,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'No hay almacenes',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Crea tu primer almacén para empezar a organizar el inventario.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          if (_canCreateWarehouse) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _onAddWarehouse,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Agregar almacén'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
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
        ],
      ),
    );
  }

  Widget _buildPaginationInfo() {
    if (_pagination == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.format_list_numbered_rounded,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                'Página ${_pagination!.paginaActual} de ${_pagination!.totalPaginas}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          Text(
            '${_pagination!.totalAlmacenes} almacenes en total',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  void _onAddWarehouse() async {
    final result = await Navigator.pushNamed(context, '/add-warehouse');
    if (result == true) {
      await _loadData(isRefresh: true);
    }
  }

  void _onEditWarehouse(Warehouse w) {
    if (!_canEditWarehouse) {
      NavigationGuard.showActionDeniedMessage(context, 'Editar almacén');
      return;
    }
    _openEditWarehouse(w);
  }

  Future<void> _openEditWarehouse(Warehouse w) async {
    final isWeb =
        PlatformUtils.isWeb && MediaQuery.of(context).size.width >= 900;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => isWeb
            ? AddWarehouseWebScreen(initialWarehouse: w)
            : AddWarehouseScreen(initialWarehouse: w),
      ),
    );

    if (result == true && mounted) {
      await _loadData(isRefresh: true);
    }
  }

  Future<void> _onViewWarehouse(Warehouse w) async {
    final isWeb =
        PlatformUtils.isWeb && MediaQuery.of(context).size.width >= 900;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => isWeb
            ? WarehouseDetailWebScreen(warehouseId: w.id)
            : WarehouseDetailScreen(warehouseId: w.id),
      ),
    );
    _loadData();
  }
}

// =====================================================
// WAREHOUSE CARD
// =====================================================
class _WarehouseCard extends StatefulWidget {
  final Warehouse warehouse;
  final VoidCallback? onEdit;
  final VoidCallback onView;

  const _WarehouseCard({
    required this.warehouse,
    this.onEdit,
    required this.onView,
  });

  @override
  State<_WarehouseCard> createState() => _WarehouseCardState();
}

class _WarehouseCardState extends State<_WarehouseCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final w = widget.warehouse;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _hovering ? AppColors.primary : AppColors.border,
            width: _hovering ? 1.4 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(_hovering ? 0.06 : 0.025),
              blurRadius: _hovering ? 14 : 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onView,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.warehouse_rounded,
                          color: AppColors.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              w.name,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                                letterSpacing: 0.1,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  Icons.location_on_rounded,
                                  size: 13,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    w.address,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _typeBadge(w.type),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Divider(
                    height: 1,
                    color: AppColors.border,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _metric(
                          Icons.layers_rounded,
                          '${w.zones.length}',
                          'Layouts',
                          AppColors.primary,
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 28,
                        color: AppColors.border,
                      ),
                      // Métrica de Límites oculta temporalmente
                      // Expanded(
                      //   child: _metric(
                      //     Icons.tune_rounded,
                      //     '${w.limitesStockCount}',
                      //     'Límites',
                      //     Colors.orange,
                      //   ),
                      // ),
                      // Container(
                      //   width: 1,
                      //   height: 28,
                      //   color: AppColors.border,
                      // ),
                      Expanded(
                        child: _actions(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _metric(IconData icon, String value, String label, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  Widget _actions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        _iconAction(
          icon: Icons.visibility_outlined,
          tooltip: 'Ver detalle',
          color: AppColors.primary,
          onTap: widget.onView,
        ),
        if (widget.onEdit != null) ...[
          const SizedBox(width: 4),
          _iconAction(
            icon: Icons.edit_outlined,
            tooltip: 'Editar',
            color: AppColors.textSecondary,
            onTap: widget.onEdit!,
          ),
        ],
      ],
    );
  }

  Widget _iconAction({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }

  Widget _typeBadge(String type) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        type.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _StatData {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  _StatData({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });
}
