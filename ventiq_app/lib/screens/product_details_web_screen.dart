import 'dart:async';
import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/order_service.dart';
import '../services/product_detail_service.dart';
import '../services/promotion_service.dart';
import '../services/user_preferences_service.dart';
import '../services/price_change_service.dart';
import '../services/currency_service.dart';
import '../utils/price_utils.dart';
import '../widgets/bottom_navigation.dart';
import '../widgets/elaborated_product_chip.dart';
import '../utils/connection_error_handler.dart';
import '../widgets/notification_widget.dart';

/// Tokens neutros de la vista web. Se centralizan aqui para que los tres
/// paneles compartan borde/fondo sin repetir literales; la paleta de acento
/// sigue viniendo de widget.categoryColor y del color por ubicacion.
const Color _kBorder = Color(0xFFE5E7EB);
const Color _kSurfaceAlt = Color(0xFFF9FAFB);
const Color _kTextPrimary = Color(0xFF1F2937);
const Color _kTextSecondary = Color(0xFF6B7280);

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

class ProductDetailsWebScreen extends StatefulWidget {
  final Product product;
  final Color categoryColor;

  const ProductDetailsWebScreen({
    Key? key,
    required this.product,
    required this.categoryColor,
  }) : super(key: key);

  @override
  State<ProductDetailsWebScreen> createState() =>
      _ProductDetailsWebScreenState();
}

