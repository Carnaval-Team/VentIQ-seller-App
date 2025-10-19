import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'products_screen.dart';
import 'barcode_scanner_screen.dart';
import 'fluid_mode_screen.dart';
import '../widgets/bottom_navigation.dart';
import '../widgets/app_drawer.dart';
import '../services/category_service.dart';
import '../services/user_preferences_service.dart';
import '../services/changelog_service.dart';
import '../services/currency_service.dart';
import '../services/update_service.dart';
import '../widgets/changelog_dialog.dart';
import '../widgets/sales_monitor_fab.dart';
import '../utils/connection_error_handler.dart';
import 'package:url_launcher/url_launcher.dart';

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
  bool _isFluidModeEnabled = false; // Para el estado del modo fluido
  bool _isOfflineModeEnabled = false; // Para el estado del modo offline
  bool _isConnectionError = false; // Para detectar errores de conexión
  bool _showRetryWidget = false; // Para mostrar el widget de reconexión

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
    _loadFluidModeSettings();
    _loadOfflineModeSettings();
    // Verificar actualizaciones después de que el frame esté completamente renderizado
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdatesAfterNavigation();
    });
  }

  Future<void> _loadDataUsageSettings() async {
    final isEnabled = await _preferencesService.isLimitDataUsageEnabled();
    if (mounted) {
      setState(() {
        _isLimitDataUsageEnabled = isEnabled;
      });
    }
  }

  Future<void> _loadFluidModeSettings() async {
    final isEnabled = await _preferencesService.isFluidModeEnabled();
    if (mounted) {
      setState(() {
        _isFluidModeEnabled = isEnabled;
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh the screen when returning from other screens
      _loadDataUsageSettings();
      _loadFluidModeSettings();
      _loadOfflineModeSettings();
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
      final isOfflineModeEnabled =
          await _preferencesService.isOfflineModeEnabled();

      List<Category> categories;

      if (isOfflineModeEnabled) {
        print('🔌 Modo offline - Cargando categorías desde cache...');

        // Cargar datos offline
        final offlineData = await _preferencesService.getOfflineData();

        if (offlineData != null && offlineData['categories'] != null) {
          final categoriesData = offlineData['categories'] as List<dynamic>;

          // Convertir datos JSON a objetos Category
          categories =
              categoriesData.map((catData) {
                return Category(
                  id: catData['id'] as int,
                  name: catData['name'] as String,
                  imageUrl: catData['imageUrl'] as String,
                  color: Color(catData['color'] as int),
                );
              }).toList();

          print(
            '✅ Categorías cargadas desde cache offline: ${categories.length}',
          );
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
    } catch (e, stackTrace) {
      final isConnectionError = ConnectionErrorHandler.isConnectionError(e);

      setState(() {
        _isConnectionError = isConnectionError;
        _errorMessage =
            isConnectionError
                ? ConnectionErrorHandler.getConnectionErrorMessage()
                : ConnectionErrorHandler.getGenericErrorMessage(e);
        _isLoading = false;
        _showRetryWidget = isConnectionError;
      });

      debugPrint('❌ Error cargando categorías: $e');
      debugPrint('🔍 Es error de conexión: $isConnectionError');
      debugPrint('🔍 Stack trace: $stackTrace');
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

  Widget _buildConnectionStatusChip() {
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isOfflineModeEnabled
                  ? '🔌 Modo offline activado - Trabajando con datos sincronizados'
                  : '🌐 Modo online - Conectado al servidor',
            ),
            backgroundColor:
                _isOfflineModeEnabled ? Colors.grey[600] : Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: _isOfflineModeEnabled ? Colors.grey[100] : Colors.green[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                _isOfflineModeEnabled ? Colors.grey[400]! : Colors.green[400]!,
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 1,
              offset: const Offset(0, 0.5),
            ),
          ],
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isOfflineModeEnabled ? Icons.cloud_off : Icons.cloud_done,
                size: 12,
                color:
                    _isOfflineModeEnabled
                        ? Colors.grey[600]
                        : Colors.green[600],
              ),
              const SizedBox(width: 3),
              Text(
                _isOfflineModeEnabled ? 'Offline' : 'Online',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  color:
                      _isOfflineModeEnabled
                          ? Colors.grey[600]
                          : Colors.green[600],
                ),
              ),
            ],
          ),
        ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        leading: Container(
          margin: const EdgeInsets.only(left: 12, top: 12, bottom: 12),
          child: _buildConnectionStatusChip(),
        ),
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
      // Si es un error de conexión, mostrar el widget especial de reconexión
      if (_showRetryWidget) {
        return ConnectionRetryWidget(
          message: _errorMessage!,
          onRetry: () => _loadCategories(forceRefresh: true),
        );
      }

      // Para otros errores, mostrar el widget de error tradicional
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
              isFluidModeEnabled: _isFluidModeEnabled,
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

  /// Verificar actualizaciones después de navegar a la vista principal
  Future<void> _checkForUpdatesAfterNavigation() async {
    // Esperar más tiempo para que la navegación se complete totalmente
    await Future.delayed(const Duration(seconds: 3));

    try {
      print(
        '🔍 Verificando actualizaciones automáticamente desde CategoriesScreen...',
      );

      // Verificar que el contexto sigue siendo válido
      if (!mounted) {
        print(
          '❌ Contexto no válido, cancelando verificación de actualizaciones',
        );
        return;
      }

      final updateInfo = await UpdateService.checkForUpdates();

      if (updateInfo['hay_actualizacion'] == true && mounted) {
        print('🆕 Actualización disponible detectada desde CategoriesScreen');
        // Solo mostrar si hay actualización disponible
        _showUpdateAvailableDialog(updateInfo);
      } else {
        print('✅ No hay actualizaciones disponibles desde CategoriesScreen');
      }
    } catch (e) {
      print(
        '❌ Error verificando actualizaciones automáticamente desde CategoriesScreen: $e',
      );
      // No mostrar error al usuario, es una verificación silenciosa
    }
  }

  /// Mostrar diálogo cuando hay actualización disponible
  void _showUpdateAvailableDialog(Map<String, dynamic> updateInfo) {
    final bool isObligatory = updateInfo['obligatoria'] ?? false;
    final String newVersion = updateInfo['version_disponible'] ?? 'Desconocida';
    final String currentVersion =
        updateInfo['current_version'] ?? 'Desconocida';

    // Verificar que el contexto sea válido antes de mostrar el diálogo
    if (!mounted) {
      print('❌ Contexto no válido para mostrar diálogo de actualización');
      return;
    }

    print('📱 Mostrando diálogo de actualización desde CategoriesScreen');

    showDialog(
      context: context,
      barrierDismissible: !isObligatory, // Si es obligatoria, no se puede cerrar
      builder: (context) => WillPopScope(
        onWillPop: () async => !isObligatory, // Prevenir cierre con botón atrás si es obligatoria
        child: AlertDialog(
          title: Row(
            children: [
              Icon(
                isObligatory ? Icons.warning : Icons.system_update,
                color: isObligatory ? Colors.orange : Colors.blue,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isObligatory
                      ? 'Actualización Obligatoria'
                      : 'Nueva Versión Disponible',
                  style: const TextStyle(fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Nueva versión disponible: $newVersion'),
              Text('Versión actual: $currentVersion'),
              const SizedBox(height: 16),
              if (isObligatory)
                const Text(
                  'Esta actualización es obligatoria y debe instalarse para continuar usando la aplicación.',
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.w500,
                  ),
                )
              else
                const Text(
                  'Se recomienda actualizar para obtener las últimas mejoras y correcciones.',
                ),
            ],
          ),
          actions: [
            if (!isObligatory)
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Más tarde'),
              ),
            ElevatedButton(
              onPressed: () => _downloadUpdate(),
              style: ElevatedButton.styleFrom(
                backgroundColor: isObligatory ? Colors.orange : Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Descargar'),
            ),
          ],
        ),
      ),
    );
  }

  /// Descargar actualización
  Future<void> _downloadUpdate() async {
    try {
      final Uri url = Uri.parse(UpdateService.downloadUrl);

      print('🔗 Intentando abrir URL: ${url.toString()}');

      // Intentar diferentes modos de lanzamiento
      bool launched = false;

      // Método 1: Intentar con navegador web
      try {
        launched = await launchUrl(url, mode: LaunchMode.externalApplication);
        print('✅ Método 1 (externalApplication): $launched');
      } catch (e) {
        print('❌ Método 1 falló: $e');
      }

      // Método 2: Si falla, intentar con navegador interno
      if (!launched) {
        try {
          launched = await launchUrl(url, mode: LaunchMode.inAppWebView);
          print('✅ Método 2 (inAppWebView): $launched');
        } catch (e) {
          print('❌ Método 2 falló: $e');
        }
      }

      // Método 3: Si falla, intentar modo plataforma
      if (!launched) {
        try {
          launched = await launchUrl(url);
          print('✅ Método 3 (default): $launched');
        } catch (e) {
          print('❌ Método 3 falló: $e');
        }
      }

      if (launched) {
        // Cerrar diálogo solo si no es obligatoria
        if (mounted) {
          Navigator.of(context).pop();
        }

        // Mostrar mensaje de confirmación
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('📱 Descarga iniciada - Instala la nueva versión'),
              backgroundColor: Colors.blue,
              duration: Duration(seconds: 4),
            ),
          );
        }
      } else {
        // Si todos los métodos fallan, mostrar diálogo con URL para copiar
        _showManualDownloadDialog();
      }
    } catch (e) {
      print('❌ Error general abriendo enlace de descarga: $e');
      _showManualDownloadDialog();
    }
  }

  /// Mostrar diálogo para descarga manual
  void _showManualDownloadDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.download, color: Colors.blue),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Descarga Manual',
                style: TextStyle(fontSize: 16),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'No se pudo abrir automáticamente el enlace de descarga.',
            ),
            const SizedBox(height: 16),
            const Text('Copia este enlace y ábrelo en tu navegador:'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: SelectableText(
                UpdateService.downloadUrl,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // Cerrar diálogo manual
              Navigator.of(context).pop(); // Cerrar diálogo de actualización
            },
            child: const Text('Cerrar'),
          ),
          ElevatedButton(
            onPressed: () async {
              // Intentar copiar al portapapeles
              try {
                await _copyToClipboard(UpdateService.downloadUrl);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('📋 Enlace copiado al portapapeles'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              } catch (e) {
                print('❌ Error copiando al portapapeles: $e');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Copiar Enlace'),
          ),
        ],
      ),
    );
  }

  /// Copiar texto al portapapeles
  Future<void> _copyToClipboard(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (e) {
      print('❌ Error copiando al portapapeles: $e');
      rethrow;
    }
  }
}

class _CategoryCard extends StatefulWidget {
  final int id;
  final String name;
  final String? imageUrl;
  final Color color;
  final bool isLimitDataUsageEnabled;
  final bool isFluidModeEnabled;

  const _CategoryCard({
    required this.id,
    required this.name,
    this.imageUrl,
    required this.color,
    required this.isLimitDataUsageEnabled,
    required this.isFluidModeEnabled,
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

    // Check if fluid mode is enabled
    if (widget.isFluidModeEnabled) {
      print('🚀 Modo fluido activado - Navegando a FluidModeScreen');
      // Navigate to fluid mode screen
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const FluidModeScreen()),
      );
    } else {
      print('📱 Modo tradicional - Navegando a ProductsScreen');
      // Navigate to products list for this category (traditional mode)
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
                          child:
                              widget.isLimitDataUsageEnabled
                                  ? Image.asset(
                                    'assets/no_image.png',
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
