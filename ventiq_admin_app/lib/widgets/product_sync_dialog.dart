import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/carnaval_service.dart';

class ProductSyncDialog extends StatefulWidget {
  final int storeId;
  final int carnavalStoreId;

  const ProductSyncDialog({
    Key? key,
    required this.storeId,
    required this.carnavalStoreId,
  }) : super(key: key);

  @override
  State<ProductSyncDialog> createState() => _ProductSyncDialogState();
}

class _ProductSyncDialogState extends State<ProductSyncDialog> {
  bool _isLoading = true;
  bool _isSyncing = false;
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _categories = [];
  Map<String, dynamic>? _selectedProduct;
  Map<String, dynamic>? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final products = await CarnavalService.getUnsyncedProducts(
        widget.storeId,
        widget.carnavalStoreId,
      );
      final categories = await CarnavalService.getCarnavalCategories();

      if (mounted) {
        setState(() => _products = products);
        setState(() => _categories = categories);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al cargar datos: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _syncProduct() async {
    if (_selectedProduct == null || _selectedCategory == null) return;

    // Mostrar diálogo de selección de ubicación
    final location = await showDialog<Map<String, dynamic>>(
      context: context,
      builder:
          (context) => _LocationSelectionDialog(
            storeId: widget.storeId,
            productId: _selectedProduct!['id'],
          ),
    );

    if (location == null) return; // Usuario canceló

    setState(() => _isSyncing = true);
    try {
      final success = await CarnavalService.syncProductToCarnaval(
        localProductId: _selectedProduct!['id'],
        carnavalCategoryId: _selectedCategory!['id'],
        carnavalStoreId: widget.carnavalStoreId,
        idUbicacion: location['id_ubicacion'],
      );

      if (mounted) {
        if (success) {
          Navigator.of(context).pop(true); // Return true on success
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Producto sincronizado exitosamente'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error al sincronizar producto'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sincronizar Producto'),
      content: SizedBox(
        width: double.maxFinite,
        child:
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_products.isEmpty)
                      const Text(
                        'No hay productos disponibles para sincronizar (deben tener imagen).',
                        style: TextStyle(color: Colors.grey),
                      )
                    else ...[
                      // Selector de Producto
                      DropdownButtonFormField<Map<String, dynamic>>(
                        decoration: const InputDecoration(
                          labelText: 'Seleccionar Producto',
                          border: OutlineInputBorder(),
                        ),
                        value: _selectedProduct,
                        items:
                            _products.map((product) {
                              return DropdownMenuItem(
                                value: product,
                                child: Text(
                                  product['denominacion'],
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                        onChanged: (value) {
                          setState(() => _selectedProduct = value);
                        },
                      ),
                      const SizedBox(height: 16),

                      // Vista previa de imagen
                      if (_selectedProduct != null &&
                          _selectedProduct!['imagen'] != null)
                        Center(
                          child: Container(
                            height: 100,
                            width: 100,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              image: DecorationImage(
                                image: NetworkImage(
                                  _selectedProduct!['imagen'],
                                ),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),

                      const SizedBox(height: 16),

                      // Selector de Categoría
                      DropdownButtonFormField<Map<String, dynamic>>(
                        decoration: const InputDecoration(
                          labelText: 'Categoría en Carnaval',
                          border: OutlineInputBorder(),
                        ),
                        value: _selectedCategory,
                        items:
                            _categories.map((category) {
                              return DropdownMenuItem(
                                value: category,
                                child: Row(
                                  children: [
                                    if (category['icon'] != null)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8.0,
                                        ),
                                        child: Image.network(
                                          category['icon'],
                                          width: 24,
                                          height: 24,
                                          errorBuilder:
                                              (context, error, stackTrace) =>
                                                  const Icon(
                                                    Icons.category,
                                                    size: 24,
                                                  ),
                                        ),
                                      ),
                                    Text(category['name']),
                                  ],
                                ),
                              );
                            }).toList(),
                        onChanged: (value) {
                          setState(() => _selectedCategory = value);
                        },
                      ),
                    ],
                  ],
                ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        if (_products.isNotEmpty)
          ElevatedButton(
            onPressed:
                (_selectedProduct == null ||
                        _selectedCategory == null ||
                        _isSyncing)
                    ? null
                    : _syncProduct,
            child:
                _isSyncing
                    ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Text('Sincronizar'),
          ),
      ],
    );
  }
}

// Dialog for selecting product location
class _LocationSelectionDialog extends StatefulWidget {
  final int storeId;
  final int productId;

  const _LocationSelectionDialog({
    required this.storeId,
    required this.productId,
  });

  @override
  State<_LocationSelectionDialog> createState() =>
      __LocationSelectionDialogState();
}

class __LocationSelectionDialogState extends State<_LocationSelectionDialog> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _locations = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadLocations();
  }

  Future<void> _loadLocations() async {
    try {
      final locations = await CarnavalService.getProductLocations(
        widget.storeId,
        widget.productId,
      );

      if (mounted) {
        setState(() {
          _locations = locations;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error al cargar ubicaciones: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Seleccionar Ubicación'),
      content: SizedBox(
        width: double.maxFinite,
        child:
            _isLoading
                ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: CircularProgressIndicator(),
                  ),
                )
                : _errorMessage != null
                ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
                : _locations.isEmpty
                ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text(
                      'No se encontraron ubicaciones para este producto',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
                : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _locations.length,
                  itemBuilder: (context, index) {
                    final location = _locations[index];
                    final stock = location['cantidad_existente'] ?? 0;

                    return ListTile(
                      leading: const Icon(
                        Icons.location_on,
                        color: AppColors.primary,
                      ),
                      title: Text(
                        location['almacen'] ?? 'Sin almacén',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(location['ubicacion'] ?? 'Sin ubicación'),
                          const SizedBox(height: 4),
                          Text(
                            'Stock: $stock',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      onTap: () => Navigator.of(context).pop(location),
                    );
                  },
                ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}
