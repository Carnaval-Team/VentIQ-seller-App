import 'package:flutter/material.dart';
import 'products_screen.dart';
import 'barcode_scanner_screen.dart';
import '../widgets/bottom_navigation.dart';
import '../widgets/app_drawer.dart';
import '../services/category_service.dart';
import '../services/user_preferences_service.dart';
import '../services/changelog_service.dart';
import '../services/currency_service.dart';
import '../widgets/changelog_dialog.dart';
import '../widgets/sales_monitor_fab.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen>
    with WidgetsBindingObserver {
  final CategoryService _categoryService = CategoryService();
  final UserPreferencesService _preferencesService = UserPreferencesService();
  final ChangelogService _changelogService = ChangelogService();
  List<Category> _categories = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _categoriesLoaded =
      false; // Flag para controlar si ya se cargaron las categorías
  bool _isLimitDataUsageEnabled = false; // Para el modo de ahorro de datos

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
    _loadDataUsageSettings();
  }
  
  Future<void> _loadDataUsageSettings() async {
    final isEnabled = await _preferencesService.isLimitDataUsageEnabled();
    if (mounted) {
      setState(() {
        _isLimitDataUsageEnabled = isEnabled;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh the screen when returning from other screens
      setState(() {});
    }
  }

  Future<void> _checkForChangelog() async {
    try {
      final isFirstTime = await _preferencesService.isFirstTimeOpening();

      if (isFirstTime) {
        // Wait a bit for the screen to load
        await Future.delayed(const Duration(milliseconds: 500));

        final changelog = await _changelogService.getLatestChangelog();
        if (changelog != null && mounted) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => ChangelogDialog(changelog: changelog),
          );

          // Save current app version to preferences
          await _preferencesService.saveAppVersion('1.0.0');
        }
      }
    } catch (e) {
      debugPrint('Error checking changelog: $e');
    }
  }

  Future<void> _loadCategories({bool forceRefresh = false}) async {
    // Si ya están cargadas y no es un refresh forzado, no hacer nada
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

      // Verificar si el modo offline está activado
      final isOfflineModeEnabled = await _preferencesService.isOfflineModeEnabled();
      
      List<Category> categories;
      
      if (isOfflineModeEnabled) {
        print('🔌 Modo offline - Cargando categorías desde cache...');
        
        // Cargar datos offline
        final offlineData = await _preferencesService.getOfflineData();
        
        if (offlineData != null && offlineData['categories'] != null) {
          final categoriesData = offlineData['categories'] as List<dynamic>;
          
          // Convertir datos JSON a objetos Category
          categories = categoriesData.map((catData) {
            return Category(
              id: catData['id'] as int,
              name: catData['name'] as String,
              imageUrl: catData['imageUrl'] as String,
              color: Color(catData['color'] as int),
            );
          }).toList();
          
          print('✅ Categorías cargadas desde cache offline: ${categories.length}');
        } else {
          throw Exception('No hay categorías sincronizadas en modo offline');
        }
      } else {
        print('🌐 Modo online - Cargando categorías desde Supabase...');
        categories = await _categoryService.getCategories();
        print('✅ Categorías cargadas desde Supabase: ${categories.length}');
      }

      setState(() {
        _categories = categories;
        _isLoading = false;
        _categoriesLoaded = true; // Marcar como cargadas
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
        _usdRate = 420.0; // Default fallback rate
        _isLoadingUsdRate = false;
      });
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          'Categorías',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF4A90E2),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
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
                    content: Text('📱 Modo ahorro de datos activado - Las imágenes no se cargan para ahorrar datos'),
                    backgroundColor: Colors.orange,
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              tooltip: 'Modo ahorro de datos activado',
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
      body: Stack(
        children: [
          _buildBody(),
          // USD Rate Chip positioned at bottom left
          Positioned(bottom: 16, left: 16, child: _buildUsdRateChip()),
        ],
      ),
      endDrawer: const AppDrawer(),
      bottomNavigationBar: AppBottomNavigation(
        currentIndex: 0, // Categorías tab
        onTap: _onBottomNavTap,
      ),
      floatingActionButton: const SalesMonitorFAB(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF4A90E2)),
            SizedBox(height: 16),
            Text(
              'Cargando categorías...',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _loadCategories(forceRefresh: true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A90E2),
                foregroundColor: Colors.white,
              ),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (_categories.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.category_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No hay categorías disponibles',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadCategories(forceRefresh: true),
      color: const Color(0xFF4A90E2),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.85,
          ),
          itemCount: _categories.length,
          itemBuilder: (context, index) {
            final category = _categories[index];
            return _CategoryCard(
              id: category.id,
              name: category.name,
              imageUrl: category.imageUrl,
              color: category.color,
              isLimitDataUsageEnabled: _isLimitDataUsageEnabled,
            );
          },
        ),
      ),
    );
  }

  void _onBottomNavTap(int index) {
    switch (index) {
      case 0: // Home (current)
        // Refresh the current screen to update badges
        setState(() {});
        break;
      case 1: // Preorden
        Navigator.pushNamed(context, '/preorder').then((_) {
          // Refresh when returning from preorder
          setState(() {});
        });
        break;
      case 2: // Órdenes
        Navigator.pushNamed(context, '/orders').then((_) {
          // Refresh when returning from orders
          setState(() {});
        });
        break;
      case 3: // Configuración
        Navigator.pushNamed(context, '/settings').then((_) {
          // Refresh when returning from settings
          setState(() {});
        });
        break;
    }
  }
}

