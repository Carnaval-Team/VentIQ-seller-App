import 'package:flutter/material.dart';
import '../services/financial_service.dart';

class CostCentersManagementScreen extends StatefulWidget {
  const CostCentersManagementScreen({Key? key}) : super(key: key);

  @override
  State<CostCentersManagementScreen> createState() => _CostCentersManagementScreenState();
}

class _CostCentersManagementScreenState extends State<CostCentersManagementScreen> {
  final FinancialService _financialService = FinancialService();
  List<Map<String, dynamic>> _costCenters = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final costCenters = await _financialService.getCostCenters();
      setState(() {
        _costCenters = costCenters;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cargando datos: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Centros de Costo'),
        backgroundColor: Colors.purple[800],
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _costCenters.length,
              itemBuilder: (context, index) {
                final costCenter = _costCenters[index];
                final parentName = costCenter['id_padre'] != null
                    ? _costCenters
                        .firstWhere(
                          (cc) => cc['id'] == costCenter['id_padre'],
                          orElse: () => {'denominacion': 'Sin padre'},
                        )['denominacion']
                    : null;

                return Card(
                  child: ListTile(
                    title: Text(costCenter['denominacion'] ?? ''),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (costCenter['descripcion'] != null)
                          Text(costCenter['descripcion']),
                        if (costCenter['codigo'] != null)
                          Text('Código: ${costCenter['codigo']}',
                               style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                        if (parentName != null)
                          Text('Centro padre: $parentName',
                               style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => _showEditDialog(costCenter),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _confirmDelete(costCenter['id']),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(),
        backgroundColor: Colors.purple[800],
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _showAddDialog() {
    showDialog(
      context: context,
      builder: (context) => _CostCenterDialog(
        costCenters: _costCenters,
        onSaved: _loadData,
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> costCenter) {
    showDialog(
      context: context,
      builder: (context) => _CostCenterDialog(
        costCenter: costCenter,
        costCenters: _costCenters,
        onSaved: _loadData,
      ),
    );
  }

  void _confirmDelete(int id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Centro de Costo'),
        content: const Text('¿Está seguro de eliminar este centro de costo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await _financialService.deleteCostCenter(id);
                _loadData();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Centro de costo eliminado exitosamente')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error eliminando centro de costo: $e')),
                );
              }
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _CostCenterDialog extends StatefulWidget {
  final Map<String, dynamic>? costCenter;
  final List<Map<String, dynamic>> costCenters;
  final VoidCallback onSaved;

  const _CostCenterDialog({
    this.costCenter,
    required this.costCenters,
    required this.onSaved,
  });

  @override
  State<_CostCenterDialog> createState() => _CostCenterDialogState();
}

class _CostCenterDialogState extends State<_CostCenterDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _codeController;
  late final TextEditingController _skuController;
  int? _selectedParentId;
  final FinancialService _financialService = FinancialService();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.costCenter?['denominacion'] ?? '');
    _descriptionController = TextEditingController(text: widget.costCenter?['descripcion'] ?? '');
    _codeController = TextEditingController(text: widget.costCenter?['codigo'] ?? '');
    _skuController = TextEditingController(text: widget.costCenter?['sku_codigo'] ?? '');
    _selectedParentId = widget.costCenter?['id_padre'];
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.costCenter != null;
    final availableParents = widget.costCenters
        .where((cc) => cc['id'] != widget.costCenter?['id'])
        .toList();
    
    return AlertDialog(
      title: Text(isEditing ? 'Editar Centro de Costo' : 'Nuevo Centro de Costo'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nombre'),
                validator: (value) => value?.isEmpty == true ? 'Requerido' : null,
              ),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Descripción'),
                maxLines: 2,
              ),
              TextFormField(
                controller: _codeController,
                decoration: const InputDecoration(labelText: 'Código'),
              ),
              TextFormField(
                controller: _skuController,
                decoration: const InputDecoration(labelText: 'SKU Código'),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                value: _selectedParentId,
                decoration: const InputDecoration(labelText: 'Centro Padre (Opcional)'),
                items: [
                  const DropdownMenuItem<int>(
                    value: null,
                    child: Text('Sin centro padre'),
                  ),
                  ...availableParents.map((cc) {
                    return DropdownMenuItem<int>(
                      value: cc['id'],
                      child: Text(cc['denominacion']),
                    );
                  }).toList(),
                ],
                onChanged: (value) => setState(() => _selectedParentId = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: _save,
          child: const Text('Guardar'),
        ),
      ],
    );
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      if (widget.costCenter != null) {
        await _financialService.updateCostCenter(
          widget.costCenter!['id'],
          _nameController.text,
          _descriptionController.text,
          _codeController.text.isEmpty ? null : _codeController.text,
          _skuController.text.isEmpty ? null : _skuController.text,
          _selectedParentId,
        );
      } else {
        await _financialService.createCostCenter(
          _nameController.text,
          _descriptionController.text,
          _codeController.text.isEmpty ? null : _codeController.text,
          _skuController.text.isEmpty ? null : _skuController.text,
          _selectedParentId,
        );
      }
      Navigator.pop(context);
      widget.onSaved();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Centro de costo ${widget.costCenter != null ? 'actualizado' : 'creado'} exitosamente')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}
