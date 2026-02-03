import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import '../models/product.dart';
import '../services/product_service.dart';
import '../services/user_preferences_service.dart';
import '../services/currency_service.dart';
import '../utils/promotion_rules.dart';
import 'product_details_screen.dart';
import 'barcode_scanner_screen.dart';
import 'assign_supplier_screen.dart';
import '../widgets/bottom_navigation.dart';
import '../widgets/sales_monitor_fab.dart';
import '../widgets/marquee_text.dart';
import '../utils/connection_error_handler.dart';
import '../widgets/notification_widget.dart';
import '../widgets/sync_status_chip.dart';

// Configuración personalizada de scroll para web
class WebScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
  };
}

class ProductsScreen extends StatefulWidget {
  final int categoryId;
  final String categoryName;
  final Color categoryColor;

  const ProductsScreen({
    Key? key,
    required this.categoryId,
    required this.categoryName,
    required this.categoryColor,
  }) : super(key: key);

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  Map<String, List<Product>> productsBySubcategory = {};
  Map<String, List<Product>> filteredProductsBySubcategory = {};
  bool isLoading = true;
  String? errorMessage;
  final ProductService _productService = ProductService();
  final UserPreferencesService _userPreferencesService =
      UserPreferencesService();
  bool _isLimitDataUsageEnabled = false; // Para el modo de ahorro de datos
  bool _isConnectionError = false; // Para detectar errores de conexión
  bool _showRetryWidget = false; // Para mostrar el widget de reconexión

  // Search functionality
  bool _isSearchVisible = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';

  // Promotion data
  Map<String, dynamic>? _promotionData;

  // Cache para evitar peticiones frecuentes
  static final Map<int, Map<String, List<Product>>> _productsCache = {};
  static final Map<int, DateTime> _cacheTimestamps = {};
  static const Duration _cacheExpiration = Duration(minutes: 5);

