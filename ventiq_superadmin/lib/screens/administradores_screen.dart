import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../widgets/app_drawer.dart';
import '../utils/platform_utils.dart';
import '../services/gerente_service.dart';

class AdministradoresScreen extends StatefulWidget {
  const AdministradoresScreen({super.key});

  @override
  State<AdministradoresScreen> createState() => _AdministradoresScreenState();
}

class _AdministradoresScreenState extends State<AdministradoresScreen> {
  final _gerenteService = GerenteService();
  List<Map<String, dynamic>> _administradores = [];
  List<Map<String, dynamic>> _filteredAdministradores = [];
  List<Map<String, dynamic>> _tiendas = [];
  bool _isLoading = true;
  String _searchQuery = '';
  int? _selectedTienda;
  String _filterByEmail = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      debugPrint('═══════════════════════════════════════════');
      debugPrint('📥 CARGANDO DATOS DE GERENTES');
      
      // Cargar tiendas y gerentes (gerentes ya incluye datos de trabajador y tienda)
      final tiendas = await _gerenteService.getAllTiendas();
      final gerentes = await _gerenteService.getAllGerentes();
      
      debugPrint('✅ Datos cargados:');
      debugPrint('  - Tiendas: ${tiendas.length}');
      debugPrint('  - Gerentes: ${gerentes.length}');
      
      // Mapear datos del RPC directamente
      final administradores = gerentes.map((gerente) {
        final nombreCompleto = '${gerente['nombres'] ?? 'Sin asignar'} ${gerente['apellidos'] ?? ''}'.trim();
        
        return {
          'id': gerente['id_gerente'],
          'uuid': gerente['uuid'],
          'nombre_trabajador': nombreCompleto,
          'rol': 'Gerente',
          'id_tienda': gerente['id_tienda'],
          'tienda': gerente['tienda_denominacion'] ?? 'Sin tienda',
          'created_at': gerente['created_at'],
          'id_trabajador': gerente['id_trabajador'],
        };
      }).toList();
      
      debugPrint('✅ Administradores procesados: ${administradores.length}');
      debugPrint('═══════════════════════════════════════════');
      
