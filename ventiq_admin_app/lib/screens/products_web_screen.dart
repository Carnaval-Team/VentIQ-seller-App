import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../config/app_colors.dart';
import '../models/product.dart';
import '../services/product_service.dart';
import '../services/currency_service.dart';
import '../services/permissions_service.dart';
import '../services/image_picker_service.dart';
import '../services/subscription_service.dart';
import '../services/user_preferences_service.dart';
import 'add_product_screen.dart';
import 'product_detail_screen.dart';
import 'excel_import_screen.dart';
import '../models/ai_product_models.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/admin_bottom_navigation.dart';
import '../widgets/ai_product_generator_sheet.dart';
import '../utils/navigation_guard.dart';

class ProductsWebScreen extends StatefulWidget {
  const ProductsWebScreen({super.key});

  @override
  State<ProductsWebScreen> createState() => _ProductsWebScreenState();
}

class _ProductsWebScreenState extends State<ProductsWebScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<Product> _products = [];
  bool _isLoading = true;
  String _selectedCategory = 'Todas';
  String _sortBy = 'name';
  bool _sortAscending = true;
  List<Map<String, dynamic>> _categories = [];
  int? _selectedCategoryId;
  final PermissionsService _permissionsService = PermissionsService();
  final SubscriptionService _subscriptionService = SubscriptionService();
  bool _canCreateProduct = false;
  bool _canEditProduct = false;
  bool _canDeleteProduct = false;
  bool _hasAdvancedPlan = false;
  bool _isLoadingAdvancedPlan = true;
  bool _isAlmacenero = false;
  String _viewMode = 'table'; // 'table' or 'grid'

  @override
  void initState() {
    super.initState();
    _checkUserRole();
    _checkPermissions();
    _loadCategories();
    _loadProducts();
    _loadAdvancedPlanStatus();
  }

  Future<void> _checkUserRole() async {
    final role = await _permissionsService.getUserRole();
    if (mounted) {
      setState(() {
        _isAlmacenero = role == UserRole.almacenero;
      });
    }
  }

  void _checkPermissions() async {
    final permissions = await Future.wait([
      _permissionsService.canPerformAction('product.create'),
      _permissionsService.canPerformAction('product.edit'),
      _permissionsService.canPerformAction('product.delete'),
    ]);

    if (!mounted) return;
    setState(() {
      _canCreateProduct = permissions[0] && !_isAlmacenero;
      _canEditProduct = permissions[1] && !_isAlmacenero;
      _canDeleteProduct = permissions[2] && !_isAlmacenero;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadProducts() async {
    setState(() => _isLoading = true);

    try {
      await CurrencyService.fetchAndUpdateExchangeRates();
      final productos = await ProductService.getProductsByTienda(
        categoryId: _selectedCategoryId,
        soloDisponibles: false,
      );

      setState(() {
        _products = productos;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
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

  Future<void> _loadAdvancedPlanStatus() async {
    setState(() => _isLoadingAdvancedPlan = true);
    try {
      final storeId = await UserPreferencesService().getIdTienda();
      if (storeId == null) {
        if (!mounted) return;
        setState(() {
          _hasAdvancedPlan = false;
          _isLoadingAdvancedPlan = false;
        });
        return;
      }
      final hasPlan = await _subscriptionService.hasAdvancedPlan(storeId);
      if (!mounted) return;
      setState(() {
        _hasAdvancedPlan = hasPlan;
        _isLoadingAdvancedPlan = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasAdvancedPlan = false;
        _isLoadingAdvancedPlan = false;
      });
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

  List<Product> get _filteredProducts {
    List<Product> filtered = _products.where((product) {
      final query = _searchQuery.toLowerCase();
      return product.name.toLowerCase().contains(query) ||
          product.categoryName.toLowerCase().contains(query) ||
          product.brand.toLowerCase().contains(query) ||
          product.sku.toLowerCase().contains(query) ||
          product.description.toLowerCase().contains(query) ||
          (product.descripcionCorta?.toLowerCase().contains(query) ?? false) ||
          (product.nombreComercial?.toLowerCase().contains(query) ?? false);
    }).toList();

    filtered.sort((a, b) {
      int result;
      switch (_sortBy) {
        case 'name':
          result = a.name.compareTo(b.name);
          break;
        case 'price':
          result = a.basePrice.compareTo(b.basePrice);
          break;
        case 'category':
          result = a.categoryName.compareTo(b.categoryName);
          break;
        case 'stock':
          result = a.stockDisponible.compareTo(b.stockDisponible);
          break;
        case 'status':
          result = (a.isActive ? 1 : 0).compareTo(b.isActive ? 1 : 0);
          break;
        default:
          result = 0;
      }
      return _sortAscending ? result : -result;
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _buildToolbar(),
            const SizedBox(height: 16),
            _buildCategoryChips(),
            const SizedBox(height: 16),
            _buildStatsSummary(),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    )
                  : _filteredProducts.isEmpty
                      ? _buildEmptyState()
                      : _viewMode == 'table'
                          ? _buildDataTable()
                          : _buildGridView(),
            ),
          ],
        ),
      ),
      endDrawer: const AdminDrawer(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Gestión de Productos',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 20,
            ),
          ),
          if (_isAlmacenero)
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue.shade700,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.visibility, size: 12, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'Solo Lectura',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      centerTitle: true,
      backgroundColor: AppColors.primary,
      elevation: 0,
      iconTheme: const IconThemeData(color: Colors.white),
      actions: [
        if (_canCreateProduct)
          IconButton(
            icon: const Icon(Icons.auto_awesome, color: Colors.white),
            onPressed: _showAiProductGenerator,
            tooltip: 'Generar productos con IA',
          ),
        if (_canCreateProduct)
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: _showAddProductDialog,
            tooltip: 'Agregar Producto',
          ),
        if (_canCreateProduct)
          IconButton(
            onPressed: () => NavigationGuard.navigateWithPermission(
              context,
              '/excel-import',
            ),
            icon: const Icon(Icons.upload_file),
            tooltip: 'Importar desde Excel',
          ),
        Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () => Scaffold.of(context).openEndDrawer(),
            tooltip: 'Menú',
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    return Row(
      children: [
        // Search
        Expanded(
          flex: 3,
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText:
                    'Buscar por nombre, SKU, descripción o nombre comercial...',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                prefixIcon:
                    const Icon(Icons.search, color: AppColors.primary, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Sort dropdown
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _sortBy,
              icon: const Icon(Icons.sort, size: 18),
              style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
              items: const [
                DropdownMenuItem(value: 'name', child: Text('Nombre')),
                DropdownMenuItem(value: 'price', child: Text('Precio')),
                DropdownMenuItem(value: 'category', child: Text('Categoría')),
                DropdownMenuItem(value: 'stock', child: Text('Stock')),
                DropdownMenuItem(value: 'status', child: Text('Estado')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    if (_sortBy == value) {
                      _sortAscending = !_sortAscending;
                    } else {
                      _sortBy = value;
                      _sortAscending = true;
                    }
                  });
                }
              },
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Sort direction
        IconButton(
          icon: Icon(
            _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
            size: 20,
          ),
          onPressed: () => setState(() => _sortAscending = !_sortAscending),
          tooltip: _sortAscending ? 'Ascendente' : 'Descendente',
          style: IconButton.styleFrom(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: Colors.grey.shade300),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // View mode toggle
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              _buildViewModeButton(Icons.table_rows, 'table'),
              _buildViewModeButton(Icons.grid_view, 'grid'),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Refresh
        IconButton(
          icon: const Icon(Icons.refresh, size: 20),
          onPressed: _loadProducts,
          tooltip: 'Recargar',
          style: IconButton.styleFrom(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: Colors.grey.shade300),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildViewModeButton(IconData icon, String mode) {
    final isSelected = _viewMode == mode;
    return InkWell(
      onTap: () => setState(() => _viewMode = mode),
      child: Container(
        width: 40,
        height: 44,
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 18,
          color: isSelected ? AppColors.primary : AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = _categories[index];
          final name = category['denominacion'] as String;
          final isSelected = _selectedCategory == name;
          return FilterChip(
            label: Text(
              name,
              style: TextStyle(
                fontSize: 13,
                color: isSelected ? Colors.white : AppColors.textPrimary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            selected: isSelected,
            onSelected: (selected) {
              setState(() {
                _selectedCategory = name;
                _selectedCategoryId = category['id'] as int?;
              });
              _loadProducts();
            },
            selectedColor: AppColors.primary,
            backgroundColor: Colors.white,
            checkmarkColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: isSelected ? AppColors.primary : Colors.grey.shade300,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatsSummary() {
    final total = _filteredProducts.length;
    final activos = _filteredProducts.where((p) => p.isActive).length;
    final sinStock =
        _filteredProducts.where((p) => !p.tieneStock && !p.esServicio).length;
    final servicios = _filteredProducts.where((p) => p.esServicio).length;

    return Row(
      children: [
        _buildStatChip('$total productos', Icons.inventory_2, Colors.blue),
        const SizedBox(width: 12),
        _buildStatChip('$activos activos', Icons.check_circle, Colors.green),
        const SizedBox(width: 12),
        _buildStatChip('$sinStock sin stock', Icons.warning_amber, Colors.orange),
        const SizedBox(width: 12),
        if (servicios > 0)
          _buildStatChip('$servicios servicios', Icons.build, Colors.purple),
      ],
    );
  }

  Widget _buildStatChip(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: color.withOpacity(0.9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataTable() {
    final products = _filteredProducts;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            // Table header
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 48), // image space
                  const SizedBox(width: 16),
                  Expanded(flex: 4, child: _buildHeaderCell('Producto')),
                  Expanded(flex: 2, child: _buildHeaderCell('Categoría')),
                  Expanded(flex: 2, child: _buildHeaderCell('SKU')),
                  Expanded(flex: 2, child: _buildHeaderCell('Precio', align: TextAlign.right)),
                  Expanded(flex: 2, child: _buildHeaderCell('Stock', align: TextAlign.center)),
                  Expanded(flex: 2, child: _buildHeaderCell('Estado', align: TextAlign.center)),
                  Expanded(flex: 2, child: _buildHeaderCell('Acciones', align: TextAlign.center)),
                ],
              ),
            ),
            // Table rows
            Expanded(
              child: ListView.separated(
                itemCount: products.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: Colors.grey.shade100),
                itemBuilder: (context, index) {
                  return _buildTableRow(products[index]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCell(String text, {TextAlign align = TextAlign.left}) {
    return Text(
      text,
      textAlign: align,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade600,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildTableRow(Product product) {
    return InkWell(
      onTap: () => _showProductDetails(product),
      hoverColor: AppColors.primary.withOpacity(0.03),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            // Image
            Stack(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: AppColors.primary.withOpacity(0.08),
                    image: product.imageUrl.isNotEmpty
                        ? DecorationImage(
                            image: NetworkImage(product.imageUrl),
                            fit: BoxFit.cover,
                            onError: (_, __) {},
                          )
                        : null,
                  ),
                  child: product.imageUrl.isEmpty
                      ? const Icon(Icons.inventory_2,
                          color: AppColors.primary, size: 22)
                      : null,
                ),
                if (product.esElaborado)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: const Icon(Icons.restaurant,
                          color: Colors.white, size: 10),
                    ),
                  ),
                if (product.esServicio)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.purple,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: const Icon(Icons.build,
                          color: Colors.white, size: 10),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            // Producto
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (product.nombreComercial != null)
                    Text(
                      product.nombreComercial!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textLight,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  Row(
                    children: [
                      Text(
                        '${_getVariantCount(product)} variante(s)',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.primary.withOpacity(0.7),
                        ),
                      ),
                      if (product.esRefrigerado) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.ac_unit, size: 13, color: Colors.blue.shade300),
                      ],
                      if (product.esFragil) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.warning, size: 13, color: Colors.orange.shade300),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Categoría
            Expanded(
              flex: 2,
              child: Text(
                product.categoryName,
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // SKU
            Expanded(
              flex: 2,
              child: Text(
                product.sku,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                  fontFamily: 'monospace',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Precio
            Expanded(
              flex: 2,
              child: Text(
                '\$${product.basePrice.toStringAsFixed(2)}',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
            // Stock
            Expanded(
              flex: 2,
              child: Center(
                child: product.esServicio
                    ? Text(
                        'N/A',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: product.tieneStock
                              ? AppColors.success.withOpacity(0.1)
                              : AppColors.error.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          product.tieneStock ? '${product.stockDisponible}' : 'Sin stock',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: product.tieneStock ? AppColors.success : AppColors.error,
                          ),
                        ),
                      ),
              ),
            ),
            // Estado
            Expanded(
              flex: 2,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: product.isActive
                        ? AppColors.success.withOpacity(0.1)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    product.isActive ? 'Activo' : 'Inactivo',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: product.isActive ? AppColors.success : AppColors.textLight,
                    ),
                  ),
                ),
              ),
            ),
            // Acciones
            Expanded(
              flex: 2,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildActionIcon(
                    Icons.visibility,
                    AppColors.info,
                    'Ver detalles',
                    () => _showProductDetails(product),
                  ),
                  if (_canEditProduct)
                    _buildActionIcon(
                      Icons.edit,
                      AppColors.primary,
                      'Editar',
                      () => _showEditProductDialog(product),
                    ),
                  if (_canDeleteProduct)
                    _buildActionIcon(
                      Icons.delete_outline,
                      AppColors.error,
                      'Eliminar',
                      () => _showDeleteConfirmation(product),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionIcon(
      IconData icon, Color color, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }

  Widget _buildGridView() {
    final products = _filteredProducts;

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        childAspectRatio: 0.75,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: products.length,
      itemBuilder: (context, index) => _buildGridCard(products[index]),
    );
  }

  Widget _buildGridCard(Product product) {
    return InkWell(
      onTap: () => _showProductDetails(product),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            Expanded(
              flex: 3,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(12)),
                  color: AppColors.primary.withOpacity(0.06),
                  image: product.imageUrl.isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(product.imageUrl),
                          fit: BoxFit.cover,
                          onError: (_, __) {},
                        )
                      : null,
                ),
                child: product.imageUrl.isEmpty
                    ? const Center(
                        child: Icon(Icons.inventory_2,
                            color: AppColors.primary, size: 40),
                      )
                    : null,
              ),
            ),
            // Info
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      product.categoryName,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '\$${product.basePrice.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                        if (!product.esServicio)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: product.tieneStock
                                  ? AppColors.success.withOpacity(0.1)
                                  : AppColors.error.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              product.tieneStock ? 'En Stock' : 'Sin Stock',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: product.tieneStock
                                    ? AppColors.success
                                    : AppColors.error,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isEmpty
                ? 'No hay productos registrados'
                : 'No se encontraron productos',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isEmpty
                ? 'Agrega tu primer producto con el botón "Nuevo Producto"'
                : 'Intenta con otros términos de búsqueda',
            style: TextStyle(fontSize: 14, color: Colors.grey[400]),
          ),
          if (_searchQuery.isEmpty && _canCreateProduct) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _showAddProductDialog,
              icon: const Icon(Icons.add),
              label: const Text('Agregar Producto'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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

  // ========== Action Methods (same logic as ProductsScreen) ==========

  int _getVariantCount(Product product) {
    if (product.variantesDisponibles.isNotEmpty) {
      int totalVariants = 0;
      for (final varianteDisponible in product.variantesDisponibles) {
        if (varianteDisponible['variante'] != null) {
          final variant = varianteDisponible['variante'];
          if (variant['opciones'] != null && variant['opciones'] is List) {
            totalVariants += (variant['opciones'] as List).length;
          } else {
            totalVariants += 1;
          }
        }
      }
      return totalVariants;
    }
    return product.variants.length;
  }

  Future<void> _showAiProductGenerator() async {
    final canCreate =
        await _permissionsService.canPerformAction('product.create');
    if (!canCreate) {
      if (mounted) {
        NavigationGuard.showActionDeniedMessage(
            context, 'Crear producto con IA');
      }
      return;
    }

    final result = await showModalBottomSheet<AiProductCreationResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AiProductGeneratorSheet(
        onProductsCreated: () => _loadProducts(),
      ),
    );

    if (!mounted || result == null) return;

    if (result.createdCount > 0) {
      _loadProducts();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Se crearon ${result.createdCount} productos.'),
          backgroundColor:
              result.hasErrors ? Colors.orange : AppColors.success,
        ),
      );
    }

    if (result.hasErrors) {
      final details = result.errors.take(3).join(' | ');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Detalles: $details'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _showAddProductDialog() async {
    final canCreate =
        await _permissionsService.canPerformAction('product.create');
    if (!canCreate) {
      if (mounted) {
        NavigationGuard.showActionDeniedMessage(context, 'Crear producto');
      }
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddProductScreen(
          onProductSaved: () {
            _loadProducts();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Producto creado exitosamente'),
                backgroundColor: AppColors.success,
              ),
            );
          },
        ),
      ),
    );
  }

  void _showProductDetails(Product product) {
    NavigationGuard.navigateWithPermission(
      context,
      '/product-detail',
      arguments: product,
    );
  }

  Future<void> _showEditProductDialog(Product product) async {
    final canEdit =
        await _permissionsService.canPerformAction('product.edit');
    if (!canEdit) {
      if (mounted) {
        NavigationGuard.showActionDeniedMessage(context, 'Editar producto');
      }
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddProductScreen(
          product: product,
          onProductSaved: () {
            _loadProducts();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Producto actualizado exitosamente'),
                backgroundColor: AppColors.success,
              ),
            );
          },
        ),
      ),
    );
  }

  void _showDeleteConfirmation(Product product) async {
    final canDelete =
        await _permissionsService.canPerformAction('product.delete');
    if (!canDelete) {
      if (mounted) {
        NavigationGuard.showActionDeniedMessage(context, 'Eliminar producto');
      }
      return;
    }
    if (await _hasStock(product)) {
      _showStockWarningDialog(product);
      return;
    }

    bool isDeleting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning, color: AppColors.error, size: 28),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Eliminar Producto',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.error,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            '¿Estás seguro de que deseas eliminar "${product.name}"?\n\nEsta acción eliminará todos los datos relacionados y no se puede deshacer.',
          ),
          actions: [
            TextButton(
              onPressed: isDeleting ? null : () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: isDeleting
                  ? null
                  : () async {
                      setState(() => isDeleting = true);
                      try {
                        final result =
                            await ProductService.deleteProductComplete(
                          int.parse(product.id),
                        );
                        if (mounted) {
                          Navigator.pop(context);
                          if (result['success'] == true) {
                            _loadProducts();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(result['message'] ??
                                    'Producto eliminado'),
                                backgroundColor: AppColors.success,
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    result['message'] ?? 'Error'),
                                backgroundColor: AppColors.error,
                              ),
                            );
                          }
                        }
                      } catch (e) {
                        setState(() => isDeleting = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: AppColors.error,
                            ),
                          );
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
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('Eliminar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _hasStock(Product product) async {
    try {
      if (product.stockDisponible > 0) return true;
      final stockLocations =
          await ProductService.getProductStockLocations(product.id.toString());
      for (var location in stockLocations) {
        final cantidad = (location['cantidad_final'] ?? 0).toDouble();
        if (cantidad > 0) return true;
      }
      return false;
    } catch (e) {
      return true;
    }
  }

  void _showStockWarningDialog(Product product) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: AppColors.warning, size: 28),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'No se puede eliminar',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.warning,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'El producto "${product.denominacion}" tiene stock disponible (${product.stockDisponible.toStringAsFixed(0)} unidades).\n\nPrimero debes agotar o ajustar el inventario a cero.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Entendido'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              NavigationGuard.navigateWithPermission(context, '/inventory');
            },
            icon: const Icon(Icons.inventory_2, size: 18),
            label: const Text('Ir a Inventario'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
