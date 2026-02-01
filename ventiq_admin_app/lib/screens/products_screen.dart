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

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _AiPlanFeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _AiPlanFeatureChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
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
  final PermissionsService _permissionsService = PermissionsService();
  final SubscriptionService _subscriptionService = SubscriptionService();
  bool _canCreateProduct = false;
  bool _canEditProduct = false;
  bool _canDeleteProduct = false;
  bool _hasAdvancedPlan = false;
  bool _isLoadingAdvancedPlan = true;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _loadCategories();
    _loadProducts();
    _loadAdvancedPlanStatus();
  }

  void _checkPermissions() async {
    print('🔐 Verificando permisos de productos...');
    final permissions = await Future.wait([
      _permissionsService.canPerformAction('product.create'),
      _permissionsService.canPerformAction('product.edit'),
      _permissionsService.canPerformAction('product.delete'),
    ]);

    final canCreate = permissions[0];
    final canEdit = permissions[1];
    final canDelete = permissions[2];

    print('  • Crear producto: $canCreate');
    print('  • Editar producto: $canEdit');
    print('  • Eliminar producto: $canDelete');

    if (!mounted) return;
    setState(() {
      _canCreateProduct = canCreate;
      _canEditProduct = canEdit;
      _canDeleteProduct = canDelete;
    });
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
      // Fetch and update exchange rates first
      print('💱 Fetching exchange rates...');
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
      debugPrint('❌ Error verificando plan avanzado: $e');
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
          if (_canCreateProduct)
            IconButton(
              icon:
                  _isLoadingAdvancedPlan
                      ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                      : Icon(
                        _hasAdvancedPlan ? Icons.auto_awesome : Icons.lock,
                        color: Colors.white,
                      ),
              onPressed:
                  _isLoadingAdvancedPlan ? null : _showAiProductGenerator,
              tooltip:
                  _hasAdvancedPlan
                      ? 'Generar productos con IA'
                      : 'Plan Avanzado requerido',
            ),
          if (_canCreateProduct)
            IconButton(
              icon: const Icon(Icons.add, color: Colors.white),
              onPressed: _showAddProductDialog,
              tooltip: 'Agregar Producto',
            ),
          if (_canCreateProduct)
            IconButton(
              onPressed:
                  () => NavigationGuard.navigateWithPermission(
                    context,
                    '/excel-import',
                  ),
              icon: const Icon(Icons.upload_file),
              tooltip: 'Importar desde Excel',
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
      floatingActionButton:
          _canCreateProduct
              ? FloatingActionButton(
                onPressed: _showAddProductDialog,
                backgroundColor: AppColors.primary,
                child: const Icon(Icons.add, color: Colors.white),
              )
              : null,
    );
  }

  Future<void> _showAiProductGenerator() async {
    final canCreate = await _permissionsService.canPerformAction(
      'product.create',
    );
    if (!canCreate) {
      if (mounted) {
        NavigationGuard.showActionDeniedMessage(
          context,
          'Crear producto con IA',
        );
      }
      return;
    }

    if (!_hasAdvancedPlan) {
      _showAdvancedPlanRequiredSheet();
      return;
    }

    final result = await showModalBottomSheet<AiProductCreationResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => AiProductGeneratorSheet(
            onProductsCreated: () {
              _loadProducts();
            },
          ),
    );

    if (!mounted || result == null) {
      return;
    }

    if (result.createdCount > 0) {
      _loadProducts();
      final message = 'Se crearon ${result.createdCount} productos.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: result.hasErrors ? Colors.orange : AppColors.success,
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

  void _showAdvancedPlanRequiredSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.4,
          maxChildSize: 0.75,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock,
                      color: AppColors.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Generador IA disponible solo en Plan Avanzado',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Desbloquea la creación masiva de productos con IA, validación automática y vista previa editable.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: const [
                      _AiPlanFeatureChip(
                        icon: Icons.auto_awesome,
                        label: 'Productos automáticos',
                      ),
                      _AiPlanFeatureChip(
                        icon: Icons.preview,
                        label: 'Vista previa editable',
                      ),
                      _AiPlanFeatureChip(
                        icon: Icons.check_circle_outline,
                        label: 'Validación inteligente',
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(context, '/subscription-detail');
                      },
                      icon: const Icon(Icons.workspace_premium),
                      label: const Text('Ver Plan Avanzado'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
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
          hintText: 'Buscar por nombre, SKU, descripción o nombre comercial...',
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
              product.brand.toLowerCase().contains(
                _searchQuery.toLowerCase(),
              ) ||
              product.sku.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              product.description.toLowerCase().contains(
                _searchQuery.toLowerCase(),
              ) ||
              (product.descripcionCorta?.toLowerCase().contains(
                    _searchQuery.toLowerCase(),
                  ) ??
                  false) ||
              (product.nombreComercial?.toLowerCase().contains(
                    _searchQuery.toLowerCase(),
                  ) ??
                  false);

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
          if (_searchQuery.isEmpty && _canCreateProduct) ...[
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
                  Stack(
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
                      // Insignia de producto elaborado
                      if (product.esElaborado)
                        Positioned(
                          top: -2,
                          right: -2,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1),
                            ),
                            child: const Icon(
                              Icons.restaurant,
                              color: Colors.white,
                              size: 12,
                            ),
                          ),
                        ),
                      // Insignia de servicio
                      if (product.esServicio)
                        Positioned(
                          top: -2,
                          right: -2,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Colors.purple,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1),
                            ),
                            child: const Icon(
                              Icons.build,
                              color: Colors.white,
                              size: 12,
                            ),
                          ),
                        ),
                    ],
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
                        if (product.nombreComercial != null)
                          const SizedBox(height: 2),
                        if (product.nombreComercial != null)
                          Text(
                            '${product.nombreComercial}',
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
                          if (!product.esServicio)
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
                      if (_canEditProduct)
                        IconButton(
                          icon: const Icon(Icons.edit, size: 20),
                          onPressed: () => _showEditProductDialog(product),
                          color: AppColors.primary,
                          tooltip: 'Editar',
                        ),
                      if (_canEditProduct)
                        IconButton(
                          icon: const Icon(Icons.add_a_photo, size: 20),
                          onPressed: () => _showAddImageDialog(product),
                          color: Colors.orange,
                          tooltip: 'Gestionar imagen',
                        ),
                      if (_canDeleteProduct)
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

  void _showAddProductDialog() async {
    final canCreate = await _permissionsService.canPerformAction(
      'product.create',
    );
    if (!canCreate) {
      if (mounted) {
        NavigationGuard.showActionDeniedMessage(context, 'Crear producto');
      }
      return;
    }
    // Navegar a la pantalla de agregar producto con callback
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => AddProductScreen(
              onProductSaved: () {
                // Recargar la lista de productos después de crear
                print('🔄 Producto creado, recargando lista...');
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
              variantWidgets.add(
                _buildNewVariantCard(
                  atributo: atributo,
                  opcion: opcion,
                  presentations: varianteDisponible['presentaciones'] ?? [],
                ),
              );
            }
          }
        }
      }
    } else {
      // Fallback to old structure
      variantWidgets =
          product.variants
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
            ...presentations
                .map(
                  (presentation) => Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 2),
                    child: Text(
                      '• ${presentation['presentacion'] ?? presentation['denominacion'] ?? 'Presentación'} (${presentation['cantidad'] ?? 1}x)',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textLight,
                      ),
                    ),
                  ),
                )
                .toList(),
          ],
        ],
      ),
    );
  }

  Future<void> _showEditProductDialog(Product product) async {
    final canEdit = await _permissionsService.canPerformAction('product.edit');
    if (!canEdit) {
      if (mounted) {
        NavigationGuard.showActionDeniedMessage(context, 'Editar producto');
      }
      return;
    }
    // ✅ ACTUALIZADO: Usar Navigator.push como en product_detail_screen para consistencia
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => AddProductScreen(
              product: product,
              onProductSaved: () {
                // Recargar la lista de productos después de editar
                print('🔄 Producto editado, recargando lista...');
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
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          ),
        ),
      ],
    );
  }

  void _showDeleteConfirmation(Product product) async {
    final canDelete = await _permissionsService.canPerformAction(
      'product.delete',
    );
    if (!canDelete) {
      if (mounted) {
        NavigationGuard.showActionDeniedMessage(context, 'Eliminar producto');
      }
      return;
    }
    // Verificar si el producto tiene stock antes de mostrar el diálogo
    if (await _hasStock(product)) {
      _showStockWarningDialog(product);
      return;
    }

    bool isDeleting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setState) => AlertDialog(
                  title: Row(
                    children: [
                      Icon(Icons.warning, color: AppColors.error, size: 28),
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
                            border: Border.all(
                              color: AppColors.error.withOpacity(0.3),
                            ),
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
                        const SizedBox(height: 8),

                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.warning.withOpacity(0.3),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '⚠️ ES NECESARIO',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.warning,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Para poder eliminar el producto no debe tener inventario disponible o ser parte de un producto elaborado o un servicio.',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Esta acción eliminará TODOS los datos relacionados a:',
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
                            border: Border.all(
                              color: AppColors.warning.withOpacity(0.3),
                            ),
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
                      onPressed:
                          isDeleting ? null : () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                    ElevatedButton(
                      onPressed:
                          isDeleting
                              ? null
                              : () async {
                                setState(() {
                                  isDeleting = true;
                                });

                                try {
                                  final result =
                                      await ProductService.deleteProductComplete(
                                        int.parse(product.id),
                                      );

                                  if (mounted) {
                                    Navigator.pop(context);

                                    if (result['success'] == true) {
                                      _showDeletionSuccessDialog(result);
                                      _loadProducts(); // Refresh the products list
                                    } else {
                                      _showErrorMessage(
                                        result['message'] ??
                                            'Error desconocido',
                                      );
                                    }
                                  }
                                } catch (e) {
                                  setState(() {
                                    isDeleting = false;
                                  });

                                  if (mounted) {
                                    _showErrorMessage(
                                      'Error al eliminar producto: $e',
                                    );
                                  }
                                }
                              },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                      ),
                      child:
                          isDeleting
                              ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
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
          ...items
              .map(
                (item) => Padding(
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
                ),
              )
              .toList(),
        ],
      ),
    );
  }

  void _showDeletionSuccessDialog(Map<String, dynamic> result) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.check_circle, color: AppColors.success, size: 28),
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
                      border: Border.all(
                        color: AppColors.success.withOpacity(0.3),
                      ),
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
                            (result['tablas_afectadas'] as List)
                                .isNotEmpty) ...[
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
        NavigationGuard.navigateAndRemoveUntil(context, '/dashboard');
        break;
      case 1: // Productos (current)
        break;
      case 2: // Inventario
        NavigationGuard.navigateWithPermission(context, '/inventory');
        break;
      case 3: // Almacenes
        NavigationGuard.navigateWithPermission(context, '/warehouse');
        break;
    }
  }

  /// Verificar si el producto tiene stock disponible
  Future<bool> _hasStock(Product product) async {
    try {
      // Verificar primero el stock disponible del producto
      if (product.stockDisponible > 0) {
        print(
          '🔍 Producto ${product.denominacion} tiene stock: ${product.stockDisponible}',
        );
        return true;
      }

      // Verificar también las ubicaciones de stock para mayor precisión
      final stockLocations = await ProductService.getProductStockLocations(
        product.id.toString(),
      );

      for (var location in stockLocations) {
        final cantidad = (location['cantidad_final'] ?? 0).toDouble();
        if (cantidad > 0) {
          print(
            '🔍 Producto ${product.denominacion} tiene stock en ubicación: $cantidad',
          );
          return true;
        }
      }

      print('✅ Producto ${product.denominacion} no tiene stock disponible');
      return false;
    } catch (e) {
      print('❌ Error verificando stock del producto: $e');
      // En caso de error, asumir que tiene stock para prevenir eliminaciones accidentales
      return true;
    }
  }

  /// Mostrar diálogo de advertencia cuando el producto tiene stock
  void _showStockWarningDialog(Product product) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder:
          (context) => AlertDialog(
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
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.warning.withOpacity(0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '📦 PRODUCTO CON STOCK',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.warning,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'El producto "${product.denominacion}" tiene stock disponible (${product.stockDisponible.toStringAsFixed(0)} unidades).',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Para poder eliminar este producto, primero debes:',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                _buildRequirementItem('📤 Realizar extracciones de inventario'),
                _buildRequirementItem(
                  '🔄 Transferir el stock a otros productos',
                ),
                _buildRequirementItem('📊 Ajustar el inventario a cero'),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.info.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.info.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: AppColors.info, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Puedes gestionar el inventario desde la sección "Inventario" del menú principal.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.info,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
              ),
            ],
          ),
    );
  }

  /// Widget helper para mostrar elementos de requisitos
  Widget _buildRequirementItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6, right: 8),
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textSecondary,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Muestra el diálogo para gestionar la imagen del producto
  Future<void> _showAddImageDialog(Product product) async {
    final canEdit = await _permissionsService.canPerformAction('product.edit');
    if (!canEdit) {
      if (mounted) {
        NavigationGuard.showActionDeniedMessage(context, 'Editar producto');
      }
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (context) => _AddImageDialog(
            product: product,
            onImageUpdated: () {
              _loadProducts(); // Recargar productos para mostrar la nueva imagen
            },
          ),
    );
  }
}

