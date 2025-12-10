import 'package:flutter/material.dart';
import '../services/carnaval_service.dart';
import '../config/app_colors.dart';

class ProductSyncSheet extends StatefulWidget {
  final int storeId;
  final int carnavalStoreId;

  const ProductSyncSheet({
    Key? key,
    required this.storeId,
    required this.carnavalStoreId,
  }) : super(key: key);

  @override
  State<ProductSyncSheet> createState() => _ProductSyncSheetState();
}

class _ProductSyncSheetState extends State<ProductSyncSheet> {
  bool _isLoading = true;
  bool _isSyncing = false;
  List<Map<String, dynamic>> _availableProducts = [];
  List<Map<String, dynamic>> _categories = [];

  // Lista de productos pendientes por sincronizar
  // Cada item es un mapa: {'product': Map, 'category': Map, 'location': Map}
  final List<Map<String, dynamic>> _pendingProducts = [];

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
        setState(() {
          _availableProducts = products;
          _categories = categories;
        });
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

  Future<void> _addToPending() async {
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

    setState(() {
      _pendingProducts.add({
        'product': _selectedProduct,
        'category': _selectedCategory,
        'location': location,
      });

      // Remover de disponibles para evitar duplicados en la selección
      _availableProducts.removeWhere((p) => p['id'] == _selectedProduct!['id']);

      // Limpiar selección
      _selectedProduct = null;
      // Mantener categoría seleccionada por comodidad
    });
  }

  void _removeFromPending(int index) {
    setState(() {
      final item = _pendingProducts[index];
      _availableProducts.add(item['product']);
      // Reordenar disponibles por nombre si se desea, o dejar al final
      _pendingProducts.removeAt(index);
    });
  }

  Future<void> _syncAll() async {
    if (_pendingProducts.isEmpty) return;

    setState(() => _isSyncing = true);

    int successCount = 0;
    int failCount = 0;

    try {
      for (final item in _pendingProducts) {
        final success = await CarnavalService.syncProductToCarnaval(
          localProductId: item['product']['id'],
          carnavalCategoryId: item['category']['id'],
          carnavalStoreId: widget.carnavalStoreId,
          idUbicacion: item['location']['id_ubicacion'],
        );

        if (success) {
          successCount++;
        } else {
          failCount++;
        }
      }

      if (mounted) {
        Navigator.of(context).pop(true); // Retornar true para recargar

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sincronización finalizada: $successCount exitosos, $failCount fallidos',
            ),
            backgroundColor: failCount == 0 ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error general: $e'),
            backgroundColor: Colors.red,
          ),
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
    // Altura dinámica: 80% de la pantalla o ajuste al contenido
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Sincronizar Productos',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          if (_isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sección de Selección
                    if (_availableProducts.isEmpty && _pendingProducts.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32.0),
                          child: Text(
                            'No hay productos disponibles para sincronizar.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    else if (_availableProducts.isNotEmpty) ...[
                      const Text(
                        'Agregar Producto',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Selector de Producto
                      DropdownButtonFormField<Map<String, dynamic>>(
                        decoration: const InputDecoration(
                          labelText: 'Seleccionar Producto',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        value: _selectedProduct,
                        isExpanded: true,
                        items:
                            _availableProducts.map((product) {
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

                      const SizedBox(height: 12),

                      // Selector de Categoría
                      DropdownButtonFormField<Map<String, dynamic>>(
                        decoration: const InputDecoration(
                          labelText: 'Categoría en Carnaval',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        value: _selectedCategory,
                        isExpanded: true,
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
                                          width: 20,
                                          height: 20,
                                          errorBuilder:
                                              (context, error, stackTrace) =>
                                                  const Icon(
                                                    Icons.category,
                                                    size: 20,
                                                  ),
                                        ),
                                      ),
                                    Expanded(
                                      child: Text(
                                        category['name'],
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                        onChanged: (value) {
                          setState(() => _selectedCategory = value);
                        },
                      ),

                      const SizedBox(height: 16),

                      // Botón Agregar
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed:
                              (_selectedProduct != null &&
                                      _selectedCategory != null)
                                  ? _addToPending
                                  : null,
                          icon: const Icon(Icons.add_circle_outline),
                          label: const Text('Agregar a la lista'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade200,
                            foregroundColor: Colors.black87,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Lista de Pendientes
                    if (_pendingProducts.isNotEmpty) ...[
                      Row(
                        children: [
                          const Text(
                            'Lista para Sincronizar',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${_pendingProducts.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _pendingProducts.length,
                        itemBuilder: (context, index) {
                          final item = _pendingProducts[index];
                          final product = item['product'];
                          final category = item['category'];

                          final location = item['location'];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading:
                                  product['imagen'] != null
                                      ? Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                          image: DecorationImage(
                                            image: NetworkImage(
                                              product['imagen'],
                                            ),
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      )
                                      : const Icon(Icons.image_not_supported),
                              title: Text(product['denominacion']),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(category['name']),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.location_on,
                                        size: 14,
                                        color: Colors.grey,
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          '${location['almacen']} - ${location['ubicacion']}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                ),
                                onPressed: () => _removeFromPending(index),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),

          // Footer con Botón Sincronizar
          if (_pendingProducts.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    offset: const Offset(0, -4),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSyncing ? null : _syncAll,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child:
                      _isSyncing
                          ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                          : Text(
                            'Sincronizar ${_pendingProducts.length} Productos',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                ),
              ),
            ),
        ],
      ),
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