      if (mounted) {
        setState(() {
          _tiendas = tiendas;
          _administradores = administradores;
          _filteredAdministradores = administradores;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error cargando administradores: $e');
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
        final email = (admin['email'] ?? '').toString().toLowerCase();
        final tienda = (admin['tienda'] ?? '').toString().toLowerCase();
        final searchLower = _searchQuery.toLowerCase();
        final emailFilterLower = _filterByEmail.toLowerCase();
        
        final matchesSearch = email.contains(searchLower) || tienda.contains(searchLower);
        final matchesEmailFilter = _filterByEmail.isEmpty || email.contains(emailFilterLower);
        final matchesTienda = _selectedTienda == null || admin['id_tienda'] == _selectedTienda;
        
        return matchesSearch && matchesEmailFilter && matchesTienda;
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
                  flex: 2,
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Buscar por tienda o email',
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
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Filtrar por correo',
                      prefixIcon: Icon(Icons.email),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _filterByEmail = value;
                      });
                      _filterAdministradores();
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 1,
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
    final gerentes = _administradores.length;
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
              'Lista de Gerentes (${_filteredAdministradores.length})',
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
                      DataColumn(label: Text('Tienda')),
                      DataColumn(label: Text('Fecha Registro')),
                      DataColumn(label: Text('Acciones')),
                    ],
                    rows: _filteredAdministradores.map((admin) {
                      return DataRow(
                        onSelectChanged: (_) => _showAdministradorDetails(admin),
                        cells: [
                          DataCell(
                            Text(admin['nombre_trabajador'] ?? 'Sin asignar'),
                          ),
                          DataCell(
                            Text(admin['tienda']),
                          ),
                          DataCell(
                            Text(_formatDate(admin['created_at'])),
                          ),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
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
            onTap: () => _showAdministradorDetails(admin),
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withOpacity(0.1),
              child: const Icon(
                Icons.admin_panel_settings,
                color: AppColors.primary,
              ),
            ),
            title: Text(
              admin['nombre_trabajador'] ?? 'Sin asignar',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(admin['tienda']),
                const SizedBox(height: 4),
                Text(
                  'Registrado: ${_formatDate(admin['created_at'])}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            trailing: PopupMenuButton(
              itemBuilder: (context) => [
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
    String emailUsuario = '';
    int? selectedTiendaId;
    String tiendaSearchQuery = '';
    String nombresTrabajador = '';
    String apellidosTrabajador = '';
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Crear Nuevo Gerente'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Sección 1: Ingresa datos para crear gerente
                  Text('Crear Nuevo Gerente', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Email del Usuario',
                      hintText: 'Ingresa el email del usuario de Supabase Auth',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email),
                    ),
                    onChanged: (value) {
                      setDialogState(() => emailUsuario = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Nombres',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      setDialogState(() => nombresTrabajador = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Apellidos',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      setDialogState(() => apellidosTrabajador = value);
                    },
                  ),
                  const SizedBox(height: 16),
                  Text('Seleccionar Tienda', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Buscar Tienda',
                      hintText: 'Escribe para filtrar tiendas',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) {
                      setDialogState(() => tiendaSearchQuery = value.toLowerCase());
                    },
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 150),
                      child: ListView(
                        shrinkWrap: true,
                        children: _tiendas
                            .where((tienda) =>
                                tienda['denominacion']
                                    .toString()
                                    .toLowerCase()
                                    .contains(tiendaSearchQuery))
                            .map((tienda) {
                          final isSelected = selectedTiendaId == tienda['id'];
                          return ListTile(
                            selected: isSelected,
                            title: Text(tienda['denominacion'] ?? 'Sin nombre'),
                            tileColor: isSelected ? AppColors.primary.withOpacity(0.1) : null,
                            onTap: () {
                              setDialogState(() {
                                selectedTiendaId = tienda['id'] as int;
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  if (selectedTiendaId != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.1),
                          border: Border.all(color: AppColors.success),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Tienda seleccionada: ${_tiendas.firstWhere((t) => t['id'] == selectedTiendaId)['denominacion']}',
                          style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (emailUsuario.isNotEmpty && nombresTrabajador.isNotEmpty && apellidosTrabajador.isNotEmpty && selectedTiendaId != null)
                          ? () {
                              debugPrint('═══════════════════════════════════════════');
                              debugPrint('📝 CREAR GERENTE DESDE EMAIL');
                              debugPrint('Email: $emailUsuario');
                              debugPrint('Nombres: $nombresTrabajador');
                              debugPrint('Apellidos: $apellidosTrabajador');
                              debugPrint('ID Tienda: $selectedTiendaId');
                              debugPrint('═══════════════════════════════════════════');
                              _createGerenteFromEmail(
                                emailUsuario,
                                nombresTrabajador,
                                apellidosTrabajador,
                                selectedTiendaId!,
                              );
                            }
                          : null,
                      child: const Text('Crear Gerente'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createGerenteFromEmail(
    String email,
    String nombres,
    String apellidos,
    int idTienda,
  ) async {
    try {
      debugPrint('═══════════════════════════════════════════');
      debugPrint('➕ CREANDO GERENTE DESDE EMAIL');
      debugPrint('Email: $email');
      debugPrint('Nombres: $nombres');
      debugPrint('Apellidos: $apellidos');
      debugPrint('ID Tienda: $idTienda');
      debugPrint('═══════════════════════════════════════════');
      
      final resultado = await _gerenteService.createGerenteFromEmail(
        email: email,
        nombres: nombres,
        apellidos: apellidos,
        idTienda: idTienda,
      );

      debugPrint('✅ Gerente creado exitosamente');
      debugPrint('Gerente ID: ${resultado['gerente_id']}');
      debugPrint('Trabajador ID: ${resultado['trabajador_id']}');

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gerente creado exitosamente'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showAdministradorDetails(Map<String, dynamic> admin) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Detalles del Gerente'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Email: ${admin['email']}'),
            const SizedBox(height: 8),
            Text('Tienda: ${admin['tienda']}'),
            const SizedBox(height: 8),
            Text('UUID: ${admin['uuid']}'),
            const SizedBox(height: 8),
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
    int? selectedTiendaId = admin['id_tienda'];
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Editar Gerente - ${admin['email']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Tienda Actual: ${admin['tienda']}'),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  value: selectedTiendaId,
                  decoration: const InputDecoration(
                    labelText: 'Nueva Tienda',
                    border: OutlineInputBorder(),
                  ),
                  items: _tiendas.map<DropdownMenuItem<int>>((tienda) => DropdownMenuItem(
                    value: tienda['id'] as int,
                    child: Text(tienda['denominacion'] ?? 'Sin nombre'),
                  )).toList(),
                  onChanged: (value) {
                    setDialogState(() => selectedTiendaId = value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: selectedTiendaId != null
                  ? () => _updateGerente(admin['id'], selectedTiendaId!)
                  : null,
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateGerente(int id, int idTienda) async {
    try {
      await _gerenteService.updateGerente(
        id: id,
        idTienda: idTienda,
      );
      
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gerente actualizado exitosamente'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al actualizar gerente: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showDeleteConfirmation(Map<String, dynamic> admin) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Eliminación'),
        content: Text('¿Estás seguro de que deseas eliminar al gerente "${admin['email']}" de la tienda "${admin['tienda']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => _deleteGerente(admin['id']),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteGerente(int id) async {
    try {
      await _gerenteService.deleteGerente(id);
      
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gerente eliminado exitosamente'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al eliminar gerente: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}
