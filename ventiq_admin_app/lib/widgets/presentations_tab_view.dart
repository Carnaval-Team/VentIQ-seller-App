import 'package:flutter/material.dart';
import '../models/presentation.dart';
import '../services/presentation_service.dart';

class PresentationsTabView extends StatefulWidget {
  const PresentationsTabView({Key? key}) : super(key: key);

  @override
  State<PresentationsTabView> createState() => _PresentationsTabViewState();
}

class _PresentationsTabViewState extends State<PresentationsTabView> {
  List<Presentation> presentations = [];
  List<Presentation> filteredPresentations = [];
  bool isLoading = true;
  String searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPresentations();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPresentations() async {
    setState(() => isLoading = true);
    try {
      final loadedPresentations = await PresentationService.getPresentations();
      setState(() {
        presentations = loadedPresentations;
        filteredPresentations = loadedPresentations;
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar presentaciones: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _filterPresentations(String query) {
    setState(() {
      searchQuery = query;
      if (query.isEmpty) {
        filteredPresentations = presentations;
      } else {
        filteredPresentations = presentations
            .where((presentation) =>
                presentation.denominacion.toLowerCase().contains(query.toLowerCase()) ||
                (presentation.descripcion?.toLowerCase().contains(query.toLowerCase()) ?? false) ||
                presentation.skuCodigo.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  Future<void> _showCreateEditDialog([Presentation? presentation]) async {
    final result = await showDialog<Presentation>(
      context: context,
      builder: (context) => PresentationFormDialog(presentation: presentation),
    );

    if (result != null) {
      await _loadPresentations();
    }
  }

  Future<void> _deletePresentationConfirm(Presentation presentation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Text('¿Está seguro de que desea eliminar la presentación "${presentation.denominacion}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await PresentationService.deletePresentation(presentation.id);
        await _loadPresentations();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Presentación eliminada exitosamente'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al eliminar presentación: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Header with search and add button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Buscar presentaciones...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onChanged: _filterPresentations,
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: () => _showCreateEditDialog(),
                  icon: const Icon(Icons.add),
                  label: const Text('Nueva Presentación'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredPresentations.isEmpty
                    ? _buildEmptyState()
                    : _buildPresentationsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            searchQuery.isEmpty ? Icons.inventory_2_outlined : Icons.search_off,
            size: 64,
            color: Colors.grey,
          ),
          const SizedBox(height: 16),
          Text(
            searchQuery.isEmpty 
                ? 'No hay presentaciones registradas'
                : 'No se encontraron presentaciones',
            style: const TextStyle(fontSize: 18, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Text(
            searchQuery.isEmpty
                ? 'Comience agregando una nueva presentación'
                : 'Intente con otros términos de búsqueda',
            style: const TextStyle(color: Colors.grey),
          ),
          if (searchQuery.isEmpty) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _showCreateEditDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Agregar Presentación'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPresentationsList() {
    return RefreshIndicator(
      onRefresh: _loadPresentations,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: filteredPresentations.length,
        itemBuilder: (context, index) {
          final presentation = filteredPresentations[index];
          return _buildPresentationCard(presentation);
        },
      ),
    );
  }

  Widget _buildPresentationCard(Presentation presentation) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        presentation.denominacion,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (presentation.descripcion != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          presentation.descripcion!,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        _showCreateEditDialog(presentation);
                        break;
                      case 'delete':
                        _deletePresentationConfirm(presentation);
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: ListTile(
                        leading: Icon(Icons.edit),
                        title: Text('Editar'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(Icons.delete, color: Colors.red),
                        title: Text('Eliminar', style: TextStyle(color: Colors.red)),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildInfoChip('SKU', presentation.skuCodigo),
                const SizedBox(width: 8),
                _buildInfoChip('ID', presentation.id.toString()),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Creado: ${_formatDate(presentation.createdAt)}',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}

class PresentationFormDialog extends StatefulWidget {
  final Presentation? presentation;
  final int? productId; // For creating presentation for specific product

  const PresentationFormDialog({Key? key, this.presentation, this.productId}) : super(key: key);

  @override
  State<PresentationFormDialog> createState() => _PresentationFormDialogState();
}

class _PresentationFormDialogState extends State<PresentationFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _denominacionController = TextEditingController();
  final _descripcionController = TextEditingController();
  final _skuCodigoController = TextEditingController();
  final _cantidadController = TextEditingController();
  
  bool _isLoading = false;
  bool _esBase = false;
  int? _selectedProductId;
  List<Map<String, dynamic>> _products = [];
  bool _loadingProducts = false;

  @override
  void initState() {
    super.initState();
    if (widget.presentation != null) {
      _denominacionController.text = widget.presentation!.denominacion;
      _descripcionController.text = widget.presentation!.descripcion ?? '';
      _skuCodigoController.text = widget.presentation!.skuCodigo;
    }
    
    if (widget.productId != null) {
      _selectedProductId = widget.productId;
      _cantidadController.text = '1';
    }
    
    _loadProducts();
  }

  @override
  void dispose() {
    _denominacionController.dispose();
    _descripcionController.dispose();
    _skuCodigoController.dispose();
    _cantidadController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() => _loadingProducts = true);
    try {
      // Mock products for now - replace with actual service call
      _products = [
        {'id': 1, 'denominacion': 'Producto Ejemplo 1', 'sku': 'PROD001'},
        {'id': 2, 'denominacion': 'Producto Ejemplo 2', 'sku': 'PROD002'},
      ];
    } catch (e) {
      print('Error loading products: $e');
    } finally {
      setState(() => _loadingProducts = false);
    }
  }

  Future<void> _savePresentacion() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final presentation = Presentation(
        id: widget.presentation?.id ?? 0,
        denominacion: _denominacionController.text.trim(),
        descripcion: _descripcionController.text.trim().isEmpty 
            ? null 
            : _descripcionController.text.trim(),
        skuCodigo: _skuCodigoController.text.trim(),
        createdAt: widget.presentation?.createdAt ?? DateTime.now(),
      );

      Presentation savedPresentation;
      if (widget.presentation == null) {
        savedPresentation = await PresentationService.createPresentation(presentation);
      } else {
        savedPresentation = await PresentationService.updatePresentation(presentation);
      }

      // If product is selected and quantity is provided, create product-presentation relationship
      if (_selectedProductId != null && _cantidadController.text.isNotEmpty) {
        final cantidad = double.tryParse(_cantidadController.text) ?? 1.0;
        await PresentationService.addPresentationToProduct(
          productId: _selectedProductId!,
          presentationId: savedPresentation.id,
          cantidad: cantidad,
          esBase: _esBase,
        );
      }

      if (mounted) {
        Navigator.of(context).pop(savedPresentation);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.presentation == null 
                ? 'Presentación creada exitosamente'
                : 'Presentación actualizada exitosamente'),
            backgroundColor: Colors.green,
          ),
        );
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
    return AlertDialog(
      title: Text(widget.presentation == null ? 'Nueva Presentación' : 'Editar Presentación'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Basic presentation fields
                Text(
                  'Información de Presentación',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _denominacionController,
                  decoration: const InputDecoration(
                    labelText: 'Denominación *',
                    border: OutlineInputBorder(),
                    helperText: 'Ej: Caja, Paquete, Unidad',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'La denominación es requerida';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descripcionController,
                  decoration: const InputDecoration(
                    labelText: 'Descripción',
                    border: OutlineInputBorder(),
                    helperText: 'Descripción opcional de la presentación',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _skuCodigoController,
                  decoration: const InputDecoration(
                    labelText: 'Código SKU *',
                    border: OutlineInputBorder(),
                    helperText: 'Código único de identificación',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'El código SKU es requerido';
                    }
                    return null;
                  },
                ),
                
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),
                
                // Product relationship section
                Text(
                  'Asignación a Producto (Opcional)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                
                if (widget.productId == null) ...[
                  DropdownButtonFormField<int>(
                    value: _selectedProductId,
                    decoration: const InputDecoration(
                      labelText: 'Seleccionar Producto',
                      border: OutlineInputBorder(),
                      helperText: 'Opcional: Asignar esta presentación a un producto',
                    ),
                    items: _loadingProducts 
                        ? []
                        : _products.map((product) {
                            return DropdownMenuItem<int>(
                              value: product['id'],
                              child: Text('${product['denominacion']} (${product['sku']})'),
                            );
                          }).toList(),
                    onChanged: (value) {
                      setState(() => _selectedProductId = value);
                    },
                  ),
                  const SizedBox(height: 16),
                ],
                
                if (_selectedProductId != null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _cantidadController,
                          decoration: const InputDecoration(
                            labelText: 'Cantidad Base *',
                            border: OutlineInputBorder(),
                            helperText: 'Cantidad de unidades en esta presentación',
                            suffixText: 'unidades',
                          ),
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (_selectedProductId != null) {
                              if (value == null || value.trim().isEmpty) {
                                return 'La cantidad es requerida';
                              }
                              final cantidad = double.tryParse(value);
                              if (cantidad == null || cantidad <= 0) {
                                return 'Ingrese una cantidad válida';
                              }
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: CheckboxListTile(
                          title: const Text('Presentación Base'),
                          subtitle: const Text('Marcar como presentación principal'),
                          value: _esBase,
                          onChanged: (value) {
                            setState(() => _esBase = value ?? false);
                          },
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue.shade600, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'La presentación base se usa como referencia principal para el producto. Solo puede haber una presentación base por producto.',
                            style: TextStyle(
                              color: Colors.blue.shade700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _savePresentacion,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.presentation == null ? 'Crear' : 'Actualizar'),
        ),
      ],
    );
  }
}
