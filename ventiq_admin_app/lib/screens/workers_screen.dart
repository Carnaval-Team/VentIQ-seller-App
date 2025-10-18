import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/admin_bottom_navigation.dart';
import '../models/worker_models.dart';
import '../services/worker_service.dart';
import '../services/store_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/navigation_guard.dart';
import '../utils/screen_protection_mixin.dart';
import 'edit_worker_multi_role_screen.dart';

class WorkersScreen extends StatefulWidget {
  const WorkersScreen({super.key});

  @override
  State<WorkersScreen> createState() => _WorkersScreenState();
}

class _WorkersScreenState extends State<WorkersScreen>
    with TickerProviderStateMixin, ScreenProtectionMixin {
  @override
  String get protectedRoute => '/workers';
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Datos de trabajadores
  List<WorkerData> _workers = [];
  List<WorkerData> _deletedWorkers = []; // 🆕 Trabajadores eliminados
  List<WorkerRole> _roles = [];
  List<TPVData> _tpvs = [];
  List<AlmacenData> _almacenes = [];
  WorkerStatistics? _statistics;

  // Estados de carga
  bool _isLoadingWorkers = true;
  bool _isLoadingRoles = true;
  bool _isLoadingDeleted = true; // 🆕 Estado de carga de eliminados

  // Filtros
  String _selectedRole = 'Todos';

  // Datos de la tienda y usuario
  int? _storeId;
  String? _userUuid;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
    ); // Solo Personal y Roles
    _initializeData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    try {
      // Obtener datos de la tienda y usuario
      final storeData = await StoreService.getWorkerRequiredData();
      if (storeData == null) {
        _showErrorDialog(
          'No se pudieron obtener los datos de la tienda. Por favor, inicia sesión nuevamente.',
        );
        return;
      }

      setState(() {
        _storeId = storeData['storeId'];
        _userUuid = storeData['userUuid'];
      });

      // Cargar datos iniciales
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Gestión de Personal',
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
          FutureBuilder<bool>(
            future: NavigationGuard.canPerformAction('worker.create'),
            builder: (context, snapshot) {
              if (snapshot.data == true) {
                return IconButton(
                  icon: const Icon(Icons.person_add, color: Colors.white),
                  onPressed: _showAddWorkerDialog,
                  tooltip: 'Agregar Trabajador',
                );
              }
              return const SizedBox.shrink();
            },
          ),
          IconButton(
            icon: const Icon(Icons.sync, color: Colors.white),
            onPressed: _showSyncUUIDDialog,
            tooltip: 'Sincronizar UUID desde Roles',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () => _initializeData(),
            tooltip: 'Actualizar',
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
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Personal', icon: Icon(Icons.people, size: 18)),
            Tab(
              text: 'Roles',
              icon: Icon(Icons.admin_panel_settings, size: 18),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildWorkersTab(), _buildRolesTab()],
      ),
      endDrawer: const AdminDrawer(),
      bottomNavigationBar: AdminBottomNavigation(
        currentIndex: 3,
        onTap: _onBottomNavTap,
      ),
    );
  }

  Widget _buildWorkersTab() {
    if (_isLoadingWorkers) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: 16),
            Text(
              'Cargando trabajadores...',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    final filteredWorkers =
        _workers.where((worker) {
          final matchesSearch =
              _searchQuery.isEmpty ||
              worker.nombreCompleto.toLowerCase().contains(
                _searchQuery.toLowerCase(),
              ) ||
              worker.rolNombre.toLowerCase().contains(
                _searchQuery.toLowerCase(),
              );

          final matchesRole =
              _selectedRole == 'Todos' || worker.tipoRol == _selectedRole;

          return matchesSearch && matchesRole;
        }).toList();

    return Column(
      children: [
        _buildSearchAndFilters(),
        if (_statistics != null) _buildStatisticsCard(),
        Expanded(
          child:
              filteredWorkers.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredWorkers.length,
                    itemBuilder: (context, index) {
                      final worker = filteredWorkers[index];
                      return _buildWorkerCard(worker);
                    },
                  ),
        ),
      ],
    );
  }

  Widget _buildSearchAndFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Buscar por nombre o rol...',
              prefixIcon: const Icon(Icons.search, color: AppColors.primary),
              suffixIcon:
                  _searchQuery.isNotEmpty
                      ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                      : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _selectedRole,
            decoration: InputDecoration(
              labelText: 'Filtrar por rol',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            items:
                [
                  'Todos',
                  'gerente',
                  'supervisor',
                  'vendedor',
                  'almacenero',
                ].map((role) {
                  return DropdownMenuItem(
                    value: role,
                    child: Text(_getRoleDisplayName(role)),
                  );
                }).toList(),
            onChanged: (value) => setState(() => _selectedRole = value!),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkerCard(WorkerData worker) {
    // Obtener el rol con mayor jerarquía
    final rolPrincipal = _getRolPrincipal(worker);
    final nombreRolPrincipal = _getRoleDisplayName(rolPrincipal);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showWorkerDetails(worker),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: _getRoleColor(rolPrincipal).withOpacity(0.1),
                child: Text(
                  worker.nombres.substring(0, 1).toUpperCase(),
                  style: TextStyle(
                    color: _getRoleColor(rolPrincipal),
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      worker.nombreCompleto,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      nombreRolPrincipal,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 🆕 NUEVO: Etiquetas múltiples de roles
                    _buildRoleTags(worker),
                    const SizedBox(height: 4),
                    // Mostrar detalles de vendedor si es vendedor
                    if (worker.esVendedor && worker.tpvDenominacion != null)
                      Row(
                        children: [
                          Icon(
                            Icons.point_of_sale,
                            size: 14,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'TPV: ${worker.tpvDenominacion}',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    // Mostrar detalles de almacenero si es almacenero
                    if (worker.esAlmacenero &&
                        worker.almacenDenominacion != null)
                      Row(
                        children: [
                          Icon(
                            Icons.warehouse,
                            size: 14,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Almacén: ${worker.almacenDenominacion}',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Botón para crear usuario si no tiene UUID
                  if (!worker.tieneUsuario)
                    IconButton(
                      icon: const Icon(Icons.person_add, size: 18),
                      onPressed: () => _showCreateUserDialog(worker),
                      tooltip: 'Crear Usuario',
                      color: Colors.green,
                    ),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 18),
                    onPressed: () => _showEditWorkerDialog(worker),
                    tooltip: 'Editar',
                    color: AppColors.primary,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, size: 18),
                    onPressed: () => _showDeleteWorkerDialog(worker),
                    tooltip: 'Eliminar',
                    color: Colors.red,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 64, color: AppColors.textSecondary),
          SizedBox(height: 16),
          Text(
            'No se encontraron trabajadores',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
          SizedBox(height: 8),
          Text(
            'Intenta ajustar los filtros de búsqueda',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  // Método para obtener el rol con mayor jerarquía
  String _getRolPrincipal(WorkerData worker) {
    // Jerarquía: gerente > supervisor > almacenero > vendedor
    if (worker.esGerente) return 'gerente';
    if (worker.esSupervisor) return 'supervisor';
    if (worker.esAlmacenero) return 'almacenero';
    if (worker.esVendedor) return 'vendedor';

    // Si no tiene roles de app, usar el rol general (seg_roll)
    // Retornar el tipoRol o rolNombre si existe
    if (worker.tipoRol.isNotEmpty && worker.tipoRol != 'sin_rol') {
      return worker.tipoRol;
    }

    // Si tiene rolNombre, usarlo
    if (worker.rolNombre.isNotEmpty) {
      return worker.rolNombre.toLowerCase();
    }

    // Por defecto, retornar 'sin_rol'
    return 'sin_rol';
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case 'gerente':
        return Colors.purple;
      case 'supervisor':
        return Colors.orange;
      case 'vendedor':
        return AppColors.primary;
      case 'almacenero':
        return Colors.green;
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
      case 'vendedor':
        return 'Vendedor';
      case 'almacenero':
        return 'Almacenero';
      case 'todos':
        return 'Todos';
      case 'sin_rol':
        return 'Trabajador';
      default:
        // Capitalizar primera letra para roles personalizados
        if (role.isEmpty) return 'Trabajador';
        return role[0].toUpperCase() + role.substring(1);
    }
  }

  // 🆕 NUEVO: Widget para mostrar etiquetas múltiples de roles
  Widget _buildRoleTags(WorkerData worker) {
    // rolesActivos ya incluye 'usuario' si tieneUsuario es true
    final tags = worker.rolesActivos;

    if (tags.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: tags.map((tag) => _buildRoleTag(tag)).toList(),
    );
  }

  // 🆕 NUEVO: Widget para construir una etiqueta individual de rol
  Widget _buildRoleTag(String role) {
    final config = _getRoleTagConfig(role);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: config['color'].withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: config['color'].withOpacity(0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(config['icon'], size: 12, color: config['color']),
          const SizedBox(width: 4),
          Text(
            config['label'],
            style: TextStyle(
              color: config['color'],
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // 🆕 NUEVO: Configuración de colores e iconos para cada tipo de rol
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
          'label': 'Vendedor',
          'icon': Icons.point_of_sale,
          'color': AppColors.primary,
        };
      case 'supervisor':
        return {
          'label': 'Supervisor',
          'icon': Icons.supervisor_account,
          'color': Colors.orange,
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
      default:
        return {'label': role, 'icon': Icons.label, 'color': Colors.grey};
    }
  }

  // Método para mostrar estadísticas
  Widget _buildStatisticsCard() {
    if (_statistics == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Estadísticas del Personal',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  'Total',
                  _statistics!.totalTrabajadores.toString(),
                  Icons.people,
                  AppColors.primary,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  'Gerentes',
                  _statistics!.totalGerentes.toString(),
                  Icons.admin_panel_settings,
                  Colors.purple,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  'Vended.',
                  _statistics!.totalVendedores.toString(),
                  Icons.point_of_sale,
                  AppColors.primary,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  'Almacen.',
                  _statistics!.totalAlmaceneros.toString(),
                  Icons.warehouse,
                  Colors.green,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // Método para mostrar diálogo de error
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Error'),
            content: Text(message),
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
    showDialog(
      context: context,
      builder:
          (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
              width: MediaQuery.of(context).size.width * 0.9,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: _getRoleColor(
                          worker.tipoRol,
                        ).withOpacity(0.1),
                        child: Text(
                          worker.nombres.substring(0, 1).toUpperCase(),
                          style: TextStyle(
                            color: _getRoleColor(worker.tipoRol),
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              worker.nombreCompleto,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              worker.rolNombre,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
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
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: _buildInfoCard(
                          'Rol',
                          _getRoleDisplayName(worker.tipoRol),
                          Icons.admin_panel_settings,
                          _getRoleColor(worker.tipoRol),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildInfoCard(
                          'Fecha Creación',
                          '${worker.fechaCreacion.day}/${worker.fechaCreacion.month}/${worker.fechaCreacion.year}',
                          Icons.calendar_today,
                          AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  if (worker.tipoRol == 'vendedor' &&
                      worker.tpvDenominacion != null)
                    Column(
                      children: [
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildInfoCard(
                                'TPV Asignado',
                                worker.tpvDenominacion!,
                                Icons.point_of_sale,
                                AppColors.primary,
                              ),
                            ),
                            if (worker.numeroConfirmacion != null)
                              const SizedBox(width: 12),
                            if (worker.numeroConfirmacion != null)
                              Expanded(
                                child: _buildInfoCard(
                                  'N° Confirmación',
                                  worker.numeroConfirmacion!,
                                  Icons.confirmation_number,
                                  Colors.orange,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  if (worker.tipoRol == 'almacenero' &&
                      worker.almacenDenominacion != null)
                    Column(
                      children: [
                        const SizedBox(height: 12),
                        _buildInfoCard(
                          'Almacén Asignado',
                          worker.almacenDenominacion!,
                          Icons.warehouse,
                          Colors.green,
                        ),
                        if (worker.almacenDireccion != null)
                          const SizedBox(height: 8),
                        if (worker.almacenDireccion != null)
                          _buildInfoCard(
                            'Dirección',
                            worker.almacenDireccion!,
                            Icons.location_on,
                            Colors.grey,
                          ),
                      ],
                    ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _showEditWorkerDialog(worker);
                        },
                        icon: const Icon(Icons.edit),
                        label: const Text('Editar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                        label: const Text('Cerrar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildInfoCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // 🆕 Diálogo mejorado para agregar trabajador
  void _showAddWorkerDialog() {
    final nombresController = TextEditingController();
    final apellidosController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final numeroConfirmacionController = TextEditingController();
    bool crearUsuario = false;
    bool asignarRolEspecifico = false;
    String? selectedRole;
    int? selectedTPV;
    int? selectedAlmacen;
    int? selectedRolGeneral;
    bool _obscurePassword = true;

    showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: Row(
                    children: [
                      Icon(Icons.person_add, color: AppColors.primary),
                      const SizedBox(width: 12),
                      const Text('Agregar Trabajador'),
                    ],
                  ),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Información básica
                        const Text(
                          'Información Básica',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: nombresController,
                          decoration: const InputDecoration(
                            labelText: 'Nombres *',
                            prefixIcon: Icon(Icons.person),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: apellidosController,
                          decoration: const InputDecoration(
                            labelText: 'Apellidos *',
                            prefixIcon: Icon(Icons.person_outline),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 16),

                        // Opción de crear usuario
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            children: [
                              Checkbox(
                                value: crearUsuario,
                                onChanged: (value) {
                                  setDialogState(() {
                                    crearUsuario = value ?? false;
                                  });
                                },
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Crear usuario de acceso',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      'Permitirá al trabajador acceder a la app',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Campos de usuario (solo si crearUsuario = true)
                        if (crearUsuario) ...[
                          const SizedBox(height: 16),
                          const Text(
                            'Credenciales de Acceso',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: emailController,
                            decoration: const InputDecoration(
                              labelText: 'Email *',
                              prefixIcon: Icon(Icons.email),
                              hintText: 'usuario@ejemplo.com',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: passwordController,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              labelText: 'Contraseña *',
                              prefixIcon: const Icon(Icons.lock),
                              hintText: 'Mínimo 6 caracteres',
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                ),
                                onPressed: () {
                                  setDialogState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 16),

                          // Opción de asignar rol específico
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange.shade200),
                            ),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: asignarRolEspecifico,
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
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Asignar rol específico de la app',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        'Vendedor o Almacenero con configuración',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Roles específicos
                          if (asignarRolEspecifico) ...[
                            const SizedBox(height: 16),
                            const Text(
                              'Configuración de Rol',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              value: selectedRole,
                              decoration: const InputDecoration(
                                labelText: 'Rol Específico *',
                                prefixIcon: Icon(Icons.work),
                                border: OutlineInputBorder(),
                              ),
                              items:
                                  [
                                        'gerente',
                                        'supervisor',
                                        'vendedor',
                                        'almacenero',
                                      ]
                                      .map(
                                        (role) => DropdownMenuItem(
                                          value: role,
                                          child: Text(
                                            _getRoleDisplayName(role),
                                          ),
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
                              DropdownButtonFormField<int>(
                                value: selectedTPV,
                                decoration: const InputDecoration(
                                  labelText: 'TPV Asignado',
                                  prefixIcon: Icon(Icons.point_of_sale),
                                  border: OutlineInputBorder(),
                                ),
                                items:
                                    _tpvs
                                        .map(
                                          (tpv) => DropdownMenuItem(
                                            value: tpv.id,
                                            child: Text(tpv.denominacion),
                                          ),
                                        )
                                        .toList(),
                                onChanged: (value) {
                                  setDialogState(() => selectedTPV = value);
                                },
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: numeroConfirmacionController,
                                decoration: const InputDecoration(
                                  labelText:
                                      'Número de Confirmación (Opcional)',
                                  prefixIcon: Icon(Icons.confirmation_number),
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ],
                            if (selectedRole == 'almacenero') ...[
                              const SizedBox(height: 12),
                              DropdownButtonFormField<int>(
                                value: selectedAlmacen,
                                decoration: const InputDecoration(
                                  labelText: 'Almacén Asignado',
                                  prefixIcon: Icon(Icons.warehouse),
                                  border: OutlineInputBorder(),
                                ),
                                items:
                                    _almacenes
                                        .map(
                                          (almacen) => DropdownMenuItem(
                                            value: almacen.id,
                                            child: Text(almacen.denominacion),
                                          ),
                                        )
                                        .toList(),
                                onChanged: (value) {
                                  setDialogState(() => selectedAlmacen = value);
                                },
                              ),
                            ],
                          ],
                        ],

                        // Rol general (si no crea usuario)
                        if (!crearUsuario) ...[
                          const SizedBox(height: 16),
                          const Text(
                            'Rol General',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<int>(
                            value: selectedRolGeneral,
                            decoration: const InputDecoration(
                              labelText: 'Rol *',
                              prefixIcon: Icon(Icons.badge),
                              border: OutlineInputBorder(),
                              helperText: 'Rol organizacional del trabajador',
                            ),
                            items:
                                _roles
                                    .map(
                                      (role) => DropdownMenuItem(
                                        value: role.id,
                                        child: Text(role.denominacion),
                                      ),
                                    )
                                    .toList(),
                            onChanged: (value) {
                              setDialogState(() => selectedRolGeneral = value);
                            },
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
                      onPressed:
                          () => _createWorkerFlexible(
                            nombres: nombresController.text,
                            apellidos: apellidosController.text,
                            crearUsuario: crearUsuario,
                            email: emailController.text,
                            password: passwordController.text,
                            asignarRolEspecifico: asignarRolEspecifico,
                            tipoRol: selectedRole,
                            tpvId: selectedTPV,
                            almacenId: selectedAlmacen,
                            numeroConfirmacion:
                                numeroConfirmacionController.text.isEmpty
                                    ? null
                                    : numeroConfirmacionController.text,
                            rolGeneralId: selectedRolGeneral,
                          ),
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar Trabajador'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                      ),
                    ),
                  ],
                ),
          ),
    );
  }

  Widget _buildRolesTab() {
    if (_isLoadingRoles) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: 16),
            Text(
              'Cargando roles...',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Roles de la Tienda',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              ElevatedButton.icon(
                onPressed: _showAddRoleDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nuevo Rol'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child:
              _roles.isEmpty
                  ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.admin_panel_settings_outlined,
                          size: 64,
                          color: AppColors.textSecondary,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No hay roles configurados',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Agrega roles para organizar tu personal',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  )
                  : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _roles.length,
                    itemBuilder: (context, index) {
                      final role = _roles[index];
                      return _buildRoleCard(role);
                    },
                  ),
        ),
      ],
    );
  }

  Widget _buildRoleCard(WorkerRole role) {
    // Contar trabajadores con este rol
    final workerCount = _workers.where((w) => w.rolId == role.id).length;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(25),
              ),
              child: const Icon(
                Icons.admin_panel_settings,
                color: AppColors.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    role.denominacion,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  if (role.descripcion != null)
                    Text(
                      role.descripcion!,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    '$workerCount trabajador${workerCount != 1 ? 'es' : ''}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, size: 18),
                  onPressed: () => _showEditRoleDialog(role),
                  tooltip: 'Editar',
                  color: AppColors.primary,
                ),
                IconButton(
                  icon: const Icon(Icons.delete, size: 18),
                  onPressed:
                      workerCount > 0
                          ? null
                          : () => _showDeleteRoleDialog(role),
                  tooltip:
                      workerCount > 0
                          ? 'No se puede eliminar (tiene trabajadores asignados)'
                          : 'Eliminar',
                  color: workerCount > 0 ? Colors.grey : Colors.red,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 🆕 Método flexible para crear trabajador (con o sin usuario)
  Future<void> _createWorkerFlexible({
    required String nombres,
    required String apellidos,
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
    // Validaciones básicas
    if (nombres.isEmpty || apellidos.isEmpty) {
      _showErrorDialog('Por favor, ingresa nombres y apellidos');
      return;
    }

    if (_storeId == null) {
      _showErrorDialog('Error: No se pudo obtener el ID de la tienda');
      return;
    }

    // Validaciones según el modo
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

    Navigator.pop(context); // Cerrar diálogo

    // Mostrar loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  crearUsuario
                      ? 'Registrando usuario y creando trabajador...'
                      : 'Creando trabajador...',
                ),
              ],
            ),
          ),
    );

    try {
      String? userUuid;

      // CASO 1: Crear usuario
      if (crearUsuario) {
        print('🔐 Registrando usuario en Supabase Auth...');
        final supabase = Supabase.instance.client;
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
        print('✅ Usuario registrado con UUID: $userUuid');

        // Si asigna rol específico
        if (asignarRolEspecifico && tipoRol != null) {
          print('👤 Creando trabajador con rol específico: $tipoRol');
          final success = await WorkerService.createWorker(
            storeId: _storeId!,
            nombres: nombres,
            apellidos: apellidos,
            tipoRol: tipoRol,
            usuarioUuid: userUuid,
            tpvId: tpvId,
            almacenId: almacenId,
            numeroConfirmacion: numeroConfirmacion,
          );

          if (!success) {
            throw Exception('Error al crear trabajador con rol específico');
          }
        } else {
          // Solo crear trabajador con UUID, sin rol específico
          print('👤 Creando trabajador con usuario pero sin rol específico');
          final success = await WorkerService.createWorkerBasic(
            storeId: _storeId!,
            nombres: nombres,
            apellidos: apellidos,
            usuarioUuid: userUuid,
            rolId: rolGeneralId,
          );

          if (!success) {
            throw Exception('Error al crear trabajador');
          }
        }
      }
      // CASO 2: No crear usuario (UUID null)
      else {
        print('👤 Creando trabajador SIN usuario (UUID null)');
        final success = await WorkerService.createWorkerBasic(
          storeId: _storeId!,
          nombres: nombres,
          apellidos: apellidos,
          usuarioUuid: null,
          rolId: rolGeneralId,
        );

        if (!success) {
          throw Exception('Error al crear trabajador');
        }
      }

      Navigator.pop(context); // Cerrar loading

      // Mostrar diálogo de confirmación
      await showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green.shade600),
                  const SizedBox(width: 12),
                  const Text('Trabajador Creado'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'El trabajador $nombres $apellidos ha sido creado exitosamente.',
                  ),
                  if (crearUsuario) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '✅ Usuario creado',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text('Email: $email'),
                        ],
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.orange),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Sin usuario de acceso. Puedes crear uno después.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Aceptar'),
                ),
              ],
            ),
      );

      // Recargar lista de trabajadores
      await _loadWorkersData();
    } catch (e) {
      Navigator.pop(context); // Cerrar loading
      print('❌ Error al crear trabajador: $e');
      _showErrorDialog('Error al crear trabajador: $e');
    }
  }

  // Método para crear trabajador con registro de usuario
  Future<void> _createWorkerWithRegistration({
    required String nombres,
    required String apellidos,
    required String email,
    required String password,
    required String tipoRol,
    int? tpvId,
    int? almacenId,
    String? numeroConfirmacion,
  }) async {
    // Validaciones
    if (nombres.isEmpty ||
        apellidos.isEmpty ||
        email.isEmpty ||
        password.isEmpty) {
      _showErrorDialog('Por favor, completa todos los campos requeridos');
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

    if (_storeId == null) {
      _showErrorDialog('Error: No se pudo obtener el ID de la tienda');
      return;
    }

    Navigator.pop(context); // Cerrar diálogo

    // Mostrar loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => const AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Registrando usuario y creando trabajador...'),
              ],
            ),
          ),
    );

    try {
      // Paso 1: Registrar usuario en Supabase Auth
      print('🔐 Registrando usuario en Supabase Auth...');
      final supabase = Supabase.instance.client;
      final authResponse = await supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'nombres': nombres,
          'apellidos': apellidos,
          'full_name': '$nombres $apellidos',
        },
        emailRedirectTo: null, // No redirigir, confirmar automáticamente
      );

      if (authResponse.user == null) {
        throw Exception('Error al registrar usuario en Supabase Auth');
      }

      final userUuid = authResponse.user!.id;
      print('✅ Usuario registrado con UUID: $userUuid');

      // Paso 2: Crear trabajador con el UUID obtenido
      print('👤 Creando trabajador...');
      final success = await WorkerService.createWorker(
        storeId: _storeId!,
        nombres: nombres,
        apellidos: apellidos,
        tipoRol: tipoRol,
        usuarioUuid: userUuid,
        tpvId: tpvId,
        almacenId: almacenId,
        numeroConfirmacion: numeroConfirmacion,
      );

      Navigator.pop(context); // Cerrar loading

      if (success) {
        // Mostrar diálogo de confirmación
        showDialog(
          context: context,
          builder:
              (context) => AlertDialog(
                title: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 28),
                    const SizedBox(width: 12),
                    const Text('Trabajador Creado'),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '✅ El trabajador ha sido creado exitosamente.',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: Colors.blue,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Importante:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'El trabajador debe confirmar su correo electrónico antes de poder acceder al sistema.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Datos de acceso:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Email: $email',
                            style: TextStyle(
                              fontSize: 14,
                              fontFamily: 'monospace',
                              color: Colors.grey.shade700,
                            ),
                          ),
                          Text(
                            'Contraseña: [Configurada por el administrador]',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Entendido'),
                  ),
                ],
              ),
        );

        await _loadWorkersData(); // Recargar datos
      }
    } catch (e) {
      Navigator.pop(context); // Cerrar loading
      print('❌ Error en registro completo: $e');

      String errorMessage = 'Error al crear usuario y trabajador: $e';
      if (e.toString().contains('User already registered')) {
        errorMessage = 'Ya existe un usuario con este email. Usa otro email.';
      } else if (e.toString().contains('Invalid email')) {
        errorMessage = 'Email inválido. Verifica el formato.';
      } else if (e.toString().contains(
        'Password should be at least 6 characters',
      )) {
        errorMessage = 'La contraseña debe tener al menos 6 caracteres.';
      }

      _showErrorDialog(errorMessage);
    }
  }

  // 🆕 Métodos para editar trabajador con roles múltiples
  void _showEditWorkerDialog(WorkerData worker) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (context) => EditWorkerMultiRoleScreen(
              worker: worker,
              storeId: _storeId!,
              userUuid: _userUuid!,
              tpvs: _tpvs,
              almacenes: _almacenes,
              onSaved: () {
                _loadWorkersData();
              },
            ),
      ),
    );
  }

  Future<void> _editWorker({
    required WorkerData worker,
    required String nombres,
    required String apellidos,
    String? uuid,
    required String tipoRol,
    int? tpvId,
    int? almacenId,
    String? numeroConfirmacion,
  }) async {
    if (nombres.isEmpty || apellidos.isEmpty) {
      _showErrorDialog('Por favor, completa todos los campos requeridos');
      return;
    }

    if (_storeId == null) {
      _showErrorDialog('Error: No se pudo obtener el ID de la tienda');
      return;
    }

    Navigator.pop(context); // Cerrar diálogo

    try {
      final success = await WorkerService.editWorker(
        workerId: worker.trabajadorId,
        storeId: _storeId!,
        nombres: nombres,
        apellidos: apellidos,
        tipoRol: tipoRol,
        usuarioUuid: uuid,
        tpvId: tpvId,
        almacenId: almacenId,
        numeroConfirmacion: numeroConfirmacion,
      );

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Trabajador actualizado exitosamente'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadWorkersData(); // Recargar datos
      }
    } catch (e) {
      _showErrorDialog('Error al actualizar trabajador: $e');
    }
  }

  // Método para eliminar trabajador
  void _showDeleteWorkerDialog(WorkerData worker) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Eliminar Trabajador'),
            content: Text(
              '¿Estás seguro de que deseas eliminar a ${worker.nombreCompleto}?\n\nEsta acción no se puede deshacer.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => _deleteWorker(worker),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
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

    Navigator.pop(context); // Cerrar diálogo

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
        await _loadWorkersData(); // Recargar datos
      }
    } catch (e) {
      _showErrorDialog('Error al eliminar trabajador: $e');
    }
  }

  // Métodos para gestión de roles
  void _showAddRoleDialog() {
    final denominacionController = TextEditingController();
    final descripcionController = TextEditingController();

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Agregar Rol'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: denominacionController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del Rol',
                    prefixIcon: Icon(Icons.admin_panel_settings),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descripcionController,
                  decoration: const InputDecoration(
                    labelText: 'Descripción (Opcional)',
                    prefixIcon: Icon(Icons.description),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed:
                    () => _createRole(
                      denominacion: denominacionController.text,
                      descripcion:
                          descripcionController.text.isEmpty
                              ? null
                              : descripcionController.text,
                    ),
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

    Navigator.pop(context); // Cerrar diálogo

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
        await _loadRolesData(); // Recargar datos
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
      builder:
          (context) => AlertDialog(
            title: Text('Editar: ${role.denominacion}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: denominacionController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del Rol',
                    prefixIcon: Icon(Icons.admin_panel_settings),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descripcionController,
                  decoration: const InputDecoration(
                    labelText: 'Descripción (Opcional)',
                    prefixIcon: Icon(Icons.description),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed:
                    () => _editRole(
                      role: role,
                      denominacion: denominacionController.text,
                      descripcion:
                          descripcionController.text.isEmpty
                              ? null
                              : descripcionController.text,
                    ),
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

    Navigator.pop(context); // Cerrar diálogo

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
        await _loadRolesData(); // Recargar datos
      }
    } catch (e) {
      _showErrorDialog('Error al actualizar rol: $e');
    }
  }

  void _showDeleteRoleDialog(WorkerRole role) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Eliminar Rol'),
            content: Text(
              '¿Estás seguro de que deseas eliminar el rol "${role.denominacion}"?\n\nEsta acción no se puede deshacer.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => _deleteRole(role),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Eliminar'),
              ),
            ],
          ),
    );
  }

  Future<void> _deleteRole(WorkerRole role) async {
    Navigator.pop(context); // Cerrar diálogo

    try {
      final success = await WorkerService.deleteRole(role.id);

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rol eliminado exitosamente'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadRolesData(); // Recargar datos
      }
    } catch (e) {
      _showErrorDialog('Error al eliminar rol: $e');
    }
  }

  // 👤 Diálogo para crear usuario para un trabajador sin UUID
  Future<void> _showCreateUserDialog(WorkerData worker) async {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    bool _obscurePassword = true;

    await showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: Row(
                    children: [
                      Icon(Icons.person_add, color: AppColors.primary),
                      const SizedBox(width: 12),
                      const Text('Crear Usuario'),
                    ],
                  ),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Trabajador:',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                worker.nombreCompleto,
                                style: const TextStyle(fontSize: 16),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Credenciales de Acceso',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: emailController,
                          decoration: const InputDecoration(
                            labelText: 'Email *',
                            prefixIcon: Icon(Icons.email),
                            hintText: 'usuario@ejemplo.com',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Contraseña *',
                            prefixIcon: const Icon(Icons.lock),
                            hintText: 'Mínimo 6 caracteres',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () {
                                setDialogState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.orange),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Se creará un usuario y se asignará al trabajador.',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
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
                              content: Text(
                                'Por favor completa todos los campos',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }

                        if (!email.contains('@')) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Por favor ingresa un email válido',
                              ),
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

                        Navigator.pop(context); // Cerrar diálogo

                        await _createUserForWorker(
                          worker: worker,
                          email: email,
                          password: password,
                        );
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Crear Usuario'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                      ),
                    ),
                  ],
                ),
          ),
    );
  }

  // Crear usuario para un trabajador existente
  Future<void> _createUserForWorker({
    required WorkerData worker,
    required String email,
    required String password,
  }) async {
    // Mostrar loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => const AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Creando usuario...'),
              ],
            ),
          ),
    );

    try {
      // Paso 1: Registrar usuario en Supabase Auth
      print('🔐 Registrando usuario en Supabase Auth...');
      final supabase = Supabase.instance.client;
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

      final userUuid = authResponse.user!.id;
      print('✅ Usuario registrado con UUID: $userUuid');

      // Paso 2: Actualizar trabajador con el UUID
      print('🔄 Actualizando trabajador con UUID...');
      final success = await WorkerService.updateWorkerUUID(
        workerId: worker.trabajadorId,
        storeId: _storeId!,
        uuid: userUuid,
      );

      if (!success) {
        throw Exception('Error al actualizar trabajador con UUID');
      }

      Navigator.pop(context); // Cerrar loading

      // Mostrar diálogo de éxito
      await showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green.shade600),
                  const SizedBox(width: 12),
                  const Text('Usuario Creado'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Usuario creado exitosamente para ${worker.nombreCompleto}',
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '✅ Credenciales',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text('Email: $email'),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Aceptar'),
                ),
              ],
            ),
      );

      // Recargar trabajadores
      await _loadWorkersData();
    } catch (e) {
      Navigator.pop(context); // Cerrar loading
      print('❌ Error al crear usuario: $e');
      _showErrorDialog('Error al crear usuario: $e');
    }
  }

  // 🔄 Diálogo para sincronizar UUID desde roles
  Future<void> _showSyncUUIDDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.sync, color: AppColors.primary),
                const SizedBox(width: 12),
                const Expanded(child: Text('Sincronizar UUID desde Roles')),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Esta acción buscará trabajadores que:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  '• No tienen UUID asignado en la tabla trabajadores',
                ),
                const Text(
                  '• Tienen roles activos (gerente, supervisor, vendedor, almacenero)',
                ),
                const Text('• El UUID se copiará desde la tabla del rol'),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.blue.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Esto permitirá que estos trabajadores puedan tener múltiples roles.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.sync, size: 18),
                label: const Text('Sincronizar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
              ),
            ],
          ),
    );

    if (confirmed == true && _storeId != null) {
      try {
        // Mostrar loading
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder:
                (context) => const Center(
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Sincronizando UUID...'),
                        ],
                      ),
                    ),
                  ),
                ),
          );
        }

        final result = await WorkerService.assignUUIDFromRoles(_storeId);

        if (mounted) {
          Navigator.pop(context); // Cerrar loading

          if (result['success'] == true) {
            final total = result['total'] ?? 0;
            final results = result['results'] as List<dynamic>;

            // Mostrar resultados
            await showDialog(
              context: context,
              builder:
                  (context) => AlertDialog(
                    title: Row(
                      children: [
                        Icon(
                          total > 0 ? Icons.check_circle : Icons.info_outline,
                          color: total > 0 ? Colors.green : Colors.orange,
                        ),
                        const SizedBox(width: 12),
                        const Text('Resultado de Sincronización'),
                      ],
                    ),
                    content: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            result['message'] ?? 'Sincronización completada',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (total > 0) ...[
                            const SizedBox(height: 16),
                            const Text(
                              'Trabajadores actualizados:',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            ...results.map((worker) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.person,
                                      size: 16,
                                      color: Colors.green.shade700,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '${worker['nombres']} ${worker['apellidos']}',
                                        style: const TextStyle(fontSize: 14),
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
                              );
                            }).toList(),
                          ],
                        ],
                      ),
                    ),
                    actions: [
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cerrar'),
                      ),
                    ],
                  ),
            );

            // Recargar trabajadores si hubo cambios
            if (total > 0) {
              await _loadWorkersData();
            }
          }
        }
      } catch (e) {
        if (mounted) {
          Navigator.pop(context); // Cerrar loading si está abierto
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  // Navegación del bottom navigation
  void _onBottomNavTap(int index) {
    switch (index) {
      case 0: // Dashboard
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/dashboard',
          (route) => false,
        );
        break;
      case 1: // Productos
        Navigator.pushNamed(context, '/products-dashboard');
        break;
      case 2: // Inventario
        Navigator.pushNamed(context, '/inventory');
        break;
      case 3: // Configuración
        Navigator.pushNamed(context, '/settings');
        break;
    }
  }
}
