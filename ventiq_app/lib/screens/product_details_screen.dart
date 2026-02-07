import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/order_service.dart';
import '../services/product_detail_service.dart';
import '../services/promotion_service.dart';
import '../services/user_preferences_service.dart';
import '../services/price_change_service.dart';
import '../services/currency_service.dart';
import '../utils/price_utils.dart';
import '../utils/promotion_rules.dart';
import '../widgets/bottom_navigation.dart';
import '../widgets/elaborated_product_chip.dart';
import '../utils/connection_error_handler.dart';
import '../widgets/notification_widget.dart';

enum _PriceAdjustmentType {
  increasePercent,
  decreasePercent,
  increaseFixed,
  decreaseFixed,
  setDirect,
}

class _PriceCustomizationResult {
  final double? price;
  final bool clear;

  const _PriceCustomizationResult({this.price, this.clear = false});
}

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

class _ProductDetailsScreenState extends State<ProductDetailsScreen>
    with SingleTickerProviderStateMixin {
  ProductVariant? selectedVariant;
  int selectedQuantity = 1;
  Map<ProductVariant, int> variantQuantities = {};
  Map<String, List<ProductVariant>> locationGroups =
      {}; // Group variants by location
  final ProductDetailService _productDetailService = ProductDetailService();
  final UserPreferencesService _userPreferencesService =
      UserPreferencesService();
  final PromotionService _promotionService = PromotionService();
  final PriceChangeService _priceChangeService = PriceChangeService();
  Product? _detailedProduct;
  bool _isLoadingDetails = false;
  String? _errorMessage;
  Map<String, dynamic>? _globalPromotionData;
  List<Map<String, dynamic>>?
  _productPromotionData; // Changed to List for multiple promotions
  bool _isLimitDataUsageEnabled = false; // Para el modo de ahorro de datos
  bool _isConnectionError = false; // Para detectar errores de conexión
  bool _showRetryWidget = false; // Para mostrar el widget de reconexión

  // USD rate data
  double _usdRate = 0.0;
  bool _isLoadingUsdRate = false;

  // Presentaciones data
  List<ProductPresentation> _productPresentations = [];
  ProductPresentation? _selectedPresentation;
  bool _isLoadingPresentations = false;
  Map<String, ProductPresentation?> _selectedPresentationsByProduct = {};
  bool _canCustomizeSalePrice = false;
  double? _customProductPrice;
  int? _lastCustomizedVariantId;
  final Map<int, double> _customVariantPrices = {};
  late final AnimationController _editIconController;
  late final Animation<double> _editIconOpacity;
  @override
  void initState() {
    super.initState();
    _editIconController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _editIconOpacity = Tween<double>(begin: 0.4, end: 1).animate(
      CurvedAnimation(parent: _editIconController, curve: Curves.easeInOut),
    );
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
    _loadDataUsageSettings();
    _loadSalePricePermission();
  }

  @override
  void dispose() {
    _editIconController.dispose();
    super.dispose();
  }

  Future<void> _loadDataUsageSettings() async {
    final isEnabled = await _userPreferencesService.isLimitDataUsageEnabled();
    if (mounted) {
      setState(() {
        _isLimitDataUsageEnabled = isEnabled;
      });
    }
  }

  String _getPriceChangeType(_PriceAdjustmentType type) {
    switch (type) {
      case _PriceAdjustmentType.increasePercent:
        return 'aumentar_porcentaje';
      case _PriceAdjustmentType.decreasePercent:
        return 'disminuir_porcentaje';
      case _PriceAdjustmentType.increaseFixed:
        return 'aumentar_monto';
      case _PriceAdjustmentType.decreaseFixed:
        return 'disminuir_monto';
      case _PriceAdjustmentType.setDirect:
        return 'precio_directo';
    }
  }

  int? _getVariantIdForLog(ProductVariant? variant) {
    if (variant == null) return null;
    final metadataId = variant.inventoryMetadata?['id_variante'];
    if (metadataId is num) return metadataId.toInt();
    return variant.id;
  }

  Future<void> _loadSalePricePermission() async {
    final canCustomize = await _userPreferencesService.canCustomizeSalePrice();
    if (!mounted) return;
    setState(() {
      _canCustomizeSalePrice = canCustomize;
    });
    if (canCustomize) {
      _editIconController.repeat(reverse: true);
    } else {
      _editIconController.stop();
      _editIconController.value = 1;
    }
  }

  double _getOriginalBasePrice(Product product, [ProductVariant? variant]) {
    return variant?.precio ?? product.precio;
  }

  double _getEffectiveBasePrice(Product product, [ProductVariant? variant]) {
    if (variant != null) {
      return _customVariantPrices[variant.id] ?? variant.precio;
    }
    if (product.variantes.isNotEmpty) {
      return product.precio;
    }
    return _customProductPrice ?? product.precio;
  }

  bool _hasCustomPrice(Product product, [ProductVariant? variant]) {
    if (variant != null) {
      return _customVariantPrices.containsKey(variant.id);
    }
    if (product.variantes.isNotEmpty) {
      return false;
    }
    return _customProductPrice != null;
  }

  ProductVariant? _getGlobalPriceVariant(Product product) {
    if (product.variantes.isEmpty) return null;

    if (_lastCustomizedVariantId != null) {
      for (final variant in product.variantes) {
        if (variant.id == _lastCustomizedVariantId) {
          return variant;
        }
      }
    }

    for (final entry in variantQuantities.entries) {
      if (entry.value > 0) return entry.key;
    }

    return product.variantes.first;
  }

  Future<void> _applyCustomPrice(
    Product product,
    ProductVariant? variant,
    double price,
    _PriceAdjustmentType adjustmentType,
  ) async {
    final originalPrice = _getEffectiveBasePrice(product, variant);
    final variantId = _getVariantIdForLog(variant);
    if (!mounted) return;
    setState(() {
      if (variant != null) {
        _customVariantPrices[variant.id] = price;
        _lastCustomizedVariantId = variant.id;
      } else {
        _customProductPrice = price;
      }
    });
    await _priceChangeService.logPriceChange(
      productId: product.id,
      variantId: variantId,
      originalPrice: originalPrice,
      resultPrice: price,
      tipo: _getPriceChangeType(adjustmentType),
    );
  }

  Future<void> _clearCustomPrice(
    Product product,
    ProductVariant? variant,
  ) async {
    final originalPrice = _getEffectiveBasePrice(product, variant);
    final resultPrice = _getOriginalBasePrice(product, variant);
    final variantId = _getVariantIdForLog(variant);
    if (!mounted) return;
    setState(() {
      if (variant != null) {
        _customVariantPrices.remove(variant.id);
        _lastCustomizedVariantId = variant.id;
      } else {
        _customProductPrice = null;
      }
    });
    await _priceChangeService.logPriceChange(
      productId: product.id,
      variantId: variantId,
      originalPrice: originalPrice,
      resultPrice: resultPrice,
      tipo: 'restablecer',
    );
  }

  double _calculateAdjustedPrice(
    double basePrice,
    _PriceAdjustmentType type,
    double value,
  ) {
    switch (type) {
      case _PriceAdjustmentType.increasePercent:
        return basePrice * (1 + value / 100);
      case _PriceAdjustmentType.decreasePercent:
        return basePrice * (1 - value / 100);
      case _PriceAdjustmentType.increaseFixed:
        return basePrice + value;
      case _PriceAdjustmentType.decreaseFixed:
        return basePrice - value;
      case _PriceAdjustmentType.setDirect:
        return value;
    }
  }

  String _getAdjustmentLabel(_PriceAdjustmentType type) {
    switch (type) {
      case _PriceAdjustmentType.increasePercent:
        return 'Aumentar %';
      case _PriceAdjustmentType.decreasePercent:
        return 'Disminuir %';
      case _PriceAdjustmentType.increaseFixed:
        return 'Aumentar monto';
      case _PriceAdjustmentType.decreaseFixed:
        return 'Disminuir monto';
      case _PriceAdjustmentType.setDirect:
        return 'Precio directo';
    }
  }

  bool _isPercentageAdjustment(_PriceAdjustmentType type) {
    return type == _PriceAdjustmentType.increasePercent ||
        type == _PriceAdjustmentType.decreasePercent;
  }

  String _getAdjustmentHint(_PriceAdjustmentType type) {
    if (type == _PriceAdjustmentType.setDirect) {
      return 'Precio final';
    }
    return _isPercentageAdjustment(type) ? 'Porcentaje' : 'Monto';
  }

  Future<void> _showPriceCustomizationDialog(
    Product product, {
    ProductVariant? variant,
  }) async {
    if (!_canCustomizeSalePrice) return;
    if (variant == null && product.variantes.isNotEmpty) return;

    final currentPrice = _getEffectiveBasePrice(product, variant);
    final originalPrice = _getOriginalBasePrice(product, variant);
    final hasCustom = _hasCustomPrice(product, variant);
    var adjustmentType = _PriceAdjustmentType.setDirect;
    final valueController = TextEditingController();

    final result = await showDialog<_PriceCustomizationResult>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final inputValue = valueController.text.replaceAll(',', '.');
            final parsedValue = double.tryParse(inputValue);
            final previewPrice =
                parsedValue == null
                    ? null
                    : _calculateAdjustedPrice(
                      currentPrice,
                      adjustmentType,
                      parsedValue,
                    );
            final previewPriceClamped =
                previewPrice == null
                    ? null
                    : previewPrice.clamp(0, double.maxFinite).toDouble();
            final previewDelta =
                previewPriceClamped != null
                    ? previewPriceClamped - currentPrice
                    : null;

            return AlertDialog(
              scrollable: true,
              title: const Text('Personalizar precio de venta (beta)'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    variant != null ? variant.nombre : product.denominacion,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Precio actual: \$${currentPrice.toStringAsFixed(2)}',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                  if (hasCustom && originalPrice != currentPrice)
                    Text(
                      'Precio original: \$${originalPrice.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 12,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<_PriceAdjustmentType>(
                    value: adjustmentType,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de ajuste',
                      border: OutlineInputBorder(),
                    ),
                    items:
                        _PriceAdjustmentType.values
                            .map(
                              (type) => DropdownMenuItem(
                                value: type,
                                child: Text(_getAdjustmentLabel(type)),
                              ),
                            )
                            .toList(),
                    onChanged: (value) {
                      if (value == null || !context.mounted) return;
                      setDialogState(() {
                        adjustmentType = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: valueController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: _getAdjustmentHint(adjustmentType),
                      border: const OutlineInputBorder(),
                      suffixText:
                          _isPercentageAdjustment(adjustmentType) ? '%' : null,
                    ),
                    onChanged: (_) {
                      if (!context.mounted) return;
                      setDialogState(() {});
                    },
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Vista previa',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          previewPriceClamped != null
                              ? '\$${previewPriceClamped.toStringAsFixed(2)}'
                              : 'Ingresa un valor para previsualizar',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color:
                                previewPrice != null
                                    ? widget.categoryColor
                                    : Colors.grey[500],
                          ),
                        ),
                        if (previewDelta != null)
                          Text(
                            previewDelta >= 0
                                ? '+\$${previewDelta.toStringAsFixed(2)}'
                                : '-\$${previewDelta.abs().toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color:
                                  previewDelta >= 0
                                      ? Colors.green[700]
                                      : Colors.red[700],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                if (hasCustom)
                  TextButton(
                    onPressed:
                        () => Navigator.of(
                          context,
                        ).pop(const _PriceCustomizationResult(clear: true)),
                    child: const Text('Restablecer'),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed:
                      previewPriceClamped == null
                          ? null
                          : () {
                            Navigator.of(context).pop(
                              _PriceCustomizationResult(
                                price: previewPriceClamped,
                              ),
                            );
                          },
                  child: const Text('Aplicar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted || result == null) return;
    if (result.clear) {
      await _clearCustomPrice(product, variant);
      return;
    }
    if (result.price != null) {
      await _applyCustomPrice(product, variant, result.price!, adjustmentType);
    }
  }

  Widget _buildEditPriceButton({
    required Product product,
    ProductVariant? variant,
    double size = 18,
  }) {
    return FadeTransition(
      opacity: _editIconOpacity,
      child: InkWell(
        onTap: () => _showPriceCustomizationDialog(product, variant: variant),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: widget.categoryColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(Icons.edit, size: size, color: widget.categoryColor),
        ),
      ),
    );
  }

  Widget _buildCustomPriceBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.orange.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.edit, size: 12, color: Colors.orange[700]),
          const SizedBox(width: 4),
          Text(
            'Precio personalizado',
            style: TextStyle(
              fontSize: 10,
              color: Colors.orange[700],
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Cargar detalles completos del producto desde Supabase o cache offline
  Future<void> _loadProductDetails() async {
    setState(() {
      _isLoadingDetails = true;
      _errorMessage = null;
    });

    try {
      // Verificar si el modo offline está activado
      final isOfflineModeEnabled =
          await _userPreferencesService.isOfflineModeEnabled();

      Product detailedProduct;

      if (isOfflineModeEnabled) {
        print(
          '🔌 Modo offline - Cargando detalles del producto desde cache...',
        );

        // Cargar datos offline
        final offlineData = await _userPreferencesService.getOfflineData();

        if (offlineData != null && offlineData['products'] != null) {
          final productsData = offlineData['products'] as Map<String, dynamic>;

          // Buscar el producto en todas las categorías
          Product? foundProduct;
          for (var categoryProducts in productsData.values) {
            final productsList = categoryProducts as List<dynamic>;
            final productData = productsList.firstWhere(
              (p) => p['id'] == widget.product.id,
              orElse: () => null,
            );

            if (productData != null &&
                productData['detalles_completos'] != null) {
              // Construir Product desde detalles completos
              final detalles = productData['detalles_completos'];
              final productoInfo = detalles['producto'];
              final inventarioList =
                  detalles['inventario'] as List<dynamic>? ?? [];

              // Crear variantes desde el inventario (igual que en modo normal)
              final variantes = <ProductVariant>[];

              for (int i = 0; i < inventarioList.length; i++) {
                final item = inventarioList[i];

                // Validar que el item no sea null
                if (item == null) continue;

                final varianteData = item['variante'] as Map<String, dynamic>?;
                final presentacionData =
                    item['presentacion'] as Map<String, dynamic>?;
                final ubicacionData =
                    item['ubicacion'] as Map<String, dynamic>?;
                final cantidadDisponible =
                    (item['cantidad_disponible'] as num?)?.toInt() ?? 0;

                // Construir nombre de variante (igual que en ProductDetailService)
                String variantName = 'Variante ${i + 1}';
                String variantDescription = '';

                if (varianteData != null) {
                  final opcion =
                      varianteData['opcion'] as Map<String, dynamic>?;
                  final atributo =
                      varianteData['atributo'] as Map<String, dynamic>?;

                  if (opcion != null && atributo != null) {
                    final valor = opcion['valor'] as String? ?? '';
                    final label = atributo['label'] as String? ?? '';
                    variantName = '$label: $valor';
                    variantDescription = 'Variante de $label con valor $valor';
                  }
                }

                // Agregar presentación al nombre (igual que en modo normal)
                if (presentacionData != null) {
                  final presentacionNombre =
                      presentacionData['denominacion'] as String? ?? '';
                  final cantidad =
                      (presentacionData['cantidad'] as num?)?.toInt() ?? 1;
                  if (presentacionNombre.isNotEmpty) {
                    variantName += ' - $presentacionNombre';
                    if (cantidad > 1) {
                      variantDescription +=
                          ' (Presentación: $cantidad unidades)';
                    }
                  }
                }

                // Extraer precio
                double precio =
                    (productoInfo['precio_actual'] as num?)?.toDouble() ?? 0.0;
                if (item['precio'] != null) {
                  precio = (item['precio'] as num).toDouble();
                } else if (varianteData != null &&
                    varianteData['precio'] != null) {
                  precio = (varianteData['precio'] as num).toDouble();
                } else if (presentacionData != null &&
                    presentacionData['precio'] != null) {
                  precio = (presentacionData['precio'] as num).toDouble();
                }

                // Extraer metadata de inventario (igual que en modo normal)
                final almacenData =
                    ubicacionData?['almacen'] as Map<String, dynamic>?;
                final inventoryMetadata = {
                  'id_inventario': item['id_inventario'],
                  'id_variante': varianteData?['id'],
                  'id_opcion_variante': varianteData?['opcion']?['id'],
                  'id_presentacion': presentacionData?['id'],
                  'id_ubicacion': ubicacionData?['id'],
                  'sku_producto': item['sku_producto'],
                  'sku_ubicacion': ubicacionData?['sku_codigo'],
                  'cantidad_disponible': cantidadDisponible,
                  'ubicacion_nombre': ubicacionData?['denominacion'],
                  'almacen_nombre': almacenData?['denominacion'],
                };

                variantes.add(
                  ProductVariant(
                    id: i + 1, // ID secuencial
                    nombre: variantName,
                    precio: precio,
                    cantidad: cantidadDisponible,
                    descripcion:
                        variantDescription.isNotEmpty
                            ? variantDescription
                            : null,
                    inventoryMetadata: inventoryMetadata,
                  ),
                );
              }

              foundProduct = Product(
                id: productoInfo['id'] as int,
                denominacion: productoInfo['denominacion'] as String,
                descripcion: productoInfo['descripcion'] as String?,
                foto: productoInfo['foto'] as String?,
                precio: (productoInfo['precio_actual'] as num).toDouble(),
                cantidad: inventarioList.fold(
                  0,
                  (sum, inv) => sum + (inv['cantidad_disponible'] as num),
                ),
                categoria: productoInfo['categoria']['denominacion'] as String,
                esRefrigerado: productoInfo['es_refrigerado'] as bool? ?? false,
                esFragil: productoInfo['es_fragil'] as bool? ?? false,
                esPeligroso: productoInfo['es_peligroso'] as bool? ?? false,
                esVendible: true,
                esComprable: true,
                esInventariable: true,
                esPorLotes: false,
                esElaborado: productoInfo['es_elaborado'] as bool? ?? false,
                esServicio: productoInfo['es_servicio'] as bool? ?? false,
                variantes: variantes,
              );

              print('✅ Detalles del producto cargados desde cache offline');
              print('  - Producto: ${foundProduct.denominacion}');
              print('  - Variantes: ${foundProduct.variantes.length}');
              break;
            }
          }

          if (foundProduct == null) {
            throw Exception(
              'No se encontraron detalles del producto en cache offline',
            );
          }

          detailedProduct = foundProduct;
        } else {
          throw Exception(
            'No hay datos de productos sincronizados en modo offline',
          );
        }
      } else {
        print('🌐 Modo online - Cargando detalles desde Supabase...');
        detailedProduct = await _productDetailService.getProductDetail(
          widget.product.id,
        );
        print('✅ Detalles del producto cargados desde Supabase');
      }

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
    } catch (e, stackTrace) {
      print('❌ Error cargando detalles del producto: $e $stackTrace');

      final isConnectionError = ConnectionErrorHandler.isConnectionError(e);

      setState(() {
        _isConnectionError = isConnectionError;
        _errorMessage =
            isConnectionError
                ? ConnectionErrorHandler.getConnectionErrorMessage()
                : ConnectionErrorHandler.getGenericErrorMessage(e);
        _isLoadingDetails = false;
        _showRetryWidget = isConnectionError;
      });

      debugPrint('🔍 Es error de conexión: $isConnectionError');
    }
  }

  void _loadPromotionData() async {
    try {
      final isOfflineModeEnabled =
          await _userPreferencesService.isOfflineModeEnabled();

      Map<String, dynamic>? globalPromotion;
      List<Map<String, dynamic>>? productPromotions;

      if (isOfflineModeEnabled) {
        print('🔌 Modo offline - Cargando promociones desde cache...');
        globalPromotion = await _userPreferencesService.getPromotionData();
        productPromotions = await _userPreferencesService.getProductPromotions(
          currentProduct.id,
        );
      } else {
        // Obtener ID de tienda
        final idTienda = await _userPreferencesService.getIdTienda();
        if (idTienda == null) {
          print('❌ No se pudo obtener ID de tienda para promociones');
          return;
        }

        // Cargar promoción global
        globalPromotion = await _promotionService.getGlobalPromotion(idTienda);

        // Cargar promociones específicas del producto usando el nuevo método
        productPromotions = await _promotionService.getProductPromotions(
          currentProduct.id,
        );

        // Guardar promociones del producto en preferencias para acceso en checkout
        if (productPromotions.isNotEmpty) {
          await _userPreferencesService.saveProductPromotions(
            currentProduct.id,
            productPromotions,
          );
        }
      }

      setState(() {
        _globalPromotionData = globalPromotion;
        _productPromotionData =
            productPromotions?.isNotEmpty == true ? productPromotions : null;
      });

      print('🎯 Promociones cargadas:');
      print(
        '  - Global: ${globalPromotion != null ? globalPromotion['codigo_promocion'] : 'No'}',
      );
      print(
        '  - Producto: ${productPromotions?.isNotEmpty == true ? '${productPromotions!.length} promociones' : 'No'}',
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

  /// Cargar presentaciones del producto desde Supabase o cache offline
  Future<void> _loadProductPresentations() async {
    setState(() {
      _isLoadingPresentations = true;
    });

    try {
      debugPrint(
        '🔍 Cargando presentaciones para producto ID: ${widget.product.id}',
      );

      // Verificar si el modo offline está activado
      final isOfflineModeEnabled =
          await _userPreferencesService.isOfflineModeEnabled();

      List<ProductPresentation> presentations = [];

      if (isOfflineModeEnabled) {
        print('🔌 Modo offline - Cargando presentaciones desde cache...');

        // Cargar datos offline
        final offlineData = await _userPreferencesService.getOfflineData();

        if (offlineData != null && offlineData['products'] != null) {
          final productsData = offlineData['products'] as Map<String, dynamic>;

          // Buscar el producto en todas las categorías
          bool found = false;
          for (var categoryProducts in productsData.values) {
            if (found) break;

            final productsList = categoryProducts as List<dynamic>;
            final productData = productsList.firstWhere(
              (p) => p['id'] == widget.product.id,
              orElse: () => null,
            );

            if (productData != null && productData['presentaciones'] != null) {
              final presentationsData =
                  productData['presentaciones'] as List<dynamic>;

              // Convertir los datos a ProductPresentation
              presentations =
                  presentationsData
                      .map((item) => ProductPresentation.fromJson(item))
                      .toList();

              print(
                '✅ ${presentations.length} presentaciones cargadas desde cache offline',
              );
              found = true;
              break;
            }
          }

          if (!found) {
            print('⚠️ No se encontraron presentaciones en cache offline');
          }
        } else {
          print('⚠️ No hay datos de productos en cache offline');
        }
      } else {
        // Modo online - Cargar desde Supabase
        print('🌐 Modo online - Cargando presentaciones desde Supabase...');
        presentations = await _productDetailService.getProductPresentations(
          widget.product.id,
        );
      }

      debugPrint('📦 Presentaciones recibidas: ${presentations.length}');
      for (final pp in presentations) {
        print(
          '  - ProductPresentation(id=${pp.id}, idProducto=${pp.idProducto}, idPresentacion=${pp.idPresentacion}, cantidad=${pp.cantidad}, esBase=${pp.esBase}, denominacion=${pp.presentacion.denominacion}, sku=${pp.presentacion.skuCodigo})',
        );
      }

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
            debugPrint(
              '🎯 Presentación seleccionada (base): idPresentacion=${_selectedPresentation!.idPresentacion}, cantidad=${_selectedPresentation!.cantidad}',
            );
          } else {
            _selectedPresentation = presentations.first;
            _selectedPresentationsByProduct[productKey] = presentations.first;
            debugPrint(
              '✅ Primera presentación seleccionada: ${_selectedPresentation!.presentacion.denominacion}',
            );
            debugPrint(
              '🎯 Presentación seleccionada (primera): idPresentacion=${_selectedPresentation!.idPresentacion}, cantidad=${_selectedPresentation!.cantidad}',
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
    } catch (e, stackTrace) {
      print('❌ Error cargando presentaciones: $e');
      print('📍 Stack trace: $stackTrace');

      setState(() {
        _productPresentations = [];
        _isLoadingPresentations = false;
        _selectedPresentation = null;
      });
    }
  }

  /// Calcula el precio con descuento, priorizando promoción de producto sobre global
  /// Para display purposes, usa la primera promoción de la lista (aplicación real en checkout)
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
  /// Para display purposes, retorna primera promoción (aplicación real en checkout)
  Map<String, dynamic>? _getActivePromotion() {
    return PromotionRules.pickPromotionForDisplay(
      productPromotions: _productPromotionData,
      globalPromotion: _globalPromotionData,
      quantity: _getTotalEquivalentUnits(),
    );
  }

  Widget _buildPriceSection(
    Product product, {
    ProductVariant? variant,
    bool showEditButton = true,
  }) {
    final basePrice = _getEffectiveBasePrice(product, variant);
    final originalBasePrice = _getOriginalBasePrice(product, variant);
    final hasCustom = _hasCustomPrice(product, variant);
    final prices = _calculatePromotionPrices(basePrice);
    final activePromotion = _getActivePromotion();

    // Determinar si hay promoción activa
    final hasPromotion =
        prices['precio_oferta'] != basePrice ||
        prices['precio_venta'] != basePrice;

    final List<Widget> priceContent = [];

    if (hasPromotion && activePromotion != null) {
      final isRecargo = PromotionRules.isRecargoPromotionType(activePromotion);

      if (activePromotion['tipo_promocion_nombre'] != null)
        priceContent.add(
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
        );

      priceContent.add(
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
      );
      priceContent.add(const SizedBox(height: 4));
      priceContent.add(
        Row(
          children: [
            Text(
              'Precio oferta: ',
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
      );
    } else {
      priceContent.add(
        Text(
          '\$${basePrice.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: widget.categoryColor,
            height: 1.2,
          ),
        ),
      );
    }

    if (hasCustom && originalBasePrice != basePrice) {
      priceContent.add(const SizedBox(height: 4));
      priceContent.add(
        Text(
          'Original: \$${originalBasePrice.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
            decoration: TextDecoration.lineThrough,
          ),
        ),
      );
      priceContent.add(const SizedBox(height: 6));
      priceContent.add(_buildCustomPriceBadge());
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: priceContent,
          ),
        ),
        if (showEditButton &&
            _canCustomizeSalePrice &&
            (variant != null || product.variantes.isEmpty))
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 2),
            child: _buildEditPriceButton(product: product, variant: variant),
          ),
      ],
    );
  }

  Widget _buildVariantPriceSection(Product product, ProductVariant variant) {
    final basePrice = _getEffectiveBasePrice(product, variant);
    final prices = _calculatePromotionPrices(basePrice);
    final activePromotion = _getActivePromotion();
    final hasPromotion =
        prices['precio_oferta'] != basePrice ||
        prices['precio_venta'] != basePrice;

    Widget priceWidget;
    if (hasPromotion && activePromotion != null) {
      final isRecargo = PromotionRules.isRecargoPromotionType(activePromotion);

      // Para recargo porcentual, mostrar el precio de venta (mayor)
      // Para descuentos, mostrar el precio de oferta (menor)
      final displayPrice =
          isRecargo ? prices['precio_venta']! : prices['precio_oferta']!;

      priceWidget = Text(
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
      priceWidget = Text(
        '\$${basePrice.toStringAsFixed(2)}',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: widget.categoryColor,
          height: 1.2,
        ),
        overflow: TextOverflow.ellipsis,
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: priceWidget),
        if (_canCustomizeSalePrice) ...[
          const SizedBox(width: 4),
          _buildEditPriceButton(product: product, variant: variant, size: 14),
        ],
      ],
    );
  }

  /// Get the current product (detailed if loaded, otherwise fallback to original)
  Product get currentProduct => _detailedProduct ?? widget.product;

  double get totalPrice {
    double total = 0.0;

    if (currentProduct.variantes.isEmpty) {
      // Producto sin variantes - usar precio con presentación
      final basePrice = _getEffectiveBasePrice(currentProduct);
      final prices = _calculatePromotionPrices(basePrice);
      final finalPrice = prices['precio_oferta']!;
      total = _calculateTotalPriceWithPresentation(
        finalPrice,
        selectedQuantity,
        currentProduct,
      );
    } else {
      // Producto con variantes - usar precio con presentación
      for (var entry in variantQuantities.entries) {
        final variant = entry.key;
        final quantity = entry.value;
        final basePrice = _getEffectiveBasePrice(currentProduct, variant);
        final prices = _calculatePromotionPrices(basePrice);
        final finalPrice = prices['precio_oferta']!;
        total += _calculateTotalPriceWithPresentation(
          finalPrice,
          quantity,
          currentProduct,
        );
      }
    }

    debugPrint(
      '💰 Total price calculado con presentaciones: \$${total.toStringAsFixed(2)}',
    );
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
        ],
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
              ? _showRetryWidget
                  ? ConnectionRetryWidget(
                    message: _errorMessage!,
                    onRetry: _loadProductDetails,
                  )
                  : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.red[300],
                        ),
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
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
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
                                _isLimitDataUsageEnabled
                                    ? Image.asset(
                                      'assets/no_image.png',
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
                                    )
                                    : currentProduct.foto != null
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
                              _buildPriceSection(
                                currentProduct,
                                variant: _getGlobalPriceVariant(currentProduct),
                                showEditButton:
                                    currentProduct.variantes.isEmpty,
                              ),
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
                              _getEffectiveBasePrice(currentProduct),
                              _getLocationName(currentProduct, null),
                              isVariant: false,
                              originalPrice: _getOriginalBasePrice(
                                currentProduct,
                              ),
                            ),
                          if (currentProduct.variantes.isNotEmpty)
                            ...variantQuantities.entries
                                .where((entry) => entry.value > 0)
                                .map(
                                  (entry) => _buildSelectedProductItem(
                                    '${currentProduct.denominacion} - ${entry.key.nombre}',
                                    entry.value,
                                    _getEffectiveBasePrice(
                                      currentProduct,
                                      entry.key,
                                    ),
                                    _getLocationName(currentProduct, entry.key),
                                    isVariant: true,
                                    originalPrice: _getOriginalBasePrice(
                                      currentProduct,
                                      entry.key,
                                    ),
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
                                  'TOTAL: ${_getTotalEquivalentUnits()} unidad${_getTotalEquivalentUnits() == 1 ? '' : 'es'}',
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
                // Solo mostrar stock si NO es un producto elaborado ni servicio
                if (!currentProduct.esElaborado && !currentProduct.esServicio)
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
                    return _buildLocationVariantCard(
                      variant,
                      isSelected,
                      locationColor,
                    );
                  }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // Método para construir card de variante dentro de una ubicación
  Widget _buildLocationVariantCard(
    ProductVariant variant,
    bool isSelected,
    Color locationColor,
  ) {
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
                isSelected ? locationColor.withOpacity(0.1) : Colors.grey[50],
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
                  color:
                      isSelected
                          ? locationColor.withOpacity(0.1)
                          : Colors.grey[100],
                  border: Border.all(
                    color:
                        isSelected
                            ? locationColor.withOpacity(0.3)
                            : Colors.grey[300]!,
                    width: 1,
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
                        _buildVariantPriceSection(currentProduct, variant),
                        const SizedBox(width: 6),
                        Container(
                          width: 3,
                          height: 3,
                          decoration: BoxDecoration(
                            color:
                                isSelected
                                    ? locationColor.withOpacity(0.6)
                                    : Colors.grey[400],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Solo mostrar stock si NO es un producto elaborado ni servicio
                        if (!currentProduct.esElaborado &&
                            !currentProduct.esServicio)
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
    double? originalPrice,
  }) {
    final locationColor = _getLocationColor(ubicacion);
    final originalPriceValue = originalPrice;
    final hasCustom = originalPriceValue != null && originalPriceValue != price;
    final prices = _calculatePromotionPrices(price);
    final activePromotion = _getActivePromotion();
    final isRecargo =
        activePromotion != null &&
        PromotionRules.isRecargoPromotionType(activePromotion);

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
              Icon(Icons.location_on, size: 16, color: locationColor),
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
          if (hasCustom) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Original: \$${originalPriceValue!.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                const SizedBox(width: 6),
                _buildCustomPriceBadge(),
              ],
            ),
          ],
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
                            // Si es elaborado o servicio, no limitar cantidad; si no, usar límite de stock
                            if (currentProduct.esElaborado ||
                                currentProduct.esServicio ||
                                selectedQuantity < maxQuantityForProduct)
                              selectedQuantity++;
                          } else {
                            // Buscar la variante correspondiente
                            for (var variant in currentProduct.variantes) {
                              if (name.contains(variant.nombre)) {
                                // Si es elaborado o servicio, no limitar cantidad; si no, usar límite de stock
                                if (currentProduct.esElaborado ||
                                    currentProduct.esServicio ||
                                    variantQuantities[variant]! <
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

  // Método para obtener el total de items (productos/presentaciones seleccionadas)
  // Mantenido para compatibilidad futura - cuenta las presentaciones, no las unidades
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

  // Método para obtener el total de unidades equivalentes considerando presentaciones
  int _getTotalEquivalentUnits() {
    int total = 0;
    if (currentProduct.variantes.isEmpty) {
      // Producto sin variantes
      final conversionFactor = _getPresentationConversionFactor(currentProduct);
      total = (selectedQuantity * conversionFactor).round();
    } else {
      // Producto con variantes
      for (var entry in variantQuantities.entries) {
        final quantity = entry.value;

        // Buscar el producto correspondiente a esta variante para obtener su factor de conversión
        final conversionFactor = _getPresentationConversionFactor(
          currentProduct,
        );
        total += (quantity * conversionFactor).round();
      }
    }

    debugPrint('📊 Total unidades equivalentes calculado: $total');
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
        print(
          '🎯 Seleccionando automáticamente variante: ${firstVariant.nombre}',
        );

        // Seleccionar la primera variante automáticamente
        // Usar addPostFrameCallback para asegurar que el setState se ejecute correctamente
        WidgetsBinding.instance.addPostFrameCallback((_) {
          setState(() {
            selectedVariant = firstVariant;
            // Establecer cantidad inicial de 1 para la variante seleccionada
            variantQuantities[firstVariant] = 1;
            print(
              '🔄 setState ejecutado - selectedVariant: ${selectedVariant?.nombre}',
            );
            print(
              '🔄 variantQuantities actualizado: ${variantQuantities.entries.where((e) => e.value > 0).map((e) => '${e.key.nombre}: ${e.value}').toList()}',
            );
          });
        });

        print(
          '🎯 Variante seleccionada automáticamente: ${firstVariant.nombre} con cantidad 1',
        );
      }
    } else {
      print(
        '🏪 Múltiples ubicaciones disponibles (${locationGroups.length}), mostrando opciones al usuario',
      );
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

  void _addToCart() async {
    final orderService = OrderService();

    // Verificar configuración de tienda antes de agregar productos
    try {
      final storeConfig = await _userPreferencesService.getStoreConfig();
      if (storeConfig != null &&
          storeConfig['need_all_orders_completed_to_continue'] == true) {
        // Verificar si hay órdenes pendientes
        final hasPendingOrders = orderService.orders.any(
          (order) => order.status.index == 1,
        ); // estado: 1 = Pendiente

        if (hasPendingOrders) {
          _showPendingOrdersDialog();
          return;
        }
      }
    } catch (e) {
      print('❌ Error al verificar configuración de tienda: $e');
      // Continuar con el flujo normal si hay error en la configuración
    }

    int totalItemsAdded = 0;
    List<String> addedItems = [];

    try {
      if (currentProduct.variantes.isEmpty) {
        // Producto sin variantes
        if (selectedQuantity > 0) {
          final basePrice = _getEffectiveBasePrice(currentProduct);
          final discountPrice = _calculateDiscountPrice(basePrice);
          final finalPrice = discountPrice ?? basePrice;

          orderService.addItemToCurrentOrder(
            producto: currentProduct,
            cantidad: selectedQuantity,
            ubicacionAlmacen: _getLocationName(currentProduct, null),
            inventoryData: _buildInventoryData(currentProduct, null),
            precioUnitario: finalPrice,
            precioBase: basePrice,
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
            final basePrice = _getEffectiveBasePrice(currentProduct, entry.key);
            final discountPrice = _calculateDiscountPrice(basePrice);
            final finalPrice = discountPrice ?? basePrice;

            orderService.addItemToCurrentOrder(
              producto: currentProduct,
              variante: entry.key,
              cantidad: entry.value,
              ubicacionAlmacen: _getLocationName(currentProduct, entry.key),
              inventoryData: _buildInventoryData(currentProduct, entry.key),
              precioUnitario: finalPrice,
              precioBase: basePrice,
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

  void _showPendingOrdersDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange,
                  size: 28,
                ),
                const SizedBox(width: 12),
                const Text(
                  'Órdenes Pendientes',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            content: const Text(
              'Debes completar todas las órdenes pendientes antes de agregar una nueva orden.',
              style: TextStyle(fontSize: 16),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Entendido'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context); // Cerrar diálogo
                  Navigator.popUntil(
                    context,
                    (route) => route.isFirst,
                  ); // Ir a home
                  Navigator.pushNamed(context, '/orders'); // Ir a órdenes
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.categoryColor,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Ver Órdenes'),
              ),
            ],
          ),
    );
  }
}
