import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  List<Map<String, dynamic>> _carnaval = [];
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

      List<Map<String, dynamic>> carnaval = [];
      try {
        carnaval = await AgenteService.getAgentesCarnaval();
      } catch (e) {
        debugPrint('Agentes Carnaval no disponibles: $e');
      }

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
          _carnaval = carnaval;
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
                      DataColumn(label: Text('Tarjeta')),
                      DataColumn(label: Text('Licencias')),
                      DataColumn(label: Text('Estado')),
                      DataColumn(label: Text('Acciones')),
                    ],
                    rows: _filteredAgentes.map((agente) {
                      final esActivo = agente['estado'] == 1;
                      return DataRow(
                        cells: [
                          DataCell(
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${agente['nombre']} ${agente['apellidos']}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Wrap(spacing: 4, children: _rolChips(agente)),
                              ],
                            ),
                          ),
                          DataCell(Text(agente['telefono'] ?? '-')),
                          DataCell(Text(agente['email'] ?? '-')),
                          DataCell(_tarjetaCell(agente['tarjeta']?.toString())),
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
                Text(_etiquetaTarjeta(agente['tarjeta']?.toString())),
                if (_rolChips(agente).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(spacing: 4, children: _rolChips(agente)),
                  ),
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

  List<Widget> _rolChips(Map<String, dynamic> agente) {
    final chips = <Widget>[];
    if (agente['es_socio'] == true) {
      chips.add(const Chip(
        label: Text('Socio', style: TextStyle(fontSize: 11)),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ));
    }
    if (agente['despliega'] == true) {
      chips.add(const Chip(
        label: Text('Despliegue', style: TextStyle(fontSize: 11)),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ));
    }
    final carnavalId = (agente['id_agente_carnaval'] as num?)?.toInt();
    if (carnavalId != null) {
      chips.add(Chip(
        label: Text(
          _nombreCarnaval(carnavalId) ?? 'Carnaval',
          style: const TextStyle(fontSize: 11),
        ),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ));
    }
    return chips;
  }

  String? _nombreCarnaval(int id) {
    for (final row in _carnaval) {
      if ((row['id'] as num?)?.toInt() == id) {
        return '${row['nombre']} ${row['apellidos']}'.trim();
      }
    }
    return null;
  }

  String _etiquetaTarjeta(String? tarjeta) {
    final limpia = (tarjeta ?? '').replaceAll(RegExp(r'\s+'), '');
    if (limpia.isEmpty) return 'Tarjeta: sin registrar';
    if (limpia.length <= 4) return 'Tarjeta: $limpia';
    return 'Tarjeta: ···· ${limpia.substring(limpia.length - 4)}';
  }

  Widget _tarjetaCell(String? tarjeta) {
    final limpia = (tarjeta ?? '').replaceAll(RegExp(r'\s+'), '');
    if (limpia.isEmpty) return const Text('—');
    final visible = limpia.length <= 4
        ? limpia
        : '···· ${limpia.substring(limpia.length - 4)}';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(visible),
        IconButton(
          tooltip: 'Copiar tarjeta',
          icon: const Icon(Icons.copy, size: 16),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: limpia));
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Tarjeta copiada')),
            );
          },
        ),
      ],
    );
  }

  Future<void> _showCrearAgenteDialog() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _AgenteFormDialog(
        agentesExistentes: _agentes,
        carnaval: _carnaval,
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Agente creado correctamente'),
          backgroundColor: AppColors.success,
        ),
      );
      _loadAgentes();
    }
  }

  Future<void> _showEditarAgenteDialog(Map<String, dynamic> agente) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _AgenteFormDialog(
        agente: agente,
        agentesExistentes: _agentes,
        carnaval: _carnaval,
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Agente actualizado correctamente'),
          backgroundColor: AppColors.success,
        ),
      );
      _loadAgentes();
    }
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

class _AgenteFormDialog extends StatefulWidget {
  final Map<String, dynamic>? agente;
  final List<Map<String, dynamic>> agentesExistentes;
  final List<Map<String, dynamic>> carnaval;

  const _AgenteFormDialog({
    this.agente,
    required this.agentesExistentes,
    required this.carnaval,
  });

  @override
  State<_AgenteFormDialog> createState() => _AgenteFormDialogState();
}

