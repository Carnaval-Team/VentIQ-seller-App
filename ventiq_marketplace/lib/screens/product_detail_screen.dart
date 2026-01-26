import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_theme.dart';
import '../services/product_detail_service.dart';
import '../services/cart_service.dart';
import '../widgets/carnaval_fab.dart';
import '../widgets/supabase_image.dart';
import '../widgets/stock_status_chip.dart';
import '../services/rating_service.dart';
import '../widgets/rating_input_dialog.dart';
import '../services/store_service.dart'; // Import agregado
import '../services/notification_service.dart';
import '../services/user_preferences_service.dart';
import '../services/user_session_service.dart';
import 'map_screen.dart';

/// Pantalla de detalles del producto del marketplace
class ProductDetailScreen extends StatefulWidget {
  final Map<String, dynamic> product;

  const ProductDetailScreen({super.key, required this.product});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  final ProductDetailService _productDetailService = ProductDetailService();
  final CartService _cartService = CartService();
  final RatingService _ratingService = RatingService();
  final StoreService _storeService = StoreService(); // Servicio agregado

  final UserSessionService _userSessionService = UserSessionService();
  final UserPreferencesService _preferencesService = UserPreferencesService();
  final NotificationService _notificationService = NotificationService();

  bool _isProductSubscribed = false;
  bool _isProductSubscriptionLoading = false;

  Map<String, dynamic>? _productDetails;
  Map<String, dynamic>? _storeDetails; // Variable para detalles de la tienda
  List<Map<String, dynamic>> _variants = [];
  List<Map<String, dynamic>> _relatedProducts = [];
  bool _isLoadingRelatedProducts = false;
  bool _isLoading = true;
  String? _errorMessage;

  // Selecciones múltiples: Key = variant id, Value = cantidad
  Map<String, int> _selectedQuantities = {};

  // Variante seleccionada en el dropdown
  Map<String, dynamic>? _selectedVariant;

