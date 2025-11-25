import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_colors.dart';
import '../widgets/app_drawer.dart';
import '../utils/platform_utils.dart';

class LicenciasScreen extends StatefulWidget {
  const LicenciasScreen({super.key});

  @override
  State<LicenciasScreen> createState() => _LicenciasScreenState();
}

class _LicenciasScreenState extends State<LicenciasScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _suscripciones = [];
  List<Map<String, dynamic>> _filteredSuscripciones = [];
  List<Map<String, dynamic>> _tiendas = [];
  
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedPlan = 'todos';
  String _selectedEstado = 'todos';

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
      
      // Cargar suscripciones con información de tienda
      final suscripcionesResponse = await _supabase
          .from('app_suscripciones')
          .select('''
            id,
            id_tienda,
            id_plan,
            fecha_inicio,
            fecha_fin,
            estado,
            metodo_pago,
            renovacion_automatica,
            created_at,
            app_dat_tienda!inner(
              denominacion,
              direccion,
              ubicacion
            ),
            app_suscripciones_plan!inner(
              denominacion,
              precio_mensual
            )
          ''')
          .order('fecha_fin', ascending: true);
      
      // Formatear datos de suscripciones
      final suscripciones = <Map<String, dynamic>>[];
      
      for (var suscripcion in suscripcionesResponse) {
        final tienda = suscripcion['app_dat_tienda'];
        final plan = suscripcion['app_suscripciones_plan'];
        final fechaVencimiento = suscripcion['fecha_fin'] != null 
            ? DateTime.parse(suscripcion['fecha_fin'])
            : DateTime.now().add(const Duration(days: 365));
        final diasRestantes = fechaVencimiento.difference(DateTime.now()).inDays;
        
        String estado = 'activa';
        if (suscripcion['estado'] != 1) {
          estado = 'inactiva';
        } else if (diasRestantes < 0) {
          estado = 'vencida';
        } else if (diasRestantes <= 30) {
          estado = 'por_vencer';
        }
        
        suscripciones.add({
          ...suscripcion,
          'plan': plan?['denominacion'] ?? 'Sin plan',
          'precio': plan?['precio_mensual'] ?? 0,
          'fecha_vencimiento': suscripcion['fecha_fin'],
          'activa': suscripcion['estado'] == 1,
          'tienda_nombre': tienda?['denominacion'] ?? 'Sin tienda',
          'tienda_direccion': tienda?['direccion'] ?? 'Sin dirección',
          'tienda_ubicacion': tienda?['ubicacion'] ?? 'Sin ubicación',
          'dias_restantes': diasRestantes,
          'estado': estado,
        });
      }
      
      if (mounted) {
        setState(() {
          _tiendas = List<Map<String, dynamic>>.from(tiendasResponse);
          _suscripciones = suscripciones;
          _isLoading = false;
        });
        // Aplicar filtros guardados después de cargar datos
        _filterSuscripciones();
      }
    } catch (e) {
      debugPrint('Error cargando suscripciones: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar suscripciones: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _filterSuscripciones() {
    setState(() {
      _filteredSuscripciones = _suscripciones.where((suscripcion) {
        final matchesSearch = 
            suscripcion['tienda_nombre'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
            suscripcion['plan'].toString().toLowerCase().contains(_searchQuery.toLowerCase());
        
        final matchesPlan = _selectedPlan == 'todos' ||
                          suscripcion['plan'].toString().toLowerCase() == _selectedPlan.toLowerCase();
        
        final matchesEstado = _selectedEstado == 'todos' ||
                            suscripcion['estado'] == _selectedEstado;
        
        return matchesSearch && matchesPlan && matchesEstado;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isDesktop = PlatformUtils.shouldUseDesktopLayout(screenSize.width);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Licencias'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Actualizar',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showCreateLicenciaDialog(),
            tooltip: 'Nueva Licencia',
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
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.all(PlatformUtils.getScreenPadding()),
        child: Column(
          children: [
            _buildFilters(),
            const SizedBox(height: 16),
            _buildStats(),
            const SizedBox(height: 16),
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.5,
              child: isDesktop 
                  ? _buildDesktopTable()
                  : _buildMobileList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    final screenSize = MediaQuery.of(context).size;
    final isDesktop = PlatformUtils.shouldUseDesktopLayout(screenSize.width);
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: isDesktop
            ? Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Buscar licencia',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                        });
                        _filterSuscripciones();
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 1,
                    child: DropdownButtonFormField<String>(
                      value: _selectedPlan,
                      decoration: const InputDecoration(
                        labelText: 'Plan',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'todos', child: Text('Todos')),
                        DropdownMenuItem(value: 'gratuita', child: Text('Gratuita')),
                        DropdownMenuItem(value: 'basica', child: Text('Básica')),
                        DropdownMenuItem(value: 'premium', child: Text('Premium')),
                        DropdownMenuItem(value: 'enterprise', child: Text('Enterprise')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedPlan = value!;
                        });
                        _filterSuscripciones();
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 1,
                    child: DropdownButtonFormField<String>(
                      value: _selectedEstado,
                      decoration: const InputDecoration(
                        labelText: 'Estado',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'todos', child: Text('Todos')),
                        DropdownMenuItem(value: 'activa', child: Text('Activas')),
                        DropdownMenuItem(value: 'por_vencer', child: Text('Por Vencer')),
                        DropdownMenuItem(value: 'vencida', child: Text('Vencidas')),
                        DropdownMenuItem(value: 'inactiva', child: Text('Inactivas')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedEstado = value!;
                        });
                        _filterSuscripciones();
                      },
                    ),
                  ),
                ],
              )
            : Column(
                spacing: 12,
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Buscar licencia',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                      _filterSuscripciones();
                    },
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedPlan,
                          decoration: const InputDecoration(
                            labelText: 'Plan',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(value: 'todos', child: Text('Todos')),
                            DropdownMenuItem(value: 'gratuita', child: Text('Gratuita')),
                            DropdownMenuItem(value: 'basica', child: Text('Básica')),
                            DropdownMenuItem(value: 'premium', child: Text('Premium')),
                            DropdownMenuItem(value: 'enterprise', child: Text('Enterprise')),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedPlan = value!;
                            });
                            _filterSuscripciones();
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedEstado,
                          decoration: const InputDecoration(
                            labelText: 'Estado',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(value: 'todos', child: Text('Todos')),
                            DropdownMenuItem(value: 'activa', child: Text('Activas')),
                            DropdownMenuItem(value: 'por_vencer', child: Text('Por Vencer')),
                            DropdownMenuItem(value: 'vencida', child: Text('Vencidas')),
                            DropdownMenuItem(value: 'inactiva', child: Text('Inactivas')),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedEstado = value!;
                            });
                            _filterSuscripciones();
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
    final screenSize = MediaQuery.of(context).size;
    final isDesktop = PlatformUtils.shouldUseDesktopLayout(screenSize.width);
    
    final activas = _suscripciones.where((s) => s['estado'] == 'activa').length;
    final porVencer = _suscripciones.where((s) => s['estado'] == 'por_vencer').length;
    final vencidas = _suscripciones.where((s) => s['estado'] == 'vencida').length;
    
    final ingresosMensuales = _suscripciones
        .where((s) => s['activa'] == true)
        .fold<double>(0, (sum, s) => sum + (s['precio'] ?? 0).toDouble());
    
    final stats = [
      ('Total Licencias', _suscripciones.length.toString(), Icons.card_membership, AppColors.primary),
      ('Activas', activas.toString(), Icons.check_circle, AppColors.success),
      ('Por Vencer', porVencer.toString(), Icons.schedule, AppColors.warning),
      ('Vencidas', vencidas.toString(), Icons.cancel, AppColors.error),
      ('Ingresos/Mes', '\$${ingresosMensuales.toStringAsFixed(0)}', Icons.attach_money, AppColors.info),
    ];
    
    if (isDesktop) {
      return Row(
        children: [
          for (int i = 0; i < stats.length; i++) ...[
            Expanded(
              child: _buildStatCard(
                stats[i].$1,
                stats[i].$2,
                stats[i].$3,
                stats[i].$4,
              ),
            ),
            if (i < stats.length - 1) const SizedBox(width: 12),
          ],
        ],
      );
    } else {
      return Column(
        spacing: 12,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  stats[0].$1,
                  stats[0].$2,
                  stats[0].$3,
                  stats[0].$4,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  stats[1].$1,
                  stats[1].$2,
                  stats[1].$3,
                  stats[1].$4,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  stats[2].$1,
                  stats[2].$2,
                  stats[2].$3,
                  stats[2].$4,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  stats[3].$1,
                  stats[3].$2,
                  stats[3].$3,
                  stats[3].$4,
                ),
              ),
            ],
          ),
          _buildStatCard(
            stats[4].$1,
            stats[4].$2,
            stats[4].$3,
            stats[4].$4,
          ),
        ],
      );
    }
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
              'Lista de Licencias',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Tienda')),
                      DataColumn(label: Text('Plan')),
                      DataColumn(label: Text('Estado')),
                      DataColumn(label: Text('Fecha Inicio')),
                      DataColumn(label: Text('Fecha Vencimiento')),
                      DataColumn(label: Text('Días Restantes')),
                      DataColumn(label: Text('Precio')),
                      DataColumn(label: Text('Acciones')),
                    ],
                    rows: _filteredSuscripciones.map((suscripcion) {
                      return DataRow(
                        cells: [
                          DataCell(
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  suscripcion['tienda_nombre'],
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  suscripcion['tienda_ubicacion'],
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          DataCell(_buildPlanChip(suscripcion['plan'])),
                          DataCell(_buildEstadoChip(suscripcion['estado'])),
                          DataCell(Text(_formatDate(suscripcion['fecha_inicio']))),
                          DataCell(Text(_formatDate(suscripcion['fecha_vencimiento']))),
                          DataCell(_buildDiasRestantesChip(suscripcion['dias_restantes'])),
                          DataCell(
                            Text(
                              '\$${suscripcion['precio'] ?? 0}',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.visibility),
                                  onPressed: () => _showLicenciaDetails(suscripcion),
                                  tooltip: 'Ver Detalles',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () => _showEditLicenciaDialog(suscripcion),
                                  tooltip: 'Editar',
                                ),
                                if (suscripcion['estado'] == 'por_vencer' || 
                                    suscripcion['estado'] == 'vencida')
                                  IconButton(
                                    icon: const Icon(Icons.refresh, color: AppColors.success),
                                    onPressed: () => _showRenovarDialog(suscripcion),
                                    tooltip: 'Renovar',
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
      itemCount: _filteredSuscripciones.length,
      itemBuilder: (context, index) {
        final suscripcion = _filteredSuscripciones[index];
        
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: _getEstadoColor(suscripcion['estado']).withOpacity(0.1),
              child: Icon(
                Icons.card_membership,
                color: _getEstadoColor(suscripcion['estado']),
              ),
            ),
            title: Text(
              suscripcion['tienda_nombre'],
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(suscripcion['tienda_ubicacion']),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _buildPlanChip(suscripcion['plan']),
                    const SizedBox(width: 8),
                    _buildEstadoChip(suscripcion['estado']),
                  ],
                ),
              ],
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow(Icons.calendar_today, 'Inicio', _formatDate(suscripcion['fecha_inicio'])),
                    _buildInfoRow(Icons.event, 'Vencimiento', _formatDate(suscripcion['fecha_vencimiento'])),
                    Row(
                      children: [
                        Icon(Icons.schedule, size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 8),
                        Text(
                          'Días restantes: ',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        _buildDiasRestantesChip(suscripcion['dias_restantes']),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _buildInfoRow(Icons.attach_money, 'Precio', '\$${suscripcion['precio'] ?? 0}'),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.visibility),
                          label: const Text('Ver'),
                          onPressed: () => _showLicenciaDetails(suscripcion),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.refresh, color: AppColors.success),
                          label: const Text('Renovar', style: TextStyle(color: AppColors.success)),
                          onPressed: () => _showRenovarDialog(suscripcion),
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

  Widget _buildPlanChip(String plan) {
    Color color;
    switch (plan.toLowerCase()) {
      case 'gratuita':
        color = AppColors.textSecondary;
        break;
      case 'basica':
        color = AppColors.info;
        break;
      case 'premium':
        color = AppColors.secondary;
        break;
      case 'enterprise':
        color = AppColors.primary;
        break;
      default:
        color = AppColors.textSecondary;
    }
    
    return Chip(
      label: Text(
        plan.toUpperCase(),
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

  Widget _buildEstadoChip(String estado) {
    final color = _getEstadoColor(estado);
    String text;
    
    switch (estado) {
      case 'activa':
        text = 'ACTIVA';
        break;
      case 'por_vencer':
        text = 'POR VENCER';
        break;
      case 'vencida':
        text = 'VENCIDA';
        break;
      case 'inactiva':
        text = 'INACTIVA';
        break;
      default:
        text = estado.toUpperCase();
    }
    
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

  Widget _buildDiasRestantesChip(int dias) {
    Color color;
    if (dias < 0) {
      color = AppColors.error;
    } else if (dias <= 7) {
      color = AppColors.error;
    } else if (dias <= 30) {
      color = AppColors.warning;
    } else {
      color = AppColors.success;
    }
    
    final text = dias < 0 ? 'Vencido hace ${-dias} días' : '$dias días';
    
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
          fontSize: 11,
          fontWeight: FontWeight.w600,
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
          Text(
            value,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Color _getEstadoColor(String estado) {
    switch (estado) {
      case 'activa':
        return AppColors.success;
      case 'por_vencer':
        return AppColors.warning;
      case 'vencida':
        return AppColors.error;
      case 'inactiva':
        return AppColors.textSecondary;
      default:
        return AppColors.textSecondary;
    }
  }

  String _formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) {
      return 'N/A';
    }
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  void _showCreateLicenciaDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nueva Licencia'),
        content: const Text('Funcionalidad de creación de licencia en desarrollo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _showLicenciaDetails(Map<String, dynamic> suscripcion) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(suscripcion['tienda_nombre']),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ID: ${suscripcion['id']}'),
            Text('Plan: ${suscripcion['plan']}'),
            Text('Estado: ${suscripcion['estado']}'),
            Text('Fecha Inicio: ${_formatDate(suscripcion['fecha_inicio'])}'),
            Text('Fecha Vencimiento: ${_formatDate(suscripcion['fecha_vencimiento'])}'),
            Text('Días Restantes: ${suscripcion['dias_restantes']}'),
            Text('Precio: \$${suscripcion['precio'] ?? 0}'),
            Text('Activa: ${suscripcion['activa'] ? 'Sí' : 'No'}'),
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

  void _showEditLicenciaDialog(Map<String, dynamic> suscripcion) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Editar Licencia - ${suscripcion['tienda_nombre']}'),
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

  void _showRenovarDialog(Map<String, dynamic> suscripcion) {
    showDialog(
      context: context,
      builder: (context) => _RenovarDialogContent(
        suscripcion: suscripcion,
        supabase: _supabase,
        onRenovacionCompleta: _loadData,
      ),
    );
  }
}

/// Widget para el diálogo de renovación con carga de planes y aplicación a gerente
class _RenovarDialogContent extends StatefulWidget {
  final Map<String, dynamic> suscripcion;
  final SupabaseClient supabase;
  final VoidCallback onRenovacionCompleta;

  const _RenovarDialogContent({
    required this.suscripcion,
    required this.supabase,
    required this.onRenovacionCompleta,
  });

  @override
  State<_RenovarDialogContent> createState() => _RenovarDialogContentState();
}

class _RenovarDialogContentState extends State<_RenovarDialogContent> {
  List<Map<String, dynamic>> _planesDisponibles = [];
  Map<String, dynamic>? _planSeleccionado;
  bool _isLoading = true;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _cargarPlanesYGerente();
  }

  Future<void> _cargarPlanesYGerente() async {
    try {
      // Cargar planes activos
      final planesResponse = await widget.supabase
          .from('app_suscripciones_plan')
          .select('*')
          .eq('es_activo', true)
          .order('id', ascending: true);

      if (mounted) {
        setState(() {
          _planesDisponibles = List<Map<String, dynamic>>.from(planesResponse);
          // Seleccionar el plan actual por defecto
          if (_planesDisponibles.isNotEmpty) {
            _planSeleccionado = _planesDisponibles.firstWhere(
              (p) => p['id'] == widget.suscripcion['id_plan'],
              orElse: () => _planesDisponibles.first,
            );
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error cargando planes: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar planes: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _confirmarRenovacion() async {
    if (_planSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona un plan'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final idTienda = widget.suscripcion['id_tienda'];
      final idSuscripcionActual = widget.suscripcion['id'];
      final esPlanPro = _planSeleccionado!['denominacion']
              ?.toString()
              .toLowerCase()
              .contains('pro') ??
          false;

      // Nueva fecha de fin: hoy + 30 días
      final ahora = DateTime.now();
      final nuevaFechaFin = ahora.add(const Duration(days: 30));

      // Actualizar la suscripción actual
      await widget.supabase
          .from('app_suscripciones')
          .update({
            'id_plan': _planSeleccionado!['id'],
            'fecha_fin': nuevaFechaFin.toIso8601String(),
            'estado': 1, // Activa
            'updated_at': ahora.toIso8601String(),
          })
          .eq('id', idSuscripcionActual);

      // Si es plan pro, buscar todas las tiendas del gerente y aplicar el mismo plan
      if (esPlanPro) {
        // Buscar gerentes de la tienda actual
        final gerentesResponse = await widget.supabase
            .from('app_dat_gerente')
            .select('uuid')
            .eq('id_tienda', idTienda);

        if (gerentesResponse.isNotEmpty) {
          // Obtener UUIDs únicos de gerentes
          final uuidsGerentes = <String>{};
          for (final gerente in gerentesResponse) {
            uuidsGerentes.add(gerente['uuid']);
          }

          // Para cada gerente, buscar todas sus tiendas
          for (final uuidGerente in uuidsGerentes) {
            final tiendasDelGerente = await widget.supabase
                .from('app_dat_gerente')
                .select('id_tienda')
                .eq('uuid', uuidGerente);

            // Aplicar el mismo plan a todas las tiendas del gerente
            for (final tiendaGerente in tiendasDelGerente) {
              final idTiendaGerente = tiendaGerente['id_tienda'];

              if (idTiendaGerente != idTienda) {
                // Buscar suscripción existente de esta tienda
                final suscripcionesExistentes = await widget.supabase
                    .from('app_suscripciones')
                    .select('id')
                    .eq('id_tienda', idTiendaGerente);

                if (suscripcionesExistentes.isNotEmpty) {
                  // Actualizar la primera suscripción existente
                  final suscripcionExistente = suscripcionesExistentes.first;
                  await widget.supabase
                      .from('app_suscripciones')
                      .update({
                        'id_plan': _planSeleccionado!['id'],
                        'fecha_fin': nuevaFechaFin.toIso8601String(),
                        'estado': 1,
                        'updated_at': ahora.toIso8601String(),
                      })
                      .eq('id', suscripcionExistente['id']);
                }
              }
            }
          }
        }
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              esPlanPro
                  ? 'Renovación aplicada a todas las tiendas del gerente'
                  : 'Renovación completada',
            ),
            backgroundColor: AppColors.success,
          ),
        );
        widget.onRenovacionCompleta();
      }
    } catch (e) {
      debugPrint('Error al renovar: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al renovar: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return AlertDialog(
        title: const Text('Renovar Licencia'),
        content: const SizedBox(
          height: 100,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return AlertDialog(
      title: const Text('Renovar Licencia'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tienda: ${widget.suscripcion['tienda_nombre']}'),
            const SizedBox(height: 16),
            const Text('Selecciona el plan:'),
            const SizedBox(height: 8),
            DropdownButtonFormField<Map<String, dynamic>>(
              value: _planSeleccionado,
              decoration: const InputDecoration(
                labelText: 'Plan',
                border: OutlineInputBorder(),
              ),
              items: _planesDisponibles.map((plan) {
                return DropdownMenuItem(
                  value: plan,
                  child: Text(
                    '${plan['denominacion']} - \$${plan['precio_mensual']}/mes',
                  ),
                );
              }).toList(),
              onChanged: (plan) {
                setState(() => _planSeleccionado = plan);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _isProcessing ? null : _confirmarRenovacion,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
          child: _isProcessing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Confirmar Renovación'),
        ),
      ],
    );
  }
}
