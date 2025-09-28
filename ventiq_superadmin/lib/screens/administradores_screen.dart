import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_colors.dart';
import '../widgets/app_drawer.dart';
import '../utils/platform_utils.dart';

class AdministradoresScreen extends StatefulWidget {
  const AdministradoresScreen({super.key});

  @override
  State<AdministradoresScreen> createState() => _AdministradoresScreenState();
}

class _AdministradoresScreenState extends State<AdministradoresScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _administradores = [];
  List<Map<String, dynamic>> _filteredAdministradores = [];
  List<Map<String, dynamic>> _tiendas = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedRole = 'todos';
  int? _selectedTienda;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      // Cargar tiendas
      final tiendasResponse = await _supabase
          .from('app_dat_tienda')
          .select('id, denominacion')
          .order('denominacion');
      
      // Cargar gerentes
      final gerentesResponse = await _supabase
          .from('app_dat_gerente')
          .select('''
            id,
            uuid,
            id_tienda,
            created_at,
            app_dat_tienda!inner(
              denominacion,
              direccion,
              ubicacion
            ),
            app_dat_trabajadores!inner(
              id,
              nombres,
              apellidos
            )
          ''');
      
      // Cargar supervisores
      final supervisoresResponse = await _supabase
          .from('app_dat_supervisor')
          .select('''
            id,
            uuid,
            id_tienda,
            created_at,
            app_dat_tienda!inner(
              denominacion,
              direccion,
              ubicacion
            ),
            app_dat_trabajadores!inner(
              id,
              nombres,
              apellidos
            )
          ''');
      
      // Combinar y formatear datos
      final administradores = <Map<String, dynamic>>[];
      
      for (var gerente in gerentesResponse) {
        final trabajador = gerente['app_dat_trabajadores'];
        final tienda = gerente['app_dat_tienda'];
        
        administradores.add({
          'id': gerente['id'],
          'uuid': gerente['uuid'],
          'nombres': trabajador?['nombres'] ?? 'Sin nombre',
          'apellidos': trabajador?['apellidos'] ?? '',
          'rol': 'Gerente',
          'id_tienda': gerente['id_tienda'],
          'tienda': tienda?['denominacion'] ?? 'Sin tienda',
          'ubicacion': tienda?['ubicacion'] ?? 'Sin ubicación',
          'created_at': gerente['created_at'],
        });
      }
      
      for (var supervisor in supervisoresResponse) {
        final trabajador = supervisor['app_dat_trabajadores'];
        final tienda = supervisor['app_dat_tienda'];
        
        administradores.add({
          'id': supervisor['id'],
          'uuid': supervisor['uuid'],
          'nombres': trabajador?['nombres'] ?? 'Sin nombre',
          'apellidos': trabajador?['apellidos'] ?? '',
          'rol': 'Supervisor',
          'id_tienda': supervisor['id_tienda'],
          'tienda': tienda?['denominacion'] ?? 'Sin tienda',
          'ubicacion': tienda?['ubicacion'] ?? 'Sin ubicación',
          'created_at': supervisor['created_at'],
        });
      }
      
      if (mounted) {
        setState(() {
          _tiendas = List<Map<String, dynamic>>.from(tiendasResponse);
          _administradores = administradores;
          _filteredAdministradores = administradores;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error cargando administradores: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar administradores: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _filterAdministradores() {
    setState(() {
      _filteredAdministradores = _administradores.where((admin) {
        final nombreCompleto = '${admin['nombres']} ${admin['apellidos']}'.toLowerCase();
        final matchesSearch = nombreCompleto.contains(_searchQuery.toLowerCase()) ||
                            admin['tienda'].toString().toLowerCase().contains(_searchQuery.toLowerCase());
        
        final matchesRole = _selectedRole == 'todos' ||
                          admin['rol'].toString().toLowerCase() == _selectedRole.toLowerCase();
        
        final matchesTienda = _selectedTienda == null ||
                            admin['id_tienda'] == _selectedTienda;
        
        return matchesSearch && matchesRole && matchesTienda;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isDesktop = PlatformUtils.shouldUseDesktopLayout(screenSize.width);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administradores de Tienda'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Actualizar',
          ),
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: () => _showCreateAdministradorDialog(),
            tooltip: 'Nuevo Administrador',
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: const AppDrawer(),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(isDesktop),
    );
  }

  Widget _buildBody(bool isDesktop) {
    return Padding(
      padding: EdgeInsets.all(PlatformUtils.getScreenPadding()),
      child: Column(
        children: [
          _buildFilters(),
          const SizedBox(height: 16),
          _buildStats(),
          const SizedBox(height: 16),
          Expanded(
            child: isDesktop 
                ? _buildDesktopTable()
                : _buildMobileList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Buscar administrador',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                      _filterAdministradores();
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    value: _selectedRole,
                    decoration: const InputDecoration(
                      labelText: 'Rol',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'todos', child: Text('Todos')),
                      DropdownMenuItem(value: 'gerente', child: Text('Gerentes')),
                      DropdownMenuItem(value: 'supervisor', child: Text('Supervisores')),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedRole = value!;
                      });
                      _filterAdministradores();
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<int?>(
                    value: _selectedTienda,
                    decoration: const InputDecoration(
                      labelText: 'Tienda',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Todas')),
                      ..._tiendas.map((tienda) => DropdownMenuItem(
                        value: tienda['id'] as int,
                        child: Text(tienda['denominacion']),
                      )),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedTienda = value;
                      });
                      _filterAdministradores();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStats() {
    final gerentes = _administradores.where((a) => a['rol'] == 'Gerente').length;
    final supervisores = _administradores.where((a) => a['rol'] == 'Supervisor').length;
    final tiendasConAdmin = _administradores.map((a) => a['id_tienda']).toSet().length;
    
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Total Administradores',
            _administradores.length.toString(),
            Icons.people,
            AppColors.primary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'Gerentes',
            gerentes.toString(),
            Icons.admin_panel_settings,
            AppColors.success,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'Supervisores',
            supervisores.toString(),
            Icons.supervisor_account,
            AppColors.info,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'Tiendas con Admin',
            tiendasConAdmin.toString(),
            Icons.store,
            AppColors.secondary,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopTable() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Lista de Administradores',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Nombre')),
                      DataColumn(label: Text('Rol')),
                      DataColumn(label: Text('Tienda')),
                      DataColumn(label: Text('Ubicación')),
                      DataColumn(label: Text('Fecha Registro')),
                      DataColumn(label: Text('Acciones')),
                    ],
                    rows: _filteredAdministradores.map((admin) {
                      return DataRow(
                        cells: [
                          DataCell(
                            Text('${admin['nombres']} ${admin['apellidos']}'),
                          ),
                          DataCell(
                            _buildRoleChip(admin['rol']),
                          ),
                          DataCell(
                            Text(admin['tienda']),
                          ),
                          DataCell(
                            Text(admin['ubicacion']),
                          ),
                          DataCell(
                            Text(_formatDate(admin['created_at'])),
                          ),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.visibility),
                                  onPressed: () => _showAdministradorDetails(admin),
                                  tooltip: 'Ver Detalles',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () => _showEditAdministradorDialog(admin),
                                  tooltip: 'Editar',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: AppColors.error),
                                  onPressed: () => _showDeleteConfirmation(admin),
                                  tooltip: 'Eliminar',
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileList() {
    return ListView.builder(
      itemCount: _filteredAdministradores.length,
      itemBuilder: (context, index) {
        final admin = _filteredAdministradores[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _getRoleColor(admin['rol']).withOpacity(0.1),
              child: Icon(
                _getRoleIcon(admin['rol']),
                color: _getRoleColor(admin['rol']),
              ),
            ),
            title: Text(
              '${admin['nombres']} ${admin['apellidos']}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(admin['tienda']),
                const SizedBox(height: 4),
                _buildRoleChip(admin['rol']),
              ],
            ),
            trailing: PopupMenuButton(
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'view',
                  child: ListTile(
                    leading: Icon(Icons.visibility),
                    title: Text('Ver Detalles'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    leading: Icon(Icons.edit),
                    title: Text('Editar'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete, color: Colors.red),
                    title: Text('Eliminar', style: TextStyle(color: Colors.red)),
                  ),
                ),
              ],
              onSelected: (value) => _handleAction(value.toString(), admin),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRoleChip(String role) {
    final color = _getRoleColor(role);
    return Chip(
      label: Text(
        role.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      backgroundColor: color.withOpacity(0.1),
      side: BorderSide(color: color),
    );
  }

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'gerente':
        return AppColors.success;
      case 'supervisor':
        return AppColors.info;
      default:
        return AppColors.textSecondary;
    }
  }

  IconData _getRoleIcon(String role) {
    switch (role.toLowerCase()) {
      case 'gerente':
        return Icons.admin_panel_settings;
      case 'supervisor':
        return Icons.supervisor_account;
      default:
        return Icons.person;
    }
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  void _handleAction(String action, Map<String, dynamic> admin) {
    switch (action) {
      case 'view':
        _showAdministradorDetails(admin);
        break;
      case 'edit':
        _showEditAdministradorDialog(admin);
        break;
      case 'delete':
        _showDeleteConfirmation(admin);
        break;
    }
  }

  void _showCreateAdministradorDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuevo Administrador'),
        content: const Text('Funcionalidad de creación de administrador en desarrollo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _showAdministradorDetails(Map<String, dynamic> admin) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${admin['nombres']} ${admin['apellidos']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Rol: ${admin['rol']}'),
            Text('Tienda: ${admin['tienda']}'),
            Text('Ubicación: ${admin['ubicacion']}'),
            Text('UUID: ${admin['uuid']}'),
            Text('Fecha de Registro: ${_formatDate(admin['created_at'])}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _showEditAdministradorDialog(Map<String, dynamic> admin) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Editar ${admin['nombres']} ${admin['apellidos']}'),
        content: const Text('Funcionalidad de edición en desarrollo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(Map<String, dynamic> admin) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Eliminación'),
        content: Text('¿Estás seguro de que deseas eliminar a "${admin['nombres']} ${admin['apellidos']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              // TODO: Implementar eliminación
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Funcionalidad en desarrollo')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}