  // USD rate data
  double _usdRate = 0.0;
  bool _isLoadingUsdRate = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadPromotionData();
    _loadUsdRate();
    _loadDataUsageSettings();
    // Asegurar que se inicialice filteredProductsBySubcategory
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProducts();
    });
  }

  Future<void> _loadDataUsageSettings() async {
    final isEnabled = await _userPreferencesService.isLimitDataUsageEnabled();
    if (mounted) {
      setState(() {
        _isLimitDataUsageEnabled = isEnabled;
      });
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _loadPromotionData() async {
    final promotionData = await _userPreferencesService.getPromotionData();
    print('🎯 ProductsScreen: Promotion data loaded: $promotionData');
    setState(() {
      _promotionData = promotionData;
    });
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
        _usdRate = 420.0; // Default fallback rate
        _isLoadingUsdRate = false;
      });
    }
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
      _filterProducts();
    });
  }

  void _filterProducts() {
    if (_searchQuery.isEmpty) {
      filteredProductsBySubcategory = Map.from(productsBySubcategory);
    } else {
      filteredProductsBySubcategory = {};
      productsBySubcategory.forEach((subcategory, products) {
        final filteredProducts =
            products.where((product) {
              return product.denominacion.toLowerCase().contains(
                    _searchQuery,
                  ) ||
                  product.descripcion?.toLowerCase().contains(_searchQuery) ==
                      true;
            }).toList();

        if (filteredProducts.isNotEmpty) {
          filteredProductsBySubcategory[subcategory] = filteredProducts;
        }
      });
    }

    // Debug logging
    print(
      '🔍 Filter applied: query="$_searchQuery", total filtered products: ${filteredProductsBySubcategory.values.fold(0, (sum, list) => sum + list.length)}',
    );
  }

  void _showSearchOverlay() {
    setState(() {
      _isSearchVisible = true;
    });

    // Focus the search field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_searchFocusNode);
    });
  }

  void _hideSearchOverlay() {
    setState(() {
      _isSearchVisible = false;
    });
    FocusScope.of(context).unfocus();
  }

  void _clearSearch() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _filterProducts();
    });
  }

  void _toggleSearch() {
    if (_isSearchVisible) {
      _hideSearchOverlay();
    } else {
      _showSearchOverlay();
    }
  }

  void _loadProducts({bool forceRefresh = false}) async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      // Verificar si el modo offline está activado
      final isOfflineModeEnabled =
          await _userPreferencesService.isOfflineModeEnabled();

      // Verificar caché si no es refresh forzado y estamos online
      if (!forceRefresh &&
          !isOfflineModeEnabled &&
          _isCacheValid(widget.categoryId)) {
        final cachedProducts = _productsCache[widget.categoryId]!;
        setState(() {
          productsBySubcategory = cachedProducts;
          filteredProductsBySubcategory = Map.from(cachedProducts);
          isLoading = false;
        });
        _filterProducts(); // Aplicar filtro actual si existe
        return;
      }

      Map<String, List<Product>> products;

      if (isOfflineModeEnabled) {
        print('🔌 Modo offline - Cargando productos desde cache...');

        // Cargar datos offline
        final offlineData = await _userPreferencesService.getOfflineData();

        if (offlineData != null && offlineData['products'] != null) {
          final productsData = offlineData['products'] as Map<String, dynamic>;

          // Buscar productos de esta categoría
          final categoryKey = widget.categoryId.toString();

          if (productsData.containsKey(categoryKey)) {
            final categoryProducts = productsData[categoryKey] as List<dynamic>;

            // Agrupar productos por subcategoría
            products = {};
            for (var prodData in categoryProducts) {
              final subcategory =
                  prodData['subcategoria'] as String? ?? 'General';

              // Crear objeto Product desde datos offline
              final product = Product(
                id: prodData['id'] as int,
                denominacion: prodData['denominacion'] as String,
                descripcion: prodData['descripcion'] as String?,
                foto: prodData['foto'] as String?,
                precio: (prodData['precio'] as num).toDouble(),
                cantidad: prodData['cantidad'] as num,
                categoria: prodData['categoria'] as String,
                esRefrigerado: false,
                esFragil: false,
                esPeligroso: false,
                esVendible: true,
                esComprable: true,
                esInventariable: true,
                esPorLotes: false,
                esElaborado: false,
                esServicio: false,
                variantes: [],
              );

              if (!products.containsKey(subcategory)) {
                products[subcategory] = [];
              }
              products[subcategory]!.add(product);
            }

            print(
              '✅ Productos cargados desde cache offline: ${categoryProducts.length}',
            );
          } else {
            products = {};
            print('⚠️ No hay productos para esta categoría en cache offline');
          }
        } else {
          throw Exception('No hay productos sincronizados en modo offline');
        }
      } else {
        print('🌐 Modo online - Cargando productos desde Supabase...');
        print('🔄 Loading products for category ${widget.categoryId}');
        products = await _productService.getProductsByCategory(
          widget.categoryId,
        );
        print(
          '✅ Loaded ${products.values.fold(0, (sum, list) => sum + list.length)} products',
        );
      }

      // Guardar en caché
      _productsCache[widget.categoryId] = products;
      _cacheTimestamps[widget.categoryId] = DateTime.now();

      setState(() {
        productsBySubcategory = products;
        filteredProductsBySubcategory = Map.from(products);
        isLoading = false;
      });

      // Aplicar filtro actual si existe
      _filterProducts();
    } catch (e, stackTrace) {
      print('❌ Error loading products: $e $stackTrace');

      final isConnectionError = ConnectionErrorHandler.isConnectionError(e);

      setState(() {
        _isConnectionError = isConnectionError;
        errorMessage =
            isConnectionError
                ? ConnectionErrorHandler.getConnectionErrorMessage()
                : ConnectionErrorHandler.getGenericErrorMessage(e);
        isLoading = false;
        _showRetryWidget = isConnectionError;
      });

      debugPrint('🔍 Es error de conexión: $isConnectionError');
    }
  }

  bool _isCacheValid(int categoryId) {
    if (!_productsCache.containsKey(categoryId) ||
        !_cacheTimestamps.containsKey(categoryId)) {
      return false;
    }

    final cacheTime = _cacheTimestamps[categoryId]!;
    final now = DateTime.now();
    return now.difference(cacheTime) < _cacheExpiration;
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
        title: Text(
          widget.categoryName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          if (_isLimitDataUsageEnabled)
            IconButton(
              icon: const Icon(
                Icons.data_saver_on,
                color: Colors.orange,
                size: 24,
              ),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      '📱 Modo ahorro de datos activado - Las imágenes no se cargan para ahorrar datos',
                    ),
                    backgroundColor: Colors.orange,
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              tooltip: 'Modo ahorro de datos activado',
            ),
          const NotificationWidget(),
          IconButton(
            icon: const Icon(
              Icons.local_shipping,
              color: Colors.white,
              size: 28,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) => AssignSupplierScreen(
                        categoryId: widget.categoryId,
                        categoryName: widget.categoryName,
                      ),
                ),
              );
            },
            tooltip: 'Asignar proveedor',
          ),
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white, size: 28),
            onPressed: _toggleSearch,
            tooltip: 'Buscar productos',
          ),
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
        ],
      ),
      bottomNavigationBar: AppBottomNavigation(
        currentIndex: 0, // No tab selected since this is a detail screen
        onTap: _onBottomNavTap,
      ),
      floatingActionButton: const SalesMonitorFAB(),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFFF8F9FA),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child:
                isLoading
                    ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(
                            color: widget.categoryColor,
                            strokeWidth: 3,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Cargando productos...',
                            style: TextStyle(
                              fontSize: 16,
                              color: widget.categoryColor,
                            ),
                          ),
                        ],
                      ),
                    )
                    : errorMessage != null
                    ? _showRetryWidget
                        ? ConnectionRetryWidget(
                          message: errorMessage!,
                          onRetry: () => _loadProducts(forceRefresh: true),
                        )
                        : Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 80,
                                color: Colors.red.withOpacity(0.3),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                errorMessage!,
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.red,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed:
                                    () => _loadProducts(forceRefresh: true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: widget.categoryColor,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Reintentar'),
                              ),
                            ],
                          ),
                        )
                    : filteredProductsBySubcategory.isEmpty
                    ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 80,
                            color: widget.categoryColor.withOpacity(0.3),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isNotEmpty
                                ? 'No se encontraron productos'
                                : 'No hay productos disponibles',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: widget.categoryColor,
                            ),
                          ),
                          if (_searchQuery.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Intenta con otros términos de búsqueda',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ],
                      ),
                    )
                    : RefreshIndicator(
                      onRefresh: () async => _loadProducts(forceRefresh: true),
                      color: widget.categoryColor,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        itemCount: filteredProductsBySubcategory.keys.length,
                        itemBuilder: (context, index) {
                          final subcategory = filteredProductsBySubcategory.keys
                              .elementAt(index);
                          final products =
                              filteredProductsBySubcategory[subcategory]!;
                          return _SubcategorySection(
                            title: subcategory,
                            products: products,
                            categoryColor: widget.categoryColor,
                            promotionData: _promotionData,
                            isLimitDataUsageEnabled: _isLimitDataUsageEnabled,
                          );
                        },
                      ),
                    ),
          ),
          // Floating search overlay
          if (_isSearchVisible)
            GestureDetector(
              onTap: _hideSearchOverlay,
              child: Container(
                color: Colors.black.withOpacity(0.5),
                child: Center(
                  child: GestureDetector(
                    onTap:
                        () {}, // Prevent closing when tapping on the search card
                    child: Container(
                      margin: const EdgeInsets.all(20),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.search,
                                color: widget.categoryColor,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: _searchController,
                                  focusNode: _searchFocusNode,
                                  autofocus: true,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _hideSearchOverlay(),
                                  decoration: InputDecoration(
                                    hintText: 'Buscar productos...',
                                    border: InputBorder.none,
                                    hintStyle: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 16,
                                    ),
                                  ),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Color(0xFF2C3E50),
                                  ),
                                ),
                              ),
                              if (_searchQuery.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.backspace_outlined),
                                  onPressed: _clearSearch,
                                  color: Colors.grey[600],
                                  tooltip: 'Limpiar búsqueda',
                                ),
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: _hideSearchOverlay,
                                color: Colors.grey[600],
                                tooltip: 'Cerrar búsqueda',
                              ),
                            ],
                          ),
                          if (_searchQuery.isNotEmpty) ...[
                            const Divider(),
                            Text(
                              '${filteredProductsBySubcategory.values.fold(0, (sum, products) => sum + products.length)} productos encontrados',
                              style: TextStyle(
                                color: widget.categoryColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          // USD Rate Chip positioned at bottom left
          Positioned(bottom: 16, left: 16, child: _buildUsdRateChip()),
          // Sync Status Chip positioned at bottom left
          const Positioned(bottom: 80, left: 16, child: SyncStatusChip()),
        ],
      ),
    );
  }

  Widget _buildUsdRateChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF4A90E2).withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.attach_money, size: 16, color: Color(0xFF4A90E2)),
          const SizedBox(width: 4),
          _isLoadingUsdRate
              ? const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF4A90E2),
                ),
              )
              : Text(
                'USD: \$${_usdRate.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2C3E50),
                ),
              ),
        ],
      ),
    );
  }

  void _onBottomNavTap(int index) {
    switch (index) {
      case 0: // Home (Categorías)
        Navigator.popUntil(context, (route) => route.isFirst);
        break;
      case 1: // Preorden
        Navigator.popUntil(context, (route) => route.isFirst);
        Navigator.pushNamed(context, '/preorder');
        break;
      case 2: // Órdenes
        Navigator.popUntil(context, (route) => route.isFirst);
        Navigator.pushNamed(context, '/orders');
        break;
      case 3: // Configuración
        Navigator.popUntil(context, (route) => route.isFirst);
        Navigator.pushNamed(context, '/settings');
        Navigator.pushNamed(context, '/settings');
        break;
    }
    ;
  }
}

