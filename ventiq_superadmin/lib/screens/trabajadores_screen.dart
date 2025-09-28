import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_colors.dart';
import '../widgets/app_drawer.dart';
import '../utils/platform_utils.dart';

class TrabajadoresScreen extends StatefulWidget {
  const TrabajadoresScreen({super.key});

  @override
  State<TrabajadoresScreen> createState() => _TrabajadoresScreenState();
}

class _TrabajadoresScreenState extends State<TrabajadoresScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _trabajadores = [];
  List<Map<String, dynamic>> _filteredTrabajadores = [];
  List<Map<String, dynamic>> _tiendas = [];
  List<Map<String, dynamic>> _roles = [];
  
  bool _isLoading = true;
  String _searchQuery = '';
  int? _selectedTienda;
  int? _selectedRol;

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
      
      // Cargar roles
      final rolesResponse = await _supabase
          .from('seg_roll')
          .select('id, denominacion')
          .order('denominacion');
      
      // Cargar trabajadores con información relacionada
      final trabajadoresResponse = await _supabase
          .from('app_dat_trabajadores')
          .select('''
            id,
            id_tienda,
            id_roll,
            nombres,
            apellidos,
            created_at,
            app_dat_tienda!inner(
              denominacion,
              ubicacion
            ),
            seg_roll!inner(
              denominacion
            )
          ''')
          .order('created_at', ascending: false);
      
      // Formatear datos de trabajadores con información adicional
      final trabajadores = <Map<String, dynamic>>[];
      
      for (var trabajador in trabajadoresResponse) {
        final tienda = trabajador['app_dat_tienda'];
        final rol = trabajador['seg_roll'];
        
        // Obtener información adicional según el rol
        Map<String, dynamic>? infoAdicional;
        String tipoTrabajador = rol?['denominacion'] ?? 'Sin rol';
        
        // Verificar si es gerente
        final gerenteResponse = await _supabase
            .from('app_dat_gerente')
            .select('uuid')
            .eq('id_trabajador', trabajador['id'])
            .maybeSingle();
        
        if (gerenteResponse != null) {
          tipoTrabajador = 'Gerente';
          infoAdicional = {'uuid': gerenteResponse['uuid'], 'tipo': 'Gerente'};
        }
        
        // Verificar si es supervisor
        if (infoAdicional == null) {
          final supervisorResponse = await _supabase
              .from('app_dat_supervisor')
              .select('uuid')
              .eq('id_trabajador', trabajador['id'])
              .maybeSingle();
          
          if (supervisorResponse != null) {
            tipoTrabajador = 'Supervisor';
            infoAdicional = {'uuid': supervisorResponse['uuid'], 'tipo': 'Supervisor'};
          }
        }
        
        // Verificar si es vendedor
        if (infoAdicional == null) {
          final vendedorResponse = await _supabase
              .from('app_dat_vendedor')
              .select('''
                uuid,
                numero_confirmacion,
                app_dat_tpv!inner(
                  denominacion
                )
              ''')
              .eq('id_trabajador', trabajador['id'])
              .maybeSingle();
          
          if (vendedorResponse != null) {
            tipoTrabajador = 'Vendedor';
            infoAdicional = {
              'uuid': vendedorResponse['uuid'],
              'tipo': 'Vendedor',
              'tpv': vendedorResponse['app_dat_tpv']?['denominacion'],
              'numero_confirmacion': vendedorResponse['numero_confirmacion'],
            };
          }
        }
        
        // Verificar si es almacenero
        if (infoAdicional == null) {
          final almaceneroResponse = await _supabase
              .from('app_dat_almacenero')
              .select('''
                uuid,
                app_dat_almacen!inner(
                  denominacion
                )
              ''')
              .eq('id_trabajador', trabajador['id'])
              .maybeSingle();
          
          if (almaceneroResponse != null) {
            tipoTrabajador = 'Almacenero';
            infoAdicional = {
              'uuid': almaceneroResponse['uuid'],
              'tipo': 'Almacenero',
              'almacen': almaceneroResponse['app_dat_almacen']?['denominacion'],
            };
          }
        }
        
        trabajadores.add({
          ...trabajador,
          'tienda_nombre': tienda?['denominacion'] ?? 'Sin tienda',
          'tienda_ubicacion': tienda?['ubicacion'] ?? 'Sin ubicación',
          'rol_nombre': rol?['denominacion'] ?? 'Sin rol',
          'tipo_trabajador': tipoTrabajador,
          'info_adicional': infoAdicional,
        });
      }
      
      if (mounted) {
        setState(() {
          _tiendas = List<Map<String, dynamic>>.from(tiendasResponse);
          _roles = List<Map<String, dynamic>>.from(rolesResponse);
          _trabajadores = trabajadores;
          _filteredTrabajadores = trabajadores;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error cargando trabajadores: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar trabajadores: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _filterTrabajadores() {
    setState(() {
      _filteredTrabajadores = _trabajadores.where((trabajador) {
        final nombreCompleto = '${trabajador['nombres']} ${trabajador['apellidos']}'.toLowerCase();
        final matchesSearch = 
            nombreCompleto.contains(_searchQuery.toLowerCase()) ||
            trabajador['tienda_nombre'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
            trabajador['tipo_trabajador'].toString().toLowerCase().contains(_searchQuery.toLowerCase());
        
        final matchesTienda = _selectedTienda == null ||
                            trabajador['id_tienda'] == _selectedTienda;
        
        final matchesRol = _selectedRol == null ||
                         trabajador['id_roll'] == _selectedRol;
        
        return matchesSearch && matchesTienda && matchesRol;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isDesktop = PlatformUtils.shouldUseDesktopLayout(screenSize.width);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Trabajadores'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Actualizar',
          ),
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: () => _showCreateTrabajadorDialog(),
            tooltip: 'Nuevo Trabajador',
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
                      labelText: 'Buscar trabajador',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                      _filterTrabajadores();
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
                      _filterTrabajadores();
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<int?>(
                    value: _selectedRol,
                    decoration: const InputDecoration(
                      labelText: 'Rol',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Todos')),
                      ..._roles.map((rol) => DropdownMenuItem(
                        value: rol['id'] as int,
                        child: Text(rol['denominacion']),
                      )),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedRol = value;
                      });
                      _filterTrabajadores();
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
    final gerentes = _trabajadores.where((t) => t['tipo_trabajador'] == 'Gerente').length;
    final supervisores = _trabajadores.where((t) => t['tipo_trabajador'] == 'Supervisor').length;
    final vendedores = _trabajadores.where((t) => t['tipo_trabajador'] == 'Vendedor').length;
    final almaceneros = _trabajadores.where((t) => t['tipo_trabajador'] == 'Almacenero').length;
    
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Total',
            _trabajadores.length.toString(),
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
            'Vendedores',
            vendedores.toString(),
            Icons.point_of_sale,
            AppColors.warning,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'Almaceneros',
            almaceneros.toString(),
            Icons.warehouse,
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
              'Lista de Trabajadores',
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
                      DataColumn(label: Text('Tipo')),
                      DataColumn(label: Text('Tienda')),
                      DataColumn(label: Text('Asignación')),
                      DataColumn(label: Text('Estado')),
                      DataColumn(label: Text('Fecha Registro')),
                      DataColumn(label: Text('Acciones')),
                    ],
                    rows: _filteredTrabajadores.map((trabajador) {
                      final info = trabajador['info_adicional'];
                      String asignacion = '-';
                      
                      if (info != null) {
                        if (info['tpv'] != null) {
                          asignacion = 'TPV: ${info['tpv']}';
                        } else if (info['almacen'] != null) {
                          asignacion = 'Almacén: ${info['almacen']}';
                        }
                      }
                      
                      return DataRow(
                        cells: [
                          DataCell(
                            Text('${trabajador['nombres']} ${trabajador['apellidos']}'),
                          ),
                          DataCell(
                            _buildRoleChip(trabajador['tipo_trabajador']),
                          ),
                          DataCell(
                            Text(trabajador['tienda_nombre']),
                          ),
                          DataCell(
                            Text(asignacion),
                          ),
                          DataCell(
                            _buildStatusChip(info != null),
                          ),
                          DataCell(
                            Text(_formatDate(trabajador['created_at'])),
                          ),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.visibility),
                                  onPressed: () => _showTrabajadorDetails(trabajador),
                                  tooltip: 'Ver Detalles',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () => _showEditTrabajadorDialog(trabajador),
                                  tooltip: 'Editar',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: AppColors.error),
                                  onPressed: () => _showDeleteConfirmation(trabajador),
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
      itemCount: _filteredTrabajadores.length,
      itemBuilder: (context, index) {
        final trabajador = _filteredTrabajadores[index];
        final info = trabajador['info_adicional'];
        
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: _getRoleColor(trabajador['tipo_trabajador']).withOpacity(0.1),
              child: Icon(
                _getRoleIcon(trabajador['tipo_trabajador']),
                color: _getRoleColor(trabajador['tipo_trabajador']),
              ),
            ),
            title: Text(
              '${trabajador['nombres']} ${trabajador['apellidos']}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(trabajador['tienda_nombre']),
                const SizedBox(height: 4),
                _buildRoleChip(trabajador['tipo_trabajador']),
              ],
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (info != null) ...[
                      if (info['uuid'] != null)
                        _buildInfoRow(Icons.fingerprint, 'UUID', info['uuid']),
                      if (info['tpv'] != null)
                        _buildInfoRow(Icons.point_of_sale, 'TPV', info['tpv']),
                      if (info['almacen'] != null)
                        _buildInfoRow(Icons.warehouse, 'Almacén', info['almacen']),
                      if (info['numero_confirmacion'] != null)
                        _buildInfoRow(Icons.verified_user, 'N° Confirmación', info['numero_confirmacion']),
                    ],
                    _buildInfoRow(Icons.location_on, 'Ubicación', trabajador['tienda_ubicacion']),
                    _buildInfoRow(Icons.calendar_today, 'Registro', _formatDate(trabajador['created_at'])),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.visibility),
                          label: const Text('Ver'),
                          onPressed: () => _showTrabajadorDetails(trabajador),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.edit),
                          label: const Text('Editar'),
                          onPressed: () => _showEditTrabajadorDialog(trabajador),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
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

  Widget _buildStatusChip(bool hasInfo) {
    final color = hasInfo ? AppColors.success : AppColors.warning;
    final text = hasInfo ? 'ACTIVO' : 'PENDIENTE';
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'gerente':
        return AppColors.success;
      case 'supervisor':
        return AppColors.info;
      case 'vendedor':
        return AppColors.warning;
      case 'almacenero':
        return AppColors.secondary;
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
      case 'vendedor':
        return Icons.point_of_sale;
      case 'almacenero':
        return Icons.warehouse;
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

  void _showCreateTrabajadorDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuevo Trabajador'),
        content: const Text('Funcionalidad de creación de trabajador en desarrollo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _showTrabajadorDetails(Map<String, dynamic> trabajador) {
    final info = trabajador['info_adicional'];
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${trabajador['nombres']} ${trabajador['apellidos']}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ID: ${trabajador['id']}'),
              Text('Tipo: ${trabajador['tipo_trabajador']}'),
              Text('Rol: ${trabajador['rol_nombre']}'),
              Text('Tienda: ${trabajador['tienda_nombre']}'),
              Text('Ubicación: ${trabajador['tienda_ubicacion']}'),
              if (info != null) ...[
                const Divider(),
                if (info['uuid'] != null)
                  Text('UUID: ${info['uuid']}'),
                if (info['tpv'] != null)
                  Text('TPV Asignado: ${info['tpv']}'),
                if (info['almacen'] != null)
                  Text('Almacén Asignado: ${info['almacen']}'),
                if (info['numero_confirmacion'] != null)
                  Text('N° Confirmación: ${info['numero_confirmacion']}'),
              ],
              const Divider(),
              Text('Fecha de Registro: ${_formatDate(trabajador['created_at'])}'),
            ],
          ),
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

  void _showEditTrabajadorDialog(Map<String, dynamic> trabajador) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Editar ${trabajador['nombres']} ${trabajador['apellidos']}'),
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

  void _showDeleteConfirmation(Map<String, dynamic> trabajador) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Eliminación'),
        content: Text('¿Estás seguro de que deseas eliminar a "${trabajador['nombres']} ${trabajador['apellidos']}"?'),
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
