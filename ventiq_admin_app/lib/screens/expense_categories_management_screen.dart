import 'package:flutter/material.dart';
import '../services/financial_service.dart';

class ExpenseCategoriesManagementScreen extends StatefulWidget {
  const ExpenseCategoriesManagementScreen({Key? key}) : super(key: key);

  @override
  State<ExpenseCategoriesManagementScreen> createState() => _ExpenseCategoriesManagementScreenState();
}

class _ExpenseCategoriesManagementScreenState extends State<ExpenseCategoriesManagementScreen> {
  final FinancialService _financialService = FinancialService();
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _subcategories = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final categories = await _financialService.getExpenseCategories();
      final subcategories = await _financialService.getExpenseSubcategories();
      setState(() {
        _categories = categories;
        _subcategories = subcategories;
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
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Categorías de Gastos'),
          backgroundColor: Colors.green[800],
          foregroundColor: Colors.white,
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Categorías'),
              Tab(text: 'Subcategorías'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _buildCategoriesTab(),
                  _buildSubcategoriesTab(),
                ],
              ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showAddDialog(),
          backgroundColor: Colors.green[800],
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildCategoriesTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _categories.length,
      itemBuilder: (context, index) {
        final category = _categories[index];
        return Card(
          child: ListTile(
            title: Text(category['denominacion'] ?? ''),
            subtitle: Text(category['descripcion'] ?? ''),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  onPressed: () => _showEditCategoryDialog(category),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _confirmDelete('categoria', category['id']),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSubcategoriesTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _subcategories.length,
      itemBuilder: (context, index) {
        final subcategory = _subcategories[index];
        final categoryName = _categories
            .firstWhere(
              (cat) => cat['id'] == subcategory['id_categoria_gasto'],
              orElse: () => {'denominacion': 'Sin categoría'},
            )['denominacion'];
        
        return Card(
          child: ListTile(
            title: Text(subcategory['denominacion'] ?? ''),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(subcategory['descripcion'] ?? ''),
                Text('Categoría: $categoryName', 
                     style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  onPressed: () => _showEditSubcategoryDialog(subcategory),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _confirmDelete('subcategoria', subcategory['id']),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAddDialog() {
    showDialog(
      context: context,
      builder: (context) => _AddCategoryDialog(
        categories: _categories,
        onSaved: _loadData,
      ),
    );
  }

  void _showEditCategoryDialog(Map<String, dynamic> category) {
    showDialog(
      context: context,
      builder: (context) => _EditCategoryDialog(
        category: category,
        onSaved: _loadData,
      ),
    );
  }

  void _showEditSubcategoryDialog(Map<String, dynamic> subcategory) {
    showDialog(
      context: context,
      builder: (context) => _EditSubcategoryDialog(
        subcategory: subcategory,
        categories: _categories,
        onSaved: _loadData,
      ),
    );
  }

  void _confirmDelete(String type, int id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Eliminar $type'),
        content: Text('¿Está seguro de eliminar esta $type?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                if (type == 'categoria') {
                  await _financialService.deleteExpenseCategory(id);
                } else {
                  await _financialService.deleteExpenseSubcategory(id);
                }
                _loadData();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$type eliminada exitosamente')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error eliminando $type: $e')),
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

class _AddCategoryDialog extends StatefulWidget {
  final List<Map<String, dynamic>> categories;
  final VoidCallback onSaved;

  const _AddCategoryDialog({
    required this.categories,
    required this.onSaved,
  });

  @override
  State<_AddCategoryDialog> createState() => _AddCategoryDialogState();
}

class _AddCategoryDialogState extends State<_AddCategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final FinancialService _financialService = FinancialService();
  bool _isCategory = true;
  int? _selectedCategoryId;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isCategory ? 'Nueva Categoría' : 'Nueva Subcategoría'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              title: const Text('Tipo'),
              subtitle: Text(_isCategory ? 'Categoría' : 'Subcategoría'),
              value: _isCategory,
              onChanged: (value) => setState(() => _isCategory = value),
            ),
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
            if (!_isCategory) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                value: _selectedCategoryId,
                decoration: const InputDecoration(labelText: 'Categoría'),
                items: widget.categories.map((cat) {
                  return DropdownMenuItem<int>(
                    value: cat['id'],
                    child: Text(cat['denominacion']),
                  );
                }).toList(),
                onChanged: (value) => setState(() => _selectedCategoryId = value),
                validator: (value) => value == null ? 'Seleccione una categoría' : null,
              ),
            ],
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
      if (_isCategory) {
        await _financialService.createExpenseCategory(
          _nameController.text,
          _descriptionController.text,
        );
      } else {
        await _financialService.createExpenseSubcategory(
          _nameController.text,
          _descriptionController.text,
          _selectedCategoryId!,
        );
      }
      Navigator.pop(context);
      widget.onSaved();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_isCategory ? 'Categoría' : 'Subcategoría'} creada exitosamente')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}

class _EditCategoryDialog extends StatefulWidget {
  final Map<String, dynamic> category;
  final VoidCallback onSaved;

  const _EditCategoryDialog({
    required this.category,
    required this.onSaved,
  });

  @override
  State<_EditCategoryDialog> createState() => _EditCategoryDialogState();
}

class _EditCategoryDialogState extends State<_EditCategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  final FinancialService _financialService = FinancialService();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category['denominacion']);
    _descriptionController = TextEditingController(text: widget.category['descripcion']);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar Categoría'),
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
      await _financialService.updateExpenseCategory(
        widget.category['id'],
        _nameController.text,
        _descriptionController.text,
      );
      Navigator.pop(context);
      widget.onSaved();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Categoría actualizada exitosamente')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}

class _EditSubcategoryDialog extends StatefulWidget {
  final Map<String, dynamic> subcategory;
  final List<Map<String, dynamic>> categories;
  final VoidCallback onSaved;

  const _EditSubcategoryDialog({
    required this.subcategory,
    required this.categories,
    required this.onSaved,
  });

  @override
  State<_EditSubcategoryDialog> createState() => _EditSubcategoryDialogState();
}

class _EditSubcategoryDialogState extends State<_EditSubcategoryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late int _selectedCategoryId;
  final FinancialService _financialService = FinancialService();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.subcategory['denominacion']);
    _descriptionController = TextEditingController(text: widget.subcategory['descripcion']);
    _selectedCategoryId = widget.subcategory['id_categoria_gasto'];
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar Subcategoría'),
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
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: _selectedCategoryId,
              decoration: const InputDecoration(labelText: 'Categoría'),
              items: widget.categories.map((cat) {
                return DropdownMenuItem<int>(
                  value: cat['id'],
                  child: Text(cat['denominacion']),
                );
              }).toList(),
              onChanged: (value) => setState(() => _selectedCategoryId = value!),
              validator: (value) => value == null ? 'Seleccione una categoría' : null,
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
      await _financialService.updateExpenseSubcategory(
        widget.subcategory['id'],
        _nameController.text,
        _descriptionController.text,
        _selectedCategoryId,
      );
      Navigator.pop(context);
      widget.onSaved();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Subcategoría actualizada exitosamente')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}
