import 'package:flutter/material.dart';
import '../../models/supplier.dart';
import '../../services/supplier_service.dart';

class SupplierSelector extends StatefulWidget {
  final Supplier? selectedSupplier;
  final Function(Supplier?) onSupplierSelected;
  final bool isRequired;
  final String? hintText;
  final bool enabled;
  final bool showCreateButton;
  final VoidCallback? onCreateNew;
  
  const SupplierSelector({
    super.key,
    this.selectedSupplier,
    required this.onSupplierSelected,
    this.isRequired = false,
    this.hintText,
    this.enabled = true,
    this.showCreateButton = true,
    this.onCreateNew,
  });
  
  @override
  State<SupplierSelector> createState() => _SupplierSelectorState();
}

class _SupplierSelectorState extends State<SupplierSelector> {
  List<Supplier> _suppliers = [];
  List<Supplier> _filteredSuppliers = [];
  bool _isLoading = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
  
  Future<void> _loadSuppliers() async {
    if (!mounted) return;
    
    setState(() => _isLoading = true);
    try {
      final suppliers = await SupplierService.getAllSuppliers();
      if (mounted) {
        setState(() {
          _suppliers = suppliers;
          _filteredSuppliers = suppliers;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar proveedores: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  void _filterSuppliers(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredSuppliers = _suppliers;
      } else {
        _filteredSuppliers = _suppliers.where((supplier) {
          return supplier.denominacion.toLowerCase().contains(query.toLowerCase()) ||
                 supplier.skuCodigo.toLowerCase().contains(query.toLowerCase()) ||
                 (supplier.ubicacion?.toLowerCase().contains(query.toLowerCase()) ?? false);
        }).toList();
      }
    });
  }
  
  void _showSupplierDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  const Expanded(
                    child: Text('Seleccionar Proveedor'),
                  ),
                  if (widget.showCreateButton)
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onCreateNew?.call();
                      },
                      tooltip: 'Crear nuevo proveedor',
                    ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: Column(
                  children: [
                    // Barra de búsqueda
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Buscar proveedor...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      onChanged: (value) {
                        _filterSuppliers(value);
                        setDialogState(() {});
                      },
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Lista de proveedores
                    Expanded(
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : _filteredSuppliers.isEmpty
                              ? _buildEmptyState()
                              : ListView.builder(
                                  itemCount: _filteredSuppliers.length,
                                  itemBuilder: (context, index) {
                                    final supplier = _filteredSuppliers[index];
                                    final isSelected = widget.selectedSupplier?.id == supplier.id;
                                    
                                    return Card(
                                      color: isSelected ? Colors.blue.shade50 : null,
                                      child: ListTile(
                                        leading: CircleAvatar(
                                          backgroundColor: Colors.blue.shade100,
                                          child: Text(
                                            supplier.denominacion.substring(0, 1).toUpperCase(),
                                            style: TextStyle(
                                              color: Colors.blue.shade700,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        title: Text(
                                          supplier.denominacion,
                                          style: TextStyle(
                                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                          ),
                                        ),
                                        subtitle: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('SKU: ${supplier.skuCodigo}'),
                                            if (supplier.ubicacion != null)
                                              Text(
                                                supplier.ubicacion!,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                          ],
                                        ),
                                        trailing: isSelected
                                            ? Icon(
                                                Icons.check_circle,
                                                color: Colors.blue.shade700,
                                              )
                                            : null,
                                        onTap: () {
                                          widget.onSupplierSelected(supplier);
                                          Navigator.of(context).pop();
                                        },
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                if (widget.selectedSupplier != null)
                  TextButton(
                    onPressed: () {
                      widget.onSupplierSelected(null);
                      Navigator.of(context).pop();
                    },
                    child: const Text('Limpiar selección'),
                  ),
              ],
            );
          },
        );
      },
    );
  }
  
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.business,
            size: 48,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isEmpty 
                ? 'No hay proveedores registrados'
                : 'No se encontraron proveedores',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          if (_searchQuery.isEmpty && widget.showCreateButton) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onCreateNew?.call();
              },
              icon: const Icon(Icons.add),
              label: const Text('Crear primer proveedor'),
            ),
          ],
        ],
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label
        Row(
          children: [
            const Text(
              'Proveedor',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (widget.isRequired)
              const Text(
                ' *',
                style: TextStyle(color: Colors.red),
              ),
          ],
        ),
        const SizedBox(height: 8),
        
        // Selector
        InkWell(
          onTap: widget.enabled ? _showSupplierDialog : null,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            decoration: BoxDecoration(
              border: Border.all(
                color: widget.enabled ? Colors.grey.shade400 : Colors.grey.shade300,
              ),
              borderRadius: BorderRadius.circular(8),
              color: widget.enabled ? Colors.white : Colors.grey.shade100,
            ),
            child: Row(
              children: [
                Expanded(
                  child: widget.selectedSupplier != null
                      ? _buildSelectedSupplierInfo()
                      : Text(
                          widget.hintText ?? 'Seleccionar proveedor',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 16,
                          ),
                        ),
                ),
                Icon(
                  Icons.arrow_drop_down,
                  color: widget.enabled ? Colors.grey[600] : Colors.grey[400],
                ),
              ],
            ),
          ),
        ),
        
        // Error message placeholder (para validación)
        if (widget.isRequired && widget.selectedSupplier == null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Seleccione un proveedor',
              style: TextStyle(
                color: Colors.red[700],
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }
  
  Widget _buildSelectedSupplierInfo() {
    final supplier = widget.selectedSupplier!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          supplier.denominacion,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Text(
              'SKU: ${supplier.skuCodigo}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            if (supplier.leadTime != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  supplier.leadTimeDisplay,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.orange.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
