import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../config/app_colors.dart';
import '../widgets/app_drawer.dart';
import '../utils/platform_utils.dart';
import '../services/agente_service.dart';

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
  String _selectedUrgencia = 'todas';
  int _diasFiltro = 365; // Mostrar todas por defecto
  bool _soloLicenciasPagas = false;

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
            id_agente,
            fecha_inicio,
            fecha_fin,
            estado,
            metodo_pago,
            renovacion_automatica,
            observaciones,
            created_at,
            app_dat_tienda!inner(
              denominacion,
              direccion,
              ubicacion
            ),
            app_suscripciones_plan!inner(
              denominacion,
              precio_mensual
            ),
            app_dat_agente(
              id,
              nombre,
              apellidos
            )
          ''')
          .order('fecha_fin', ascending: true);

      // Formatear datos de suscripciones
      final suscripciones = <Map<String, dynamic>>[];

      for (var suscripcion in suscripcionesResponse) {
        final tienda = suscripcion['app_dat_tienda'];
        final plan = suscripcion['app_suscripciones_plan'];
        final fechaVencimiento =
            suscripcion['fecha_fin'] != null
                ? DateTime.parse(suscripcion['fecha_fin'])
                : DateTime.now().add(const Duration(days: 365));
        final diasRestantes =
            fechaVencimiento.difference(DateTime.now()).inDays;

        String estado = 'activa';
        if (suscripcion['estado'] != 1) {
          estado = 'inactiva';
        } else if (diasRestantes < 0) {
          estado = 'vencida';
        } else if (diasRestantes <= 30) {
          estado = 'por_vencer';
        }

        String urgencia = 'baja';
        if (diasRestantes < 0) {
          urgencia = 'vencida';
        } else if (diasRestantes <= 5) {
          urgencia = 'critica';
        } else if (diasRestantes <= 15) {
          urgencia = 'alta';
        } else if (diasRestantes <= 30) {
          urgencia = 'media';
        }

        final agente = suscripcion['app_dat_agente'];
        final agenteNombre = agente != null
            ? '${agente['nombre']} ${agente['apellidos']}'
            : null;

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
          'estado_computed': estado,
          'estado': estado,
          'estado_id': suscripcion['estado'],
          'urgencia': urgencia,
          'agente_nombre': agenteNombre,
          'id_agente': suscripcion['id_agente'],
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
      _filteredSuscripciones =
          _suscripciones.where((suscripcion) {
            final matchesSearch =
                suscripcion['tienda_nombre'].toString().toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                ) ||
                suscripcion['plan'].toString().toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                );

            final matchesPlan =
                _selectedPlan == 'todos' ||
                suscripcion['plan'].toString().toLowerCase() ==
                    _selectedPlan.toLowerCase();

            final matchesEstado =
                _selectedEstado == 'todos' ||
                suscripcion['estado'] == _selectedEstado;

            final matchesUrgencia =
                _selectedUrgencia == 'todas' ||
                suscripcion['urgencia'] == _selectedUrgencia;

            final matchesDias = suscripcion['dias_restantes'] <= _diasFiltro;

            // No mostrar licencias vencidas hace más de 60 días
            final diasRestantes = suscripcion['dias_restantes'] as int;
            final noExpiradaMasDe60Dias = diasRestantes >= -60;

            // Filtro de licencias pagas (excluir gratis)
            final matchesPagas = !_soloLicenciasPagas ||
                ((suscripcion['precio'] as num?) ?? 0) > 0;

            return matchesSearch &&
                matchesPlan &&
                matchesEstado &&
                matchesUrgencia &&
                matchesDias &&
                noExpiradaMasDe60Dias &&
                matchesPagas;
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
      body:
          _isLoading
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
              child: isDesktop ? _buildDesktopTable() : _buildMobileList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Buscar tienda o plan',
                  prefixIcon: Icon(Icons.search),
                  border: InputBorder.none,
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                  _filterSuscripciones();
                },
              ),
            ),
            const VerticalDivider(width: 1),
            IconButton(
              icon: Icon(
                Icons.filter_list,
                color:
                    (_selectedPlan != 'todos' ||
                            _selectedEstado != 'todos' ||
                            _selectedUrgencia != 'todas' ||
                            _diasFiltro != 365 ||
                            _soloLicenciasPagas)
                        ? AppColors.primary
                        : null,
              ),
              onPressed: _showFilterDialog,
              tooltip: 'Filtros Avanzados',
            ),
          ],
        ),
      ),
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Row(
                  children: [
                    Icon(Icons.filter_alt, color: AppColors.primary),
                    SizedBox(width: 8),
                    Text('Filtros de Licencias'),
                  ],
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 16,
                    children: [
                      DropdownButtonFormField<String>(
                        value: _selectedPlan,
                        decoration: const InputDecoration(
                          labelText: 'Plan de Suscripción',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'todos',
                            child: Text('Todos'),
                          ),
                          DropdownMenuItem(
                            value: 'gratuita',
                            child: Text('Gratuita'),
                          ),
                          DropdownMenuItem(
                            value: 'basica',
                            child: Text('Básica'),
                          ),
                          DropdownMenuItem(
                            value: 'premium',
                            child: Text('Premium'),
                          ),
                          DropdownMenuItem(
                            value: 'enterprise',
                            child: Text('Enterprise'),
                          ),
                        ],
                        onChanged: (value) {
                          setDialogState(() => _selectedPlan = value!);
                        },
                      ),
                      DropdownButtonFormField<String>(
                        value: _selectedEstado,
                        decoration: const InputDecoration(
                          labelText: 'Estado de Licencia',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'todos',
                            child: Text('Todos'),
                          ),
                          DropdownMenuItem(
                            value: 'activa',
                            child: Text('Activas'),
                          ),
                          DropdownMenuItem(
                            value: 'por_vencer',
                            child: Text('Por Vencer'),
                          ),
                          DropdownMenuItem(
                            value: 'vencida',
                            child: Text('Vencidas'),
                          ),
                          DropdownMenuItem(
                            value: 'inactiva',
                            child: Text('Inactivas'),
                          ),
                        ],
                        onChanged: (value) {
                          setDialogState(() => _selectedEstado = value!);
                        },
                      ),
                      DropdownButtonFormField<String>(
                        value: _selectedUrgencia,
                        decoration: const InputDecoration(
                          labelText: 'Urgencia (Renovación)',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'todas',
                            child: Text('Todas'),
                          ),
                          DropdownMenuItem(
                            value: 'vencida',
                            child: Text('Vencidas'),
                          ),
                          DropdownMenuItem(
                            value: 'critica',
                            child: Text('Crítica (≤7 días)'),
                          ),
                          DropdownMenuItem(
                            value: 'alta',
                            child: Text('Alta (≤15 días)'),
                          ),
                          DropdownMenuItem(
                            value: 'media',
                            child: Text('Media (≤30 días)'),
                          ),
                          DropdownMenuItem(
                            value: 'baja',
                            child: Text('Baja (>30 días)'),
                          ),
                        ],
                        onChanged: (value) {
                          setDialogState(() => _selectedUrgencia = value!);
                        },
                      ),
                      DropdownButtonFormField<int>(
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
                          setDialogState(() => _diasFiltro = value!);
                        },
                      ),
                      CheckboxListTile(
                        title: const Text('Solo Licencias Pagas'),
                        subtitle: const Text('Excluir licencias gratuitas'),
                        value: _soloLicenciasPagas,
                        onChanged: (value) {
                          setDialogState(
                            () => _soloLicenciasPagas = value ?? false,
                          );
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedPlan = 'todos';
                        _selectedEstado = 'todos';
                        _selectedUrgencia = 'todas';
                        _diasFiltro = 365;
                        _soloLicenciasPagas = false;
                      });
                      _filterSuscripciones();
                      Navigator.pop(context);
                    },
                    child: const Text('Limpiar'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      _filterSuscripciones();
                      Navigator.pop(context);
                    },
                    child: const Text('Aplicar Filtros'),
                  ),
                ],
              );
            },
          ),
    );
  }

  Widget _buildStats() {
    final screenSize = MediaQuery.of(context).size;
    final isDesktop = PlatformUtils.shouldUseDesktopLayout(screenSize.width);

    final activas = _suscripciones.where((s) => s['estado'] == 'activa').length;
    final porVencer =
        _suscripciones.where((s) => s['estado'] == 'por_vencer').length;
    final vencidas =
        _suscripciones.where((s) => s['estado'] == 'vencida').length;

    // Total de licencias no gratuitas (precio > 0)
    final totalNoGratis = _suscripciones
        .where((s) => ((s['precio'] ?? 0) as num).toDouble() > 0)
        .length;

    // Ingresos del mes: licencias activas no gratuitas que se vencen después del mes en curso
    final now = DateTime.now();
    final finMes = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    final ingresosMensuales = _suscripciones
        .where((s) {
          final precio = ((s['precio'] ?? 0) as num).toDouble();
          if (precio <= 0) return false;
          if (s['activa'] != true) return false;
          final fechaFin = s['fecha_vencimiento'] != null
              ? DateTime.parse(s['fecha_vencimiento'])
              : DateTime.now().add(const Duration(days: 365));
          return fechaFin.isAfter(finMes);
        })
        .fold<double>(0, (sum, s) => sum + ((s['precio'] ?? 0) as num).toDouble());

    final stats = [
      (
        'Licencias Pagas',
        totalNoGratis.toString(),
        Icons.card_membership,
        AppColors.primary,
      ),
      ('Activas', activas.toString(), Icons.check_circle, AppColors.success),
      ('Por Vencer', porVencer.toString(), Icons.schedule, AppColors.warning),
      ('Vencidas', vencidas.toString(), Icons.cancel, AppColors.error),
      (
        'Ingresos/Mes',
        '\$${ingresosMensuales.toStringAsFixed(0)}',
        Icons.attach_money,
        AppColors.info,
      ),
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
      // Diseño móvil: Rejilla más compacta o Wrap
      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  stats[0].$1,
                  stats[0].$2,
                  stats[0].$3,
                  stats[0].$4,
                  isMobile: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatCard(
                  stats[1].$1,
                  stats[1].$2,
                  stats[1].$3,
                  stats[1].$4,
                  isMobile: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  stats[2].$1,
                  stats[2].$2,
                  stats[2].$3,
                  stats[2].$4,
                  isMobile: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatCard(
                  stats[3].$1,
                  stats[3].$2,
                  stats[3].$3,
                  stats[3].$4,
                  isMobile: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildStatCard(
            stats[4].$1,
            stats[4].$2,
            stats[4].$3,
            stats[4].$4,
            isMobile: true,
          ),
        ],
      );
    }
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color, {
    bool isMobile = false,
  }) {
    final isIngresos = title == 'Ingresos/Mes';
    final cardWidget = _buildCardContent(title, value, icon, color, isMobile);

    if (isIngresos) {
      return GestureDetector(
        onTap: () => Navigator.of(context).pushNamed('/ingresos-distribucion'),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: cardWidget,
        ),
      );
    }

    return cardWidget;
  }

  Widget _buildCardContent(
    String title,
    String value,
    IconData icon,
    Color color,
    bool isMobile,
  ) {
    if (isMobile) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    Text(
                      title,
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

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
                      DataColumn(label: Text('Urgencia')),
                      DataColumn(label: Text('Tienda')),
                      DataColumn(label: Text('Plan')),
                      DataColumn(label: Text('Estado')),
                      DataColumn(label: Text('Agente')),
                      DataColumn(label: Text('Fecha Inicio')),
                      DataColumn(label: Text('Fecha Vencimiento')),
                      DataColumn(label: Text('Días Restantes')),
                      DataColumn(label: Text('Precio')),
                      DataColumn(label: Text('Acciones')),
                    ],
                    rows:
                        _filteredSuscripciones.map((suscripcion) {
                          return DataRow(
                            cells: [
                              DataCell(
                                _buildUrgenciaChip(suscripcion['urgencia']),
                              ),
                              DataCell(
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      suscripcion['tienda_nombre'],
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
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
                              DataCell(
                                InkWell(
                                  onTap: () => _showAsignarAgenteDialog(suscripcion),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.support_agent,
                                        size: 16,
                                        color: suscripcion['agente_nombre'] != null
                                            ? AppColors.primary
                                            : Colors.grey,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        suscripcion['agente_nombre'] ?? 'Sin asignar',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: suscripcion['agente_nombre'] != null
                                              ? AppColors.textPrimary
                                              : Colors.grey,
                                          fontStyle: suscripcion['agente_nombre'] == null
                                              ? FontStyle.italic
                                              : FontStyle.normal,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(_formatDate(suscripcion['fecha_inicio'])),
                              ),
                              DataCell(
                                Text(
                                  _formatDate(suscripcion['fecha_vencimiento']),
                                ),
                              ),
                              DataCell(
                                _buildDiasRestantesChip(
                                  suscripcion['dias_restantes'],
                                ),
                              ),
                              DataCell(
                                Text(
                                  '\$${suscripcion['precio'] ?? 0}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.visibility),
                                      onPressed:
                                          () =>
                                              _showLicenciaDetails(suscripcion),
                                      tooltip: 'Ver Detalles',
                                    ),
                                    if (suscripcion['estado'] == 'por_vencer' ||
                                        suscripcion['estado'] == 'vencida')
                                      IconButton(
                                        icon: const Icon(
                                          Icons.history,
                                          color: AppColors.primary,
                                        ),
                                        onPressed:
                                            () => _showHistorialDialog(
                                              suscripcion,
                                            ),
                                        tooltip: 'Historial',
                                      ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.refresh,
                                        color: AppColors.success,
                                      ),
                                      onPressed:
                                          () => _showRenovarDialog(suscripcion),
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
              backgroundColor: _getEstadoColor(
                suscripcion['estado'],
              ).withOpacity(0.1),
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
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _buildUrgenciaChip(suscripcion['urgencia']),
                    _buildPlanChip(suscripcion['plan']),
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
                    _buildInfoRow(
                      Icons.calendar_today,
                      'Inicio',
                      _formatDate(suscripcion['fecha_inicio']),
                    ),
                    _buildInfoRow(
                      Icons.event,
                      'Vencimiento',
                      _formatDate(suscripcion['fecha_vencimiento']),
                    ),
                    Row(
                      children: [
                        Icon(
                          Icons.schedule,
                          size: 16,
                          color: AppColors.textSecondary,
                        ),
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
                    _buildInfoRow(
                      Icons.attach_money,
                      'Precio',
                      '\$${suscripcion['precio'] ?? 0}',
                    ),
                    InkWell(
                      onTap: () => _showAsignarAgenteDialog(suscripcion),
                      child: _buildInfoRow(
                        Icons.support_agent,
                        'Agente',
                        suscripcion['agente_nombre'] ?? 'Sin asignar',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.edit, size: 18),
                          label: const Text('Editar'),
                          onPressed: () => _showEditLicenciaDialog(suscripcion),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.history, size: 18),
                          label: const Text('Historial'),
                          onPressed: () => _showHistorialDialog(suscripcion),
                        ),
                        TextButton.icon(
                          icon: const Icon(
                            Icons.refresh,
                            color: AppColors.success,
                          ),
                          label: const Text(
                            'Renovar',
                            style: TextStyle(color: AppColors.success),
                          ),
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
        color = AppColors.success;
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
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          Text(value, style: const TextStyle(fontSize: 12)),
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
      builder: (context) => _CreateLicenciaDialogContent(
        supabase: _supabase,
        tiendas: _tiendas,
        onCreateComplete: _loadData,
      ),
    );
  }

  void _showEditLicenciaDialog(Map<String, dynamic> suscripcion) {
    showDialog(
      context: context,
      builder: (context) => _EditLicenciaDialogContent(
        suscripcion: suscripcion,
        supabase: _supabase,
        onEditComplete: _loadData,
      ),
    );
  }

  void _showAsignarAgenteDialog(Map<String, dynamic> suscripcion) {
    showDialog(
      context: context,
      builder: (context) => _AsignarAgenteDialogContent(
        suscripcion: suscripcion,
        onAsignacionCompleta: _loadData,
      ),
    );
  }

  void _showLicenciaDetails(Map<String, dynamic> suscripcion) {
    showDialog(
      context: context,
      builder: (context) => _LicenciaDetailsDialog(
        suscripcion: suscripcion,
        supabase: _supabase,
      ),
    );
  }

  void _showRenovarDialog(Map<String, dynamic> suscripcion) {
    showDialog(
      context: context,
      builder:
          (context) => _RenovarDialogContent(
            suscripcion: suscripcion,
            supabase: _supabase,
            onRenovacionCompleta: _loadData,
          ),
    );
  }

  void _showHistorialDialog(Map<String, dynamic> suscripcion) {
    showDialog(
      context: context,
      builder:
          (context) => _HistorialDialogContent(
            suscripcion: suscripcion,
            supabase: _supabase,
          ),
    );
  }
}

class _HistorialDialogContent extends StatefulWidget {
  final Map<String, dynamic> suscripcion;
  final SupabaseClient supabase;

  const _HistorialDialogContent({
    required this.suscripcion,
    required this.supabase,
  });

  @override
  State<_HistorialDialogContent> createState() =>
      _HistorialDialogContentState();
}

class _HistorialDialogContentState extends State<_HistorialDialogContent> {
  List<Map<String, dynamic>> _historial = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _cargarHistorial();
  }

  Future<void> _cargarHistorial() async {
    try {
      final response = await widget.supabase
          .from('app_suscripciones_historial')
          .select('''
            *,
            plan_anterior:app_suscripciones_plan!app_suscripciones_historial_id_plan_anterior_fkey(denominacion),
            plan_nuevo:app_suscripciones_plan!app_suscripciones_historial_id_plan_nuevo_fkey(denominacion)
          ''')
          .eq('id_suscripcion', widget.suscripcion['id'])
          .order('fecha_cambio', ascending: false);

      if (mounted) {
        setState(() {
          _historial = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error cargando historial: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatDateTime(String dateStr) {
    final date = DateTime.parse(dateStr);
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Historial - ${widget.suscripcion['tienda_nombre']}'),
      content: SizedBox(
        width: 600,
        height: 400,
        child:
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _historial.isEmpty
                ? const Center(child: Text('No hay registros de historial'))
                : ListView.separated(
                  itemCount: _historial.length,
                  separatorBuilder: (context, index) => const Divider(),
                  itemBuilder: (context, index) {
                    final item = _historial[index];
                    final planAnterior =
                        item['plan_anterior']?['denominacion'] ?? 'N/A';
                    final planNuevo =
                        item['plan_nuevo']?['denominacion'] ?? 'N/A';

                    return ListTile(
                      isThreeLine: true,
                      title: Text(_formatDateTime(item['fecha_cambio'])),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Plan: $planAnterior ➔ $planNuevo'),
                          if (item['evidencia'] != null &&
                              item['evidencia'].toString().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child:
                                  item['evidencia'].toString().startsWith(
                                        'http',
                                      )
                                      ? InkWell(
                                        onTap: () {
                                          showDialog(
                                            context: context,
                                            builder:
                                                (context) => Dialog(
                                                  child: Image.network(
                                                    item['evidencia'],
                                                  ),
                                                ),
                                          );
                                        },
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                          child: Image.network(
                                            item['evidencia'],
                                            height: 100,
                                            width: 150,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) =>
                                                    const Text(
                                                      'Error al cargar imagen',
                                                    ),
                                          ),
                                        ),
                                      )
                                      : Text(
                                        'Evidencia: ${item['evidencia']}',
                                        style: const TextStyle(
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                            ),
                          Text('Motivo: ${item['motivo'] ?? 'Sin motivo'}'),
                        ],
                      ),
                    );
                  },
                ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
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
  final ImagePicker _imagePicker = ImagePicker();
  Uint8List? _selectedImageBytes;
  String? _selectedImageName;
  bool _isLoading = true;
  bool _isProcessing = false;
  late DateTime _fechaFin;

  @override
  void initState() {
    super.initState();
    final ahora = DateTime.now();
    final mesSiguiente = ahora.month == 12 ? 1 : ahora.month + 1;
    final anioSiguiente = ahora.month == 12 ? ahora.year + 1 : ahora.year;
    _fechaFin = DateTime(anioSiguiente, mesSiguiente, 2);
    _cargarPlanesYGerente();
  }

  @override
  void dispose() {
    super.dispose();
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
      final idTienda = (widget.suscripcion['id_tienda'] as num?)?.toInt();
      final idSuscripcionActual = widget.suscripcion['id'];
      final currentUser = widget.supabase.auth.currentUser;
      final planId = (_planSeleccionado?['id'] as num?)?.toInt();
      final planAmount =
          (_planSeleccionado?['precio_mensual'] as num?)?.toDouble() ?? 0;

      if (currentUser == null) throw Exception('Usuario no autenticado');
      if (idTienda == null || planId == null) {
        throw Exception('No se pudo identificar la tienda o el plan');
      }

      String? evidenciaUrl;
      if (_selectedImageBytes != null) {
        evidenciaUrl = await _uploadEvidenceImage();
        if (evidenciaUrl == null) {
          throw Exception('No se pudo subir la imagen de evidencia');
        }
      }

      final esPlanPro =
          _planSeleccionado!['denominacion']?.toString().toLowerCase().contains(
            'pro',
          ) ??
          false;

      final ahora = DateTime.now();

      // 1. Guardar en el historial
      await widget.supabase.from('app_suscripciones_historial').insert({
        'id_suscripcion': idSuscripcionActual,
        'id_plan_anterior': widget.suscripcion['id_plan'],
        'id_plan_nuevo': _planSeleccionado!['id'],
        'estado_anterior': widget.suscripcion['estado_id'],
        'estado_nuevo': 1, // Activa
        'motivo': 'Renovación de licencia',
        'cambiado_por': currentUser.id,
        'evidencia': evidenciaUrl ?? '',
      });

      // 2. Actualizar la suscripción actual
      await widget.supabase
          .from('app_suscripciones')
          .update({
            'id_plan': planId,
            'fecha_fin': _fechaFin.toIso8601String(),
            'estado': 1, // Activa
            'updated_at': ahora.toIso8601String(),
          })
          .eq('id', idSuscripcionActual);

      await _upsertRenewalSummary(
        month: ahora.month,
        year: ahora.year,
        storeId: idTienda,
        planId: planId,
        amount: planAmount,
      );

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
                        'id_plan': planId,
                        'fecha_fin': _fechaFin.toIso8601String(),
                        'estado': 1,
                        'updated_at': ahora.toIso8601String(),
                      })
                      .eq('id', suscripcionExistente['id']);

                  // También guardar historial para las tiendas del gerente
                  await widget.supabase
                      .from('app_suscripciones_historial')
                      .insert({
                        'id_suscripcion': suscripcionExistente['id'],
                        'id_plan_nuevo': planId,
                        'estado_nuevo': 1,
                        'motivo': 'Renovación por Plan PRO de gerente',
                        'cambiado_por': currentUser.id,
                      });

                  // await _upsertRenewalSummary(
                  //   month: ahora.month,
                  //   year: ahora.year,
                  //   storeId: idTiendaGerente,
                  //   planId: planId,
                  //   amount: planAmount,
                  // );
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

  Future<void> _upsertRenewalSummary({
    required int month,
    required int year,
    required int storeId,
    required int planId,
    required double amount,
  }) async {
    final existing =
        await widget.supabase
            .from('app_suscripciones_renovaciones_resumen')
            .select('id, total_pagado')
            .eq('id_mes', month)
            .eq('id_anno', year)
            .eq('id_tienda', storeId)
            .eq('id_plan', planId)
            .maybeSingle();

    if (existing != null && existing['id'] != null) {
      final currentTotal = (existing['total_pagado'] as num?)?.toDouble() ?? 0;
      await widget.supabase
          .from('app_suscripciones_renovaciones_resumen')
          .update({'total_pagado': currentTotal + amount})
          .eq('id', existing['id']);
    } else {
      await widget.supabase
          .from('app_suscripciones_renovaciones_resumen')
          .insert({
            'id_mes': month,
            'id_anno': year,
            'id_tienda': storeId,
            'id_plan': planId,
            'total_pagado': amount,
          });
    }
  }

  Future<void> _pickImage() async {
    try {
      final ImageSource? source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (BuildContext context) {
          return SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_camera),
                  title: const Text('Tomar foto'),
                  onTap: () => Navigator.of(context).pop(ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('Seleccionar de galería'),
                  onTap: () => Navigator.of(context).pop(ImageSource.gallery),
                ),
                ListTile(
                  leading: const Icon(Icons.cancel),
                  title: const Text('Cancelar'),
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          );
        },
      );

      if (source != null) {
        final XFile? image = await _imagePicker.pickImage(
          source: source,
          maxWidth: 800,
          maxHeight: 800,
          imageQuality: 80,
        );

        if (image != null) {
          final bytes = await image.readAsBytes();
          if (mounted) {
            setState(() {
              _selectedImageBytes = bytes;
              _selectedImageName =
                  'licencia_${DateTime.now().millisecondsSinceEpoch}.jpg';
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al seleccionar imagen: $e')),
        );
      }
    }
  }

  Future<String?> _uploadEvidenceImage() async {
    if (_selectedImageBytes == null || _selectedImageName == null) return null;

    try {
      final fileName = _selectedImageName!;
      final fileBytes = _selectedImageBytes!;

      await widget.supabase.storage
          .from('suscripciones_evidencias')
          .uploadBinary(
            fileName,
            fileBytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );

      final String publicUrl = widget.supabase.storage
          .from('suscripciones_evidencias')
          .getPublicUrl(fileName);

      return publicUrl;
    } catch (e) {
      debugPrint('Error uploading image: $e');
      return null;
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
              items:
                  _planesDisponibles.map((plan) {
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
            const SizedBox(height: 16),
            const Text('Fecha de Vencimiento:'),
            const SizedBox(height: 8),
            InkWell(
              onTap: () async {
                final DateTime? picked = await showDatePicker(
                  context: context,
                  initialDate: _fechaFin,
                  firstDate: DateTime.now(),
                  lastDate: DateTime(2030),
                );
                if (picked != null) {
                  setState(() => _fechaFin = picked);
                }
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_fechaFin.day}/${_fechaFin.month}/${_fechaFin.year}',
                    ),
                    const Icon(Icons.calendar_today, size: 16),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Evidencia de pago (Imagen):'),
            const SizedBox(height: 8),
            if (_selectedImageBytes != null)
              Stack(
                children: [
                  Container(
                    height: 150,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.textSecondary),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        _selectedImageBytes!,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                      ),
                      onPressed:
                          () => setState(() {
                            _selectedImageBytes = null;
                            _selectedImageName = null;
                          }),
                    ),
                  ),
                ],
              )
            else
              OutlinedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('Subir evidencia'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
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
          child:
              _isProcessing
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

// =====================================================
// Dialog para asignar agente a una suscripción
// =====================================================

class _AsignarAgenteDialogContent extends StatefulWidget {
  final Map<String, dynamic> suscripcion;
  final VoidCallback onAsignacionCompleta;

  const _AsignarAgenteDialogContent({
    required this.suscripcion,
    required this.onAsignacionCompleta,
  });

  @override
  State<_AsignarAgenteDialogContent> createState() =>
      _AsignarAgenteDialogContentState();
}

class _AsignarAgenteDialogContentState
    extends State<_AsignarAgenteDialogContent> {
  List<Map<String, dynamic>> _agentes = [];
  int? _selectedAgenteId;
  bool _isLoading = true;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _selectedAgenteId = widget.suscripcion['id_agente'] as int?;
    _loadAgentes();
  }

  Future<void> _loadAgentes() async {
    try {
      final agentes = await AgenteService.getAgentes(soloActivos: true);
      if (mounted) {
        setState(() {
          _agentes = agentes;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error cargando agentes: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _asignar() async {
    setState(() => _isProcessing = true);
    try {
      await AgenteService.asignarAgenteASuscripcion(
        idSuscripcion: widget.suscripcion['id'],
        idAgente: _selectedAgenteId,
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _selectedAgenteId != null
                  ? 'Agente asignado correctamente'
                  : 'Agente desvinculado correctamente',
            ),
            backgroundColor: AppColors.success,
          ),
        );
        widget.onAsignacionCompleta();
      }
    } catch (e) {
      debugPrint('Error asignando agente: $e');
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.support_agent, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Asignar Agente - ${widget.suscripcion['tienda_nombre']}',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: _isLoading
            ? const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Plan: ${widget.suscripcion['plan']}',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int?>(
                    value: _selectedAgenteId,
                    decoration: const InputDecoration(
                      labelText: 'Agente',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text(
                          'Sin asignar',
                          style: TextStyle(
                            fontStyle: FontStyle.italic,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                      ..._agentes.map((agente) {
                        return DropdownMenuItem<int?>(
                          value: agente['id'] as int,
                          child: Text(
                            '${agente['nombre']} ${agente['apellidos']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }),
                    ],
                    onChanged: (value) {
                      setState(() => _selectedAgenteId = value);
                    },
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _isProcessing ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _isProcessing ? null : _asignar,
          child: _isProcessing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

// =====================================================
// Dialog para editar licencia (con agente)
// =====================================================

class _EditLicenciaDialogContent extends StatefulWidget {
  final Map<String, dynamic> suscripcion;
  final SupabaseClient supabase;
  final VoidCallback onEditComplete;

  const _EditLicenciaDialogContent({
    required this.suscripcion,
    required this.supabase,
    required this.onEditComplete,
  });

  @override
  State<_EditLicenciaDialogContent> createState() =>
      _EditLicenciaDialogContentState();
}

class _EditLicenciaDialogContentState
    extends State<_EditLicenciaDialogContent> {
  final _formKey = GlobalKey<FormState>();

  List<Map<String, dynamic>> _planesDisponibles = [];
  List<Map<String, dynamic>> _agentesDisponibles = [];
  bool _isLoading = true;
  bool _isProcessing = false;

  late DateTime _fechaInicio;
  late DateTime _fechaFin;
  late int _estado;
  late int _idPlan;
  int? _idAgente;
  late TextEditingController _observacionesController;

  @override
  void initState() {
    super.initState();
    _initFields();
    _loadData();
  }

  @override
  void dispose() {
    _observacionesController.dispose();
    super.dispose();
  }

  void _initFields() {
    try {
      _fechaInicio = DateTime.parse(widget.suscripcion['fecha_inicio']);
    } catch (e) {
      _fechaInicio = DateTime.now();
    }

    try {
      if (widget.suscripcion['fecha_fin'] != null) {
        _fechaFin = DateTime.parse(widget.suscripcion['fecha_fin']);
      } else {
        _fechaFin = DateTime.now().add(const Duration(days: 30));
      }
    } catch (e) {
      _fechaFin = DateTime.now().add(const Duration(days: 30));
    }

    _estado = int.tryParse(widget.suscripcion['estado_id'].toString()) ?? 1;
    _idPlan = int.tryParse(widget.suscripcion['id_plan'].toString()) ?? 1;
    _idAgente = widget.suscripcion['id_agente'] as int?;
    _observacionesController = TextEditingController(
      text: widget.suscripcion['observaciones'] ?? '',
    );
  }

  Future<void> _loadData() async {
    try {
      final planes = await widget.supabase
          .from('app_suscripciones_plan')
          .select('*')
          .eq('es_activo', true)
          .order('id', ascending: true);

      final agentes = await AgenteService.getAgentes(soloActivos: true);

      if (mounted) {
        setState(() {
          _planesDisponibles = List<Map<String, dynamic>>.from(planes);
          _agentesDisponibles = agentes;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error cargando datos para edición: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _fechaInicio : _fechaFin,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _fechaInicio = picked;
        } else {
          _fechaFin = picked;
        }
      });
    }
  }

  Future<void> _guardarCambios() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isProcessing = true);

    try {
      final idSuscripcion = widget.suscripcion['id'];
      final currentUser = widget.supabase.auth.currentUser;

      final planAnterior = widget.suscripcion['id_plan'];
      final estadoAnterior = widget.suscripcion['estado_id'];

      final fechaFinString = _fechaFin.toIso8601String();
      final fechaInicioString = _fechaInicio.toIso8601String();

      final haCambiadoPlan = planAnterior != _idPlan;
      final haCambiadoEstado = estadoAnterior != _estado;
      final haCambiadoFecha = widget.suscripcion['fecha_fin'] != fechaFinString;

      if ((haCambiadoPlan || haCambiadoEstado || haCambiadoFecha) &&
          currentUser != null) {
        await widget.supabase.from('app_suscripciones_historial').insert({
          'id_suscripcion': idSuscripcion,
          'id_plan_anterior': planAnterior,
          'id_plan_nuevo': _idPlan,
          'estado_anterior': estadoAnterior,
          'estado_nuevo': _estado,
          'motivo': 'Edición administrativa de licencia',
          'cambiado_por': currentUser.id,
        });
      }

      await widget.supabase
          .from('app_suscripciones')
          .update({
            'id_plan': _idPlan,
            'fecha_inicio': fechaInicioString,
            'fecha_fin': fechaFinString,
            'estado': _estado,
            'id_agente': _idAgente,
            'observaciones': _observacionesController.text,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', idSuscripcion);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Licencia actualizada correctamente'),
            backgroundColor: AppColors.success,
          ),
        );
        widget.onEditComplete();
      }
    } catch (e) {
      debugPrint('Error al actualizar licencia: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al actualizar: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const AlertDialog(
        content: SizedBox(
          height: 100,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return AlertDialog(
      title: Text('Editar Licencia - ${widget.suscripcion['tienda_nombre']}'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<int>(
                value: _idPlan,
                decoration: const InputDecoration(
                  labelText: 'Plan',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: _planesDisponibles.map((plan) {
                  return DropdownMenuItem<int>(
                    value: plan['id'],
                    child: Text(plan['denominacion']),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _idPlan = value);
                },
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<int>(
                value: _estado,
                decoration: const InputDecoration(
                  labelText: 'Estado',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('Activa')),
                  DropdownMenuItem(value: 0, child: Text('Inactiva')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _estado = value);
                },
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<int?>(
                value: _idAgente,
                decoration: const InputDecoration(
                  labelText: 'Agente',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                isExpanded: true,
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text(
                      'Sin asignar',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  ..._agentesDisponibles.map((agente) {
                    return DropdownMenuItem<int?>(
                      value: agente['id'] as int,
                      child: Text(
                        '${agente['nombre']} ${agente['apellidos']}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }),
                ],
                onChanged: (value) {
                  setState(() => _idAgente = value);
                },
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _selectDate(context, true),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Fecha Inicio',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${_fechaInicio.day}/${_fechaInicio.month}/${_fechaInicio.year}',
                            ),
                            const Icon(Icons.calendar_today, size: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: () => _selectDate(context, false),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Fecha Vencimiento',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${_fechaFin.day}/${_fechaFin.month}/${_fechaFin.year}',
                            ),
                            const Icon(Icons.calendar_today, size: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _observacionesController,
                decoration: const InputDecoration(
                  labelText: 'Observaciones',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _isProcessing ? null : _guardarCambios,
          child: _isProcessing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

class _LicenciaDetailsDialog extends StatefulWidget {
  final Map<String, dynamic> suscripcion;
  final SupabaseClient supabase;

  const _LicenciaDetailsDialog({
    required this.suscripcion,
    required this.supabase,
  });

  @override
  State<_LicenciaDetailsDialog> createState() => _LicenciaDetailsDialogState();
}

class _LicenciaDetailsDialogState extends State<_LicenciaDetailsDialog> {
  late Future<Map<String, dynamic>> _tiendaDetailsFuture;

  @override
  void initState() {
    super.initState();
    _tiendaDetailsFuture = _fetchTiendaDetails();
  }

  Future<Map<String, dynamic>> _fetchTiendaDetails() async {
    try {
      final idTienda = widget.suscripcion['id_tienda'];
      final tiendaResp = await widget.supabase
          .from('app_dat_tienda')
          .select()
          .eq('id', idTienda)
          .single();
      return tiendaResp;
    } catch (e) {
      debugPrint('Error fetching tienda details: $e');
      return {};
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: FutureBuilder<Map<String, dynamic>>(
        future: _tiendaDetailsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return AlertDialog(
              title: const Text('Error'),
              content: const Text('No se pudieron cargar los detalles de la tienda'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cerrar'),
                ),
              ],
            );
          }

          final tienda = snapshot.data!;
          final suscripcion = widget.suscripcion;

          return SingleChildScrollView(
            child: AlertDialog(
              title: Text(tienda['denominacion'] ?? 'Tienda'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSection('Información de Suscripción', [
                      _buildDetailRow('Plan', suscripcion['plan'] ?? 'N/A'),
                      _buildDetailRow('Estado', suscripcion['estado'] ?? 'N/A'),
                      _buildDetailRow(
                        'Fecha Inicio',
                        _formatDate(suscripcion['fecha_inicio']),
                      ),
                      _buildDetailRow(
                        'Fecha Vencimiento',
                        _formatDate(suscripcion['fecha_vencimiento']),
                      ),
                      _buildDetailRow(
                        'Días Restantes',
                        '${suscripcion['dias_restantes'] ?? 0}',
                      ),
                      _buildDetailRow('Precio', '\$${suscripcion['precio'] ?? 0}'),
                      _buildDetailRow(
                        'Agente',
                        suscripcion['agente_nombre'] ?? 'Sin asignar',
                      ),
                      _buildDetailRow(
                        'Activa',
                        suscripcion['activa'] == true ? 'Sí' : 'No',
                      ),
                    ]),
                    const SizedBox(height: 16),
                    _buildSection('Información de Tienda', [
                      _buildDetailRow('ID', '${tienda['id']}'),
                      _buildDetailRow(
                        'Nombre',
                        tienda['denominacion'] ?? 'N/A',
                      ),
                      _buildDetailRow(
                        'Dirección',
                        tienda['direccion'] ?? 'No especificada',
                      ),
                      _buildDetailRow(
                        'Ubicación',
                        tienda['ubicacion'] ?? 'No especificada',
                      ),
                      _buildDetailRow(
                        'País',
                        tienda['nombre_pais'] ?? tienda['pais'] ?? 'N/A',
                      ),
                      _buildDetailRow(
                        'Estado/Provincia',
                        tienda['nombre_estado'] ??
                            tienda['estado'] ??
                            tienda['provincia'] ??
                            'N/A',
                      ),
                      _buildDetailRow(
                        'Teléfono',
                        tienda['phone'] ?? 'No especificado',
                      ),
                      _buildDetailRow(
                        'Creada',
                        _formatDate(tienda['created_at']),
                      ),
                    ]),
                    const SizedBox(height: 16),
                    if (tienda['latitude'] != null && tienda['longitude'] != null)
                      _buildSection('Ubicación Geográfica', [
                        _buildDetailRow(
                          'Latitud',
                          '${tienda['latitude']}',
                        ),
                        _buildDetailRow(
                          'Longitud',
                          '${tienda['longitude']}',
                        ),
                      ]),
                    if (tienda['latitude'] != null && tienda['longitude'] != null)
                      const SizedBox(height: 16),
                    _buildSection('Horarios de Operación', [
                      _buildDetailRow(
                        'Hora Apertura',
                        tienda['hora_apertura'] ?? '09:00',
                      ),
                      _buildDetailRow(
                        'Hora Cierre',
                        tienda['hora_cierre'] ?? '18:00',
                      ),
                      if (tienda['dias_trabajo'] != null)
                        _buildDetailRow(
                          'Días de Trabajo',
                          _formatDiasTrabajo(tienda['dias_trabajo']),
                        ),
                    ]),
                    const SizedBox(height: 16),
                    _buildSection('Configuración', [
                      _buildDetailRow(
                        'Mostrar en Catálogo',
                        tienda['mostrar_en_catalogo'] == true ? 'Sí' : 'No',
                      ),
                      _buildDetailRow(
                        'Solo Catálogo',
                        tienda['only_catalogo'] == true ? 'Sí' : 'No',
                      ),
                      _buildDetailRow(
                        'Validada',
                        tienda['validada'] == true ? 'Sí' : 'No',
                      ),
                      _buildDetailRow(
                        'Admin Carnaval',
                        tienda['admin_carnaval'] == true ? 'Sí' : 'No',
                      ),
                    ]),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cerrar'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1F2937),
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF6B7280),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF1F2937),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    try {
      final dt = date is String ? DateTime.parse(date) : date as DateTime;
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (e) {
      return 'N/A';
    }
  }

  String _formatDiasTrabajo(dynamic dias) {
    if (dias == null) return 'N/A';
    try {
      if (dias is String) {
        dias = dias.replaceAll('"', '').replaceAll('[', '').replaceAll(']', '');
      }
      if (dias is List) {
        return dias.join(', ');
      }
      return dias.toString();
    } catch (e) {
      return 'N/A';
    }
  }
}

class _CreateLicenciaDialogContent extends StatefulWidget {
  final SupabaseClient supabase;
  final List<Map<String, dynamic>> tiendas;
  final VoidCallback onCreateComplete;

  const _CreateLicenciaDialogContent({
    required this.supabase,
    required this.tiendas,
    required this.onCreateComplete,
  });

  @override
  State<_CreateLicenciaDialogContent> createState() =>
      _CreateLicenciaDialogContentState();
}

class _CreateLicenciaDialogContentState
    extends State<_CreateLicenciaDialogContent> {
  List<Map<String, dynamic>> _planesDisponibles = [];
  Map<String, dynamic>? _planSeleccionado;
  int? _selectedTiendaId;
  DateTime? _fechaVencimiento;
  final ImagePicker _imagePicker = ImagePicker();
  Uint8List? _selectedImageBytes;
  String? _selectedImageName;
  bool _isLoading = true;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _cargarPlanes();
  }

  Future<void> _cargarPlanes() async {
    try {
      final planesResponse = await widget.supabase
          .from('app_suscripciones_plan')
          .select('*')
          .eq('es_activo', true)
          .order('id', ascending: true);

      if (mounted) {
        setState(() {
          _planesDisponibles = List<Map<String, dynamic>>.from(planesResponse);
          if (_planesDisponibles.isNotEmpty) {
            _planSeleccionado = _planesDisponibles.first;
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
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final ImageSource? source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (BuildContext context) {
          return SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_camera),
                  title: const Text('Tomar foto'),
                  onTap: () => Navigator.of(context).pop(ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('Seleccionar de galería'),
                  onTap: () => Navigator.of(context).pop(ImageSource.gallery),
                ),
                ListTile(
                  leading: const Icon(Icons.cancel),
                  title: const Text('Cancelar'),
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          );
        },
      );

      if (source != null) {
        final XFile? image = await _imagePicker.pickImage(
          source: source,
          maxWidth: 800,
          maxHeight: 800,
          imageQuality: 80,
        );

        if (image != null) {
          final bytes = await image.readAsBytes();
          if (mounted) {
            setState(() {
              _selectedImageBytes = bytes;
              _selectedImageName =
                  'licencia_${DateTime.now().millisecondsSinceEpoch}.jpg';
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al seleccionar imagen: $e')),
        );
      }
    }
  }

  Future<String?> _uploadEvidenceImage() async {
    if (_selectedImageBytes == null || _selectedImageName == null) return null;

    try {
      final fileName = _selectedImageName!;
      final fileBytes = _selectedImageBytes!;

      await widget.supabase.storage
          .from('suscripciones_evidencias')
          .uploadBinary(
            fileName,
            fileBytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );

      final String publicUrl = widget.supabase.storage
          .from('suscripciones_evidencias')
          .getPublicUrl(fileName);

      return publicUrl;
    } catch (e) {
      debugPrint('Error uploading image: $e');
      return null;
    }
  }

  Future<void> _createLicencia() async {
    if (_selectedTiendaId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona una tienda'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_planSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona un plan'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_fechaVencimiento == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona una fecha de vencimiento'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      String? evidenciaUrl;

      // Upload photo if provided
      if (_selectedImageBytes != null) {
        evidenciaUrl = await _uploadEvidenceImage();
        if (evidenciaUrl == null) {
          throw Exception('No se pudo subir la imagen');
        }
      }

      // Create subscription
      await widget.supabase.from('app_suscripciones').insert({
        'id_tienda': _selectedTiendaId,
        'id_plan': _planSeleccionado!['id'],
        'fecha_inicio': DateTime.now().toIso8601String(),
        'fecha_fin': _fechaVencimiento!.toIso8601String(),
        'estado': 1,
        'metodo_pago': 'manual',
        'renovacion_automatica': false,
        'foto_url': evidenciaUrl,
      });

      if (!mounted) return;

      Navigator.pop(context);
      widget.onCreateComplete();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Licencia creada exitosamente'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      debugPrint('Error creating license: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al crear licencia: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nueva Licencia'),
      content: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 16,
                children: [
                  // Tienda dropdown
                  DropdownButtonFormField<int>(
                    value: _selectedTiendaId,
                    decoration: const InputDecoration(
                      labelText: 'Tienda',
                      border: OutlineInputBorder(),
                    ),
                    items: widget.tiendas
                        .map((tienda) => DropdownMenuItem(
                              value: tienda['id'] as int,
                              child: Text(tienda['denominacion'] ?? 'Sin nombre'),
                            ))
                        .toList(),
                    onChanged: (value) {
                      setState(() => _selectedTiendaId = value);
                    },
                  ),

                  // Plan dropdown
                  DropdownButtonFormField<Map<String, dynamic>>(
                    value: _planSeleccionado,
                    decoration: const InputDecoration(
                      labelText: 'Plan',
                      border: OutlineInputBorder(),
                    ),
                    items: _planesDisponibles
                        .map((plan) => DropdownMenuItem(
                              value: plan,
                              child: Text(plan['denominacion'] ?? 'Sin nombre'),
                            ))
                        .toList(),
                    onChanged: (value) {
                      setState(() => _planSeleccionado = value);
                    },
                  ),

                  // Expiration date picker
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate:
                            DateTime.now().add(const Duration(days: 30)),
                        firstDate: DateTime.now(),
                        lastDate:
                            DateTime.now().add(const Duration(days: 3650)),
                      );
                      if (picked != null) {
                        setState(() => _fechaVencimiento = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _fechaVencimiento == null
                                ? 'Fecha de vencimiento'
                                : '${_fechaVencimiento!.day}/${_fechaVencimiento!.month}/${_fechaVencimiento!.year}',
                            style: TextStyle(
                              color: _fechaVencimiento == null
                                  ? Colors.grey[600]
                                  : Colors.black,
                            ),
                          ),
                          const Icon(Icons.calendar_today, size: 20),
                        ],
                      ),
                    ),
                  ),

                  // Photo upload
                  if (_selectedImageBytes != null)
                    Column(
                      children: [
                        Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Image.memory(_selectedImageBytes!,
                              fit: BoxFit.cover),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _pickImage,
                          icon: const Icon(Icons.image),
                          label: const Text('Cambiar foto'),
                        ),
                      ],
                    )
                  else
                    ElevatedButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.image),
                      label: const Text('Seleccionar foto (opcional)'),
                    ),
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: _isProcessing ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _isProcessing ? null : _createLicencia,
          child: _isProcessing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Crear'),
        ),
      ],
    );
  }
}
