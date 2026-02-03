import 'package:flutter/material.dart';
import '../widgets/notification_widget.dart';
import '../utils/app_snackbar.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../services/product_detail_service.dart';
import '../services/promotion_service.dart';
import '../services/user_preferences_service.dart';
import '../utils/price_utils.dart';
import '../utils/promotion_rules.dart';

class FluidProductDetailsWidget extends StatefulWidget {
  final Product product;
  final Function(List<OrderItem>) onCompleted;

  const FluidProductDetailsWidget({
    Key? key,
    required this.product,
    required this.onCompleted,
  }) : super(key: key);

  @override
  State<FluidProductDetailsWidget> createState() =>
      _FluidProductDetailsWidgetState();
}

class _FluidProductDetailsWidgetState extends State<FluidProductDetailsWidget> {
  final ProductDetailService _productDetailService = ProductDetailService();
  final PromotionService _promotionService = PromotionService();
  final UserPreferencesService _userPreferencesService =
      UserPreferencesService();

  // Estados de carga
  bool _isLoadingDetails = true;
  bool _isLoadingPresentations = false;

  // Datos del producto
  Product? _currentProduct;
  List<ProductPresentation> _productPresentations = [];
  ProductPresentation? _selectedPresentation;

  // Variantes y cantidades
  ProductVariant? _selectedVariant;
  Map<ProductVariant, int> _variantQuantities = {};
  Map<String, List<ProductVariant>> _locationGroups = {};

  // Presentaciones
  int _selectedQuantity = 1;

  // Promotion data
  Map<String, dynamic>? _globalPromotionData;
  List<Map<String, dynamic>>? _productPromotionData;

  @override
  void initState() {
    super.initState();
    _loadProductDetails();
  }

  Future<void> _loadProductDetails() async {
    setState(() {
      _isLoadingDetails = true;
    });

    try {
      print('🔍 Cargando detalles del producto: ${widget.product.id}');

      // Cargar detalles completos del producto
      final productDetails = await _productDetailService.getProductDetail(
        widget.product.id,
      );

      if (productDetails != null) {
        setState(() {
          _currentProduct = productDetails;
        });

        // Agrupar variantes por ubicación
        _groupVariantsByLocation();

        // Cargar presentaciones
        await _loadProductPresentations();

        // Cargar datos de promociones
        await _loadPromotionData();
      } else {
        // Si no hay detalles, usar el producto base
        setState(() {
          _currentProduct = widget.product;
        });
      }
    } catch (e) {
      print('❌ Error cargando detalles del producto: $e');
      setState(() {
        _currentProduct = widget.product;
      });
    } finally {
      setState(() {
        _isLoadingDetails = false;
      });
    }
  }

  void _groupVariantsByLocation() {
    if (_currentProduct?.variantes.isEmpty ?? true) return;

    _locationGroups.clear();

    for (final variant in _currentProduct!.variantes) {
      final locationKey = variant.descripcion ?? 'Ubicación desconocida';

      if (!_locationGroups.containsKey(locationKey)) {
        _locationGroups[locationKey] = [];
      }

      _locationGroups[locationKey]!.add(variant);
    }

    print('🏪 Grupos de ubicación creados: ${_locationGroups.keys.toList()}');

    // Selección automática si solo hay una ubicación
    if (_locationGroups.length == 1) {
      _autoSelectSingleLocation();
    }
  }

