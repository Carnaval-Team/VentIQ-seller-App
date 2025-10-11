import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/vendedor_service.dart';
import '../services/tpv_service.dart';
import '../services/user_preferences_service.dart';
import '../config/app_colors.dart';

class VendedorManagementScreen extends StatefulWidget {
  @override
  _VendedorManagementScreenState createState() =>
      _VendedorManagementScreenState();
}

class _VendedorManagementScreenState extends State<VendedorManagementScreen> {
  List<Map<String, dynamic>> _vendedores = [];
  List<Map<String, dynamic>> _trabajadoresDisponibles = [];
  List<Map<String, dynamic>> _tpvsDisponibles = [];
  bool _isLoading = true;
  String _searchTerm = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        VendedorService.getVendedoresByStore(),
        VendedorService.getTrabajadoresDisponibles(),
        TpvService.getTpvsDisponibles(),
      ]);

      setState(() {
        _vendedores = results[0];
        _trabajadoresDisponibles = results[1];
        _tpvsDisponibles = results[2];
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Error cargando datos: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Gestión de Vendedores'),
        backgroundColor: AppColors.primary,
        actions: [IconButton(icon: Icon(Icons.refresh), onPressed: _loadData)],
      ),
      body: _isLoading ? _buildLoadingWidget() : _buildContent(),
      floatingActionButton: _buildFloatingActionButtons(),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        _buildSearchBar(),
        _buildStatsCards(),
        Expanded(child: _buildVendedoresList()),
      ],
    );
  }

  Widget _buildFloatingActionButtons() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.extended(
          heroTag: "existing_worker",
          onPressed: _showCreateFromExistingWorkerDialog,
          backgroundColor: AppColors.success,
          icon: Icon(Icons.person_add),
          label: Text('Desde Trabajador'),
        ),
        SizedBox(height: 10),
        FloatingActionButton.extended(
          heroTag: "new_worker",
          onPressed: _showCreateFromScratchDialog,
          backgroundColor: AppColors.primary,
          icon: Icon(Icons.add_business),
          label: Text('Crear Nuevo'),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: EdgeInsets.all(16),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Buscar vendedores...',
          prefixIcon: Icon(Icons.search),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onChanged: (value) => setState(() => _searchTerm = value),
      ),
    );
  }

  Widget _buildStatsCards() {
    return Container(
      height: 100,
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              'Total Vendedores',
              _vendedores.length.toString(),
              Icons.people,
              AppColors.primary,
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: _buildStatCard(
              'Trabajadores Disponibles',
              _trabajadoresDisponibles.length.toString(),
              Icons.person_outline,
              AppColors.success,
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: _buildStatCard(
              'TPVs Libres',
              _tpvsDisponibles.length.toString(),
              Icons.point_of_sale,
              AppColors.warning,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: TextStyle(fontSize: 10),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVendedoresList() {
    final filteredVendedores =
        _vendedores.where((vendedor) {
          if (_searchTerm.isEmpty) return true;
          final trabajador = vendedor['trabajador'] as Map<String, dynamic>?;
          final tpv = vendedor['tpv'] as Map<String, dynamic>?;
          final nombres =
              trabajador?['nombres']?.toString().toLowerCase() ?? '';
          final apellidos =
              trabajador?['apellidos']?.toString().toLowerCase() ?? '';
          final tpvNombre =
              tpv?['denominacion']?.toString().toLowerCase() ?? '';
          final term = _searchTerm.toLowerCase();
          return nombres.contains(term) ||
              apellidos.contains(term) ||
              tpvNombre.contains(term);
        }).toList();

    if (filteredVendedores.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              _searchTerm.isEmpty
                  ? 'No hay vendedores registrados'
                  : 'No se encontraron vendedores',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: filteredVendedores.length,
      itemBuilder:
          (context, index) => _buildVendedorCard(filteredVendedores[index]),
    );
  }

  Widget _buildVendedorCard(Map<String, dynamic> vendedor) {
    final trabajador = vendedor['trabajador'] as Map<String, dynamic>?;
    final tpv = vendedor['tpv'] as Map<String, dynamic>?;
    final nombre =
        '${trabajador?['nombres'] ?? ''} ${trabajador?['apellidos'] ?? ''}'
            .trim();
    final tpvNombre = tpv?['denominacion'] ?? 'Sin TPV';

    return Card(
      margin: EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.primary,
          child: Text(
            nombre.isNotEmpty ? nombre[0].toUpperCase() : 'V',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(
          nombre.isNotEmpty ? nombre : 'Sin nombre',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.point_of_sale, size: 16, color: AppColors.success),
                SizedBox(width: 4),
                Text('TPV: $tpvNombre'),
              ],
            ),
            SizedBox(height: 2),
            Row(
              children: [
                Icon(Icons.badge, size: 16, color: Colors.grey),
                SizedBox(width: 4),
                Text('ID: ${vendedor['id']}'),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) => _handleVendedorAction(value, vendedor),
          itemBuilder:
              (context) => [
                PopupMenuItem(
                  value: 'reasignar',
                  child: Row(
                    children: [
                      Icon(Icons.swap_horiz, color: AppColors.warning),
                      SizedBox(width: 8),
                      Text('Reasignar TPV'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'desasignar',
                  child: Row(
                    children: [
                      Icon(Icons.person_remove, color: AppColors.error),
                      SizedBox(width: 8),
                      Text('Desasignar'),
                    ],
                  ),
                ),
              ],
        ),
      ),
    );
  }

  // MÉTODOS AUXILIARES
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.success,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _buildLoadingWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppColors.primary),
          SizedBox(height: 16),
          Text('Cargando vendedores...'),
        ],
      ),
    );
  }

  void _handleVendedorAction(String action, Map<String, dynamic> vendedor) {
    switch (action) {
      case 'reasignar':
        _showReasignarDialog(vendedor);
        break;
      case 'desasignar':
        _showDesasignarDialog(vendedor);
        break;
    }
  }

  void _showReasignarDialog(Map<String, dynamic> vendedor) {
    if (_tpvsDisponibles.isEmpty) {
      _showError('No hay TPVs disponibles para reasignar');
      return;
    }

    final trabajador = vendedor['trabajador'] as Map<String, dynamic>?;
    final currentTpv = vendedor['tpv'] as Map<String, dynamic>?;
    final nombre =
        '${trabajador?['nombres'] ?? ''} ${trabajador?['apellidos'] ?? ''}'
            .trim();

    showDialog(
      context: context,
      builder: (context) => ReasignarVendedorDialog(
        vendedor: vendedor,
        vendedorNombre: nombre,
        currentTpvId: currentTpv?['id'],
        tpvsDisponibles: _tpvsDisponibles,
        onVendedorReasignado: () {
          Navigator.pop(context);
          _loadData();
          _showSuccess('Vendedor reasignado exitosamente');
        },
      ),
    );
  }

  void _showDesasignarDialog(Map<String, dynamic> vendedor) {
    final trabajador = vendedor['trabajador'] as Map<String, dynamic>?;
    final nombre =
        '${trabajador?['nombres'] ?? ''} ${trabajador?['apellidos'] ?? ''}'
            .trim();

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.warning, color: AppColors.warning),
                SizedBox(width: 8),
                Text('Confirmar Desasignación'),
              ],
            ),
            content: Text(
              '¿Estás seguro de que deseas desasignar a $nombre como vendedor?\n\nEsta acción eliminará su asignación al TPV pero mantendrá el historial de operaciones.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => _desasignarVendedor(vendedor['id']),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                ),
                child: Text('Desasignar'),
              ),
            ],
          ),
    );
  }

  Future<void> _desasignarVendedor(int vendedorId) async {
    Navigator.pop(context);
    try {
      final success = await VendedorService.desasignarVendedorDeTpv(vendedorId);
      if (success) {
        _loadData();
        _showSuccess('Vendedor desasignado exitosamente');
      } else {
        _showError('Error al desasignar vendedor');
      }
    } catch (e) {
      _showError('Error: $e');
    }
  }

  void _showCreateFromExistingWorkerDialog() {
    if (_trabajadoresDisponibles.isEmpty) {
      _showError(
        'No hay trabajadores disponibles para asignar como vendedores',
      );
      return;
    }
    if (_tpvsDisponibles.isEmpty) {
      _showError('No hay TPVs disponibles para asignar');
      return;
    }

    showDialog(
      context: context,
      builder:
          (context) => CreateVendedorFromWorkerDialog(
            trabajadoresDisponibles: _trabajadoresDisponibles,
            tpvsDisponibles: _tpvsDisponibles,
            onVendedorCreated: () {
              Navigator.pop(context);
              _loadData();
              _showSuccess('Vendedor creado exitosamente');
            },
          ),
    );
  }

  void _showCreateFromScratchDialog() {
    if (_tpvsDisponibles.isEmpty) {
      _showError('No hay TPVs disponibles para asignar');
      return;
    }

    showDialog(
      context: context,
      builder:
          (context) => CreateVendedorFromScratchDialog(
            tpvsDisponibles: _tpvsDisponibles,
            onVendedorCreated: () {
              Navigator.pop(context);
              _loadData();
              _showSuccess('Trabajador y vendedor creados exitosamente');
            },
          ),
    );
  }
}

