import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/supplier.dart';
import '../../services/supplier_service.dart';

class AddEditSupplierScreen extends StatefulWidget {
  final Supplier? supplier;

  const AddEditSupplierScreen({super.key, this.supplier});

  @override
  State<AddEditSupplierScreen> createState() => _AddEditSupplierScreenState();
}

class _AddEditSupplierScreenState extends State<AddEditSupplierScreen> {
  final _formKey = GlobalKey<FormState>();
  final _denominacionController = TextEditingController();
  final _direccionController = TextEditingController();
  final _ubicacionController = TextEditingController();
  final _skuCodigoController = TextEditingController();
  final _leadTimeController = TextEditingController();

  bool _isLoading = false;
  bool get _isEditing => widget.supplier != null;

  @override
  void initState() {
    super.initState();
    _initializeForm();
  }

  @override
  void dispose() {
    _denominacionController.dispose();
    _direccionController.dispose();
    _ubicacionController.dispose();
    _skuCodigoController.dispose();
    _leadTimeController.dispose();
    super.dispose();
  }

  void _initializeForm() {
    if (_isEditing) {
      final supplier = widget.supplier!;
      _denominacionController.text = supplier.denominacion;
      _direccionController.text = supplier.direccion ?? '';
      _ubicacionController.text = supplier.ubicacion ?? '';
      _skuCodigoController.text = supplier.skuCodigo;
      _leadTimeController.text = supplier.leadTime?.toString() ?? '';
    }
  }

  Future<void> _saveSupplier() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final supplier = Supplier(
        id: _isEditing ? widget.supplier!.id : 0,
        denominacion: _denominacionController.text.trim(),
        direccion:
            _direccionController.text.trim().isEmpty
                ? null
                : _direccionController.text.trim(),
        ubicacion:
            _ubicacionController.text.trim().isEmpty
                ? null
                : _ubicacionController.text.trim(),
        skuCodigo: _skuCodigoController.text.trim(),
        leadTime:
            _leadTimeController.text.trim().isEmpty
                ? null
                : int.tryParse(_leadTimeController.text.trim()),
        createdAt: _isEditing ? widget.supplier!.createdAt : DateTime.now(),
      );

      Map<String, dynamic> result;
      if (_isEditing) {
        result = await SupplierService.updateSupplier(supplier);
      } else {
        result = await SupplierService.createSupplier(supplier);
      }

      if (mounted) {
        setState(() => _isLoading = false);

        if (result['success']) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message']),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop(true); // Indicar que se guardó exitosamente
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message']),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar proveedor: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar Proveedor' : 'Nuevo Proveedor'),
        actions: [
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _saveSupplier,
              child: Text(
                _isEditing ? 'Guardar' : 'Crear',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Información básica
              _buildSectionHeader('Información Básica', Icons.business),
              const SizedBox(height: 16),

              _buildTextField(
                controller: _denominacionController,
                label: 'Nombre del Proveedor',
                hint: 'Ej: Distribuidora ABC S.A.',
                icon: Icons.business,
                isRequired: true,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'El nombre del proveedor es obligatorio';
                  }
                  if (value.trim().length < 2) {
                    return 'El nombre debe tener al menos 2 caracteres';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              _buildTextField(
                controller: _skuCodigoController,
                label: 'Código SKU',
                hint: 'Ej: PROV001',
                icon: Icons.qr_code,
                isRequired: true,
                textCapitalization: TextCapitalization.characters,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'El código SKU es obligatorio';
                  }
                  if (value.trim().length < 3) {
                    return 'El código SKU debe tener al menos 3 caracteres';
                  }
                  // Validar que solo contenga letras, números y guiones
                  if (!RegExp(r'^[A-Z0-9_-]+$').hasMatch(value.trim())) {
                    return 'Solo se permiten letras, números, guiones y guiones bajos';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 24),

              // Información de contacto
              _buildSectionHeader('Información de Contacto', Icons.location_on),
              const SizedBox(height: 16),

              _buildTextField(
                controller: _direccionController,
                label: 'Dirección',
                hint: 'Ej: Calle 123, Edificio ABC',
                icon: Icons.home,
                maxLines: 2,
              ),

              const SizedBox(height: 16),

              _buildTextField(
                controller: _ubicacionController,
                label: 'Ciudad/Ubicación',
                hint: 'Ej: La Habana, Cuba',
                icon: Icons.location_city,
              ),

              const SizedBox(height: 24),

              // Información operativa
              _buildSectionHeader('Información Operativa', Icons.settings),
              const SizedBox(height: 16),

              _buildTextField(
                controller: _leadTimeController,
                label: 'Tiempo de Entrega (días)',
                hint: 'Ej: 7',
                icon: Icons.schedule,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (value) {
                  if (value != null && value.trim().isNotEmpty) {
                    final leadTime = int.tryParse(value.trim());
                    if (leadTime == null || leadTime <= 0) {
                      return 'Debe ser un número mayor a 0';
                    }
                    if (leadTime > 365) {
                      return 'El tiempo de entrega no puede ser mayor a 365 días';
                    }
                  }
                  return null;
                },
              ),

              const SizedBox(height: 32),

              // Información adicional
              if (_isEditing) ...[_buildInfoCard(), const SizedBox(height: 32)],

              // Botones de acción
              _buildActionButtons(),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 24, color: Colors.blue.shade700),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.blue.shade700,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    IconData? icon,
    bool isRequired = false,
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label + (isRequired ? ' *' : ''),
        hintText: hint,
        prefixIcon: icon != null ? Icon(icon) : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      validator: validator,
    );
  }

  Widget _buildInfoCard() {
    final supplier = widget.supplier!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Información del Registro',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 12),

            _buildInfoRow('ID', supplier.id.toString()),
            _buildInfoRow('Creado', _formatDate(supplier.createdAt)),

            if (supplier.hasMetrics) ...[
              const Divider(height: 24),
              Text(
                'Métricas',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              _buildInfoRow(
                'Total de Órdenes',
                supplier.totalOrders.toString(),
              ),
              _buildInfoRow(
                'Valor Promedio',
                '\$${supplier.averageOrderValue?.toStringAsFixed(2) ?? '0.00'}',
              ),
              _buildInfoRow('Performance', supplier.performanceLevel),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton(
            onPressed: _isLoading ? null : _saveSupplier,
            child:
                _isLoading
                    ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : Text(_isEditing ? 'Guardar Cambios' : 'Crear Proveedor'),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}
