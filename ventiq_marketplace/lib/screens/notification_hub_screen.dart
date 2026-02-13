import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../services/category_service.dart';
import '../services/marketplace_service.dart';
import '../services/notification_service.dart';
import '../widgets/notifications_panel.dart';
import '../widgets/product_card.dart';
import 'product_detail_screen.dart';

class NotificationHubScreen extends StatefulWidget {
  const NotificationHubScreen({super.key});

  @override
  State<NotificationHubScreen> createState() => _NotificationHubScreenState();
}

class _NotificationHubScreenState extends State<NotificationHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _didApplyInitialTab = false;

  final MarketplaceService _marketplaceService = MarketplaceService();
  final NotificationService _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notificationService.initializeUserNotifications();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_didApplyInitialTab) return;
    final args = ModalRoute.of(context)?.settings.arguments;

    int? initialTabIndex;
    if (args is int) {
      initialTabIndex = args;
    } else if (args is Map) {
      final raw = args['initialTabIndex'];
      if (raw is int) {
        initialTabIndex = raw;
      } else if (raw != null) {
        initialTabIndex = int.tryParse(raw.toString());
      }
    }

    if (initialTabIndex != null &&
        initialTabIndex >= 0 &&
        initialTabIndex <= 1) {
      _didApplyInitialTab = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _tabController.index = initialTabIndex!;
      });
    } else {
      _didApplyInitialTab = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = AppTheme.getAccentColor(context);

    return Scaffold(
      backgroundColor: AppTheme.getBackgroundColor(context),
      appBar: AppBar(
        title: const Text('Hub'),
        backgroundColor: isDark ? AppTheme.darkSurfaceColor : AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: accentColor,
          indicatorWeight: 3,
          tabs: const [
            Tab(text: 'Recomendados', icon: Icon(Icons.recommend_outlined)),
            Tab(
              text: 'Notificaciones',
              icon: Icon(Icons.notifications_outlined),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _RecommendedProductsTab(marketplaceService: _marketplaceService),
          NotificationsPanel(
            notificationService: _notificationService,
            embedded: true,
          ),
        ],
      ),
    );
  }
}

class _RecommendedProductsTab extends StatefulWidget {
  final MarketplaceService marketplaceService;

  const _RecommendedProductsTab({required this.marketplaceService});

  @override
  State<_RecommendedProductsTab> createState() =>
      _RecommendedProductsTabState();
}

class _RecommendedProductsTabState extends State<_RecommendedProductsTab> {
  static const int _pageSize = 20;

