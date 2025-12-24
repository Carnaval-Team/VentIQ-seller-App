import 'dart:async';
import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../widgets/product_card.dart';
import '../widgets/store_card.dart';
import '../widgets/product_list_card.dart';
import '../widgets/store_list_card.dart';
import 'product_detail_screen.dart';
import 'store_detail_screen.dart';
import 'map_screen.dart';
import '../services/product_service.dart';
import '../services/store_service.dart';
import '../services/marketplace_service.dart'; // Added for searchProducts

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
  final MarketplaceService _marketplaceService =
      MarketplaceService(); // Instance for searching products

  List<Map<String, dynamic>> _bestSellingProducts = [];
  List<Map<String, dynamic>> _featuredStores = [];

  // Search state
  bool _isLoadingProducts = true;
  bool _isLoadingStores = true;
  bool _isSearching = false;
  bool _isLoadingSearch = false;
  List<Map<String, dynamic>> _searchResultsStores = [];
  List<Map<String, dynamic>> _searchResultsProducts = [];
  Timer? _debounceTimer;

  // Banner state
  bool _showBanner = true;
  Timer? _bannerTimer;
  final GlobalKey<_MarqueeTextState> _marqueeKey =
      GlobalKey<_MarqueeTextState>();

  @override
  void initState() {
    super.initState();
    _loadData();
    _startBannerTimer();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    _bannerTimer?.cancel();
    super.dispose();
  }

  /// Iniciar timer para mostrar/ocultar banner
  void _startBannerTimer() {
    _bannerTimer = Timer.periodic(const Duration(seconds: 90), (timer) {
      if (mounted) {
        setState(() {
          _showBanner = !_showBanner;
        });
      }
    });
  }

  /// Cargar datos desde Supabase
  Future<void> _loadData() async {
    await Future.wait([_loadBestSellingProducts(), _loadFeaturedStores()]);
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

  void _onSearchChanged(String query) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();

    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _isSearching = false;
        _searchResultsStores = [];
        _searchResultsProducts = [];
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _isLoadingSearch = true;
    });

    try {
      // Parallel execution for better performance
      final results = await Future.wait([
        _storeService.searchStores(query, limit: 10),
        _marketplaceService.searchProducts(query, limit: 20),
      ]);

      setState(() {
        _searchResultsStores = results[0];
        _searchResultsProducts = results[1];
        _isLoadingSearch = false;
      });
    } catch (e) {
      print('Error searching: $e');
      setState(() {
        _isLoadingSearch = false;
      });
    }
  }

  /// Navegar a la pantalla del mapa
  Future<void> _navigateToMap() async {
    // Mostrar loading si es necesario, o navegar directamente y cargar allá
    // Aquí cargamos antes para pasar la lista filtrada
    try {
      // Mostrar indicador de carga rápido (opcional, o usar un overlay)
      if (!mounted) return;

      // Mostrar diálogo de carga simple
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: AppTheme.primaryColor),
        ),
      );

      final stores = await _storeService.getStoresWithLocation();

      if (!mounted) return;

      // Cerrar diálogo de carga
      Navigator.of(context).pop();

      if (stores.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hay tiendas con ubicación disponible'),
          ),
        );
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => MapScreen(stores: stores)),
      );
    } catch (e) {
      if (mounted && Navigator.canPop(context)) {
        Navigator.of(context).pop(); // Cerrar diálogo solo si está abierto
      }
      print('❌ Error navegando al mapa: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al cargar el mapa')),
        );
      }
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

            // Buscador fijo (aunque scrollea con el contenido, visualmente es el primer elemento)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: _buildSearchSection(),
              ),
            ),

            // Banner informativo sobre Carnaval App
            SliverToBoxAdapter(child: _buildCarnavalInfoBanner()),

            if (_isSearching) _buildSearchResults() else _buildHomeContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeContent() {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
    );
  }

  Widget _buildSearchResults() {
    if (_isLoadingSearch) {
      return const SliverFillRemaining(
        child: Center(
          child: CircularProgressIndicator(color: AppTheme.primaryColor),
        ),
      );
    }

    if (_searchResultsStores.isEmpty && _searchResultsProducts.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'No se encontraron resultados',
                style: TextStyle(fontSize: 18, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildListDelegate([
        if (_searchResultsStores.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              'Tiendas (${_searchResultsStores.length})',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          ..._searchResultsStores.map(
            (store) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: StoreListCard(
                storeName: store['denominacion'] ?? store['nombre'] ?? 'Tienda',
                logoUrl: store['imagen_url'],
                ubicacion: store['ubicacion'] ?? 'Sin ubicación',
                direccion: store['direccion'] ?? 'Sin dirección',
                productCount: (store['total_productos'] as num?)?.toInt() ?? 0,
                // Add dummy values for required fields if missing
                provincia: store['provincia'] ?? '',
                municipio: store['municipio'] ?? '',
                latitude: null,
                longitude: null,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => StoreDetailScreen(
                        store: {
                          'id': store['id'] ?? store['id_tienda'],
                          'nombre': store['denominacion'] ?? store['nombre'],
                          'logoUrl': store['imagen_url'],
                          'ubicacion': store['ubicacion'],
                          'direccion': store['direccion'],
                        },
                      ),
                    ),
                  );
                },
                onMapTap: () {}, // Optional
              ),
            ),
          ),
        ],

        if (_searchResultsProducts.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              'Productos (${_searchResultsProducts.length})',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          ..._searchResultsProducts.map(
            (product) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ProductListCard(
                productName: product['denominacion'] ?? 'Producto',
                price:
                    (product['app_dat_precio_venta']?[0]?['precio_venta'] ??
                            product['precio_venta'] ??
                            0)
                        .toDouble(),
                imageUrl: product['imagen'],
                storeName: 'Ver detalle', // Simplify for search result
                availableStock: 10, // Dummy or fetch if available
                rating: 0,
                presentations: const [], // Detailed view handles this
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          ProductDetailScreen(product: product),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
        const SizedBox(height: 40),
      ]),
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
                      const SizedBox(width: 8),
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
                              'Catálogo',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Notification Button
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
                      // Map Button
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.map_outlined),
                          color: Colors.white,
                          onPressed: _navigateToMap,
                          tooltip: 'Ver Mapa',
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Profile Button
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
        child: TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            hintText: 'Buscar productos o tiendas...',
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

  /// Banner informativo sobre Carnaval App con efecto marquee
  Widget _buildCarnavalInfoBanner() {
    if (!_showBanner) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.paddingM,
        AppTheme.paddingS,
        AppTheme.paddingM,
        AppTheme.paddingS,
      ),
      child: GestureDetector(
        onTap: () {
          // Reiniciar animación del marquee
          _marqueeKey.currentState?.resetAnimation();
        },
        child: Container(
          height: 36,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade50, Colors.blue.shade100],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.shade200, width: 1),
          ),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  Icons.info_outline,
                  color: Colors.blue.shade600,
                  size: 20,
                ),
              ),
              Expanded(
                child: _MarqueeText(
                  key: _marqueeKey,
                  textSpan: TextSpan(
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue.shade900,
                      fontWeight: FontWeight.w500,
                    ),
                    children: [
                      const TextSpan(
                        text:
                            'Algunos de los productos que aparecen en el catálogo se pueden comprar en línea a través de Carnaval App con ',
                      ),
                      TextSpan(
                        text: 'envío a domicilio gratis',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14, // Más grande
                          color: Colors.blue.shade900,
                        ),
                      ),
                      const TextSpan(
                        text:
                            '. El precio puede diferir por temas logísticos y de preparación hasta en un 5%. Para ir a comprar haga click en el botón rojo en la parte inferior derecha.',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
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
                    style: TextStyle(color: Colors.white70, fontSize: 14),
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
                      CircularProgressIndicator(color: AppTheme.primaryColor),
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
                        productName:
                            product['nombre'] as String? ?? 'Sin nombre',
                        price:
                            (product['precio_venta'] as num?)?.toDouble() ??
                            0.0,
                        category:
                            product['categoria_nombre'] as String? ??
                            'Sin categoría',
                        imageUrl: product['imagen'] as String?,
                        storeName:
                            product['tienda_nombre'] as String? ?? 'Tienda',
                        rating:
                            (product['rating_promedio'] as num?)?.toDouble() ??
                            0.0,
                        salesCount:
                            (product['total_vendido'] as num?)?.toInt() ?? 0,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  ProductDetailScreen(product: product),
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
                      CircularProgressIndicator(color: AppTheme.primaryColor),
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
                        productCount:
                            (store['total_productos'] as num?)?.toInt() ?? 0,
                        salesCount:
                            (store['total_ventas'] as num?)?.toInt() ?? 0,
                        rating:
                            (store['rating_promedio'] as num?)?.toDouble() ??
                            0.0,
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
                                  'ubicacion':
                                      store['ubicacion'] ?? 'Sin ubicación',
                                  'provincia': 'Santo Domingo',
                                  'municipio': 'Santo Domingo Este',
                                  'direccion':
                                      store['direccion'] ?? 'Sin dirección',
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

/// Widget de texto con efecto marquee (desplazamiento horizontal)
/// Widget de texto con efecto marquee (desplazamiento horizontal)
class _MarqueeText extends StatefulWidget {
  final TextSpan textSpan;

  const _MarqueeText({super.key, required this.textSpan});

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText>
    with SingleTickerProviderStateMixin {
  late ScrollController _scrollController;
  late Timer _timer;
  double _offset = 0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();

    // Iniciar animación después de un pequeño delay
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _startScrolling();
      }
    });
  }

  void resetAnimation() {
    _offset = 0;
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  void _startScrolling() {
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted || !_scrollController.hasClients) {
        timer.cancel();
        return;
      }

      _offset += 1.5;

      // Si llegamos al final, volver al inicio
      if (_offset >= _scrollController.position.maxScrollExtent) {
        _offset = 0;
      }

      _scrollController.jumpTo(_offset);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Row(
        children: [
          Text.rich(widget.textSpan),
          const SizedBox(width: 100), // Espacio antes de repetir
          Text.rich(widget.textSpan),
        ],
      ),
    );
  }
}
