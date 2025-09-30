import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/admin_bottom_navigation.dart';
import '../models/worker_models.dart';
import '../services/worker_service.dart';
import '../services/store_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WorkersScreen extends StatefulWidget {
  const WorkersScreen({super.key});

  @override
  State<WorkersScreen> createState() => _WorkersScreenState();
}

class _WorkersScreenState extends State<WorkersScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Datos de trabajadores
  List<WorkerData> _workers = [];
  List<WorkerRole> _roles = [];
  List<TPVData> _tpvs = [];
  List<AlmacenData> _almacenes = [];
  WorkerStatistics? _statistics;

  // Estados de carga
  bool _isLoadingWorkers = true;
  bool _isLoadingRoles = true;

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
          IconButton(
            icon: const Icon(Icons.person_add, color: Colors.white),
            onPressed: _showAddWorkerDialog,
            tooltip: 'Agregar Trabajador',
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
                backgroundColor: _getRoleColor(worker.tipoRol).withOpacity(0.1),
                child: Text(
                  worker.nombres.substring(0, 1).toUpperCase(),
                  style: TextStyle(
                    color: _getRoleColor(worker.tipoRol),
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
                      worker.rolNombre,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (worker.tipoRol == 'vendedor' &&
                        worker.tpvDenominacion != null)
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
                    if (worker.tipoRol == 'almacenero' &&
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getRoleColor(worker.tipoRol).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _getRoleDisplayName(worker.tipoRol),
                      style: TextStyle(
                        color: _getRoleColor(worker.tipoRol),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
    switch (role) {
      case 'gerente':
        return 'Gerente';
      case 'supervisor':
        return 'Supervisor';
      case 'vendedor':
        return 'Vendedor';
      case 'almacenero':
        return 'Almacenero';
      case 'Todos':
        return 'Todos';
      default:
        return role;
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

  // Diálogo para agregar trabajador
  void _showAddWorkerDialog() {
    final nombresController = TextEditingController();
    final apellidosController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final numeroConfirmacionController = TextEditingController();
    String selectedRole = 'vendedor';
    int? selectedTPV;
    int? selectedAlmacen;
    bool _obscurePassword = true;

    showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: const Text('Agregar Trabajador'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: nombresController,
                          decoration: const InputDecoration(
                            labelText: 'Nombres',
                            prefixIcon: Icon(Icons.person),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: apellidosController,
                          decoration: const InputDecoration(
                            labelText: 'Apellidos',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: emailController,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.email),
                            hintText: 'usuario@ejemplo.com',
                          ),
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Contraseña',
                            prefixIcon: const Icon(Icons.lock),
                            hintText: 'Mínimo 6 caracteres',
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
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: selectedRole,
                          decoration: const InputDecoration(
                            labelText: 'Rol',
                            prefixIcon: Icon(Icons.work),
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
                                      child: Text(_getRoleDisplayName(role)),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (value) {
                            setDialogState(() {
                              selectedRole = value!;
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
                              labelText: 'Número de Confirmación (Opcional)',
                              prefixIcon: Icon(Icons.confirmation_number),
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
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                    ElevatedButton(
                      onPressed:
                          () => _createWorkerWithRegistration(
                            nombres: nombresController.text,
                            apellidos: apellidosController.text,
                            email: emailController.text,
                            password: passwordController.text,
                            tipoRol: selectedRole,
                            tpvId: selectedTPV,
                            almacenId: selectedAlmacen,
                            numeroConfirmacion:
                                numeroConfirmacionController.text.isEmpty
                                    ? null
                                    : numeroConfirmacionController.text,
                          ),
                      child: const Text('Agregar'),
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

  // Métodos para editar trabajador
  void _showEditWorkerDialog(WorkerData worker) {
    final nombresController = TextEditingController(text: worker.nombres);
    final apellidosController = TextEditingController(text: worker.apellidos);
    final uuidController = TextEditingController(
      text: worker.usuarioUuid ?? '',
    );
    final numeroConfirmacionController = TextEditingController(
      text: worker.numeroConfirmacion ?? '',
    );
    String selectedRole = worker.tipoRol;
    int? selectedTPV = worker.tpvId;
    int? selectedAlmacen = worker.almacenId;

    showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setDialogState) => AlertDialog(
                  title: Text('Editar: ${worker.nombreCompleto}'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: nombresController,
                          decoration: const InputDecoration(
                            labelText: 'Nombres',
                            prefixIcon: Icon(Icons.person),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: apellidosController,
                          decoration: const InputDecoration(
                            labelText: 'Apellidos',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: uuidController,
                          decoration: const InputDecoration(
                            labelText: 'UUID del Usuario',
                            prefixIcon: Icon(Icons.fingerprint),
                            hintText: 'UUID de Supabase Auth',
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: selectedRole,
                          decoration: const InputDecoration(
                            labelText: 'Rol',
                            prefixIcon: Icon(Icons.work),
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
                                      child: Text(_getRoleDisplayName(role)),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (value) {
                            setDialogState(() {
                              selectedRole = value!;
                              if (selectedRole != 'vendedor')
                                selectedTPV = null;
                              if (selectedRole != 'almacenero')
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
                              labelText: 'Número de Confirmación (Opcional)',
                              prefixIcon: Icon(Icons.confirmation_number),
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
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                    ElevatedButton(
                      onPressed:
                          () => _editWorker(
                            worker: worker,
                            nombres: nombresController.text,
                            apellidos: apellidosController.text,
                            uuid:
                                uuidController.text.isEmpty
                                    ? null
                                    : uuidController.text,
                            tipoRol: selectedRole,
                            tpvId: selectedTPV,
                            almacenId: selectedAlmacen,
                            numeroConfirmacion:
                                numeroConfirmacionController.text.isEmpty
                                    ? null
                                    : numeroConfirmacionController.text,
                          ),
                      child: const Text('Guardar'),
                    ),
                  ],
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