/// Diálogo para seleccionar y subir imagen del producto
class _AddImageDialog extends StatefulWidget {
  final Product product;
  final VoidCallback onImageUpdated;

  const _AddImageDialog({required this.product, required this.onImageUpdated});

  @override
  State<_AddImageDialog> createState() => _AddImageDialogState();
}

class _AddImageDialogState extends State<_AddImageDialog> {
  final ImagePicker _imagePicker = ImagePicker();
  bool _isLoading = false;

  Future<void> _pickImageWeb() async {
    try {
      setState(() => _isLoading = true);

      final Uint8List? bytes = await ImagePickerService.pickImage();

      if (bytes != null) {
        final fileName =
            'product_${widget.product.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';

        // Subir imagen y actualizar producto
        final success = await ProductService.updateProductImage(
          productId: widget.product.id,
          imageBytes: bytes,
          imageFileName: fileName,
        );

        if (success && mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Imagen actualizada exitosamente'),
              backgroundColor: AppColors.success,
            ),
          );

          // Ejecutar callback para recargar la lista
          widget.onImageUpdated();
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Error al actualizar la imagen'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      setState(() => _isLoading = true);

      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 80,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        final fileName =
            'product_${widget.product.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';

        // Subir imagen y actualizar producto
        final success = await ProductService.updateProductImage(
          productId: widget.product.id,
          imageBytes: bytes,
          imageFileName: fileName,
        );

        if (success && mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Imagen actualizada exitosamente'),
              backgroundColor: AppColors.success,
            ),
          );

          // Ejecutar callback para recargar la lista
          widget.onImageUpdated();
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Error al actualizar la imagen'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _removeImage() async {
    try {
      setState(() => _isLoading = true);

      // Actualizar producto con imagen vacía
      final success = await ProductService.removeProductImage(
        productId: widget.product.id,
      );

      if (success && mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Imagen eliminada exitosamente'),
            backgroundColor: AppColors.success,
          ),
        );

        // Ejecutar callback para recargar la lista
        widget.onImageUpdated();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Error al eliminar la imagen'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Icon(Icons.add_a_photo, color: Colors.orange[600], size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Gestionar Imagen',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        widget.product.name,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (_isLoading)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    color: AppColors.textSecondary,
                  ),
              ],
            ),
          ),

          // Imagen actual
          if (widget.product.imageUrl.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  const Text(
                    'Imagen actual:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      image: DecorationImage(
                        image: NetworkImage(widget.product.imageUrl),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Opciones
          if (!_isLoading) ...[
            if (kIsWeb) ...[
              // Opción para web
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.upload_file, color: Colors.blue),
                ),
                title: const Text('Seleccionar archivo'),
                subtitle: const Text('Elegir una imagen desde tu computadora'),
                onTap: _pickImageWeb,
              ),
            ] else ...[
              // Opciones para móvil
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.camera_alt, color: Colors.blue),
                ),
                title: const Text('Tomar foto'),
                subtitle: const Text('Usar la cámara del dispositivo'),
                onTap: () => _pickImage(ImageSource.camera),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.photo_library, color: Colors.green),
                ),
                title: const Text('Seleccionar de galería'),
                subtitle: const Text('Elegir una imagen existente'),
                onTap: () => _pickImage(ImageSource.gallery),
              ),
            ],
            if (widget.product.imageUrl.isNotEmpty) ...[
              const Divider(height: 1),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.delete, color: Colors.red),
                ),
                title: const Text('Eliminar imagen'),
                subtitle: const Text('Quitar la imagen actual'),
                onTap: _removeImage,
              ),
            ],
            const SizedBox(height: 20),
          ] else ...[
            const Padding(
              padding: EdgeInsets.all(40),
              child: Column(
                children: [
                  CircularProgressIndicator(color: AppColors.primary),
                  SizedBox(height: 16),
                  Text(
                    'Procesando imagen...',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
