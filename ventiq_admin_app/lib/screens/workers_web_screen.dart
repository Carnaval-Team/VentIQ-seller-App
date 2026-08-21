import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/admin_bottom_navigation.dart';
import '../models/worker_models.dart';
import '../models/hr_models.dart';
import '../services/worker_service.dart';
import '../services/store_service.dart';
import '../services/hr_service.dart';
import '../services/subscription_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/navigation_guard.dart';
import '../utils/screen_protection_mixin.dart';
import 'edit_worker_multi_role_screen.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:typed_data';

// En web el PDF se descarga con un anchor; en el resto de plataformas el stub
// lanza UnsupportedError (esta pantalla solo se monta en web).
import '../services/web_download_stub.dart'
    if (dart.library.html) '../services/web_download_web.dart' as web_download;

/// Ancho maximo del contenido principal en web
const double _kMaxContentWidth = 1400.0;

class WorkersWebScreen extends StatefulWidget {
  const WorkersWebScreen({super.key});

  @override
  State<WorkersWebScreen> createState() => _WorkersWebScreenState();
}

class _WorkersWebScreenState extends State<WorkersWebScreen>
    with TickerProviderStateMixin, ScreenProtectionMixin {
  @override
  String get protectedRoute => '/workers';

  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  List<WorkerData> _workers = [];
  List<WorkerRole> _roles = [];
  List<TPVData> _tpvs = [];
  List<AlmacenData> _almacenes = [];
  WorkerStatistics? _statistics;

  bool _isLoadingWorkers = true;
  bool _isLoadingRoles = true;

  bool _canEditWorkers = false;
  bool _canDeleteWorkers = false;
  bool _hasHRPlan = false;

  String _selectedRole = 'Todos';

  // Ordenamiento de la tabla de personal
  String _sortColumn = 'nombre';
  bool _sortAscending = true;

  int? _storeId;
  String? _userUuid;

  List<ShiftWithWorkers> _shifts = [];
  bool _isLoadingShifts = false;
  DateTime _fechaDesde = DateTime.now().subtract(const Duration(days: 7));
  DateTime _fechaHasta = DateTime.now();
  HRSummary? _hrSummary;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _loadPermissions();
    _initializeData();
    _checkHRPlan();
  }

  Future<void> _checkHRPlan() async {
    try {
      final hasPlan = await SubscriptionService().hasProPlanInAnyStore();
      if (!mounted) return;
      setState(() {
        _hasHRPlan = hasPlan;
        _tabController.dispose();
        _tabController = TabController(length: hasPlan ? 3 : 2, vsync: this);
        _tabController.addListener(() => setState(() {}));
      });
    } catch (e) {
      print('❌ Error verificando plan HR: $e');
    }
  }

  Future<void> _loadPermissions() async {
    final permissions = await Future.wait([
      NavigationGuard.canPerformAction('worker.edit'),
      NavigationGuard.canPerformAction('worker.delete'),
    ]);
    if (!mounted) return;
    setState(() {
      _canEditWorkers = permissions[0];
      _canDeleteWorkers = permissions[1];
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    try {
      final storeData = await StoreService.getWorkerRequiredData();
      if (storeData == null) {
        _showErrorDialog(
          'No se pudieron obtener los datos de la tienda. '
          'Por favor, inicia sesión nuevamente.',
        );
        return;
      }
      setState(() {
        _storeId = storeData['storeId'];
        _userUuid = storeData['userUuid'];
      });
      await Future.wait([
        _loadWorkersData(),
        _loadRolesData(),
        _loadAuxiliaryData(),
      ]);
    } catch (e) {
      print('❌ Error inicializando datos: $e');
      _showErrorDialog('Error al cargar los datos: $e');
    }
  }

  Future<void> _loadWorkersData() async {
    if (_storeId == null || _userUuid == null) return;
    setState(() => _isLoadingWorkers = true);
    try {
      final workers = await WorkerService.getWorkersByStore(
        _storeId!,
        _userUuid!,
      );
      final statistics = await WorkerService.getWorkerStatistics(_storeId!);
      setState(() {
        _workers = workers;
        _statistics = statistics;
        _isLoadingWorkers = false;
      });
    } catch (e) {
      print('❌ Error cargando trabajadores: $e');
      setState(() => _isLoadingWorkers = false);
      _showErrorDialog('Error al cargar trabajadores: $e');
    }
  }

  Future<void> _loadRolesData() async {
    if (_storeId == null) return;
    setState(() => _isLoadingRoles = true);
    try {
      final roles = await WorkerService.getRolesByStore(_storeId!);
      setState(() {
        _roles = roles;
        _isLoadingRoles = false;
      });
    } catch (e) {
      print('❌ Error cargando roles: $e');
      setState(() => _isLoadingRoles = false);
      _showErrorDialog('Error al cargar roles: $e');
    }
  }

  Future<void> _loadAuxiliaryData() async {
    if (_storeId == null) return;
    try {
      final tpvs = await WorkerService.getTPVsByStore(_storeId!);
      final almacenes = await WorkerService.getAlmacenesByStore(_storeId!);
      setState(() {
        _tpvs = tpvs;
        _almacenes = almacenes;
      });
    } catch (e) {
      print('❌ Error cargando datos auxiliares: $e');
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
      endDrawer: const AdminDrawer(),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kMaxContentWidth),
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildWorkersTab(),
              _buildRolesTab(),
              if (_hasHRPlan) _buildHRTab(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const AdminBottomNavigation(
        currentRoute: '/workers',
      ),
    );
  }

  PreferredSizeWidget _buildWebAppBar() {
    return AppBar(
      backgroundColor: AppColors.primary,
      elevation: 0,
      centerTitle: false,
      iconTheme: const IconThemeData(color: Colors.white),
      title: const Text(
        'Gestión de Personal',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),
      actions: [
        if (_canEditWorkers)
          _appBarIconBtn(
            Icons.sync,
            'Sincronizar UUID desde Roles',
            _showSyncUUIDDialog,
          ),
        if (_hasHRPlan)
          FutureBuilder<bool>(
            future: NavigationGuard.canPerformAction('hr.dashboard'),
            builder: (context, snapshot) {
              if (snapshot.data == true) {
                return _appBarIconBtn(Icons.badge, 'Recursos Humanos', () {
                  Navigator.pushNamed(
                    context,
                    '/hr-dashboard',
                    arguments: {'fromGerente': true},
                  );
                });
              }
              return const SizedBox.shrink();
            },
          ),
        _appBarIconBtn(Icons.refresh, 'Actualizar', _initializeData),
        Builder(
          builder: (context) => _appBarIconBtn(
            Icons.menu,
            'Menú',
            () => Scaffold.of(context).openEndDrawer(),
          ),
        ),
        const SizedBox(width: 8),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(42),
        child: Container(
          color: AppColors.primary,
          alignment: Alignment.centerLeft,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            indicatorSize: TabBarIndicatorSize.tab,
            labelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: const TextStyle(fontSize: 13),
            tabs: [
              const Tab(
                height: 42,
                child: _TabLabel(icon: Icons.people, text: 'Personal'),
              ),
              const Tab(
                height: 42,
                child: _TabLabel(
                  icon: Icons.admin_panel_settings,
                  text: 'Roles',
                ),
              ),
              if (_hasHRPlan)
                const Tab(
                  height: 42,
                  child: _TabLabel(
                    icon: Icons.attach_money,
                    text: 'Recursos Humanos',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _appBarIconBtn(
    IconData icon,
    String tooltip,
    VoidCallback onPressed,
  ) {
    return IconButton(
      icon: Icon(icon, color: Colors.white, size: 20),
      onPressed: onPressed,
      tooltip: tooltip,
      splashRadius: 20,
    );
  }

  // =====================================================
  // STATS
  // =====================================================

  Widget _buildStatsRow() {
    final stats = _statistics;
    if (stats == null) return const SizedBox.shrink();
    return Row(
      children: [
        Expanded(
          child: _statCard(
            'Total',
            stats.totalTrabajadores.toString(),
            Icons.people,
            AppColors.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statCard(
            'Gerentes',
            stats.totalGerentes.toString(),
            Icons.admin_panel_settings,
            Colors.purple,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statCard(
            'Dependientes',
            stats.totalVendedores.toString(),
            Icons.point_of_sale,
            AppColors.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statCard(
            'Almaceneros',
            stats.totalAlmaceneros.toString(),
            Icons.warehouse,
            Colors.green,
          ),
        ),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 17),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                    height: 1.1,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // WORKERS TAB
  // =====================================================

  List<WorkerData> get _filteredWorkers {
    final query = _searchQuery.toLowerCase();
    final list = _workers.where((w) {
      final matchSearch = query.isEmpty ||
          w.nombreCompleto.toLowerCase().contains(query) ||
          w.rolNombre.toLowerCase().contains(query) ||
          (w.email?.toLowerCase().contains(query) ?? false);
      final matchRole = _selectedRole == 'Todos' || w.tipoRol == _selectedRole;
      return matchSearch && matchRole;
    }).toList();

    list.sort((a, b) {
      int cmp;
      switch (_sortColumn) {
        case 'rol':
          cmp = _getRoleDisplayName(_getRolPrincipal(a))
              .compareTo(_getRoleDisplayName(_getRolPrincipal(b)));
          break;
        case 'salario':
          cmp = a.tarifaVigente.compareTo(b.tarifaVigente);
          break;
        default:
          cmp = a.nombreCompleto.toLowerCase().compareTo(
                b.nombreCompleto.toLowerCase(),
              );
      }
      return _sortAscending ? cmp : -cmp;
    });
    return list;
  }

  Widget _buildWorkersTab() {
    if (_isLoadingWorkers) return _buildLoader('Cargando trabajadores...');

    final filteredWorkers = _filteredWorkers;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_statistics != null) ...[
            _buildStatsRow(),
            const SizedBox(height: 16),
          ],
          Expanded(
            child: _buildPanel(
              header: _buildWorkersToolbar(filteredWorkers.length),
              child: filteredWorkers.isEmpty
                  ? _buildEmptyState(
                      Icons.people_outline,
                      'No se encontraron trabajadores',
                      'Intenta ajustar los filtros de búsqueda',
                    )
                  : Column(
                      children: [
                        _buildWorkersHeaderRow(),
                        const Divider(height: 1),
                        Expanded(
                          child: ListView.separated(
                            padding: EdgeInsets.zero,
                            itemCount: filteredWorkers.length,
                            separatorBuilder: (_, __) => const Divider(
                              height: 1,
                              indent: 20,
                              endIndent: 20,
                            ),
                            itemBuilder: (context, index) =>
                                _buildWorkerRow(filteredWorkers[index]),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkersToolbar(int count) {
    return Row(
      children: [
        SizedBox(
          width: 280,
          child: TextField(
            controller: _searchController,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Buscar por nombre, rol o email...',
              hintStyle: const TextStyle(fontSize: 13),
              prefixIcon: const Icon(
                Icons.search,
                size: 18,
                color: AppColors.primary,
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 36),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      splashRadius: 14,
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedRole,
              isDense: true,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
              icon: const Icon(
                Icons.filter_list,
                size: 17,
                color: AppColors.primary,
              ),
              items: const [
                'Todos',
                'gerente',
                'supervisor',
                'auditor',
                'vendedor',
                'almacenero',
                'recursos_humanos',
              ].map((role) {
                return DropdownMenuItem(
                  value: role,
                  child: Text(_getRoleDisplayName(role)),
                );
              }).toList(),
              onChanged: (v) => setState(() => _selectedRole = v!),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Text(
          '$count trabajador${count != 1 ? 'es' : ''}',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const Spacer(),
        FutureBuilder<bool>(
          future: NavigationGuard.canPerformAction('worker.create'),
          builder: (context, snapshot) {
            if (snapshot.data != true) return const SizedBox.shrink();
            return ElevatedButton.icon(
              onPressed: _showAddWorkerDialog,
              icon: const Icon(Icons.person_add, size: 16),
              label: const Text(
                'Nuevo Trabajador',
                style: TextStyle(fontSize: 13),
              ),
              style: _primaryButtonStyle,
            );
          },
        ),
      ],
    );
  }

  Widget _buildWorkersHeaderRow() {
    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
      child: Row(
        children: [
          const SizedBox(width: 44),
          _colHeader('NOMBRE', flex: 3, sortKey: 'nombre'),
          _colHeader('ROL PRINCIPAL', flex: 2, sortKey: 'rol'),
          _colHeader('ROLES ACTIVOS', flex: 3),
          _colHeader('SALARIO', flex: 2, sortKey: 'salario'),
          _colHeader('TPV / ALMACÉN', flex: 2),
          const SizedBox(width: 104),
        ],
      ),
    );
  }

  Widget _colHeader(String text, {int flex = 1, String? sortKey}) {
    final isSorted = sortKey != null && _sortColumn == sortKey;
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: isSorted ? AppColors.primary : AppColors.textSecondary,
              letterSpacing: 0.5,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (isSorted)
          Icon(
            _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
            size: 12,
            color: AppColors.primary,
          ),
      ],
    );

    return Expanded(
      flex: flex,
      child: sortKey == null
          ? label
          : InkWell(
              onTap: () => setState(() {
                if (_sortColumn == sortKey) {
                  _sortAscending = !_sortAscending;
                } else {
                  _sortColumn = sortKey;
                  _sortAscending = true;
                }
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: label,
              ),
            ),
    );
  }

  Widget _buildWorkerRow(WorkerData worker) {
    final rolPrincipal = _getRolPrincipal(worker);
    final color = _getRoleColor(rolPrincipal);
    final nombreDisplay = _getRoleDisplayName(rolPrincipal);

    return InkWell(
      onTap: () => _showWorkerDetails(worker),
      hoverColor: AppColors.primary.withOpacity(0.03),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        child: Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: color.withOpacity(0.12),
              child: Text(
                worker.nombres.substring(0, 1).toUpperCase(),
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    worker.nombreCompleto,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (worker.email != null)
                    Text(
                      worker.email!,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    nombreDisplay,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            Expanded(flex: 3, child: _buildRoleTags(worker)),
            Expanded(
              flex: 2,
              child: worker.tarifaVigente > 0
                  ? Row(
                      children: [
                        Icon(
                          worker.tipoSalario.esPorDia
                              ? Icons.today
                              : Icons.attach_money,
                          size: 12,
                          color: Colors.green[700],
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            worker.tarifaFormatted,
                            style: TextStyle(
                              color: Colors.green[700],
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      '—',
                      style: TextStyle(color: Colors.grey[400], fontSize: 11),
                    ),
            ),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (worker.esVendedor && worker.tpvDenominacion != null)
                    _miniIconText(Icons.point_of_sale, worker.tpvDenominacion!),
                  if (worker.esAlmacenero && worker.almacenDenominacion != null)
                    _miniIconText(Icons.warehouse, worker.almacenDenominacion!),
                  if (!worker.esVendedor && !worker.esAlmacenero)
                    Text(
                      '—',
                      style: TextStyle(color: Colors.grey[400], fontSize: 11),
                    ),
                ],
              ),
            ),
            SizedBox(
              width: 104,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!worker.tieneUsuario && _canEditWorkers)
                    _actionBtn(
                      Icons.person_add,
                      Colors.green,
                      'Crear Usuario',
                      () => _showCreateUserDialog(worker),
                    ),
                  if (_canEditWorkers)
                    _actionBtn(
                      Icons.edit,
                      AppColors.primary,
                      'Editar',
                      () => _showEditWorkerDialog(worker),
                    ),
                  if (_canDeleteWorkers)
                    _actionBtn(
                      Icons.delete,
                      Colors.red,
                      'Eliminar',
                      () => _showDeleteWorkerDialog(worker),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniIconText(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 11, color: Colors.grey[500]),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            text,
            style: TextStyle(color: Colors.grey[600], fontSize: 11),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _actionBtn(
    IconData icon,
    Color color,
    String tooltip,
    VoidCallback onPressed,
  ) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }

  // =====================================================
  // ROLES TAB
  // =====================================================

  Widget _buildRolesTab() {
    if (_isLoadingRoles) return _buildLoader('Cargando roles...');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: _buildPanel(
        header: Row(
          children: [
            const Text(
              'Roles de la Tienda',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 12),
            Text(
              '${_roles.length} rol${_roles.length != 1 ? 'es' : ''}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: _showAddRoleDialog,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Nuevo Rol', style: TextStyle(fontSize: 13)),
              style: _primaryButtonStyle,
            ),
          ],
        ),
        child: _roles.isEmpty
            ? _buildEmptyState(
                Icons.admin_panel_settings_outlined,
                'No hay roles configurados',
                'Agrega roles para organizar tu personal',
              )
            : ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: _roles.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 20, endIndent: 20),
                itemBuilder: (context, index) => _buildRoleRow(_roles[index]),
              ),
      ),
    );
  }

  Widget _buildRoleRow(WorkerRole role) {
    final workerCount = _workers.where((w) => w.rolId == role.id).length;
    final canDelete = _canDeleteWorkers && workerCount == 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.admin_panel_settings,
              color: AppColors.primary,
              size: 17,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  role.denominacion,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (role.descripcion != null && role.descripcion!.isNotEmpty)
                  Text(
                    role.descripcion!,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$workerCount trabajador${workerCount != 1 ? 'es' : ''}',
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (_canEditWorkers)
            _actionBtn(
              Icons.edit,
              AppColors.primary,
              'Editar',
              () => _showEditRoleDialog(role),
            ),
          _actionBtn(
            Icons.delete,
            canDelete ? Colors.red : Colors.grey[350]!,
            !_canDeleteWorkers
                ? 'Sin permisos'
                : workerCount > 0
                    ? 'No se puede eliminar (tiene trabajadores asignados)'
                    : 'Eliminar',
            canDelete ? () => _showDeleteRoleDialog(role) : () {},
          ),
        ],
      ),
    );
  }

  // =====================================================
  // HR TAB
  // =====================================================

  Widget _buildHRTab() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHRToolbar(),
          const SizedBox(height: 16),
          Expanded(
            child: _buildPanel(
              header: Row(
                children: [
                  const Text(
                    'Turnos del Período',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${_shifts.length} turno${_shifts.length != 1 ? 's' : ''}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: _shifts.isEmpty ? null : _exportHRReportToPDF,
                    icon: const Icon(Icons.picture_as_pdf, size: 16),
                    label: const Text(
                      'Exportar PDF',
                      style: TextStyle(fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
              child: _isLoadingShifts
                  ? _buildLoader('Cargando datos de RR.HH...')
                  : _shifts.isEmpty
                      ? _buildEmptyState(
                          Icons.calendar_today_outlined,
                          'No hay turnos en este período',
                          'Selecciona otro rango de fechas',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(14),
                          itemCount: _shifts.length,
                          itemBuilder: (context, index) =>
                              _buildShiftCard(_shifts[index]),
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHRToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.date_range, color: AppColors.primary, size: 17),
              SizedBox(width: 8),
              Text(
                'Período:',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ],
          ),
          SizedBox(
            width: 150,
            child: _buildDateField(
              label: 'Desde',
              date: _fechaDesde,
              onTap: () => _selectDate(context, true),
            ),
          ),
          SizedBox(
            width: 150,
            child: _buildDateField(
              label: 'Hasta',
              date: _fechaHasta,
              onTap: () => _selectDate(context, false),
            ),
          ),
          ElevatedButton.icon(
            onPressed: _loadHRData,
            icon: const Icon(Icons.search, size: 16),
            label: const Text('Buscar', style: TextStyle(fontSize: 13)),
            style: _primaryButtonStyle,
          ),
          if (_hrSummary != null) ...[
            _hrSummaryChip(
              'Turnos',
              _hrSummary!.totalTurnos.toString(),
              Colors.blue,
            ),
            _hrSummaryChip(
              'Trabajadores',
              _hrSummary!.totalTrabajadores.toString(),
              Colors.indigo,
            ),
            _hrSummaryChip(
              'Horas',
              '${_hrSummary!.totalHorasTrabajadas.toStringAsFixed(1)}h',
              Colors.orange,
            ),
            _hrSummaryChip(
              'Total',
              _hrSummary!.totalSalariosFormatted,
              Colors.green,
            ),
          ],
        ],
      ),
    );
  }

  Widget _hrSummaryChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(color: color.withOpacity(0.75), fontSize: 11),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // SHARED WEB CHROME
  // =====================================================

  /// Tarjeta blanca con cabecera fija y contenido expandido: base de cada tab.
  Widget _buildPanel({required Widget header, required Widget child}) {
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: header,
          ),
          const Divider(height: 1),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _buildLoader(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 2.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(IconData icon, String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: Colors.grey[350]),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  ButtonStyle get _primaryButtonStyle => ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      );

  /// Contenedor estandar para los dialogos de esta pantalla en web.
  Widget _dialogBody({required double width, required Widget child}) {
    return SizedBox(
      width: width,
      child: SingleChildScrollView(child: child),
    );
  }

  Widget _noticeBox({
    required Color color,
    required IconData icon,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // HELPERS / UTILS
  // =====================================================

  String _getRolPrincipal(WorkerData worker) {
    // Jerarquía: gerente > supervisor > recursos_humanos > almacenero > vendedor
    if (worker.esGerente) return 'gerente';
    if (worker.esSupervisor) return 'supervisor';
    if (worker.esRecursosHumanos) return 'recursos_humanos';
    if (worker.esAlmacenero) return 'almacenero';
    if (worker.esVendedor) return 'vendedor';
    if (worker.tipoRol.isNotEmpty && worker.tipoRol != 'sin_rol') {
      return worker.tipoRol;
    }
    if (worker.rolNombre.isNotEmpty) return worker.rolNombre.toLowerCase();
    return 'sin_rol';
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case 'gerente':
        return Colors.purple;
      case 'supervisor':
        return Colors.orange;
      case 'auditor':
        return Colors.teal;
      case 'vendedor':
        return AppColors.primary;
      case 'almacenero':
        return Colors.green;
      case 'recursos_humanos':
        return Colors.indigo;
      default:
        return Colors.grey;
    }
  }

  String _getRoleDisplayName(String role) {
    switch (role.toLowerCase()) {
      case 'gerente':
        return 'Gerente';
      case 'supervisor':
        return 'Supervisor';
      case 'auditor':
        return 'Auditor';
      case 'vendedor':
        return 'Dependiente';
      case 'almacenero':
        return 'Almacenero';
      case 'recursos_humanos':
        return 'Recursos Humanos';
      case 'todos':
        return 'Todos';
      case 'sin_rol':
        return 'Trabajador';
      default:
        if (role.isEmpty) return 'Trabajador';
        return role[0].toUpperCase() + role.substring(1);
    }
  }

  int? _getRoleIdFromName(String? roleName) {
    if (roleName == null) return null;
    try {
      final display = _getRoleDisplayName(roleName).toLowerCase();
      final key = roleName.toLowerCase();
      final role = _roles.firstWhere(
        (r) {
          final d = r.denominacion.toLowerCase();
          if (d == display || d == key) return true;
          if (key == 'vendedor' &&
              (d.contains('vendedor') || d.contains('dependiente'))) {
            return true;
          }
          return false;
        },
        orElse: () => WorkerRole(
          id: 0,
          denominacion: '',
          descripcion: null,
          createdAt: DateTime.now(),
        ),
      );
      return role.id > 0 ? role.id : null;
    } catch (e) {
      print('⚠️ No se encontró rol con nombre: $roleName');
      return null;
    }
  }

  String? _getRoleNameFromId(int? roleId) {
    if (roleId == null) return null;
    try {
      final role = _roles.firstWhere(
        (r) => r.id == roleId,
        orElse: () => WorkerRole(
          id: 0,
          denominacion: '',
          descripcion: null,
          createdAt: DateTime.now(),
        ),
      );
      if (role.id == 0) return null;
      final d = role.denominacion.toLowerCase();
      if (d.contains('gerente')) return 'gerente';
      if (d.contains('supervisor')) return 'supervisor';
      if (d.contains('auditor')) return 'auditor';
      if (d.contains('vendedor') || d.contains('dependiente')) {
        return 'vendedor';
      }
      if (d.contains('almacenero')) return 'almacenero';
      if (d.contains('recursos humanos') || d.contains('recursos_humanos')) {
        return 'recursos_humanos';
      }
      return null;
    } catch (e) {
      print('⚠️ No se encontró rol con ID: $roleId');
      return null;
    }
  }

  Widget _buildRoleTags(WorkerData worker) {
    final tags = worker.rolesActivos;
    if (tags.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 4,
      runSpacing: 3,
      children: tags.map((tag) => _buildRoleTag(tag)).toList(),
    );
  }

  Widget _buildRoleTag(String role) {
    final config = _getRoleTagConfig(role);
    final color = config['color'] as Color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(config['icon'] as IconData, size: 9, color: color),
          const SizedBox(width: 3),
          Text(
            config['label'] as String,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _getRoleTagConfig(String role) {
    switch (role) {
      case 'usuario':
        return {
          'label': 'Usuario',
          'icon': Icons.account_circle,
          'color': Colors.blue,
        };
      case 'vendedor':
        return {
          'label': 'Dependiente',
          'icon': Icons.point_of_sale,
          'color': AppColors.primary,
        };
      case 'supervisor':
        return {
          'label': 'Supervisor',
          'icon': Icons.supervisor_account,
          'color': Colors.orange,
        };
      case 'auditor':
        return {
          'label': 'Auditor',
          'icon': Icons.fact_check,
          'color': Colors.teal,
        };
      case 'almacenero':
        return {
          'label': 'Almacenero',
          'icon': Icons.warehouse,
          'color': Colors.green,
        };
      case 'gerente':
        return {
          'label': 'Gerente',
          'icon': Icons.admin_panel_settings,
          'color': Colors.purple,
        };
      case 'recursos_humanos':
        return {
          'label': 'RR.HH.',
          'icon': Icons.people_alt,
          'color': Colors.indigo,
        };
      default:
        return {'label': role, 'icon': Icons.label, 'color': Colors.grey};
    }
  }

  // =====================================================
  // DIALOGS
  // =====================================================

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: SizedBox(width: 380, child: Text(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showWorkerDetails(WorkerData worker) {
    final rolPrincipal = _getRolPrincipal(worker);
    final color = _getRoleColor(rolPrincipal);

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: _dialogBody(
          width: 460,
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 25,
                      backgroundColor: color.withOpacity(0.1),
                      child: Text(
                        worker.nombres.substring(0, 1).toUpperCase(),
                        style: TextStyle(
                          color: color,
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            worker.nombreCompleto,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            _getRoleDisplayName(rolPrincipal),
                            style: TextStyle(color: color, fontSize: 13),
                          ),
                          if (worker.email != null)
                            Text(
                              worker.email!,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          if (worker.usuarioUuid != null)
                            Text(
                              'ID: ${worker.usuarioUuid!.substring(0, 8)}...',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _buildRoleTags(worker),
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 12),
                _buildInfoRow(
                  Icons.admin_panel_settings,
                  'Rol',
                  _getRoleDisplayName(worker.tipoRol),
                  color,
                ),
                _buildInfoRow(
                  Icons.calendar_today,
                  'Fecha de creación',
                  '${worker.fechaCreacion.day}/${worker.fechaCreacion.month}/'
                      '${worker.fechaCreacion.year}',
                  AppColors.primary,
                ),
                if (worker.tarifaVigente > 0)
                  _buildInfoRow(
                    worker.tipoSalario.esPorDia
                        ? Icons.today
                        : Icons.attach_money,
                    worker.tipoSalario.esPorDia
                        ? 'Salario por día'
                        : 'Salario por hora',
                    worker.tarifaFormatted,
                    Colors.green,
                  ),
                if (worker.esVendedor && worker.tpvDenominacion != null)
                  _buildInfoRow(
                    Icons.point_of_sale,
                    'TPV asignado',
                    worker.tpvDenominacion!,
                    AppColors.primary,
                  ),
                if (worker.numeroConfirmacion != null)
                  _buildInfoRow(
                    Icons.confirmation_number,
                    'N° de confirmación',
                    worker.numeroConfirmacion!,
                    Colors.orange,
                  ),
                if (worker.esAlmacenero && worker.almacenDenominacion != null)
                  _buildInfoRow(
                    Icons.warehouse,
                    'Almacén asignado',
                    worker.almacenDenominacion!,
                    Colors.green,
                  ),
                if (worker.almacenDireccion != null)
                  _buildInfoRow(
                    Icons.location_on,
                    'Dirección',
                    worker.almacenDireccion!,
                    Colors.grey,
                  ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, size: 15),
                      label: const Text('Cerrar'),
                    ),
                    if (_canEditWorkers) ...[
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _showEditWorkerDialog(worker);
                        },
                        icon: const Icon(Icons.edit, size: 15),
                        label: const Text('Editar'),
                        style: _primaryButtonStyle,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, color: color, size: 15),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddWorkerDialog() {
    final nombresController = TextEditingController();
    final apellidosController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final numeroConfirmacionController = TextEditingController();
    final salarioHorasController = TextEditingController(text: '0');
    TipoSalario tipoSalario = TipoSalario.hora;
    bool crearUsuario = false;
    bool asignarRolEspecifico = false;
    String? selectedRole;
    int? selectedTPV;
    int? selectedAlmacen;
    int? selectedRolGeneral;
    bool obscurePassword = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: const Row(
            children: [
              Icon(Icons.person_add, color: AppColors.primary, size: 20),
              SizedBox(width: 10),
              Text('Agregar Trabajador', style: TextStyle(fontSize: 17)),
            ],
          ),
          content: _dialogBody(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('Información Básica'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: nombresController,
                        decoration: _fieldDecoration(
                          'Nombres *',
                          Icons.person,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: apellidosController,
                        decoration: _fieldDecoration(
                          'Apellidos *',
                          Icons.person_outline,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    SegmentedButton<TipoSalario>(
                      segments: const [
                        ButtonSegment(
                          value: TipoSalario.hora,
                          label: Text('Por hora'),
                          icon: Icon(Icons.schedule, size: 15),
                        ),
                        ButtonSegment(
                          value: TipoSalario.dia,
                          label: Text('Por día'),
                          icon: Icon(Icons.today, size: 15),
                        ),
                      ],
                      selected: {tipoSalario},
                      onSelectionChanged: (sel) =>
                          setDialogState(() => tipoSalario = sel.first),
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        textStyle: WidgetStateProperty.all(
                          const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: salarioHorasController,
                        decoration: _fieldDecoration(
                          tipoSalario.esPorDia
                              ? 'Salario por Día'
                              : 'Salario por Hora',
                          Icons.attach_money,
                        ).copyWith(
                          suffixText: tipoSalario.tarifaSufijo,
                          hintText: '0.00',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  tipoSalario.esPorDia
                      ? 'Salario en moneda local por día trabajado'
                      : 'Salario en moneda local por hora trabajada',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 14),
                _checkboxCard(
                  value: crearUsuario,
                  color: Colors.blue,
                  title: 'Crear usuario de acceso',
                  subtitle: 'Permitirá al trabajador acceder a la app',
                  onChanged: (value) =>
                      setDialogState(() => crearUsuario = value ?? false),
                ),
                if (crearUsuario) ...[
                  const SizedBox(height: 14),
                  _sectionTitle('Credenciales de Acceso'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: emailController,
                          decoration: _fieldDecoration('Email *', Icons.email)
                              .copyWith(hintText: 'usuario@ejemplo.com'),
                          keyboardType: TextInputType.emailAddress,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: passwordController,
                          obscureText: obscurePassword,
                          decoration: _fieldDecoration(
                            'Contraseña *',
                            Icons.lock,
                          ).copyWith(
                            hintText: 'Mínimo 6 caracteres',
                            suffixIcon: IconButton(
                              icon: Icon(
                                obscurePassword
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                                size: 18,
                              ),
                              onPressed: () => setDialogState(
                                () => obscurePassword = !obscurePassword,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _checkboxCard(
                    value: asignarRolEspecifico,
                    color: Colors.orange,
                    title: 'Asignar rol específico de la app',
                    subtitle: 'Dependiente o Almacenero con configuración',
                    onChanged: (value) {
                      setDialogState(() {
                        asignarRolEspecifico = value ?? false;
                        if (!asignarRolEspecifico) {
                          selectedRole = null;
                          selectedTPV = null;
                          selectedAlmacen = null;
                        }
                      });
                    },
                  ),
                  if (asignarRolEspecifico) ...[
                    const SizedBox(height: 14),
                    _sectionTitle('Configuración de Rol'),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: selectedRole,
                      decoration: _fieldDecoration(
                        'Rol Específico *',
                        Icons.work,
                      ),
                      items: [
                        'gerente',
                        'supervisor',
                        'auditor',
                        'vendedor',
                        'almacenero',
                        if (_hasHRPlan) 'recursos_humanos',
                      ]
                          .map(
                            (r) => DropdownMenuItem(
                              value: r,
                              child: Text(_getRoleDisplayName(r)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          selectedRole = value;
                          selectedTPV = null;
                          selectedAlmacen = null;
                        });
                      },
                    ),
                    if (selectedRole == 'vendedor') ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: selectedTPV,
                              decoration: _fieldDecoration(
                                'TPV Asignado',
                                Icons.point_of_sale,
                              ),
                              items: _tpvs
                                  .map(
                                    (t) => DropdownMenuItem(
                                      value: t.id,
                                      child: Text(t.denominacion),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) =>
                                  setDialogState(() => selectedTPV = v),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: numeroConfirmacionController,
                              decoration: _fieldDecoration(
                                'N° Confirmación (Opcional)',
                                Icons.confirmation_number,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (selectedRole == 'almacenero') ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        value: selectedAlmacen,
                        decoration: _fieldDecoration(
                          'Almacén Asignado',
                          Icons.warehouse,
                        ),
                        items: _almacenes
                            .map(
                              (a) => DropdownMenuItem(
                                value: a.id,
                                child: Text(a.denominacion),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setDialogState(() => selectedAlmacen = v),
                      ),
                    ],
                  ],
                ],
                if (!crearUsuario) ...[
                  const SizedBox(height: 14),
                  _sectionTitle('Rol General'),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: _getRoleNameFromId(selectedRolGeneral),
                    decoration: _fieldDecoration('Rol *', Icons.badge).copyWith(
                      helperText: 'Rol organizacional del trabajador',
                    ),
                    items: [
                      'gerente',
                      'supervisor',
                      'auditor',
                      'vendedor',
                      'almacenero',
                      if (_hasHRPlan) 'recursos_humanos',
                    ]
                        .map(
                          (r) => DropdownMenuItem(
                            value: r,
                            child: Text(_getRoleDisplayName(r)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setDialogState(
                      () => selectedRolGeneral = _getRoleIdFromName(value),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              onPressed: () => _createWorkerFlexible(
                nombres: nombresController.text,
                apellidos: apellidosController.text,
                tipoSalario: tipoSalario,
                salarioHoras: tipoSalario.esPorDia
                    ? 0.0
                    : double.tryParse(salarioHorasController.text) ?? 0.0,
                salarioDia: tipoSalario.esPorDia
                    ? double.tryParse(salarioHorasController.text) ?? 0.0
                    : 0.0,
                crearUsuario: crearUsuario,
                email: emailController.text,
                password: passwordController.text,
                asignarRolEspecifico: asignarRolEspecifico,
                tipoRol: selectedRole,
                tpvId: selectedTPV,
                almacenId: selectedAlmacen,
                numeroConfirmacion: numeroConfirmacionController.text.isEmpty
                    ? null
                    : numeroConfirmacionController.text,
                rolGeneralId: selectedRolGeneral,
              ),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Agregar Trabajador'),
              style: _primaryButtonStyle,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
    );
  }

  InputDecoration _fieldDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 13),
      prefixIcon: Icon(icon, size: 18),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  Widget _checkboxCard({
    required bool value,
    required Color color,
    required String title,
    required String subtitle,
    required ValueChanged<bool?> onChanged,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Checkbox(
              value: value,
              onChanged: onChanged,
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditWorkerDialog(WorkerData worker) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => EditWorkerMultiRoleScreen(
          worker: worker,
          storeId: _storeId!,
          userUuid: _userUuid!,
          tpvs: _tpvs,
          almacenes: _almacenes,
          canDelete: _canDeleteWorkers,
          onSaved: () => _loadWorkersData(),
          onDeleted: () => _loadWorkersData(),
        ),
      ),
    );
  }

  void _showDeleteWorkerDialog(WorkerData worker) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Eliminar Trabajador'),
        content: SizedBox(
          width: 420,
          child: Text(
            '¿Estás seguro de que deseas eliminar a ${worker.nombreCompleto}?\n\n'
            'Se eliminarán todos sus roles en el sistema (gerente, supervisor, '
            'dependiente, almacenero, recursos humanos, auditor).\n\n'
            'Esta acción no se puede deshacer.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => _deleteWorker(worker),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteWorker(WorkerData worker) async {
    if (_storeId == null) {
      _showErrorDialog('Error: No se pudo obtener el ID de la tienda');
      return;
    }
    Navigator.pop(context);
    try {
      final success = await WorkerService.deleteWorker(
        worker.trabajadorId,
        _storeId!,
      );
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Trabajador eliminado exitosamente'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadWorkersData();
      }
    } catch (e) {
      _showErrorDialog('Error al eliminar trabajador: $e');
    }
  }

  void _showAddRoleDialog() {
    final denominacionController = TextEditingController();
    final descripcionController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Agregar Rol', style: TextStyle(fontSize: 17)),
        content: _dialogBody(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: denominacionController,
                decoration: _fieldDecoration(
                  'Nombre del Rol',
                  Icons.admin_panel_settings,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descripcionController,
                decoration: _fieldDecoration(
                  'Descripción (Opcional)',
                  Icons.description,
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => _createRole(
              denominacion: denominacionController.text,
              descripcion: descripcionController.text.isEmpty
                  ? null
                  : descripcionController.text,
            ),
            style: _primaryButtonStyle,
            child: const Text('Crear'),
          ),
        ],
      ),
    );
  }

  Future<void> _createRole({
    required String denominacion,
    String? descripcion,
  }) async {
    if (denominacion.isEmpty) {
      _showErrorDialog('Por favor, ingresa el nombre del rol');
      return;
    }
    if (_storeId == null) {
      _showErrorDialog('Error: No se pudo obtener el ID de la tienda');
      return;
    }
    Navigator.pop(context);
    try {
      final success = await WorkerService.createRole(
        storeId: _storeId!,
        denominacion: denominacion,
        descripcion: descripcion,
      );
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rol creado exitosamente'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadRolesData();
      }
    } catch (e) {
      _showErrorDialog('Error al crear rol: $e');
    }
  }

  void _showEditRoleDialog(WorkerRole role) {
    final denominacionController = TextEditingController(
      text: role.denominacion,
    );
    final descripcionController = TextEditingController(
      text: role.descripcion ?? '',
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          'Editar: ${role.denominacion}',
          style: const TextStyle(fontSize: 17),
        ),
        content: _dialogBody(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: denominacionController,
                decoration: _fieldDecoration(
                  'Nombre del Rol',
                  Icons.admin_panel_settings,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descripcionController,
                decoration: _fieldDecoration(
                  'Descripción (Opcional)',
                  Icons.description,
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => _editRole(
              role: role,
              denominacion: denominacionController.text,
              descripcion: descripcionController.text.isEmpty
                  ? null
                  : descripcionController.text,
            ),
            style: _primaryButtonStyle,
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _editRole({
    required WorkerRole role,
    required String denominacion,
    String? descripcion,
  }) async {
    if (denominacion.isEmpty) {
      _showErrorDialog('Por favor, ingresa el nombre del rol');
      return;
    }
    Navigator.pop(context);
    try {
      final success = await WorkerService.editRole(
        roleId: role.id,
        denominacion: denominacion,
        descripcion: descripcion,
      );
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rol actualizado exitosamente'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadRolesData();
      }
    } catch (e) {
      _showErrorDialog('Error al actualizar rol: $e');
    }
  }

  void _showDeleteRoleDialog(WorkerRole role) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Eliminar Rol'),
        content: SizedBox(
          width: 400,
          child: Text(
            '¿Estás seguro de que deseas eliminar el rol '
            '"${role.denominacion}"?\n\nEsta acción no se puede deshacer.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => _deleteRole(role),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteRole(WorkerRole role) async {
    Navigator.pop(context);
    try {
      final success = await WorkerService.deleteRole(role.id);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rol eliminado exitosamente'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadRolesData();
      }
    } catch (e) {
      _showErrorDialog('Error al eliminar rol: $e');
    }
  }

  Future<void> _showCreateUserDialog(WorkerData worker) async {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    bool obscurePassword = true;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: const Row(
            children: [
              Icon(Icons.person_add, color: AppColors.primary, size: 20),
              SizedBox(width: 10),
              Text('Crear Usuario', style: TextStyle(fontSize: 17)),
            ],
          ),
          content: _dialogBody(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Trabajador:',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        worker.nombreCompleto,
                        style: const TextStyle(fontSize: 15),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _sectionTitle('Credenciales de Acceso'),
                const SizedBox(height: 10),
                TextField(
                  controller: emailController,
                  decoration: _fieldDecoration('Email *', Icons.email)
                      .copyWith(hintText: 'usuario@ejemplo.com'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: obscurePassword,
                  decoration:
                      _fieldDecoration('Contraseña *', Icons.lock).copyWith(
                    hintText: 'Mínimo 6 caracteres',
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                        size: 18,
                      ),
                      onPressed: () => setDialogState(
                        () => obscurePassword = !obscurePassword,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _noticeBox(
                  color: Colors.orange,
                  icon: Icons.info_outline,
                  text: 'Se creará un usuario y se asignará al trabajador.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final email = emailController.text.trim();
                final password = passwordController.text;
                if (email.isEmpty || password.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Por favor completa todos los campos'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                if (!email.contains('@')) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Por favor ingresa un email válido'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                if (password.length < 6) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'La contraseña debe tener al menos 6 caracteres',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                Navigator.pop(context);
                await _createUserForWorker(
                  worker: worker,
                  email: email,
                  password: password,
                );
              },
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Crear Usuario'),
              style: _primaryButtonStyle,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createUserForWorker({
    required WorkerData worker,
    required String email,
    required String password,
  }) async {
    _showBlockingLoader('Creando usuario...');

    try {
      final supabase = Supabase.instance.client;
      String? userUuid;
      bool userAlreadyExisted = false;

      try {
        final authResponse = await supabase.auth.signUp(
          email: email,
          password: password,
          data: {
            'nombres': worker.nombres,
            'apellidos': worker.apellidos,
            'full_name': worker.nombreCompleto,
          },
          emailRedirectTo: null,
        );
        if (authResponse.user == null) {
          throw Exception('Error al registrar usuario en Supabase Auth');
        }
        userUuid = authResponse.user!.id;
      } catch (signUpError) {
        if (signUpError.toString().contains('user_already_exists') ||
            signUpError.toString().contains('User already registered')) {
          try {
            final loginResponse = await supabase.auth.signInWithPassword(
              email: email,
              password: password,
            );
            if (loginResponse.user != null) {
              userUuid = loginResponse.user!.id;
              userAlreadyExisted = true;
            } else {
              throw Exception(
                'No se pudo obtener el UUID del usuario existente',
              );
            }
          } catch (loginError) {
            throw Exception(
              'El email ya está registrado pero no se pudo autenticar. '
              'Verifica la contraseña.',
            );
          }
        } else {
          rethrow;
        }
      }

      if (userUuid == null) {
        throw Exception('No se pudo obtener el UUID del usuario');
      }

      final success = await WorkerService.updateWorkerUUID(
        workerId: worker.trabajadorId,
        storeId: _storeId!,
        uuid: userUuid,
      );
      if (!success) throw Exception('Error al actualizar trabajador con UUID');

      if (mounted) Navigator.pop(context);

      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: Row(
            children: [
              Icon(
                Icons.check_circle,
                color: userAlreadyExisted ? Colors.orange : Colors.green,
                size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                userAlreadyExisted ? 'Usuario Vinculado' : 'Usuario Creado',
                style: const TextStyle(fontSize: 17),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  userAlreadyExisted
                      ? 'El trabajador ${worker.nombreCompleto} ha sido '
                          'vinculado a un usuario existente.'
                      : 'Usuario creado exitosamente para '
                          '${worker.nombreCompleto}.',
                ),
                const SizedBox(height: 12),
                _noticeBox(
                  color: userAlreadyExisted ? Colors.orange : Colors.green,
                  icon: userAlreadyExisted
                      ? Icons.warning_amber
                      : Icons.check_circle_outline,
                  text: userAlreadyExisted
                      ? 'El usuario ya existía en el sistema y ha sido '
                          'vinculado exitosamente al trabajador.\nEmail: $email'
                      : 'Email: $email',
                ),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: _primaryButtonStyle,
              child: const Text('Aceptar'),
            ),
          ],
        ),
      );
      await _loadWorkersData();
    } catch (e) {
      if (mounted) Navigator.pop(context);
      print('❌ Error al crear usuario: $e');
      _showErrorDialog('Error al crear usuario: $e');
    }
  }

  Future<void> _showSyncUUIDDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.sync, color: AppColors.primary, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Sincronizar UUID desde Roles',
                style: TextStyle(fontSize: 17),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Esta acción buscará trabajadores que:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text('• No tienen UUID asignado en la tabla trabajadores'),
              const Text(
                '• Tienen roles activos (gerente, supervisor, vendedor, '
                'almacenero)',
              ),
              const Text('• El UUID se copiará desde la tabla del rol'),
              const SizedBox(height: 14),
              _noticeBox(
                color: Colors.blue,
                icon: Icons.info_outline,
                text: 'Esto permitirá que estos trabajadores puedan tener '
                    'múltiples roles.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.sync, size: 16),
            label: const Text('Sincronizar'),
            style: _primaryButtonStyle,
          ),
        ],
      ),
    );

    if (confirmed != true || _storeId == null) return;

    try {
      if (mounted) _showBlockingLoader('Sincronizando UUID...');

      final result = await WorkerService.assignUUIDFromRoles(_storeId);

      if (!mounted) return;
      Navigator.pop(context);

      if (result['success'] == true) {
        final total = result['total'] ?? 0;
        final results = (result['results'] as List<dynamic>?) ?? const [];

        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            title: Row(
              children: [
                Icon(
                  total > 0 ? Icons.check_circle : Icons.info_outline,
                  color: total > 0 ? Colors.green : Colors.orange,
                  size: 22,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Resultado de Sincronización',
                    style: TextStyle(fontSize: 17),
                  ),
                ),
              ],
            ),
            content: _dialogBody(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result['message'] ?? 'Sincronización completada',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (total > 0) ...[
                    const SizedBox(height: 14),
                    const Text(
                      'Trabajadores actualizados:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...results.map(
                      (worker) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Icon(
                              Icons.person,
                              size: 15,
                              color: Colors.green.shade700,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${worker['nombres']} ${worker['apellidos']}',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                worker['rol_asignado'] ?? '',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.blue.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: _primaryButtonStyle,
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );

        if (total > 0) await _loadWorkersData();
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showBlockingLoader(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                    strokeWidth: 2.5,
                  ),
                ),
                const SizedBox(height: 14),
                Text(message, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =====================================================
  // HR HELPERS
  // =====================================================

  Widget _buildDateField({
    required String label,
    required DateTime date,
    required VoidCallback onTap,
  }) {
    final fmt = DateFormat('dd/MM/yyyy');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 12),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          prefixIcon: const Icon(Icons.calendar_today, size: 15),
          prefixIconConstraints: const BoxConstraints(minWidth: 34),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 12,
          ),
        ),
        child: Text(fmt.format(date), style: const TextStyle(fontSize: 13)),
      ),
    );
  }

  Future<void> _selectDate(BuildContext context, bool isFromDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isFromDate ? _fechaDesde : _fechaHasta,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        if (isFromDate) {
          _fechaDesde = picked;
          if (_fechaDesde.isAfter(_fechaHasta)) _fechaHasta = _fechaDesde;
        } else {
          _fechaHasta = picked;
          if (_fechaHasta.isBefore(_fechaDesde)) _fechaDesde = _fechaHasta;
        }
      });
    }
  }

  Future<void> _loadHRData() async {
    if (_storeId == null) return;
    setState(() => _isLoadingShifts = true);
    try {
      final shifts = await HRService.getShiftsWithWorkers(
        idTienda: _storeId!,
        fechaDesde: _fechaDesde,
        fechaHasta: _fechaHasta,
      );
      final summary = await HRService.getHRSummary(
        idTienda: _storeId!,
        fechaDesde: _fechaDesde,
        fechaHasta: _fechaHasta,
      );
      setState(() {
        _shifts = shifts;
        _hrSummary = summary;
        _isLoadingShifts = false;
      });
    } catch (e) {
      print('❌ Error cargando datos de RR.HH.: $e');
      setState(() => _isLoadingShifts = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar datos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildShiftCard(ShiftWithWorkers shift) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final hasWorkers = shift.trabajadores.isNotEmpty;
    // Fechas UTC convertidas a hora de La Habana (UTC-4)
    final fechaAperturaLocal =
        shift.fechaApertura.toUtc().subtract(const Duration(hours: 4));
    final fechaCierreLocal =
        shift.fechaCierre?.toUtc().subtract(const Duration(hours: 4));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: shift.isOpen
                  ? Colors.green.withOpacity(0.1)
                  : Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              shift.isOpen ? Icons.lock_open : Icons.lock,
              color: shift.isOpen ? Colors.green : Colors.grey,
              size: 17,
            ),
          ),
          title: Text(
            'Turno #${shift.turnoId} - ${shift.tpvDenominacion}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Wrap(
              spacing: 14,
              children: [
                Text(
                  'Vendedor: ${shift.vendedorNombre}',
                  style: const TextStyle(fontSize: 11.5),
                ),
                Text(
                  'Apertura: ${dateFormat.format(fechaAperturaLocal)}',
                  style: const TextStyle(fontSize: 11.5),
                ),
                if (!shift.isOpen && fechaCierreLocal != null)
                  Text(
                    'Cierre: ${dateFormat.format(fechaCierreLocal)}',
                    style: const TextStyle(fontSize: 11.5),
                  ),
              ],
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: hasWorkers
                      ? Colors.blue.withOpacity(0.1)
                      : Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${shift.trabajadores.length} trabajador'
                  '${shift.trabajadores.length != 1 ? 'es' : ''}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: hasWorkers ? Colors.blue : Colors.orange,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                shift.duracionTurno,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.expand_more,
                size: 20,
                color: AppColors.textSecondary,
              ),
            ],
          ),
          children: [
            if (hasWorkers) ...[
              const Divider(),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Trabajadores del Turno',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 10),
              ...shift.trabajadores.map((w) => _buildWorkerHoursCard(w)),
            ] else
              const Padding(
                padding: EdgeInsets.all(10),
                child: Text(
                  'No hay trabajadores registrados en este turno',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkerHoursCard(ShiftWorkerHours worker) {
    final timeFormat = DateFormat('HH:mm');
    final horaEntradaLocal =
        worker.horaEntrada.toUtc().subtract(const Duration(hours: 4));
    final horaSalidaLocal =
        worker.horaSalida?.toUtc().subtract(const Duration(hours: 4));

    return Tooltip(
      message: 'Click para editar las horas trabajadas',
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        onTap: () => _showEditHoursDialog(worker),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: AppColors.primary.withOpacity(0.1),
                child: Text(
                  worker.trabajadorNombre.substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          worker.trabajadorNombre,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        if (worker.isManuallyEdited) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade100,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.amber.shade400),
                            ),
                            child: Text(
                              'MANUAL',
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Row(
                      children: [
                        Text(
                          worker.rolNombre,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(Icons.login, size: 10, color: Colors.grey[500]),
                        const SizedBox(width: 3),
                        Text(
                          timeFormat.format(horaEntradaLocal),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                        if (worker.horaSalida != null) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.logout, size: 10, color: Colors.grey[500]),
                          const SizedBox(width: 3),
                          Text(
                            timeFormat.format(horaSalidaLocal!),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: worker.isWorking
                          ? Colors.green.withOpacity(0.1)
                          : Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      worker.horasTrabajadasFormatted,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: worker.isWorking ? Colors.green : Colors.blue,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    worker.tarifaFormatted,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    worker.salarioTotalFormatted,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              const Icon(Icons.edit, size: 14, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showEditHoursDialog(ShiftWorkerHours worker) async {
    final hoursController = TextEditingController(
      text: worker.horasTrabajadas?.toStringAsFixed(2) ?? '0.00',
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.edit, color: AppColors.primary, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Editar Horas Trabajadas',
                style: TextStyle(fontSize: 17),
              ),
            ),
          ],
        ),
        content: _dialogBody(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      worker.trabajadorNombre,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.blue.shade900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${worker.rolNombre} · ${worker.tarifaFormatted}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: hoursController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: _fieldDecoration(
                  'Horas Trabajadas',
                  Icons.access_time,
                ).copyWith(hintText: '0.00', suffixText: 'horas'),
                autofocus: true,
              ),
              if (worker.esPorDia)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _noticeBox(
                    color: Colors.orange,
                    icon: Icons.info_outline,
                    text: 'Este trabajador cobra por día: las horas '
                        'registradas no modifican su salario.',
                  ),
                ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Salario Total:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.green.shade900,
                      ),
                    ),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: hoursController,
                      builder: (context, value, child) {
                        final hours = double.tryParse(value.text) ?? 0.0;
                        // Modalidad día: la jornada se paga completa, así que
                        // ajustar las horas no altera el importe.
                        final total = worker.esPorDia
                            ? worker.salarioHora
                            : hours * worker.salarioHora;
                        return Text(
                          '\$${total.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _noticeBox(
                color: Colors.orange,
                icon: Icons.warning_amber,
                text: 'Este cambio quedará registrado como edición manual.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              final newHours = double.tryParse(hoursController.text);
              if (newHours == null || newHours < 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Por favor ingresa un valor válido'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              Navigator.pop(context, true);
            },
            icon: const Icon(Icons.save, size: 16),
            label: const Text('Guardar'),
            style: _primaryButtonStyle,
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      final newHours = double.tryParse(hoursController.text);
      if (newHours != null && _userUuid != null) {
        await _updateWorkerHours(worker, newHours);
      }
    }
  }

  Future<void> _updateWorkerHours(
    ShiftWorkerHours worker,
    double newHours,
  ) async {
    try {
      _showBlockingLoader('Actualizando horas...');
      await HRService.updateWorkerHoursManually(
        idRegistro: worker.id,
        newHours: newHours,
        userUuid: _userUuid!,
        horaEntrada: worker.horaEntrada,
        currentHours: worker.horasTrabajadas ?? 0.0,
        horaSalida: worker.horaSalida,
      );
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Horas actualizadas: ${newHours.toStringAsFixed(2)}h'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        await _loadHRData();
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      print('❌ Error actualizando horas: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al actualizar horas: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // =====================================================
  // CREATE WORKER FLEXIBLE
  // =====================================================

  Future<void> _createWorkerFlexible({
    required String nombres,
    required String apellidos,
    double salarioHoras = 0.0,
    double salarioDia = 0.0,
    TipoSalario tipoSalario = TipoSalario.hora,
    required bool crearUsuario,
    String? email,
    String? password,
    required bool asignarRolEspecifico,
    String? tipoRol,
    int? tpvId,
    int? almacenId,
    String? numeroConfirmacion,
    int? rolGeneralId,
  }) async {
    if (nombres.isEmpty || apellidos.isEmpty) {
      _showErrorDialog('Por favor, ingresa nombres y apellidos');
      return;
    }
    if (_storeId == null) {
      _showErrorDialog('Error: No se pudo obtener el ID de la tienda');
      return;
    }
    if (crearUsuario) {
      if (email == null ||
          email.isEmpty ||
          password == null ||
          password.isEmpty) {
        _showErrorDialog('Por favor, completa email y contraseña');
        return;
      }
      if (!email.contains('@')) {
        _showErrorDialog('Por favor, ingresa un email válido');
        return;
      }
      if (password.length < 6) {
        _showErrorDialog('La contraseña debe tener al menos 6 caracteres');
        return;
      }
      if (asignarRolEspecifico && tipoRol == null) {
        _showErrorDialog('Por favor, selecciona un rol específico');
        return;
      }
    } else {
      if (rolGeneralId == null) {
        _showErrorDialog('Por favor, selecciona un rol general');
        return;
      }
    }

    Navigator.pop(context);

    _showBlockingLoader(
      crearUsuario
          ? 'Registrando usuario y creando trabajador...'
          : 'Creando trabajador...',
    );

    try {
      String? userUuid;
      bool userAlreadyExisted = false;

      if (crearUsuario) {
        final supabase = Supabase.instance.client;
        try {
          final authResponse = await supabase.auth.signUp(
            email: email!,
            password: password!,
            data: {
              'nombres': nombres,
              'apellidos': apellidos,
              'full_name': '$nombres $apellidos',
            },
            emailRedirectTo: null,
          );
          if (authResponse.user == null) {
            throw Exception('Error al registrar usuario en Supabase Auth');
          }
          userUuid = authResponse.user!.id;
        } catch (signUpError) {
          if (signUpError.toString().contains('user_already_exists') ||
              signUpError.toString().contains('User already registered')) {
            try {
              final loginResponse = await supabase.auth.signInWithPassword(
                email: email!,
                password: password!,
              );
              if (loginResponse.user != null) {
                userUuid = loginResponse.user!.id;
                userAlreadyExisted = true;
              } else {
                throw Exception(
                  'No se pudo obtener el UUID del usuario existente',
                );
              }
            } catch (loginError) {
              throw Exception(
                'El email ya está registrado pero no se pudo autenticar. '
                'Verifica la contraseña.',
              );
            }
          } else {
            rethrow;
          }
        }

        if (userUuid == null) {
          throw Exception('No se pudo obtener el UUID del usuario');
        }

        if (asignarRolEspecifico && tipoRol != null) {
          final success = await WorkerService.createWorker(
            storeId: _storeId!,
            nombres: nombres,
            apellidos: apellidos,
            tipoRol: tipoRol,
            usuarioUuid: userUuid,
            salarioHoras: salarioHoras,
            salarioDia: salarioDia,
            tipoSalario: tipoSalario,
            tpvId: tpvId,
            almacenId: almacenId,
            numeroConfirmacion: numeroConfirmacion,
          );
          if (!success) {
            throw Exception('Error al crear trabajador con rol específico');
          }
        } else {
          final success = await WorkerService.createWorkerBasic(
            storeId: _storeId!,
            nombres: nombres,
            apellidos: apellidos,
            usuarioUuid: userUuid,
            salarioHoras: salarioHoras,
            salarioDia: salarioDia,
            tipoSalario: tipoSalario,
            rolId: rolGeneralId,
          );
          if (!success) throw Exception('Error al crear trabajador');
        }
      } else {
        final success = await WorkerService.createWorkerBasic(
          storeId: _storeId!,
          nombres: nombres,
          apellidos: apellidos,
          usuarioUuid: null,
          rolId: rolGeneralId,
          salarioHoras: salarioHoras,
          salarioDia: salarioDia,
          tipoSalario: tipoSalario,
        );
        if (!success) throw Exception('Error al crear trabajador');
      }

      Navigator.pop(context);

      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: Row(
            children: [
              Icon(
                Icons.check_circle,
                color: userAlreadyExisted ? Colors.orange : Colors.green,
                size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                userAlreadyExisted
                    ? 'Trabajador Vinculado'
                    : 'Trabajador Creado',
                style: const TextStyle(fontSize: 17),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'El trabajador $nombres $apellidos ha sido creado '
                  'exitosamente.',
                ),
                const SizedBox(height: 12),
                if (crearUsuario)
                  _noticeBox(
                    color: userAlreadyExisted ? Colors.orange : Colors.green,
                    icon: userAlreadyExisted
                        ? Icons.warning_amber
                        : Icons.check_circle_outline,
                    text: userAlreadyExisted
                        ? 'El usuario ya existía en el sistema y ha sido '
                            'vinculado exitosamente al trabajador.\n'
                            'Email: $email'
                        : 'Usuario creado.\nEmail: $email',
                  )
                else
                  _noticeBox(
                    color: Colors.orange,
                    icon: Icons.info_outline,
                    text: 'Sin usuario de acceso. Puedes crear uno después '
                        'desde la tabla de personal.',
                  ),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: _primaryButtonStyle,
              child: const Text('Aceptar'),
            ),
          ],
        ),
      );

      await _loadWorkersData();
    } catch (e) {
      Navigator.pop(context);
      print('❌ Error al crear trabajador: $e');
      _showErrorDialog('Error al crear trabajador: $e');
    }
  }

  // =====================================================
  // PDF EXPORT
  // =====================================================

  Future<void> _exportHRReportToPDF() async {
    if (_shifts.isEmpty || _hrSummary == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay datos para exportar'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    try {
      _showBlockingLoader('Generando PDF...');
      final pdfBytes = await _generateHRPDF();
      if (mounted) Navigator.pop(context);

      final dateStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      // En web el navegador descarga el archivo directamente.
      web_download.downloadFileWeb(
        pdfBytes,
        'Desglose_Salarios_$dateStr.pdf',
        'application/pdf',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ PDF generado y descargado exitosamente'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      print('❌ Error al exportar PDF: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al generar PDF: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<Uint8List> _generateHRPDF() async {
    final pdf = pw.Document();
    final dateFormat = DateFormat('dd/MM/yyyy');
    final timeFormat = DateFormat('HH:mm');
    final now = DateTime.now();

    final trabajadoresMap = <int, Map<String, dynamic>>{};
    for (final shift in _shifts) {
      for (final worker in shift.trabajadores) {
        if (!trabajadoresMap.containsKey(worker.idTrabajador)) {
          trabajadoresMap[worker.idTrabajador] = {
            'nombre': worker.trabajadorNombre,
            'rol': worker.rolNombre,
            'salarioHora': worker.salarioHora,
            'totalHoras': 0.0,
            'totalSalario': 0.0,
          };
        }
        if (worker.horasTrabajadas != null) {
          trabajadoresMap[worker.idTrabajador]!['totalHoras'] +=
              worker.horasTrabajadas!;
          trabajadoresMap[worker.idTrabajador]!['totalSalario'] +=
              worker.salarioTotal;
        }
      }
    }
    final trabajadoresList = trabajadoresMap.values.toList();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'DESGLOSE DE SALARIOS POR TRABAJADORES',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'Periodo: ${dateFormat.format(_fechaDesde)} - '
                  '${dateFormat.format(_fechaHasta)}',
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Generado: ${dateFormat.format(now)} '
                  '${timeFormat.format(now)}',
                  style: const pw.TextStyle(fontSize: 11),
                ),
                pw.SizedBox(height: 16),
              ],
            ),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey200,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'RESUMEN GENERAL',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Total Turnos: ${_hrSummary!.totalTurnos}'),
                      pw.Text(
                        'Total Trabajadores: '
                        '${_hrSummary!.totalTrabajadores}',
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Total Horas: '
                        '${_hrSummary!.totalHorasTrabajadas.toStringAsFixed(2)}h',
                      ),
                      pw.Text(
                        'Total Salarios: '
                        '${_hrSummary!.totalSalariosFormatted}',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              'DETALLE POR TRABAJADOR',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 10),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(2),
                2: const pw.FlexColumnWidth(1.5),
                3: const pw.FlexColumnWidth(1.5),
                4: const pw.FlexColumnWidth(2),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  children: ['Trabajador', 'Rol', 'Horas', '\$/Hora', 'Total']
                      .map(
                        (h) => pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(
                            h,
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                ...trabajadoresList.map(
                  (t) => pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(
                          t['nombre'],
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(
                          t['rol'],
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(
                          '${t['totalHoras'].toStringAsFixed(2)}h',
                          style: const pw.TextStyle(fontSize: 8),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(
                          '\$${t['salarioHora'].toStringAsFixed(2)}',
                          style: const pw.TextStyle(fontSize: 8),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(
                          '\$${t['totalSalario'].toStringAsFixed(2)}',
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Text(
              'DESGLOSE POR TURNOS',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 10),
            ..._shifts.map((shift) {
              final fechaAperturaLocal =
                  shift.fechaApertura.toUtc().subtract(const Duration(hours: 4));
              final fechaCierreLocal =
                  shift.fechaCierre?.toUtc().subtract(const Duration(hours: 4));
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.all(7),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey100,
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'Turno #${shift.turnoId} - ${shift.tpvDenominacion}',
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          'Vendedor: ${shift.vendedorNombre}',
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(left: 8),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Apertura: '
                          '${dateFormat.format(fechaAperturaLocal)} '
                          '${timeFormat.format(fechaAperturaLocal)}',
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                        if (!shift.isOpen && fechaCierreLocal != null)
                          pw.Text(
                            'Cierre: '
                            '${dateFormat.format(fechaCierreLocal)} '
                            '${timeFormat.format(fechaCierreLocal)}',
                            style: const pw.TextStyle(fontSize: 8),
                          ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  if (shift.trabajadores.isNotEmpty)
                    pw.Table(
                      border: pw.TableBorder.all(
                        color: PdfColors.grey300,
                        width: 0.5,
                      ),
                      columnWidths: {
                        0: const pw.FlexColumnWidth(3),
                        1: const pw.FlexColumnWidth(1.5),
                        2: const pw.FlexColumnWidth(1.5),
                        3: const pw.FlexColumnWidth(1.5),
                        4: const pw.FlexColumnWidth(1.5),
                      },
                      children: [
                        pw.TableRow(
                          decoration: const pw.BoxDecoration(
                            color: PdfColors.grey200,
                          ),
                          children: [
                            'Trabajador',
                            'Entrada',
                            'Salida',
                            'Horas',
                            'Salario',
                          ]
                              .map(
                                (h) => pw.Padding(
                                  padding: const pw.EdgeInsets.all(4),
                                  child: pw.Text(
                                    h,
                                    style: pw.TextStyle(
                                      fontWeight: pw.FontWeight.bold,
                                      fontSize: 7,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                        ...shift.trabajadores.map((worker) {
                          final entradaLocal = worker.horaEntrada
                              .toUtc()
                              .subtract(const Duration(hours: 4));
                          final salidaLocal = worker.horaSalida
                              ?.toUtc()
                              .subtract(const Duration(hours: 4));
                          return pw.TableRow(
                            children: [
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(4),
                                child: pw.Text(
                                  worker.trabajadorNombre,
                                  style: const pw.TextStyle(fontSize: 7),
                                ),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(4),
                                child: pw.Text(
                                  timeFormat.format(entradaLocal),
                                  style: const pw.TextStyle(fontSize: 7),
                                  textAlign: pw.TextAlign.center,
                                ),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(4),
                                child: pw.Text(
                                  worker.horaSalida != null
                                      ? timeFormat.format(salidaLocal!)
                                      : 'En turno',
                                  style: const pw.TextStyle(fontSize: 7),
                                  textAlign: pw.TextAlign.center,
                                ),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(4),
                                child: pw.Text(
                                  worker.horasTrabajadasFormatted,
                                  style: const pw.TextStyle(fontSize: 7),
                                  textAlign: pw.TextAlign.center,
                                ),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(4),
                                child: pw.Text(
                                  worker.salarioTotalFormatted,
                                  style: const pw.TextStyle(fontSize: 7),
                                  textAlign: pw.TextAlign.right,
                                ),
                              ),
                            ],
                          );
                        }),
                      ],
                    ),
                  pw.SizedBox(height: 12),
                ],
              );
            }),
          ];
        },
      ),
    );
    return pdf.save();
  }
}

/// Etiqueta compacta de tab: icono e texto en una sola linea para ahorrar
/// altura vertical (en movil el Tab apila icono sobre texto).
class _TabLabel extends StatelessWidget {
  final IconData icon;
  final String text;

  const _TabLabel({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15),
        const SizedBox(width: 7),
        Text(text),
      ],
    );
  }
}
