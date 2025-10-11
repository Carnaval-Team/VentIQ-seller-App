import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../services/vendedor_service.dart';
import '../../services/user_preferences_service.dart';

/// Widget para asignar vendedor a un TPV
/// Permite crear desde trabajador existente o crear nuevo trabajador
class AsignateVendorDialog extends StatefulWidget {
  final Map<String, dynamic> tpv;
  final VoidCallback onSuccess;

  const AsignateVendorDialog({
    Key? key,
    required this.tpv,
    required this.onSuccess,
  }) : super(key: key);

  @override
  State<AsignateVendorDialog> createState() => _AsignateVendorDialogState();
}

class _AsignateVendorDialogState extends State<AsignateVendorDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isLoadingWorkers = true;
  
  // Modo: 'existing' o 'new'
  String _mode = 'existing';
  
  // Para trabajador existente
  List<Map<String, dynamic>> _trabajadoresDisponibles = [];
  Map<String, dynamic>? _selectedTrabajador;
  
  // Para nuevo trabajador
  final _nombresController = TextEditingController();
  final _apellidosController = TextEditingController();
  int? _selectedRoll;
  
  // Roles disponibles (puedes ajustar según tu sistema)
  final List<Map<String, dynamic>> _roles = [
    {'id': 1, 'nombre': 'Vendedor'},
    {'id': 2, 'nombre': 'Cajero'},
    {'id': 3, 'nombre': 'Supervisor'},
  ];

  @override
  void initState() {
    super.initState();
    _loadTrabajadoresDisponibles();
  }

  @override
  void dispose() {
    _nombresController.dispose();
    _apellidosController.dispose();
    super.dispose();
  }

  Future<void> _loadTrabajadoresDisponibles() async {
    setState(() => _isLoadingWorkers = true);
    try {
      final trabajadores = await VendedorService.getTrabajadoresDisponibles();
      setState(() {
        _trabajadoresDisponibles = trabajadores;
        _isLoadingWorkers = false;
      });
    } catch (e) {
      print('❌ Error cargando trabajadores: $e');
      setState(() => _isLoadingWorkers = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar trabajadores: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _asignarVendedor() async {
    if (!_formKey.currentState!.validate()) return;

    // Validaciones específicas por modo
    if (_mode == 'existing' && _selectedTrabajador == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debe seleccionar un trabajador'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_mode == 'new' && _selectedRoll == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debe seleccionar un rol'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userPrefs = UserPreferencesService();
      final uuid = await userPrefs.getUserId();
      final idTienda = await userPrefs.getIdTienda();

      if (uuid == null || idTienda == null) {
        throw Exception('No se pudo obtener información del usuario');
      }

      bool success = false;

      if (_mode == 'existing') {
        // Crear vendedor desde trabajador existente
        success = await VendedorService.createVendedor(
          trabajadorId: _selectedTrabajador!['id'],
          tpvId: widget.tpv['id'],
          uuid: uuid,
        );
      } else {
        // Crear trabajador y vendedor
        success = await VendedorService.createTrabajadorYVendedor(
          nombres: _nombresController.text.trim(),
          apellidos: _apellidosController.text.trim(),
          idRoll: _selectedRoll!,
          idTienda: idTienda,
          tpvId: widget.tpv['id'],
          uuid: uuid,
        );
      }

      setState(() => _isLoading = false);

      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _mode == 'existing'
                    ? 'Vendedor asignado exitosamente'
                    : 'Trabajador creado y asignado exitosamente',
              ),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop();
          widget.onSuccess();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error al asignar vendedor'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.person_add,
                    color: AppColors.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Asignar Vendedor',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'TPV: ${widget.tpv['denominacion']}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Mode Selector
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildModeButton(
                      mode: 'existing',
                      icon: Icons.person_search,
                      label: 'Trabajador Existente',
                    ),
                  ),
                  Expanded(
                    child: _buildModeButton(
                      mode: 'new',
                      icon: Icons.person_add_alt_1,
                      label: 'Nuevo Trabajador',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Content
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: _mode == 'existing'
                      ? _buildExistingWorkerForm()
                      : _buildNewWorkerForm(),
                ),
              ),
            ),

            // Actions
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isLoading ? null : _asignarVendedor,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          _mode == 'existing' ? 'Asignar' : 'Crear y Asignar',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeButton({
    required String mode,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _mode == mode;
    return InkWell(
      onTap: () => setState(() => _mode = mode),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.grey[600],
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey[600],
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExistingWorkerForm() {
    if (_isLoadingWorkers) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_trabajadoresDisponibles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_off,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No hay trabajadores disponibles',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Todos los trabajadores ya están asignados como vendedores',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => setState(() => _mode = 'new'),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Crear Nuevo Trabajador'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Seleccione un trabajador',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _trabajadoresDisponibles.length,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              color: Colors.grey[300],
            ),
            itemBuilder: (context, index) {
              final trabajador = _trabajadoresDisponibles[index];
              final isSelected = _selectedTrabajador?['id'] == trabajador['id'];
              
              return ListTile(
                onTap: () => setState(() => _selectedTrabajador = trabajador),
                leading: CircleAvatar(
                  backgroundColor: isSelected
                      ? AppColors.primary
                      : Colors.grey[300],
                  child: Icon(
                    Icons.person,
                    color: isSelected ? Colors.white : Colors.grey[600],
                  ),
                ),
                title: Text(
                  '${trabajador['nombres']} ${trabajador['apellidos']}',
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                subtitle: Text(
                  'ID: ${trabajador['id']} • Roll: ${trabajador['id_roll']}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                trailing: isSelected
                    ? Icon(
                        Icons.check_circle,
                        color: AppColors.primary,
                      )
                    : Icon(
                        Icons.radio_button_unchecked,
                        color: Colors.grey[400],
                      ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNewWorkerForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Datos del nuevo trabajador',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),

        // Nombres
        TextFormField(
          controller: _nombresController,
          decoration: InputDecoration(
            labelText: 'Nombres *',
            hintText: 'Ingrese los nombres',
            prefixIcon: const Icon(Icons.person_outline),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            filled: true,
            fillColor: Colors.grey[50],
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Los nombres son obligatorios';
            }
            if (value.trim().length < 2) {
              return 'Los nombres deben tener al menos 2 caracteres';
            }
            return null;
          },
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 16),

        // Apellidos
        TextFormField(
          controller: _apellidosController,
          decoration: InputDecoration(
            labelText: 'Apellidos *',
            hintText: 'Ingrese los apellidos',
            prefixIcon: const Icon(Icons.person_outline),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            filled: true,
            fillColor: Colors.grey[50],
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Los apellidos son obligatorios';
            }
            if (value.trim().length < 2) {
              return 'Los apellidos deben tener al menos 2 caracteres';
            }
            return null;
          },
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 16),

        // Rol
        DropdownButtonFormField<int>(
          value: _selectedRoll,
          decoration: InputDecoration(
            labelText: 'Rol *',
            hintText: 'Seleccione un rol',
            prefixIcon: const Icon(Icons.badge_outlined),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            filled: true,
            fillColor: Colors.grey[50],
          ),
          items: _roles.map((rol) {
            return DropdownMenuItem<int>(
              value: rol['id'],
              child: Text(rol['nombre']),
            );
          }).toList(),
          onChanged: (value) => setState(() => _selectedRoll = value),
          validator: (value) {
            if (value == null) {
              return 'Debe seleccionar un rol';
            }
            return null;
          },
        ),
        const SizedBox(height: 24),

        // Info box
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue[200]!),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                color: Colors.blue[700],
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'El trabajador será creado y asignado automáticamente como vendedor del TPV ${widget.tpv['denominacion']}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.blue[900],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
