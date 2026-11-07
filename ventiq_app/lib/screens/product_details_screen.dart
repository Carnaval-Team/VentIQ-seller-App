import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/moneda_venta_service.dart';
import '../services/order_service.dart';
import '../services/product_detail_service.dart';
import '../services/promotion_service.dart';
import '../services/user_preferences_service.dart';
import '../services/price_change_service.dart';
import '../services/preview_rebalanceo_service.dart';
import '../utils/price_utils.dart';
import '../utils/presentacion_cadena_local.dart';
import '../utils/desarme_bulto_local.dart';
import '../utils/promotion_rules.dart';
import '../theme/ventiq_home_theme.dart';
import '../widgets/elaborated_product_chip.dart';
import '../utils/connection_error_handler.dart';
import '../widgets/notification_widget.dart';
import 'package_product_screen.dart';

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
  double selectedQuantity = 1;
  Map<ProductVariant, double> variantQuantities = {};
  double _fractionStep = 0.5;
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

  // Presentaciones data
  List<ProductPresentation> _productPresentations = [];
  bool _isLoadingPresentations = false;
  Map<String, ProductPresentation?> _selectedPresentationsByProduct = {};
  bool _canCustomizeSalePrice = false;
  double? _customProductPrice;
  int? _lastCustomizedVariantId;
  final Map<int, double> _customVariantPrices = {};
  AnimationController? _editIconController;
  Animation<double>? _editIconOpacity;

  // Estado para desarmar bultos - FASE 6
  // Map<int presentacionId, int cantidadDesarmada>
  final Map<int, int> _bultosDesarmados = {};
  // Stock simulado offline de cada presentación: {presentacionId: cantidad}
  final Map<int, double> _stockPresentacionesSimulado = {};

  @override
  void initState() {
    super.initState();

    // Si es paquete, redirigir a pantalla dedicada de paquetes
    if (widget.product.esPaquete) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder:
                (_) => PackageProductScreen(
                  product: widget.product,
                  categoryColor: widget.categoryColor,
                ),
          ),
        );
      });
      return;
    }

    // Si el producto no tiene stock, mostrar aviso y volver (excepto elaborados y servicios)
    // Venta por unidades: con saldo 0 pero bultos desarmables SÍ se puede vender.
    if (widget.product.cantidadReal <= 0 &&
        _sinStockNiDesarmable &&
        !widget.product.esElaborado &&
        !widget.product.esServicio) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder:
              (ctx) => AlertDialog(
                title: const Text('Sin stock'),
                content: const Text('Este producto no tiene stock disponible.'),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      Navigator.of(context).pop();
                    },
                    child: const Text('Volver'),
                  ),
                ],
              ),
        );
      });
      return;
    }

    _editIconController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _editIconOpacity = Tween<double>(begin: 0.4, end: 1).animate(
      CurvedAnimation(parent: _editIconController!, curve: Curves.easeInOut),
    );
    // Inicializar cantidades de variantes
    for (var variant in widget.product.variantes) {
      variantQuantities[variant] = 0.0;
    }
    // Group variants by location
    _groupVariantsByLocation(widget.product.variantes);
    // Cargar detalles completos del producto
    _loadProductDetails();
    _loadPromotionData();
    _loadProductPresentations();
    _loadFractionStep();
    _loadDataUsageSettings();
    _loadSalePricePermission();
  }

  @override
  void dispose() {
    _editIconController?.dispose();
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
      _editIconController?.repeat(reverse: true);
    } else {
      _editIconController?.stop();
      _editIconController?.value = 1;
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
                    'Precio actual: ${MonedaVentaService.formatearPrecio(currentPrice, conSimbolo: true)}',
                    style: TextStyle(color: VentiqHomeTheme.textSecondary),
                  ),
                  if (hasCustom && originalPrice != currentPrice)
                    Text(
                      'Precio original: ${MonedaVentaService.formatearPrecio(originalPrice, conSimbolo: true)}',
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
                      border: Border.all(color: VentiqHomeTheme.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Vista previa',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: VentiqHomeTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          previewPriceClamped != null
                              ? MonedaVentaService.formatearPrecio(
                                previewPriceClamped,
                                conSimbolo: true,
                              )
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
                                ? '+${MonedaVentaService.formatearPrecio(previewDelta, conSimbolo: true)}'
                                : '-${MonedaVentaService.formatearPrecio(previewDelta.abs(), conSimbolo: true)}',
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
      opacity: _editIconOpacity ?? const AlwaysStoppedAnimation(1.0),
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
      // Verificar si el modo offline / full-offline está activado
      final useLocalData = await _userPreferencesService.shouldUseLocalData();

      Product detailedProduct;

      if (useLocalData) {
        print(
          '🔌 Offline/full-offline - Cargando detalles del producto desde cache...',
        );

        // Cargar datos offline
        final offlineData = await _userPreferencesService.getOfflineData();

        if (offlineData != null && offlineData['products'] != null) {
          final productsData = offlineData['products'] as Map<String, dynamic>;

          // Buscar el producto en todas las categorías
          Product? foundProduct;
          for (var categoryProducts in productsData.values) {
            if (categoryProducts is! List) continue;
            Map<String, dynamic>? productData;
            for (final raw in categoryProducts) {
              if (raw is! Map) continue;
              final p = Map<String, dynamic>.from(raw);
              final pid = p['id'];
              final id = pid is int ? pid : (pid is num ? pid.toInt() : null);
              if (id == widget.product.id) {
                productData = p;
                break;
              }
            }
            if (productData == null) continue;

            if (productData['detalles_completos'] != null) {
              final detallesRaw = productData['detalles_completos'];
              if (detallesRaw is! Map) continue;
              final detalles = Map<String, dynamic>.from(detallesRaw);

              // Un solo parser para online y offline. Antes esta pantalla
              // reconstruia las variantes a mano (~140 lineas duplicadas).
              foundProduct = ProductDetailService.productoDesdeRespuestaDetalle(
                detalles,
                fallbackStock:
                    (productData['cantidad'] as num?)?.toDouble() ??
                    widget.product.cantidadReal.toDouble(),
              );
              print('Detalles del producto cargados desde cache offline');
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
          fallbackStock: widget.product.cantidadReal.toDouble(),
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

        // Presentaciones sin fila de inventario: puede que
        // _loadPresentations ya haya terminado (carrera) o que los
        // detalles hayan reemplazado el objeto producto. Es idempotente.
        _agregarVariantesPresentacionesSinStock();

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
      final useLocalData = await _userPreferencesService.shouldUseLocalData();

      Map<String, dynamic>? globalPromotion;
      List<Map<String, dynamic>>? productPromotions;

      if (useLocalData) {
        print('🔌 Offline/full-offline - Cargando promociones desde cache...');
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

  /// Cargar presentaciones del producto desde Supabase o cache offline
  Future<void> _loadProductPresentations() async {
    setState(() {
      _isLoadingPresentations = true;
    });

    try {
      debugPrint(
        '🔍 Cargando presentaciones para producto ID: ${widget.product.id}',
      );

      // Verificar si el modo offline / full-offline está activado
      final useLocalData = await _userPreferencesService.shouldUseLocalData();

      List<ProductPresentation> presentations = [];

      if (useLocalData) {
        print(
          '🔌 Offline/full-offline - Cargando presentaciones desde cache...',
        );

        // Cargar datos offline
        final offlineData = await _userPreferencesService.getOfflineData();

        if (offlineData != null && offlineData['products'] != null) {
          final productsData = offlineData['products'] as Map<String, dynamic>;

          // Buscar el producto en todas las categorías
          bool found = false;
          for (var categoryProducts in productsData.values) {
            if (found) break;
            if (categoryProducts is! List) continue;

            Map<String, dynamic>? productData;
            for (final raw in categoryProducts) {
              if (raw is! Map) continue;
              final p = Map<String, dynamic>.from(raw);
              final pid = p['id'];
              final id = pid is int ? pid : (pid is num ? pid.toInt() : null);
              if (id == widget.product.id) {
                productData = p;
                break;
              }
            }

            if (productData != null && productData['presentaciones'] != null) {
              final presentationsData = List<dynamic>.from(
                productData['presentaciones'] as List,
              );

              // Convertir los datos a ProductPresentation
              presentations =
                  presentationsData
                      .whereType<Map>()
                      .map(
                        (item) => ProductPresentation.fromJson(
                          Map<String, dynamic>.from(item),
                        ),
                      )
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
            _selectedPresentationsByProduct[productKey] =
                basePresentations.first;
            debugPrint(
              '✅ Presentación base seleccionada: '
              '${basePresentations.first.presentacion.denominacion}',
            );
          } else {
            _selectedPresentationsByProduct[productKey] = presentations.first;
            debugPrint(
              '✅ Primera presentación seleccionada: '
              '${presentations.first.presentacion.denominacion}',
            );
          }
        } else {
          debugPrint(
            '⚠️ No hay presentaciones configuradas, usando presentación por defecto',
          );
          _selectedPresentationsByProduct[productKey] = null;
        }
        _agregarVariantesPresentacionesSinStock();
      });
    } catch (e, stackTrace) {
      print('❌ Error cargando presentaciones: $e');
      print('📍 Stack trace: $stackTrace');

      setState(() {
        _productPresentations = [];
        _isLoadingPresentations = false;
      });
    }
  }

  Future<void> _loadFractionStep() async {
    final step = await UserPreferencesService().getFractionStep();
    if (mounted) {
      setState(() {
        _fractionStep = step;
      });
    }
  }

  bool _isCurrentPresentationFractional([ProductVariant? variant]) {
    if (variant != null) {
      final idPresVariante =
          (variant.inventoryMetadata?['id_presentacion'] as num?)?.toInt();
      if (idPresVariante != null) {
        final pres = _productPresentations
            .cast<ProductPresentation?>()
            .firstWhere((p) => p?.id == idPresVariante, orElse: () => null);
        if (pres != null) {
          return pres.presentacion.esFraccionable;
        }
      }
    }
    final productKey = '${currentProduct.id}';
    final selected = _selectedPresentationsByProduct[productKey];
    if (selected != null) {
      return selected.presentacion.esFraccionable;
    }
    return false;
  }

  Widget _buildFractionStepSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Incremento:',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: VentiqHomeTheme.textSecondary,
          ),
        ),
        Flexible(
          child: SegmentedButton<double>(
            segments: const [
              ButtonSegment(value: 0.1, label: Text('0.1')),
              ButtonSegment(value: 0.25, label: Text('0.25')),
              ButtonSegment(value: 0.5, label: Text('0.5')),
            ],
            selected: {_fractionStep},
            onSelectionChanged: (Set<double> newSelection) {
              setState(() {
                _fractionStep = newSelection.first;
              });
              UserPreferencesService().setFractionStep(newSelection.first);
            },
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStatePropertyAll(const TextStyle(fontSize: 12)),
            ),
          ),
        ),
      ],
    );
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
                color:
                    isRecargo
                        ? widget.categoryColor
                        : VentiqHomeTheme.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              MonedaVentaService.formatearPrecio(
                prices['precio_venta']!,
                conSimbolo: true,
              ),
              style: TextStyle(
                fontSize: isRecargo ? 16 : 14,
                color:
                    isRecargo
                        ? widget.categoryColor
                        : VentiqHomeTheme.textSecondary,
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
                color:
                    isRecargo
                        ? VentiqHomeTheme.textSecondary
                        : widget.categoryColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              MonedaVentaService.formatearPrecio(
                PriceUtils.roundDiscountPrice(prices['precio_oferta']!),
                conSimbolo: true,
              ),
              style: TextStyle(
                fontSize: isRecargo ? 14 : 16,
                fontWeight: FontWeight.w600,
                color:
                    isRecargo
                        ? VentiqHomeTheme.textSecondary
                        : widget.categoryColor,
                height: 1.2,
              ),
            ),
          ],
        ),
      );
    } else {
      priceContent.add(
        Text(
          MonedaVentaService.formatearPrecio(basePrice, conSimbolo: true),
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
          'Original: ${MonedaVentaService.formatearPrecio(originalBasePrice, conSimbolo: true)}',
          style: TextStyle(
            fontSize: 11,
            color: VentiqHomeTheme.textSecondary,
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
        MonedaVentaService.formatearPrecio(
          PriceUtils.roundDiscountPrice(displayPrice),
          conSimbolo: true,
        ),
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
        MonedaVentaService.formatearPrecio(basePrice, conSimbolo: true),
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
          variant, // FASE 4: factor POR VARIANTE, no global
        );
      }
    }

    debugPrint(
      '💰 Total price calculado con presentaciones: \$${total.toMoneyString(2)}',
    );
    return total;
  }

  double get maxQuantityForProduct {
    final base = currentProduct.cantidadReal.toDouble();

    // VENTA POR UNIDADES con saldo 0: si la presentación elegida tiene saldo
    // propio 0 pero hay bultos desarmables, el límite es el máximo servible
    // (equivalente convertible). Sin cadena o sin saldos locales se conserva
    // el límite previo: el servidor manda al vender.
    final idPres = _presentacionElegidaId(currentProduct);
    final stocks = _stocksPorPresentacionLocal();
    if (idPres == null || stocks == null || _cadenaPresentaciones().isEmpty) {
      return base;
    }
    final maxServible = math.max(
      0.0,
      (_disponibilidadPorPresentacion()[idPres]?.disponible ?? 0) -
          reservadoExtra,
    );
    return math.max(base, maxServible);
  }

  /// Cantidad extra ya seleccionada en esta pantalla (variantQuantities),
  /// expresada en unidades base. Las líneas del carrito se descuentan dentro
  /// de `_disponibilidadPorPresentacion`; esto cubre lo que el vendedor está
  /// marcando ahora mismo y aún no agregó a la orden.
  double get reservadoExtra {
    var total = 0.0;
    final cadena = _cadenaPresentaciones();
    for (final e in variantQuantities.entries) {
      final idPres =
          (e.key.inventoryMetadata?['id_presentacion'] as num?)?.toInt();
      var factor = 1.0;
      for (final p in cadena) {
        if (p.idPresentacion == idPres) {
          factor = p.factorRel;
          break;
        }
      }
      total += e.value * factor;
    }
    return total;
  }

  /// ¿No hay stock ni directo ni desarmando bultos?
  ///
  /// Compuerta de entrada de la pantalla. Con saldo 0 en la presentación base
  /// pero bultos desarmables, el producto SÍ es vendible por unidades, así que
  /// no se muestra "Sin stock". Sin `stockMixto` (cache legacy) conserva el
  /// criterio previo de `cantidadReal` para no bloquear nada nuevo.
  bool get _sinStockNiDesarmable {
    if (currentProduct.cantidadReal > 0) return false;
    final stocks = _stocksPorPresentacionLocal();
    if (stocks == null) return true;
    final cadena = _cadenaPresentaciones();
    if (cadena.isEmpty) return true;
    // Alguna presentación con saldo convertible > 0.
    for (final p in cadena) {
      if ((stocks[p.idPresentacion] ?? 0) > 0) return false;
    }
    return true;
  }

  double maxQuantityForVariant(ProductVariant variant) {
    final propio = variant.cantidadReal.toDouble();

    // Venta por unidades con saldo 0: el límite sube al máximo convertible
    // (sumando los bultos de presentaciones mayores). Sin stockMixto o sin
    // cadena se conserva el límite previo: el servidor manda al vender.
    final idPresVariante =
        (variant.inventoryMetadata?['id_presentacion'] as num?)?.toInt();
    final stocks = _stocksPorPresentacionLocal();
    final cadena = _cadenaPresentaciones();
    if (idPresVariante == null || stocks == null || cadena.isEmpty) {
      return propio;
    }
    final maxServible = math.max(
      0.0,
      (_disponibilidadPorPresentacion()[idPresVariante]?.disponible ?? 0) -
          reservadoExtra,
    );
    return math.max(propio, maxServible);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.product.cantidadReal <= 0 &&
        _sinStockNiDesarmable &&
        !widget.product.esElaborado &&
        !widget.product.esServicio) {
      return const Scaffold(
        backgroundColor: VentiqHomeTheme.surface,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      backgroundColor: VentiqHomeTheme.surface,
      body: Column(
        children: [
          Expanded(
            child:
                _isLoadingDetails
                    // Primer frame con el producto inyectado: hero + nombre +
                    // progreso, en vez de una pantalla en blanco con un spinner.
                    ? CustomScrollView(
                      slivers: <Widget>[
                        _buildHeroSliver(context),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                const LinearProgressIndicator(
                                  minHeight: 3,
                                  color: VentiqHomeTheme.primary,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Cargando stock, presentaciones y variantes…',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: VentiqHomeTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                    : _errorMessage != null
                    ? _showRetryWidget
                        ? Column(
                          children: <Widget>[
                            Expanded(
                              child: ConnectionRetryWidget(
                                message: _errorMessage!,
                                onRetry: _loadProductDetails,
                              ),
                            ),
                            SafeArea(
                              top: false,
                              child: TextButton.icon(
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.arrow_back, size: 18),
                                label: const Text('Volver'),
                              ),
                            ),
                          ],
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
                                  color: VentiqHomeTheme.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _errorMessage!,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: VentiqHomeTheme.textSecondary,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton(
                                onPressed: _loadProductDetails,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: VentiqHomeTheme.primary,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Reintentar'),
                              ),
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.arrow_back, size: 18),
                                label: const Text('Volver'),
                              ),
                            ],
                          ),
                        )
                    : LayoutBuilder(
                      builder: (
                        BuildContext context,
                        BoxConstraints constraints,
                      ) {
                        // Web / TPV grande: imagen sticky a la izquierda y
                        // ficha + controles en la columna derecha (§8).
                        final bool wide = constraints.maxWidth >= 900;
                        final Widget scroll = CustomScrollView(
                          slivers: <Widget>[
                            _buildHeroSliver(context, expandido: !wide),
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    // Sección superior: Imagen y información del producto
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Información del producto
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              // Denominación con chip de producto elaborado
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      currentProduct
                                                          .denominacion,
                                                      style: const TextStyle(
                                                        fontSize: 18,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: Color(
                                                          0xFF1F2937,
                                                        ),
                                                        height: 1.2,
                                                      ),
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  ElaboratedProductChip(
                                                    productId:
                                                        currentProduct.id,
                                                    productName:
                                                        currentProduct
                                                            .denominacion,
                                                    // Flags ya resueltos por el detalle:
                                                    // el chip no hace red al montarse.
                                                    esElaborado:
                                                        currentProduct
                                                            .esElaborado,
                                                    esServicio:
                                                        currentProduct
                                                            .esServicio,
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              // Categoría
                                              Text(
                                                currentProduct.categoria,
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color:
                                                      VentiqHomeTheme
                                                          .textSecondary,
                                                  height: 1.2,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 8),
                                              // Precio del producto con descuento
                                              _buildPriceSection(
                                                currentProduct,
                                                variant: _getGlobalPriceVariant(
                                                  currentProduct,
                                                ),
                                                showEditButton:
                                                    currentProduct
                                                        .variantes
                                                        .isEmpty,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 24),
                                    // Controles de venta ANTES de las ubicaciones: el
                                    // vendedor ve el stepper sin tener que elegir almacén
                                    // primero (§8 del plan).
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
                                            (
                                              entry,
                                            ) => _buildSelectedProductItem(
                                              '${currentProduct.denominacion} - ${entry.key.nombre}',
                                              entry.value,
                                              _getEffectiveBasePrice(
                                                currentProduct,
                                                entry.key,
                                              ),
                                              _getLocationName(
                                                currentProduct,
                                                entry.key,
                                              ),
                                              isVariant: true,
                                              variant:
                                                  entry
                                                      .key, // FASE 4: factor POR VARIANTE
                                              originalPrice:
                                                  _getOriginalBasePrice(
                                                    currentProduct,
                                                    entry.key,
                                                  ),
                                            ),
                                          ),
                                    const SizedBox(height: 8),
                                    // Ubicaciones plegadas: se abren solas solo cuando
                                    // hay más de una con stock (el caso en que hay que
                                    // elegir). Con una sola, el vendedor ya está listo.
                                    if (currentProduct.variantes.isNotEmpty)
                                      _buildUbicacionesPlegadas(),
                                    const SizedBox(height: 16),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );

                        if (!wide) return scroll;

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Expanded(flex: 5, child: _buildPanelImagenWide()),
                            Expanded(flex: 6, child: scroll),
                          ],
                        );
                      },
                    ),
          ),
          // Fila fija con total y botón de agregar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: VentiqHomeTheme.card,
              border: Border(
                top: BorderSide(color: VentiqHomeTheme.border, width: 1),
              ),
              boxShadow: VentiqHomeTheme.shadowCard,
            ),
            child: Row(
              children: [
                // Stepper siempre visible: con la variante auto-seleccionada se
                // ajusta la cantidad sin tener que buscar el control en el
                // cuerpo del detalle (§8 del plan).
                _buildStepperBarra(),
                const SizedBox(width: 8),
                // Total de productos seleccionados
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'TOTAL: ${PriceUtils.formatQuantity(_getTotalEquivalentUnits())} unidad${_getTotalEquivalentUnits() == 1 ? '' : 'es'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: VentiqHomeTheme.textSecondary,
                        ),
                      ),
                      Text(
                        MonedaVentaService.formatearPrecio(
                          totalPrice,
                          conSimbolo: true,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: widget.categoryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Botón de agregar
                SizedBox(
                  width: 110,
                  height: 50,
                  child: ElevatedButton(
                    onPressed:
                        _getTotalEquivalentUnits() > 0 ? _addToCart : null,
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
          ),
        ],
      ),
    );
  }

  /// Cabecera colapsable con el hero de imagen del producto (§8 del plan).
  ///
  /// Sustituye al `AppBar` plano: la foto ocupa el alto de la cabecera y se
  /// colapsa al hacer scroll. La miniatura de `ProductoTile` comparte el tag
  /// `prod-{id}` para que la transición desde el listado sea continua.
  ///
  /// [expandido] = `false` en la columna derecha de escritorio: la imagen ya se
  /// muestra en el panel izquierdo, así que allí solo queda una barra compacta
  /// con el nombre y las acciones.
  Widget _buildHeroSliver(BuildContext context, {bool expandido = true}) {
    if (!expandido) {
      return SliverAppBar(
        pinned: true,
        toolbarHeight: 56,
        backgroundColor: VentiqHomeTheme.card,
        foregroundColor: VentiqHomeTheme.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 2,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 26),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          currentProduct.denominacion,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: _heroAcciones(context),
      );
    }

    final double altoExpandido = (MediaQuery.sizeOf(context).height * 0.32)
        .clamp(220.0, 320.0);

    return SliverAppBar(
      pinned: true,
      expandedHeight: altoExpandido,
      backgroundColor: widget.categoryColor,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 2,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, size: 28),
        onPressed: () => Navigator.pop(context),
      ),
      actions: _heroAcciones(context),
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        titlePadding: const EdgeInsetsDirectional.only(
          start: 56,
          bottom: 14,
          end: 16,
        ),
        title: Text(
          currentProduct.denominacion,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            shadows: <Shadow>[Shadow(color: Color(0x99000000), blurRadius: 6)],
          ),
        ),
        background: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            _buildHeroImagen(currentProduct),
            // Velo: garantiza contraste del título sobre cualquier foto.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: <double>[0, 0.55, 1],
                  colors: <Color>[
                    Color(0x66000000),
                    Color(0x22000000),
                    Color(0xB3000000),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroImagen(Product producto) {
    final String? foto = producto.foto;
    final bool usarFoto =
        !_isLimitDataUsageEnabled && _hasValidProductImage(foto);
    if (!usarFoto) return _heroFallback(producto);

    return Hero(
      tag: 'prod-${producto.id}',
      child: Image.network(
        _compressImageUrl(foto!),
        fit: BoxFit.cover,
        loadingBuilder: (
          BuildContext context,
          Widget child,
          ImageChunkEvent? p,
        ) {
          return p == null ? child : _heroFallback(producto);
        },
        errorBuilder: (_, __, ___) => _heroFallback(producto),
      ),
    );
  }

  Widget _heroFallback(Product producto) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            widget.categoryColor,
            widget.categoryColor.withValues(alpha: 0.65),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          producto.esElaborado
              ? Icons.restaurant_menu_rounded
              : Icons.inventory_2_rounded,
          size: 84,
          color: Colors.white.withValues(alpha: 0.35),
        ),
      ),
    );
  }

  /// Acciones de la cabecera (modo ahorro de datos + campana). Compartidas por
  /// la cabecera expandida y la compacta de escritorio.
  List<Widget> _heroAcciones(BuildContext context) {
    return <Widget>[
      if (_isLimitDataUsageEnabled)
        IconButton(
          icon: const Icon(Icons.data_saver_on, color: Colors.orange, size: 24),
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
    ];
  }

  /// Panel de imagen fijo de la columna izquierda en pantallas ≥ 900 px.
  Widget _buildPanelImagenWide() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: _buildHeroImagen(currentProduct),
            ),
          ),
        ),
      ),
    );
  }

  /// Cantidad de la línea activa (la auto-seleccionada o el producto base).
  double _cantidadEnBarra() {
    if (selectedVariant != null) {
      return variantQuantities[selectedVariant!] ?? 0;
    }
    return selectedQuantity;
  }

  /// Sube/baja la cantidad desde la barra inferior fija.
  ///
  /// En variantes permite llegar a 0 (la línea desaparece del cuerpo); en un
  /// producto sin variantes se queda en mínimo 1.
  void _cambiarCantidadBarra(double delta) {
    setState(() {
      if (selectedVariant != null) {
        final double actual = variantQuantities[selectedVariant!] ?? 0;
        variantQuantities[selectedVariant!] = (actual + delta).clamp(
          0.0,
          double.infinity,
        );
      } else {
        selectedQuantity = (selectedQuantity + delta).clamp(
          1.0,
          double.infinity,
        );
      }
    });
  }

  Widget _buildStepperBarra() {
    final double cantidad = _cantidadEnBarra();
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: VentiqHomeTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: VentiqHomeTheme.border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            tooltip: 'Quitar uno',
            onPressed: cantidad > 0 ? () => _cambiarCantidadBarra(-1) : null,
            icon: const Icon(Icons.remove, size: 18),
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
            padding: EdgeInsets.zero,
          ),
          SizedBox(
            width: 24,
            child: Text(
              PriceUtils.formatQuantity(cantidad),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: VentiqHomeTheme.textPrimary,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Añadir uno',
            onPressed: () => _cambiarCantidadBarra(1),
            icon: const Icon(Icons.add, size: 18),
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  /// Ubicaciones **plegadas** (§8 del plan): el detalle ya deja una variante
  /// seleccionada, así que la lista de almacenes es una acción secundaria.
  ///
  /// Se abre sola solo cuando hay más de una ubicación con stock, que es el
  /// caso en el que el vendedor tiene que elegir. Con una sola, ocupa pantalla
  /// sin aportar nada.
  Widget _buildUbicacionesPlegadas() {
    final int conStock =
        locationGroups.values
            .where((List<ProductVariant> v) => _getLocationStock(v) > 0)
            .length;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(
          color: VentiqHomeTheme.card,
          borderRadius: BorderRadius.circular(VentiqHomeTheme.radiusBlock),
          border: Border.all(color: VentiqHomeTheme.border, width: 1),
        ),
        child: ExpansionTile(
          key: PageStorageKey<String>('ubicaciones-${widget.product.id}'),
          initiallyExpanded: conStock > 1,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          title: Row(
            children: <Widget>[
              const Icon(Icons.warehouse_outlined, size: 18),
              const SizedBox(width: 6),
              Text(
                'UBICACIONES',
                style: VentiqHomeTheme.rotuloBloque.copyWith(fontSize: 12),
              ),
              const SizedBox(width: 8),
              Text(
                '${locationGroups.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: VentiqHomeTheme.textSecondary,
                ),
              ),
            ],
          ),
          children: <Widget>[
            for (final MapEntry<String, List<ProductVariant>> entry
                in locationGroups.entries)
              _buildLocationGroup(entry.key, entry.value),
          ],
        ),
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
                if (!currentProduct.esElaborado &&
                    !currentProduct.esServicio) ...[
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
                      '${_getLocationStockReal(variants)}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: locationColor,
                      ),
                    ),
                  ),
                  if (_getLocationReservadoCarnaval(variants) > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange[300]!),
                      ),
                      child: Text(
                        'Carritos: ${_getLocationReservadoCarnaval(variants)}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange[800],
                        ),
                      ),
                    ),
                  ],
                  if (_getLocationEnOrdenesCarnaval(variants) > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue[300]!),
                      ),
                      child: Text(
                        'Órdenes: ${_getLocationEnOrdenesCarnaval(variants)}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue[800],
                        ),
                      ),
                    ),
                  ],
                ],
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
    double currentQuantity = variantQuantities[variant] ?? 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: () {
          setState(() {
            if (currentQuantity == 0) {
              variantQuantities[variant] = 1.0;
            } else {
              variantQuantities[variant] = 0.0;
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
              color: isSelected ? locationColor : VentiqHomeTheme.border,
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
                          : VentiqHomeTheme.surface,
                  border: Border.all(
                    color:
                        isSelected
                            ? locationColor.withOpacity(0.3)
                            : VentiqHomeTheme.border,
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
                                : VentiqHomeTheme.textPrimary,
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
                            !currentProduct.esServicio) ...[
                          Text(
                            () {
                              final idPres =
                                  (variant.inventoryMetadata?['id_presentacion']
                                          as num?)
                                      ?.toInt();
                              final d =
                                  idPres == null
                                      ? null
                                      : _disponibilidadPorPresentacion()[idPres];
                              if (d != null &&
                                  d.disponible > variant.cantidadReal) {
                                return 'Stock: ${variant.cantidadReal} · ${FormatoPresentacion.cantidad(d.disponible)} disp · desarma';
                              }
                              return 'Stock: ${variant.cantidadReal}';
                            }(),
                            style: TextStyle(
                              fontSize: 10,
                              color: VentiqHomeTheme.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (variant.reservadoCarnaval > 0) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange[50],
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.orange[300]!),
                              ),
                              child: Text(
                                'Res: ${variant.reservadoCarnaval}',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.orange[800],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
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
    double quantity,
    double price,
    String ubicacion, {
    bool isVariant = false,
    double? originalPrice,
    ProductVariant? variant,
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
        color: VentiqHomeTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: VentiqHomeTheme.border, width: 1),
        boxShadow: VentiqHomeTheme.shadowCard,
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
                    color: VentiqHomeTheme.textPrimary,
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
                  MonedaVentaService.formatearPrecio(
                    _calculateTotalPriceWithPresentation(
                      finalPrice,
                      quantity,
                      currentProduct,
                      variant, // FASE 4: factor POR VARIANTE
                    ),
                    conSimbolo: true,
                  ),
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
                            ? 'Venta: ${MonedaVentaService.formatearPrecio(prices['precio_venta']!, conSimbolo: true)}'
                            : 'Base: ${MonedaVentaService.formatearPrecio(price, conSimbolo: true)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: VentiqHomeTheme.textSecondary,
                          fontWeight: FontWeight.w400,
                          decoration:
                              isRecargo ? null : TextDecoration.lineThrough,
                        ),
                      ),
                      Text(
                        isRecargo
                            ? 'Oferta: ${MonedaVentaService.formatearPrecio(PriceUtils.roundDiscountPrice(prices['precio_oferta']!), conSimbolo: true)}'
                            : 'Oferta: ${MonedaVentaService.formatearPrecio(PriceUtils.roundDiscountPrice(finalPrice), conSimbolo: true)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: locationColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                  : Text(
                    'Precio: ${MonedaVentaService.formatearPrecio(price, conSimbolo: true)}',
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
                  'Original: ${MonedaVentaService.formatearPrecio(originalPriceValue!, conSimbolo: true)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: VentiqHomeTheme.textSecondary,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                const SizedBox(width: 6),
                _buildCustomPriceBadge(),
              ],
            ),
          ],
          const SizedBox(height: 12),
          // Sin combobox de presentación: en productos con variantes el
          // nombre de la tarjeta ya incluye la presentación y el selector
          // quedaba bloqueado (información duplicada de solo lectura).
          if (_isCurrentPresentationFractional(variant)) ...[
            const SizedBox(height: 8),
            _buildFractionStepSelector(),
          ],
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
                  color: VentiqHomeTheme.textPrimary,
                ),
              ),
              // Controles de cantidad mejorados
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: VentiqHomeTheme.border, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () {
                        final step =
                            _isCurrentPresentationFractional(variant)
                                ? _fractionStep
                                : 1.0;
                        setState(() {
                          if (currentProduct.variantes.isEmpty) {
                            if (selectedQuantity > 0)
                              selectedQuantity = (selectedQuantity - step)
                                  .clamp(0.0, double.infinity);
                          } else {
                            // Buscar la variante correspondiente POR IDENTIDAD
                            // (entry.key), no por nombre.contains(...). Un
                            // nombre es prefijo del otro ("Variante 1" contiene
                            // a "1") y el string matching agarrava la equivocada.
                            if (variant != null &&
                                variantQuantities[variant]! > 0) {
                              variantQuantities[variant] =
                                  (variantQuantities[variant]! - step).clamp(
                                    0.0,
                                    double.infinity,
                                  );
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
                      onTap:
                          () => _showQuantityDialog(
                            name,
                            quantity.toDouble(),
                            variant,
                          ),
                      child: Container(
                        width: 50,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          border: Border.symmetric(
                            vertical: BorderSide(
                              color: VentiqHomeTheme.border,
                              width: 1,
                            ),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            PriceUtils.formatQuantity(quantity.toDouble()),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: VentiqHomeTheme.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        final step =
                            _isCurrentPresentationFractional(variant)
                                ? _fractionStep
                                : 1.0;
                        setState(() {
                          if (currentProduct.variantes.isEmpty) {
                            // Si es elaborado o servicio, no limitar cantidad; si no, usar límite de stock
                            if (currentProduct.esElaborado ||
                                currentProduct.esServicio ||
                                selectedQuantity + step <=
                                    maxQuantityForProduct)
                              selectedQuantity += step;
                          } else {
                            // Ver la nota arriba del `-`: busqueda POR
                            // IDENTIDAD, no por nombre.contains.
                            if (variant != null) {
                              if (currentProduct.esElaborado ||
                                  currentProduct.esServicio ||
                                  variantQuantities[variant]! + step <=
                                      maxQuantityForVariant(variant)) {
                                variantQuantities[variant] =
                                    variantQuantities[variant]! + step;
                                _avisarDesarmePendiente(
                                  variantQuantities[variant]!,
                                  (variant.inventoryMetadata?['id_presentacion']
                                          as num?)
                                      ?.toInt(),
                                );
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

  /// Construir selector de presentaciones para un producto.
  ///
  /// - Productos SIN variantes: el usuario elige libremente la presentación
  ///   del dropdown. El factor real (`cantidad / cantidad_base`) se resuelve en
  ///   `_getPresentationConversionFactor` vía `PresentacionCadenaLocal`.
  ///
  /// - Productos CON variantes: **el dropdown no se oculta**, se muestra
  ///   **bloqueado** a la presentación de la variante que el usuario marcó.
  ///   Cada variante ya viene con su `id_presentacion` de la fila de inventario;
  ///   dejar el selector activo crearía dos ejes del mismo dato (presentación
  ///   global vs presentación por variante) y el usuario podría vender "1 Caja"
  ///   con el id_presentacion de la "Bolsa".
  Widget _buildPresentationSelector(
    Product product, [
    ProductVariant? variant,
  ]) {
    final productKey = '${product.id}';
    final selectedPresentationForProduct =
        _selectedPresentationsByProduct[productKey];
    final productoTieneVariantes = product.variantes.isNotEmpty;

    if (_productPresentations.isEmpty) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Presentación:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: VentiqHomeTheme.textPrimary,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: VentiqHomeTheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: VentiqHomeTheme.border, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.inventory_2,
                  size: 16,
                  color: VentiqHomeTheme.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Unidad (1.0)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: VentiqHomeTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Para productos con variantes, el dropdown se BLOQUEA a la presentación
    // de la variante seleccionada (no al del selector global). `onChanged`
    // no hace nada: el usuario cambia de variante, no de presentación.
    ProductPresentation? displayValue = selectedPresentationForProduct;
    bool onChangedEnabled = false;
    String? bloqueadoPorVariante;

    if (productoTieneVariantes) {
      // Priorizar el `variant` pasado por parámetro (la variante de ESTE card)
      // para que el dropdown refleje la presentación de la variante que
      // visualmente pertenece a este card, no la primera con cantidad del mapa.
      ProductVariant? varianteActiva = variant ?? selectedVariant;
      final cantActiva =
          varianteActiva != null
              ? variantQuantities[varianteActiva] ?? 0.0
              : 0.0;
      if (cantActiva <= 0) {
        varianteActiva = _varianteConCantidad();
      }
      if (varianteActiva != null) {
        final idPres =
            (varianteActiva.inventoryMetadata?['id_presentacion'] as num?)
                ?.toInt();
        if (idPres != null) {
          final presVariante = _productPresentations
              .cast<ProductPresentation?>()
              .firstWhere((p) => p?.id == idPres, orElse: () => null);
          if (presVariante != null) {
            displayValue = presVariante;
            bloqueadoPorVariante = presVariante.presentacion.denominacion;
          }
        }
      }
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Presentación:',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: VentiqHomeTheme.textPrimary,
          ),
        ),
        // Expanded para que el dropdown ocupe el espacio disponible entre
        // el label y el candado, en lugar de contraerse al ancho natural y
        // verse visualmente "abajo-centro" con el candado separado a la derecha.
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: VentiqHomeTheme.border, width: 1),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<ProductPresentation>(
                value: displayValue,
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
                              '${presentation.presentacion.denominacion} (${presentation.cantidad})'
                              '${() {
                                final d = _disponibilidadPorPresentacion()[presentation.id];
                                if (d == null) return '';
                                var tag = ' · ${FormatoPresentacion.cantidad(d.disponible)} disp';
                                if (d.stockPropio <= 0 && d.disponible > 0) {
                                  tag += ' · desarma';
                                }
                                return tag;
                              }()}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight:
                                    presentation.esBase
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                color:
                                    presentation.esBase
                                        ? Colors.orange[700]
                                        : VentiqHomeTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                onChanged:
                    onChangedEnabled
                        ? (ProductPresentation? newPresentation) {
                          setState(() {
                            _selectedPresentationsByProduct[productKey] =
                                newPresentation;
                            debugPrint(
                              '🔄 Presentación cambiada para producto '
                              '${product.id}: ${newPresentation?.presentacion.denominacion}',
                            );
                          });
                        }
                        : null, // BLOQUEADO: variante activa, no se cambia aquí.
              ),
            ),
          ),
        ),
        if (bloqueadoPorVariante != null)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Tooltip(
              message:
                  'Presentación de la variante seleccionada. '
                  'Cambie de variante para cambiar la presentación.',
              child: const Icon(Icons.lock, size: 14, color: Colors.grey),
            ),
          ),
      ],
    );
  }

  /// Primera variante con cantidad > 0, usada para bloquear el dropdown cuando
  /// el producto tiene variantes. Si ninguna variante tiene cantidad, devuelve
  /// la primera (el dropdown se muestra sobre la base, igual que antes del
  /// cierre de presentaciones).
  ProductVariant? _varianteConCantidad() {
    for (final e in variantQuantities.entries) {
      if (e.value > 0) return e.key;
    }
    if (currentProduct.variantes.isNotEmpty) {
      return currentProduct.variantes.first;
    }
    return null;
  }

  /// Factor RELATIVO A LA BASE de la presentación elegida para `product`.
  ///
  /// **No** es `presentation.cantidad` a secas: `cantidad` es el número de
  /// unidades base por empaquetado, pero la base NO siempre es x1 (131 filas
  /// `es_base` tienen cantidad 12/24/30). Usar `cantidad` cruda multiplica
  /// por el factor de la base dos veces en esos productos.
  ///
  /// El factor relativo correcto es `cantidad / cantidad_de_la_base`, que
  /// `PresentacionCadenaLocal` ya calcula replicando `fn_presentaciones_producto`.
  /// Este método delega en `_presentacionElegidaFactorRel` (que ya usa esa
  /// cadena) en vez de duplicar la lógica.
  ///
  /// - Para productos sin variantes: factor de la presentación elegida.
  /// - Para productos con variantes: **cada variante trae su propia fila de
  ///   inventario** con su `id_presentacion`; el factor se resuelve por
  ///   variante, no compartido. Si la variante no expone presentación, cae a 1.
  double _getPresentationConversionFactor(
    Product product, [
    ProductVariant? variant,
  ]) {
    final factor = _factorRelSeleccionado(product, variant);
    debugPrint(
      '📊 Factor de conversión para producto ${product.id}'
      '${variant != null ? ' (variante ${variant.id})' : ''}: $factor',
    );
    return factor;
  }

  /// Resuelve el `factorRel` de la presentación elegida.
  ///
  /// - Sin variante: el selector global de la pantalla (`_presentacionElegidaFactorRel`).
  /// - Con variante: el `id_presentacion` de su `inventoryMetadata`, buscado
  ///   en la cadena que se cargó para el producto. Si la variante no lo
  ///   expone, cae al selector global y luego a 1.0.
  double _factorRelSeleccionado(Product product, [ProductVariant? variant]) {
    if (variant != null) {
      final idPresVariante =
          (variant.inventoryMetadata?['id_presentacion'] as num?)?.toInt();
      if (idPresVariante != null) {
        final f = _factorRelDeCadena(product, idPresVariante);
        if (f != null) {
          return f;
        }
      }
    }
    return _presentacionElegidaFactorRel(product) ?? 1.0;
  }

  /// Busca el `factorRel` de un `id_presentacion` (fila
  /// `app_dat_producto_presentacion.id`) en la cadena cargada. El `id` de
  /// `ProductPresentation` es precisamente esa fila (ver el comentario de
  /// `_presentacionElegidaId`).
  double? _factorRelDeCadena(Product product, int idFilaPresentacion) {
    final crudas =
        _productPresentations
            .map(
              (p) => {
                'id': p.id,
                'cantidad': p.cantidad,
                'es_base': p.esBase,
                'presentacion': {
                  'id': p.idPresentacion,
                  'denominacion': p.presentacion.denominacion,
                  'sku_codigo': p.presentacion.skuCodigo,
                },
              },
            )
            .toList();
    final cadena = PresentacionCadenaLocal.resolverDesdeCrudas(crudas);
    for (final p in cadena) {
      if (p.idPresentacion == idFilaPresentacion) return p.factorRel;
    }
    return null;
  }

  /// Calcular el precio total considerando la presentación seleccionada.
  ///
  /// [variant] es necesario para productos con variantes: cada variante lleva
  /// su propia presentación (fila de inventario distinta), así que el factor se
  /// resuelve por variante, no global. Si se omite, usa la del selector global
  /// (caso de productos sin variantes).
  double _calculateTotalPriceWithPresentation(
    double basePrice,
    double quantity,
    Product product, [
    ProductVariant? variant,
  ]) {
    final conversionFactor = _getPresentationConversionFactor(product, variant);
    final unitPrice = basePrice * conversionFactor;
    final rawTotal = unitPrice * quantity;
    final totalPrice = rawTotal;

    debugPrint(
      '💰 Cálculo precio para producto ${product.id}'
      '${variant != null ? ' (variante ${variant.id})' : ''}:',
    );
    debugPrint('   - Precio base: \$${basePrice.toMoneyString(2)}');
    debugPrint('   - Factor conversión: ${conversionFactor}');
    debugPrint('   - Precio unitario: \$${unitPrice.toMoneyString(2)}');
    debugPrint('   - Cantidad: $quantity');
    debugPrint('   - Precio total: \$${totalPrice.toMoneyString(2)}');

    return totalPrice;
  }

  // Método para obtener el total de unidades equivalentes considerando presentaciones
  double _getTotalEquivalentUnits() {
    double total = 0.0;
    if (currentProduct.variantes.isEmpty) {
      // Producto sin variantes: factor de la presentación elegida en el selector.
      total =
          selectedQuantity * _getPresentationConversionFactor(currentProduct);
    } else {
      // Producto con variantes: CADA variante lleva su propia presentación
      // (fila de inventario distinta). Antes se aplicaba un solo factor del
      // producto a todas las variantes, lo que daba equivalentes falsos cuando
      // cada variante está en una presentación distinta (ej. "Variante 1 -
      // Caja" + "Variante 2 - Blister").
      for (final entry in variantQuantities.entries) {
        final quantity = entry.value;
        final factor = _getPresentationConversionFactor(
          currentProduct,
          entry.key,
        );
        total += quantity * factor;
      }
    }

    debugPrint('📊 Total unidades equivalentes calculado: $total');
    return total;
  }

  void _showQuantityDialog(
    String productName,
    double currentQuantity, [
    ProductVariant? variant,
  ]) {
    final isFractional = _isCurrentPresentationFractional(variant);
    final TextEditingController quantityController = TextEditingController(
      text: PriceUtils.formatQuantity(currentQuantity),
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
                keyboardType:
                    isFractional
                        ? const TextInputType.numberWithOptions(decimal: true)
                        : TextInputType.number,
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
                  _updateQuantityFromDialog(productName, value, variant);
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
                _updateQuantityFromDialog(
                  productName,
                  quantityController.text,
                  variant,
                );
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

  void _updateQuantityFromDialog(
    String productName,
    String quantityText, [
    ProductVariant? variant,
  ]) {
    final double? newQuantity = double.tryParse(quantityText);
    if (newQuantity == null || newQuantity < 0) return;

    // Aviso inmediato: la cantidad elegida excede el saldo propio de la
    // presentación, así que al vender se abrirán bultos de presentaciones
    // mayores. Es solo un aviso: la validación real la hace el preview al
    // agregar (online) o el resolutor local (offline).
    final stocks = _stocksPorPresentacionLocal();
    final cadena = _cadenaPresentaciones();
    if (stocks != null && cadena.isNotEmpty) {
      final idPres = _presentacionElegidaId(currentProduct);
      if (idPres != null && newQuantity > (stocks[idPres] ?? 0)) {
        final nombre =
            cadena
                .firstWhere(
                  (p) => p.idPresentacion == idPres,
                  orElse: () => cadena.first,
                )
                .nombre;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No hay suficiente $nombre suelto: se abrirán otras '
              'presentaciones para completar la venta.',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }

    setState(() {
      if (currentProduct.variantes.isEmpty) {
        // Producto sin variantes
        selectedQuantity = newQuantity;
      } else if (variant != null) {
        // R16: la variante se identifica por identidad, no por
        // `nombre.contains(...)`: dos variantes con nombres solapados
        // ("Caja" y "Caja grande") escribían la cantidad en la equivocada.
        final maxQty =
            currentProduct.esElaborado || currentProduct.esServicio
                ? newQuantity
                : newQuantity.clamp(0.0, maxQuantityForVariant(variant));
        variantQuantities[variant] = maxQty;
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

    // Dejar una variante seleccionada desde el primer frame: sin esto, con
    // variantes el vendedor veía «UBICACIONES» sin ningún control de venta y
    // tenía que tocar a ciegas una variante para que apareciera el stepper.
    _autoSeleccionarMejorVariante();
  }

  /// Auto-selecciona la variante con más stock para que los controles de venta
  /// estén disponibles de inmediato.
  ///
  /// - Con una ubicación: la primera variante (comportamiento anterior).
  /// - Con varias: la ubicación con más stock y, dentro, la variante con más
  ///   saldo. El vendedor puede cambiarla después en «UBICACIONES».
  void _autoSeleccionarMejorVariante() {
    if (locationGroups.isEmpty) return;

    MapEntry<String, List<ProductVariant>> mejor = locationGroups.entries.first;
    double mejorStock = _getLocationStock(mejor.value);

    for (final MapEntry<String, List<ProductVariant>> entry in locationGroups
        .entries
        .skip(1)) {
      final double stock = _getLocationStock(entry.value);
      if (stock > mejorStock) {
        mejor = entry;
        mejorStock = stock;
      }
    }

    if (mejor.value.isEmpty) return;

    ProductVariant elegida = mejor.value.first;
    for (final ProductVariant v in mejor.value.skip(1)) {
      if (v.cantidadReal > elegida.cantidadReal) elegida = v;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        selectedVariant = elegida;
        variantQuantities[elegida] = 1;
        _avisarDesarmePendiente(
          1,
          (elegida.inventoryMetadata?['id_presentacion'] as num?)?.toInt(),
        );
      });
    });

    debugPrint(
      '🎯 Auto-selección: ${mejor.key} · ${elegida.nombre} '
      '(stock ${elegida.cantidadReal})',
    );
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
  double _getLocationStock(List<ProductVariant> variants) {
    return variants.fold(0.0, (sum, variant) => sum + variant.cantidad);
  }

  double _getLocationStockReal(List<ProductVariant> variants) {
    return variants.fold(0.0, (sum, variant) => sum + variant.cantidadReal);
  }

  num _getLocationReservadoCarnaval(List<ProductVariant> variants) {
    return variants.fold<num>(
      0,
      (sum, variant) => sum + variant.reservadoCarnaval,
    );
  }

  num _getLocationEnOrdenesCarnaval(List<ProductVariant> variants) {
    return variants.fold<num>(
      0,
      (sum, variant) => sum + variant.enOrdenesCarnaval,
    );
  }

  bool _hasValidProductImage(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    if (url.contains('unsplash.com')) return false;
    return true;
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
  /// Id de la fila `app_dat_producto_presentacion` que el usuario eligió, o
  /// `null` si no hay ninguna cargada.
  ///
  /// FASE 4 presentaciones. Ojo con el nombre de los campos de
  /// `ProductPresentation`: `id` es la FILA (lo que el ledger guarda en
  /// `id_presentacion`) e `idPresentacion` es la FK al nomenclador
  /// (1=Unidad, 3=Caja...). Mandar `idPresentacion` haría que el servidor no
  /// encontrara la fila y cayera al fallback de la base — el mismo choque de
  /// nombres que causó el bug de valoración del `19`.
  int? _presentacionElegidaId(Product product) {
    return _selectedPresentationsByProduct['${product.id}']?.id;
  }

  /// Nombre de la presentación elegida ("Bulto").
  String? _presentacionElegidaNombre(Product product) {
    return _selectedPresentationsByProduct['${product.id}']
        ?.presentacion
        .denominacion;
  }

  /// Factor RELATIVO A LA BASE de la presentación elegida.
  ///
  /// No es `presentation.cantidad` a secas: hay 131 filas `es_base` con factor
  /// 12/24/30, y ahí `cantidad` no es el equivalente real. El factor relativo es
  /// `cantidad / cantidad_de_la_base`, que es lo que calcula
  /// `PresentacionCadenaLocal` replicando `fn_presentaciones_producto`.
  double? _presentacionElegidaFactorRel(Product product) {
    final elegida = _selectedPresentationsByProduct['${product.id}'];
    if (elegida == null) return null;

    final cadena = PresentacionCadenaLocal.resolverDesdeCrudas(
      _productPresentations
          .map(
            (p) => {
              'id': p.id,
              'cantidad': p.cantidad,
              'es_base': p.esBase,
              'presentacion': {
                'id': p.idPresentacion,
                'denominacion': p.presentacion.denominacion,
                'sku_codigo': p.presentacion.skuCodigo,
              },
            },
          )
          .toList(),
    );

    // Match por `id` = fila de `app_dat_producto_presentacion` (11197, 11198...).
    // `PresentacionCadenaLocal.idPresentacion` guarda `raw['id']`, o sea la FILA,
    // y el ledger (`app_dat_inventario_productos.id_presentacion`) tambien usa la
    // fila — verificado en produccion con el producto 11007. NO comparar contra
    // `idPresentacion` (el nomenclador 1=Unidad/3=Caja): no coincide nunca.
    for (final p in cadena) {
      if (p.idPresentacion == elegida.id) return p.factorRel;
    }
    return null;
  }

  /// Cadena de presentaciones del producto, ya ordenada y con factores.
  ///
  /// Misma construcción que usa `_presentacionElegidaFactorRel`: el `id` de
  /// `ProductPresentation` es la FILA (`app_dat_producto_presentacion.id`),
  /// que es lo que guardan tanto `PresentacionLocal.idPresentacion` como el
  /// ledger (`app_dat_inventario_productos.id_presentacion`).
  List<PresentacionLocal> _cadenaPresentaciones() {
    return PresentacionCadenaLocal.resolverDesdeCrudas(
      _productPresentations
          .map(
            (p) => {
              'id': p.id,
              'cantidad': p.cantidad,
              'es_base': p.esBase,
              'presentacion': {
                'id': p.idPresentacion,
                'denominacion': p.presentacion.denominacion,
                'sku_codigo': p.presentacion.skuCodigo,
              },
            },
          )
          .toList(),
    );
  }

  /// Saldos locales por presentación para evaluar el desarme sin red.
  ///
  /// Fuente principal: las filas de inventario que ya llegan como variantes
  /// (`inventoryMetadata['id_presentacion']` + `cantidadReal`) y, para
  /// productos sin variantes, la metadata del producto. `stockMixto` queda de
  /// respaldo. Si no hay nada, devuelve null y el evaluador no bloquea.
  Map<int, double>? _stocksPorPresentacionLocal() {
    final out = <int, double>{};

    for (final v in currentProduct.variantes) {
      final id = (v.inventoryMetadata?['id_presentacion'] as num?)?.toInt();
      if (id == null) continue;
      out[id] = (out[id] ?? 0) + v.cantidadReal.toDouble();
    }

    if (out.isEmpty) {
      final meta = currentProduct.inventoryMetadata;
      final id = (meta?['id_presentacion'] as num?)?.toInt();
      if (id != null) {
        out[id] = currentProduct.cantidadReal.toDouble();
      }
    }

    if (out.isNotEmpty) return out;

    final mixto = currentProduct.stockMixto;
    if (mixto == null || mixto.isEmpty) return null;
    for (final fila in mixto) {
      final id = (fila['id_presentacion'] as num?)?.toInt();
      final cant =
          (fila['cantidad_final'] as num?)?.toDouble() ??
          (fila['saldo'] as num?)?.toDouble();
      if (id != null && cant != null) {
        out[id] = (out[id] ?? 0) + cant;
      }
    }
    return out;
  }

  /// Unidades base ya reservadas por ESTE producto en la orden actual.
  ///
  /// "Consumo acumulado en base": las líneas del carrito que comparten pozo
  /// de stock (mismo producto, cualquier presentación) se suman en unidades
  /// base y se descuentan del total convertible, evitando sobreventa entre
  /// presentaciones (1 Bulto + 5 Unidades compiten por el mismo stock).
  ///
  /// `item.cantidad` está en SU presentación; `item.idPresentacion` es la
  /// fila de `app_dat_producto_presentacion` y su factor se resuelve en la
  /// cadena local. Items sin presentación cuentan como unidad base.
  double _reservadoBaseEnCarrito() {
    final items = OrderService().currentOrder?.items;
    if (items == null || items.isEmpty) return 0;
    final cadena = _cadenaPresentaciones();
    var total = 0.0;
    for (final item in items) {
      if (item.producto.id != currentProduct.id) continue;
      final idPres =
          item.idPresentacion ??
          (item.inventoryData?['id_presentacion'] as num?)?.toInt();
      var factor = 1.0;
      if (idPres != null) {
        for (final p in cadena) {
          if (p.idPresentacion == idPres) {
            factor = p.factorRel;
            break;
          }
        }
        // No está en la cadena: usar el factor congelado del item si existe.
        if (factor == 1.0) factor = item.presentacionFactor ?? 1.0;
      }
      total += item.cantidad * factor;
    }
    return total;
  }

  /// Disponibilidad neta por presentación: stock + convertible - reservas.
  Map<int, DisponibilidadPresentacion> _disponibilidadPorPresentacion() {
    final cadena = _cadenaPresentaciones();
    final stocks = _stocksPorPresentacionLocal();
    if (cadena.isEmpty || stocks == null) return const {};
    return DesarmeBultoLocal.disponiblesPorPresentacion(
      cadena: cadena,
      stocks: stocks,
      reservadoBase: _reservadoBaseEnCarrito(),
    );
  }

  /// Presentaciones configuradas que no tienen fila de inventario.
  ///
  /// El listado de variantes nace de las filas de
  /// `app_dat_inventario_productos`, así que una presentación jamás recibida
  /// no aparece. Si el producto usa presentaciones COMO variantes (ninguna
  /// fila trae `id_variante` real), se crea una variante sintética con
  /// cantidad 0 para que sea seleccionable y se sirva por desarme.
  void _agregarVariantesPresentacionesSinStock() {
    if (_productPresentations.isEmpty) return;
    final variantes = currentProduct.variantes;
    if (variantes.isEmpty) return;

    // El inventario guarda filas por pareja variante×presentación. Una
    // presentación sin fila no aparece: se crea una variante sintética por
    // cada id_variante que no la tenga, clonando la fila existente de esa
    // variante (misma ubicación/precio, cantidad 0 → se sirve por desarme).
    final porVariante = <int?, List<ProductVariant>>{};
    for (final v in variantes) {
      final idVar = (v.inventoryMetadata?['id_variante'] as num?)?.toInt();
      porVariante.putIfAbsent(idVar, () => []).add(v);
    }

    var nextId = variantes.fold<int>(0, (m, v) => math.max(m, v.id)) + 1;
    var agregadas = 0;

    for (final entry in porVariante.entries) {
      final filas = entry.value;
      final conFila =
          filas
              .map(
                (v) =>
                    (v.inventoryMetadata?['id_presentacion'] as num?)?.toInt(),
              )
              .whereType<int>()
              .toSet();
      final plantilla = filas.first;

      for (final pres in _productPresentations) {
        if (conFila.contains(pres.id)) continue;
        final meta = Map<String, dynamic>.from(
          plantilla.inventoryMetadata ?? {},
        );
        meta['id_presentacion'] = pres.id;
        meta['cantidad_disponible'] = 0.0;
        meta['presentacion_nombre'] = pres.presentacion.denominacion;
        meta['presentacion_sin_stock'] = true;
        // El nombre de la fila real es "<atributos> - <presentación>": se
        // conserva la parte de atributos y se cambia la presentación.
        var nombreBase = plantilla.nombre;
        final presPlantilla =
            plantilla.inventoryMetadata?['presentacion_nombre']?.toString();
        if (presPlantilla != null && nombreBase.endsWith(' - $presPlantilla')) {
          nombreBase = nombreBase.substring(
            0,
            nombreBase.length - presPlantilla.length - 3,
          );
        }
        final nombreFinal =
            nombreBase == plantilla.nombre
                ? pres.presentacion.denominacion
                : '$nombreBase - ${pres.presentacion.denominacion}';
        final sintetica = ProductVariant(
          id: nextId++,
          nombre: nombreFinal,
          precio: plantilla.precio,
          cantidad: 0,
          descripcion:
              'Sin stock propio: se sirve desarmando otras presentaciones',
          inventoryMetadata: meta,
        );
        variantes.add(sintetica);
        variantQuantities.putIfAbsent(sintetica, () => 0);
        agregadas++;
      }
    }
    if (agregadas > 0) {
      debugPrint(
        '📦 $agregadas presentaciones sin stock expuestas como variantes '
        '(se sirven por desarme)',
      );
      _groupVariantsByLocation(variantes);
    }
  }

  /// Aviso offline: no alcanza el stock ni desarmando bultos.
  ///
  /// Gemelo de `_avisarImposible` de `PreviewRebalanceoService`, pero con el
  /// máximo calculado localmente. No usa la preferencia "no preguntar": la
  /// falta de stock no se silencia.
  Future<void> _avisarStockInsuficienteOffline(double maximoServible) async {
    await showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.inventory_2_outlined, color: Colors.red),
                SizedBox(width: 8),
                Expanded(child: Text('No hay suficiente')),
              ],
            ),
            content: Text(
              maximoServible > 0
                  ? 'No alcanza el stock disponible. Como máximo se pueden servir '
                      '${FormatoPresentacion.cantidad(maximoServible)}.'
                  : 'No alcanza el stock disponible.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Entendido'),
              ),
            ],
          ),
    );
  }

  /// Confirmación offline del desarme. `null` si se canceló el diálogo.
  Future<bool?> _confirmarDesarmeOffline(PlanDesarme plan) async {
    if (!mounted) return false;
    return showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.unfold_more, color: Colors.orange.shade800),
                const SizedBox(width: 8),
                const Expanded(child: Text('¿Desarmar un bulto?')),
              ],
            ),
            content: Text(plan.mensaje),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Desarmar'),
              ),
            ],
          ),
    );
  }

  /// Plan de desarme para una cantidad y presentación concretas, calculado
  /// con los saldos locales (las variantes ya traen las filas de inventario).
  /// Null si alcanza el saldo propio o no hay datos para evaluar.
  PlanDesarme? _planDesarmePara(double cantidad, int? idPresentacion) {
    if (idPresentacion == null || cantidad <= 0) return null;
    final cadena = _cadenaPresentaciones();
    final stocks = _stocksPorPresentacionLocal();
    if (cadena.isEmpty || stocks == null) return null;
    final eval = DesarmeBultoLocal.evaluar(
      cadena: cadena,
      stocks: stocks,
      idPresentacionPedida: idPresentacion,
      cantidadPedida: cantidad,
    );
    return eval.requiereDesarme ? eval.plan : null;
  }

  /// Texto informativo de qué se va a abrir para servir [cantidad].
  ///
  /// Se muestra al pasarce del saldo propio de la presentación — también con
  /// el 1 por defecto cuando el saldo es 0 — y en el snackbar de éxito.
  String? _mensajeDesarmePara(double cantidad, int? idPresentacion) {
    final plan = _planDesarmePara(cantidad, idPresentacion);
    if (plan == null) return null;
    return '📦 Se abrirá ${FormatoPresentacion.cantidad(plan.cantidadOrigen)} '
        '${FormatoPresentacion.plural(plan.origen.nombre, plan.cantidadOrigen)} '
        '(${FormatoPresentacion.cantidad(plan.cantidadDestino)} '
        '${FormatoPresentacion.plural(_nombrePresentacionPedida(idPresentacion)!, plan.cantidadDestino)})';
  }

  String? _nombrePresentacionPedida(int? idPresentacion) {
    if (idPresentacion == null) return null;
    for (final p in _cadenaPresentaciones()) {
      if (p.idPresentacion == idPresentacion) return p.nombre;
    }
    return null;
  }

  /// Líneas "Se abrió X Y" a partir del plan del preview online.
  List<String> _conversionesDePreview(PreviewRebalanceo preview) {
    final msg = preview.mensajeUsuario?.toString() ?? '';
    if (msg.isEmpty) return const [];
    return ['📦 $msg'];
  }

  /// Aviso informativo (no bloqueante) de que la cantidad excede el saldo
  /// propio y se abrirán bultos. Incluye el caso del 1 por defecto con saldo 0.
  void _avisarDesarmePendiente(double cantidad, int? idPresentacion) {
    final mensaje = _mensajeDesarmePara(cantidad, idPresentacion);
    if (mensaje == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

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

    // FASE 4 presentaciones: la presentación ELEGIDA en la UI manda sobre la
    // del inventario.
    //
    // `inventoryMetadata['id_presentacion']` es la presentación de la fila de
    // inventario que resolvió el catálogo — normalmente la base. Si el usuario
    // eligió "Bulto" en el selector y se manda esa, el servidor registra la
    // venta contra la presentación equivocada: cantidad en Bultos con el
    // id_presentacion de la Bolsa.
    //
    // CON VARIANTE la regla se invierte: cada variante es su propia fila de
    // inventario con su propio `id_presentacion`, y el precio ya se calculó
    // con ese factor (`_factorRelSeleccionado`). El selector global es
    // por-producto; si mandara aquí, todas las variantes llegarían al RPC con
    // la misma presentación y el precio quedaría en la unidad equivocada.
    final int? idPresFila =
        variant != null
            ? ((inventoryMetadata['id_presentacion'] as num?)?.toInt() ??
                _presentacionElegidaId(product))
            : (_presentacionElegidaId(product) ??
                (inventoryMetadata['id_presentacion'] as num?)?.toInt());
    final String? presNombre =
        variant != null
            ? (idPresFila != null
                    ? _nombrePresentacionPedida(idPresFila)
                    : null) ??
                _presentacionElegidaNombre(product)
            : _presentacionElegidaNombre(product);
    final double? presFactor =
        variant != null
            ? (idPresFila != null
                    ? _factorRelDeCadena(product, idPresFila)
                    : null) ??
                _presentacionElegidaFactorRel(product)
            : _presentacionElegidaFactorRel(product);

    final inventoryData = {
      'id_producto': product.id,
      'id_variante': inventoryMetadata['id_variante'],
      'id_opcion_variante': inventoryMetadata['id_opcion_variante'],
      'id_ubicacion': inventoryMetadata['id_ubicacion'],
      // Fallback al inventario cuando el producto no tiene presentaciones
      // cargadas (offline sin caché): el servidor resuelve la base.
      'id_presentacion': idPresFila,
      // Nombre y factor relativo de la presentación elegida, para que
      // `OrderService` los congele en el `OrderItem`. Van por aquí porque
      // `Product` no lleva las presentaciones: la cadena vive en el estado de
      // esta pantalla (`_productPresentations`), no en el modelo.
      'presentacion_nombre': presNombre,
      'presentacion_factor_rel': presFactor,
      'sku_producto':
          inventoryMetadata['sku_producto'] ?? product.id.toString(),
      'sku_ubicacion': inventoryMetadata['sku_ubicacion'],
    };

    print('✅ Inventory data construido: $inventoryData');
    return inventoryData;
  }

  /// Recoge de OrderService el resultado del ultimo item pedido y, si fue a
  /// cocina, guarda el nombre de la estacion para el aviso. Devuelve sin hacer
  /// nada cuando la linea no paso por la ruta de Fase 2.
  void _acumularDestinoCocina(OrderService s, Set<String> destinos) {
    final r = s.ultimoPedido;
    if (r == null || !r.fueACocina) return;
    destinos.add(r.cocinaNombre ?? 'cocina');
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

    double totalItemsAdded = 0.0;
    List<String> addedItems = [];
    // Fase 2: a que cocinas se mandaron los platos, para decirlo en el aviso.
    final Set<String> destinosCocina = {};
    // Desarme: que empaques se abrieron para servir la venta, para el aviso.
    final List<String> desarmesAplicados = [];

    try {
      // El factor se calcula POR rama (sin variantes) y POR VARIANTE (con
      // variantes): cada variante puede estar en una presentación distinta, por
      // eso no se puede extrapolar un solo `conversionFactor` del producto a
      // todas las variantes. Ver comentario FASE 4 arriba.
      final conversionFactor = _getPresentationConversionFactor(currentProduct);

      // ══════════════════════════════════════════════════════════════════════
      // FASE 4.1 · Preguntar antes de abrir o armar un empaque.
      //
      // Se consulta ANTES de tocar el carrito: con cocina activa
      // `addItemToCurrentOrder` ya descuenta inventario, así que preguntar
      // después sería preguntar por algo ya hecho.
      //
      // La consulta es de solo lectura y NO reserva stock: entre esto y la
      // venta otra caja puede mover el saldo. El error de la venta se sigue
      // manejando igual; este diálogo no lo sustituye.
      // ══════════════════════════════════════════════════════════════════════
      final invPreview = _buildInventoryData(currentProduct, null);
      final idPresPreview = (invPreview['id_presentacion'] as num?)?.toInt();
      final idUbicPreview = (invPreview['id_ubicacion'] as num?)?.toInt();
      final cantidadPreview =
          currentProduct.variantes.isEmpty
              ? selectedQuantity
              : variantQuantities.values.fold<double>(0, (s, v) => s + v);

      if (idPresPreview != null &&
          idUbicPreview != null &&
          cantidadPreview > 0) {
        // ══════════════════════════════════════════════════════════════════
        // DESARME OFFLINE: `PreviewRebalanceoService` depende de
        // `fn_preview_rebalanceo` (red). Sin red, el desarme se evalúa
        // localmente con la cadena cacheada y los saldos de `stockMixto`.
        // Es solo consulta: al sincronizar, la venta ejecuta el rebalanceo
        // real en el servidor (`fn_rebalancear_presentaciones`), que es la
        // autoridad. Aquí solo se avisa al vendedor y se pide confirmación.
        // ══════════════════════════════════════════════════════════════════
        final useLocalData = await _userPreferencesService.shouldUseLocalData();
        var seguir = true;

        if (useLocalData) {
          final eval = DesarmeBultoLocal.evaluar(
            cadena: _cadenaPresentaciones(),
            stocks: _stocksPorPresentacionLocal() ?? const {},
            idPresentacionPedida: idPresPreview,
            cantidadPedida: cantidadPreview,
          );

          if (eval.esImposible) {
            await _avisarStockInsuficienteOffline(eval.maximoServible);
            seguir = false;
          } else if (eval.requiereDesarme) {
            seguir = await _confirmarDesarmeOffline(eval.plan!) ?? false;
            if (seguir) {
              desarmesAplicados.add(
                '📦 Se abrió ${FormatoPresentacion.cantidad(eval.plan!.cantidadOrigen)} '
                '${FormatoPresentacion.plural(eval.plan!.origen.nombre, eval.plan!.cantidadOrigen)}',
              );
            }
          }
        } else {
          final preview = await PreviewRebalanceoService.consultar(
            idProducto: currentProduct.id,
            idUbicacion: idUbicPreview,
            idPresentacion: idPresPreview,
            cantidad: cantidadPreview,
          );
          seguir = await PreviewRebalanceoService.confirmarSiHaceFalta(
            context,
            idProducto: currentProduct.id,
            idUbicacion: idUbicPreview,
            idPresentacion: idPresPreview,
            cantidad: cantidadPreview,
          );
          if (seguir && preview.requierePreguntar) {
            for (final conv in _conversionesDePreview(preview)) {
              desarmesAplicados.add(conv);
            }
          }
        }
        if (!seguir) return;
      }

      if (currentProduct.variantes.isEmpty) {
        // Producto sin variantes
        if (selectedQuantity > 0) {
          final basePrice = _getEffectiveBasePrice(currentProduct);
          final discountPrice = _calculateDiscountPrice(basePrice);
          final finalPrice = discountPrice ?? basePrice;

          // ══════════════════════════════════════════════════════════════════
          // FASE 4 presentaciones: la cantidad va EN LA PRESENTACION ELEGIDA.
          //
          // Antes se mandaba `selectedQuantity * conversionFactor` (unidades
          // base) y el precio por unidad base. El servidor guardaba entonces
          // "24 Unidades" cuando el cajero vendio "2 Cajas": el ledger perdia
          // el empaque y el criterio central del plan (transferir 2 cajas deja
          // 2 Cajas, no 24 Unidades) se rompia en la venta.
          //
          // Ahora: cantidad = lo que el usuario escribio, precio_unitario =
          // precio base x factor. El IMPORTE no cambia -- es el mismo producto
          // de los dos numeros -- asi que ni el total de la orden ni el
          // arqueo se mueven.
          // ══════════════════════════════════════════════════════════════════
          final cantidadEnPresentacion = selectedQuantity;
          final precioPorPresentacion = finalPrice * conversionFactor;
          final precioBasePorPresentacion = basePrice * conversionFactor;

          // await: con cocina activa esto PIDE el plato (mueve inventario y
          // dispara comanda) y puede fallar por falta de stock. Sin await la
          // excepcion se perderia y el mensaje diria "agregado" de todos modos.
          await orderService.addItemToCurrentOrder(
            producto: currentProduct,
            cantidad: cantidadEnPresentacion,
            ubicacionAlmacen: _getLocationName(currentProduct, null),
            inventoryData: _buildInventoryData(currentProduct, null),
            precioUnitario: precioPorPresentacion,
            precioBase: precioBasePorPresentacion,
            promotionData: _getActivePromotion(),
          );
          _acumularDestinoCocina(orderService, destinosCocina);
          totalItemsAdded += cantidadEnPresentacion;
          addedItems.add(
            '${currentProduct.denominacion} (x${PriceUtils.formatQuantity(cantidadEnPresentacion)})',
          );

          // Resetear cantidad después de agregar
          setState(() {
            selectedQuantity = 0.0;
          });
        }
      } else {
        // Producto con variantes
        for (var entry in variantQuantities.entries) {
          if (entry.value > 0) {
            final basePrice = _getEffectiveBasePrice(currentProduct, entry.key);
            final discountPrice = _calculateDiscountPrice(basePrice);
            final finalPrice = discountPrice ?? basePrice;
            // FASE 4: igual que la rama sin variantes — cantidad en la
            // presentación elegida, precio × factor. Ver el comentario largo
            // arriba. Pero aquí el factor es POR VARIANTE: cada una lleva su
            // propia presentación (fila de inventario distinta), así que no se
            // reusa el `conversionFactor` global del try{} encima.
            final cantidadEnPresentacion = entry.value;
            final factorVariante = _getPresentationConversionFactor(
              currentProduct,
              entry.key,
            );
            final precioPorPresentacion = finalPrice * factorVariante;
            final precioBasePorPresentacion = basePrice * factorVariante;

            await orderService.addItemToCurrentOrder(
              producto: currentProduct,
              variante: entry.key,
              cantidad: cantidadEnPresentacion,
              ubicacionAlmacen: _getLocationName(currentProduct, entry.key),
              inventoryData: _buildInventoryData(currentProduct, entry.key),
              precioUnitario: precioPorPresentacion,
              precioBase: precioBasePorPresentacion,
              promotionData: _getActivePromotion(),
            );
            _acumularDestinoCocina(orderService, destinosCocina);
            totalItemsAdded += cantidadEnPresentacion;
            addedItems.add(
              '${entry.key.nombre} (x${PriceUtils.formatQuantity(cantidadEnPresentacion)})',
            );
          }
        }

        // Resetear cantidades después de agregar
        setState(() {
          for (var variant in currentProduct.variantes) {
            variantQuantities[variant] = 0.0;
          }
        });
      }

      // Mostrar mensaje de éxito y navegar a categorías
      if (totalItemsAdded > 0) {
        // El stock cambió: que reabrir el detalle no muestre la caché vieja.
        _productDetailService.invalidarDetalle(currentProduct.id);

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
                // Fase 2: si el plato se mando a cocina hay que DECIRLO. El
                // mesero necesita saber que ya esta comandado y no volver a
                // pedirlo, y con que estacion contar el tiempo.
                if (destinosCocina.isNotEmpty)
                  Text(
                    '🍳 Enviado a ${destinosCocina.join(", ")}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else
                  Text(
                    'Total en orden: ${orderService.currentOrderItemCount} productos',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                // Desarme: decir QUÉ se abrió para servir la venta, siempre
                // que haya hecho falta (queda registrado en el servidor).
                for (final d in desarmesAplicados)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      d,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
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
