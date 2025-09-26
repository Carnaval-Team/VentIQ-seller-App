import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/order_service.dart';
import '../services/product_detail_service.dart';
import '../services/promotion_service.dart';
import '../services/user_preferences_service.dart';
import '../services/currency_service.dart';
import '../utils/price_utils.dart';
import '../widgets/bottom_navigation.dart';
import '../widgets/elaborated_product_chip.dart';

class ProductDetailsScreen extends StatefulWidget {
  final Product product;
  final Color categoryColor;

  const ProductDetailsScreen({
    Key? key,
    required this.product,
    required this.categoryColor,
  }) : super(key: key);

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  ProductVariant? selectedVariant;
  int selectedQuantity = 1;
  Map<ProductVariant, int> variantQuantities = {};
  Map<String, List<ProductVariant>> locationGroups =
      {}; // Group variants by location
  final ProductDetailService _productDetailService = ProductDetailService();
  final UserPreferencesService _userPreferencesService =
      UserPreferencesService();
  final PromotionService _promotionService = PromotionService();
  Product? _detailedProduct;
  bool _isLoadingDetails = false;
  String? _errorMessage;
  Map<String, dynamic>? _globalPromotionData;
  Map<String, dynamic>? _productPromotionData;

  // USD rate data
  double _usdRate = 0.0;
  bool _isLoadingUsdRate = false;

  // Presentaciones data
  List<ProductPresentation> _productPresentations = [];
  ProductPresentation? _selectedPresentation;
  bool _isLoadingPresentations = false;
  Map<String, ProductPresentation?> _selectedPresentationsByProduct = {};

  @override
  void initState() {
    super.initState();
    // Inicializar cantidades de variantes
    for (var variant in widget.product.variantes) {
      variantQuantities[variant] = 0;
    }
    // Group variants by location
    _groupVariantsByLocation(widget.product.variantes);
    // Cargar detalles completos del producto
    _loadProductDetails();
    _loadPromotionData();
    _loadUsdRate();
    _loadProductPresentations();
  }