// Nueva clase para las secciones de subcategorías al estilo Google Play Store
class _SubcategorySection extends StatefulWidget {
  final String title;
  final List<Product> products;
  final Color categoryColor;
  final Map<String, dynamic>? promotionData;
  final bool isLimitDataUsageEnabled;

  const _SubcategorySection({
    required this.title,
    required this.products,
    required this.categoryColor,
    this.promotionData,
    required this.isLimitDataUsageEnabled,
  });

  @override
  State<_SubcategorySection> createState() => _SubcategorySectionState();
}

class _SubcategorySectionState extends State<_SubcategorySection> {
  final ScrollController _scrollController = ScrollController();
  final FocusNode _scrollFocusNode = FocusNode();

  @override
  void dispose() {
    _scrollController.dispose();
    _scrollFocusNode.dispose();
    super.dispose();
  }

  double _scrollStep(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return (width * 0.85) + 16;
  }

  void _scrollBy(double offset) {
    if (!_scrollController.hasClients) return;

    final maxScrollExtent = _scrollController.position.maxScrollExtent;
    final targetOffset = (_scrollController.offset + offset).clamp(
      0.0,
      maxScrollExtent,
    );

    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, RawKeyEvent event) {
    if (!kIsWeb) {
      return KeyEventResult.ignored;
    }

    if (event is! RawKeyDownEvent) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _scrollBy(_scrollStep(context));
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _scrollBy(-_scrollStep(context));
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Widget _buildScrollButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
  }) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: IconButton(
        icon: Icon(icon, color: widget.categoryColor),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Título de la subcategoría
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2C3E50),
                ),
              ),
              TextButton(
                onPressed: () {
                  // TODO: Navegar a ver todos los productos de esta subcategoría
                },
                child: const Text(
                  '',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF4A90E2),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Lista horizontal de productos optimizada para espaciado
        _buildProductsList(context),
        const SizedBox(height: 24), // Espaciado entre secciones
      ],
    );
  }

  Widget _buildProductsList(BuildContext context) {
    final products = widget.products;

    // Si hay 3 o menos productos, mostrar en una sola columna sin espacios extra
    if (products.length <= 3) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children:
              products.asMap().entries.map((entry) {
                final index = entry.key;
                final product = entry.value;
                return Container(
                  margin: EdgeInsets.only(
                    bottom: index < products.length - 1 ? 6 : 0,
                  ),
                  child: _PlayStoreProductCard(
                    product: product,
                    categoryColor: widget.categoryColor,
                    promotionData: widget.promotionData,
                    isLimitDataUsageEnabled: widget.isLimitDataUsageEnabled,
                  ),
                );
              }).toList(),
        ),
      );
    }

    final listView = ListView.builder(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: kIsWeb ? 56 : 16),
      physics: const BouncingScrollPhysics(),
      cacheExtent: kIsWeb ? 200 : 300,
      addAutomaticKeepAlives: kIsWeb,
      addRepaintBoundaries: kIsWeb,
      itemCount:
          (products.length / 3).ceil(), // Número de columnas de 3 productos
      itemBuilder: (context, columnIndex) {
        // Calcular productos para esta columna
        final startIndex = columnIndex * 3;
        final endIndex = (startIndex + 3).clamp(0, products.length);
        final columnProducts = products.sublist(startIndex, endIndex);

        return Container(
          width: MediaQuery.of(context).size.width * 0.85, // 85% del ancho
          margin: const EdgeInsets.only(right: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children:
                columnProducts.asMap().entries.map((entry) {
                  final index = entry.key;
                  final product = entry.value;
                  return Container(
                    margin: EdgeInsets.only(
                      bottom:
                          index < columnProducts.length - 1
                              ? 6
                              : 0, // Solo espaciado entre cards, no al final
                    ),
                    child: _PlayStoreProductCard(
                      product: product,
                      categoryColor: widget.categoryColor,
                      promotionData: widget.promotionData,
                      isLimitDataUsageEnabled: widget.isLimitDataUsageEnabled,
                    ),
                  );
                }).toList(),
          ),
        );
      },
    );

    final listContent =
        kIsWeb
            ? ScrollConfiguration(
              behavior: WebScrollBehavior(),
              child: listView,
            )
            : listView;

    final focusableList = Focus(
      focusNode: _scrollFocusNode,
      canRequestFocus: kIsWeb,
      skipTraversal: !kIsWeb,
      onKey: _handleKeyEvent,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapDown: (_) {
          if (kIsWeb) {
            _scrollFocusNode.requestFocus();
          }
        },
        child: listContent,
      ),
    );

    if (!kIsWeb) {
      return SizedBox(
        height:
            228, // Altura optimizada: 3 productos (70px) + espaciado (6px entre cards) = 3*70 + 2*6 = 222px + padding
        child: focusableList,
      );
    }

    return SizedBox(
      height:
          228, // Altura optimizada: 3 productos (70px) + espaciado (6px entre cards) = 3*70 + 2*6 = 222px + padding
      child: Stack(
        children: [
          Positioned.fill(child: focusableList),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: _buildScrollButton(
                icon: Icons.chevron_left,
                tooltip: 'Mover productos a la izquierda',
                onPressed: () => _scrollBy(-_scrollStep(context)),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _buildScrollButton(
                icon: Icons.chevron_right,
                tooltip: 'Mover productos a la derecha',
                onPressed: () => _scrollBy(_scrollStep(context)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Nueva clase para las cards de producto al estilo Google Play Store
class _PlayStoreProductCard extends StatefulWidget {
  final Product product;
  final Color categoryColor;
  final Map<String, dynamic>? promotionData;
  final bool isLimitDataUsageEnabled;

  const _PlayStoreProductCard({
    required this.product,
    required this.categoryColor,
    this.promotionData,
    required this.isLimitDataUsageEnabled,
  });

  @override
  State<_PlayStoreProductCard> createState() => _PlayStoreProductCardState();
}

class _PlayStoreProductCardState extends State<_PlayStoreProductCard> {
  void _showOutOfStockDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: Row(
            children: [
              Icon(
                Icons.inventory_2_outlined,
                color: Colors.red[600],
                size: 28,
              ),
              const SizedBox(width: 12),
              const Text(
                'Producto Agotado',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.product.denominacion,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Este producto está actualmente agotado y no se puede agregar a la orden.',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: widget.categoryColor,
              ),
              child: const Text(
                'Entendido',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        );
      },
    );
  }

  Map<String, double> _calculatePromotionPrices() {
    final activePromotion = PromotionRules.pickPromotionForDisplay(
      productPromotions: null,
      globalPromotion: widget.promotionData,
      quantity: 1,
    );

    if (activePromotion == null) {
      print('🎯 No promotion data available');
      return {
        'precio_venta': widget.product.precio,
        'precio_oferta': widget.product.precio,
      };
    }

    final basePrice = PromotionRules.resolveBasePrice(
      unitPrice: widget.product.precio,
      basePrice: widget.product.precio,
      promotion: activePromotion,
    );

    final promotionPrices = PromotionRules.calculatePromotionPrices(
      basePrice: basePrice,
      promotion: activePromotion,
    );

    print('🎯 Promotion prices: $promotionPrices');

    return promotionPrices;
  }

  @override
  Widget build(BuildContext context) {
    final promotionPrices = _calculatePromotionPrices();
    final precioVenta = promotionPrices['precio_venta']!;
    final precioOferta = promotionPrices['precio_oferta']!;
    final activePromotion = PromotionRules.pickPromotionForDisplay(
      productPromotions: null,
      globalPromotion: widget.promotionData,
      quantity: 1,
    );
    final hasPromotion = activePromotion != null;

    return GestureDetector(
      onTap: () {
        // Verificar si el producto está agotado (solo para productos no elaborados ni servicios)
        if (!widget.product.esElaborado &&
            !widget.product.esServicio &&
            widget.product.cantidad <= 0) {
          _showOutOfStockDialog(context);
          return;
        }

        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) => ProductDetailsScreen(
                  product: widget.product,
                  categoryColor: widget.categoryColor,
                ),
          ),
        );
      },
      child: Container(
        height: 70, // Altura reducida sin la descripción
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            // Imagen del producto (pequeña, como icono de app)
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child:
                    widget.isLimitDataUsageEnabled
                        ? Image.asset(
                          'assets/no_image.png',
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.grey[200],
                              child: Icon(
                                Icons.shopping_bag,
                                size: 24,
                                color: Colors.grey[400],
                              ),
                            );
                          },
                        )
                        : Image.network(
                          widget.product.foto ?? '',
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.grey[200],
                              child: Icon(
                                Icons.shopping_bag,
                                size: 24,
                                color: Colors.grey[400],
                              ),
                            );
                          },
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              color: Colors.grey[200],
                              child: const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            );
                          },
                        ),
              ),
            ),
            const SizedBox(width: 16),
            // Información del producto
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Nombre del producto con efecto marquee
                  Flexible(
                    child: MarqueeText(
                      text: widget.product.denominacion,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF1F2937),
                        height: 1.2,
                      ),
                      scrollSpeed: 30.0,
                      pauseDuration: const Duration(seconds: 2),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Precio y rating/stock
                  Flexible(
                    child: Row(
                      children: [
                        if (hasPromotion && precioVenta != precioOferta) ...[
                          // Precio de venta (tachado si es mayor que oferta)
                          Flexible(
                            child: Text(
                              '\$${precioVenta.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: precioVenta > precioOferta ? 12 : 14,
                                color:
                                    precioVenta > precioOferta
                                        ? Colors.grey
                                        : widget.categoryColor,
                                decoration:
                                    precioVenta > precioOferta
                                        ? TextDecoration.lineThrough
                                        : null,
                                fontWeight:
                                    precioVenta > precioOferta
                                        ? FontWeight.normal
                                        : FontWeight.w600,
                                height: 1.2,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          // Precio de oferta (destacado si es menor que venta)
                          Flexible(
                            child: Text(
                              '\$${precioOferta.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: precioOferta < precioVenta ? 14 : 12,
                                fontWeight:
                                    precioOferta < precioVenta
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                color:
                                    precioOferta < precioVenta
                                        ? widget.categoryColor
                                        : Colors.grey,
                                decoration:
                                    precioOferta > precioVenta
                                        ? TextDecoration.lineThrough
                                        : null,
                                height: 1.2,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ] else
                          // Precio normal sin promoción
                          Flexible(
                            child: Text(
                              '\$${widget.product.precio.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: widget.categoryColor,
                                height: 1.2,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        const SizedBox(width: 6),
                        // Separador
                        Container(
                          width: 3,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.grey[400],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Estado de stock, elaborado o servicio
                        Flexible(
                          child: Text(
                            widget.product.esElaborado
                                ? '(elaborado)'
                                : widget.product.esServicio
                                ? '(servicio)'
                                : widget.product.cantidad > 0
                                ? 'Stock: ${widget.product.cantidad}'
                                : 'Agotado',
                            style: TextStyle(
                              fontSize: 13,
                              color:
                                  widget.product.esElaborado
                                      ? Colors.orange[600]
                                      : widget.product.esServicio
                                      ? Colors.blue[600]
                                      : widget.product.cantidad > 0
                                      ? Colors.green[600]
                                      : Colors.red[600],
                              height: 1.2,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
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
}

class _ProductCard extends StatefulWidget {
  final Product product;
  final Color categoryColor;

  const _ProductCard({required this.product, required this.categoryColor});

  @override
  State<_ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<_ProductCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    setState(() => _isPressed = true);
    _animationController.forward();
  }

  void _onTapUp(TapUpDetails details) {
    setState(() => _isPressed = false);
    _animationController.reverse();
    _onProductTap();
  }

  void _onTapCancel() {
    setState(() => _isPressed = false);
    _animationController.reverse();
  }

  void _onProductTap() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => ProductDetailsScreen(
              product: widget.product,
              categoryColor: widget.categoryColor,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTapDown: _onTapDown,
              onTapUp: _onTapUp,
              onTapCancel: _onTapCancel,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color:
                          _isPressed
                              ? widget.categoryColor.withOpacity(0.3)
                              : Colors.black.withOpacity(0.08),
                      blurRadius: _isPressed ? 15 : 10,
                      offset: Offset(0, _isPressed ? 2 : 4),
                      spreadRadius: _isPressed ? 2 : 0,
                    ),
                  ],
                  border:
                      _isPressed
                          ? Border.all(
                            color: widget.categoryColor.withOpacity(0.5),
                            width: 2,
                          )
                          : null,
                ),
                child: Row(
                  children: [
                    // Foto del producto - más compacta
                    Container(
                      width: 75,
                      height: 75,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: widget.categoryColor.withOpacity(0.1),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child:
                            widget.product.foto != null
                                ? Image.network(
                                  widget.product.foto!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            widget.categoryColor.withOpacity(
                                              0.3,
                                            ),
                                            widget.categoryColor.withOpacity(
                                              0.1,
                                            ),
                                          ],
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.inventory_2,
                                        color: widget.categoryColor,
                                        size: 32,
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
                                        gradient: LinearGradient(
                                          colors: [
                                            widget.categoryColor.withOpacity(
                                              0.2,
                                            ),
                                            widget.categoryColor.withOpacity(
                                              0.1,
                                            ),
                                          ],
                                        ),
                                      ),
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          color: widget.categoryColor,
                                          strokeWidth: 2,
                                          value:
                                              loadingProgress
                                                          .expectedTotalBytes !=
                                                      null
                                                  ? loadingProgress
                                                          .cumulativeBytesLoaded /
                                                      loadingProgress
                                                          .expectedTotalBytes!
                                                  : null,
                                        ),
                                      ),
                                    );
                                  },
                                )
                                : Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        widget.categoryColor.withOpacity(0.3),
                                        widget.categoryColor.withOpacity(0.1),
                                      ],
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.inventory_2,
                                    color: widget.categoryColor,
                                    size: 32,
                                  ),
                                ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Información del producto
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Denominación con efecto marquee
                          MarqueeText(
                            text: widget.product.denominacion,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2C3E50),
                            ),
                            scrollSpeed: 30.0,
                            pauseDuration: const Duration(seconds: 2),
                          ),
                          const SizedBox(height: 12),
                          // Cantidad y precio
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: widget.categoryColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  widget.product.esElaborado
                                      ? '(elaborado)'
                                      : widget.product.esServicio
                                      ? '(servicio)'
                                      : 'Stock: ${widget.product.cantidad}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: widget.categoryColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '\$${widget.product.precio.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: widget.categoryColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // Iconos de propiedades
                          Wrap(
                            spacing: 6,
                            runSpacing: 3,
                            children: [
                              if (widget.product.esRefrigerado)
                                _PropertyIcon(
                                  icon: Icons.ac_unit,
                                  color: Colors.blue,
                                  tooltip: 'Refrigerado',
                                ),
                              if (widget.product.esFragil)
                                _PropertyIcon(
                                  icon: Icons.warning_amber_rounded,
                                  color: Colors.orange,
                                  tooltip: 'Frágil',
                                ),
                              if (widget.product.esPeligroso)
                                _PropertyIcon(
                                  icon: Icons.dangerous,
                                  color: Colors.red,
                                  tooltip: 'Peligroso',
                                ),
                              if (widget.product.esVendible)
                                _PropertyIcon(
                                  icon: Icons.sell,
                                  color: Colors.green,
                                  tooltip: 'Vendible',
                                ),
                              if (widget.product.esComprable)
                                _PropertyIcon(
                                  icon: Icons.shopping_cart,
                                  color: Colors.purple,
                                  tooltip: 'Comprable',
                                ),
                              if (widget.product.esInventariable)
                                _PropertyIcon(
                                  icon: Icons.inventory,
                                  color: Colors.teal,
                                  tooltip: 'Inventariable',
                                ),
                              if (widget.product.esPorLotes)
                                _PropertyIcon(
                                  icon: Icons.batch_prediction,
                                  color: Colors.brown,
                                  tooltip: 'Por lotes',
                                ),
                            ],
                          ),
                        ],
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
}

class _PropertyIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;

  const _PropertyIcon({
    required this.icon,
    required this.color,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.3), width: 1),
        ),
        child: Icon(icon, size: 14, color: color),
      ),
    );
  }
}