class _CategoryCard extends StatefulWidget {
  final int id;
  final String name;
  final String? imageUrl;
  final Color color;
  final bool isLimitDataUsageEnabled;

  const _CategoryCard({
    required this.id,
    required this.name,
    this.imageUrl,
    required this.color,
    required this.isLimitDataUsageEnabled,
  });

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard>
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
    // Navigate to products list for this category
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

  void _onTapCancel() {
    setState(() => _isPressed = false);
    _animationController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: GestureDetector(
            onTapDown: _onTapDown,
            onTapUp: _onTapUp,
            onTapCancel: _onTapCancel,
            child: Container(
              decoration: BoxDecoration(
                color:
                    _isPressed ? widget.color.withOpacity(0.8) : widget.color,
                border: Border(
                  right: const BorderSide(color: Color(0xFFE0E0E0), width: 0.5),
                  bottom: const BorderSide(
                    color: Color(0xFFE0E0E0),
                    width: 0.5,
                  ),
                ),
              ),
              child: Stack(
                children: [
                  // Large rotated image behind text (bottom-right area)
                  Positioned(
                    bottom: 0,
                    right: -15,
                    child: Transform.rotate(
                      angle: -0.2, // Slight rotation (about 11 degrees)
                      child: Container(
                        width: 220,
                        height: 120,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(1),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(1),
                          child: widget.isLimitDataUsageEnabled
                              ? Image.asset(
                                  'assets/no_image.png',
                                  width: 120,
                                  height: 80,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        _getCategoryIcon(widget.name),
                                        size: 40,
                                        color: Colors.white,
                                      ),
                                    );
                                  },
                                )
                              : widget.imageUrl != null
                                  ? Image.network(
                                    widget.imageUrl!,
                                    width: 120,
                                    height: 80,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Icon(
                                          _getCategoryIcon(widget.name),
                                          size: 40,
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
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: const Center(
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      );
                                    },
                                  )
                                  : Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      _getCategoryIcon(widget.name),
                                      size: 40,
                                      color: Colors.white,
                                    ),
                                  ),
                        ),
                      ),
                    ),
                  ),
                  // Category name in top-left corner (on top of image)
                  Positioned(
                    top: 16,
                    left: 16,
                    child: Text(
                      widget.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.5,
                        shadows: [
                          Shadow(
                            offset: Offset(0, 1),
                            blurRadius: 3,
                            color: Colors.black26,
                          ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
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

// Mock categories are now replaced by Supabase data
// The Category class is now defined in category_service.dart
