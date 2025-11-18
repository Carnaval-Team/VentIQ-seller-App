import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_colors.dart';
import '../widgets/app_drawer.dart';
import '../utils/platform_utils.dart';

class RenovacionesScreen extends StatefulWidget {
  const RenovacionesScreen({super.key});

  @override
  State<RenovacionesScreen> createState() => _RenovacionesScreenState();
}

class _RenovacionesScreenState extends State<RenovacionesScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _renovaciones = [];
  List<Map<String, dynamic>> _filteredRenovaciones = [];
  
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedUrgencia = 'todas';
  int _diasFiltro = 30; // Por defecto muestra las que vencen en 30 días

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      // Cargar suscripciones próximas a vencer o vencidas
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
            created_at,
            app_dat_tienda!inner(
              id,
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
      
      // Filtrar solo las que necesitan renovación
      final renovaciones = <Map<String, dynamic>>[];
      final ahora = DateTime.now();
      
      for (var suscripcion in suscripcionesResponse) {
        final tienda = suscripcion['app_dat_tienda'];
        final plan = suscripcion['app_suscripciones_plan'];
        final fechaVencimiento = suscripcion['fecha_fin'] != null 
            ? DateTime.parse(suscripcion['fecha_fin'])
            : ahora.add(const Duration(days: 365));
        final diasRestantes = fechaVencimiento.difference(ahora).inDays;
        
        // Solo incluir las que vencen pronto o ya vencieron
        if (diasRestantes <= 60) {
          String urgencia = 'baja';
          Color urgenciaColor = AppColors.info;
          
          if (diasRestantes < 0) {
            urgencia = 'vencida';
            urgenciaColor = AppColors.error;
          } else if (diasRestantes <= 7) {
            urgencia = 'critica';
            urgenciaColor = AppColors.error;
          } else if (diasRestantes <= 15) {
            urgencia = 'alta';
            urgenciaColor = AppColors.warning;
          } else if (diasRestantes <= 30) {
            urgencia = 'media';
            urgenciaColor = AppColors.secondary;
          }
          
          // Obtener información adicional de la tienda
          final ventasResponse = await _supabase
              .from('app_dat_operacion_venta')
              .select('importe_total')
              .eq('id_tpv', tienda['id']) // Usar id_tpv en lugar de id_tienda
              .gte('created_at', DateTime.now().subtract(const Duration(days: 30)).toIso8601String());
          
          double ventasUltimos30Dias = 0;
          if (ventasResponse is List) {
            for (var venta in ventasResponse) {
              ventasUltimos30Dias += (venta['importe_total'] ?? 0).toDouble();
            }
          }
          
          renovaciones.add({
            ...suscripcion,
            'plan': plan?['denominacion'] ?? 'Sin plan',
            'precio': plan?['precio_mensual'] ?? 0,
            'fecha_vencimiento': suscripcion['fecha_fin'],
            'tienda_nombre': tienda?['denominacion'] ?? 'Sin tienda',
            'tienda_direccion': tienda?['direccion'] ?? 'Sin dirección',
            'tienda_ubicacion': tienda?['ubicacion'] ?? 'Sin ubicación',
            'dias_restantes': diasRestantes,
            'urgencia': urgencia,
            'urgencia_color': urgenciaColor,
            'ventas_ultimos_30_dias': ventasUltimos30Dias,
            'fecha_contacto': null, // Para registrar último contacto
            'notas': '', // Para notas del seguimiento
          });
        }
      }
      
      if (mounted) {
        setState(() {
          _renovaciones = renovaciones;
          _filteredRenovaciones = renovaciones;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error cargando renovaciones: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar renovaciones: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _filterRenovaciones() {
    setState(() {
      _filteredRenovaciones = _renovaciones.where((renovacion) {
        final matchesSearch = 
            renovacion['tienda_nombre'].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
            renovacion['plan'].toString().toLowerCase().contains(_searchQuery.toLowerCase());
        
        final matchesUrgencia = _selectedUrgencia == 'todas' ||
                              renovacion['urgencia'] == _selectedUrgencia;
        
        final matchesDias = renovacion['dias_restantes'] <= _diasFiltro;
        
        return matchesSearch && matchesUrgencia && matchesDias;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isDesktop = PlatformUtils.shouldUseDesktopLayout(screenSize.width);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Renovaciones'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Actualizar',
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () => _exportarRenovaciones(),
            tooltip: 'Exportar Lista',
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
                      labelText: 'Buscar tienda',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                      _filterRenovaciones();
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    value: _selectedUrgencia,
                    decoration: const InputDecoration(
                      labelText: 'Urgencia',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'todas', child: Text('Todas')),
                      DropdownMenuItem(value: 'vencida', child: Text('Vencidas')),
                      DropdownMenuItem(value: 'critica', child: Text('Crítica (≤7 días)')),
                      DropdownMenuItem(value: 'alta', child: Text('Alta (≤15 días)')),
                      DropdownMenuItem(value: 'media', child: Text('Media (≤30 días)')),
                      DropdownMenuItem(value: 'baja', child: Text('Baja (>30 días)')),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedUrgencia = value!;
                      });
                      _filterRenovaciones();
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<int>(
                    value: _diasFiltro,
                    decoration: const InputDecoration(
                      labelText: 'Días para vencer',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 7, child: Text('7 días')),
                      DropdownMenuItem(value: 15, child: Text('15 días')),
                      DropdownMenuItem(value: 30, child: Text('30 días')),
                      DropdownMenuItem(value: 60, child: Text('60 días')),
                      DropdownMenuItem(value: 365, child: Text('Todas')),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _diasFiltro = value!;
                      });
                      _filterRenovaciones();
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
    final vencidas = _renovaciones.where((r) => r['urgencia'] == 'vencida').length;
    final criticas = _renovaciones.where((r) => r['urgencia'] == 'critica').length;
    final altas = _renovaciones.where((r) => r['urgencia'] == 'alta').length;
    final medias = _renovaciones.where((r) => r['urgencia'] == 'media').length;
    
    final ingresosPotenciales = _renovaciones
        .fold<double>(0, (sum, r) => sum + (r['precio'] ?? 0).toDouble());
    
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Total',
            _renovaciones.length.toString(),
            Icons.schedule,
            AppColors.primary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'Vencidas',
            vencidas.toString(),
            Icons.cancel,
            AppColors.error,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'Críticas',
            criticas.toString(),
            Icons.warning,
            AppColors.error,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'Alta Prioridad',
            altas.toString(),
            Icons.priority_high,
            AppColors.warning,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatCard(
            'Ingresos Pot.',
            '\$${ingresosPotenciales.toStringAsFixed(0)}',
            Icons.attach_money,
            AppColors.success,
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Renovaciones Pendientes',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  '${_filteredRenovaciones.length} renovaciones',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Urgencia')),
                      DataColumn(label: Text('Tienda')),
                      DataColumn(label: Text('Plan Actual')),
                      DataColumn(label: Text('Vencimiento')),
                      DataColumn(label: Text('Días')),
                      DataColumn(label: Text('Ventas (30d)')),
                      DataColumn(label: Text('Precio')),
                      DataColumn(label: Text('Acciones')),
                    ],
                    rows: _filteredRenovaciones.map((renovacion) {
                      return DataRow(
                        cells: [
                          DataCell(_buildUrgenciaChip(renovacion['urgencia'])),
                          DataCell(
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  renovacion['tienda_nombre'],
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  renovacion['tienda_ubicacion'],
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          DataCell(_buildPlanChip(renovacion['plan'])),
                          DataCell(
                            Text(
                              _formatDate(renovacion['fecha_vencimiento']),
                              style: TextStyle(
                                color: renovacion['dias_restantes'] < 0 
                                    ? AppColors.error 
                                    : null,
                              ),
                            ),
                          ),
                          DataCell(_buildDiasChip(renovacion['dias_restantes'])),
                          DataCell(
                            Text(
                              '\$${renovacion['ventas_ultimos_30_dias'].toStringAsFixed(0)}',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          DataCell(
                            Text(
                              '\$${renovacion['precio'] ?? 0}',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.phone, color: AppColors.info),
                                  onPressed: () => _showContactarDialog(renovacion),
                                  tooltip: 'Contactar',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.refresh, color: AppColors.success),
                                  onPressed: () => _showRenovarDialog(renovacion),
                                  tooltip: 'Renovar',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.note_add),
                                  onPressed: () => _showNotasDialog(renovacion),
                                  tooltip: 'Agregar Nota',
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
      itemCount: _filteredRenovaciones.length,
      itemBuilder: (context, index) {
        final renovacion = _filteredRenovaciones[index];
        
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: (renovacion['urgencia_color'] as Color).withOpacity(0.1),
              child: Icon(
                _getUrgenciaIcon(renovacion['urgencia']),
                color: renovacion['urgencia_color'] as Color,
              ),
            ),
            title: Text(
              renovacion['tienda_nombre'],
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(renovacion['tienda_ubicacion']),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _buildUrgenciaChip(renovacion['urgencia']),
                    const SizedBox(width: 8),
                    _buildPlanChip(renovacion['plan']),
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
                    _buildInfoRow(Icons.event, 'Vencimiento', _formatDate(renovacion['fecha_vencimiento'])),
                    Row(
                      children: [
                        Icon(Icons.schedule, size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 8),
                        Text(
                          'Días: ',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        _buildDiasChip(renovacion['dias_restantes']),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _buildInfoRow(Icons.trending_up, 'Ventas (30d)', '\$${renovacion['ventas_ultimos_30_dias'].toStringAsFixed(0)}'),
                    _buildInfoRow(Icons.attach_money, 'Precio Plan', '\$${renovacion['precio'] ?? 0}'),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.phone, size: 18),
                          label: const Text('Contactar'),
                          onPressed: () => _showContactarDialog(renovacion),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.refresh, color: AppColors.success, size: 18),
                          label: const Text('Renovar', style: TextStyle(color: AppColors.success)),
                          onPressed: () => _showRenovarDialog(renovacion),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.note_add, size: 18),
                          label: const Text('Nota'),
                          onPressed: () => _showNotasDialog(renovacion),
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

  Widget _buildUrgenciaChip(String urgencia) {
    Color color;
    String text;
    
    switch (urgencia) {
      case 'vencida':
        color = AppColors.error;
        text = 'VENCIDA';
        break;
      case 'critica':
        color = AppColors.error;
        text = 'CRÍTICA';
        break;
      case 'alta':
        color = AppColors.warning;
        text = 'ALTA';
        break;
      case 'media':
        color = AppColors.secondary;
        text = 'MEDIA';
        break;
      case 'baja':
        color = AppColors.info;
        text = 'BAJA';
        break;
      default:
        color = AppColors.textSecondary;
        text = urgencia.toUpperCase();
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
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

  Widget _buildDiasChip(int dias) {
    Color color;
    if (dias < 0) {
      color = AppColors.error;
    } else if (dias <= 7) {
      color = AppColors.error;
    } else if (dias <= 15) {
      color = AppColors.warning;
    } else if (dias <= 30) {
      color = AppColors.secondary;
    } else {
      color = AppColors.info;
    }
    
    final text = dias < 0 ? '${-dias}d vencido' : '${dias}d';
    
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
          Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  IconData _getUrgenciaIcon(String urgencia) {
    switch (urgencia) {
      case 'vencida':
        return Icons.cancel;
      case 'critica':
        return Icons.warning;
      case 'alta':
        return Icons.priority_high;
      case 'media':
        return Icons.schedule;
      case 'baja':
        return Icons.info_outline;
      default:
        return Icons.schedule;
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

  void _showContactarDialog(Map<String, dynamic> renovacion) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Contactar ${renovacion['tienda_nombre']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Registrar contacto con el cliente para renovación.'),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Notas del contacto',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Contacto registrado')),
              );
            },
            child: const Text('Registrar'),
          ),
        ],
      ),
    );
  }

  void _showRenovarDialog(Map<String, dynamic> renovacion) {
    // Navegar a la pantalla de Licencias
    Navigator.of(context).pushNamed('/licencias');
  }

  void _showNotasDialog(Map<String, dynamic> renovacion) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Notas - ${renovacion['tienda_nombre']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Agregar nota',
                border: OutlineInputBorder(),
              ),
              maxLines: 4,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Nota guardada')),
              );
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _exportarRenovaciones() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Funcionalidad de exportación en desarrollo')),
    );
  }
}
