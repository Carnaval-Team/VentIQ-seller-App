import 'package:flutter/material.dart';
import '../models/supplier.dart';
import '../models/product.dart';
import '../services/supplier_service.dart';
import '../services/product_service.dart';
import '../services/user_preferences_service.dart';

class AssignSupplierScreen extends StatefulWidget {
  final int categoryId;
  final String categoryName;

  const AssignSupplierScreen({
    Key? key,
    required this.categoryId,
    required this.categoryName,
  }) : super(key: key);

  @override
  State<AssignSupplierScreen> createState() => _AssignSupplierScreenState();
}

class _AssignSupplierScreenState extends State<AssignSupplierScreen> {
  final SupplierService _supplierService = SupplierService();
  final ProductService _productService = ProductService();
  final UserPreferencesService _userPreferencesService =
      UserPreferencesService();

  List<Supplier> _suppliers = [];
  List<Product> _products = [];
  Supplier? _selectedSupplier;
  Set<int> _selectedProductIds = {};
  bool _isLoading = true;
  bool _isAssigning = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final idTienda = await _userPreferencesService.getIdTienda();
      if (idTienda == null) {
        throw Exception('No se pudo obtener el ID de la tienda');
      }

      // Cargar proveedores
      final suppliers = await _supplierService.getSuppliersByStore(idTienda);

      // Cargar todos los productos de la categoría
      final productsBySubcategory =
          await _productService.getProductsByCategory(widget.categoryId);

      // Aplanar la lista de productos
      final allProducts = <Product>[];
      productsBySubcategory.forEach((subcategory, products) {
        allProducts.addAll(products);
      });

      setState(() {
        _suppliers = suppliers;
        _products = allProducts;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error cargando datos: $e';
        _isLoading = false;
      });
    }
  }

  void _toggleProductSelection(int productId) {
    setState(() {
      if (_selectedProductIds.contains(productId)) {
        _selectedProductIds.remove(productId);
      } else {
        _selectedProductIds.add(productId);
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedProductIds.length == _products.length) {
        _selectedProductIds.clear();
      } else {
        _selectedProductIds = _products.map((p) => p.id).toSet();
      }
    });
  }

  Future<void> _assignSupplier() async {
    if (_selectedSupplier == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor selecciona un proveedor'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_selectedProductIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor selecciona al menos un producto'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      setState(() {
        _isAssigning = true;
      });

      await _supplierService.assignSupplierToProducts(
        _selectedSupplier!.id,
        _selectedProductIds.toList(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Proveedor "${_selectedSupplier!.nombre}" asignado a ${_selectedProductIds.length} producto(s)',
            ),
            backgroundColor: Colors.green,
          ),
        );

        // Regresar a la pantalla anterior
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error asignando proveedor: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAssigning = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF4A90E2),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A90E2),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Asignar Proveedor',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          if (!_isLoading)
            TextButton.icon(
              onPressed: _isAssigning ? null : _assignSupplier,
              icon: _isAssigning
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check, color: Colors.white),
              label: const Text(
                'Asignar',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF8F9FA),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF4A90E2),
                ),
              )
            : _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 80,
                          color: Colors.red,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.red,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadData,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4A90E2),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      // Dropdown de proveedores
                      Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<Supplier>(
                            isExpanded: true,
                            value: _selectedSupplier,
                            hint: const Text(
                              'Seleccionar proveedor',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                              ),
                            ),
                            icon: const Icon(
                              Icons.arrow_drop_down,
                              color: Color(0xFF4A90E2),
                            ),
                            items: _suppliers.map((supplier) {
                              return DropdownMenuItem<Supplier>(
                                value: supplier,
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.business,
                                      color: Color(0xFF4A90E2),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        supplier.nombre,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          color: Color(0xFF2C3E50),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (supplier) {
                              setState(() {
                                _selectedSupplier = supplier;
                              });
                            },
                          ),
                        ),
                      ),

                      // Botón seleccionar todos
                      if (_products.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${_selectedProductIds.length} de ${_products.length} seleccionados',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF2C3E50),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _toggleSelectAll,
                                icon: Icon(
                                  _selectedProductIds.length == _products.length
                                      ? Icons.check_box
                                      : Icons.check_box_outline_blank,
                                  color: const Color(0xFF4A90E2),
                                ),
                                label: Text(
                                  _selectedProductIds.length == _products.length
                                      ? 'Deseleccionar todos'
                                      : 'Seleccionar todos',
                                  style: const TextStyle(
                                    color: Color(0xFF4A90E2),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      const Divider(height: 1),

                      // Lista de productos
                      Expanded(
                        child: _products.isEmpty
                            ? const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.inventory_2_outlined,
                                      size: 80,
                                      color: Colors.grey,
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      'No hay productos disponibles',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: _products.length,
                                itemBuilder: (context, index) {
                                  final product = _products[index];
                                  final isSelected =
                                      _selectedProductIds.contains(product.id);

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? const Color(0xFF4A90E2)
                                              .withOpacity(0.1)
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isSelected
                                            ? const Color(0xFF4A90E2)
                                            : Colors.grey.withOpacity(0.2),
                                        width: isSelected ? 2 : 1,
                                      ),
                                    ),
                                    child: CheckboxListTile(
                                      value: isSelected,
                                      onChanged: (_) =>
                                          _toggleProductSelection(product.id),
                                      activeColor: const Color(0xFF4A90E2),
                                      title: Text(
                                        product.denominacion,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: isSelected
                                              ? FontWeight.w600
                                              : FontWeight.w500,
                                          color: const Color(0xFF2C3E50),
                                        ),
                                      ),
                                      subtitle: product.descripcion != null
                                          ? Text(
                                              product.descripcion!,
                                              style: TextStyle(
                                                fontSize: 14,
                                                color: Colors.grey[600],
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            )
                                          : null,
                                      secondary: product.foto != null
                                          ? ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: Image.network(
                                                product.foto!,
                                                width: 50,
                                                height: 50,
                                                fit: BoxFit.cover,
                                                errorBuilder:
                                                    (context, error, stack) {
                                                  return Container(
                                                    width: 50,
                                                    height: 50,
                                                    decoration: BoxDecoration(
                                                      color: Colors.grey[200],
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        8,
                                                      ),
                                                    ),
                                                    child: const Icon(
                                                      Icons.image_not_supported,
                                                      color: Colors.grey,
                                                    ),
                                                  );
                                                },
                                              ),
                                            )
                                          : Container(
                                              width: 50,
                                              height: 50,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF4A90E2)
                                                    .withOpacity(0.1),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: const Icon(
                                                Icons.inventory_2,
                                                color: Color(0xFF4A90E2),
                                              ),
                                            ),
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
}