  void _autoSelectSingleLocation() {
    final firstLocationEntry = _locationGroups.entries.first;
    final locationKey = firstLocationEntry.key;
    final variants = firstLocationEntry.value;

    if (variants.isNotEmpty) {
      final firstVariant = variants.first;

      print('🎯 Solo una ubicación disponible: $locationKey');
      print(
        '🎯 Seleccionando automáticamente variante: ${firstVariant.nombre}',
      );

      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _selectedVariant = firstVariant;
          _variantQuantities[firstVariant] = 1;
        });
      });
    }
  }

  Future<void> _loadProductPresentations() async {
    setState(() {
      _isLoadingPresentations = true;
    });

    try {
      final presentations = await _productDetailService.getProductPresentations(
        widget.product.id,
      );

      setState(() {
        _productPresentations = presentations;

        // Seleccionar presentación base por defecto
        _selectedPresentation = presentations.firstWhere(
          (p) => p.esBase,
          orElse:
              () =>
                  presentations.isNotEmpty
                      ? presentations.first
                      : ProductPresentation(
                        id: 0,
                        idProducto: widget.product.id,
                        idPresentacion: 0,
                        cantidad: 1.0,
                        esBase: true,
                        presentacion: Presentation(
                          id: 0,
                          denominacion: 'Unidad',
                          descripcion: 'Presentación por defecto',
                          skuCodigo: 'DEFAULT',
                        ),
                      ),
        );
      });

      print('📦 Presentaciones cargadas: ${presentations.length}');
      print(
        '📦 Presentación seleccionada: ${_selectedPresentation?.presentacion.denominacion}',
      );
    } catch (e) {
      print('❌ Error cargando presentaciones: $e');
      // Crear presentación por defecto
      setState(() {
        _selectedPresentation = ProductPresentation(
          id: 0,
          idProducto: widget.product.id,
          idPresentacion: 0,
          cantidad: 1.0,
          esBase: true,
          presentacion: Presentation(
            id: 0,
            denominacion: 'Unidad',
            descripcion: 'Presentación por defecto',
            skuCodigo: 'DEFAULT',
          ),
        );
      });
    } finally {
      setState(() {
        _isLoadingPresentations = false;
      });
    }
  }

  /// Cargar datos de promociones
  Future<void> _loadPromotionData() async {
    try {
      // Obtener ID de tienda
      final userData = await _userPreferencesService.getUserData();
      final idTienda = userData['idTienda'] as int?;

      if (idTienda == null) {
        print('❌ No se pudo obtener ID de tienda');
        return;
      }

      // Cargar promoción global
      final globalPromotion = await _promotionService.getGlobalPromotion(
        idTienda,
      );

      // Cargar promociones específicas del producto usando el nuevo método
      final productPromotions = await _promotionService.getProductPromotions(
        widget.product.id,
      );

      if (mounted) {
        setState(() {
          _globalPromotionData = globalPromotion;
          _productPromotionData =
              productPromotions.isNotEmpty ? productPromotions : null;
        });
      }

      print('🎯 Promociones cargadas en FluidMode:');
      print(
        '  - Global: ${globalPromotion != null ? globalPromotion['codigo_promocion'] : 'No'}',
      );
      print(
        '  - Producto: ${_productPromotionData != null ? _productPromotionData!.length : 0} promociones',
      );
    } catch (e) {
      print('❌ Error cargando promociones: $e');
      if (mounted) {
        setState(() {
          _globalPromotionData = null;
          _productPromotionData = null;
        });
      }
    }
  }

  /// Calcula el precio con descuento, priorizando promoción de producto sobre global
  Map<String, double> _calculatePromotionPrices(double originalPrice) {
    // Priorizar promoción específica del producto sobre promoción global
    final activePromotion = PromotionRules.pickPromotionForDisplay(
      productPromotions: _productPromotionData,
      globalPromotion: _globalPromotionData,
      quantity: _getTotalEquivalentUnits(),
    );

    if (activePromotion == null) {
      return {'precio_venta': originalPrice, 'precio_oferta': originalPrice};
    }

    final basePrice = PromotionRules.resolveBasePrice(
      unitPrice: originalPrice,
      basePrice: originalPrice,
      promotion: activePromotion,
    );

    return PromotionRules.calculatePromotionPrices(
      basePrice: basePrice,
      promotion: activePromotion,
    );
  }

  /// Obtiene información de la promoción activa
  Map<String, dynamic>? _getActivePromotion() {
    return PromotionRules.pickPromotionForDisplay(
      productPromotions: _productPromotionData,
      globalPromotion: _globalPromotionData,
      quantity: _getTotalEquivalentUnits(),
    );
  }

  int _getTotalEquivalentUnits() {
    final conversionFactor = _selectedPresentation?.cantidad ?? 1.0;

    if (_currentProduct?.variantes.isNotEmpty ?? false) {
      int total = 0;
      for (final quantity in _variantQuantities.values) {
        total += (quantity * conversionFactor).round();
      }
      return total;
    }

    return (_selectedQuantity * conversionFactor).round();
  }

  /// Construye la sección de precio con promociones
  Widget _buildPriceSection(double originalPrice) {
    final prices = _calculatePromotionPrices(originalPrice);
    final activePromotion = _getActivePromotion();

    // Determinar si hay promoción activa
    final hasPromotion =
        prices['precio_oferta'] != originalPrice ||
        prices['precio_venta'] != originalPrice;

    if (hasPromotion && activePromotion != null) {
      final isRecargo = PromotionRules.isRecargoPromotionType(activePromotion);

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
                  color: isRecargo ? Colors.purple : Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '\$${prices['precio_venta']!.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: isRecargo ? 16 : 14,
                  color: isRecargo ? Colors.purple : Colors.grey[600],
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
                  color: isRecargo ? Colors.grey[600] : Colors.purple,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '\$${PriceUtils.formatDiscountPrice(prices['precio_oferta']!)}',
                style: TextStyle(
                  fontSize: isRecargo ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  color: isRecargo ? Colors.grey[600] : Colors.purple,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ],
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '\$${originalPrice.toStringAsFixed(2)}',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.green,
          ),
        ),
      );
    }
  }

  /// Construye la sección de precio para variantes
  Widget _buildVariantPriceSection(double originalPrice) {
    final prices = _calculatePromotionPrices(originalPrice);
    final activePromotion = _getActivePromotion();
    final hasPromotion =
        prices['precio_oferta'] != originalPrice ||
        prices['precio_venta'] != originalPrice;

    if (hasPromotion && activePromotion != null) {
      final isRecargo = PromotionRules.isRecargoPromotionType(activePromotion);

      // Para recargo porcentual, mostrar el precio de venta (mayor)
      // Para descuentos, mostrar el precio de oferta (menor)
      final displayPrice =
          isRecargo ? prices['precio_venta']! : prices['precio_oferta']!;

      return Text(
        '\$${PriceUtils.formatDiscountPrice(displayPrice)}',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.purple,
          height: 1.2,
        ),
        overflow: TextOverflow.ellipsis,
      );
    } else {
      return Text(
        '\$${originalPrice.toStringAsFixed(2)}',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.purple,
          height: 1.2,
        ),
        overflow: TextOverflow.ellipsis,
      );
    }
  }

  void _onVariantSelected(ProductVariant variant) {
    setState(() {
      _selectedVariant = variant;
      if (!_variantQuantities.containsKey(variant)) {
        _variantQuantities[variant] = 1;
      }
    });
  }

  void _updateVariantQuantity(ProductVariant variant, int quantity) {
    setState(() {
      if (quantity > 0) {
        _variantQuantities[variant] = quantity;
      } else {
        _variantQuantities.remove(variant);
        if (_selectedVariant == variant) {
          _selectedVariant = null;
        }
      }
    });
  }

  void _updateQuantity(int quantity) {
    setState(() {
      _selectedQuantity = quantity;
    });
  }

  void _onPresentationChanged(ProductPresentation? presentation) {
    setState(() {
      _selectedPresentation = presentation;
    });
  }

  List<OrderItem> _createOrderItems() {
    List<OrderItem> items = [];

    if (_currentProduct?.variantes.isNotEmpty ?? false) {
      // Producto con variantes
      for (final entry in _variantQuantities.entries) {
        if (entry.value > 0) {
          final variant = entry.key;
          final quantity = entry.value;
          final conversionFactor = _selectedPresentation?.cantidad ?? 1.0;
          final finalQuantity = quantity * conversionFactor;

          // Calcular precios con promociones
          final prices = _calculatePromotionPrices(variant.precio);
          final activePromotion = _getActivePromotion();

          items.add(
            OrderItem(
              id: 'item_${DateTime.now().millisecondsSinceEpoch}',
              producto: _currentProduct!,
              cantidad: finalQuantity.toInt(),
              precioUnitario:
                  prices['precio_oferta']!, // Usar precio con descuento
              precioBase: prices['precio_venta'], // Precio base para cálculos
              ubicacionAlmacen: variant.descripcion ?? 'Almacén',
              variante: variant,
              promotionData: activePromotion, // Incluir datos de promoción
            ),
          );
        }
      }
    } else {
      // Producto sin variantes
      if (_selectedQuantity > 0) {
        final conversionFactor = _selectedPresentation?.cantidad ?? 1.0;
        final finalQuantity = _selectedQuantity * conversionFactor;

        // Calcular precios con promociones
        final prices = _calculatePromotionPrices(_currentProduct!.precio);
        final activePromotion = _getActivePromotion();

        items.add(
          OrderItem(
            id: 'item_${DateTime.now().millisecondsSinceEpoch}',
            producto: _currentProduct!,
            cantidad: finalQuantity.toInt(),
            precioUnitario:
                prices['precio_oferta']!, // Usar precio con descuento
            precioBase: prices['precio_venta'], // Precio base para cálculos
            ubicacionAlmacen: 'Almacén Principal',
            promotionData: activePromotion, // Incluir datos de promoción
          ),
        );
      }
    }

    return items;
  }

  void _continueToPayment() {
    final orderItems = _createOrderItems();

    if (orderItems.isEmpty) {
      AppSnackBar.showPersistent(
        context,
        message: 'Debes seleccionar al menos un producto',
        backgroundColor: Colors.orange,
      );
      return;
    }

    widget.onCompleted(orderItems);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingDetails) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.purple),
            SizedBox(height: 16),
            Text('Cargando detalles del producto...'),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProductHeader(),
          const SizedBox(height: 24),
          _buildPresentationSelector(),
          const SizedBox(height: 24),
          _buildVariantSelector(),
          const SizedBox(height: 24),
          _buildQuantitySelector(),
          const SizedBox(height: 24),
          _buildSelectedItems(),
          const SizedBox(height: 32),
          _buildContinueButton(),
        ],
      ),
    );
  }

  Widget _buildProductHeader() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Imagen del producto
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey.shade200,
              ),
              child:
                  _currentProduct?.foto != null &&
                          _currentProduct!.foto!.isNotEmpty
                      ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          _currentProduct!.foto!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(
                              Icons.image_not_supported,
                              color: Colors.grey.shade400,
                            );
                          },
                        ),
                      )
                      : Icon(
                        Icons.inventory,
                        color: Colors.grey.shade400,
                        size: 40,
                      ),
            ),
            const SizedBox(width: 16),

            // Información del producto
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _currentProduct?.denominacion ?? 'Producto',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _currentProduct?.categoria ?? '',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  ),
                  if (_currentProduct?.descripcion != null &&
                      _currentProduct!.descripcion!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _currentProduct!.descripcion!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  _buildPriceSection(_currentProduct?.precio ?? 0.0),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresentationSelector() {
    if (_isLoadingPresentations) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Cargando presentaciones...'),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.inventory_2, color: Colors.purple.shade600),
                const SizedBox(width: 8),
                const Text(
                  'Presentación',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (_productPresentations.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('Unidad (1.0) - Presentación por defecto'),
                  ],
                ),
              )
            else
              DropdownButtonFormField<ProductPresentation>(
                value: _selectedPresentation,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                items:
                    _productPresentations.map((presentation) {
                      return DropdownMenuItem(
                        value: presentation,
                        child: Row(
                          children: [
                            if (presentation.esBase)
                              const Icon(
                                Icons.star,
                                color: Colors.orange,
                                size: 16,
                              ),
                            if (presentation.esBase) const SizedBox(width: 4),
                            Text(
                              '${presentation.presentacion.denominacion} (${presentation.cantidad})',
                            ),
                            if (presentation.esBase) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'BASE',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.orange,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                onChanged: _onPresentationChanged,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVariantSelector() {
    if (_currentProduct?.variantes.isEmpty ?? true) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.location_on, color: Colors.blue.shade600),
                const SizedBox(width: 8),
                const Text(
                  'Ubicaciones Disponibles',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),

            ..._locationGroups.entries.map((entry) {
              final locationKey = entry.key;
              final variants = entry.value;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    locationKey,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...variants.map((variant) => _buildVariantTile(variant)),
                  const SizedBox(height: 12),
                ],
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildVariantTile(ProductVariant variant) {
    final isSelected = _selectedVariant == variant;
    final quantity = _variantQuantities[variant] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(
          color: isSelected ? Colors.purple : Colors.grey.shade300,
          width: isSelected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
        color: isSelected ? Colors.purple.withOpacity(0.05) : null,
      ),
      child: ListTile(
        title: Text(variant.nombre),
        subtitle: Row(
          children: [
            Text('Precio: '),
            _buildVariantPriceSection(variant.precio),
            Text(' | Stock: ${variant.cantidad}'),
          ],
        ),
        trailing:
            isSelected
                ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed:
                          quantity > 0
                              ? () =>
                                  _updateVariantQuantity(variant, quantity - 1)
                              : null,
                      icon: const Icon(Icons.remove),
                    ),
                    Text(
                      quantity.toString(),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      onPressed:
                          quantity < variant.cantidad
                              ? () =>
                                  _updateVariantQuantity(variant, quantity + 1)
                              : null,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                )
                : null,
        onTap: () => _onVariantSelected(variant),
      ),
    );
  }

  Widget _buildQuantitySelector() {
    if (_currentProduct?.variantes.isNotEmpty ?? false) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.add_shopping_cart, color: Colors.green.shade600),
                const SizedBox(width: 8),
                const Text(
                  'Cantidad',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed:
                      _selectedQuantity > 1
                          ? () => _updateQuantity(_selectedQuantity - 1)
                          : null,
                  icon: const Icon(Icons.remove),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey.shade200,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  _selectedQuantity.toString(),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 16),
                IconButton(
                  onPressed: () => _updateQuantity(_selectedQuantity + 1),
                  icon: const Icon(Icons.add),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.purple.shade100,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedItems() {
    final orderItems = _createOrderItems();

    if (orderItems.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shopping_cart, color: Colors.green.shade600),
                const SizedBox(width: 8),
                const Text(
                  'Productos Seleccionados',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),

            ...orderItems.map(
              (item) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.producto.denominacion,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          if (item.variante != null)
                            Text(
                              item.variante!.nombre,
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                              ),
                            ),
                          if (item.inventoryData?['presentacion'] != null)
                            Text(
                              'Presentación: ${item.inventoryData!['presentacion']}',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Cantidad: ${item.cantidad.toStringAsFixed(0)}',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        Text(
                          'Total: \$${item.subtotal.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total General:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  '\$${orderItems.fold(0.0, (sum, item) => sum + item.subtotal).toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContinueButton() {
    final orderItems = _createOrderItems();
    final canContinue = orderItems.isNotEmpty;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: canContinue ? _continueToPayment : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.purple,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          disabledBackgroundColor: Colors.grey.shade300,
        ),
        child: Text(
          canContinue
              ? 'Continuar a Métodos de Pago (${orderItems.length} producto${orderItems.length != 1 ? 's' : ''})'
              : 'Selecciona productos para continuar',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
