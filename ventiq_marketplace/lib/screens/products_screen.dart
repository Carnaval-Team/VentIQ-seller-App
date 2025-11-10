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
      appBar: AppBar(
        title: const Text('Productos'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Barra de búsqueda
          _buildSearchBar(),
          
          // Filtro de categorías
          _buildCategoryFilter(),
          
          // Contador de resultados
          if (!_isLoading && _products.isNotEmpty) _buildResultsCounter(),
          
          // Lista de productos
          Expanded(
            child: _isLoading
                ? _buildLoadingState()
                : _products.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _refreshProducts,
                        child: _buildProductsList(),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(AppTheme.paddingM),
      color: Colors.white,
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: 'Buscar por nombre, SKU, categoría, tienda...',
          prefixIcon: const Icon(Icons.search, color: AppTheme.primaryColor),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged('');
                  },
                )
              : null,
          filled: true,
          fillColor: AppTheme.backgroundColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusM),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppTheme.paddingM,
            vertical: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryFilter() {
    return Container(
      height: 50,
      color: Colors.white,
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
              child: FilterChip(
                label: const Text('Todos'),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) {
                    _onCategoryChanged(null);
                  }
                },
                backgroundColor: Colors.white,
                selectedColor: AppTheme.primaryColor.withOpacity(0.2),
                labelStyle: TextStyle(
                  color: isSelected ? AppTheme.primaryColor : AppTheme.textSecondary,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
                side: BorderSide(
                  color: isSelected
                      ? AppTheme.primaryColor
                      : Colors.grey.shade300,
                  width: isSelected ? 1.5 : 1,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
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
            child: FilterChip(
              label: Text(categoryName),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  _onCategoryChanged(categoryId);
                }
              },
              backgroundColor: Colors.white,
              selectedColor: AppTheme.primaryColor.withOpacity(0.2),
              labelStyle: TextStyle(
                color: isSelected ? AppTheme.primaryColor : AppTheme.textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
              side: BorderSide(
                color: isSelected
                    ? AppTheme.primaryColor
                    : Colors.grey.shade300,
                width: isSelected ? 1.5 : 1,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          );
        },
      ),
    );
  }

  Widget _buildResultsCounter() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.paddingM,
        vertical: AppTheme.paddingS,
      ),
      color: AppTheme.backgroundColor,
      child: Row(
        children: [
          Text(
            '${_products.length} ${_products.length == 1 ? 'producto encontrado' : 'productos encontrados'}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: AppTheme.paddingM),
          Text(
            'Cargando productos...',
            style: TextStyle(
              fontSize: 16,
              color: AppTheme.textSecondary,
            ),
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
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(
        top: AppTheme.paddingS,
        bottom: AppTheme.paddingL,
      ),
      itemCount: _products.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        // Indicador de carga al final
        if (index == _products.length) {
          return const Padding(
            padding: EdgeInsets.all(AppTheme.paddingM),
            child: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }
        
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
    );
  }
}
