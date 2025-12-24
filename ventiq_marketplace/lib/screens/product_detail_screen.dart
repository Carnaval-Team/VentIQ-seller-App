import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../services/product_detail_service.dart';
import '../services/cart_service.dart';
import '../widgets/carnaval_fab.dart';
import '../services/rating_service.dart';
import '../widgets/rating_input_dialog.dart';
import '../services/store_service.dart'; // Import agregado
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

  Map<String, dynamic>? _productDetails;
  Map<String, dynamic>? _storeDetails; // Variable para detalles de la tienda
  List<Map<String, dynamic>> _variants = [];
  bool _isLoading = true;
  String? _errorMessage;

  // Selecciones múltiples: Key = variant id, Value = cantidad
  Map<String, int> _selectedQuantities = {};

  // Variante seleccionada en el dropdown
  Map<String, dynamic>? _selectedVariant;

  @override
  void initState() {
    super.initState();
    _loadProductDetails();
  }

  /// Carga los detalles completos del producto desde Supabase
  Future<void> _loadProductDetails() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
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
      });
    }
  }

  /// Actualiza la cantidad seleccionada de una variante
  void _updateQuantity(String variantId, int quantity) {
    setState(() {
      if (quantity > 0) {
        _selectedQuantities[variantId] = quantity;
      } else {
        _selectedQuantities.remove(variantId);
      }
    });
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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '$totalItems ${totalItems == 1 ? 'producto agregado' : 'productos agregados'} al carrito',
                  ),
                ),
              ],
            ),
            backgroundColor: AppTheme.successColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }

      // Limpiar selecciones
      setState(() {
        _selectedQuantities.clear();
      });
    } catch (e) {
      print('❌ Error agregando al carrito: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al agregar al carrito: $e'),
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

  void _openStoreLocation() {
    final metadata = widget.product['metadata'] as Map<String, dynamic>?;
    if (metadata == null) return;

    final storeLocation = metadata['ubicacion'] as String?;

    if (storeLocation == null || !storeLocation.contains(',')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ubicación de la tienda no disponible'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Construir objeto de tienda para el mapa
    final storeData = {
      'id': metadata['id_tienda'],
      'denominacion': metadata['denominacion_tienda'],
      'ubicacion': storeLocation,
      'direccion': metadata['direccion'],
      'imagem_url':
          null, // No tenemos la imagen de la tienda aquí, usará icono default
    };

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            MapScreen(stores: [storeData], initialStore: storeData),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      floatingActionButton: const Padding(
        padding: EdgeInsets.only(bottom: 80),
        child: CarnavalFab(),
      ),
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

                  // Descripción
                  if (_productDetails?['descripcion'] != null)
                    _buildDescriptionSection(),

                  // Variantes disponibles
                  _buildVariantsSection(),

                  // Información de la tienda
                  // if (widget.product['metadata'] != null)
                  //   _buildStoreInfoSection(),

                  // Botón fijo de agregar al carrito
                  if (_selectedQuantities.isNotEmpty) _buildFixedCartButton(),

                  // Espacio final
                  const SizedBox(height: 16),
                ],
              ),
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
              ? Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Center(
                      child: Icon(
                        Icons.shopping_bag_rounded,
                        size: 100,
                        color: Colors.grey[300],
                      ),
                    );
                  },
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
            const SizedBox(height: 8),
            const SizedBox(height: 8),
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
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.successColor.withOpacity(0.1),
                          AppTheme.successColor.withOpacity(0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.successColor.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.inventory_2_rounded,
                          size: 18,
                          color: AppTheme.successColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${_productDetails?['cantidad_total'] ?? 0} en stock',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.successColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Variantes
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primaryColor.withOpacity(0.1),
                          AppTheme.primaryColor.withOpacity(0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.primaryColor.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.widgets_rounded,
                          size: 18,
                          color: AppTheme.primaryColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${_variants.length} opciones',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
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

  Widget _buildDescriptionSection() {
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
                  Icons.description_rounded,
                  color: AppTheme.primaryColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Descripción del Producto',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _productDetails!['descripcion'],
            style: TextStyle(
              fontSize: 15,
              color: AppTheme.textSecondary.withOpacity(0.9),
              height: 1.6,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVariantsSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
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
                      AppTheme.accentColor.withOpacity(0.2),
                      AppTheme.accentColor.withOpacity(0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.shopping_basket_rounded,
                  color: AppTheme.accentColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Elige tu Presentación',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryColor,
                      AppTheme.primaryColor.withOpacity(0.8),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primaryColor.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  '${_variants.length}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (_variants.isEmpty)
            Center(
              child: Container(
                padding: const EdgeInsets.all(32),
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
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 48,
                      color: AppTheme.textSecondary.withOpacity(0.5),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No hay presentaciones disponibles',
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
          else
            _buildSingleVariantCard(),
        ],
      ),
    );
  }

  Widget _buildSingleVariantCard() {
    if (_selectedVariant == null) return const SizedBox.shrink();

    final variantId = _selectedVariant!['id'] as String;
    final descripcion = _selectedVariant!['descripcion'] as String?;
    final precio = (_selectedVariant!['precio'] as num?)?.toDouble() ?? 0.0;
    final cantidadTotal = _selectedVariant!['cantidad_total'] as int? ?? 0;
    final currentQuantity = _selectedQuantities[variantId] ?? 0;
    final isSelected = currentQuantity > 0;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? AppTheme.primaryColor
              : Colors.grey.withOpacity(0.1),
          width: isSelected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isSelected
                ? AppTheme.primaryColor.withOpacity(0.2)
                : Colors.black.withOpacity(0.05),
            blurRadius: isSelected ? 15 : 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Dropdown selector de presentación
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primaryColor.withOpacity(0.08),
                    AppTheme.primaryColor.withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.primaryColor.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<Map<String, dynamic>>(
                  value: _selectedVariant,
                  isExpanded: true,
                  icon: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: AppTheme.primaryColor,
                    size: 24,
                  ),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                  items: _variants.map((variant) {
                    final vNombre = variant['nombre'] as String? ?? 'Variante';
                    final vEsBase = variant['es_base'] as bool? ?? false;
                    return DropdownMenuItem<Map<String, dynamic>>(
                      value: variant,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              vNombre,
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (vEsBase)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.warningColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.star_rounded,
                                    size: 10,
                                    color: AppTheme.warningColor,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    'Base',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.warningColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (newVariant) {
                    setState(() {
                      _selectedVariant = newVariant;
                      // Limpiar cantidad anterior si cambia de variante
                      _selectedQuantities.clear();
                    });
                  },
                ),
              ),
            ),

            if (descripcion != null) ...[
              const SizedBox(height: 8),
              Text(
                descripcion,
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary.withOpacity(0.85),
                  height: 1.2,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            const SizedBox(height: 12),

            // Precio y stock
            Row(
              children: [
                Text(
                  '\$${precio.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.accentColor,
                    letterSpacing: -0.3,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: cantidadTotal > 0
                        ? AppTheme.successColor.withOpacity(0.08)
                        : AppTheme.errorColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: cantidadTotal > 0
                          ? AppTheme.successColor.withOpacity(0.2)
                          : AppTheme.errorColor.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.inventory_2_rounded,
                        size: 14,
                        color: cantidadTotal > 0
                            ? AppTheme.successColor
                            : AppTheme.errorColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$cantidadTotal disponibles',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cantidadTotal > 0
                              ? AppTheme.successColor
                              : AppTheme.errorColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Selector de cantidad
            Row(
              children: [
                // Botón menos
                Container(
                  decoration: BoxDecoration(
                    color: currentQuantity > 0
                        ? AppTheme.primaryColor.withOpacity(0.08)
                        : Colors.grey.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: IconButton(
                    onPressed: currentQuantity > 0
                        ? () => _updateQuantity(variantId, currentQuantity - 1)
                        : null,
                    icon: const Icon(Icons.remove_rounded),
                    color: AppTheme.primaryColor,
                    iconSize: 22,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                  ),
                ),

                // Cantidad
                Expanded(
                  child: Container(
                    alignment: Alignment.center,
                    child: Text(
                      '$currentQuantity',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: isSelected
                            ? AppTheme.primaryColor
                            : AppTheme.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                ),

                // Botón más
                Container(
                  decoration: BoxDecoration(
                    color: currentQuantity < cantidadTotal
                        ? AppTheme.primaryColor.withOpacity(0.08)
                        : Colors.grey.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: IconButton(
                    onPressed: currentQuantity < cantidadTotal
                        ? () => _updateQuantity(variantId, currentQuantity + 1)
                        : null,
                    icon: const Icon(Icons.add_rounded),
                    color: AppTheme.primaryColor,
                    iconSize: 22,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                  ),
                ),
              ],
            ),

            // Subtotal
            if (currentQuantity > 0) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryColor.withOpacity(0.08),
                      AppTheme.primaryColor.withOpacity(0.12),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppTheme.primaryColor.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Subtotal:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    Text(
                      '\$${(precio * currentQuantity).toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primaryColor,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFixedCartButton() {
    final totalItems = _selectedQuantities.values.fold<int>(
      0,
      (sum, qty) => sum + qty,
    );
    final totalPrice = _selectedQuantities.entries.fold<double>(0.0, (
      sum,
      entry,
    ) {
      final variant = _variants.firstWhere((v) => v['id'] == entry.key);
      final precio = (variant['precio'] as num?)?.toDouble() ?? 0.0;
      return sum + (precio * entry.value);
    });

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      height: 100,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Colors.white.withOpacity(0.95)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppTheme.primaryColor.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Información del total
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primaryColor.withOpacity(0.15),
                        AppTheme.primaryColor.withOpacity(0.08),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$totalItems ${totalItems == 1 ? 'producto' : 'productos'}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primaryColor.withOpacity(0.9),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Text(
                      'Total: ',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '\$${totalPrice.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.accentColor,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Botón de agregar
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.primaryColor,
                  AppTheme.primaryColor.withOpacity(0.8),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withOpacity(0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: _addToCart,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.shopping_cart_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Agregar',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
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
}
