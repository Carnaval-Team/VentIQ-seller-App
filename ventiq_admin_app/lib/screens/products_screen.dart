import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_colors.dart';
import '../models/product.dart';
import '../services/product_service.dart';
import 'add_product_screen.dart';
import 'product_detail_screen.dart';
import '../widgets/admin_bottom_navigation.dart';
import '../widgets/admin_drawer.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<Product> _products = [];
  bool _isLoading = true;
  String _selectedCategory = 'Todas';
  String _sortBy = 'name';
  List<Map<String, dynamic>> _categories = [];
  int? _selectedCategoryId;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadProducts() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final productos = await ProductService.getProductsByTienda(
        categoryId: _selectedCategoryId,
        soloDisponibles: false,
      );

      setState(() {
        _products = productos;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar productos: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _loadCategories() async {
    try {
      final categorias = await ProductService.getCategorias();
      setState(() {
        _categories = [
          {'id': null, 'denominacion': 'Todas'},
          ...categorias,
        ];
      });
    } catch (e) {
      print('Error al cargar categorías: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Gestión de Productos',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        backgroundColor: AppColors.primary,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: _showAddProductDialog,
            tooltip: 'Agregar Producto',
          ),
          Builder(
            builder:
                (context) => IconButton(
                  icon: const Icon(Icons.menu, color: Colors.white),
                  onPressed: () => Scaffold.of(context).openEndDrawer(),
                  tooltip: 'Menú',
                ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchAndFilters(),
          Expanded(
            child: _isLoading ? _buildLoadingState() : _buildProductsList(),
          ),
        ],
      ),
      endDrawer: const AdminDrawer(),
      bottomNavigationBar: AdminBottomNavigation(
        currentIndex: 1,
        onTap: _onBottomNavTap,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddProductDialog,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppColors.primary),
          SizedBox(height: 16),
          Text(
            'Cargando productos...',
            style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters() {
    return Container(
      color: Colors.white,
      child: Column(children: [_buildSearchBar(), _buildFilters()]),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Buscar productos...',
          prefixIcon: const Icon(Icons.search, color: AppColors.primary),
          suffixIcon:
              _searchQuery.isNotEmpty
                  ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _searchQuery = '';
                      });
                    },
                  )
                  : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
        },
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children:
                    _categories.map((category) {
                      final categoryName = category['denominacion'] as String;
                      final isSelected = _selectedCategory == categoryName;
                      return Container(
                        margin: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(categoryName),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              _selectedCategory = categoryName;
                              _selectedCategoryId = category['id'] as int?;
                            });
                            _loadProducts(); // Recargar productos con filtro
                          },
                          selectedColor: AppColors.primary.withOpacity(0.2),
                          checkmarkColor: AppColors.primary,
                        ),
                      );
                    }).toList(),
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort, color: AppColors.primary),
            onSelected: (value) {
              setState(() {
                _sortBy = value;
              });
            },
            itemBuilder:
                (context) => [
                  const PopupMenuItem(
                    value: 'name',
                    child: Text('Ordenar por Nombre'),
                  ),
                  const PopupMenuItem(
                    value: 'price',
                    child: Text('Ordenar por Precio'),
                  ),
                  const PopupMenuItem(
                    value: 'category',
                    child: Text('Ordenar por Categoría'),
                  ),
                ],
          ),
        ],
      ),
    );
  }

  Widget _buildProductsList() {
    List<Product> filteredProducts =
        _products.where((product) {
          final matchesSearch =
              product.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              product.categoryName.toLowerCase().contains(
                _searchQuery.toLowerCase(),
              ) ||
              product.brand.toLowerCase().contains(_searchQuery.toLowerCase());

          // El filtro de categoría ya se aplica en la carga de datos
          return matchesSearch;
        }).toList();

    // Aplicar ordenamiento
    filteredProducts.sort((a, b) {
      switch (_sortBy) {
        case 'name':
          return a.name.compareTo(b.name);
        case 'price':
          return a.basePrice.compareTo(b.basePrice);
        case 'category':
          return a.categoryName.compareTo(b.categoryName);
        default:
          return 0;
      }
    });

    if (filteredProducts.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredProducts.length,
      itemBuilder: (context, index) {
        final product = filteredProducts[index];
        return _buildProductCard(product);
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isEmpty
                ? 'No hay productos registrados'
                : 'No se encontraron productos',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isEmpty
                ? 'Agrega tu primer producto usando el botón +'
                : 'Intenta con otros términos de búsqueda',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
          if (_searchQuery.isEmpty) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _showAddProductDialog,
              icon: const Icon(Icons.add),
              label: const Text('Agregar Producto'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProductCard(Product product) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _showProductDetails(product),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      image: DecorationImage(
                        image: NetworkImage(product.imageUrl),
                        fit: BoxFit.cover,
                        onError: (exception, stackTrace) {},
                      ),
                    ),
                    child:
                        product.imageUrl.isEmpty
                            ? Container(
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.inventory_2,
                                color: AppColors.primary,
                                size: 30,
                              ),
                            )
                            : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          product.categoryName,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'SKU: ${product.sku}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '\$${product.basePrice.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  product.tieneStock
                                      ? AppColors.success.withOpacity(0.1)
                                      : AppColors.error.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              product.tieneStock ? 'En Stock' : 'Sin Stock',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color:
                                    product.tieneStock
                                        ? AppColors.success
                                        : AppColors.error,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  product.isActive
                                      ? AppColors.primary.withOpacity(0.1)
                                      : AppColors.textLight.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              product.isActive ? 'Activo' : 'Inactivo',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color:
                                    product.isActive
                                        ? AppColors.primary
                                        : AppColors.textLight,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                product.description,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          '${_getVariantCount(product)} variante(s)',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.primary,
                          ),
                        ),
                        if (product.esRefrigerado) ...[
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.ac_unit,
                            size: 16,
                            color: AppColors.info,
                          ),
                        ],
                        if (product.esFragil) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.warning,
                            size: 16,
                            color: AppColors.warning,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.visibility, size: 20),
                        onPressed: () => _showProductDetails(product),
                        color: AppColors.info,
                        tooltip: 'Ver detalles',
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () => _showEditProductDialog(product),
                        color: AppColors.primary,
                        tooltip: 'Editar',
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, size: 20),
                        onPressed: () => _showDeleteConfirmation(product),
                        color: AppColors.error,
                        tooltip: 'Eliminar',
                      ),
                    ],
                  ),
                ],
              ),
              // Removed invalid _buildDetailRow calls - these should be in product details modal
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVariantCard(ProductVariant variant) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  variant.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                '\$${variant.price.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                'Presentación: ${variant.presentation}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                'SKU: ${variant.sku}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          if (variant.barcode.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Código: ${variant.barcode}',
              style: const TextStyle(fontSize: 12, color: AppColors.textLight),
            ),
          ],
        ],
      ),
    );
  }

  void _showAddProductDialog() {
    Navigator.pushNamed(context, '/add-product').then((result) {
      // Si se creó un producto, recargar la lista
      if (result == true) {
        _loadProducts();
      }
    });
  }

  void _showProductDetails(Product product) {
    Navigator.pushNamed(
      context,
      '/product-detail',
      arguments: product,
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _getVariantCount(Product product) {
    // Count variants from new RPC structure (variantes_disponibles)
    if (product.variantesDisponibles.isNotEmpty) {
      int totalVariants = 0;
      for (final varianteDisponible in product.variantesDisponibles) {
        if (varianteDisponible['variante'] != null) {
          final variant = varianteDisponible['variante'];
          if (variant['opciones'] != null && variant['opciones'] is List) {
            totalVariants += (variant['opciones'] as List).length;
          } else {
            totalVariants += 1; // Single variant
          }
        }
      }
      return totalVariants;
    }
    
    // Fallback to old structure
    return product.variants.length;
  }

  List<Widget> _buildVariantsList(Product product) {
    List<Widget> variantWidgets = [];
    
    // Handle new RPC structure (variantes_disponibles)
    if (product.variantesDisponibles.isNotEmpty) {
      for (final varianteDisponible in product.variantesDisponibles) {
        if (varianteDisponible['variante'] != null) {
          final variant = varianteDisponible['variante'];
          final atributo = variant['atributo'];
          
          if (variant['opciones'] != null && variant['opciones'] is List) {
            final opciones = variant['opciones'] as List<dynamic>;
            for (final opcion in opciones) {
              variantWidgets.add(_buildNewVariantCard(
                atributo: atributo,
                opcion: opcion,
                presentations: varianteDisponible['presentaciones'] ?? [],
              ));
            }
          }
        }
      }
    } else {
      // Fallback to old structure
      variantWidgets = product.variants
          .map((variant) => _buildVariantCard(variant))
          .toList();
    }
    
    if (variantWidgets.isEmpty) {
      variantWidgets.add(
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            'No hay variantes disponibles',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }
    
    return variantWidgets;
  }

  Widget _buildNewVariantCard({
    required Map<String, dynamic> atributo,
    required Map<String, dynamic> opcion,
    required List<dynamic> presentations,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '${atributo['label'] ?? atributo['denominacion'] ?? 'Atributo'}: ${opcion['valor'] ?? 'Valor'}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                'SKU: ${opcion['sku_codigo'] ?? 'N/A'}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          if (presentations.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Presentaciones:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            ...presentations.map((presentation) => Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 2),
              child: Text(
                '• ${presentation['presentacion'] ?? presentation['denominacion'] ?? 'Presentación'} (${presentation['cantidad'] ?? 1}x)',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textLight,
                ),
              ),
            )).toList(),
          ],
        ],
      ),
    );
  }

  void _showEditProductDialog(Product product) {
    final TextEditingController priceController = TextEditingController(
      text: product.basePrice.toString()
    );
    bool isUpdating = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text(
            'Editar Producto',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Product info (read-only)
                _buildReadOnlyField('Nombre', product.name),
                const SizedBox(height: 12),
                _buildReadOnlyField('SKU', product.sku),
                const SizedBox(height: 12),
                _buildReadOnlyField('Categoría', product.categoryName),
                const SizedBox(height: 12),
                _buildReadOnlyField('Descripción', product.description),
                const SizedBox(height: 12),
                _buildReadOnlyField('Estado', product.isActive ? 'Activo' : 'Inactivo'),
                const SizedBox(height: 12),
                _buildReadOnlyField('Stock', product.tieneStock ? 'Disponible' : 'Sin Stock'),
                const SizedBox(height: 16),
                
                // Editable price field
                const Text(
                  'Precio de Venta (CUP)',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: priceController,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    prefixText: '\$ ',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.primary),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'El precio es requerido';
                    }
                    final price = double.tryParse(value.trim());
                    if (price == null || price <= 0) {
                      return 'Ingrese un precio válido';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isUpdating ? null : () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: isUpdating ? null : () async {
                final newPriceText = priceController.text.trim();
                final newPrice = double.tryParse(newPriceText);
                
                if (newPrice == null || newPrice <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Ingrese un precio válido'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                  return;
                }

                setState(() {
                  isUpdating = true;
                });

                try {
                  await _updateProductPrice(int.parse(product.id), newPrice);
                  
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Precio actualizado exitosamente'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                    _loadProducts(); // Refresh the products list
                  }
                } catch (e) {
                  setState(() {
                    isUpdating = false;
                  });
                  
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error al actualizar precio: $e'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              child: isUpdating 
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadOnlyField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _updateProductPrice(int productId, double newPrice) async {
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('app_dat_precio_venta')
          .update({'precio_venta_cup': newPrice})
          .eq('id_producto', productId)
          .select();

      if (response.isEmpty) {
        throw Exception('No se encontró el producto para actualizar');
      }
    } catch (e) {
      throw Exception('Error al actualizar el precio: $e');
    }
  }

  void _showDeleteConfirmation(Product product) {
    bool isDeleting = false;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.warning,
                color: AppColors.error,
                size: 28,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Eliminar Producto Completo',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.error,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '⚠️ OPERACIÓN IRREVERSIBLE',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.error,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Se eliminará permanentemente:',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '"${product.name}"',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Esta acción eliminará TODOS los datos relacionados:',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                _buildDeletionCategory('📊 Inventario y Movimientos', [
                  'Registros de inventario',
                  'Extracciones de productos',
                  'Recepciones de productos',
                  'Control de productos',
                  'Ajustes de inventario',
                  'Pre-asignaciones',
                ]),
                _buildDeletionCategory('💰 Precios y Ventas', [
                  'Precios de venta',
                  'Clasificación ABC',
                  'Márgenes comerciales',
                ]),
                _buildDeletionCategory('🏪 Almacén y Ubicaciones', [
                  'Límites de almacén',
                  'Códigos de barras',
                ]),
                _buildDeletionCategory('📋 Información del Producto', [
                  'Etiquetas',
                  'Multimedias (imágenes)',
                  'Presentaciones',
                  'Subcategorías',
                  'Garantías',
                ]),
                _buildDeletionCategory('🎯 Marketing', [
                  'Promociones aplicadas',
                ]),
                _buildDeletionCategory('🍽️ Restaurante (si aplica)', [
                  'Recetas',
                  'Modificaciones',
                ]),
                _buildDeletionCategory('💼 Contabilidad', [
                  'Asignación de costos',
                ]),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.warning.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: AppColors.warning,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Esta operación no se puede deshacer. Asegúrate de tener un respaldo si es necesario.',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isDeleting ? null : () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: isDeleting ? null : () async {
                setState(() {
                  isDeleting = true;
                });

                try {
                  final result = await ProductService.deleteProductComplete(
                    int.parse(product.id)
                  );

                  if (mounted) {
                    Navigator.pop(context);
                    
                    if (result['success'] == true) {
                      _showDeletionSuccessDialog(result);
                      _loadProducts(); // Refresh the products list
                    } else {
                      _showErrorMessage(result['message'] ?? 'Error desconocido');
                    }
                  }
                } catch (e) {
                  setState(() {
                    isDeleting = false;
                  });
                  
                  if (mounted) {
                    _showErrorMessage('Error al eliminar producto: $e');
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
              ),
              child: isDeleting 
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text('Eliminar Definitivamente'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeletionCategory(String title, List<String> items) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          ...items.map((item) => Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '• ',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                Expanded(
                  child: Text(
                    item,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          )).toList(),
        ],
      ),
    );
  }

  void _showDeletionSuccessDialog(Map<String, dynamic> result) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.check_circle,
              color: AppColors.success,
              size: 28,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Producto Eliminado',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.success,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                result['message'] ?? 'Producto eliminado exitosamente',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.success.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resumen de eliminación:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.success,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Producto: ${result['nombre_producto']}',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    Text(
                      'Total registros eliminados: ${result['total_registros_eliminados']}',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    if (result['tablas_afectadas'] != null && 
                        (result['tablas_afectadas'] as List).isNotEmpty) ...[
                      Text(
                        'Configuraciones afectadas: ${(result['tablas_afectadas'] as List).length}',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
            ),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _onBottomNavTap(int index) {
    switch (index) {
      case 0: // Dashboard
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/dashboard',
          (route) => false,
        );
        break;
      case 1: // Productos (current)
        break;
      case 2: // Inventario
        Navigator.pushNamed(context, '/inventory');
        break;
      case 3: // Configuración
        Navigator.pushNamed(context, '/settings');
        break;
    }
  }
}