// DIÁLOGO PARA CREAR VENDEDOR DESDE TRABAJADOR EXISTENTE
class CreateVendedorFromWorkerDialog extends StatefulWidget {
  final List<Map<String, dynamic>> trabajadoresDisponibles;
  final List<Map<String, dynamic>> tpvsDisponibles;
  final VoidCallback onVendedorCreated;

  CreateVendedorFromWorkerDialog({
    required this.trabajadoresDisponibles,
    required this.tpvsDisponibles,
    required this.onVendedorCreated,
  });

  @override
  _CreateVendedorFromWorkerDialogState createState() =>
      _CreateVendedorFromWorkerDialogState();
}

class _CreateVendedorFromWorkerDialogState
    extends State<CreateVendedorFromWorkerDialog> {
  Map<String, dynamic>? _selectedTrabajador;
  Map<String, dynamic>? _selectedTpv;
  bool _isCreating = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.person_add, color: AppColors.success),
          SizedBox(width: 8),
          Text('Crear Vendedor desde Trabajador'),
        ],
      ),
      content: Container(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Selecciona un trabajador existente y asígnalo a un TPV:',
              style: TextStyle(color: Colors.grey[600]),
            ),
            SizedBox(height: 20),

            // Selector de Trabajador
            Text('Trabajador *', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<Map<String, dynamic>>(
                  value: _selectedTrabajador,
                  hint: Text('  Seleccionar trabajador...'),
                  isExpanded: true,
                  items:
                      widget.trabajadoresDisponibles.map((trabajador) {
                        final nombre =
                            '${trabajador['nombres']} ${trabajador['apellidos']}';
                        return DropdownMenuItem(
                          value: trabajador,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: AppColors.primary,
                                  child: Text(
                                    nombre[0].toUpperCase(),
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        nombre,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Text(
                                        'ID: ${trabajador['id']}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                  onChanged:
                      (value) => setState(() => _selectedTrabajador = value),
                ),
              ),
            ),

            SizedBox(height: 20),

            // Selector de TPV
            Text('TPV *', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<Map<String, dynamic>>(
                  value: _selectedTpv,
                  hint: Text('  Seleccionar TPV...'),
                  isExpanded: true,
                  items:
                      widget.tpvsDisponibles.map((tpv) {
                        return DropdownMenuItem(
                          value: tpv,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.point_of_sale,
                                  color: AppColors.success,
                                ),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        tpv['denominacion'],
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Text(
                                        'ID: ${tpv['id']}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                  onChanged: (value) => setState(() => _selectedTpv = value),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isCreating ? null : () => Navigator.pop(context),
          child: Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed:
              _isCreating || _selectedTrabajador == null || _selectedTpv == null
                  ? null
                  : _createVendedor,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
          child:
              _isCreating
                  ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : Text('Crear Vendedor'),
        ),
      ],
    );
  }

  Future<void> _createVendedor() async {
    setState(() => _isCreating = true);

    try {
      final currentUser = Supabase.instance.client.auth.currentUser;

      if (currentUser == null) {
        throw Exception('Usuario no autenticado');
      }

      final success = await VendedorService.createVendedor(
        trabajadorId: _selectedTrabajador!['id'],
        tpvId: _selectedTpv!['id'],
        uuid: currentUser.id,
      );

      if (success) {
        widget.onVendedorCreated();
      } else {
        throw Exception('Error al crear el vendedor');
      }
    } catch (e) {
      setState(() => _isCreating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
      );
    }
  }
}

// DIÁLOGO PARA CREAR VENDEDOR DESDE CERO
class CreateVendedorFromScratchDialog extends StatefulWidget {
  final List<Map<String, dynamic>> tpvsDisponibles;
  final VoidCallback onVendedorCreated;

  CreateVendedorFromScratchDialog({
    required this.tpvsDisponibles,
    required this.onVendedorCreated,
  });

  @override
  _CreateVendedorFromScratchDialogState createState() =>
      _CreateVendedorFromScratchDialogState();
}

class _CreateVendedorFromScratchDialogState
    extends State<CreateVendedorFromScratchDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nombresController = TextEditingController();
  final _apellidosController = TextEditingController();
  Map<String, dynamic>? _selectedTpv;
  Map<String, dynamic>? _selectedRol;
  bool _isCreating = false;
  List<Map<String, dynamic>> _roles = [];

  @override
  void initState() {
    super.initState();
    _loadRoles();
  }

  Future<void> _loadRoles() async {
    try {
      final roles = await Supabase.instance.client
          .from('app_nom_roll')
          .select('id, denominacion')
          .order('denominacion');
      setState(() => _roles = List<Map<String, dynamic>>.from(roles));
    } catch (e) {
      print('Error cargando roles: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.add_business, color: AppColors.primary),
          SizedBox(width: 8),
          Text('Crear Trabajador y Vendedor'),
        ],
      ),
      content: Container(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Crea un nuevo trabajador y asígnalo como vendedor:',
                style: TextStyle(color: Colors.grey[600]),
              ),
              SizedBox(height: 20),

              // Nombres
              TextFormField(
                controller: _nombresController,
                decoration: InputDecoration(
                  labelText: 'Nombres *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Los nombres son obligatorios';
                  }
                  return null;
                },
              ),

              SizedBox(height: 16),

              // Apellidos
              TextFormField(
                controller: _apellidosController,
                decoration: InputDecoration(
                  labelText: 'Apellidos *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Los apellidos son obligatorios';
                  }
                  return null;
                },
              ),

              SizedBox(height: 16),

              // Selector de Rol
              Text('Rol *', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<Map<String, dynamic>>(
                    value: _selectedRol,
                    hint: Text('  Seleccionar rol...'),
                    isExpanded: true,
                    items:
                        _roles.map((rol) {
                          return DropdownMenuItem(
                            value: rol,
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text(rol['denominacion']),
                            ),
                          );
                        }).toList(),
                    onChanged: (value) => setState(() => _selectedRol = value),
                  ),
                ),
              ),

              SizedBox(height: 16),

              // Selector de TPV
              Text('TPV *', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<Map<String, dynamic>>(
                    value: _selectedTpv,
                    hint: Text('  Seleccionar TPV...'),
                    isExpanded: true,
                    items:
                        widget.tpvsDisponibles.map((tpv) {
                          return DropdownMenuItem(
                            value: tpv,
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.point_of_sale,
                                    color: AppColors.success,
                                  ),
                                  SizedBox(width: 12),
                                  Text(tpv['denominacion']),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                    onChanged: (value) => setState(() => _selectedTpv = value),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isCreating ? null : () => Navigator.pop(context),
          child: Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed:
              _isCreating || !_canCreate()
                  ? null
                  : _createTrabajadorAndVendedor,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          child:
              _isCreating
                  ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : Text('Crear Todo'),
        ),
      ],
    );
  }

  bool _canCreate() {
    return _formKey.currentState?.validate() == true &&
        _selectedRol != null &&
        _selectedTpv != null;
  }

  Future<void> _createTrabajadorAndVendedor() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isCreating = true);

    try {
      final userPrefs = UserPreferencesService();
      final storeId = await userPrefs.getIdTienda();
      final currentUser = Supabase.instance.client.auth.currentUser;

      if (storeId == null || currentUser == null) {
        throw Exception('Error de autenticación o tienda');
      }

      // 1. Crear trabajador
      final trabajadorData = {
        'nombres': _nombresController.text.trim(),
        'apellidos': _apellidosController.text.trim(),
        'id_tienda': storeId,
        'id_roll': _selectedRol!['id'],
        'created_at': DateTime.now().toIso8601String(),
      };

      final trabajadorResult =
          await Supabase.instance.client
              .from('app_dat_trabajadores')
              .insert(trabajadorData)
              .select('id')
              .single();

      final trabajadorId = trabajadorResult['id'];

      // 2. Crear vendedor
      final success = await VendedorService.createVendedor(
        trabajadorId: trabajadorId,
        tpvId: _selectedTpv!['id'],
        uuid: currentUser.id,
      );

      if (success) {
        widget.onVendedorCreated();
      } else {
        throw Exception('Error al crear el vendedor');
      }
    } catch (e) {
      setState(() => _isCreating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  void dispose() {
    _nombresController.dispose();
    _apellidosController.dispose();
    super.dispose();
  }
}

// DIÁLOGO PARA REASIGNAR VENDEDOR A OTRO TPV
class ReasignarVendedorDialog extends StatefulWidget {
  final Map<String, dynamic> vendedor;
  final String vendedorNombre;
  final int? currentTpvId;
  final List<Map<String, dynamic>> tpvsDisponibles;
  final VoidCallback onVendedorReasignado;

  ReasignarVendedorDialog({
    required this.vendedor,
    required this.vendedorNombre,
    required this.currentTpvId,
    required this.tpvsDisponibles,
    required this.onVendedorReasignado,
  });

  @override
  _ReasignarVendedorDialogState createState() =>
      _ReasignarVendedorDialogState();
}

class _ReasignarVendedorDialogState extends State<ReasignarVendedorDialog> {
  Map<String, dynamic>? _selectedTpv;
  bool _isReasignando = false;

  @override
  Widget build(BuildContext context) {
    // Filtrar TPVs disponibles (excluir el TPV actual)
    final tpvsParaReasignar = widget.tpvsDisponibles
        .where((tpv) => tpv['id'] != widget.currentTpvId)
        .toList();

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.swap_horiz, color: AppColors.warning),
          SizedBox(width: 8),
          Text('Reasignar Vendedor'),
        ],
      ),
      content: Container(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reasignar a ${widget.vendedorNombre} a un nuevo TPV:',
              style: TextStyle(color: Colors.grey[600]),
            ),
            SizedBox(height: 16),

            // Información del vendedor actual
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.primary,
                    child: Text(
                      widget.vendedorNombre.isNotEmpty
                          ? widget.vendedorNombre[0].toUpperCase()
                          : 'V',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.vendedorNombre,
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'TPV Actual: ${widget.vendedor['tpv']?['denominacion'] ?? 'Sin TPV'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 20),

            if (tpvsParaReasignar.isEmpty)
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No hay otros TPVs disponibles para reasignar',
                        style: TextStyle(color: Colors.orange[800]),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              // Selector de nuevo TPV
              Text('Nuevo TPV *', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<Map<String, dynamic>>(
                    value: _selectedTpv,
                    hint: Text('  Seleccionar nuevo TPV...'),
                    isExpanded: true,
                    items: tpvsParaReasignar.map((tpv) {
                      return DropdownMenuItem(
                        value: tpv,
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              Icon(
                                Icons.point_of_sale,
                                color: AppColors.success,
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      tpv['denominacion'],
                                      style: TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      'ID: ${tpv['id']}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) => setState(() => _selectedTpv = value),
                  ),
                ),
              ),

              SizedBox(height: 16),

              // Advertencia sobre validaciones
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber[200]!),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info, color: Colors.amber[700], size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Validaciones automáticas:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.amber[800],
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '• No debe tener turnos abiertos\n• No debe tener operaciones pendientes\n• El nuevo TPV debe estar disponible',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.amber[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isReasignando ? null : () => Navigator.pop(context),
          child: Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _isReasignando ||
                  tpvsParaReasignar.isEmpty ||
                  _selectedTpv == null
              ? null
              : _reasignarVendedor,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
          child: _isReasignando
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('Reasignar'),
        ),
      ],
    );
  }

  Future<void> _reasignarVendedor() async {
    setState(() => _isReasignando = true);

    try {
      final success = await VendedorService.asignarVendedorATpv(
        vendedorId: widget.vendedor['id'],
        tpvId: _selectedTpv!['id'],
      );

      if (success) {
        widget.onVendedorReasignado();
      } else {
        throw Exception('Error al reasignar vendedor');
      }
    } catch (e) {
      setState(() => _isReasignando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
}
