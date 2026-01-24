import 'package:flutter/material.dart';
import 'products_screen.dart';
import 'barcode_scanner_screen.dart';
import 'product_details_screen.dart';
import '../widgets/bottom_navigation.dart';
import '../widgets/app_drawer.dart';
import '../services/category_service.dart';
import '../services/user_preferences_service.dart';
import '../services/changelog_service.dart';
import '../services/currency_service.dart';
import '../services/product_service.dart';
import '../models/product.dart';
import '../widgets/changelog_dialog.dart';
import '../widgets/sales_monitor_fab.dart';
import 'dart:async';

class CategoriesWebScreen extends StatefulWidget {
  const CategoriesWebScreen({super.key});

  @override
  State<CategoriesWebScreen> createState() => _CategoriesWebScreenState();
}

class _CategoriesWebScreenState extends State<CategoriesWebScreen>
    with WidgetsBindingObserver {
  final CategoryService _categoryService = CategoryService();
  final UserPreferencesService _preferencesService = UserPreferencesService();
  final ChangelogService _changelogService = ChangelogService();
  final ProductService _productService = ProductService();
  final FocusNode _searchFocusNode = FocusNode();
  List<Category> _categories = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _categoriesLoaded = false;
  bool _isSearchOpen = false;
  bool _isSearchingProducts = false;
  bool _isOfflineModeEnabled = false;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  List<Product> _searchResults = [];

  // USD rate data
  double _usdRate = 0.0;
  bool _isLoadingUsdRate = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkForChangelog();
    _loadCategories();
    _loadUsdRate();
    _loadOfflineModeSettings();
    _searchController.addListener(() {
      _onSearchChanged(_searchController.text);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {});
    }
  }

  Future<void> _checkForChangelog() async {
    try {
      final isFirstTime = await _preferencesService.isFirstTimeOpening();

      if (isFirstTime) {
        await Future.delayed(const Duration(milliseconds: 500));

        final changelog = await _changelogService.getLatestChangelog();
        if (changelog != null && mounted) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => ChangelogDialog(changelog: changelog),
          );

          await _preferencesService.saveAppVersion('1.0.0');
        }
      }
    } catch (e) {
      debugPrint('Error checking changelog: $e');
    }
  }

  Future<void> _loadCategories({bool forceRefresh = false}) async {
    if (_categoriesLoaded && !forceRefresh) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final categories = await _categoryService.getCategories();

      setState(() {
        _categories = categories;
        _isLoading = false;
        _categoriesLoaded = true;
      });

      debugPrint('✅ Categorías cargadas: ${categories.length}');
    } catch (e) {
      setState(() {
        _errorMessage = 'Error al cargar categorías: $e';
        _isLoading = false;
      });
      debugPrint('❌ Error cargando categorías: $e');
    }
  }

  Future<void> _loadUsdRate() async {
    setState(() {
      _isLoadingUsdRate = true;
    });

    try {
      final rate = await CurrencyService.getUsdRate();
      setState(() {
        _usdRate = rate;
        _isLoadingUsdRate = false;
      });
    } catch (e) {
      print('❌ Error loading USD rate: $e');
      setState(() {
        _usdRate = 420.0;
        _isLoadingUsdRate = false;
      });
    }
  }

  Future<void> _loadOfflineModeSettings() async {
    final isEnabled = await _preferencesService.isOfflineModeEnabled();
    if (mounted) {
      setState(() {
        _isOfflineModeEnabled = isEnabled;
      });
    }
  }

  // ---------- Global search ----------
  void _toggleSearch() {
    setState(() {
      _isSearchOpen = !_isSearchOpen;
      _searchResults = [];
      _searchController.clear();
    });

    if (_isSearchOpen) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _searchFocusNode.requestFocus();
      });
    } else {
      _searchDebounce?.cancel();
      _isSearchingProducts = false;
      FocusScope.of(context).unfocus();
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 320), () {
      _performProductSearch(value);
    });
  }

  Future<void> _performProductSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearchingProducts = false;
      });
      return;
    }

    if (_isOfflineModeEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '🔌 Modo offline activo: la búsqueda global requiere conexión',
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    setState(() {
      _isSearchingProducts = true;
    });

    try {
      final results = await _productService.searchProducts(
        query: trimmed,
        categoryId: null,
        soloDisponibles: false,
      );
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _isSearchingProducts = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSearchingProducts = false;
        _searchResults = [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error al buscar productos: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        style: const TextStyle(color: Colors.black87),
        cursorColor: const Color(0xFF4A90E2),
        decoration: InputDecoration(
          hintText: 'Buscar productos...',
          hintStyle: TextStyle(color: Colors.grey[500]),
          border: InputBorder.none,
          prefixIcon: const Icon(Icons.search, color: Color(0xFF4A90E2)),
          suffixIcon:
              _searchController.text.isNotEmpty
                  ? IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _searchResults = [];
                      });
                    },
                  )
                  : null,
        ),
        textInputAction: TextInputAction.search,
        onSubmitted: _performProductSearch,
      ),
    );
  }

  Widget _buildSearchResultsOverlay() {
    final media = MediaQuery.of(context);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        ignoring: false,
        child: Container(
          color: Colors.black.withOpacity(0.25),
          child: SafeArea(
            top: false,
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                width: media.size.width,
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const SizedBox(width: 12),
                        const Icon(Icons.explore, color: Color(0xFF4A90E2)),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Búsqueda global',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: Color(0xFF2C3E50),
                            ),
                          ),
                        ),
                        if (_isSearchingProducts)
                          const Padding(
                            padding: EdgeInsets.only(right: 12),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF4A90E2),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_searchController.text.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Text(
                          'Escribe para buscar productos por nombre o descripción.',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      )
                    else if (_searchResults.isEmpty && !_isSearchingProducts)
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Text(
                          'Sin resultados. Prueba con otro término.',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: media.size.height * 0.55,
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            final product = _searchResults[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: const Color(
                                  0xFF4A90E2,
                                ).withOpacity(0.12),
                                child: Icon(
                                  product.esServicio
                                      ? Icons.room_service
                                      : (product.esElaborado
                                          ? Icons.restaurant_menu
                                          : Icons.shopping_bag),
                                  color: const Color(0xFF4A90E2),
                                ),
                              ),
                              title: Text(
                                product.denominacion,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF2C3E50),
                                ),
                              ),
                              subtitle: Text(
                                product.descripcion ?? 'Sin descripción',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '\$${product.precio.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF4A90E2),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          (product.cantidad > 0
                                              ? Colors.green[50]
                                              : Colors.red[50]) ??
                                          Colors.grey[100],
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color:
                                            (product.cantidad > 0
                                                ? Colors.green[300]
                                                : Colors.red[300]) ??
                                            Colors.grey,
                                      ),
                                    ),
                                    child: Text(
                                      product.cantidad > 0
                                          ? 'Stock: ${product.cantidad}'
                                          : 'Sin stock',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color:
                                            product.cantidad > 0
                                                ? Colors.green[700]
                                                : Colors.red[700],
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () {
                                _toggleSearch();
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (_) => ProductDetailsScreen(
                                          product: product,
                                          categoryColor: const Color(
                                            0xFF4A90E2,
                                          ),
                                        ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUsdRateChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: const Color(0xFF4A90E2).withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.attach_money, size: 20, color: Color(0xFF4A90E2)),
          const SizedBox(width: 6),
          _isLoadingUsdRate
              ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF4A90E2),
                ),
              )
              : Text(
                'USD: \$${_usdRate.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2C3E50),
                ),
              ),
        ],
      ),
    );
  }

  int _getCrossAxisCount(double screenWidth) {
    if (screenWidth > 1400) return 6;
    if (screenWidth > 1200) return 5;
    if (screenWidth > 900) return 4;
    if (screenWidth > 600) return 3;
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          'Categorías - VentIQ POS',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 22,
          ),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF4A90E2),
        elevation: 2,
        shadowColor: const Color(0xFF4A90E2).withOpacity(0.3),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom:
            _isSearchOpen
                ? PreferredSize(
                  preferredSize: const Size.fromHeight(72),
                  child: Container(
                    color: const Color(0xFF4A90E2),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: _buildSearchBar(),
                  ),
                )
                : null,
        actions: [
          IconButton(
            icon: Icon(
              _isSearchOpen ? Icons.close : Icons.search,
              color: Colors.white,
              size: 26,
            ),
            tooltip: 'Buscar productos',
            onPressed: _toggleSearch,
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(
              Icons.qr_code_scanner,
              color: Colors.white,
              size: 28,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const BarcodeScannerScreen(),
                ),
              );
            },
            tooltip: 'Escanear código de barras',
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white, size: 26),
            onPressed: () => _loadCategories(forceRefresh: true),
            tooltip: 'Actualizar categorías',
          ),
          const SizedBox(width: 8),
          Builder(
            builder:
                (context) => IconButton(
                  icon: const Icon(Icons.menu, color: Colors.white, size: 28),
                  onPressed: () => Scaffold.of(context).openEndDrawer(),
                  tooltip: 'Menú',
                ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          _buildBody(screenSize),
          if (_isSearchOpen) _buildSearchResultsOverlay(),
          // USD Rate Chip positioned at bottom left
          Positioned(bottom: 24, left: 24, child: _buildUsdRateChip()),
        ],
      ),
      endDrawer: const AppDrawer(),
      bottomNavigationBar: AppBottomNavigation(
        currentIndex: 0,
        onTap: _onBottomNavTap,
      ),
      floatingActionButton: const SalesMonitorFAB(),
    );
  }

  Widget _buildBody(Size screenSize) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF4A90E2), strokeWidth: 3),
            SizedBox(height: 20),
            Text(
              'Cargando categorías...',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 80, color: Colors.grey[400]),
              const SizedBox(height: 24),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => _loadCategories(forceRefresh: true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4A90E2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Reintentar',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_categories.isEmpty) {
      return Center(
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.category_outlined, size: 80, color: Colors.grey),
              SizedBox(height: 24),
              Text(
                'No hay categorías disponibles',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadCategories(forceRefresh: true),
      color: const Color(0xFF4A90E2),
      child: Container(
        padding: const EdgeInsets.all(24.0),
        child: GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _getCrossAxisCount(screenSize.width),
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 1.1,
          ),
          itemCount: _categories.length,
          itemBuilder: (context, index) {
            final category = _categories[index];
            return _CategoryWebCard(
              id: category.id,
              name: category.name,
              imageUrl: category.imageUrl,
              color: category.color,
            );
          },
        ),
      ),
    );
  }

  void _onBottomNavTap(int index) {
    switch (index) {
      case 0:
        setState(() {});
        break;
      case 1:
        Navigator.pushNamed(context, '/preorder').then((_) {
          setState(() {});
        });
        break;
      case 2:
        Navigator.pushNamed(context, '/orders').then((_) {
          setState(() {});
        });
        break;
      case 3:
        Navigator.pushNamed(context, '/settings').then((_) {
          setState(() {});
        });
        break;
    }
  }
}

