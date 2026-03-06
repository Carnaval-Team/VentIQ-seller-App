import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../widgets/app_drawer.dart';
import '../utils/platform_utils.dart';
import '../services/agente_service.dart';

class AgentesScreen extends StatefulWidget {
  const AgentesScreen({super.key});

  @override
  State<AgentesScreen> createState() => _AgentesScreenState();
}

class _AgentesScreenState extends State<AgentesScreen> {
  List<Map<String, dynamic>> _agentes = [];
  List<Map<String, dynamic>> _filteredAgentes = [];
  bool _isLoading = true;
  String _searchQuery = '';
  bool _mostrarInactivos = false;

  @override
  void initState() {
    super.initState();
    _loadAgentes();
  }

  Future<void> _loadAgentes() async {
    setState(() => _isLoading = true);
    try {
      final agentes = await AgenteService.getAgentes(
        soloActivos: !_mostrarInactivos,
      );

      // Contar suscripciones por agente
      final agentesConConteo = <Map<String, dynamic>>[];
      for (final agente in agentes) {
        final count = await AgenteService.contarSuscripcionesActivas(
          agente['id'],
        );
        agentesConConteo.add({
          ...agente,
          'suscripciones_activas': count,
        });
      }

      if (mounted) {
        setState(() {
          _agentes = agentesConConteo;
          _isLoading = false;
        });
        _filterAgentes();
      }
    } catch (e) {
      debugPrint('Error cargando agentes: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar agentes: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _filterAgentes() {
    setState(() {
      _filteredAgentes = _agentes.where((agente) {
        final nombre = '${agente['nombre']} ${agente['apellidos']}'.toLowerCase();
        final telefono = (agente['telefono'] ?? '').toString().toLowerCase();
        final email = (agente['email'] ?? '').toString().toLowerCase();
        return nombre.contains(_searchQuery.toLowerCase()) ||
            telefono.contains(_searchQuery.toLowerCase()) ||
            email.contains(_searchQuery.toLowerCase());
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isDesktop = PlatformUtils.shouldUseDesktopLayout(screenSize.width);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Agentes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAgentes,
            tooltip: 'Actualizar',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showCrearAgenteDialog,
            tooltip: 'Nuevo Agente',
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
              height: MediaQuery.of(context).size.height * 0.55,
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
                  labelText: 'Buscar agente',
                  prefixIcon: Icon(Icons.search),
                  border: InputBorder.none,
                ),
                onChanged: (value) {
                  _searchQuery = value;
                  _filterAgentes();
                },
              ),
            ),
            const VerticalDivider(width: 1),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Inactivos', style: TextStyle(fontSize: 12)),
                Switch(
                  value: _mostrarInactivos,
                  onChanged: (value) {
                    setState(() => _mostrarInactivos = value);
                    _loadAgentes();
                  },
                  activeColor: AppColors.primary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStats() {
    final total = _agentes.length;
    final activos = _agentes.where((a) => a['estado'] == 1).length;
    final totalSuscripciones = _agentes.fold<int>(
      0,
      (sum, a) => sum + ((a['suscripciones_activas'] as int?) ?? 0),
    );

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Total Agentes',
            total.toString(),
            Icons.support_agent,
            AppColors.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Activos',
            activos.toString(),
            Icons.check_circle,
            AppColors.success,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Licencias Asignadas',
            totalSuscripciones.toString(),
            Icons.card_membership,
            AppColors.info,
          ),
        ),
      ],
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
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
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
              'Lista de Agentes',
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
                      DataColumn(label: Text('Teléfono')),
                      DataColumn(label: Text('Email')),
                      DataColumn(label: Text('Licencias')),
                      DataColumn(label: Text('Estado')),
                      DataColumn(label: Text('Acciones')),
                    ],
                    rows: _filteredAgentes.map((agente) {
                      final esActivo = agente['estado'] == 1;
                      return DataRow(
                        cells: [
                          DataCell(
                            Text(
                              '${agente['nombre']} ${agente['apellidos']}',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          DataCell(Text(agente['telefono'] ?? '-')),
                          DataCell(Text(agente['email'] ?? '-')),
                          DataCell(
                            Chip(
                              label: Text(
                                '${agente['suscripciones_activas'] ?? 0}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white,
                                ),
                              ),
                              backgroundColor: AppColors.info,
                              padding: EdgeInsets.zero,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          DataCell(
                            Chip(
                              label: Text(
                                esActivo ? 'Activo' : 'Inactivo',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: esActivo
                                      ? AppColors.success
                                      : AppColors.error,
                                ),
                              ),
                              backgroundColor: esActivo
                                  ? AppColors.success.withOpacity(0.1)
                                  : AppColors.error.withOpacity(0.1),
                              side: BorderSide.none,
                              padding: EdgeInsets.zero,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 20),
                                  onPressed: () =>
                                      _showEditarAgenteDialog(agente),
                                  tooltip: 'Editar',
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.assignment,
                                    size: 20,
                                  ),
                                  onPressed: () =>
                                      _showSuscripcionesAgente(agente),
                                  tooltip: 'Ver Licencias',
                                ),
                                IconButton(
                                  icon: Icon(
                                    esActivo
                                        ? Icons.block
                                        : Icons.check_circle_outline,
                                    size: 20,
                                    color: esActivo
                                        ? AppColors.error
                                        : AppColors.success,
                                  ),
                                  onPressed: () =>
                                      _toggleEstadoAgente(agente),
                                  tooltip: esActivo
                                      ? 'Desactivar'
                                      : 'Activar',
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
      itemCount: _filteredAgentes.length,
      itemBuilder: (context, index) {
        final agente = _filteredAgentes[index];
        final esActivo = agente['estado'] == 1;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: esActivo
                  ? AppColors.primary.withOpacity(0.1)
                  : Colors.grey.withOpacity(0.1),
              child: Icon(
                Icons.support_agent,
                color: esActivo ? AppColors.primary : Colors.grey,
              ),
            ),
            title: Text(
              '${agente['nombre']} ${agente['apellidos']}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (agente['telefono'] != null)
                  Text('📱 ${agente['telefono']}'),
                if (agente['email'] != null)
                  Text('📧 ${agente['email']}'),
                Text(
                  'Licencias: ${agente['suscripciones_activas'] ?? 0}',
                  style: TextStyle(
                    color: AppColors.info,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'editar':
                    _showEditarAgenteDialog(agente);
                    break;
                  case 'licencias':
                    _showSuscripcionesAgente(agente);
                    break;
                  case 'toggle':
                    _toggleEstadoAgente(agente);
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'editar',
                  child: ListTile(
                    leading: Icon(Icons.edit),
                    title: Text('Editar'),
                    dense: true,
                  ),
                ),
                const PopupMenuItem(
                  value: 'licencias',
                  child: ListTile(
                    leading: Icon(Icons.assignment),
                    title: Text('Ver Licencias'),
                    dense: true,
                  ),
                ),
                PopupMenuItem(
                  value: 'toggle',
                  child: ListTile(
                    leading: Icon(
                      esActivo ? Icons.block : Icons.check_circle_outline,
                      color: esActivo ? AppColors.error : AppColors.success,
                    ),
                    title: Text(esActivo ? 'Desactivar' : 'Activar'),
                    dense: true,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // =====================================================
  // DIALOGS
  // =====================================================

  void _showCrearAgenteDialog() {
    final nombreController = TextEditingController();
    final apellidosController = TextEditingController();
    final telefonoController = TextEditingController();
    final emailController = TextEditingController();
    final observacionesController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) {
        bool isProcessing = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.person_add, color: AppColors.primary),
                  SizedBox(width: 8),
                  Text('Nuevo Agente'),
                ],
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nombreController,
                        decoration: const InputDecoration(
                          labelText: 'Nombre *',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Requerido' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: apellidosController,
                        decoration: const InputDecoration(
                          labelText: 'Apellidos *',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Requerido' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: telefonoController,
                        decoration: const InputDecoration(
                          labelText: 'Teléfono',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: emailController,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: observacionesController,
                        decoration: const InputDecoration(
                          labelText: 'Observaciones',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      isProcessing ? null : () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: isProcessing
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setDialogState(() => isProcessing = true);
                          try {
                            await AgenteService.crearAgente(
                              nombre: nombreController.text.trim(),
                              apellidos: apellidosController.text.trim(),
                              telefono: telefonoController.text.trim().isEmpty
                                  ? null
                                  : telefonoController.text.trim(),
                              email: emailController.text.trim().isEmpty
                                  ? null
                                  : emailController.text.trim(),
                              observaciones:
                                  observacionesController.text.trim().isEmpty
                                      ? null
                                      : observacionesController.text.trim(),
                            );
                            if (context.mounted) Navigator.pop(context);
                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                const SnackBar(
                                  content: Text('Agente creado correctamente'),
                                  backgroundColor: AppColors.success,
                                ),
                              );
                              _loadAgentes();
                            }
                          } catch (e) {
                            setDialogState(() => isProcessing = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error: $e'),
                                  backgroundColor: AppColors.error,
                                ),
                              );
                            }
                          }
                        },
                  child: isProcessing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Crear'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditarAgenteDialog(Map<String, dynamic> agente) {
    final nombreController = TextEditingController(text: agente['nombre']);
    final apellidosController =
        TextEditingController(text: agente['apellidos']);
    final telefonoController =
        TextEditingController(text: agente['telefono'] ?? '');
    final emailController =
        TextEditingController(text: agente['email'] ?? '');
    final observacionesController =
        TextEditingController(text: agente['observaciones'] ?? '');
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) {
        bool isProcessing = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.edit, color: AppColors.primary),
                  SizedBox(width: 8),
                  Text('Editar Agente'),
                ],
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nombreController,
                        decoration: const InputDecoration(
                          labelText: 'Nombre *',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Requerido' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: apellidosController,
                        decoration: const InputDecoration(
                          labelText: 'Apellidos *',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Requerido' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: telefonoController,
                        decoration: const InputDecoration(
                          labelText: 'Teléfono',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: emailController,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: observacionesController,
                        decoration: const InputDecoration(
                          labelText: 'Observaciones',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      isProcessing ? null : () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: isProcessing
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setDialogState(() => isProcessing = true);
                          try {
                            await AgenteService.actualizarAgente(
                              id: agente['id'],
                              nombre: nombreController.text.trim(),
                              apellidos: apellidosController.text.trim(),
                              telefono: telefonoController.text.trim().isEmpty
                                  ? null
                                  : telefonoController.text.trim(),
                              email: emailController.text.trim().isEmpty
                                  ? null
                                  : emailController.text.trim(),
                              observaciones:
                                  observacionesController.text.trim().isEmpty
                                      ? null
                                      : observacionesController.text.trim(),
                            );
                            if (context.mounted) Navigator.pop(context);
                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                const SnackBar(
                                  content:
                                      Text('Agente actualizado correctamente'),
                                  backgroundColor: AppColors.success,
                                ),
                              );
                              _loadAgentes();
                            }
                          } catch (e) {
                            setDialogState(() => isProcessing = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error: $e'),
                                  backgroundColor: AppColors.error,
                                ),
                              );
                            }
                          }
                        },
                  child: isProcessing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _toggleEstadoAgente(Map<String, dynamic> agente) async {
    final esActivo = agente['estado'] == 1;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(esActivo ? 'Desactivar Agente' : 'Activar Agente'),
        content: Text(
          esActivo
              ? '¿Desactivar a ${agente['nombre']} ${agente['apellidos']}?'
              : '¿Activar a ${agente['nombre']} ${agente['apellidos']}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: esActivo ? AppColors.error : AppColors.success,
              foregroundColor: Colors.white,
            ),
            child: Text(esActivo ? 'Desactivar' : 'Activar'),
          ),
        ],
      ),
    );

    if (confirmado != true) return;

    try {
      if (esActivo) {
        await AgenteService.desactivarAgente(agente['id']);
      } else {
        await AgenteService.activarAgente(agente['id']);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              esActivo
                  ? 'Agente desactivado'
                  : 'Agente activado',
            ),
            backgroundColor: AppColors.success,
          ),
        );
        _loadAgentes();
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

  void _showSuscripcionesAgente(Map<String, dynamic> agente) {
    showDialog(
      context: context,
      builder: (context) => _SuscripcionesAgenteDialog(agente: agente),
    );
  }
}

// =====================================================
// Dialog para ver suscripciones de un agente
// =====================================================

class _SuscripcionesAgenteDialog extends StatefulWidget {
  final Map<String, dynamic> agente;

  const _SuscripcionesAgenteDialog({required this.agente});

  @override
  State<_SuscripcionesAgenteDialog> createState() =>
      _SuscripcionesAgenteDialogState();
}

class _SuscripcionesAgenteDialogState
    extends State<_SuscripcionesAgenteDialog> {
  List<Map<String, dynamic>> _suscripciones = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSuscripciones();
  }

  Future<void> _loadSuscripciones() async {
    try {
      final suscripciones = await AgenteService.getSuscripcionesDeAgente(
        widget.agente['id'],
      );
      if (mounted) {
        setState(() {
          _suscripciones = suscripciones;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error cargando suscripciones del agente: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '-';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Licencias - ${widget.agente['nombre']} ${widget.agente['apellidos']}',
      ),
      content: SizedBox(
        width: 500,
        height: 400,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _suscripciones.isEmpty
                ? const Center(
                    child: Text('No tiene licencias asignadas'),
                  )
                : ListView.separated(
                    itemCount: _suscripciones.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, index) {
                      final s = _suscripciones[index];
                      final tienda = s['app_dat_tienda'];
                      final plan = s['app_suscripciones_plan'];
                      final fechaFin = s['fecha_fin'];
                      final diasRestantes = fechaFin != null
                          ? DateTime.parse(fechaFin)
                              .difference(DateTime.now())
                              .inDays
                          : 999;

                      return ListTile(
                        title: Text(
                          tienda?['denominacion'] ?? 'Sin tienda',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Plan: ${plan?['denominacion'] ?? '-'}'),
                            Text('Vence: ${_formatDate(fechaFin)}'),
                          ],
                        ),
                        trailing: Chip(
                          label: Text(
                            diasRestantes < 0
                                ? 'Vencida'
                                : '$diasRestantes días',
                            style: TextStyle(
                              fontSize: 11,
                              color: diasRestantes < 0
                                  ? AppColors.error
                                  : diasRestantes <= 30
                                      ? AppColors.warning
                                      : AppColors.success,
                            ),
                          ),
                          backgroundColor: (diasRestantes < 0
                                  ? AppColors.error
                                  : diasRestantes <= 30
                                      ? AppColors.warning
                                      : AppColors.success)
                              .withOpacity(0.1),
                          side: BorderSide.none,
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
