import 'package:flutter/material.dart';
import '../services/financial_service.dart';

class CostTypesManagementScreen extends StatefulWidget {
  const CostTypesManagementScreen({Key? key}) : super(key: key);

  @override
  State<CostTypesManagementScreen> createState() => _CostTypesManagementScreenState();
}

class _CostTypesManagementScreenState extends State<CostTypesManagementScreen> {
  final FinancialService _financialService = FinancialService();
  List<Map<String, dynamic>> _costTypes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final costTypes = await _financialService.getCostTypes();
      setState(() {
        _costTypes = costTypes;
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
        title: const Text('Tipos de Costos'),
        backgroundColor: Colors.orange[800],
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _costTypes.length,
              itemBuilder: (context, index) {
                final costType = _costTypes[index];
                return Card(
                  child: ListTile(
                    title: Text(costType['denominacion'] ?? ''),
                    subtitle: Text(costType['descripcion'] ?? ''),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => _showEditDialog(costType),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _confirmDelete(costType['id']),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(),
        backgroundColor: Colors.orange[800],
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _showAddDialog() {
    showDialog(
      context: context,
      builder: (context) => _CostTypeDialog(
        onSaved: _loadData,
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> costType) {
    showDialog(
      context: context,
      builder: (context) => _CostTypeDialog(
        costType: costType,
        onSaved: _loadData,
      ),
    );
  }

  void _confirmDelete(int id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Tipo de Costo'),
        content: const Text('¿Está seguro de eliminar este tipo de costo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await _financialService.deleteCostType(id);
                _loadData();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Tipo de costo eliminado exitosamente')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error eliminando tipo de costo: $e')),
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

class _CostTypeDialog extends StatefulWidget {
  final Map<String, dynamic>? costType;
  final VoidCallback onSaved;

  const _CostTypeDialog({
    this.costType,
    required this.onSaved,
  });

  @override
  State<_CostTypeDialog> createState() => _CostTypeDialogState();
}

class _CostTypeDialogState extends State<_CostTypeDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  final FinancialService _financialService = FinancialService();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.costType?['denominacion'] ?? '');
    _descriptionController = TextEditingController(text: widget.costType?['descripcion'] ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.costType != null;
    
    return AlertDialog(
      title: Text(isEditing ? 'Editar Tipo de Costo' : 'Nuevo Tipo de Costo'),
      content: Form(
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
          ],
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
      if (widget.costType != null) {
        await _financialService.updateCostType(
          widget.costType!['id'],
          _nameController.text,
          _descriptionController.text,
        );
      } else {
        await _financialService.createCostType(
          _nameController.text,
          _descriptionController.text,
        );
      }
      Navigator.pop(context);
      widget.onSaved();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tipo de costo ${widget.costType != null ? 'actualizado' : 'creado'} exitosamente')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}
