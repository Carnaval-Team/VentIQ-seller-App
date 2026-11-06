import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import '../models/home_catalogo.dart' show claveNombre;
import '../models/product.dart';
import '../services/order_service.dart';
import '../models/order.dart' show OrderItem;
import '../utils/desarme_bulto_local.dart';
import '../widgets/cocina_chip.dart';
import '../widgets/moneda_venta_chip.dart';
import '../services/product_service.dart';
import '../theme/ventiq_home_theme.dart';
import '../services/user_preferences_service.dart';
import '../services/currency_service.dart';
import '../services/moneda_venta_service.dart';
import '../utils/promotion_rules.dart';
import '../utils/price_utils.dart';
import '../utils/navigation_helper.dart';
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

  /// Si viene, la pantalla enseña **solo** esa subcategoría.
  ///
  /// Lo usa el drawer del Home al pedir "ver listado completo" desde una
  /// subcategoría: sin esto habría que abrir el listado entero de la categoría y
  /// dejar al vendedor buscando la sección que ya había elegido.
  ///
  /// Se compara por nombre y no por id porque esta pantalla ya agrupa por
  /// `subcategoria_nombre`; el id no llega hasta aquí.
  final String? subcategoriaNombre;

  const ProductsScreen({
    Key? key,
    required this.categoryId,
    required this.categoryName,
    required this.categoryColor,
    this.subcategoriaNombre,
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
  bool _isShowSkuEnabled = false;
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
    _loadShowSkuSetting();
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

  Future<void> _loadShowSkuSetting() async {
    final isEnabled = await _userPreferencesService.isShowSkuEnabled();
    if (mounted) {
      setState(() {
        _isShowSkuEnabled = isEnabled;
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
        _usdRate = 0.0;
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

    // Filtro por subcategoría (lo pide el drawer del Home). Se compara con
    // `claveNombre` para que "Bebidas frías" y "Bebidas Frías" sean lo mismo.
    final String? soloSub = widget.subcategoriaNombre;
    if (soloSub != null && soloSub.trim().isNotEmpty) {
      final String clave = claveNombre(soloSub);
      filteredProductsBySubcategory = Map<String, List<Product>>.fromEntries(
        filteredProductsBySubcategory.entries.where(
          (MapEntry<String, List<Product>> e) => claveNombre(e.key) == clave,
        ),
      );
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

      // Offline o dispositivo full-offline: siempre datos locales (sin sync/red).
      final useLocalData = await _userPreferencesService.shouldUseLocalData();

      // Verificar caché si no es refresh forzado y estamos online
      if (!forceRefresh && !useLocalData && _isCacheValid(widget.categoryId)) {
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

      if (useLocalData) {
        print(
          '🔌 Offline/full-offline - Cargando productos locales '
          '(categoría ${widget.categoryId})...',
        );
        products = await _productService.getProductsByCategory(
          widget.categoryId,
          forceLocal: true,
        );
        print(
          '✅ Productos locales: '
          '${products.values.fold(0, (sum, list) => sum + list.length)}',
        );
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
      backgroundColor: VentiqHomeTheme.surface,
      appBar: AppBar(
        backgroundColor: VentiqHomeTheme.primary,
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
          MonedaVentaChip(onChanged: (_) => setState(() {})),
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
              color: VentiqHomeTheme.surface,
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
                                color: VentiqHomeTheme.textSecondary,
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
                            showSku:
                                _isShowSkuEnabled ||
                                _userPreferencesService.isShowSkuEnabledSync,
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
                                  color: VentiqHomeTheme.textSecondary,
                                  tooltip: 'Limpiar búsqueda',
                                ),
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: _hideSearchOverlay,
                                color: VentiqHomeTheme.textSecondary,
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
        border: Border.all(color: VentiqHomeTheme.primary.withOpacity(0.3)),
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
          const Icon(
            Icons.attach_money,
            size: 16,
            color: VentiqHomeTheme.primary,
          ),
          const SizedBox(width: 4),
          _isLoadingUsdRate
              ? const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: VentiqHomeTheme.primary,
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
      case 0: // Home → /mesas si modo restaurante (sin cuenta activa), /categories si no
        NavigationHelper.goHome(context);
        break;
      case 1: // Carrito: preorden, o la cuenta de mesa abierta en restaurante
        NavigationHelper.goCarrito(context);
        break;
      case 2: // Órdenes
        Navigator.popUntil(context, (route) => route.isFirst);
        Navigator.pushNamed(context, '/orders');
        break;
      case 3: // Configuración
        Navigator.popUntil(context, (route) => route.isFirst);
        Navigator.pushNamed(context, '/settings');
        break;
    }
  }
}

// Nueva clase para las secciones de subcategorías al estilo Google Play Store
class _SubcategorySection extends StatefulWidget {
  final String title;
  final List<Product> products;
  final Color categoryColor;
  final Map<String, dynamic>? promotionData;
  final bool isLimitDataUsageEnabled;
  final bool showSku;

  const _SubcategorySection({
    required this.title,
    required this.products,
    required this.categoryColor,
    this.promotionData,
    required this.isLimitDataUsageEnabled,
    this.showSku = false,
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
              Expanded(
                child: Text(
                  widget.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2C3E50),
                  ),
                ),
              ),
              // Contador de productos de la subcategoría.
              //
              // Aquí había un TextButton con texto vacío y un onPressed sin
              // implementar: un "Ver todos" a medias que dejaba un área
              // pulsable invisible que no hacía nada. Se sustituye por el
              // conteo, que sí informa, en vez de prometer una navegación
              // que no existe.
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: widget.categoryColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: widget.categoryColor.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  widget.products.length == 1
                      ? '1 producto'
                      : '${widget.products.length} productos',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: widget.categoryColor,
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
                    showSku: widget.showSku,
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
                      showSku: widget.showSku,
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

    final double cardHeight = widget.showSku ? 84.0 : 70.0;
    final double columnHeight = cardHeight * 3 + 6 * 2; // 3 cards + 2 gaps

    if (!kIsWeb) {
      return SizedBox(height: columnHeight, child: focusableList);
    }

    return SizedBox(
      height: columnHeight,
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
  final bool showSku;

  const _PlayStoreProductCard({
    required this.product,
    required this.categoryColor,
    this.promotionData,
    required this.isLimitDataUsageEnabled,
    this.showSku = false,
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
                style: TextStyle(
                  fontSize: 14,
                  color: VentiqHomeTheme.textSecondary,
                ),
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
            widget.product.cantidadReal <= 0) {
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
        height:
            (widget.showSku &&
                    widget.product.sku != null &&
                    widget.product.sku!.isNotEmpty)
                ? 84
                : 70,
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
                              color: VentiqHomeTheme.border,
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
                              color: VentiqHomeTheme.border,
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
                              color: VentiqHomeTheme.border,
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
                  // SKU del producto (si está habilitado)
                  if (widget.showSku &&
                      widget.product.sku != null &&
                      widget.product.sku!.isNotEmpty)
                    Text(
                      'SKU: ${widget.product.sku}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: widget.categoryColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  // Nombre del producto con efecto marquee
                  Flexible(
                    child: MarqueeText(
                      text: widget.product.denominacion,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        color: VentiqHomeTheme.textPrimary,
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
                              MonedaVentaService.formatearPrecio(
                                precioVenta,
                                conSimbolo: true,
                              ),
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
                              MonedaVentaService.formatearPrecio(
                                precioOferta,
                                conSimbolo: true,
                              ),
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
                              MonedaVentaService.formatearPrecio(
                                widget.product.precio,
                                conSimbolo: true,
                              ),
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
                        // Estado de stock, elaborado o servicio.
                        // Si el plato va a cocina, manda la disponibilidad de
                        // esa estacion: "3 porciones" / "Hasta 5" / "Agotado".
                        Flexible(
                          child: Text(
                            widget.product.vaACocina
                                ? widget.product.etiquetaDisponibilidad
                                : widget.product.esElaborado
                                ? '(elaborado)'
                                : widget.product.esServicio
                                ? '(servicio)'
                                : _stockLabelConReservas(widget.product),
                            style: TextStyle(
                              fontSize: 13,
                              color:
                                  widget.product.vaACocina
                                      ? (widget.product.cantidadReal > 0 ||
                                              widget.product.ilimitado
                                          ? (widget.product.esPorTanda
                                              ? Colors.amber[800]
                                              : Colors.indigo[500])
                                          : Colors.red[600])
                                      : widget.product.esElaborado
                                      ? Colors.orange[600]
                                      : widget.product.esServicio
                                      ? Colors.blue[600]
                                      : widget.product.cantidadReal > 0
                                      ? Colors.green[600]
                                      : Colors.red[600],
                              height: 1.2,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Estacion de cocina: el vendedor necesita saber a
                        // donde va el plato antes de prometerlo al cliente.
                        if (widget.product.vaACocina &&
                            widget.product.cocina != null) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: CocinaChip(
                              product: widget.product,
                              compacto: true,
                            ),
                          ),
                        ],
                        if (widget.product.reservadoCarnaval > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange[300]!),
                            ),
                            child: Text(
                              'Reservado: ${widget.product.reservadoCarnaval}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.orange[800],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
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

/// Stock visible en la tarjeta descontando lo ya reservado en la orden.
///
/// Mismo pozo que en el detalle: las l�neas del carrito consumen unidades
/// base del producto, as� que el total convertible baja aunque el f�sico
/// siga igual. Solo afecta la etiqueta; el l�mite real lo impone el detalle.
String _stockLabelConReservas(Product product) {
  final items = OrderService().currentOrder?.items ?? <OrderItem>[];
  final reservadoBase = items
      .where((i) => i.producto.id == product.id)
      .fold<double>(0, (s, i) => s + i.cantidad * (i.presentacionFactor ?? 1));
  if (reservadoBase <= 0) return product.stockLabel();

  final mixto = product.stockMixto;
  if (mixto == null || mixto.isEmpty) return product.stockLabel();

  final disponibles = DesarmeBultoLocal.disponiblesDesdeDesglose(mixto);
  var baseTotal = 0.0;
  for (final f in mixto) {
    final cant = (f['cantidad'] as num?)?.toDouble() ?? 0;
    final factor = (f['factor_rel'] as num?)?.toDouble();
    baseTotal += cant * (factor == null || factor <= 0 ? 1 : factor);
  }
  final libre = math.max(0.0, baseTotal - reservadoBase);
  if (libre <= 0) return 'Agotado';

  final partes = <String>[];
  for (final f in mixto) {
    final id = (f['id_presentacion'] as num?)?.toInt();
    final factor = (f['factor_rel'] as num?)?.toDouble() ?? 1;
    final nombre = f['nombre']?.toString() ?? 'Presentaci�n';
    final disp = id != null ? (disponibles[id] ?? 0) : 0.0;
    final neta = (disponibles.isNotEmpty ? libre / factor : 0.0);
    partes.add('$nombre: ${_fmtDisponible(neta > disp ? neta : disp)}');
  }
  return 'Stock: ${_fmtDisponible(libre)} base\n${partes.join(' � ')}';
}

String _fmtDisponible(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
