import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../widgets/tpv_managements/tpv.dart';
import '../widgets/tpv_managements/vendor.dart';
import '../widgets/tpv_managements/price_alterations.dart';
import '../widgets/tpv_managements/asignate_vendor.dart';
import '../services/tpv_service.dart';
import '../utils/navigation_guard.dart';

/// Pantalla principal de gestión de TPVs y Vendedores (vista web)
class TpvManagementWebScreen extends StatefulWidget {
  const TpvManagementWebScreen({Key? key}) : super(key: key);

  @override
  State<TpvManagementWebScreen> createState() => _TpvManagementWebScreenState();
}

class _TpvManagementWebScreenState extends State<TpvManagementWebScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int _refreshKey = 0;
  int _currentTabIndex = 0;

  bool _canCreateTpv = false;

  static const double _kMaxContentWidth = 1280;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabChange);
    _loadPermissions();
  }

  void _handleTabChange() {
    if (!mounted) return;
    if (_tabController.indexIsChanging) return;
    if (_tabController.index == _currentTabIndex) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _currentTabIndex = _tabController.index);
    });
  }

  Future<void> _loadPermissions() async {
    final canCreate = await NavigationGuard.canPerformAction('tpv.create');
    if (!mounted) return;
    setState(() => _canCreateTpv = canCreate);
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _refreshData() {
    setState(() => _refreshKey++);
  }

  String get _searchHint {
    switch (_currentTabIndex) {
      case 0:
        return 'Buscar TPVs...';
      case 1:
        return 'Buscar vendedores...';
      case 2:
        return 'Buscar cambios de precio...';
      default:
        return 'Buscar...';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Gestión de TPVs',
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
                          icon: Icons.point_of_sale_outlined,
                          text: 'TPVs',
                        ),
                      ),
                      Tab(
                        height: 48,
                        child: _TabLabel(
                          icon: Icons.people_alt_outlined,
                          text: 'Vendedores',
                        ),
                      ),
                      Tab(
                        height: 48,
                        child: _TabLabel(
                          icon: Icons.price_change_outlined,
                          text: 'Cambios',
                        ),
                      ),
                    ],
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white70,
                    indicator: const UnderlineTabIndicator(
                      borderSide: BorderSide(width: 3, color: Colors.white),
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
      body: Column(
        children: [
          _buildFilterBar(),
          Container(height: 1, color: AppColors.border),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTabBody(
                  TpvListWidget(
                    key: ValueKey('tpv_$_refreshKey'),
                    searchQuery: _searchQuery,
                    onRefresh: _refreshData,
                  ),
                ),
                _buildTabBody(
                  VendorListWidget(
                    key: ValueKey('vendor_$_refreshKey'),
                    searchQuery: _searchQuery,
                    onRefresh: _refreshData,
                  ),
                ),
                _buildTabBody(
                  PriceAlterationsTabView(
                    key: ValueKey('price_changes_$_refreshKey'),
                    searchQuery: _searchQuery,
                    onRefresh: _refreshData,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _canCreateTpv && _currentTabIndex == 0
          ? FloatingActionButton.extended(
              onPressed: _showAddDialog,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 2,
              icon: const Icon(Icons.add, size: 20),
              label: const Text(
                'Nuevo TPV',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            )
          : null,
    );
  }

  Widget _buildFilterBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.025),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kMaxContentWidth),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 600;
              final searchField = _buildSearchField();
              final contextLabel = _buildContextLabel();
              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    contextLabel,
                    const SizedBox(height: 10),
                    searchField,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: contextLabel),
                  const SizedBox(width: 16),
                  SizedBox(width: 360, child: searchField),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildContextLabel() {
    final IconData icon;
    final String title;
    final String subtitle;
    switch (_currentTabIndex) {
      case 0:
        icon = Icons.point_of_sale_outlined;
        title = 'Terminales de Punto de Venta';
        subtitle = 'Gestiona los TPVs registrados en la tienda';
        break;
      case 1:
        icon = Icons.people_alt_outlined;
        title = 'Vendedores';
        subtitle = 'Administra los vendedores y sus permisos';
        break;
      case 2:
        icon = Icons.price_change_outlined;
        title = 'Cambios de Precio';
        subtitle = 'Historial y control de alteraciones de precio';
        break;
      default:
        icon = Icons.dashboard_outlined;
        title = 'Gestión';
        subtitle = '';
    }

    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: AppColors.primary),
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
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: 0.1,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    final hasQuery = _searchQuery.isNotEmpty;
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasQuery ? AppColors.primary : AppColors.border,
          width: hasQuery ? 1.5 : 1,
        ),
        boxShadow: hasQuery
            ? [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.10),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Icon(
            Icons.search_rounded,
            size: 18,
            color: hasQuery ? AppColors.primary : AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: _searchHint,
                hintStyle: const TextStyle(
                  color: AppColors.textLight,
                  fontSize: 13,
                ),
                isDense: true,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          if (hasQuery)
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
                child: Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: AppColors.primary,
                  ),
                ),
              ),
            )
          else
            const SizedBox(width: 14),
        ],
      ),
    );
  }

  Widget _buildTabBody(Widget child) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _kMaxContentWidth),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
          child: child,
        ),
      ),
    );
  }

  void _showAddDialog() {
    final isTPVTab = _currentTabIndex == 0;
    final isVendorTab = _currentTabIndex == 1;

    if (isTPVTab) {
      if (!_canCreateTpv) {
        NavigationGuard.showActionDeniedMessage(context, 'Crear TPV');
        return;
      }
      _showCreateTpvDialog();
    } else if (isVendorTab) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Seleccione un TPV desde la lista para asignar un vendedor',
          ),
          backgroundColor: AppColors.info,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No hay acciones disponibles en esta pestaña'),
          backgroundColor: AppColors.info,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
    }
  }

  /// Muestra el diálogo para crear un nuevo TPV
  void _showCreateTpvDialog() {
    if (!_canCreateTpv) {
      NavigationGuard.showActionDeniedMessage(context, 'Crear TPV');
      return;
    }
    final denominacionController = TextEditingController();
    int? selectedAlmacenId;

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.4),
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 8,
          backgroundColor: AppColors.surface,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header simple
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Crear nuevo TPV',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Define la denominación y el almacén',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      InkWell(
                        onTap: () => Navigator.pop(context),
                        borderRadius: BorderRadius.circular(6),
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(
                            Icons.close_rounded,
                            color: AppColors.textSecondary,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(height: 1, color: AppColors.border),

                // Contenido
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: TpvService.getAlmacenesByStore(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 30),
                          child: Center(
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: AppColors.primary,
                                strokeWidth: 2.5,
                              ),
                            ),
                          ),
                        );
                      }

                      if (snapshot.hasError) {
                        return _buildInlineError('Error: ${snapshot.error}');
                      }

                      final almacenes = snapshot.data ?? [];

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFieldLabel('Denominación', required: true),
                          const SizedBox(height: 6),
                          TextField(
                            controller: denominacionController,
                            onChanged: (_) => setState(() {}),
                            style: const TextStyle(fontSize: 13),
                            decoration: _inputDecoration(
                              'Ej: TPV Principal',
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildFieldLabel('Almacén', required: true),
                          const SizedBox(height: 6),
                          if (almacenes.isEmpty)
                            _buildInlineWarning(
                              'No hay almacenes. Crea uno antes de registrar un TPV.',
                            )
                          else
                            Container(
                              decoration: BoxDecoration(
                                color: AppColors.surfaceVariant,
                                border: Border.all(
                                  color: selectedAlmacenId != null
                                      ? AppColors.primary
                                      : AppColors.border,
                                  width: selectedAlmacenId != null ? 1.5 : 1,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<int>(
                                  value: selectedAlmacenId,
                                  hint: const Text(
                                    'Seleccione un almacén',
                                    style: TextStyle(
                                      color: AppColors.textLight,
                                      fontSize: 13,
                                    ),
                                  ),
                                  isExpanded: true,
                                  icon: const Icon(
                                    Icons.expand_more_rounded,
                                    color: AppColors.textSecondary,
                                    size: 20,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textPrimary,
                                  ),
                                  items: almacenes.map((almacen) {
                                    return DropdownMenuItem<int>(
                                      value: almacen['id'],
                                      child: Text(
                                        almacen['denominacion'] ?? 'Sin nombre',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (id) {
                                    if (id != null) {
                                      setState(() => selectedAlmacenId = id);
                                    }
                                  },
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                Container(height: 1, color: AppColors.border),

                // Footer
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Cancelar',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      ElevatedButton(
                        onPressed: denominacionController.text.isEmpty ||
                                selectedAlmacenId == null
                            ? null
                            : () async {
                                Navigator.pop(context);
                                await _createTpv(
                                  denominacionController.text,
                                  selectedAlmacenId!,
                                );
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.border,
                          disabledForegroundColor: AppColors.textLight,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Crear',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: AppColors.textLight,
        fontSize: 13,
      ),
      isDense: true,
      filled: true,
      fillColor: AppColors.surfaceVariant,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    );
  }

  Widget _buildFieldLabel(String text, {bool required = false}) {
    return Row(
      children: [
        Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12,
            color: AppColors.textPrimary,
          ),
        ),
        if (required)
          const Text(
            ' *',
            style: TextStyle(
              color: AppColors.error,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
      ],
    );
  }

  Widget _buildInlineError(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.error, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.error, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineWarning(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warning.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppColors.warning, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Crea un nuevo TPV
  Future<void> _createTpv(String denominacion, int idAlmacen) async {
    if (!_canCreateTpv) {
      if (mounted) {
        NavigationGuard.showActionDeniedMessage(context, 'Crear TPV');
      }
      return;
    }
    try {
      final success = await TpvService.createTpv(
        denominacion: denominacion,
        idAlmacen: idAlmacen,
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('TPV "$denominacion" creado exitosamente'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
          _refreshData();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Error al crear el TPV'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    }
  }
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