class _AgenteFormDialogState extends State<_AgenteFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombre;
  late final TextEditingController _apellidos;
  late final TextEditingController _telefono;
  late final TextEditingController _email;
  late final TextEditingController _observaciones;
  late final TextEditingController _tarjeta;
  late bool _esSocio;
  late bool _despliega;
  int? _idCarnaval;
  bool _guardando = false;

  bool get _editando => widget.agente != null;

  @override
  void initState() {
    super.initState();
    final a = widget.agente;
    _nombre = TextEditingController(text: a?['nombre']?.toString() ?? '');
    _apellidos = TextEditingController(text: a?['apellidos']?.toString() ?? '');
    _telefono = TextEditingController(text: a?['telefono']?.toString() ?? '');
    _email = TextEditingController(text: a?['email']?.toString() ?? '');
    _observaciones =
        TextEditingController(text: a?['observaciones']?.toString() ?? '');
    _tarjeta = TextEditingController(text: a?['tarjeta']?.toString() ?? '');
    _esSocio = a?['es_socio'] == true;
    _despliega = a == null || a['despliega'] != false;
    _idCarnaval = (a?['id_agente_carnaval'] as num?)?.toInt();
  }

  @override
  void dispose() {
    _nombre.dispose();
    _apellidos.dispose();
    _telefono.dispose();
    _email.dispose();
    _observaciones.dispose();
    _tarjeta.dispose();
    super.dispose();
  }

  String _norm(String value) {
    const from = 'áéíóúüñ';
    const to = 'aeiouun';
    var out = value.toLowerCase().trim();
    for (var i = 0; i < from.length; i++) {
      out = out.replaceAll(from[i], to[i]);
    }
    return out.replaceAll(RegExp(r'\s+'), ' ');
  }

  Set<int> get _ocupados {
    final propio = (widget.agente?['id_agente_carnaval'] as num?)?.toInt();
    final ids = <int>{};
    for (final row in widget.agentesExistentes) {
      final id = (row['id_agente_carnaval'] as num?)?.toInt();
      if (id != null && id != propio) ids.add(id);
    }
    return ids;
  }

  String? get _sugerencia {
    if (_idCarnaval != null) return null;
    final nombre = _norm('${_nombre.text} ${_apellidos.text}');
    if (nombre.isEmpty) return null;
    for (final row in widget.carnaval) {
      final id = (row['id'] as num?)?.toInt();
      if (id == null || _ocupados.contains(id)) continue;
      final candidato = _norm('${row['nombre']} ${row['apellidos']}');
      if (candidato == nombre) {
        return '${row['nombre']} ${row['apellidos']}'.trim();
      }
    }
    return null;
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);
    String? vacio(TextEditingController c) {
      final t = c.text.trim();
      return t.isEmpty ? null : t;
    }

    try {
      if (_editando) {
        await AgenteService.actualizarAgente(
          id: (widget.agente!['id'] as num).toInt(),
          nombre: _nombre.text.trim(),
          apellidos: _apellidos.text.trim(),
          telefono: vacio(_telefono),
          email: vacio(_email),
          observaciones: vacio(_observaciones),
          tarjeta: vacio(_tarjeta),
          esSocio: _esSocio,
          despliega: _despliega,
          idAgenteCarnaval: _idCarnaval,
        );
      } else {
        await AgenteService.crearAgente(
          nombre: _nombre.text.trim(),
          apellidos: _apellidos.text.trim(),
          telefono: vacio(_telefono),
          email: vacio(_email),
          observaciones: vacio(_observaciones),
          tarjeta: vacio(_tarjeta),
          esSocio: _esSocio,
          despliega: _despliega,
          idAgenteCarnaval: _idCarnaval,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final opciones = widget.carnaval.where((row) {
      final id = (row['id'] as num?)?.toInt();
      return id != null && (id == _idCarnaval || !_ocupados.contains(id));
    }).toList();
    if (_idCarnaval != null &&
        !opciones.any((row) => (row['id'] as num?)?.toInt() == _idCarnaval)) {
      opciones.insert(0, {
        'id': _idCarnaval,
        'nombre': 'Agente Carnaval',
        'apellidos': '#$_idCarnaval',
      });
    }
    final sugerencia = _sugerencia;

    return AlertDialog(
      title: Row(
        children: [
          Icon(_editando ? Icons.edit : Icons.person_add, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(_editando ? 'Editar agente' : 'Nuevo agente'),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nombre,
                  decoration: const InputDecoration(
                    labelText: 'Nombre *',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _apellidos,
                  decoration: const InputDecoration(
                    labelText: 'Apellidos *',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _telefono,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _tarjeta,
                  decoration: const InputDecoration(
                    labelText: 'Tarjeta',
                    border: OutlineInputBorder(),
                    isDense: true,
                    helperText: 'Se usa para copiar el pago. Puede quedar vacía.',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _observaciones,
                  decoration: const InputDecoration(
                    labelText: 'Observaciones',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _esSocio,
                  onChanged: _guardando
                      ? null
                      : (v) => setState(() => _esSocio = v ?? false),
                  title: const Text('Socio'),
                  subtitle: const Text(
                    'Parte el neto de Inventtia y el 1% global de Carnaval.',
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _despliega,
                  onChanged: _guardando
                      ? null
                      : (v) => setState(() => _despliega = v ?? false),
                  title: const Text('Se asigna en licencias'),
                  subtitle: const Text(
                    'Aparece al elegir el agente que desplegó una tienda.',
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int?>(
                  value: _idCarnaval,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Agente de Carnaval',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Sin agente de Carnaval'),
                    ),
                    ...opciones.map((row) {
                      final id = (row['id'] as num).toInt();
                      return DropdownMenuItem<int?>(
                        value: id,
                        child: Text('${row['nombre']} ${row['apellidos']}'.trim()),
                      );
                    }),
                  ],
                  onChanged: _guardando
                      ? null
                      : (v) => setState(() => _idCarnaval = v),
                ),
                if (sugerencia != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Hay un agente de Carnaval con el mismo nombre ($sugerencia) y no está enlazado. Elige esa ficha si es la misma persona.',
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_editando ? 'Guardar' : 'Crear'),
        ),
      ],
    );
  }
}
