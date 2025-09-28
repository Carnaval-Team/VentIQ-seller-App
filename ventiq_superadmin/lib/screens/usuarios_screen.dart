import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../models/usuario.dart';
import '../widgets/app_drawer.dart';
import '../utils/platform_utils.dart';

class UsuariosScreen extends StatefulWidget {
  const UsuariosScreen({super.key});

  @override
  State<UsuariosScreen> createState() => _UsuariosScreenState();
}

class _UsuariosScreenState extends State<UsuariosScreen> {
  List<Usuario> _usuarios = [];
  List<Usuario> _filteredUsuarios = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedFilter = 'todos';

  @override
  void initState() {
    super.initState();
    _loadUsuarios();
  }

  Future<void> _loadUsuarios() async {
    setState(() => _isLoading = true);
    
    // Simular carga de datos
    await Future.delayed(const Duration(seconds: 1));
    
    setState(() {
      _usuarios = Usuario.getMockData();
      _filteredUsuarios = _usuarios;
      _isLoading = false;
    });
  }

  void _filterUsuarios() {
    setState(() {
      _filteredUsuarios = _usuarios.where((usuario) {
        final matchesSearch = usuario.nombreCompleto.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                            usuario.email.toLowerCase().contains(_searchQuery.toLowerCase());
        
        final matchesFilter = _selectedFilter == 'todos' ||
                            (_selectedFilter == 'activos' && usuario.activo) ||
                            (_selectedFilter == 'inactivos' && !usuario.activo) ||
                            (_selectedFilter == 'super_admin' && usuario.esSuperAdmin) ||
                            (_selectedFilter == 'admin_tienda' && usuario.esAdminTienda);
        
        return matchesSearch && matchesFilter;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isDesktop = PlatformUtils.shouldUseDesktopLayout(screenSize.width);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Usuarios'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadUsuarios,
            tooltip: 'Actualizar',
          ),
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: () => _showCreateUsuarioDialog(),
            tooltip: 'Nuevo Usuario',
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: const AppDrawer(),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(isDesktop),
      floatingActionButton: !isDesktop ? FloatingActionButton(
        onPressed: () => _showCreateUsuarioDialog(),
        child: const Icon(Icons.person_add),
      ) : null,
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
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Buscar usuarios...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  _searchQuery = value;
                  _filterUsuarios();
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                value: _selectedFilter,
                decoration: const InputDecoration(
                  labelText: 'Filtrar por',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'todos', child: Text('Todos')),
                  DropdownMenuItem(value: 'activos', child: Text('Activos')),
                  DropdownMenuItem(value: 'inactivos', child: Text('Inactivos')),
                  DropdownMenuItem(value: 'super_admin', child: Text('Super Admins')),
                  DropdownMenuItem(value: 'admin_tienda', child: Text('Admin Tienda')),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedFilter = value!;
                  });
                  _filterUsuarios();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStats() {
    final activos = _usuarios.where((u) => u.activo).length;
    final inactivos = _usuarios.length - activos;
    final superAdmins = _usuarios.where((u) => u.esSuperAdmin).length;

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Total Usuarios',
            _usuarios.length.toString(),
            Icons.people,
            AppColors.primary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'Activos',
            activos.toString(),
            Icons.check_circle,
            AppColors.success,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'Inactivos',
            inactivos.toString(),
            Icons.cancel,
            AppColors.error,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'Super Admins',
            superAdmins.toString(),
            Icons.admin_panel_settings,
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
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        child: Column(
          children: [
            // Header de la tabla
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.people, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Lista de Usuarios (${_filteredUsuarios.length})',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            // Tabla con scroll
            Expanded(
              child: SingleChildScrollView(
                child: SizedBox(
                  width: double.infinity,
                  child: DataTable(
                    columnSpacing: 16,
                    horizontalMargin: 16,
                    headingRowHeight: 56,
                    dataRowHeight: 72,
                    columns: const [
                      DataColumn(
                        label: Expanded(
                          child: Text(
                            'Usuario',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Expanded(
                          child: Text(
                            'Email',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Expanded(
                          child: Text(
                            'Rol',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Expanded(
                          child: Text(
                            'Tiendas',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Expanded(
                          child: Text(
                            'Estado',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Expanded(
                          child: Text(
                            'Último Acceso',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Expanded(
                          child: Text(
                            'Acciones',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                    rows: _filteredUsuarios.map((usuario) {
                      return DataRow(
                        cells: [
                          DataCell(
                            SizedBox(
                              width: double.infinity,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    usuario.nombreCompleto,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'ID: ${usuario.id}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: double.infinity,
                              child: Text(
                                usuario.email,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: double.infinity,
                              child: _buildRoleChip(usuario.rol),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: double.infinity,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.info.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  usuario.tiendasAsignadas.length.toString(),
                                  style: TextStyle(
                                    color: AppColors.info,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: double.infinity,
                              child: _buildStatusChip(usuario.activo),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: double.infinity,
                              child: _buildLastAccessInfo(usuario),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: double.infinity,
                              child: _buildActions(usuario),
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
      itemCount: _filteredUsuarios.length,
      itemBuilder: (context, index) {
        final usuario = _filteredUsuarios[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _getRoleColor(usuario.rol).withOpacity(0.1),
              child: Icon(
                _getRoleIcon(usuario.rol),
                color: _getRoleColor(usuario.rol),
              ),
            ),
            title: Text(
              usuario.nombreCompleto,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(usuario.email),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _buildRoleChip(usuario.rol),
                    const SizedBox(width: 8),
                    _buildStatusChip(usuario.activo),
                  ],
                ),
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
                  value: 'password',
                  child: ListTile(
                    leading: Icon(Icons.lock_reset),
                    title: Text('Cambiar Contraseña'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'toggle',
                  child: ListTile(
                    leading: Icon(Icons.toggle_on),
                    title: Text('Activar/Desactivar'),
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
              onSelected: (value) => _handleAction(value.toString(), usuario),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRoleChip(String rol) {
    Color color = _getRoleColor(rol);
    String displayText = _getRoleDisplayText(rol);

    return Chip(
      label: Text(
        displayText,
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

  Widget _buildStatusChip(bool activo) {
    Color color = activo ? AppColors.success : AppColors.error;
    String text = activo ? 'ACTIVO' : 'INACTIVO';

    return Chip(
      label: Text(
        text,
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

  Widget _buildLastAccessInfo(Usuario usuario) {
    if (usuario.ultimoAcceso == null) {
      return const Text('Nunca');
    }

    final now = DateTime.now();
    final difference = now.difference(usuario.ultimoAcceso!);
    
    String text;
    Color color = AppColors.textSecondary;

    if (difference.inDays > 30) {
      text = '${difference.inDays} días';
      color = AppColors.error;
    } else if (difference.inDays > 7) {
      text = '${difference.inDays} días';
      color = AppColors.warning;
    } else if (difference.inDays > 0) {
      text = '${difference.inDays} días';
    } else if (difference.inHours > 0) {
      text = '${difference.inHours}h';
    } else {
      text = 'Ahora';
      color = AppColors.success;
    }

    return Text(
      text,
      style: TextStyle(
        color: color,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildActions(Usuario usuario) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.visibility),
          onPressed: () => _handleAction('view', usuario),
          tooltip: 'Ver Detalles',
        ),
        IconButton(
          icon: const Icon(Icons.edit),
          onPressed: () => _handleAction('edit', usuario),
          tooltip: 'Editar',
        ),
        IconButton(
          icon: const Icon(Icons.lock_reset),
          onPressed: () => _handleAction('password', usuario),
          tooltip: 'Cambiar Contraseña',
        ),
        IconButton(
          icon: Icon(
            usuario.activo ? Icons.toggle_on : Icons.toggle_off,
            color: usuario.activo ? AppColors.success : AppColors.error,
          ),
          onPressed: () => _handleAction('toggle', usuario),
          tooltip: usuario.activo ? 'Desactivar' : 'Activar',
        ),
        IconButton(
          icon: const Icon(Icons.delete, color: AppColors.error),
          onPressed: () => _handleAction('delete', usuario),
          tooltip: 'Eliminar',
        ),
      ],
    );
  }

  Color _getRoleColor(String rol) {
    switch (rol) {
      case 'super_admin':
        return AppColors.primary;
      case 'admin_tienda':
        return AppColors.secondary;
      case 'gerente':
        return AppColors.info;
      case 'supervisor':
        return AppColors.warning;
      default:
        return AppColors.textSecondary;
    }
  }

  IconData _getRoleIcon(String rol) {
    switch (rol) {
      case 'super_admin':
        return Icons.admin_panel_settings;
      case 'admin_tienda':
        return Icons.store;
      case 'gerente':
        return Icons.business;
      case 'supervisor':
        return Icons.supervisor_account;
      default:
        return Icons.person;
    }
  }

  String _getRoleDisplayText(String rol) {
    switch (rol) {
      case 'super_admin':
        return 'SUPER ADMIN';
      case 'admin_tienda':
        return 'ADMIN TIENDA';
      case 'gerente':
        return 'GERENTE';
      case 'supervisor':
        return 'SUPERVISOR';
      default:
        return rol.toUpperCase();
    }
  }

  void _handleAction(String action, Usuario usuario) {
    switch (action) {
      case 'view':
        _showUsuarioDetails(usuario);
        break;
      case 'edit':
        _showEditUsuarioDialog(usuario);
        break;
      case 'password':
        _showChangePasswordDialog(usuario);
        break;
      case 'toggle':
        _toggleUsuarioStatus(usuario);
        break;
      case 'delete':
        _showDeleteConfirmation(usuario);
        break;
    }
  }

  void _showCreateUsuarioDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuevo Usuario'),
        content: const Text('Funcionalidad de creación de usuario en desarrollo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _showUsuarioDetails(Usuario usuario) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(usuario.nombreCompleto),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Email: ${usuario.email}'),
            Text('Rol: ${_getRoleDisplayText(usuario.rol)}'),
            Text('Tiendas Asignadas: ${usuario.tiendasAsignadas.length}'),
            Text('Estado: ${usuario.activo ? "Activo" : "Inactivo"}'),
            Text('Fecha de Creación: ${usuario.fechaCreacion.toString().split(' ')[0]}'),
            if (usuario.ultimoAcceso != null)
              Text('Último Acceso: ${usuario.ultimoAcceso.toString().split(' ')[0]}'),
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

  void _showEditUsuarioDialog(Usuario usuario) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Editar ${usuario.nombreCompleto}'),
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

  void _showChangePasswordDialog(Usuario usuario) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cambiar Contraseña - ${usuario.nombreCompleto}'),
        content: const Text('Funcionalidad de cambio de contraseña en desarrollo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _toggleUsuarioStatus(Usuario usuario) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${usuario.activo ? "Desactivar" : "Activar"} Usuario'),
        content: Text(
          '¿Estás seguro de que deseas ${usuario.activo ? "desactivar" : "activar"} a "${usuario.nombreCompleto}"?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              // TODO: Implementar cambio de estado
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Funcionalidad en desarrollo')),
              );
            },
            child: Text(usuario.activo ? 'Desactivar' : 'Activar'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(Usuario usuario) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Eliminación'),
        content: Text('¿Estás seguro de que deseas eliminar a "${usuario.nombreCompleto}"?'),
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
