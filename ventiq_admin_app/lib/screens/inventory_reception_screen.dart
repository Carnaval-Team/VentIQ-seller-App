import 'package:flutter/material.dart';
// import 'dart:convert';
// import 'dart:io';
import '../config/app_colors.dart';
import '../models/product.dart';
import '../services/product_service.dart';
import '../services/inventory_service.dart';
import '../services/user_preferences_service.dart';

class InventoryReceptionScreen extends StatefulWidget {
  const InventoryReceptionScreen({super.key});

  @override
  State<InventoryReceptionScreen> createState() =>
      _InventoryReceptionScreenState();
}

class _InventoryReceptionScreenState extends State<InventoryReceptionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _entregadoPorController = TextEditingController();
  final _recibidoPorController = TextEditingController();
  final _observacionesController = TextEditingController();
  final _montoTotalController = TextEditingController();
  final _searchController = TextEditingController();

  List<Product> _availableProducts = [];
  List<Product> _filteredProducts = [];
  List<Map<String, dynamic>> _selectedProducts = [];
  List<Map<String, dynamic>> _motivoOptions = [];
  Map<String, dynamic>? _selectedMotivo;
  bool _isLoading = false;
  bool _isLoadingProducts = true;
  bool _isLoadingMotivos = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _loadMotivoOptions();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _entregadoPorController.dispose();
    _recibidoPorController.dispose();
    _observacionesController.dispose();
    _montoTotalController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
      _filterProducts();
    });
  }

  void _filterProducts() {
    if (_searchQuery.isEmpty) {
      _filteredProducts = List.from(_availableProducts);
    } else {
      _filteredProducts =
          _availableProducts.where((product) {
            return product.name.toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                ) ||
                product.sku.toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                ) ||
                product.brand.toLowerCase().contains(
                  _searchQuery.toLowerCase(),
                );
          }).toList();
    }
  }

  Future<void> _loadMotivoOptions() async {
    try {
      setState(() => _isLoadingMotivos = true);
      final motivos = await InventoryService.getMotivoRecepcionOptions();
      setState(() {
        _motivoOptions = motivos;
        if (motivos.isNotEmpty) {
          _selectedMotivo = motivos.first;
        }
        _isLoadingMotivos = false;
      });
    } catch (e) {
      setState(() => _isLoadingMotivos = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al cargar motivos: $e')));
      }
    }
  }

  Future<void> _loadProducts() async {
    try {
      setState(() => _isLoadingProducts = true);
      final products = await ProductService.getProductsByTienda();
      setState(() {
        _availableProducts = products;
        _filteredProducts = products;
        _isLoadingProducts = false;
      });
    } catch (e) {
      setState(() => _isLoadingProducts = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar productos: $e')),
        );
      }
    }
  }

  void _addProductToReception(Product product) {
    showDialog(
      context: context,
      builder:
          (context) => _ProductQuantityDialog(
            product: product,
            onAdd: (productData) {
              setState(() {
                _selectedProducts.add(productData);
              });
              Navigator.pop(context);
            },
          ),
    );
  }

  void _removeProduct(int index) {
    setState(() {
      _selectedProducts.removeAt(index);
    });
  }

  double get _totalAmount {
    return _selectedProducts.fold(0.0, (sum, item) {
      final cantidad = item['cantidad'] as double;
      final precio = item['precio_unitario'] as double? ?? 0.0;
      return sum + (cantidad * precio);
    });
  }

  Future<void> _submitReception() async {
    if (!_formKey.currentState!.validate() || _selectedProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Complete todos los campos y agregue al menos un producto',
          ),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();
      final userUuid = await userPrefs.getUserId();

      if (idTienda == null || userUuid == null) {
        throw Exception('No se encontró información del usuario');
      }

      final result = await InventoryService.insertInventoryReception(
        entregadoPor: _entregadoPorController.text,
        idTienda: idTienda,
        montoTotal:
            _montoTotalController.text.isNotEmpty
                ? double.parse(_montoTotalController.text)
                : _totalAmount,
        motivo: _selectedMotivo?['id']?.toString() ?? '',
        observaciones: _observacionesController.text,
        productos: _selectedProducts,
        recibidoPor: _recibidoPorController.text,
        uuid: userUuid,
      );

      if (mounted) {
        if (result['status'] == 'success') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Recepción registrada exitosamente. ID: ${result['id_operacion']}',
              ),
              backgroundColor: AppColors.success,
            ),
          );
          Navigator.pop(context);
        } else {
          throw Exception(result['message'] ?? 'Error desconocido');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al registrar recepción: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Recepción de Inventario',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildReceptionInfoSection(),
                    const SizedBox(height: 24),
                    _buildProductSelectionSection(),
                    const SizedBox(height: 24),
                    _buildSelectedProductsSection(),
                  ],
                ),
              ),
            ),
            _buildBottomSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildReceptionInfoSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Información de Recepción',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _entregadoPorController,
              decoration: const InputDecoration(
                labelText: 'Entregado por',
                border: OutlineInputBorder(),
              ),
              validator:
                  (value) => value?.isEmpty == true ? 'Campo requerido' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _recibidoPorController,
              decoration: const InputDecoration(
                labelText: 'Recibido por',
                border: OutlineInputBorder(),
              ),
              validator:
                  (value) => value?.isEmpty == true ? 'Campo requerido' : null,
            ),
            const SizedBox(height: 12),
            _isLoadingMotivos
                ? const Center(child: CircularProgressIndicator())
                : DropdownButtonFormField<Map<String, dynamic>>(
                  value: _selectedMotivo,
                  decoration: const InputDecoration(
                    labelText: 'Motivo',
                    border: OutlineInputBorder(),
                  ),
                  items:
                      _motivoOptions.map((motivo) {
                        return DropdownMenuItem(
                          value: motivo,
                          child: Text(
                            motivo['denominacion'] ?? 'Sin denominación',
                          ),
                        );
                      }).toList(),
                  onChanged: (motivo) {
                    setState(() {
                      _selectedMotivo = motivo;
                    });
                  },
                  validator: (value) {
                    if (value == null) return 'Campo requerido';
                    return null;
                  },
                ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _observacionesController,
              decoration: const InputDecoration(
                labelText: 'Observaciones',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _montoTotalController,
              decoration: InputDecoration(
                labelText: 'Monto Total (Opcional)',
                hintText:
                    'Calculado automáticamente: \$${_totalAmount.toStringAsFixed(2)}',
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductSelectionSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Seleccionar Productos',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Buscar productos',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 300,
              child:
                  _isLoadingProducts
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                        itemCount: _filteredProducts.length,
                        itemBuilder: (context, index) {
                          final product = _filteredProducts[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppColors.primary.withOpacity(
                                0.1,
                              ),
                              child: Icon(
                                Icons.inventory_2,
                                color: AppColors.primary,
                              ),
                            ),
                            title: Text(product.name),
                            subtitle: Text(
                              'SKU: ${product.sku} | Marca: ${product.brand}',
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.add_circle,
                                color: AppColors.primary,
                              ),
                              onPressed: () => _addProductToReception(product),
                            ),
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedProductsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Productos Seleccionados (${_selectedProducts.length})',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (_selectedProducts.isEmpty)
              const Center(
                child: Text(
                  'No hay productos seleccionados',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _selectedProducts.length,
                itemBuilder: (context, index) {
                  final item = _selectedProducts[index];
                  return ListTile(
                    title: Text(item['nombre_producto']),
                    subtitle: Text(
                      'Cantidad: ${item['cantidad']} | Precio: \$${item['precio_unitario']?.toStringAsFixed(2) ?? '0.00'}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.remove_circle,
                        color: AppColors.error,
                      ),
                      onPressed: () => _removeProduct(index),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.3),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total:',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                '\$${_totalAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _submitReception,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child:
                  _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                        'Registrar Recepción',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductQuantityDialog extends StatefulWidget {
  final Product product;
  final Function(Map<String, dynamic>) onAdd;

  const _ProductQuantityDialog({required this.product, required this.onAdd});

  @override
  State<_ProductQuantityDialog> createState() => _ProductQuantityDialogState();
}

class _ProductQuantityDialogState extends State<_ProductQuantityDialog> {
  final _cantidadController = TextEditingController();
  final _precioController = TextEditingController();
  Map<String, dynamic>? _selectedVariant;
  Map<String, dynamic>? _selectedPresentation;
  List<Map<String, dynamic>> _availableVariants = [];
  List<Map<String, dynamic>> _availablePresentations = [];

  @override
  void initState() {
    super.initState();
    _initializeVariantsAndPresentations();
    _precioController.text = widget.product.basePrice.toString();
  }

  void _initializeVariantsAndPresentations() {
    // Extract unique variants from inventario
    final variantMap = <String, Map<String, dynamic>>{};
    final presentationMap = <String, Map<String, dynamic>>{};

    for (final inventoryItem in widget.product.inventario) {
      // Add variant if exists
      if (inventoryItem['variante'] != null) {
        final variant = inventoryItem['variante'];
        final variantKey = '${variant['id']}_${variant['opcion']?['id']}';
        if (!variantMap.containsKey(variantKey)) {
          variantMap[variantKey] = variant;
        }
      }

      // Add presentation if exists
      if (inventoryItem['presentacion'] != null) {
        final presentation = inventoryItem['presentacion'];
        final presentationKey = presentation['id'].toString();
        if (!presentationMap.containsKey(presentationKey)) {
          presentationMap[presentationKey] = presentation;
        }
      }
    }

    _availableVariants = variantMap.values.toList();
    _availablePresentations = presentationMap.values.toList();

    // Set defaults
    if (_availableVariants.isNotEmpty) {
      _selectedVariant = _availableVariants.first;
    }
    if (_availablePresentations.isNotEmpty) {
      _selectedPresentation = _availablePresentations.first;
    }
  }

  Map<String, dynamic>? _findMatchingInventoryItem() {
    // Find inventory item that matches both selected variant and presentation
    for (final inventoryItem in widget.product.inventario) {
      bool variantMatches = true;
      bool presentationMatches = true;

      // Check variant match
      if (_selectedVariant != null && inventoryItem['variante'] != null) {
        final itemVariant = inventoryItem['variante'];
        variantMatches =
            itemVariant['id'] == _selectedVariant!['id'] &&
            itemVariant['opcion']?['id'] == _selectedVariant!['opcion']?['id'];
      } else if (_selectedVariant != null ||
          inventoryItem['variante'] != null) {
        variantMatches = false;
      }

      // Check presentation match
      if (_selectedPresentation != null &&
          inventoryItem['presentacion'] != null) {
        presentationMatches =
            inventoryItem['presentacion']['id'] == _selectedPresentation!['id'];
      } else if (_selectedPresentation != null ||
          inventoryItem['presentacion'] != null) {
        presentationMatches = false;
      }

      if (variantMatches && presentationMatches) {
        return inventoryItem;
      }
    }

    // If no exact match, return first item as fallback
    return widget.product.inventario.isNotEmpty
        ? widget.product.inventario.first
        : null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Agregar ${widget.product.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Variant selection dropdown
          if (_availableVariants.length > 1)
            DropdownButtonFormField<Map<String, dynamic>>(
              value: _selectedVariant,
              decoration: const InputDecoration(
                labelText: 'Variante',
                border: OutlineInputBorder(),
              ),
              items:
                  _availableVariants.map((variant) {
                    final atributo = variant['atributo']?['label'] ?? '';
                    final opcion = variant['opcion']?['valor'] ?? '';
                    final displayText =
                        atributo.isNotEmpty && opcion.isNotEmpty
                            ? '$atributo: $opcion'
                            : 'Variante ${_availableVariants.indexOf(variant) + 1}';

                    return DropdownMenuItem(
                      value: variant,
                      child: Text(displayText),
                    );
                  }).toList(),
              onChanged: (variant) {
                setState(() {
                  _selectedVariant = variant;
                });
              },
            ),
          if (_availableVariants.length > 1) const SizedBox(height: 12),

          // Presentation selection dropdown
          if (_availablePresentations.length > 1)
            DropdownButtonFormField<Map<String, dynamic>>(
              value: _selectedPresentation,
              decoration: const InputDecoration(
                labelText: 'Presentación',
                border: OutlineInputBorder(),
              ),
              items:
                  _availablePresentations.map((presentation) {
                    final denominacion = presentation['denominacion'] ?? '';
                    final cantidad = presentation['cantidad'] ?? 1;
                    final displayText =
                        denominacion.isNotEmpty
                            ? '$denominacion (${cantidad}x)'
                            : 'Presentación ${_availablePresentations.indexOf(presentation) + 1}';

                    return DropdownMenuItem(
                      value: presentation,
                      child: Text(displayText),
                    );
                  }).toList(),
              onChanged: (presentation) {
                setState(() {
                  _selectedPresentation = presentation;
                });
              },
            ),
          if (_availablePresentations.length > 1) const SizedBox(height: 12),
          const SizedBox(height: 12),
          TextFormField(
            controller: _cantidadController,
            decoration: const InputDecoration(
              labelText: 'Cantidad',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            validator: (value) {
              if (value?.isEmpty == true) return 'Campo requerido';
              if (double.tryParse(value!) == null)
                return 'Ingrese un número válido';
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _precioController,
            decoration: const InputDecoration(
              labelText: 'Precio Unitario',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_cantidadController.text.isNotEmpty) {
              final cantidad = double.tryParse(_cantidadController.text) ?? 0;
              final precio = double.tryParse(_precioController.text) ?? 0;

              // Extract proper IDs from inventory item data
              final productData = {
                'id_producto': int.parse(widget.product.id),
                'cantidad': cantidad,
                'precio_unitario': precio,
                'sku_producto': widget.product.sku,
                'nombre_producto': widget.product.name,
              };

              // Add variant and presentation IDs from separate selections
              if (_selectedVariant != null) {
                productData['id_variante'] = _selectedVariant!['id'];
                if (_selectedVariant!['opcion'] != null) {
                  productData['id_opcion_variante'] =
                      _selectedVariant!['opcion']['id'];
                }
              }

              if (_selectedPresentation != null) {
                productData['id_presentacion'] = _selectedPresentation!['id'];
              }

              // Find matching inventory item for location info
              final matchingInventoryItem = _findMatchingInventoryItem();
              if (matchingInventoryItem != null) {
                if (matchingInventoryItem['ubicacion'] != null) {
                  productData['id_ubicacion'] =
                      matchingInventoryItem['ubicacion']['id'];
                  productData['sku_ubicacion'] =
                      matchingInventoryItem['ubicacion']['sku_codigo'];
                }
                if (matchingInventoryItem['id_inventario'] != null) {
                  productData['id_inventario'] =
                      matchingInventoryItem['id_inventario'];
                }
              }

              widget.onAdd(productData);
            }
          },
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          child: const Text('Agregar', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