  Future<void> _showPostAddDialog(int totalItems) async {
    if (!mounted) return;

    final action = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusXL),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusXL),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                  decoration: const BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.22),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.25),
                          ),
                        ),
                        child: const Icon(
                          Icons.check_circle_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Agregado al plan',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$totalItems ${totalItems == 1 ? 'producto' : 'productos'} agregado${totalItems == 1 ? '' : 's'}',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(null),
                        icon: const Icon(Icons.close_rounded),
                        color: Colors.white,
                        tooltip: 'Cerrar',
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '¿Qué deseas hacer ahora?',
                        style: TextStyle(
                          color: AppTheme.textPrimary.withOpacity(0.9),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).pop('continue'),
                        icon: const Icon(Icons.grid_view_rounded),
                        label: const Text('Continuar comprando'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryColor,
                          side: BorderSide(
                            color: AppTheme.primaryColor.withOpacity(0.35),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        onPressed: () => Navigator.of(context).pop('plan'),
                        icon: const Icon(Icons.shopping_cart_rounded),
                        label: const Text('Ir al plan'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accentColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || action == null) return;

    final initialTabIndex = action == 'plan' ? 3 : 2;

    Navigator.pushNamedAndRemoveUntil(
      context,
      '/home',
      (route) => false,
      arguments: initialTabIndex,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadProductDetails();
    _loadProductSubscriptionStatus();
  }

  int? _getProductId() {
    final dynamic productIdValue =
        widget.product['id_producto'] ?? widget.product['id'];
    if (productIdValue == null) return null;

    if (productIdValue is int) return productIdValue;
    if (productIdValue is String) return int.tryParse(productIdValue);
    if (productIdValue is num) return productIdValue.toInt();
    return int.tryParse(productIdValue.toString());
  }

  Future<void> _loadProductSubscriptionStatus() async {
    final productId = _getProductId();
    if (productId == null) return;

    final active = await _notificationService.isProductSubscriptionActive(
      productId: productId,
    );
    if (!mounted) return;
    setState(() {
      _isProductSubscribed = active;
    });
  }

  Future<bool> _ensureLoggedIn() async {
    final isLoggedIn = await _userSessionService.isLoggedIn();
    if (!mounted) return false;

    if (!isLoggedIn) {
      final goToLogin =
          await showDialog<bool>(
            context: context,
            builder: (context) {
              return AlertDialog(
                title: const Text('Iniciar sesión'),
                content: const Text(
                  'Para continuar necesitas iniciar sesión o registrarte.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Ir a login'),
                  ),
                ],
              );
            },
          ) ??
          false;

      if (!goToLogin || !mounted) return false;

      final result = await Navigator.of(context).pushNamed('/auth');
      if (!mounted) return false;

      if (result == true) {
        await _notificationService.initializeUserNotifications(force: true);
        await _loadProductSubscriptionStatus();
        return true;
      }

      return false;
    }

    return true;
  }

  Future<bool> _ensureNotificationsAccepted() async {
    final status = await _preferencesService.getNotificationConsentStatus();
    if (!mounted) return false;

    if (status == NotificationConsentStatus.accepted) {
      return true;
    }

    final selected = await showDialog<NotificationConsentStatus>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Notificaciones'),
          content: const Text(
            '¿Quieres recibir notificaciones sobre novedades, productos y recomendaciones?',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(NotificationConsentStatus.never),
              child: const Text('Nunca'),
            ),
            TextButton(
              onPressed: () => Navigator.of(
                context,
              ).pop(NotificationConsentStatus.remindLater),
              child: const Text('Más tarde'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(NotificationConsentStatus.denied),
              child: const Text('No'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(NotificationConsentStatus.accepted),
              child: const Text('Sí'),
            ),
          ],
        );
      },
    );

    if (!mounted || selected == null) return false;

    final enabled = await _notificationService.saveNotificationConsent(
      status: selected,
    );

    if (!mounted) return enabled;

    if (selected == NotificationConsentStatus.accepted && !enabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Permiso de notificaciones denegado. Puedes activarlo desde Ajustes.',
          ),
        ),
      );
    }

    return enabled;
  }

  Future<void> _onProductNotificationsPressed() async {
    final productId = _getProductId();
    if (productId == null) return;
    if (_isProductSubscriptionLoading) return;

    final canProceed = await _ensureLoggedIn();
    if (!canProceed || !mounted) return;

    final consentOk = await _ensureNotificationsAccepted();
    if (!consentOk || !mounted) return;

    setState(() {
      _isProductSubscriptionLoading = true;
    });

    try {
      final next = await _notificationService.toggleProductSubscription(
        productId: productId,
      );
      if (!mounted) return;

      setState(() {
        _isProductSubscribed = next;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            next
                ? 'Notificaciones del producto activadas'
                : 'Notificaciones del producto desactivadas',
          ),
          backgroundColor: next ? AppTheme.successColor : Colors.grey.shade800,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo actualizar la suscripción'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isProductSubscriptionLoading = false;
      });
    }
  }

  String _normalizeWhatsappPhone(String raw) {
    return raw.replaceAll(RegExp(r'[^0-9]'), '');
  }

  Future<void> _openWhatsApp(String? rawPhone) async {
    final phone = rawPhone?.toString().trim();
    if (phone == null || phone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Teléfono no disponible'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final normalized = _normalizeWhatsappPhone(phone);
    if (normalized.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Teléfono no válido'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final waAppUri = Uri.parse('whatsapp://send?phone=$normalized');
    final waWebUri = Uri.parse('https://wa.me/$normalized');

    try {
      final launchedApp = await launchUrl(
        waAppUri,
        mode: LaunchMode.externalApplication,
      );
      if (launchedApp) return;
    } catch (_) {}

    try {
      await launchUrl(waWebUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo abrir WhatsApp: $e'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  /// Carga los detalles completos del producto desde Supabase
  Future<void> _loadProductDetails() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isLoadingRelatedProducts = true;
    });

    try {
      // ✅ Manejo seguro de tipos para id_producto
      final dynamic productIdValue =
          widget.product['id_producto'] ?? widget.product['id'];

      if (productIdValue == null) {
        throw Exception('ID del producto no disponible en los datos');
      }

      // Convertir a int de forma segura
      final int productId;
      if (productIdValue is int) {
        productId = productIdValue;
      } else if (productIdValue is String) {
        productId = int.parse(productIdValue);
      } else {
        productId = (productIdValue as num).toInt();
      }

      print('🔍 Cargando detalles del producto ID: $productId');

      // 1. Cargar detalles del producto
      final details = await _productDetailService.getProductDetail(productId);

      // Cargar productos relacionados (top 10)
      final relatedProducts = await _productDetailService.getRelatedProducts(
        productId,
        limit: 10,
      );

      // 2. Cargar detalles de la tienda si tenemos el ID
      Map<String, dynamic>? storeData;

      // Intentar obtener ID de tienda de varias fuentes
      dynamic storeIdValue;
      if (widget.product['metadata'] != null) {
        storeIdValue = widget.product['metadata']['id_tienda'];
      }

      // Si no está en metadata, buscar en los detalles del producto recién cargados
      if (storeIdValue == null && details['id_tienda'] != null) {
        storeIdValue = details['id_tienda'];
      }

      if (storeIdValue != null) {
        final int storeId = storeIdValue is int
            ? storeIdValue
            : int.tryParse(storeIdValue.toString()) ?? 0;

        if (storeId > 0) {
          print('🔍 Cargando detalles de la tienda ID: $storeId');
          storeData = await _storeService.getStoreDetails(storeId);
        }
      }

      setState(() {
        _productDetails = details;
        _storeDetails = storeData;
        _variants = List<Map<String, dynamic>>.from(details['variantes'] ?? []);
        _relatedProducts = relatedProducts;
        _isLoadingRelatedProducts = false;
        // Seleccionar la primera variante por defecto
        if (_variants.isNotEmpty) {
          _selectedVariant = _variants.first;
        }
        _isLoading = false;
      });

      print('✅ Detalles cargados: ${_variants.length} variantes disponibles');
      if (_storeDetails != null) {
        print('✅ Tienda cargada: ${_storeDetails!['denominacion']}');
      }
    } catch (e, stackTrace) {
      print('❌ Error cargando detalles: $e');
      print('Stack trace: $stackTrace');
      setState(() {
        _errorMessage = 'Error al cargar los detalles del producto: $e';
        _isLoading = false;
        _isLoadingRelatedProducts = false;
      });
    }
  }

  Future<void> _addDefaultToPlan() async {
    final variant =
        _selectedVariant ?? (_variants.isNotEmpty ? _variants.first : null);

    if (variant == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay presentación disponible para este producto'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final variantId = variant['id']?.toString();
    if (variantId == null || variantId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo determinar la presentación del producto'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _selectedQuantities = {variantId: 1};
    });

    await _addToCart();
  }

  /// Agrega los productos seleccionados al carrito
  Future<void> _addToCart() async {
    if (_selectedQuantities.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona al menos un producto'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      // ✅ Obtener TODOS los datos de la tienda desde metadata del RPC
      Map<String, dynamic>? metadata =
          widget.product['metadata'] as Map<String, dynamic>?;

      // Intentar recuperar metadatos si no vienen en la navegación
      if (metadata == null && _storeDetails != null) {
        print(
          '⚠️ Metadata no disponible en widget.product, usando _storeDetails',
        );
        metadata = {
          'id_tienda': _storeDetails!['id'],
          'denominacion_tienda': _storeDetails!['denominacion'],
          'ubicacion': _storeDetails!['ubicacion'],
          'direccion': _storeDetails!['direccion'],
          'provincia': _storeDetails!['provincia'],
          'municipio': _storeDetails!['municipio'],
        };
      }

      if (metadata == null) {
        throw Exception(
          'Metadata del producto no disponible y no se pudo recuperar de la tienda',
        );
      }

      // Extraer datos de la tienda desde metadata (según get_productos_marketplace.sql líneas 94-132)
      final storeId = metadata['id_tienda'] as int? ?? 0;
      final storeName = metadata['denominacion_tienda'] as String? ?? 'Tienda';
      final storeLocation = metadata['ubicacion'] as String?;
      final storeAddress = metadata['direccion'] as String?;
      final storeProvincia = metadata['provincia'] as String?;
      final storeMunicipio = metadata['municipio'] as String?;

      // Debug: Verificar datos de la tienda
      print('🏪 Agregando al carrito desde tienda:');
      print('  Producto: ${widget.product['denominacion']}');
      print('  🏬 Tienda ID: $storeId');
      print('  🏬 Tienda: $storeName');
      print('  📍 Ubicación: $storeLocation');
      print('  📍 Municipio: $storeMunicipio');
      print('  📍 Provincia: $storeProvincia');

      if (storeId == 0) {
        throw Exception(
          'ID de tienda inválido (0). Verifica los datos del producto.',
        );
      }

      // Agregar cada variante seleccionada al carrito
      for (final entry in _selectedQuantities.entries) {
        final variantId = entry.key;
        final quantity = entry.value;

        // Buscar la variante en la lista
        final variant = _variants.firstWhere((v) => v['id'] == variantId);

        // ✅ Obtener productId de forma segura
        final dynamic productIdValue =
            widget.product['id_producto'] ?? widget.product['id'];
        final int productId = productIdValue is int
            ? productIdValue
            : (productIdValue is String
                  ? int.parse(productIdValue)
                  : (productIdValue as num).toInt());

        await _cartService.addItem(
          productId: productId,
          productName:
              _productDetails?['denominacion'] ??
              widget.product['denominacion'] ??
              'Producto',
          productImage: _productDetails?['imagen'] as String?,
          variantId: variantId,
          variantName: variant['nombre'] as String? ?? 'Variante',
          presentacion: variant['presentacion'] as String? ?? 'Unidad',
          price: (variant['precio'] as num?)?.toDouble() ?? 0.0,
          quantity: quantity,
          storeId: storeId,
          storeName: storeName,
          storeLocation: storeLocation,
          storeAddress: storeAddress,
          storeProvincia: storeProvincia,
          storeMunicipio: storeMunicipio,
        );

        print(
          '  ✅ Agregado: ${variant['nombre']} x$quantity a tienda "$storeName" (ID: $storeId)',
        );
      }

      final totalItems = _selectedQuantities.values.fold<int>(
        0,
        (sum, qty) => sum + qty,
      );

      print(
        '✅ $totalItems ${totalItems == 1 ? 'producto agregado' : 'productos agregados'} al plan',
      );

      // Limpiar selecciones
      setState(() {
        _selectedQuantities.clear();
      });

      if (mounted) {
        await _showPostAddDialog(totalItems);
      }
    } catch (e) {
      print('❌ Error agregando al carrito: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al agregar al plan: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _showRatingDialog({
    required String title,
    required Function(double, String?) onSubmit,
  }) async {
    await showDialog(
      context: context,
      builder: (context) => RatingInputDialog(title: title, onSubmit: onSubmit),
    );
  }

  void _rateProduct() {
    // ✅ Obtener ID del producto de forma segura
    final dynamic productIdValue =
        widget.product['id_producto'] ?? widget.product['id'];
    final int productId = productIdValue is int
        ? productIdValue
        : (productIdValue is String
              ? int.parse(productIdValue)
              : (productIdValue as num).toInt());

    _showRatingDialog(
      title: 'Calificar Producto',
      onSubmit: (rating, comment) async {
        await _ratingService.submitProductRating(
          productId: productId,
          rating: rating,
          comentario: comment,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('¡Gracias por calificar el producto!'),
              backgroundColor: AppTheme.successColor,
            ),
          );
        }
      },
    );
  }

  Future<void> _openStoreLocation() async {
    final metadata = widget.product['metadata'] as Map<String, dynamic>?;

    dynamic storeIdValue;
    if (metadata != null) {
      storeIdValue = metadata['id_tienda'];
    }

    final int storeId = storeIdValue is int
        ? storeIdValue
        : int.tryParse(storeIdValue?.toString() ?? '') ?? 0;

    // Preferir coordenadas reales de la tienda desde _storeDetails (tabla app_dat_tienda)
    final String? ubicacionCoords =
        (_storeDetails?['ubicacion'] as String?) ??
        (metadata?['ubicacion'] as String?);

    // Validación estricta: debe ser lat,lng numérico
    final parts = ubicacionCoords?.split(',');
    final lat = (parts != null && parts.length == 2)
        ? double.tryParse(parts[0].trim())
        : null;
    final lng = (parts != null && parts.length == 2)
        ? double.tryParse(parts[1].trim())
        : null;

    if (lat == null || lng == null) {
      // Intentar obtener detalles de tienda si aún no están cargados
      Map<String, dynamic>? storeDetails = _storeDetails;
      if (storeDetails == null && storeId > 0) {
        try {
          storeDetails = await _storeService.getStoreDetails(storeId);
        } catch (_) {}
      }

      final String? fallbackUbicacion = storeDetails?['ubicacion'] as String?;
      final fallbackParts = fallbackUbicacion?.split(',');
      final fallbackLat = (fallbackParts != null && fallbackParts.length == 2)
          ? double.tryParse(fallbackParts[0].trim())
          : null;
      final fallbackLng = (fallbackParts != null && fallbackParts.length == 2)
          ? double.tryParse(fallbackParts[1].trim())
          : null;

      if (fallbackLat == null || fallbackLng == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ubicación de la tienda no disponible'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Reemplazar con ubicación válida
      final storeData = {
        'id': storeId > 0 ? storeId : (metadata?['id_tienda']),
        'denominacion':
            storeDetails?['denominacion'] ?? metadata?['denominacion_tienda'],
        'ubicacion': fallbackUbicacion,
        'direccion': storeDetails?['direccion'] ?? metadata?['direccion'],
        'imagen_url': storeDetails?['imagen_url'],
        'logoUrl': storeDetails?['imagen_url'],
      };

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                MapScreen(stores: [storeData], initialStore: storeData),
          ),
        );
      }
      return;
    }

    // Construir objeto de tienda para el mapa
    final storeData = {
      'id': storeId > 0 ? storeId : (metadata?['id_tienda']),
      'denominacion':
          _storeDetails?['denominacion'] ?? metadata?['denominacion_tienda'],
      'ubicacion': ubicacionCoords,
      'direccion': _storeDetails?['direccion'] ?? metadata?['direccion'],
      'imagen_url': _storeDetails?['imagen_url'],
      'logoUrl': _storeDetails?['imagen_url'],
    };

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              MapScreen(stores: [storeData], initialStore: storeData),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      floatingActionButton: const Padding(
        padding: EdgeInsets.only(bottom: 80),
        child: CarnavalFab(),
      ),
      bottomNavigationBar: (!_isLoading && _errorMessage == null)
          ? SafeArea(child: _buildAddToPlanSection())
          : null,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              icon: _isProductSubscriptionLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppTheme.primaryColor,
                        ),
                      ),
                    )
                  : Icon(
                      _isProductSubscribed
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_none_rounded,
                      color: AppTheme.primaryColor,
                    ),
              onPressed: _isProductSubscriptionLoading
                  ? null
                  : _onProductNotificationsPressed,
              tooltip: _isProductSubscribed
                  ? 'Desactivar notificaciones'
                  : 'Activar notificaciones',
            ),
          ),
          Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              icon: const Icon(
                Icons.star_rate_rounded,
                color: AppTheme.warningColor,
              ),
              onPressed: _rateProduct,
              tooltip: 'Calificar Producto',
            ),
          ),
          Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              icon: const Icon(
                Icons.share_outlined,
                color: AppTheme.textPrimary,
              ),
              onPressed: () {},
            ),
          ),
          Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              icon: const Icon(
                Icons.favorite_border,
                color: AppTheme.errorColor,
              ),
              onPressed: () {},
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryColor),
            )
          : _errorMessage != null
          ? _buildErrorState()
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hero Image con gradiente
                  _buildHeroImage(),

                  // Información del producto
                  _buildProductInfo(),

                  // Características destacadas
                  // _buildFeatures(),

                  // Productos relacionados
                  _buildRelatedProductsSection(),

                  // Espacio final
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildRelatedProductsSection() {
    if (_isLoadingRelatedProducts) {
      return const SizedBox.shrink();
    }

    if (_relatedProducts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryColor.withOpacity(0.2),
                      AppTheme.primaryColor.withOpacity(0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: AppTheme.primaryColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Productos relacionados',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 240,
            child: PageView.builder(
              controller: PageController(viewportFraction: 0.82),
              itemCount: _relatedProducts.length,
              itemBuilder: (context, index) {
                final p = _relatedProducts[index];
                final name = (p['denominacion'] ?? 'Producto').toString();
                final imageUrl = p['imagen']?.toString();
                final tieneStock = (p['tiene_stock'] as bool?) ?? false;
                final stockRaw = (p['stock_disponible'] as num?);
                final metadata = p['metadata'] as Map<String, dynamic>?;
                final ratingRaw = metadata?['rating_promedio'];
                final rating = ratingRaw is num
                    ? ratingRaw.toDouble()
                    : double.tryParse(ratingRaw?.toString() ?? '') ?? 0.0;
                final totalRatingsRaw = metadata?['total_ratings'];
                final totalRatings = totalRatingsRaw is int
                    ? totalRatingsRaw
                    : int.tryParse(totalRatingsRaw?.toString() ?? '') ?? 0;
                final priceRaw = p['precio_venta'];
                final price = priceRaw is num
                    ? priceRaw.toDouble()
                    : double.tryParse(priceRaw?.toString() ?? '') ?? 0.0;

                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProductDetailScreen(product: p),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.grey.withOpacity(0.12),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(18),
                              ),
                              child: SizedBox(
                                height: 130,
                                width: double.infinity,
                                child: imageUrl != null && imageUrl.isNotEmpty
                                    ? SupabaseImage(
                                        imageUrl: imageUrl,
                                        width: double.infinity,
                                        height: 130,
                                        fit: BoxFit.cover,
                                        errorWidgetOverride: Container(
                                          color: Colors.grey[100],
                                          child: const Center(
                                            child: Icon(
                                              Icons.shopping_bag_rounded,
                                              color: AppTheme.textSecondary,
                                              size: 36,
                                            ),
                                          ),
                                        ),
                                      )
                                    : Container(
                                        color: Colors.grey[100],
                                        child: const Center(
                                          child: Icon(
                                            Icons.shopping_bag_rounded,
                                            color: AppTheme.textSecondary,
                                            size: 36,
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.textPrimary,
                                        height: 1.15,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.star_rounded,
                                          size: 14,
                                          color: AppTheme.warningColor,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          rating.toStringAsFixed(1),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.textPrimary,
                                          ),
                                        ),
                                        if (totalRatings > 0) ...[
                                          const SizedBox(width: 4),
                                          Text(
                                            '($totalRatings)',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.textSecondary
                                                  .withOpacity(0.85),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const Spacer(),
                                    Row(
                                      children: [
                                        Text(
                                          '\$${price.toStringAsFixed(2)}',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                            color: AppTheme.accentColor,
                                            letterSpacing: -0.2,
                                          ),
                                        ),
                                        const Spacer(),
                                        Builder(
                                          builder: (context) {
                                            const lowStockThreshold = 10;
                                            final int stockCount =
                                                stockRaw != null
                                                ? stockRaw.toInt()
                                                : (tieneStock
                                                      ? lowStockThreshold + 1
                                                      : 0);

                                            return StockStatusChip(
                                              stock: stockCount,
                                              lowStockThreshold:
                                                  lowStockThreshold,
                                              showQuantity: true,
                                              fontSize: 11,
                                              iconSize: 13,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                              borderRadius: 10,
                                              maxWidth: 110,
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            _errorMessage ?? 'Error desconocido',
            style: const TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadProductDetails,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  /// Hero Image con gradiente y badges flotantes
  Widget _buildHeroImage() {
    final imageUrl =
        _productDetails?['imagen'] ??
        widget.product['imagen'] ??
        widget.product['imageUrl'];

    final screenWidth = MediaQuery.of(context).size.width;

    return Stack(
      children: [
        // Imagen principal
        Container(
          height: 280,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.primaryColor.withOpacity(0.1),
                AppTheme.secondaryColor.withOpacity(0.1),
              ],
            ),
          ),
          child: imageUrl != null
              ? SupabaseImage(
                  imageUrl: imageUrl,
                  width: screenWidth,
                  height: 280,
                  fit: BoxFit.cover,
                  errorWidgetOverride: Center(
                    child: Icon(
                      Icons.shopping_bag_rounded,
                      size: 100,
                      color: Colors.grey[300],
                    ),
                  ),
                )
              : Center(
                  child: Icon(
                    Icons.shopping_bag_rounded,
                    size: 100,
                    color: Colors.grey[300],
                  ),
                ),
        ),
        // Gradiente overlay
        Container(
          height: 280,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
            ),
          ),
        ),
        // Badge de categoría flotante
        Positioned(
          top: 100,
          left: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.secondaryColor,
                  AppTheme.secondaryColor.withOpacity(0.8),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.secondaryColor.withOpacity(0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.category_rounded,
                  color: Colors.white,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  _productDetails?['categoria'] ?? 'Sin categoría',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Badge de rating flotante
        Positioned(
          top: 100,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.star_rounded,
                  color: AppTheme.warningColor,
                  size: 18,
                ),
                const SizedBox(width: 4),
                Text(
                  '${((_productDetails?['rating_promedio'] as num?) ?? 0.0).toStringAsFixed(1)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(width: 2),
                Text(
                  '(${(_productDetails?['total_ratings'] as int?) ?? 0})',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Información del producto con diseño premium
  Widget _buildProductInfo() {
    return Transform.translate(
      offset: const Offset(0, -50),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Nombre del producto
            Text(
              _productDetails?['denominacion'] ??
                  widget.product['denominacion'] ??
                  'Producto',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
                height: 1.2,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 10),

            Builder(
              builder: (context) {
                final variant =
                    _selectedVariant ??
                    (_variants.isNotEmpty ? _variants.first : null);
                final price =
                    (variant?['precio'] as num?)?.toDouble() ??
                    (_productDetails?['precio'] as num?)?.toDouble() ??
                    0.0;

                return Row(
                  children: [
                    Text(
                      '\$${price.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.accentColor,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 10),
            // Información de la tienda (clickable)
            if (_storeDetails != null ||
                widget.product['metadata'] != null) ...[
              Builder(
                builder: (context) {
                  final storeName =
                      _storeDetails?['denominacion'] ??
                      widget.product['metadata']?['denominacion_tienda'] ??
                      'Tienda';

                  String locationText = '';
                  if (_storeDetails != null) {
                    final address = _storeDetails!['direccion'] ?? '';
                    final state = _storeDetails!['nombre_estado'] ?? '';
                    final country = _storeDetails!['nombre_pais'] ?? '';
                    locationText = [
                      address,
                      state,
                      country,
                    ].where((e) => e.toString().isNotEmpty).join(', ');
                  } else {
                    final municipio =
                        widget.product['metadata']?['municipio'] ?? '';
                    final provincia =
                        widget.product['metadata']?['provincia'] ?? '';
                    locationText = '$municipio, $provincia';
                  }

                  if (locationText.trim() == ',')
                    locationText = 'Ubicación no disponible';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _openStoreLocation,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.store_rounded,
                                  color: AppTheme.primaryColor,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      storeName,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.primaryColor,
                                      ),
                                    ),
                                    if (locationText.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.location_on_outlined,
                                            size: 12,
                                            color: AppTheme.textSecondary,
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              locationText,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: AppTheme.textSecondary,
                                              ),
                                              maxLines:
                                                  2, // Permitir 2 líneas para dirección larga
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    Builder(
                                      builder: (context) {
                                        final phone = _storeDetails?['phone']
                                            ?.toString();
                                        if (phone == null ||
                                            phone.trim().isEmpty) {
                                          return const SizedBox.shrink();
                                        }

                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            top: 6,
                                          ),
                                          child: InkWell(
                                            onTap: () => _openWhatsApp(phone),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.chat_rounded,
                                                  size: 14,
                                                  color: Colors.green,
                                                ),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Text(
                                                    phone,
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: AppTheme
                                                          .textSecondary,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 14,
                                color: AppTheme.primaryColor,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
            const SizedBox(height: 12),
            // Metadata del producto
            Row(
              children: [
                // Stock
                Expanded(
                  child: Builder(
                    builder: (context) {
                      const lowStockThreshold = 10;
                      final stockRaw = _productDetails?['cantidad_total'];
                      final stock = stockRaw is num
                          ? stockRaw.toInt()
                          : int.tryParse(stockRaw?.toString() ?? '') ?? 0;

                      return StockStatusChip(
                        stock: stock,
                        lowStockThreshold: lowStockThreshold,
                        showQuantity: true,
                        fullWidth: true,
                        fontSize: 13,
                        iconSize: 18,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        borderRadius: 12,
                        maxWidth: null,
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddToPlanSection() {
    final variant =
        _selectedVariant ?? (_variants.isNotEmpty ? _variants.first : null);
    final price =
        (variant?['precio'] as num?)?.toDouble() ??
        (_productDetails?['precio'] as num?)?.toDouble() ??
        0.0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.primaryColor.withOpacity(0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '\$${price.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.accentColor,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.primaryColor,
                  AppTheme.primaryColor.withOpacity(0.85),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withOpacity(0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: (variant == null) ? null : _addDefaultToPlan,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.playlist_add, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Añadir al plan',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Sección con información de la tienda
  Widget _buildStoreInfoSection() {
    final metadata = widget.product['metadata'] as Map<String, dynamic>?;
    if (metadata == null) return const SizedBox.shrink();

    return Transform.translate(
      offset: const Offset(
        0,
        -40,
      ), // Negative offset to overlap slightly or sit close
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 15,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              onTap: _openStoreLocation,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Icon(
                        Icons.store_rounded,
                        color: AppTheme.primaryColor,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Vendido por',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            metadata['denominacion_tienda'] ??
                                'Tienda Desconocida',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          if (metadata['ubicacion'] != null) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  Icons.location_on_outlined,
                                  size: 14,
                                  color: AppTheme.textSecondary,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    '${metadata['municipio']}, ${metadata['provincia']}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppTheme.textSecondary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 16,
                        color: AppTheme.textSecondary,
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

  /// Características destacadas
  Widget _buildFeatures() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryColor.withOpacity(0.05),
            AppTheme.secondaryColor.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.primaryColor.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildFeatureItem(
            Icons.local_shipping_rounded,
            'Envío rápido',
            AppTheme.primaryColor,
          ),
          Container(
            width: 1,
            height: 40,
            color: AppTheme.textSecondary.withOpacity(0.2),
          ),
          _buildFeatureItem(
            Icons.verified_user_rounded,
            'Garantizado',
            AppTheme.successColor,
          ),
          Container(
            width: 1,
            height: 40,
            color: AppTheme.textSecondary.withOpacity(0.2),
          ),
          _buildFeatureItem(
            Icons.payment_rounded,
            'Pago seguro',
            AppTheme.accentColor,
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String label, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary.withOpacity(0.8),
          ),
        ),
      ],
    );
  }
}
