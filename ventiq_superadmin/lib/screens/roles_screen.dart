import 'dart:async';
import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../config/app_routes.dart';
import '../models/superadmin.dart';
import '../models/superadmin_role.dart';
import '../models/usuario.dart';
import '../services/superadmin_role_service.dart';
import '../services/superadmin_user_service.dart';
import '../services/user_service.dart';
import '../widgets/app_drawer.dart';

class RolesScreen extends StatefulWidget {
  const RolesScreen({super.key});

  @override
  State<RolesScreen> createState() => _RolesScreenState();
}

class _RolesScreenState extends State<RolesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  final _roleService = SuperAdminRoleService();
  final _superAdminService = SuperAdminUserService();
  final _userService = UserService();

  List<SuperAdminRole> _roles = [];
  List<SuperAdmin> _superAdmins = [];

  bool _loadingRoles = true;
  bool _loadingUsers = true;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) {
      setState(() => _currentIndex = _tabController.index);
    }
  }

  Future<void> _loadData() async {
    await Future.wait([_loadRoles(), _loadUsers()]);
  }

  Future<void> _loadRoles() async {
    setState(() => _loadingRoles = true);
    try {
      _roles = await _roleService.getRoles(soloActivos: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando roles: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingRoles = false);
    }
  }

  Future<void> _loadUsers() async {
    setState(() => _loadingUsers = true);
    try {
      _superAdmins = await _superAdminService.getSuperAdmins(soloActivos: false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando usuarios: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingUsers = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Roles y Permisos'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.shield), text: 'Roles'),
            Tab(icon: Icon(Icons.people), text: 'Usuarios'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Actualizar',
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: const AppDrawer(),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildRolesTab(),
          _buildUsersTab(),
        ],
      ),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton.extended(
              onPressed: () => _showRoleForm(),
              icon: const Icon(Icons.add),
              label: const Text('Nuevo Rol'),
            )
          : FloatingActionButton.extended(
              onPressed: _showAddUserDialog,
              icon: const Icon(Icons.person_add),
              label: const Text('Agregar Usuario'),
            ),
    );
  }

  Widget _buildRolesTab() {
    if (_loadingRoles) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_roles.isEmpty) {
      return _buildEmptyState(
        icon: Icons.shield_outlined,
        title: 'No hay roles configurados',
        subtitle: 'Crea un rol para asignar permisos de navegación',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _roles.length,
      itemBuilder: (context, index) => _buildRoleCard(_roles[index]),
    );
  }

  Widget _buildUsersTab() {
    if (_loadingUsers) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_superAdmins.isEmpty) {
      return _buildEmptyState(
        icon: Icons.people_outline,
        title: 'No hay usuarios con acceso de superadmin',
        subtitle: 'Agrega un usuario y asígnale un rol',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _superAdmins.length,
      itemBuilder: (context, index) => _buildUserCard(_superAdmins[index]),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: AppColors.textHint),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  String _getRouteLabel(String route) {
    for (final r in AppRoutes.protected) {
      if (r.route == route) return r.label;
    }
    return route;
  }

  Widget _buildRoleCard(SuperAdminRole role) {
    final routeLabels = role.permisos.map(_getRouteLabel).toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
              child: const Icon(Icons.shield, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    role.nombre,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  if (role.descripcion != null && role.descripcion!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        role.descripcion!,
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ),
                  const SizedBox(height: 8),
                  if (routeLabels.isEmpty)
                    Text(
                      'Sin rutas asignadas',
                      style: TextStyle(color: AppColors.textHint, fontSize: 13),
                    )
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: routeLabels.map((label) {
                        return Chip(
                          label: Text(
                            label,
                            style: const TextStyle(fontSize: 11),
                          ),
                          backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                          side: BorderSide(color: AppColors.primary.withValues(alpha: 0.3)),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
            Column(
              children: [
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => _showRoleForm(role: role),
                  tooltip: 'Editar',
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: AppColors.error),
                  onPressed: () => _confirmDelete(role),
                  tooltip: 'Eliminar',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserCard(SuperAdmin admin) {
    final roleName = admin.rol?.nombre ?? 'Sin rol';
    final roleColor = admin.rol != null ? AppColors.primary : AppColors.textSecondary;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.secondary.withValues(alpha: 0.1),
          child: Icon(Icons.person, color: AppColors.secondary),
        ),
        title: Text(admin.nombreCompleto, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(admin.email, style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Row(
              children: [
                Chip(
                  label: Text(
                    roleName,
                    style: TextStyle(color: roleColor, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  backgroundColor: roleColor.withValues(alpha: 0.1),
                  side: BorderSide(color: roleColor),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text(
                    admin.activo ? 'ACTIVO' : 'INACTIVO',
                    style: TextStyle(
                      color: admin.activo ? AppColors.success : AppColors.error,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  backgroundColor: (admin.activo ? AppColors.success : AppColors.error).withValues(alpha: 0.1),
                  side: BorderSide(color: admin.activo ? AppColors.success : AppColors.error),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ],
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _showChangeRoleDialog(admin),
              tooltip: 'Cambiar Rol',
            ),
            IconButton(
              icon: Icon(
                admin.activo ? Icons.toggle_on : Icons.toggle_off,
                color: admin.activo ? AppColors.success : AppColors.error,
              ),
              onPressed: () => _toggleSuperAdmin(admin),
              tooltip: admin.activo ? 'Desactivar' : 'Activar',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRoleForm({SuperAdminRole? role}) async {
    final result = await showDialog<SuperAdminRole>(
      context: context,
      builder: (context) => _RoleFormDialog(role: role),
    );
    if (result != null) await _loadData();
  }

  Future<void> _confirmDelete(SuperAdminRole role) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Rol'),
        content: Text('¿Eliminar el rol "${role.nombre}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true && role.id != null) {
      try {
        await _roleService.deleteRole(role.id!);
        await _loadData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  Future<void> _showChangeRoleDialog(SuperAdmin admin) async {
    await showDialog(
      context: context,
      builder: (context) => _ChangeRoleDialog(
        admin: admin,
        roles: _roles,
        onSaved: _loadData,
      ),
    );
  }

  Future<void> _toggleSuperAdmin(SuperAdmin admin) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(admin.activo ? 'Desactivar acceso' : 'Activar acceso'),
        content: Text(
          '¿${admin.activo ? 'Desactivar' : 'Activar'} el acceso de superadmin de "${admin.nombreCompleto}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(admin.activo ? 'Desactivar' : 'Activar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _superAdminService.toggleSuperAdmin(admin.id, !admin.activo);
        await _loadUsers();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  Future<void> _showAddUserDialog() async {
    await showDialog(
      context: context,
      builder: (context) => _AddSuperAdminDialog(
        roles: _roles,
        userService: _userService,
        superAdminService: _superAdminService,
        onSaved: _loadData,
      ),
    );
  }
}

class _RoleFormDialog extends StatefulWidget {
  final SuperAdminRole? role;

  const _RoleFormDialog({this.role});

  @override
  State<_RoleFormDialog> createState() => _RoleFormDialogState();
}

class _RoleFormDialogState extends State<_RoleFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _service = SuperAdminRoleService();

  late final List<String> _selectedRoutes;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.role?.nombre ?? '';
    _descController.text = widget.role?.descripcion ?? '';
    _selectedRoutes = List<String>.from(widget.role?.permisos ?? []);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final role = SuperAdminRole(
        id: widget.role?.id,
        nombre: _nameController.text.trim(),
        descripcion: _descController.text.trim().isEmpty
            ? null
            : _descController.text.trim(),
        permisos: _selectedRoutes.toList(),
        activo: widget.role?.activo ?? true,
        createdAt: widget.role?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final saved = widget.role == null
          ? await _service.createRole(role)
          : await _service.updateRole(role);

      if (mounted) Navigator.pop(context, saved);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.role == null ? 'Nuevo Rol' : 'Editar Rol'),
      content: SizedBox(
        width: 600,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del rol',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Requerido' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descController,
                  decoration: const InputDecoration(
                    labelText: 'Descripción',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Permisos de navegación',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  'Selecciona las rutas a las que los usuarios con este rol podrán acceder.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 12),
                _buildRoutesSelector(),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _save,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }

  Widget _buildRoutesSelector() {
    final groups = <String?, List<AppRoute>>{};
    for (final route in AppRoutes.protected) {
      groups.putIfAbsent(route.group, () => []).add(route);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: groups.entries.map((entry) {
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (entry.key != null)
                  Text(
                    entry.key!,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: entry.value.map((route) {
                    final selected = _selectedRoutes.contains(route.route);
                    return FilterChip(
                      label: Text(route.label),
                      selected: selected,
                      onSelected: (value) {
                        setState(() {
                          if (value) {
                            _selectedRoutes.add(route.route);
                          } else {
                            _selectedRoutes.remove(route.route);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ChangeRoleDialog extends StatefulWidget {
  final SuperAdmin admin;
  final List<SuperAdminRole> roles;
  final VoidCallback onSaved;

  const _ChangeRoleDialog({
    required this.admin,
    required this.roles,
    required this.onSaved,
  });

  @override
  State<_ChangeRoleDialog> createState() => _ChangeRoleDialogState();
}

class _ChangeRoleDialogState extends State<_ChangeRoleDialog> {
  final _service = SuperAdminUserService();
  SuperAdminRole? _selectedRole;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedRole = widget.admin.rol;
  }

  Future<void> _save() async {
    setState(() => _isLoading = true);
    try {
      await _service.assignRole(widget.admin.id, _selectedRole?.id);
      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cambiar Rol'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.admin.nombreCompleto),
            const SizedBox(height: 16),
            DropdownButtonFormField<SuperAdminRole?>(
              key: ValueKey('change_role_${widget.admin.id}'),
              initialValue: _selectedRole,
              decoration: const InputDecoration(
                labelText: 'Rol',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Sin rol (acceso legacy)'),
                ),
                ...widget.roles.map((role) {
                  return DropdownMenuItem(
                    value: role,
                    child: Text(role.nombre),
                  );
                }),
              ],
              onChanged: (value) => setState(() => _selectedRole = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _save,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

class _AddSuperAdminDialog extends StatefulWidget {
  final List<SuperAdminRole> roles;
  final UserService userService;
  final SuperAdminUserService superAdminService;
  final VoidCallback onSaved;

  const _AddSuperAdminDialog({
    required this.roles,
    required this.userService,
    required this.superAdminService,
    required this.onSaved,
  });

  @override
  State<_AddSuperAdminDialog> createState() => _AddSuperAdminDialogState();
}

class _AddSuperAdminDialogState extends State<_AddSuperAdminDialog> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  List<Usuario> _users = [];
  bool _isSearching = false;
  bool _isSaving = false;
  Usuario? _selectedUser;
  SuperAdminRole? _selectedRole;

  @override
  void initState() {
    super.initState();
    _searchUsers('');
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      _searchUsers(value);
    });
  }

  Future<void> _searchUsers(String search) async {
    setState(() => _isSearching = true);
    try {
      final result = await widget.userService.getPaginatedUsersSummary(
        limit: 20,
        offset: 0,
        search: search,
        category: 'todos',
      );
      if (mounted) {
        setState(() {
          _users = List<Usuario>.from(result['users']);
          _selectedUser = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error buscando usuarios: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _save() async {
    if (_selectedUser == null) return;
    setState(() => _isSaving = true);
    try {
      await widget.superAdminService.createOrEnableSuperAdmin(
        _selectedUser!,
        _selectedRole?.id,
      );
      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Agregar Superadmin'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Buscar usuario',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: _onSearchChanged,
            ),
            const SizedBox(height: 16),
            if (_isSearching)
              const Center(child: CircularProgressIndicator())
            else
              DropdownButtonFormField<Usuario?>(
                key: ValueKey('add_user_${_searchController.text}'),
                initialValue: _selectedUser,
                decoration: const InputDecoration(
                  labelText: 'Usuario',
                  border: OutlineInputBorder(),
                ),
                items: _users.map((user) {
                  return DropdownMenuItem(
                    value: user,
                    child: Text('${user.nombreCompleto} (${user.email})'),
                  );
                }).toList(),
                onChanged: (value) => setState(() => _selectedUser = value),
              ),
            const SizedBox(height: 16),
            DropdownButtonFormField<SuperAdminRole?>(
              key: ValueKey('add_role_${_selectedUser?.id ?? 'empty'}'),
              initialValue: _selectedRole,
              decoration: const InputDecoration(
                labelText: 'Rol a asignar',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Sin rol (acceso legacy)'),
                ),
                ...widget.roles.map((role) {
                  return DropdownMenuItem(
                    value: role,
                    child: Text(role.nombre),
                  );
                }),
              ],
              onChanged: (value) => setState(() => _selectedRole = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _isSaving || _selectedUser == null ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}
