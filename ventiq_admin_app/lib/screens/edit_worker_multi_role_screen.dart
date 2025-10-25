import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../models/worker_models.dart';
import '../services/worker_service.dart';

class EditWorkerMultiRoleScreen extends StatefulWidget {
  final WorkerData worker;
  final int storeId;
  final String userUuid;
  final List<TPVData> tpvs;
  final List<AlmacenData> almacenes;
  final VoidCallback onSaved;

  const EditWorkerMultiRoleScreen({
    super.key,
    required this.worker,
    required this.storeId,
    required this.userUuid,
    required this.tpvs,
    required this.almacenes,
    required this.onSaved,
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

  // Estado de roles
  late Set<String> _activeRoles;

  // Datos específicos por rol
  int? _vendedorTpvId;
  String? _vendedorNumeroConfirmacion;
  int? _almaceneroAlmacenId;

  bool _isLoading = false;

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

    // Inicializar roles activos
    _activeRoles = Set.from(widget.worker.rolesActivos);

    // 🐛 DEBUG: Ver qué datos llegan
    print('🔍 DEBUG - Worker Data:');
    print('  - Roles activos: ${widget.worker.rolesActivos}');
    print('  - datosEspecificos: ${widget.worker.datosEspecificos}');
    print('  - tpvId: ${widget.worker.tpvId}');
    print('  - numeroConfirmacion: ${widget.worker.numeroConfirmacion}');
    print('  - almacenId: ${widget.worker.almacenId}');
    print('  - 💰 salarioHoras: ${widget.worker.salarioHoras}'); // 💰 NUEVO DEBUG

    // Inicializar datos específicos
    _vendedorTpvId = widget.worker.tpvId;
    _vendedorNumeroConfirmacion = widget.worker.numeroConfirmacion;
    _almaceneroAlmacenId = widget.worker.almacenId;

    print('  - _vendedorTpvId inicializado: $_vendedorTpvId');
    print('  - _almaceneroAlmacenId inicializado: $_almaceneroAlmacenId');
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nombresController.dispose();
    _apellidosController.dispose();
    _uuidController.dispose();
    _salarioHorasController.dispose(); // 💰 NUEVO
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
          // 💰 NUEVO: Campo de salario por hora
          TextField(
            controller: _salarioHorasController,
            decoration: const InputDecoration(
              labelText: 'Salario por Hora',
              prefixIcon: Icon(Icons.attach_money),
              border: OutlineInputBorder(),
              hintText: '0.00',
              helperText: 'Salario en moneda local por hora trabajada',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
            'Vendedor',
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
                    } else {
                      _activeRoles.remove(roleKey);
                      // Limpiar datos específicos al desactivar
                      if (roleKey == 'vendedor') {
                        _vendedorTpvId = null;
                        _vendedorNumeroConfirmacion = null;
                      } else if (roleKey == 'almacenero') {
                        _almaceneroAlmacenId = null;
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
            'Configuración de Vendedor',
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

    if (_activeRoles.isEmpty) {
      _showError('Debes seleccionar al menos un rol');
      return;
    }

    // Validar datos específicos de vendedor
    if (_activeRoles.contains('vendedor') && _vendedorTpvId == null) {
      _showError('Debes seleccionar un TPV para el rol de vendedor');
      return;
    }

    // Validar datos específicos de almacenero
    if (_activeRoles.contains('almacenero') && _almaceneroAlmacenId == null) {
      _showError('Debes seleccionar un almacén para el rol de almacenero');
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
        salarioHoras: double.tryParse(_salarioHorasController.text) ?? 0.0, // 💰 NUEVO
      );

      // 2. Gestionar roles: agregar nuevos y eliminar desactivados
      final rolesOriginales = Set.from(widget.worker.rolesActivos);
      final rolesNuevos = _activeRoles.difference(rolesOriginales);
      final rolesEliminados = rolesOriginales.difference(_activeRoles);

      // Agregar roles nuevos
      for (final role in rolesNuevos) {
        if (role == 'usuario') continue; // Skip usuario, es automático

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