class _CategoryWebCard extends StatefulWidget {
  final int id;
  final String name;
  final String? imageUrl;
  final Color color;

  const _CategoryWebCard({
    required this.id,
    required this.name,
    this.imageUrl,
    required this.color,
  });

  @override
  State<_CategoryWebCard> createState() => _CategoryWebCardState();
}

class _CategoryWebCardState extends State<_CategoryWebCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _elevationAnimation;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _elevationAnimation = Tween<double>(begin: 4.0, end: 12.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onHover(bool isHovered) {
    setState(() => _isHovered = isHovered);
    if (isHovered) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  }

  void _onTap() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => ProductsScreen(
              categoryId: widget.id,
              categoryName: widget.name,
              categoryColor: widget.color,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: MouseRegion(
            onEnter: (_) => _onHover(true),
            onExit: (_) => _onHover(false),
            child: GestureDetector(
              onTap: _onTap,
              child: Container(
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withOpacity(0.3),
                      blurRadius: _elevationAnimation.value,
                      offset: Offset(0, _elevationAnimation.value / 2),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    // Background pattern
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              widget.color,
                              widget.color.withOpacity(0.8),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Image
                    if (widget.imageUrl != null)
                      Positioned(
                        bottom: -10,
                        right: -10,
                        child: Transform.rotate(
                          angle: -0.1,
                          child: Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                widget.imageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      _getCategoryIcon(widget.name),
                                      size: 50,
                                      color: Colors.white,
                                    ),
                                  );
                                },
                                loadingBuilder: (
                                  context,
                                  child,
                                  loadingProgress,
                                ) {
                                  if (loadingProgress == null) return child;
                                  return Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Center(
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),

                    // Category name
                    Positioned(
                      top: 20,
                      left: 20,
                      right: 20,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.5,
                              shadows: [
                                Shadow(
                                  offset: Offset(0, 2),
                                  blurRadius: 4,
                                  color: Colors.black26,
                                ),
                              ],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Ver productos',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Hover effect overlay
                    if (_isHovered)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: Colors.white.withOpacity(0.1),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  IconData _getCategoryIcon(String categoryName) {
    switch (categoryName.toLowerCase()) {
      case 'bebidas':
        return Icons.local_drink;
      case 'snacks':
        return Icons.fastfood;
      case 'lácteos':
        return Icons.icecream;
      case 'panadería':
        return Icons.bakery_dining;
      case 'limpieza':
        return Icons.cleaning_services;
      case 'salud':
        return Icons.health_and_safety;
      default:
        return Icons.category;
    }
  }
}
