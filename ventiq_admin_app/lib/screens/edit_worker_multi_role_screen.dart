import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../models/worker_models.dart';
import '../models/cocina.dart';
import '../services/worker_service.dart';
import '../services/cocina_service.dart';

class EditWorkerMultiRoleScreen extends StatefulWidget {
  final WorkerData worker;
  final int storeId;
  final String userUuid;
  final List<TPVData> tpvs;
  final List<AlmacenData> almacenes;
  final VoidCallback onSaved;
  final bool canDelete;
  final VoidCallback? onDeleted;

  const EditWorkerMultiRoleScreen({
    super.key,
    required this.worker,
    required this.storeId,
    required this.userUuid,
    required this.tpvs,
    required this.almacenes,
    required this.onSaved,
    this.canDelete = false,
    this.onDeleted,
  });

  @override
  State<EditWorkerMultiRoleScreen> createState() =>
      _EditWorkerMultiRoleScreenState();
}

class _EditWorkerMultiRoleScreenState extends State<EditWorkerMultiRoleScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Controladores de texto
  late TextEditingController _nombresController;
  late TextEditingController _apellidosController;
  late TextEditingController _uuidController;
  late TextEditingController _salarioHorasController; // 💰 NUEVO
  late TextEditingController _salarioDiaController; // 💰 NUEVO
  // Modalidad de pago. Ambas tarifas se conservan al alternarla.
  late TipoSalario _tipoSalario; // 💰 NUEVO

  // Estado de roles
  late Set<String> _activeRoles;

  // Datos específicos por rol
  int? _vendedorTpvId;
  String? _vendedorNumeroConfirmacion;
  int? _almaceneroAlmacenId;
  // Cocina (jefe de cocina / cocinero)
  int? _cocinaId;
  bool _esJefeCocina = true;
  List<Cocina> _cocinas = const [];
  bool _cargandoCocinas = false;
  int? _cocinaAsignadaAlCargar;

  bool _isLoading = false;

  // Control de inventario
  bool _manejaAperturaControl = true; // Default to true (safe behavior)

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Inicializar controladores
    _nombresController = TextEditingController(text: widget.worker.nombres);
    _apellidosController = TextEditingController(text: widget.worker.apellidos);
    _uuidController = TextEditingController(
      text: widget.worker.usuarioUuid ?? '',
    );
    _salarioHorasController = TextEditingController(
      text: widget.worker.salarioHoras.toStringAsFixed(2), // 💰 NUEVO
    );
    _salarioDiaController = TextEditingController(
      text: widget.worker.salarioDia.toStringAsFixed(2), // 💰 NUEVO
    );
    _tipoSalario = widget.worker.tipoSalario; // 💰 NUEVO

    // Inicializar roles activos
    _activeRoles = Set.from(widget.worker.rolesActivos);

    // 🐛 DEBUG: Ver qué datos llegan
    print('🔍 DEBUG - Worker Data:');
    print('  - Roles activos: ${widget.worker.rolesActivos}');
    print('  - datosEspecificos: ${widget.worker.datosEspecificos}');
    print('  - tpvId: ${widget.worker.tpvId}');
    print('  - numeroConfirmacion: ${widget.worker.numeroConfirmacion}');
    print('  - almacenId: ${widget.worker.almacenId}');
    print(
      '  - 💰 salarioHoras: ${widget.worker.salarioHoras}',
    ); // 💰 NUEVO DEBUG

    // Inicializar datos específicos
    _vendedorTpvId = widget.worker.tpvId;
    _vendedorNumeroConfirmacion = widget.worker.numeroConfirmacion;
    _almaceneroAlmacenId = widget.worker.almacenId;

    // Inicializar maneja_apertura_control
    _manejaAperturaControl = widget.worker.manejaAperturaControl ?? true;

    print('  - _vendedorTpvId inicializado: $_vendedorTpvId');
    print('  - _almaceneroAlmacenId inicializado: $_almaceneroAlmacenId');
    print('  - 📋 manejaAperturaControl: $_manejaAperturaControl');

    _cargarCocinas();

  }

  /// Carga las cocinas de la tienda y, si el trabajador ya esta asignado a
  /// alguna, la preselecciona con su grado (jefe o cocinero).
  ///
  /// El rol de cocina NO viene en `worker.rolesActivos` (ese getter se arma con
  /// los 6 roles historicos), asi que se deduce de la tabla: si tiene fila en
  /// app_dat_jefe_cocina, el checkbox aparece marcado.
  Future<void> _cargarCocinas() async {
    setState(() => _cargandoCocinas = true);
    try {
      final cocinas = await CocinaService.listarCocinas();

      List<Map<String, dynamic>> asignadas = const [];
      final uuid = widget.worker.usuarioUuid;
      if (uuid != null && uuid.isNotEmpty) {
        asignadas = await CocinaService.cocinasDeTrabajador(uuid);
      }

      if (!mounted) return;
      setState(() {
        _cocinas = cocinas;
        if (asignadas.isNotEmpty) {
          final a = asignadas.first;
          _cocinaId = (a['id_cocina'] as num?)?.toInt();
          _cocinaAsignadaAlCargar = _cocinaId;
          _esJefeCocina = a['es_jefe'] == true;
          _activeRoles.add(_esJefeCocina ? 'jefe_cocina' : 'cocinero');
        }
      });
    } catch (e) {
      print('⚠️ No se pudieron cargar las cocinas: $e');
    } finally {
      if (mounted) setState(() => _cargandoCocinas = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nombresController.dispose();
    _apellidosController.dispose();
    _uuidController.dispose();
    _salarioHorasController.dispose(); // 💰 NUEVO
    _salarioDiaController.dispose(); // 💰 NUEVO
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Editar: ${widget.worker.nombreCompleto}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (widget.canDelete)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white),
              tooltip: 'Eliminar trabajador',
              onPressed: _isLoading ? null : _confirmDeleteWorker,
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Información Básica', icon: Icon(Icons.person, size: 18)),
            Tab(
              text: 'Roles y Permisos',
              icon: Icon(Icons.admin_panel_settings, size: 18),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildBasicInfoTab(), _buildRolesTab()],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildBasicInfoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Datos Personales',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nombresController,
            decoration: const InputDecoration(
              labelText: 'Nombres *',
              prefixIcon: Icon(Icons.person),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _apellidosController,
            decoration: const InputDecoration(
              labelText: 'Apellidos *',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          // 💰 NUEVO: Modalidad de pago (por hora o por día)
          SegmentedButton<TipoSalario>(
            segments: const [
              ButtonSegment(
                value: TipoSalario.hora,
                label: Text('Por hora'),
                icon: Icon(Icons.schedule, size: 18),
              ),
              ButtonSegment(
                value: TipoSalario.dia,
                label: Text('Por día'),
                icon: Icon(Icons.today, size: 18),
              ),
            ],
            selected: {_tipoSalario},
            onSelectionChanged: (sel) =>
                setState(() => _tipoSalario = sel.first),
          ),
          const SizedBox(height: 12),
          // 💰 NUEVO: Tarifa de la modalidad activa. Solo se muestra la que
          // aplica, pero ambas se guardan para no perder la configuración.
          TextField(
            key: ValueKey('tarifa_${_tipoSalario.dbValue}'),
            controller: _tipoSalario.esPorDia
                ? _salarioDiaController
                : _salarioHorasController,
            decoration: InputDecoration(
              labelText: _tipoSalario.esPorDia
                  ? 'Salario por Día'
                  : 'Salario por Hora',
              prefixIcon: const Icon(Icons.attach_money),
              suffixText: _tipoSalario.tarifaSufijo,
              border: const OutlineInputBorder(),
              hintText: '0.00',
              helperText: _tipoSalario.esPorDia
                  ? 'Salario en moneda local por día trabajado'
                  : 'Salario en moneda local por hora trabajada',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 24),
          const Text(
            'Configuración de Turnos',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Card(
            child: SwitchListTile(
              value: _manejaAperturaControl,
              onChanged: (value) {
                setState(() {
                  _manejaAperturaControl = value;
                });
              },
              title: const Text(
                'Debe contar inventario en turnos',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                _manejaAperturaControl
                    ? 'Este trabajador DEBE contar inventario al abrir y cerrar turnos'
                    : 'Este trabajador PUEDE omitir el conteo de inventario (opcional)',
                style: TextStyle(
                  fontSize: 13,
                  color:
                      _manejaAperturaControl
                          ? Colors.green.shade700
                          : Colors.orange.shade700,
                ),
              ),
              secondary: Icon(
                _manejaAperturaControl
                    ? Icons.inventory
                    : Icons.inventory_2_outlined,
                color: _manejaAperturaControl ? Colors.green : Colors.orange,
              ),
              activeColor: Colors.green,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Cuenta de Usuario',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _uuidController,
            decoration: const InputDecoration(
              labelText: 'UUID del Usuario',
              prefixIcon: Icon(Icons.fingerprint),
              border: OutlineInputBorder(),
              hintText: 'UUID de Supabase Auth',
              helperText: 'Dejar vacío si no tiene cuenta de usuario',
            ),
            readOnly: true,
          ),
        ],
      ),
    );
  }

  Widget _buildRolesTab() {
    final hasUuid = _uuidController.text.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Roles Asignados',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Selecciona los roles que tendrá este trabajador',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
          if (!hasUuid)
            Column(
              children: [
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber, color: Colors.orange.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Este trabajador no tiene cuenta de usuario (UUID). Debe tener una cuenta antes de asignarle roles.',
                          style: TextStyle(
                            color: Colors.orange.shade900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(height: 16),
          _buildRoleCheckbox(
            'gerente',
            'Gerente',
            Icons.admin_panel_settings,
            Colors.purple,
          ),
          _buildRoleCheckbox(
            'supervisor',
            'Supervisor',
            Icons.supervisor_account,
            Colors.orange,
          ),
          _buildRoleCheckbox(
            'vendedor',
            'Dependiente',
            Icons.point_of_sale,
            AppColors.primary,
          ),
          if (_activeRoles.contains('vendedor')) _buildVendedorConfig(),
          _buildRoleCheckbox(
            'almacenero',
            'Almacenero',
            Icons.warehouse,
            Colors.green,
          ),
          if (_activeRoles.contains('almacenero')) _buildAlmaceneroConfig(),
          // Cocina. Dos roles distintos sobre la misma tabla: el jefe puede
          // producir tandas y mover inventario de su cocina; el cocinero solo
          // usa el KDS. Se ofrecen por separado para que quede explicito.
          if (_cocinas.isNotEmpty || _cargandoCocinas) ...[
            _buildRoleCheckbox(
              'jefe_cocina',
              'Jefe de Cocina',
              Icons.soup_kitchen,
              Colors.deepOrange,
            ),
            _buildRoleCheckbox(
              'cocinero',
              'Cocinero',
              Icons.outdoor_grill,
              Colors.brown,
            ),
            if (_activeRoles.contains('jefe_cocina') ||
                _activeRoles.contains('cocinero'))
              _buildCocinaConfig(),
          ],
          _buildRoleCheckbox(
            'recursos_humanos',
            'Recursos Humanos',
            Icons.people_alt,
            Colors.indigo,
          ),
        ],
      ),
    );
  }

  Widget _buildRoleCheckbox(
    String roleKey,
    String roleLabel,
    IconData icon,
    Color color,
  ) {
    final isActive = _activeRoles.contains(roleKey);
    final hasUuid = _uuidController.text.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: CheckboxListTile(
        value: isActive,
        onChanged:
            !hasUuid
                ? null
                : (value) {
                  setState(() {
                    if (value == true) {
                      _activeRoles.add(roleKey);
                      // Jefe y cocinero son grados del MISMO registro
                      // (app_dat_jefe_cocina.es_jefe): no pueden coexistir.
                      if (roleKey == 'jefe_cocina') {
                        _activeRoles.remove('cocinero');
                        _esJefeCocina = true;
                      } else if (roleKey == 'cocinero') {
                        _activeRoles.remove('jefe_cocina');
                        _esJefeCocina = false;
                      }
                    } else {
                      _activeRoles.remove(roleKey);
                      // Limpiar datos específicos al desactivar
                      if (roleKey == 'vendedor') {
                        _vendedorTpvId = null;
                        _vendedorNumeroConfirmacion = null;
                      } else if (roleKey == 'almacenero') {
                        _almaceneroAlmacenId = null;
                      } else if (roleKey == 'jefe_cocina' ||
                          roleKey == 'cocinero') {
                        _cocinaId = null;
                      }
                    }
                  });
                },
        title: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Text(
              roleLabel,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color:
                    !hasUuid
                        ? Colors.grey.shade400
                        : (isActive ? color : Colors.grey),
              ),
            ),
          ],
        ),
        activeColor: color,
        subtitle:
            !hasUuid
                ? const Text(
                  'Requiere cuenta de usuario',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                )
                : null,
      ),
    );
  }

  Widget _buildVendedorConfig() {
    return Container(
      margin: const EdgeInsets.only(left: 16, bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Configuración de Dependiente',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            value: _vendedorTpvId,
            decoration: const InputDecoration(
              labelText: 'TPV Asignado',
              prefixIcon: Icon(Icons.point_of_sale),
              border: OutlineInputBorder(),
            ),
            items:
                widget.tpvs.map((tpv) {
                  return DropdownMenuItem(
                    value: tpv.id,
                    child: Text(tpv.denominacion),
                  );
                }).toList(),
            onChanged: (value) {
              setState(() => _vendedorTpvId = value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Número de Confirmación (Opcional)',
              prefixIcon: Icon(Icons.confirmation_number),
              border: OutlineInputBorder(),
            ),
            onChanged: (value) {
              _vendedorNumeroConfirmacion = value.isEmpty ? null : value;
            },
            controller: TextEditingController(
              text: _vendedorNumeroConfirmacion ?? '',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlmaceneroConfig() {
    return Container(
      margin: const EdgeInsets.only(left: 16, bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Configuración de Almacenero',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            value: _almaceneroAlmacenId,
            decoration: const InputDecoration(
              labelText: 'Almacén Asignado',
              prefixIcon: Icon(Icons.warehouse),
              border: OutlineInputBorder(),
            ),
            items:
                widget.almacenes.map((almacen) {
                  return DropdownMenuItem(
                    value: almacen.id,
                    child: Text(almacen.denominacion),
                  );
                }).toList(),
            onChanged: (value) {
              setState(() => _almaceneroAlmacenId = value);
            },
          ),
        ],
      ),
    );
  }

  /// Selector de cocina para los roles de cocina.
  ///
  /// El ámbito del rol es la COCINA, no el almacén: aunque cada cocina tenga su
  /// almacén detrás, el jefe se asigna a la estación y el backend deriva el
  /// almacén. Así un chef que cubre dos estaciones no necesita dos almaceneros.
  Widget _buildCocinaConfig() {
    final esJefe = _activeRoles.contains('jefe_cocina');
    final color = esJefe ? Colors.deepOrange : Colors.brown;

    return Container(
      margin: const EdgeInsets.only(left: 16, bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            esJefe ? 'Configuración de Jefe de Cocina' : 'Configuración de Cocinero',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 12),
          if (_cargandoCocinas)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(minHeight: 2),
            )
          else
            DropdownButtonFormField<int>(
              value: _cocinaId,
              decoration: const InputDecoration(
                labelText: 'Cocina Asignada',
                prefixIcon: Icon(Icons.soup_kitchen),
                border: OutlineInputBorder(),
              ),
              items: _cocinas.map((cocina) {
                return DropdownMenuItem(
                  value: cocina.id,
                  child: Text(
                    cocina.activa
                        ? cocina.denominacion
                        : '${cocina.denominacion} (inactiva)',
                  ),
                );
              }).toList(),
              onChanged: (value) {
                setState(() => _cocinaId = value);
              },
            ),
          const SizedBox(height: 10),
          Text(
            esJefe
                ? 'Verá el KDS de esta cocina y podrá producir, cerrar y anular '
                    'tandas, además de operar el inventario de su almacén.'
                : 'Verá el KDS de esta cocina y podrá marcar platos. No podrá '
                    'producir tandas ni mover inventario.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _saveChanges,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child:
                  _isLoading
                      ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                      : const Text(
                        'Guardar Cambios',
                        style: TextStyle(color: Colors.white),
                      ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteWorker() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Trabajador'),
        content: Text(
          '¿Estás seguro de que deseas eliminar a ${widget.worker.nombreCompleto}?\n\n'
          'Se eliminarán todos sus roles en el sistema (gerente, supervisor, '
          'dependiente, almacenero, recursos humanos, auditor).\n\n'
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isLoading = true);
    try {
      final success = await WorkerService.deleteWorker(
        widget.worker.trabajadorId,
        widget.storeId,
      );
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Trabajador eliminado exitosamente'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onDeleted?.call();
        widget.onSaved();
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        _showError('Error al eliminar trabajador: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveChanges() async {
    // Validaciones
    if (_nombresController.text.trim().isEmpty ||
        _apellidosController.text.trim().isEmpty) {
      _showError('Por favor, completa los campos obligatorios');
      return;
    }

    // 🆕 NUEVO: Validar que tenga UUID si tiene roles
    if (_activeRoles.isNotEmpty && _uuidController.text.trim().isEmpty) {
      _showError(
        'El trabajador debe tener una cuenta de usuario (UUID) antes de asignarle roles',
      );
      return;
    }

    // ✅ CORREGIDO: Permitir guardar sin roles si no tiene UUID
    // Solo validar roles si tiene UUID
    if (_uuidController.text.trim().isNotEmpty && _activeRoles.isEmpty) {
      _showError(
        'Si el trabajador tiene cuenta de usuario, debe tener al menos un rol',
      );
      return;
    }

    // Validar datos específicos de vendedor
    if (_activeRoles.contains('vendedor') && _vendedorTpvId == null) {
      _showError('Debes seleccionar un TPV para el rol de dependiente');
      return;
    }

    // Validar datos específicos de almacenero
    if (_activeRoles.contains('almacenero') && _almaceneroAlmacenId == null) {
      _showError('Debes seleccionar un almacén para el rol de almacenero');
      return;
    }

    // Validar datos específicos de cocina. El backend tambien lo exige
    // ("El rol de cocina requiere una cocina asignada"), pero validarlo aqui
    // evita el viaje y da un mensaje en el contexto del formulario.
    final tieneRolCocina = _activeRoles.contains('jefe_cocina') ||
        _activeRoles.contains('cocinero');
    if (tieneRolCocina && _cocinaId == null) {
      _showError('Debes seleccionar una cocina para el rol de cocina');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Actualizar información básica
      await WorkerService.editWorker(
        workerId: widget.worker.trabajadorId,
        storeId: widget.storeId,
        nombres: _nombresController.text.trim(),
        apellidos: _apellidosController.text.trim(),
        tipoRol: widget.worker.tipoRol, // Mantener el rol principal
        usuarioUuid: _uuidController.text.isEmpty ? null : _uuidController.text,
        salarioHoras:
            double.tryParse(_salarioHorasController.text) ?? 0.0, // 💰 NUEVO
        salarioDia:
            double.tryParse(_salarioDiaController.text) ?? 0.0, // 💰 NUEVO
        tipoSalario: _tipoSalario, // 💰 NUEVO
        manejaAperturaControl:
            _manejaAperturaControl, // 📋 NUEVO: Control de inventario
      );

      // 2. Gestionar roles: agregar nuevos y eliminar desactivados
      final rolesOriginales = Set.from(widget.worker.rolesActivos);
      final rolesNuevos = _activeRoles.difference(rolesOriginales);
      final rolesEliminados = rolesOriginales.difference(_activeRoles);

      // Agregar roles nuevos
      for (final role in rolesNuevos) {
        if (role == 'usuario') continue; // Skip usuario, es automático
        // Los roles de cocina se gestionan en 2.b: necesitan p_id_cocina, que
        // este bucle generico no pasa. Sin este skip, addWorkerRole llegaria al
        // backend sin cocina y devolveria "El rol de cocina requiere una cocina
        // asignada", abortando el guardado completo del trabajador.
        if (role == 'jefe_cocina' || role == 'cocinero') continue;

        await WorkerService.addWorkerRole(
          trabajadorId: widget.worker.trabajadorId,
          storeId: widget.storeId,
          tipoRol: role,
          usuarioUuid:
              _uuidController.text.isEmpty
                  ? widget.userUuid
                  : _uuidController.text,
          tpvId: role == 'vendedor' ? _vendedorTpvId : null,
          almacenId: role == 'almacenero' ? _almaceneroAlmacenId : null,
          numeroConfirmacion:
              role == 'vendedor' ? _vendedorNumeroConfirmacion : null,
        );
      }

      // Eliminar roles desactivados
      for (final role in rolesEliminados) {
        if (role == 'usuario') continue; // Skip usuario

        await WorkerService.removeWorkerRole(
          trabajadorId: widget.worker.trabajadorId,
          tipoRol: role,
        );
      }

      // 2.b Roles de cocina.
      //
      // Van aparte del bucle de arriba a proposito: `rolesActivos` se
      // construye con los 6 roles historicos (usuario, gerente, supervisor,
      // vendedor, almacenero, recursos_humanos) y nunca contiene cocina, asi
      // que la diferencia de conjuntos no los ve. Se resuelve contra el estado
      // real de la tabla, que es lo que se cargo en _cargarCocinas().
      final uuidCocina = _uuidController.text.isEmpty
          ? widget.userUuid
          : _uuidController.text;

      if (tieneRolCocina && _cocinaId != null) {
        // Idempotente en el backend: si ya estaba, actualiza el grado.
        await WorkerService.addWorkerRole(
          trabajadorId: widget.worker.trabajadorId,
          storeId: widget.storeId,
          tipoRol: _activeRoles.contains('jefe_cocina')
              ? 'jefe_cocina'
              : 'cocinero',
          usuarioUuid: uuidCocina,
          idCocina: _cocinaId,
          esJefeCocina: _activeRoles.contains('jefe_cocina'),
        );
      } else if (_cocinaAsignadaAlCargar != null) {
        // Tenia rol de cocina y se desmarco: quitarlo.
        await WorkerService.removeWorkerRole(
          trabajadorId: widget.worker.trabajadorId,
          tipoRol: 'jefe_cocina',
        );
      }

      // 3. Actualizar datos específicos de roles existentes
      if (_activeRoles.contains('vendedor') &&
          rolesOriginales.contains('vendedor')) {
        await WorkerService.updateRoleSpecificData(
          trabajadorId: widget.worker.trabajadorId,
          tipoRol: 'vendedor',
          tpvId: _vendedorTpvId,
          numeroConfirmacion: _vendedorNumeroConfirmacion,
        );
      }

      if (_activeRoles.contains('almacenero') &&
          rolesOriginales.contains('almacenero')) {
        await WorkerService.updateRoleSpecificData(
          trabajadorId: widget.worker.trabajadorId,
          tipoRol: 'almacenero',
          almacenId: _almaceneroAlmacenId,
        );
      }

      setState(() => _isLoading = false);

      // Mostrar éxito y cerrar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Trabajador actualizado exitosamente'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onSaved();
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Error al guardar cambios: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }
}