  /// Cargar detalles completos del producto desde Supabase
  Future<void> _loadProductDetails() async {
    setState(() {
      _isLoadingDetails = true;
      _errorMessage = null;
    });

    try {
      final detailedProduct = await _productDetailService.getProductDetail(
        widget.product.id,
      );

      setState(() {
        _detailedProduct = detailedProduct;
        _isLoadingDetails = false;

        // Reinicializar cantidades de variantes con los nuevos datos
        variantQuantities.clear();
        locationGroups.clear();

        // Group variants by warehouse location
        _groupVariantsByLocation(detailedProduct.variantes);

        for (var variant in detailedProduct.variantes) {
          variantQuantities[variant] = 0;
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error al cargar detalles: $e';
        _isLoadingDetails = false;
      });
    }
  }

  void _loadPromotionData() async {
    try {
      // Obtener ID de tienda
      final idTienda = await _userPreferencesService.getIdTienda();
      if (idTienda == null) {
        print('❌ No se pudo obtener ID de tienda para promociones');
        return;
      }

      // Cargar promoción global
      final globalPromotion = await _promotionService.getGlobalPromotion(
        idTienda,
      );

      // Cargar promoción específica del producto
      final productPromotion = await _promotionService.getProductPromotion(
        idTienda,
        currentProduct.denominacion,
      );

      setState(() {
        _globalPromotionData = globalPromotion;
        _productPromotionData = productPromotion;
      });

      print('🎯 Promociones cargadas:');
      print(
        '  - Global: ${globalPromotion != null ? globalPromotion['codigo_promocion'] : 'No'}',
      );
      print(
        '  - Producto: ${productPromotion != null ? productPromotion['codigo_promocion'] : 'No'}',
      );
    } catch (e) {
      print('❌ Error cargando promociones: $e');
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

  /// Cargar presentaciones del producto desde Supabase
  Future<void> _loadProductPresentations() async {
    setState(() {
      _isLoadingPresentations = true;
    });

    try {
      debugPrint(
        '🔍 Cargando presentaciones para producto ID: ${widget.product.id}',
      );

      final presentations = await _productDetailService.getProductPresentations(
        widget.product.id,
      );

      setState(() {
        _productPresentations = presentations;
        _isLoadingPresentations = false;

        // Inicializar presentación seleccionada para este producto específico
        final productKey = '${widget.product.id}';

        if (presentations.isNotEmpty) {
          final basePresentations =
              presentations.where((p) => p.esBase).toList();
          if (basePresentations.isNotEmpty) {
            _selectedPresentation = basePresentations.first;
            _selectedPresentationsByProduct[productKey] =
                basePresentations.first;
            debugPrint(
              '✅ Presentación base seleccionada: ${_selectedPresentation!.presentacion.denominacion}',
            );
          } else {
            _selectedPresentation = presentations.first;
            _selectedPresentationsByProduct[productKey] = presentations.first;
            debugPrint(
              '✅ Primera presentación seleccionada: ${_selectedPresentation!.presentacion.denominacion}',
            );
          }
        } else {
          debugPrint(
            '⚠️ No hay presentaciones configuradas, usando presentación por defecto',
          );
          _selectedPresentation = null;
          _selectedPresentationsByProduct[productKey] = null;
        }
      });
    } catch (e) {
      debugPrint('❌ Error cargando presentaciones: $e');
      setState(() {
        _productPresentations = [];
        _selectedPresentation = null;
        _isLoadingPresentations = false;
      });
    }
  }

  /// Calcula el precio con descuento, priorizando promoción de producto sobre global
  Map<String, double> _calculatePromotionPrices(double originalPrice) {
    // Priorizar promoción específica del producto sobre promoción global
    final activePromotion = _productPromotionData ?? _globalPromotionData;

    if (activePromotion == null) {
      return {'precio_venta': originalPrice, 'precio_oferta': originalPrice};
    }

    final valorDescuento = activePromotion['valor_descuento'] as double?;
    final tipoDescuento = activePromotion['tipo_descuento'] as int?;

    return PriceUtils.calculatePromotionPrices(
      originalPrice,
      valorDescuento,
      tipoDescuento,
    );
  }

  /// Método de compatibilidad para el precio con descuento (mantiene funcionalidad existente)
  double? _calculateDiscountPrice(double originalPrice) {
    final prices = _calculatePromotionPrices(originalPrice);

    // Si hay promoción activa, retornar el precio de oferta
    if (prices['precio_oferta'] != originalPrice) {
      return prices['precio_oferta'];
    }

    return null;
  }

  /// Obtiene información de la promoción activa
  Map<String, dynamic>? _getActivePromotion() {
    return _productPromotionData ?? _globalPromotionData;
  }

  Widget _buildPriceSection(double originalPrice) {
    final prices = _calculatePromotionPrices(originalPrice);
    final activePromotion = _getActivePromotion();

    // Determinar si hay promoción activa
    final hasPromotion =
        prices['precio_oferta'] != originalPrice ||
        prices['precio_venta'] != originalPrice;

    if (hasPromotion && activePromotion != null) {
      final tipoDescuento = activePromotion['tipo_descuento'] as int?;
      final isRecargo = tipoDescuento == 3; // Recargo porcentual

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mostrar tipo de promoción
          if (activePromotion['tipo_promocion_nombre'] != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color:
                    isRecargo
                        ? Colors.orange.withOpacity(0.1)
                        : Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isRecargo ? Colors.orange : Colors.green,
                  width: 1,
                ),
              ),
              child: Text(
                activePromotion['tipo_promocion_nombre'],
                style: TextStyle(
                  fontSize: 10,
                  color: isRecargo ? Colors.orange[700] : Colors.green[700],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

          // Precio de venta (normal o intercambiado)
          Row(
            children: [
              Text(
                isRecargo ? 'Precio venta: ' : 'Precio base: ',
                style: TextStyle(
                  fontSize: 12,
                  color: isRecargo ? widget.categoryColor : Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '\$${prices['precio_venta']!.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: isRecargo ? 16 : 14,
                  color: isRecargo ? widget.categoryColor : Colors.grey[600],
                  fontWeight: isRecargo ? FontWeight.w600 : FontWeight.w500,
                  decoration: isRecargo ? null : TextDecoration.lineThrough,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Precio de oferta (normal o intercambiado)
          Row(
            children: [
              Text(
                isRecargo ? 'Precio oferta: ' : 'Precio oferta: ',
                style: TextStyle(
                  fontSize: 12,
                  color: isRecargo ? Colors.grey[600] : widget.categoryColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '\$${PriceUtils.formatDiscountPrice(prices['precio_oferta']!)}',
                style: TextStyle(
                  fontSize: isRecargo ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  color: isRecargo ? Colors.grey[600] : widget.categoryColor,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ],
      );
    } else {
      return Text(
        '\$${originalPrice.toStringAsFixed(2)}',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: widget.categoryColor,
          height: 1.2,
        ),
      );
    }
  }

  Widget _buildVariantPriceSection(double originalPrice) {
    final prices = _calculatePromotionPrices(originalPrice);
    final activePromotion = _getActivePromotion();
    final hasPromotion =
        prices['precio_oferta'] != originalPrice ||
        prices['precio_venta'] != originalPrice;

    if (hasPromotion && activePromotion != null) {
      final tipoDescuento = activePromotion['tipo_descuento'] as int?;
      final isRecargo = tipoDescuento == 3; // Recargo porcentual

      // Para recargo porcentual, mostrar el precio de venta (mayor)
      // Para descuentos, mostrar el precio de oferta (menor)
      final displayPrice =
          isRecargo ? prices['precio_venta']! : prices['precio_oferta']!;

      return Text(
        '\$${PriceUtils.formatDiscountPrice(displayPrice)}',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: widget.categoryColor,
          height: 1.2,
        ),
        overflow: TextOverflow.ellipsis,
      );
    } else {
      return Text(
        '\$${originalPrice.toStringAsFixed(2)}',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: widget.categoryColor,
          height: 1.2,
        ),
        overflow: TextOverflow.ellipsis,
      );
    }
  }

  /// Get the current product (detailed if loaded, otherwise fallback to original)
  Product get currentProduct => _detailedProduct ?? widget.product;

  double get totalPrice {
    double total = 0.0;

    if (currentProduct.variantes.isEmpty) {
      // Producto sin variantes - siempre usar precio_oferta
      final prices = _calculatePromotionPrices(currentProduct.precio);
      final finalPrice = prices['precio_oferta']!;
      total = finalPrice * selectedQuantity;
    } else {
      // Producto con variantes - siempre usar precio_oferta
      for (var entry in variantQuantities.entries) {
        final prices = _calculatePromotionPrices(entry.key.precio);
        final finalPrice = prices['precio_oferta']!;
        total += finalPrice * entry.value;
      }
    }

    return total;
  }

  int get maxQuantityForProduct {
    return currentProduct.cantidad.toInt();
  }

  int maxQuantityForVariant(ProductVariant variant) {
    return variant.cantidad.toInt();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A90E2),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back,
            color: Color.fromARGB(255, 255, 255, 255),
            size: 28,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                currentProduct.denominacion,
                style: const TextStyle(
                  color: Color.fromARGB(255, 255, 255, 255),
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // const SizedBox(width: 8),
            // ElaboratedProductChip(
            //   productId: currentProduct.id,
            //   productName: currentProduct.denominacion,
            // ),
          ],
        ),
        centerTitle: true,
      ),
      bottomNavigationBar: AppBottomNavigation(
        currentIndex: 0, // No tab selected since this is a detail screen
        onTap: _onBottomNavTap,
      ),
      body: Stack(
        children: [
          _isLoadingDetails
              ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF4A90E2)),
                    SizedBox(height: 16),
                    Text(
                      'Cargando detalles del producto...',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),
              )
              : _errorMessage != null
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                    const SizedBox(height: 16),
                    Text(
                      'Error al cargar detalles',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage!,
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _loadProductDetails,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4A90E2),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              )
              : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sección superior: Imagen y información del producto
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Imagen del producto
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.grey[300]!,
                              width: 1,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(11),
                            child:
                                currentProduct.foto != null
                                    ? Image.network(
                                      _compressImageUrl(currentProduct.foto!),
                                      fit: BoxFit.cover,
                                      errorBuilder: (
                                        context,
                                        error,
                                        stackTrace,
                                      ) {
                                        return Container(
                                          color: Colors.grey[100],
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              const Icon(
                                                Icons.inventory_2,
                                                color: Colors.grey,
                                                size: 32,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Sin imagen',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                      loadingBuilder: (
                                        context,
                                        child,
                                        loadingProgress,
                                      ) {
                                        if (loadingProgress == null)
                                          return child;
                                        return Container(
                                          color: Colors.grey[100],
                                          child: const Center(
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        );
                                      },
                                    )
                                    : Container(
                                      color: Colors.grey[100],
                                      child: const Icon(
                                        Icons.inventory_2,
                                        color: Colors.grey,
                                        size: 40,
                                      ),
                                    ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Información del producto
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Denominación con chip de producto elaborado
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      currentProduct.denominacion,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1F2937),
                                        height: 1.2,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElaboratedProductChip(
                                    productId: currentProduct.id,
                                    productName: currentProduct.denominacion,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              // Categoría
                              Text(
                                currentProduct.categoria,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                  height: 1.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              // Precio del producto con descuento
                              _buildPriceSection(currentProduct.precio),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Sección de ubicaciones (agrupadas por almacén-ubicación)
                    if (currentProduct.variantes.isNotEmpty) ...[
                      Text(
                        'UBICACIONES:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[800],
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Lista de ubicaciones con variantes agrupadas
                      ...locationGroups.entries.map((locationEntry) {
                        return _buildLocationGroup(
                          locationEntry.key,
                          locationEntry.value,
                        );
                      }).toList(),
                      const SizedBox(height: 16),
                    ],
                    // Productos seleccionados
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[200]!, width: 1),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Productos seleccionados',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[800],
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Lista de productos seleccionados
                          if (currentProduct.variantes.isEmpty &&
                              selectedQuantity > 0)
                            _buildSelectedProductItem(
                              currentProduct.denominacion,
                              selectedQuantity,
                              currentProduct.precio,
                              _getLocationName(currentProduct, null),
                              isVariant: false,
                            ),
                          if (currentProduct.variantes.isNotEmpty)
                            ...variantQuantities.entries
                                .where((entry) => entry.value > 0)
                                .map(
                                  (entry) => _buildSelectedProductItem(
                                    '${currentProduct.denominacion} - ${entry.key.nombre}',
                                    entry.value,
                                    entry.key.precio,
                                    _getLocationName(currentProduct, entry.key),
                                    isVariant: true,
                                  ),
                                ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Fila con total y botón de agregar
                    Row(
                      children: [
                        // Total de productos seleccionados
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.grey[300]!,
                                width: 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'TOTAL: ${_getTotalItems()} producto${_getTotalItems() == 1 ? '' : 's'}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[700],
                                  ),
                                ),
                                Text(
                                  '\$${totalPrice.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: widget.categoryColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Botón de agregar
                        SizedBox(
                          width: 120,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: totalPrice > 0 ? _addToCart : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: widget.categoryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              elevation: 0,
                            ),
                            child: const Text(
                              'Agregar',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          // USD Rate Chip positioned at bottom left
          // Positioned(
          //   bottom: 0,
          //   left: 0,
          //   child: _buildUsdRateChip(),
          // ),
        ],
      ),
    );
  }

  // Método para construir grupo de ubicación con sus variantes
  Widget _buildLocationGroup(
    String locationName,
    List<ProductVariant> variants,
  ) {
    final totalStock = _getLocationStock(variants);
    final locationColor = _getLocationColor(locationName);
    final locationColorLight = locationColor.withOpacity(0.1);
    final locationColorSemi = locationColor.withOpacity(0.2);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: locationColor.withOpacity(0.3), width: 1),
        boxShadow: [
          BoxShadow(
            color: locationColor.withOpacity(0.1),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header de la ubicación con color único
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: locationColorLight,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(7),
                topRight: Radius.circular(7),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.location_on, color: locationColor, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    locationName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: locationColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: locationColorSemi,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$totalStock',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: locationColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Lista de variantes en esta ubicación
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children:
                  variants.map((variant) {
                    final isSelected = variantQuantities[variant]! > 0;
                    return _buildLocationVariantCard(variant, isSelected, locationColor);
                  }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // Método para construir card de variante dentro de una ubicación
  Widget _buildLocationVariantCard(ProductVariant variant, bool isSelected, Color locationColor) {
    int currentQuantity = variantQuantities[variant] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: () {
          setState(() {
            if (currentQuantity == 0) {
              variantQuantities[variant] = 1;
            } else {
              variantQuantities[variant] = 0;
            }
          });
        },
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color:
                isSelected
                    ? locationColor.withOpacity(0.1)
                    : Colors.grey[50],
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected ? locationColor : Colors.grey[300]!,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              // Imagen pequeña de la variante con color de ubicación
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: isSelected ? locationColor.withOpacity(0.1) : Colors.grey[100],
                  border: Border.all(
                    color: isSelected ? locationColor.withOpacity(0.3) : Colors.grey[300]!, 
                    width: 1
                  ),
                ),
                child: Icon(
                  Icons.inventory_2,
                  color: isSelected ? locationColor : Colors.grey,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              // Información de la variante
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nombre de la variante
                    Text(
                      variant.nombre,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color:
                            isSelected
                                ? locationColor
                                : const Color(0xFF1F2937),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    // Precio y stock
                    Row(
                      children: [
                        _buildVariantPriceSection(variant.precio),
                        const SizedBox(width: 6),
                        Container(
                          width: 3,
                          height: 3,
                          decoration: BoxDecoration(
                            color: isSelected ? locationColor.withOpacity(0.6) : Colors.grey[400],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Stock: ${variant.cantidad}',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Indicador de selección con color de ubicación
              if (isSelected)
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: locationColor,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 12),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Método para construir items de productos seleccionados
  Widget _buildSelectedProductItem(
    String name,
    int quantity,
    double price,
    String ubicacion, {
    bool isVariant = false,
  }) {
    final locationColor = _getLocationColor(ubicacion);
    final prices = _calculatePromotionPrices(price);
    final activePromotion = _getActivePromotion();
    final isRecargo =
        activePromotion != null && activePromotion['tipo_descuento'] == 3;

    // Siempre usar precio_oferta para mostrar en productos seleccionados
    final finalPrice = prices['precio_oferta']!;
    final hasPromotion =
        prices['precio_oferta'] != price || prices['precio_venta'] != price;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fila superior: Nombre del producto y total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: locationColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '\$${_calculateTotalPriceWithPresentation(finalPrice, quantity, currentProduct).toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: locationColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Fila media: Ubicación y precio unitario
          Row(
            children: [
              Icon(
                Icons.location_on,
                size: 16,
                color: locationColor,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  ubicacion,
                  style: TextStyle(
                    fontSize: 13,
                    color: locationColor,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              hasPromotion
                  ? Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        isRecargo
                            ? 'Venta: \$${prices['precio_venta']!.toStringAsFixed(2)}'
                            : 'Base: \$${price.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w400,
                          decoration:
                              isRecargo ? null : TextDecoration.lineThrough,
                        ),
                      ),
                      Text(
                        isRecargo
                            ? 'Oferta: \$${PriceUtils.formatDiscountPrice(prices['precio_oferta']!)}'
                            : 'Oferta: \$${PriceUtils.formatDiscountPrice(finalPrice)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: locationColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                  : Text(
                    'Precio: \$${price.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 13,
                      color: locationColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
            ],
          ),
          const SizedBox(height: 12),
          // Fila de presentación
          _buildPresentationSelector(currentProduct),
          const SizedBox(height: 8),
          // Fila inferior: Controles de cantidad
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Cantidad:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[800],
                ),
              ),
              // Controles de cantidad mejorados
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () {
                        setState(() {
                          if (currentProduct.variantes.isEmpty) {
                            if (selectedQuantity > 0) selectedQuantity--;
                          } else {
                            // Buscar la variante correspondiente
                            for (var variant in currentProduct.variantes) {
                              if (name.contains(variant.nombre)) {
                                if (variantQuantities[variant]! > 0) {
                                  variantQuantities[variant] =
                                      variantQuantities[variant]! - 1;
                                }
                                break;
                              }
                            }
                          }
                        });
                      },
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(7),
                        bottomLeft: Radius.circular(7),
                      ),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color:
                              quantity > 0
                                  ? widget.categoryColor.withOpacity(0.1)
                                  : Colors.grey[50],
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(7),
                            bottomLeft: Radius.circular(7),
                          ),
                        ),
                        child: Icon(
                          Icons.remove,
                          size: 18,
                          color:
                              quantity > 0
                                  ? widget.categoryColor
                                  : Colors.grey[400],
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => _showQuantityDialog(name, quantity),
                      child: Container(
                        width: 50,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          border: Border.symmetric(
                            vertical: BorderSide(
                              color: Colors.grey[300]!,
                              width: 1,
                            ),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '$quantity',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        setState(() {
                          if (currentProduct.variantes.isEmpty) {
                            if (selectedQuantity < maxQuantityForProduct)
                              selectedQuantity++;
                          } else {
                            // Buscar la variante correspondiente
                            for (var variant in currentProduct.variantes) {
                              if (name.contains(variant.nombre)) {
                                if (variantQuantities[variant]! <
                                    variant.cantidad) {
                                  variantQuantities[variant] =
                                      variantQuantities[variant]! + 1;
                                }
                                break;
                              }
                            }
                          }
                        });
                      },
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(7),
                        bottomRight: Radius.circular(7),
                      ),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: widget.categoryColor.withOpacity(0.1),
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(7),
                            bottomRight: Radius.circular(7),
                          ),
                        ),
                        child: Icon(
                          Icons.add,
                          size: 18,
                          color: widget.categoryColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Construir selector de presentaciones para un producto
  Widget _buildPresentationSelector(Product product) {
    // Obtener la presentación seleccionada para este producto específico
    final productKey = '${product.id}';
    final selectedPresentationForProduct =
        _selectedPresentationsByProduct[productKey];

    // Si no hay presentaciones cargadas, mostrar presentación por defecto
    if (_productPresentations.isEmpty) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Presentación:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey[800],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.inventory_2, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Text(
                  'Unidad (1.0)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Presentación:',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.grey[800],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!, width: 1),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<ProductPresentation>(
              value: selectedPresentationForProduct,
              isDense: true,
              items:
                  _productPresentations.map((presentation) {
                    return DropdownMenuItem<ProductPresentation>(
                      value: presentation,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (presentation.esBase) ...[
                            Icon(
                              Icons.star,
                              size: 14,
                              color: Colors.orange[600],
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            '${presentation.presentacion.denominacion} (${presentation.cantidad})',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight:
                                  presentation.esBase
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                              color:
                                  presentation.esBase
                                      ? Colors.orange[700]
                                      : Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
              onChanged: (ProductPresentation? newPresentation) {
                setState(() {
                  _selectedPresentationsByProduct[productKey] = newPresentation;
                  debugPrint(
                    '🔄 Presentación cambiada para producto ${product.id}: ${newPresentation?.presentacion.denominacion} (Factor: ${newPresentation?.cantidad})',
                  );
                });
              },
            ),
          ),
        ),
      ],
    );
  }

  /// Obtener el factor de conversión de la presentación seleccionada para un producto
  double _getPresentationConversionFactor(Product product) {
    final productKey = '${product.id}';
    final selectedPresentation = _selectedPresentationsByProduct[productKey];

    if (selectedPresentation != null) {
      debugPrint(
        '📊 Factor de conversión para producto ${product.id}: ${selectedPresentation.cantidad} (${selectedPresentation.presentacion.denominacion})',
      );
      return selectedPresentation.cantidad;
    }

    // Si no hay presentación seleccionada, usar presentación por defecto (1.0)
    debugPrint(
      '📊 Usando factor de conversión por defecto: 1.0 para producto ${product.id}',
    );
    return 1.0;
  }

  /// Calcular el precio total considerando la presentación seleccionada
  double _calculateTotalPriceWithPresentation(
    double basePrice,
    int quantity,
    Product product,
  ) {
    final conversionFactor = _getPresentationConversionFactor(product);
    final unitPrice = basePrice * conversionFactor;
    final totalPrice = unitPrice * quantity;

    debugPrint('💰 Cálculo precio para producto ${product.id}:');
    debugPrint('   - Precio base: \$${basePrice.toStringAsFixed(2)}');
    debugPrint('   - Factor conversión: ${conversionFactor}');
    debugPrint('   - Precio unitario: \$${unitPrice.toStringAsFixed(2)}');
    debugPrint('   - Cantidad: $quantity');
    debugPrint('   - Precio total: \$${totalPrice.toStringAsFixed(2)}');

    return totalPrice;
  }

  // Método para obtener el total de items
  int _getTotalItems() {
    int total = 0;
    if (currentProduct.variantes.isEmpty) {
      total = selectedQuantity;
    } else {
      for (var quantity in variantQuantities.values) {
        total += quantity;
      }
    }
    return total;
  }

  void _showQuantityDialog(String productName, int currentQuantity) {
    final TextEditingController quantityController = TextEditingController(
      text: currentQuantity.toString(),
    );

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            'Cantidad',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: widget.categoryColor,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                productName,
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: quantityController,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Cantidad deseada',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: widget.categoryColor),
                  ),
                ),
                onSubmitted: (value) {
                  _updateQuantityFromDialog(productName, value);
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                _updateQuantityFromDialog(productName, quantityController.text);
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.categoryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirmar'),
            ),
          ],
        );
      },
    );
  }

  void _updateQuantityFromDialog(String productName, String quantityText) {
    final int? newQuantity = int.tryParse(quantityText);
    if (newQuantity == null || newQuantity < 0) return;

    setState(() {
      if (currentProduct.variantes.isEmpty) {
        // Producto sin variantes
        selectedQuantity = newQuantity;
      } else {
        // Buscar la variante correspondiente
        for (var variant in currentProduct.variantes) {
          if (productName.contains(variant.nombre)) {
            variantQuantities[variant] = newQuantity;
            break;
          }
        }
      }
    });
  }

  /// Group variants by warehouse location (almacen_nombre - ubicacion_nombre)
  void _groupVariantsByLocation(List<ProductVariant> variants) {
    locationGroups.clear();

    for (var variant in variants) {
      String locationKey = _getLocationKey(variant);

      if (locationGroups.containsKey(locationKey)) {
        locationGroups[locationKey]!.add(variant);
      } else {
        locationGroups[locationKey] = [variant];
      }
    }

    print('🏪 Grupos de ubicación creados: ${locationGroups.keys.toList()}');
    for (var entry in locationGroups.entries) {
      print('   ${entry.key}: ${entry.value.length} variantes');
    }

    // Si solo hay una ubicación, seleccionar automáticamente la primera variante
    _autoSelectSingleLocation();
  }

  /// Selecciona automáticamente la primera variante si solo hay una ubicación
  void _autoSelectSingleLocation() {
    if (locationGroups.length == 1) {
      final singleLocationEntry = locationGroups.entries.first;
      final locationKey = singleLocationEntry.key;
      final variants = singleLocationEntry.value;
      
      if (variants.isNotEmpty) {
        final firstVariant = variants.first;
        
        print('🎯 Solo una ubicación disponible: $locationKey');
        print('🎯 Seleccionando automáticamente variante: ${firstVariant.nombre}');
        
        // Seleccionar la primera variante automáticamente
        // Usar addPostFrameCallback para asegurar que el setState se ejecute correctamente
        WidgetsBinding.instance.addPostFrameCallback((_) {
          setState(() {
            selectedVariant = firstVariant;
            // Establecer cantidad inicial de 1 para la variante seleccionada
            variantQuantities[firstVariant] = 1;
            print('🔄 setState ejecutado - selectedVariant: ${selectedVariant?.nombre}');
            print('🔄 variantQuantities actualizado: ${variantQuantities.entries.where((e) => e.value > 0).map((e) => '${e.key.nombre}: ${e.value}').toList()}');
          });
        });
        
        print('🎯 Variante seleccionada automáticamente: ${firstVariant.nombre} con cantidad 1');
      }
    } else {
      print('🏪 Múltiples ubicaciones disponibles (${locationGroups.length}), mostrando opciones al usuario');
    }
  }

  /// Genera un color único para cada ubicación basado en el color de la categoría
  Color _getLocationColor(String locationName) {
    // Crear un hash simple del nombre de la ubicación
    int hash = locationName.hashCode;
    
    // Obtener los componentes RGB del color de la categoría
    int red = widget.categoryColor.red;
    int green = widget.categoryColor.green;
    int blue = widget.categoryColor.blue;
    
    // Generar variaciones del color base usando el hash
    // Usar diferentes operaciones para cada componente RGB
    int newRed = ((red + (hash % 60) - 30).clamp(50, 255)).toInt();
    int newGreen = ((green + ((hash >> 8) % 60) - 30).clamp(50, 255)).toInt();
    int newBlue = ((blue + ((hash >> 16) % 60) - 30).clamp(50, 255)).toInt();
    
    return Color.fromARGB(255, newRed, newGreen, newBlue);
  }


  /// Get location key from variant's inventory metadata
  String _getLocationKey(ProductVariant variant) {
    final metadata = variant.inventoryMetadata;
    if (metadata != null) {
      final almacenNombre = metadata['almacen_nombre'] as String?;
      final ubicacionNombre = metadata['ubicacion_nombre'] as String?;

      if (almacenNombre != null && ubicacionNombre != null) {
        return '$almacenNombre - $ubicacionNombre';
      } else if (almacenNombre != null) {
        return almacenNombre;
      } else if (ubicacionNombre != null) {
        return ubicacionNombre;
      }
    }

    // Fallback for variants without location metadata
    return 'Ubicación no especificada';
  }

  /// Get total stock for a location group
  int _getLocationStock(List<ProductVariant> variants) {
    return variants.fold(0, (sum, variant) => sum + variant.cantidad.toInt());
  }

  String _compressImageUrl(String url) {
    if (url.contains('images.unsplash.com') ||
        url.contains('plus.unsplash.com')) {
      // Si ya tiene parámetros, reemplazar o agregar los de compresión
      final uri = Uri.parse(url);
      final params = Map<String, String>.from(uri.queryParameters);

      // Aplicar compresión
      params['q'] = '60';
      params['w'] = '600';
      params['fm'] = 'webp';

      return uri.replace(queryParameters: params).toString();
    }
    return url;
  }

  // Get location name from inventory metadata
  String _getLocationName(Product product, ProductVariant? variant) {
    Map<String, dynamic>? inventoryMetadata;

    if (variant != null) {
      inventoryMetadata = variant.inventoryMetadata;
    } else {
      inventoryMetadata = product.inventoryMetadata;
    }

    if (inventoryMetadata != null) {
      final ubicacionNombre = inventoryMetadata['ubicacion_nombre'] as String?;
      final almacenNombre = inventoryMetadata['almacen_nombre'] as String?;

      if (ubicacionNombre != null && almacenNombre != null) {
        return '$almacenNombre - $ubicacionNombre';
      } else if (ubicacionNombre != null) {
        return ubicacionNombre;
      } else if (almacenNombre != null) {
        return almacenNombre;
      }
    }

    // Fallback to default location names
    if (variant != null) {
      return 'Almacén B-${variant.nombre.substring(0, 1)}';
    } else {
      return 'Almacén A-1';
    }
  }

  // Build inventory data for fn_registrar_venta RPC
  Map<String, dynamic> _buildInventoryData(
    Product product,
    ProductVariant? variant,
  ) {
    // Extract inventory data from the product detail response
    Map<String, dynamic>? inventoryMetadata;

    if (variant != null) {
      // Use variant's inventory metadata
      inventoryMetadata = variant.inventoryMetadata;
      print('🔧 Usando metadata de variante: $inventoryMetadata');
    } else {
      // Use product's inventory metadata (for products without variants)
      inventoryMetadata = product.inventoryMetadata;
      print('🔧 Usando metadata de producto: $inventoryMetadata');
    }

    if (inventoryMetadata == null) {
      print('⚠️ No hay metadata de inventario disponible');
      // Fallback to basic data if no inventory metadata available
      return {
        'id_producto': product.id,
        'id_variante': variant?.id,
        'id_opcion_variante': null,
        'id_ubicacion': null,
        'id_presentacion': null,
        'sku_producto': product.id.toString(),
        'sku_ubicacion': null,
      };
    }

    final inventoryData = {
      'id_producto': product.id,
      'id_variante': inventoryMetadata['id_variante'],
      'id_opcion_variante': inventoryMetadata['id_opcion_variante'],
      'id_ubicacion': inventoryMetadata['id_ubicacion'],
      'id_presentacion': inventoryMetadata['id_presentacion'],
      'sku_producto':
          inventoryMetadata['sku_producto'] ?? product.id.toString(),
      'sku_ubicacion': inventoryMetadata['sku_ubicacion'],
    };

    print('✅ Inventory data construido: $inventoryData');
    return inventoryData;
  }

  void _addToCart() {
    final orderService = OrderService();
    int totalItemsAdded = 0;
    List<String> addedItems = [];

    try {
      if (currentProduct.variantes.isEmpty) {
        // Producto sin variantes
        if (selectedQuantity > 0) {
          final discountPrice = _calculateDiscountPrice(currentProduct.precio);
          final finalPrice = discountPrice ?? currentProduct.precio;

          orderService.addItemToCurrentOrder(
            producto: currentProduct,
            cantidad: selectedQuantity,
            ubicacionAlmacen: _getLocationName(currentProduct, null),
            inventoryData: _buildInventoryData(currentProduct, null),
            precioUnitario: finalPrice,
            precioBase: currentProduct.precio,
            promotionData: _getActivePromotion(),
          );
          totalItemsAdded += selectedQuantity;
          addedItems.add('${currentProduct.denominacion} (x$selectedQuantity)');

          // Resetear cantidad después de agregar
          setState(() {
            selectedQuantity = 0;
          });
        }
      } else {
        // Producto con variantes
        for (var entry in variantQuantities.entries) {
          if (entry.value > 0) {
            final discountPrice = _calculateDiscountPrice(entry.key.precio);
            final finalPrice = discountPrice ?? entry.key.precio;

            orderService.addItemToCurrentOrder(
              producto: currentProduct,
              variante: entry.key,
              cantidad: entry.value,
              ubicacionAlmacen: _getLocationName(currentProduct, entry.key),
              inventoryData: _buildInventoryData(currentProduct, entry.key),
              precioUnitario: finalPrice,
              precioBase: entry.key.precio,
              promotionData: _getActivePromotion(),
            );
            totalItemsAdded += entry.value;
            addedItems.add('${entry.key.nombre} (x${entry.value})');
          }
        }

        // Resetear cantidades después de agregar
        setState(() {
          for (var variant in currentProduct.variantes) {
            variantQuantities[variant] = 0;
          }
        });
      }

      // Mostrar mensaje de éxito y navegar a categorías
      if (totalItemsAdded > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '✅ Agregado a la orden',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  addedItems.join('\n'),
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  'Total en orden: ${orderService.currentOrderItemCount} productos',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ],
            ),
            backgroundColor: widget.categoryColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 2),
          ),
        );

        // Navegar de vuelta a categorías después de agregar productos
        Navigator.pop(context);
      } else {
        // No hay items seleccionados
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              '⚠️ Selecciona al menos un producto o variante',
            ),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // Manejo de errores
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error al agregar: ${e.toString()}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
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
        break;
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
                'USD: ${_usdRate.toStringAsFixed(0)}',
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
}