class _ProductDetailsWebScreenState extends State<ProductDetailsWebScreen>
    with SingleTickerProviderStateMixin {
  ProductVariant? selectedVariant;
  double selectedQuantity = 1;
  Map<ProductVariant, double> variantQuantities = {};
  Map<String, List<ProductVariant>> locationGroups =
      {}; // Group variants by location
  final Map<String, bool> _locationExpanded = {};
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
  final Map<String, TextEditingController> _qtyControllers = {};
  Timer? _qtyDebounceTimer;

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
    _qtyDebounceTimer?.cancel();
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    _qtyControllers.clear();
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

  /// [compact] deja solo el icono: dentro de una fila de linea seleccionada el
  /// texto completo roba el ancho que necesita el nombre del producto.
  Widget _buildCustomPriceBadge({bool compact = false}) {
    final badge = Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.orange.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.edit, size: 12, color: Colors.orange[700]),
          if (!compact) ...[
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
        ],
      ),
    );

    if (!compact) return badge;
    return Tooltip(message: 'Precio personalizado', child: badge);
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

      // Cargar promociones específicas del producto usando el nuevo método
      final productPromotions = await _promotionService.getProductPromotions(
        currentProduct.id,
      );

      // Guardar promociones del producto en preferencias para acceso en checkout
      if (productPromotions.isNotEmpty) {
        await _userPreferencesService.saveProductPromotions(
          currentProduct.id,
          productPromotions,
        );
      }

      setState(() {
        _globalPromotionData = globalPromotion;
        _productPromotionData =
            productPromotions.isNotEmpty ? productPromotions : null;
      });

      print('🎯 Promociones cargadas:');
      print(
        '  - Global: ${globalPromotion != null ? globalPromotion['codigo_promocion'] : 'No'}',
      );
      print(
        '  - Producto: ${productPromotions.isNotEmpty ? '${productPromotions.length} promociones' : 'No'}',
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
  /// Para display purposes, usa la primera promoción de la lista (aplicación real en checkout)
  Map<String, double> _calculatePromotionPrices(double originalPrice) {
    // Priorizar promoción específica del producto sobre promoción global
    final activePromotion =
        (_productPromotionData != null && _productPromotionData!.isNotEmpty)
            ? _productPromotionData!.first
            : _globalPromotionData;

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
  /// Para display purposes, retorna primera promoción (aplicación real en checkout)
  Map<String, dynamic>? _getActivePromotion() {
    if (_productPromotionData != null && _productPromotionData!.isNotEmpty) {
      return _productPromotionData!.first;
    }
    return _globalPromotionData;
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
      final tipoDescuento = activePromotion['tipo_descuento'] as int?;
      final isRecargo = tipoDescuento == 3; // Recargo porcentual

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
                fontSize: isRecargo ? 21 : 14,
                color: isRecargo ? widget.categoryColor : Colors.grey[600],
                fontWeight: isRecargo ? FontWeight.w700 : FontWeight.w500,
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
                fontSize: isRecargo ? 15 : 21,
                fontWeight: FontWeight.w700,
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
            fontSize: 21,
            fontWeight: FontWeight.w700,
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
      final tipoDescuento = activePromotion['tipo_descuento'] as int?;
      final isRecargo = tipoDescuento == 3; // Recargo porcentual

      // Para recargo porcentual, mostrar el precio de venta (mayor)
      // Para descuentos, mostrar el precio de oferta (menor)
      final displayPrice =
          isRecargo ? prices['precio_venta']! : prices['precio_oferta']!;

      priceWidget = Text(
        '\$${PriceUtils.formatDiscountPrice(displayPrice)}',
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: widget.categoryColor,
          height: 1.2,
        ),
        overflow: TextOverflow.ellipsis,
      );
    } else {
      priceWidget = Text(
        '\$${basePrice.toStringAsFixed(2)}',
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
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

  double get maxQuantityForProduct {
    return currentProduct.cantidad.toDouble();
  }

  double maxQuantityForVariant(ProductVariant variant) {
    return variant.cantidad.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    // Tres escalones de ancho: en monitores grandes se aprovecha mas espacio
    // sin dejar que las filas se estiren tanto que cueste seguirlas con la vista.
    final contentMaxWidth =
        screenWidth >= 1600
            ? 1240.0
            : screenWidth >= 1280
            ? 1120.0
            : 1000.0;
    final horizontalPadding = screenWidth >= 1280 ? 32.0 : 20.0;
    final totalUnits = _getTotalEquivalentUnits();
    return Scaffold(
      // Fondo gris muy suave para que los paneles blancos se lean como tarjetas.
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A90E2),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
          tooltip: 'Volver',
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                currentProduct.denominacion,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
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
              ? _buildLoadingState()
              : _errorMessage != null
              ? (_showRetryWidget
                  ? ConnectionRetryWidget(
                    message: _errorMessage!,
                    onRetry: _loadProductDetails,
                  )
                  : _buildErrorState())
              // La barra de accion vive fuera del scroll: el total y el boton
              // quedan siempre visibles aunque la lista de ubicaciones sea larga.
              : Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                        vertical: 16,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: contentMaxWidth,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildProductHeaderCard(),
                              if (currentProduct.variantes.isNotEmpty) ...[
                                const SizedBox(height: 14),
                                _buildLocationsPanel(),
                              ],
                              const SizedBox(height: 14),
                              _buildSelectionPanel(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  _buildActionBar(
                    totalUnits,
                    contentMaxWidth,
                    horizontalPadding,
                  ),
                ],
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

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Color(0xFF4A90E2)),
          SizedBox(height: 16),
          Text(
            'Cargando detalles del producto...',
            style: TextStyle(fontSize: 15, color: Colors.grey),
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
          Icon(Icons.error_outline, size: 56, color: Colors.red[300]),
          const SizedBox(height: 16),
          Text(
            'Error al cargar detalles',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              _errorMessage!,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _loadProductDetails,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Reintentar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A90E2),
              foregroundColor: Colors.white,
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  /// Contenedor base de los tres bloques de la pantalla (cabecera, ubicaciones
  /// y seleccion) para que compartan borde, radio y sombra.
  Widget _buildPanel({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildSectionHeader(
    IconData icon,
    String title, {
    String? badge,
    Widget? trailing,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: widget.categoryColor),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: _kTextPrimary,
            letterSpacing: 0.1,
          ),
        ),
        if (badge != null) ...[const SizedBox(width: 8), _buildCountChip(badge)],
        const Spacer(),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildCountChip(String text, {Color? color}) {
    final chipColor = color ?? widget.categoryColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: chipColor.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: chipColor.withOpacity(0.22), width: 1),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: chipColor,
        ),
      ),
    );
  }

  Widget _buildMetaChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _kSurfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kBorder, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: _kTextSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF4B5563),
            ),
          ),
        ],
      ),
    );
  }

  /// Miniatura del producto. Respeta el modo ahorro de datos y los estados de
  /// carga/error de la imagen remota.
  Widget _buildProductImage(double size) {
    Widget placeholder() => Container(
      color: Colors.grey[100],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.inventory_2, color: Colors.grey, size: 28),
          const SizedBox(height: 4),
          Text(
            'Sin imagen',
            style: TextStyle(fontSize: 10, color: Colors.grey[600]),
          ),
        ],
      ),
    );

    Widget content;
    if (_isLimitDataUsageEnabled) {
      content = Image.asset(
        'assets/no_image.png',
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => placeholder(),
      );
    } else if (currentProduct.foto != null) {
      content = Image.network(
        _compressImageUrl(currentProduct.foto!),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => placeholder(),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            color: Colors.grey[100],
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
      );
    } else {
      content = Container(
        color: Colors.grey[100],
        child: const Icon(Icons.inventory_2, color: Colors.grey, size: 32),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: content,
      ),
    );
  }

  /// Cabecera: miniatura, nombre, metadatos en chips, descripcion y precio.
  /// El precio se separa a la derecha en su propio bloque: en web hay ancho de
  /// sobra y asi queda alineado con el total de la barra inferior.
  Widget _buildProductHeaderCard() {
    final showStock =
        !currentProduct.esElaborado && !currentProduct.esServicio;
    final locationCount = locationGroups.length;
    final description = currentProduct.descripcion?.trim();

    return _buildPanel(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProductImage(112),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        currentProduct.denominacion,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: _kTextPrimary,
                          height: 1.25,
                          letterSpacing: -0.2,
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
                if (description != null && description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: _kTextSecondary,
                      height: 1.45,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildMetaChip(
                      Icons.sell_outlined,
                      currentProduct.categoria,
                    ),
                    if (showStock)
                      _buildMetaChip(
                        Icons.inventory_2_outlined,
                        'Stock total ${PriceUtils.formatQuantity(currentProduct.cantidad.toDouble())}',
                      ),
                    if (locationCount > 0)
                      _buildMetaChip(
                        Icons.place_outlined,
                        locationCount == 1
                            ? '1 ubicación'
                            : '$locationCount ubicaciones',
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          // Bloque de precio a la derecha, separado por un divisor sutil.
          Container(
            constraints: const BoxConstraints(minWidth: 200, maxWidth: 280),
            padding: const EdgeInsets.only(left: 20),
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: _kBorder, width: 1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Precio unitario',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[500],
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 6),
                _buildPriceSection(
                  currentProduct,
                  variant: _getGlobalPriceVariant(currentProduct),
                  showEditButton: currentProduct.variantes.isEmpty,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationsPanel() {
    final entries = locationGroups.entries.toList();

    return _buildPanel(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionHeader(
            Icons.place_outlined,
            'Ubicaciones',
            badge: '${entries.length}',
            trailing: entries.length > 1 ? _buildExpandAllButton() : null,
          ),
          const SizedBox(height: 12),
          ...entries.map(
            (entry) => _buildLocationGroup(entry.key, entry.value),
          ),
        ],
      ),
    );
  }

  /// Atajo para abrir o cerrar todas las ubicaciones de golpe: con varios
  /// almacenes, hacerlo una por una es el mayor punto de friccion en web.
  Widget _buildExpandAllButton() {
    final anyCollapsed = locationGroups.keys.any(
      (key) => !(_locationExpanded[key] ?? true),
    );
    return TextButton.icon(
      onPressed: () {
        setState(() {
          for (final key in locationGroups.keys) {
            _locationExpanded[key] = anyCollapsed;
          }
        });
      },
      icon: Icon(
        anyCollapsed ? Icons.unfold_more : Icons.unfold_less,
        size: 16,
      ),
      label: Text(anyCollapsed ? 'Expandir todo' : 'Colapsar todo'),
      style: TextButton.styleFrom(
        foregroundColor: widget.categoryColor,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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
    final locationColorLight = locationColor.withOpacity(0.08);
    final locationColorSemi = locationColor.withOpacity(0.16);
    final isExpanded = _locationExpanded[locationName] ?? true;
    final selectedInLocation =
        variants.where((v) => (variantQuantities[v] ?? 0) > 0).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        // El borde se tinta cuando el grupo esta abierto o tiene seleccion,
        // asi se distingue sin necesidad de una segunda sombra anidada.
        border: Border.all(
          color:
              isExpanded || selectedInLocation > 0
                  ? locationColor.withOpacity(0.35)
                  : _kBorder,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header de la ubicación con color único
          Material(
            color: Colors.transparent,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(9),
              topRight: Radius.circular(9),
            ),
            child: InkWell(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(9),
                topRight: Radius.circular(9),
              ),
              onTap: () {
                setState(() {
                  _locationExpanded[locationName] = !isExpanded;
                });
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: locationColorLight,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(9),
                    topRight: Radius.circular(9),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: locationColor.withOpacity(0.25),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        Icons.location_on,
                        color: locationColor,
                        size: 15,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        locationName,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: locationColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      variants.length == 1
                          ? '1 variante'
                          : '${variants.length} variantes',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: locationColor.withOpacity(0.75),
                      ),
                    ),
                    if (selectedInLocation > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: locationColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$selectedInLocation sel.',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                    // Solo mostrar stock si NO es un producto elaborado ni servicio
                    if (!currentProduct.esElaborado &&
                        !currentProduct.esServicio) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: locationColorSemi,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Stock total $totalStock',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: locationColor,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: isExpanded ? 0 : 0.5,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.expand_more,
                        color: locationColor,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Lista de variantes en esta ubicación
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            child: ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: isExpanded ? 1 : 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: _kSurfaceAlt,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(9),
                      bottomRight: Radius.circular(9),
                    ),
                  ),
                  padding: const EdgeInsets.all(10),
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
              ),
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
    double currentQuantity = variantQuantities[variant] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: isSelected ? locationColor.withOpacity(0.08) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          hoverColor: locationColor.withOpacity(0.05),
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color:
                    isSelected
                        ? locationColor.withOpacity(0.45)
                        : _kBorder,
                width: isSelected ? 1.2 : 1,
              ),
            ),
            child: Row(
              children: [
                // Imagen pequeña de la variante con color de ubicación
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    color: locationColor.withOpacity(0.08),
                    border: Border.all(
                      color: locationColor.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    Icons.inventory_2,
                    color: isSelected ? locationColor : Colors.grey[600],
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                // Nombre de la variante
                Expanded(
                  child: Text(
                    variant.nombre,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? locationColor : _kTextPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                // Precio de la variante (con boton de edicion si aplica)
                _buildVariantPriceSection(currentProduct, variant),
                // Solo mostrar stock si NO es un producto elaborado ni servicio
                if (!currentProduct.esElaborado &&
                    !currentProduct.esServicio) ...[
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: locationColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Stock ${variant.cantidad}',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: locationColor,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 12),
                // Cantidad elegida: evita bajar al panel solo para consultarla.
                if (isSelected && currentQuantity > 1)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      '×${PriceUtils.formatQuantity(currentQuantity)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: locationColor,
                      ),
                    ),
                  ),
                // Indicador de selección con color de ubicación
                SizedBox(
                  width: 22,
                  height: 22,
                  child:
                      isSelected
                          ? Container(
                            decoration: BoxDecoration(
                              color: locationColor,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 13,
                            ),
                          )
                          : Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.grey[300]!,
                                width: 1.4,
                              ),
                            ),
                          ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Panel de seleccion: presentacion (una sola vez, es del producto) y una
  /// fila compacta por linea seleccionada.
  Widget _buildSelectionPanel() {
    final hasVariants = currentProduct.variantes.isNotEmpty;
    final selectedEntries =
        hasVariants
            ? variantQuantities.entries
                .where((entry) => entry.value > 0)
                .toList()
            : const <MapEntry<ProductVariant, double>>[];
    final selectedCount =
        hasVariants
            ? selectedEntries.length
            : (selectedQuantity > 0 ? 1 : 0);

    return _buildPanel(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionHeader(
            Icons.shopping_basket_outlined,
            'Productos seleccionados',
            badge: selectedCount > 0 ? '$selectedCount' : null,
            trailing: _buildPresentationSelector(currentProduct),
          ),
          const SizedBox(height: 12),
          // Sin variantes la fila se muestra siempre: si desapareciera al bajar
          // a 0 el usuario se quedaria sin control para volver a subir.
          if (!hasVariants)
            _buildSelectedProductItem(
              currentProduct.denominacion,
              selectedQuantity,
              _getEffectiveBasePrice(currentProduct),
              _getLocationName(currentProduct, null),
              isVariant: false,
              originalPrice: _getOriginalBasePrice(currentProduct),
            )
          else if (selectedEntries.isEmpty)
            _buildEmptySelection()
          else
            ...selectedEntries.map(
              (entry) => _buildSelectedProductItem(
                '${currentProduct.denominacion} - ${entry.key.nombre}',
                entry.value,
                _getEffectiveBasePrice(currentProduct, entry.key),
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
    );
  }

  Widget _buildEmptySelection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      decoration: BoxDecoration(
        color: _kSurfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder, width: 1),
      ),
      child: Column(
        children: [
          Icon(
            Icons.add_shopping_cart_outlined,
            size: 26,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 8),
          Text(
            'Toca una variante en las ubicaciones para agregarla a la orden',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: _kTextSecondary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  // Método para construir items de productos seleccionados
  Widget _buildSelectedProductItem(
    String name,
    double quantity,
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
        activePromotion != null && activePromotion['tipo_descuento'] == 3;

    // Siempre usar precio_oferta para mostrar en productos seleccionados
    final finalPrice = prices['precio_oferta']!;
    final hasPromotion =
        prices['precio_oferta'] != price || prices['precio_venta'] != price;
    final lineTotal = _calculateTotalPriceWithPresentation(
      finalPrice,
      quantity,
      currentProduct,
    );
    final isActive = quantity > 0;

    // Una sola fila por linea: nombre + ubicacion, precio unitario, cantidad y
    // total. Antes cada linea era una tarjeta de tres filas.
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isActive ? Colors.white : _kSurfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive ? locationColor.withOpacity(0.30) : _kBorder,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Franja con el color de la ubicacion: identifica la linea de un vistazo.
          Container(
            width: 4,
            height: 36,
            decoration: BoxDecoration(
              color: locationColor.withOpacity(isActive ? 0.9 : 0.25),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: _kTextPrimary,
                    height: 1.25,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.location_on, size: 12, color: locationColor),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        ubicacion,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: locationColor,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (hasCustom) ...[
                      const SizedBox(width: 8),
                      _buildCustomPriceBadge(compact: true),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 148,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasPromotion) ...[
                  Text(
                    isRecargo
                        ? 'Venta \$${prices['precio_venta']!.toStringAsFixed(2)}'
                        : 'Base \$${price.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w400,
                      decoration:
                          isRecargo ? null : TextDecoration.lineThrough,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Oferta \$${PriceUtils.formatDiscountPrice(finalPrice)}',
                    style: TextStyle(
                      fontSize: 13.5,
                      color: locationColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ] else ...[
                  Text(
                    'Precio unitario',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '\$${price.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 13.5,
                      color: locationColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (hasCustom)
                  Text(
                    'Original \$${originalPriceValue!.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Colors.grey[600],
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _buildQuantityStepper(name: name, quantity: quantity),
          const SizedBox(width: 14),
          SizedBox(
            width: 104,
            child: Text(
              '\$${lineTotal.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: isActive ? locationColor : Colors.grey[400],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Control de cantidad de una linea. Mantiene el debounce de 3 s del campo
  /// manual y las validaciones de stock de _applyManualQty.
  Widget _buildQuantityStepper({
    required String name,
    required double quantity,
  }) {
    const leftRadius = BorderRadius.only(
      topLeft: Radius.circular(7),
      bottomLeft: Radius.circular(7),
    );
    const rightRadius = BorderRadius.only(
      topRight: Radius.circular(7),
      bottomRight: Radius.circular(7),
    );
    final qtyKey = 'detail_$name';
    final controller = _getQtyController(qtyKey, quantity);

    return Container(
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
            borderRadius: leftRadius,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color:
                    quantity > 0
                        ? widget.categoryColor.withOpacity(0.1)
                        : Colors.grey[100],
                borderRadius: leftRadius,
              ),
              child: Icon(
                Icons.remove,
                size: 16,
                color:
                    quantity > 0 ? widget.categoryColor : Colors.grey[400],
              ),
            ),
          ),
          Container(
            width: 58,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.symmetric(
                vertical: BorderSide(color: Colors.grey[300]!, width: 1),
              ),
            ),
            child: Center(
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                textAlignVertical: TextAlignVertical.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _kTextPrimary,
                  height: 1.0,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                  isCollapsed: true,
                ),
                onChanged: (value) {
                  _qtyDebounceTimer?.cancel();
                  _qtyDebounceTimer = Timer(
                    const Duration(seconds: 3),
                    () => _applyManualQty(name, qtyKey, controller.text),
                  );
                },
                onSubmitted: (value) {
                  _qtyDebounceTimer?.cancel();
                  _applyManualQty(name, qtyKey, value);
                },
                onTapOutside: (_) {
                  _qtyDebounceTimer?.cancel();
                  _applyManualQty(name, qtyKey, controller.text);
                  FocusScope.of(context).unfocus();
                },
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
                          variantQuantities[variant]! < variant.cantidad) {
                        variantQuantities[variant] =
                            variantQuantities[variant]! + 1;
                      }
                      break;
                    }
                  }
                }
              });
            },
            borderRadius: rightRadius,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: widget.categoryColor.withOpacity(0.1),
                borderRadius: rightRadius,
              ),
              child: Icon(Icons.add, size: 16, color: widget.categoryColor),
            ),
          ),
        ],
      ),
    );
  }

  /// Barra fija inferior con el total y la accion principal.
  Widget _buildActionBar(
    double totalUnits,
    double contentMaxWidth,
    double horizontalPadding,
  ) {
    final canAdd = totalPrice > 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: _kBorder, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 12,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentMaxWidth),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Total de la selección',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '\$${totalPrice.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: widget.categoryColor,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              _buildMetaChip(
                Icons.inventory_2_outlined,
                '${PriceUtils.formatQuantity(totalUnits)} unidad${totalUnits == 1 ? '' : 'es'}',
              ),
              const Spacer(),
              if (!canAdd)
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Text(
                    currentProduct.variantes.isEmpty
                        ? 'Indica una cantidad mayor que 0'
                        : 'Selecciona al menos una variante',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ),
              SizedBox(
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: canAdd ? _addToCart : null,
                  icon: const Icon(Icons.add_shopping_cart, size: 18),
                  label: const Text('Agregar a la orden'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.categoryColor,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[300],
                    disabledForegroundColor: Colors.grey[500],
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
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
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Presentación',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _kTextSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            constraints: const BoxConstraints(minHeight: 32),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _kSurfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kBorder, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.inventory_2, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Text(
                  'Unidad (1.0)',
                  style: TextStyle(
                    fontSize: 12.5,
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
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Presentación',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: _kTextSecondary,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: _kSurfaceAlt,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _kBorder, width: 1),
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
    double quantity,
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
  double _getTotalItems() {
    double total = 0;
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
  double _getTotalEquivalentUnits() {
    double total = 0;
    if (currentProduct.variantes.isEmpty) {
      // Producto sin variantes
      final conversionFactor = _getPresentationConversionFactor(currentProduct);
      total = selectedQuantity * conversionFactor;
    } else {
      // Producto con variantes
      for (var entry in variantQuantities.entries) {
        final quantity = entry.value;

        // Buscar el producto correspondiente a esta variante para obtener su factor de conversión
        final conversionFactor = _getPresentationConversionFactor(
          currentProduct,
        );
        total += quantity * conversionFactor;
      }
    }

    debugPrint('📊 Total unidades equivalentes calculado: $total');
    return total;
  }

  TextEditingController _getQtyController(String key, double currentQty) {
    if (!_qtyControllers.containsKey(key)) {
      _qtyControllers[key] = TextEditingController(text: '$currentQty');
    } else if (_qtyControllers[key]!.text != '$currentQty') {
      final ctrl = _qtyControllers[key]!;
      ctrl.text = '$currentQty';
      ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
    }
    return _qtyControllers[key]!;
  }

  void _showStockWarning(double maxQty, {String? variantName}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEF6C00).withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.inventory_2_outlined,
                color: Color(0xFF5D4037),
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    variantName != null
                        ? 'Stock limitado - $variantName'
                        : 'Stock limitado',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Color(0xFF4E342E),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Cantidad ajustada al máximo disponible: $maxQty',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF6D4C41),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFFFF3E0),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFFFCC80), width: 1),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        duration: const Duration(seconds: 5),
        elevation: 4,
      ),
    );
  }

  void _applyManualQty(String productName, String key, String value) {
    final newQty = int.tryParse(value);
    if (newQty != null && newQty >= 0) {
      // Validar stock si no es elaborado ni servicio
      if (!currentProduct.esElaborado && !currentProduct.esServicio) {
        if (currentProduct.variantes.isEmpty) {
          // Producto sin variantes: validar contra stock del producto
          if (newQty > maxQuantityForProduct) {
            setState(() {
              selectedQuantity = maxQuantityForProduct;
            });
            if (_qtyControllers.containsKey(key)) {
              _qtyControllers[key]!.text = '$maxQuantityForProduct';
            }
            _showStockWarning(maxQuantityForProduct);
            return;
          }
        } else {
          // Producto con variantes: validar contra stock de la variante
          for (var variant in currentProduct.variantes) {
            if (productName.contains(variant.nombre)) {
              final maxQty = maxQuantityForVariant(variant);
              if (newQty > maxQty) {
                setState(() {
                  variantQuantities[variant] = maxQty;
                });
                if (_qtyControllers.containsKey(key)) {
                  _qtyControllers[key]!.text = '$maxQty';
                }
                _showStockWarning(maxQty, variantName: variant.nombre);
                return;
              }
              break;
            }
          }
        }
      }
      _updateQuantityFromDialog(productName, value);
    } else {
      // Revert to current quantity if invalid
      if (currentProduct.variantes.isEmpty) {
        if (_qtyControllers.containsKey(key)) {
          _qtyControllers[key]!.text = '$selectedQuantity';
        }
      } else {
        for (var variant in currentProduct.variantes) {
          if (productName.contains(variant.nombre)) {
            if (_qtyControllers.containsKey(key)) {
              _qtyControllers[key]!.text = '${variantQuantities[variant] ?? 0}';
            }
            break;
          }
        }
      }
    }
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
    final double? newQuantity = double.tryParse(quantityText);
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

    _locationExpanded.removeWhere(
      (key, _) => !locationGroups.containsKey(key),
    );
    for (final locationKey in locationGroups.keys) {
      _locationExpanded.putIfAbsent(locationKey, () => false);
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

    double totalItemsAdded = 0;
    List<String> addedItems = [];

    try {
      final conversionFactor = _getPresentationConversionFactor(currentProduct);

      if (currentProduct.variantes.isEmpty) {
        // Producto sin variantes
        if (selectedQuantity > 0) {
          final basePrice = _getEffectiveBasePrice(currentProduct);
          final discountPrice = _calculateDiscountPrice(basePrice);
          final finalPrice = discountPrice ?? basePrice;
          final cantidadEnUnidadesBase = selectedQuantity * conversionFactor;

          orderService.addItemToCurrentOrder(
            producto: currentProduct,
            cantidad: cantidadEnUnidadesBase,
            ubicacionAlmacen: _getLocationName(currentProduct, null),
            inventoryData: _buildInventoryData(currentProduct, null),
            precioUnitario: finalPrice,
            precioBase: basePrice,
            promotionData: _getActivePromotion(),
          );
          totalItemsAdded += cantidadEnUnidadesBase;
          addedItems.add('${currentProduct.denominacion} (x${PriceUtils.formatQuantity(cantidadEnUnidadesBase)})');

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
            final cantidadEnUnidadesBase = entry.value * conversionFactor;

            orderService.addItemToCurrentOrder(
              producto: currentProduct,
              variante: entry.key,
              cantidad: cantidadEnUnidadesBase,
              ubicacionAlmacen: _getLocationName(currentProduct, entry.key),
              inventoryData: _buildInventoryData(currentProduct, entry.key),
              precioUnitario: finalPrice,
              precioBase: basePrice,
              promotionData: _getActivePromotion(),
            );
            totalItemsAdded += cantidadEnUnidadesBase;
            addedItems.add('${entry.key.nombre} (x${PriceUtils.formatQuantity(cantidadEnUnidadesBase)})');
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
