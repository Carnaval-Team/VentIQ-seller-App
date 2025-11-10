import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../widgets/product_card.dart';
import '../widgets/store_card.dart';
import '../widgets/search_bar_widget.dart';
import 'product_detail_screen.dart';
import 'store_detail_screen.dart';
import '../services/product_service.dart';
import '../services/store_service.dart';

/// Pantalla principal del marketplace
class HomeScreen extends StatefulWidget {
  final Function(int)? onNavigateToTab;

  const HomeScreen({super.key, this.onNavigateToTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ProductService _productService = ProductService();
  final StoreService _storeService = StoreService();
  
  List<Map<String, dynamic>> _bestSellingProducts = [];
  List<Map<String, dynamic>> _featuredStores = [];
  bool _isLoadingProducts = true;
  bool _isLoadingStores = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Cargar datos desde Supabase
  Future<void> _loadData() async {
    await Future.wait([
      _loadBestSellingProducts(),
      _loadFeaturedStores(),
    ]);
  }

  /// Cargar productos más vendidos
  Future<void> _loadBestSellingProducts() async {
    setState(() {
      _isLoadingProducts = true;
    });

    try {
      final products = await _productService.getMostSoldProducts(limit: 10);
      setState(() {
        _bestSellingProducts = products;
        _isLoadingProducts = false;
      });
    } catch (e) {
      print('❌ Error cargando productos: $e');
      setState(() {
        _isLoadingProducts = false;
      });
    }
  }

  /// Cargar tiendas destacadas
  Future<void> _loadFeaturedStores() async {
    setState(() {
      _isLoadingStores = true;
    });

    try {
      final stores = await _storeService.getFeaturedStores(limit: 10);
      setState(() {
        _featuredStores = stores;
        _isLoadingStores = false;
      });
    } catch (e) {
      print('❌ Error cargando tiendas: $e');
      setState(() {
        _isLoadingStores = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VentIQ Marketplace'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () {},
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Buscador
              _buildSearchSection(),

              const SizedBox(height: AppTheme.paddingM),

              // Productos más vendidos
              _buildBestSellingProducts(),

              const SizedBox(height: AppTheme.paddingL),

              // Tiendas destacadas
              _buildTopStores(),

              const SizedBox(height: AppTheme.paddingL),
            ],
          ),
        ),
      ),
    );
  }

  /// Sección del buscador
  Widget _buildSearchSection() {
    return Container(
      padding: const EdgeInsets.all(AppTheme.paddingM),
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppTheme.paddingM),
          SearchBarWidget(
            controller: _searchController,
            onSearch: (query) {
              // TODO: Implementar búsqueda
              print('Buscando: $query');
            },
          ),
        ],
      ),
    );
  }

  /// Sección de productos más vendidos
  Widget _buildBestSellingProducts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.paddingM),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '🔥 Productos Más Vendidos',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              TextButton(
                onPressed: () {
                  // Navegar al tab de Productos (index 2)
                  widget.onNavigateToTab?.call(2);
                },
                child: const Text('Ver todos'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTheme.paddingS),
        SizedBox(
          height: 280,
          child: _isLoadingProducts
              ? const Center(child: CircularProgressIndicator())
              : _bestSellingProducts.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(AppTheme.paddingM),
                        child: Text(
                          'No hay productos disponibles',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      ),
                    )
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.paddingS,
                      ),
                      itemCount: _bestSellingProducts.length,
                      itemBuilder: (context, index) {
                        final product = _bestSellingProducts[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppTheme.paddingS,
                          ),
                          child: ProductCard(
                            productName: product['nombre'] as String? ?? 'Sin nombre',
                            price: (product['precio_venta'] as num?)?.toDouble() ?? 0.0,
                            category: product['categoria_nombre'] as String? ?? 'Sin categoría',
                            imageUrl: product['imagen'] as String?,
                            storeName: product['tienda_nombre'] as String? ?? 'Tienda',
                            rating: (product['rating_promedio'] as num?)?.toDouble() ?? 0.0,
                            salesCount: (product['total_vendido'] as num?)?.toInt() ?? 0,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ProductDetailScreen(
                                    product: {
                                      'id': product['id_producto'],
                                      'nombre': product['nombre'],
                                      'precio': product['precio_venta'],
                                      'categoria': product['categoria_nombre'],
                                      'imageUrl': product['imagen'],
                                      'tienda': product['tienda_nombre'],
                                      'rating': product['rating_promedio'],
                                      'stock': product['stock_disponible'],
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  /// Sección de tiendas destacadas
  Widget _buildTopStores() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.paddingM),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '⭐ Tiendas Destacadas',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              TextButton(
                onPressed: () {
                  // Navegar al tab de Tiendas (index 1)
                  widget.onNavigateToTab?.call(1);
                },
                child: const Text('Ver todas'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTheme.paddingS),
        SizedBox(
          height: 200,
          child: _isLoadingStores
              ? const Center(child: CircularProgressIndicator())
              : _featuredStores.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(AppTheme.paddingM),
                        child: Text(
                          'No hay tiendas disponibles',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      ),
                    )
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.paddingS,
                      ),
                      itemCount: _featuredStores.length,
                      itemBuilder: (context, index) {
                        final store = _featuredStores[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppTheme.paddingS,
                          ),
                          child: StoreCard(
                            storeName: store['nombre'] as String? ?? 'Tienda',
                            productCount: (store['total_productos'] as num?)?.toInt() ?? 0,
                            salesCount: (store['total_ventas'] as num?)?.toInt() ?? 0,
                            rating: (store['rating_promedio'] as num?)?.toDouble() ?? 0.0,
                            logoUrl: store['imagen_url'] as String?,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => StoreDetailScreen(
                                    store: {
                                      'id': store['id_tienda'],
                                      'nombre': store['nombre'],
                                      'logoUrl': store['imagen_url'],
                                      'ubicacion': store['ubicacion'] ?? 'Sin ubicación',
                                      'provincia': 'Santo Domingo',
                                      'municipio': 'Santo Domingo Este',
                                      'direccion': store['direccion'] ?? 'Sin dirección',
                                      'productCount': store['total_productos'],
                                      'latitude': 18.4861,
                                      'longitude': -69.9312,
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
  

