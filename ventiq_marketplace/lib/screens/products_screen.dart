import 'dart:async';
import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../widgets/product_list_card.dart';
import 'product_detail_screen.dart';
import '../services/marketplace_service.dart';
import '../services/category_service.dart';

/// Pantalla de productos con paginación y filtros
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final MarketplaceService _marketplaceService = MarketplaceService();
  final CategoryService _categoryService = CategoryService();
  
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _categories = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int? _selectedCategoryId;
  
  // Paginación
  final int _pageSize = 20;
  int _currentOffset = 0;
  bool _hasMoreProducts = true;
  final ScrollController _scrollController = ScrollController();
  
  // Debounce para búsqueda
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadProducts();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  /// Carga las categorías desde la base de datos
  Future<void> _loadCategories() async {
    try {
      final categories = await _categoryService.getAllCategories();
      setState(() {
        _categories = categories;
      });
    } catch (e) {
      print('❌ Error cargando categorías: $e');
      // Continuar sin categorías
    }
  }

  /// Carga los productos con paginación y búsqueda
  Future<void> _loadProducts({bool reset = false}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _currentOffset = 0;
        _products = [];
        _hasMoreProducts = true;
      });
    }

    if (!_hasMoreProducts && !reset) return;

    try {
      // Obtener query de búsqueda
      final searchQuery = _searchController.text.trim();
      
      final newProducts = await _marketplaceService.getProducts(
        idTienda: null, // Siempre null para marketplace
        idCategoria: _selectedCategoryId,
        soloDisponibles: true,
        searchQuery: searchQuery.isEmpty ? null : searchQuery,
        limit: _pageSize,
        offset: _currentOffset,
      );

      setState(() {
        if (reset) {
          _products = newProducts;
        } else {
          _products.addAll(newProducts);
        }
        
        _currentOffset += newProducts.length;
        _hasMoreProducts = newProducts.length == _pageSize;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      print('❌ Error cargando productos: $e');
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar productos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Maneja el scroll para cargar más productos
  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      if (!_isLoadingMore && _hasMoreProducts) {
        setState(() => _isLoadingMore = true);
        _loadProducts();
      }
    }
  }

  // La búsqueda ahora se hace en el servidor, no necesitamos filtrado local

  /// Maneja el cambio de búsqueda (con debounce de 500ms)
  void _onSearchChanged(String query) {
    // Cancelar el timer anterior si existe
    _debounceTimer?.cancel();
    
    // Crear nuevo timer de 500ms
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      // Recargar productos con la nueva búsqueda
      _loadProducts(reset: true);
    });
  }

  /// Maneja el cambio de categoría
  void _onCategoryChanged(int? categoryId) {
    setState(() {
      _selectedCategoryId = categoryId;
    });
    _loadProducts(reset: true);
  }

  /// Abre los detalles de un producto
  void _openProductDetails(Map<String, dynamic> product) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductDetailScreen(product: product),
      ),
    );
  }

  /// Refresca los productos
  Future<void> _refreshProducts() async {
    await _loadProducts(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: RefreshIndicator(
        onRefresh: _refreshProducts,
        color: AppTheme.primaryColor,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // AppBar moderno con gradiente
            _buildModernAppBar(),
            
            // Barra de búsqueda
            SliverToBoxAdapter(child: _buildSearchSection()),
            
            // Filtro de categorías
            SliverToBoxAdapter(child: _buildCategoryFilter()),
            
            // Contador de resultados
            if (!_isLoading && _products.isNotEmpty)
              SliverToBoxAdapter(child: _buildResultsCounter()),
            
            // Contenido principal
            _isLoading
                ? SliverToBoxAdapter(child: _buildLoadingState())
                : _products.isEmpty
                    ? SliverToBoxAdapter(child: _buildEmptyState())
                    : _buildProductsList(),
            
            // Indicador de carga al final
            if (_isLoadingMore)
              SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.all(AppTheme.paddingM),
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// AppBar moderno con SliverAppBar
  Widget _buildModernAppBar() {
    return SliverAppBar(
      expandedHeight: 140.0,
      floating: false,
      pinned: true,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.primaryColor,
                AppTheme.primaryColor.withOpacity(0.85),
                AppTheme.accentColor.withOpacity(0.7),
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.paddingM,
                vertical: AppTheme.paddingS,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppTheme.errorColor.withOpacity(0.3),
                              AppTheme.warningColor.withOpacity(0.3),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.shopping_bag_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Productos',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                              ),
                            ),
                            Text(
                              'Encuentra lo que necesitas',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Sección del buscador mejorada
  Widget _buildSearchSection() {
    return Padding(
      padding: const EdgeInsets.all(AppTheme.paddingM),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            hintText: 'Buscar productos...',
            hintStyle: TextStyle(
              color: AppTheme.textSecondary.withOpacity(0.6),
              fontSize: 15,
            ),
            prefixIcon: Container(
              padding: const EdgeInsets.all(12),
              child: const Icon(
                Icons.search_rounded,
                color: AppTheme.primaryColor,
                size: 24,
              ),
            ),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(
                      Icons.clear_rounded,
                      color: AppTheme.textSecondary,
                    ),
                    onPressed: () {
                      _searchController.clear();
                      _onSearchChanged('');
                    },
                  )
                : null,
            filled: false,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusL),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 16,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryFilter() {
    return Container(
      height: 56,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.paddingM),
        itemCount: _categories.length + 1, // +1 para "Todos"
        itemBuilder: (context, index) {
          // Primer item es "Todos"
          if (index == 0) {
            final isSelected = _selectedCategoryId == null;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? LinearGradient(
                          colors: [
                            AppTheme.primaryColor.withOpacity(0.15),
                            AppTheme.primaryColor.withOpacity(0.08),
                          ],
                        )
                      : null,
                  color: isSelected ? null : Colors.grey[50],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? AppTheme.primaryColor.withOpacity(0.3)
                        : Colors.grey.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _onCategoryChanged(null),
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text(
                        'Todos',
                        style: TextStyle(
                          color: isSelected ? AppTheme.primaryColor : AppTheme.textSecondary,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          fontSize: 13,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
          
          // Resto de categorías
          final category = _categories[index - 1];
          final categoryId = category['id'] as int;
          final categoryName = category['denominacion'] as String;
          final isSelected = _selectedCategoryId == categoryId;
          
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Container(
              decoration: BoxDecoration(
                gradient: isSelected
                    ? LinearGradient(
                        colors: [
                          AppTheme.primaryColor.withOpacity(0.15),
                          AppTheme.primaryColor.withOpacity(0.08),
                        ],
                      )
                    : null,
                color: isSelected ? null : Colors.grey[50],
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? AppTheme.primaryColor.withOpacity(0.3)
                      : Colors.grey.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _onCategoryChanged(categoryId),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      categoryName,
                      style: TextStyle(
                        color: isSelected ? AppTheme.primaryColor : AppTheme.textSecondary,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        fontSize: 13,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildResultsCounter() {
    final isFiltering = _searchController.text.isNotEmpty || _selectedCategoryId != null;
    
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppTheme.paddingM,
        vertical: 8,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            isFiltering
                ? AppTheme.accentColor.withOpacity(0.08)
                : AppTheme.secondaryColor.withOpacity(0.06),
            isFiltering
                ? AppTheme.accentColor.withOpacity(0.04)
                : AppTheme.secondaryColor.withOpacity(0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isFiltering
              ? AppTheme.accentColor.withOpacity(0.2)
              : Colors.grey.withOpacity(0.15),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isFiltering
                  ? AppTheme.accentColor.withOpacity(0.15)
                  : AppTheme.secondaryColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isFiltering ? Icons.filter_list_rounded : Icons.shopping_bag_rounded,
              size: 18,
              color: isFiltering ? AppTheme.accentColor : AppTheme.secondaryColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${_products.length} ${_products.length == 1 ? 'producto encontrado' : 'productos encontrados'}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isFiltering ? AppTheme.accentColor : AppTheme.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primaryColor.withOpacity(0.1),
                    AppTheme.accentColor.withOpacity(0.05),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: const CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Cargando productos...',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Preparando las mejores ofertas',
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary.withOpacity(0.8),
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
          Icon(
            Icons.shopping_bag_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: AppTheme.paddingM),
          const Text(
            'No se encontraron productos',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: AppTheme.paddingS),
          const Text(
            'Intenta con otros términos de búsqueda',
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductsList() {
    return SliverPadding(
      padding: const EdgeInsets.only(
        top: 8,
        bottom: AppTheme.paddingXL,
      ),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
        
        final product = _products[index];
        final metadata = product['metadata'] as Map<String, dynamic>?;
        
        // Extraer presentaciones del metadata
        final presentacionesData = metadata?['presentaciones'] as List<dynamic>?;
        final presentaciones = presentacionesData?.map((p) {
          final presentacion = p as Map<String, dynamic>;
          final denominacion = presentacion['denominacion'] as String? ?? '';
          final cantidad = presentacion['cantidad'] ?? 1;
          final esBase = presentacion['es_base'] as bool? ?? false;
          
          // Formato: "Unidad" o "Caja x24" con indicador de base
          if (cantidad == 1) {
            return esBase ? '$denominacion ⭐' : denominacion;
          } else {
            return esBase ? '$denominacion x$cantidad ⭐' : '$denominacion x$cantidad';
          }
        }).toList() ?? [];
        
        return ProductListCard(
          productName: product['denominacion'] ?? 'Sin nombre',
          price: (product['precio_venta'] ?? 0).toDouble(),
          imageUrl: product['imagen'],
          storeName: metadata?['denominacion_tienda'] ?? 'Sin tienda',
          availableStock: (product['stock_disponible'] ?? 0).toInt(),
          rating: (metadata?['rating_promedio'] ?? 0.0).toDouble(),
          presentations: presentaciones,
          onTap: () => _openProductDetails(product),
        );
          },
          childCount: _products.length,
        ),
      ),
    );
  }
}