  final ScrollController _scrollController = ScrollController();
  final CategoryService _categoryService = CategoryService();

  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _categories = [];
  bool _isLoadingCategories = true;
  int? _selectedCategoryId;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadCategories();
    _loadProducts(reset: true);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _isLoading || _isLoadingMore) return;

    final threshold = 240.0;
    final remaining =
        _scrollController.position.maxScrollExtent - _scrollController.offset;
    if (remaining <= threshold) {
      _loadProducts();
    }
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await _categoryService.getAllCategories();
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _isLoadingCategories = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingCategories = false;
      });
    }
  }

  void _onCategorySelected(int? categoryId) {
    if (_selectedCategoryId == categoryId) return;

    setState(() {
      _selectedCategoryId = categoryId;
    });

    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }

    _loadProducts(reset: true);
  }

  bool _matchesCategory(Map<String, dynamic> product, int? selectedCategoryId) {
    if (selectedCategoryId == null) return true;

    final raw = product['id_categoria'];
    if (raw == null) return false;

    final parsedId = raw is int
        ? raw
        : raw is num
        ? raw.toInt()
        : int.tryParse(raw.toString());

    return parsedId == selectedCategoryId;
  }

  Future<void> _loadProducts({bool reset = false}) async {
    if (_isLoadingMore) return;

    final selectedCategoryId = _selectedCategoryId;
    if (reset) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _products = [];
        _offset = 0;
        _hasMore = true;
      });
    } else {
      setState(() {
        _isLoadingMore = true;
        _errorMessage = null;
      });
    }

    try {
      var localOffset = _offset;
      var localHasMore = _hasMore;
      var foundAnyForFilter = false;
      final batch = <Map<String, dynamic>>[];

      while (true) {
        final items = await widget.marketplaceService.getRecommendedProducts(
          limit: _pageSize,
          offset: localOffset,
        );

        final filtered = items
            .where((p) => _matchesCategory(p, selectedCategoryId))
            .toList();
        batch.addAll(filtered);
        foundAnyForFilter = foundAnyForFilter || filtered.isNotEmpty;

        localOffset += items.length;
        localHasMore = items.length >= _pageSize;

        if (selectedCategoryId == null) break;
        if (foundAnyForFilter) break;
        if (!localHasMore) break;
        if (items.isEmpty) break;
      }

      if (!mounted) return;

      setState(() {
        _products = [..._products, ...batch];
        _offset = localOffset;
        _hasMore = localHasMore;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  void _openProductDetails(Map<String, dynamic> product) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductDetailScreen(product: product),
      ),
    );
  }

  Widget _buildCategoryFilter() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = AppTheme.getAccentColor(context);
    final cardColor = AppTheme.getCardColor(context);
    final textSecondary = AppTheme.getTextSecondaryColor(context);

    final chips = <Map<String, dynamic>>[
      {'id': null, 'denominacion': 'Todas'},
      if (!_isLoadingCategories) ..._categories,
    ];

    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.paddingM,
          vertical: AppTheme.paddingS,
        ),
        itemBuilder: (context, index) {
          final category = chips[index];
          final rawId = category['id'];
          final int? categoryId = rawId == null
              ? null
              : rawId is int
              ? rawId
              : rawId is num
              ? rawId.toInt()
              : int.tryParse(rawId.toString());
          final label = category['denominacion']?.toString() ?? 'Sin categoría';
          final isSelected = _selectedCategoryId == categoryId;

          return ChoiceChip(
            label: Text(label),
            selected: isSelected,
            onSelected: (_) => _onCategorySelected(categoryId),
            showCheckmark: false,
            selectedColor: accentColor,
            backgroundColor: cardColor,
            side: BorderSide(
              color: isSelected ? accentColor : (isDark ? AppTheme.darkDividerColor : Colors.grey.shade300),
            ),
            labelStyle: TextStyle(
              color: isSelected ? Colors.white : textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: chips.length,
      ),
    );
  }

  Widget _buildEmptyState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = AppTheme.getTextPrimaryColor(context);
    final textSecondary = AppTheme.getTextSecondaryColor(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.paddingL),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.recommend_outlined,
              size: 72,
              color: isDark ? AppTheme.darkTextHint : Colors.grey.shade500,
            ),
            const SizedBox(height: 16),
            Text(
              'Sin recomendaciones aún',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Suscríbete a tiendas o productos para recibir recomendaciones personalizadas.',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    final textPrimary = AppTheme.getTextPrimaryColor(context);
    final textSecondary = AppTheme.getTextSecondaryColor(context);
    final accentColor = AppTheme.getAccentColor(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.paddingL),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 68, color: Colors.red.shade400),
            const SizedBox(height: 12),
            Text(
              'No se pudieron cargar los recomendados',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? '',
              style: TextStyle(
                fontSize: 12,
                color: textSecondary,
                height: 1.3,
              ),
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _loadProducts(reset: true),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => _loadProducts(reset: true),
      color: AppTheme.primaryColor,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildCategoryFilter()),
          if (_isLoading && _products.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_errorMessage != null && _products.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: _buildErrorState())
          else if (_products.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: _buildEmptyState())
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.paddingM,
                AppTheme.paddingS,
                AppTheme.paddingM,
                AppTheme.paddingL,
              ),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final product = _products[index];
                  final metadata = product['metadata'] as Map<String, dynamic>?;

                  return ProductCard(
                    productName: product['denominacion'] ?? 'Sin nombre',
                    price: (product['precio_venta'] ?? 0).toDouble(),
                    category:
                        product['categoria_nombre']?.toString() ?? 'Producto',
                    imageUrl: product['imagen'],
                    storeName: metadata?['denominacion_tienda'] ?? 'Sin tienda',
                    rating: (metadata?['rating_promedio'] ?? 0.0).toDouble(),
                    salesCount: 0,
                    width: null,
                    onTap: () => _openProductDetails(product),
                  );
                }, childCount: _products.length),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: AppTheme.paddingM,
                  mainAxisSpacing: AppTheme.paddingM,
                  mainAxisExtent: 290,
                ),
              ),
            ),
          if (_isLoadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(AppTheme.paddingM),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}
