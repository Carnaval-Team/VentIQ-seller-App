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
      backgroundColor: AppTheme.backgroundColor,
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: AppTheme.primaryColor,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // AppBar con efecto moderno
            _buildModernAppBar(),

            // Contenido principal
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  // Buscador con diseño mejorado
                  _buildSearchSection(),

                  const SizedBox(height: AppTheme.paddingL),

                  // Banner promocional
                  // _buildPromoBanner(),

                  const SizedBox(height: AppTheme.paddingL),

                  // Productos más vendidos
                  _buildBestSellingProducts(),

                  const SizedBox(height: AppTheme.paddingXL),

                  // Tiendas destacadas
                  _buildTopStores(),

                  const SizedBox(height: AppTheme.paddingXL),
                ],
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
      expandedHeight: 120.0,
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
                AppTheme.primaryColor.withOpacity(0.8),
                AppTheme.secondaryColor,
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
                        padding: const EdgeInsets.all(0),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Image.asset(
                            'assets/logo_app_no_background.png',
                            width: 58,
                            height: 58,
                            fit: BoxFit.contain,
                          ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Inventtia',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            Text(
                              'Marketplace',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.notifications_outlined),
                          color: Colors.white,
                          onPressed: () {},
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.account_circle_outlined),
                          color: Colors.white,
                          onPressed: () {},
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
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.paddingM),
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
        child: SearchBarWidget(
          controller: _searchController,
          onSearch: (query) {
            // TODO: Implementar búsqueda
            print('Buscando: $query');
          },
        ),
      ),
    );
  }

  /// Banner promocional
  Widget _buildPromoBanner() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.paddingM),
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.accentColor,
              AppTheme.accentColor.withOpacity(0.8),
            ],
          ),
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
          boxShadow: [
            BoxShadow(
              color: AppTheme.accentColor.withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Patrón de fondo decorativo
            Positioned(
              right: -20,
              top: -20,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
            ),
            Positioned(
              right: 40,
              bottom: -30,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
            ),
            // Contenido
            Padding(
              padding: const EdgeInsets.all(AppTheme.paddingL),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '🎉 OFERTA ESPECIAL',
                      style: TextStyle(
                        color: AppTheme.accentColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '¡Descuentos de hasta\n50% en productos!',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Aprovecha las mejores ofertas',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Sección de productos más vendidos con diseño mejorado
  Widget _buildBestSellingProducts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.paddingM),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.errorColor.withOpacity(0.2),
                          AppTheme.warningColor.withOpacity(0.2),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.local_fire_department_rounded,
                      color: AppTheme.errorColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Más Vendidos',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        'Los favoritos del momento',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: TextButton(
                  onPressed: () {
                    widget.onNavigateToTab?.call(2);
                  },
                  child: Row(
                    children: [
                      Text(
                        'Ver todos',
                        style: TextStyle(
                          color: AppTheme.primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: AppTheme.primaryColor,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTheme.paddingM),
        SizedBox(
          height: 290,
          child: _isLoadingProducts
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        color: AppTheme.primaryColor,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Cargando productos...',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              : _bestSellingProducts.isEmpty
                  ? Center(
                      child: Container(
                        margin: const EdgeInsets.all(AppTheme.paddingM),
                        padding: const EdgeInsets.all(AppTheme.paddingL),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(AppTheme.radiusL),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.inventory_2_outlined,
                              size: 48,
                              color: AppTheme.textSecondary.withOpacity(0.5),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'No hay productos disponibles',
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.paddingM,
                      ),
                      itemCount: _bestSellingProducts.length,
                      itemBuilder: (context, index) {
                        final product = _bestSellingProducts[index];
                        return Padding(
                          padding: const EdgeInsets.only(right: AppTheme.paddingM),
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

  /// Sección de tiendas destacadas con diseño mejorado
  Widget _buildTopStores() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.paddingM),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.warningColor.withOpacity(0.2),
                          AppTheme.warningColor.withOpacity(0.1),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.store_rounded,
                      color: AppTheme.warningColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tiendas Destacadas',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        'Las mejores valoradas',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: TextButton(
                  onPressed: () {
                    widget.onNavigateToTab?.call(1);
                  },
                  child: Row(
                    children: [
                      Text(
                        'Ver todas',
                        style: TextStyle(
                          color: AppTheme.primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: AppTheme.primaryColor,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTheme.paddingM),
        SizedBox(
          height: 210,
          child: _isLoadingStores
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        color: AppTheme.primaryColor,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Cargando tiendas...',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              : _featuredStores.isEmpty
                  ? Center(
                      child: Container(
                        margin: const EdgeInsets.all(AppTheme.paddingM),
                        padding: const EdgeInsets.all(AppTheme.paddingL),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(AppTheme.radiusL),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.store_mall_directory_outlined,
                              size: 48,
                              color: AppTheme.textSecondary.withOpacity(0.5),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'No hay tiendas disponibles',
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.paddingM,
                      ),
                      itemCount: _featuredStores.length,
                      itemBuilder: (context, index) {
                        final store = _featuredStores[index];
                        return Padding(
                          padding: const EdgeInsets.only(right: AppTheme.paddingM),
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
  

