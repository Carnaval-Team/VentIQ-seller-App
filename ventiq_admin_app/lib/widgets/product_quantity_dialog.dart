import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_colors.dart';
import '../models/product.dart';
import '../models/warehouse.dart';
import '../services/currency_service.dart';
import '../services/presentacion_cadena_service.dart';
import '../utils/presentation_converter.dart';
import 'cantidad_mixta_input.dart';
import 'price_currency_converter_widget.dart';
import 'presentacion_equivalencia_widget.dart';

class ProductQuantityDialog extends StatefulWidget {
  final Product product;
  final WarehouseZone? selectedLocation;
  final String invoiceCurrency;
  final double? exchangeRate;
  final Function(Map<String, dynamic>) onProductAdded;

  const ProductQuantityDialog({
    Key? key,
    required this.product,
    required this.onProductAdded,
    this.selectedLocation,
    required this.invoiceCurrency,
    this.exchangeRate,
  }) : super(key: key);

  @override
  State<ProductQuantityDialog> createState() => _ProductQuantityDialogState();
}

class _ProductQuantityDialogState extends State<ProductQuantityDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _precioUnitarioController = TextEditingController();
  final _precioReferenciaController = TextEditingController();
  final _descuentoPorcentajeController = TextEditingController();
  final _descuentoMontoController = TextEditingController();
  final _bonificacionCantidadController = TextEditingController();
  final _codigoLoteController = TextEditingController();
  DateTime? _fechaVencimiento;

  List<Map<String, dynamic>> _availableVariants = [];
  List<Map<String, dynamic>> _availablePresentations = [];
  Map<String, dynamic>? _selectedVariant;
  Map<String, dynamic>? _selectedPresentation;

  double? _lastPurchasePrice;
  String? _lastPurchaseDate;
  bool _isLoadingLastPrice = false;
  double? _averagePrice;
  bool _isLoadingAveragePrice = false;

  // Variables para conversión de moneda (siempre en USD)
  double? _finalPriceInUSD;
  String _finalCurrency = 'USD';

  // ── FASE 2 presentaciones: captura mixta ─────────────────────────────────
  // El modo mixto permite entrar "4 cajas Y 4 unidades" en un solo formulario,
  // que es el objetivo de la fase. El modo simple (un dropdown + una cantidad)
  // se conserva para productos de una sola presentacion y como salida si algo
  // falla al leer la cadena.
  bool _modoMixto = false;
  bool _cargandoCadenaMixta = true;
  List<PresentacionCadena> _cadena = [];
  List<LineaMixta> _lineasMixtas = [];

  /// Moneda en la que el usuario escribe los precios del modo mixto.
  String _monedaEntradaMixta = 'USD';

  /// Tasa USD→CUP para convertir los precios mixtos. Se lee una vez.
  double? _usdToCupRate;

  /// Flag real de lotes: el selector de recepción a menudo no trae
  /// `es_por_lotes` en el Map → Product queda en false. Se resuelve al abrir.
  bool _esPorLotes = false;
  bool _cargandoFlagLotes = true;

  @override
  void initState() {
    super.initState();

    // Debug: Verificar el producto recibido en el diálogo
    print('🎯 ProductQuantityDialog - Producto recibido:');
    print('  - name: ${widget.product.name}');
    print('  - sku: "${widget.product.sku}"');
    print('  - sku.isEmpty: ${widget.product.sku.isEmpty}');
    print('  - esPorLotes (payload): ${widget.product.esPorLotes}');

    _esPorLotes = widget.product.esPorLotes;
    _finalCurrency = widget.invoiceCurrency;
    _monedaEntradaMixta = widget.invoiceCurrency;
    _initializeVariantsAndPresentations();
    _loadLastPurchasePrice();
    _cargarCadenaMixta();
    _resolverEsPorLotes();
  }

  /// Confirma `es_por_lotes` desde BD si el Product llegó sin el flag.
  Future<void> _resolverEsPorLotes() async {
    if (widget.product.esPorLotes) {
      if (mounted) {
        setState(() {
          _esPorLotes = true;
          _cargandoFlagLotes = false;
        });
      }
      return;
    }

    final idProducto = int.tryParse(widget.product.id);
    if (idProducto == null) {
      if (mounted) setState(() => _cargandoFlagLotes = false);
      return;
    }

    try {
      final row = await Supabase.instance.client
          .from('app_dat_producto')
          .select('es_por_lotes')
          .eq('id', idProducto)
          .maybeSingle();
      final flag = row != null && row['es_por_lotes'] == true;
      print('🎯 es_por_lotes desde BD (id=$idProducto): $flag');
      if (mounted) {
        setState(() {
          _esPorLotes = flag;
          _cargandoFlagLotes = false;
        });
      }
    } catch (e) {
      print('⚠️ No se pudo leer es_por_lotes: $e');
      if (mounted) setState(() => _cargandoFlagLotes = false);
    }
  }

  /// Lee la cadena de presentaciones y decide si ofrecer captura mixta.
  ///
  /// Solo se ofrece con 2+ presentaciones: con una sola, el modo mixto seria un
  /// formulario mas complicado para hacer exactamente lo mismo.
  Future<void> _cargarCadenaMixta() async {
    final idProducto = int.tryParse(widget.product.id);
    if (idProducto == null) {
      if (mounted) setState(() => _cargandoCadenaMixta = false);
      return;
    }

    final cadena = await PresentacionCadenaService.cadena(idProducto);
    if (!mounted) return;

    setState(() {
      _cadena = cadena;
      _modoMixto = cadena.length > 1;
      _cargandoCadenaMixta = false;
      if (cadena.isNotEmpty) {
        final base = cadena.firstWhere(
          (presentacion) => presentacion.esBase,
          orElse: () => cadena.first,
        );
        final matches = _availablePresentations.where(
          (presentacion) =>
              presentacion['id']?.toString() == base.idPresentacion.toString(),
        );
        if (matches.isNotEmpty) {
          _selectedPresentation = matches.first;
          _loadAveragePriceForPresentation(matches.first);
        }
      }
    });

    if (cadena.length > 1) {
      // La tasa solo hace falta si el usuario va a escribir precios en CUP.
      try {
        final rate = await CurrencyService.getEffectiveUsdToCupRate();
        if (mounted) setState(() => _usdToCupRate = rate);
      } catch (e) {
        print('⚠️ No se pudo leer la tasa USD→CUP: $e');
      }
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _precioUnitarioController.dispose();
    _precioReferenciaController.dispose();
    _descuentoPorcentajeController.dispose();
    _descuentoMontoController.dispose();
    _bonificacionCantidadController.dispose();
    _codigoLoteController.dispose();
    super.dispose();
  }

  bool get _requiereLote => _esPorLotes;

  /// Campos de lote para el payload de recepción (Fase 1 vencimientos).
  Map<String, dynamic> _lotePayload() {
    if (!_requiereLote) return const {};
    final codigo = _codigoLoteController.text.trim();
    final fecha = _fechaVencimiento;
    return {
      if (codigo.isNotEmpty) 'codigo_lote': codigo,
      if (fecha != null)
        'fecha_vencimiento':
            '${fecha.year.toString().padLeft(4, '0')}-'
            '${fecha.month.toString().padLeft(2, '0')}-'
            '${fecha.day.toString().padLeft(2, '0')}',
    };
  }

  bool _validarLoteSiAplica() {
    if (_cargandoFlagLotes) {
      _mostrarError('Cargando datos del producto, espere un momento…');
      return false;
    }
    if (!_requiereLote) return true;
    if (_codigoLoteController.text.trim().isEmpty) {
      _mostrarError('Este producto es por lotes: indique el código de lote');
      return false;
    }
    if (_fechaVencimiento == null) {
      _mostrarError(
        'Este producto es por lotes: indique la fecha de vencimiento',
      );
      return false;
    }
    return true;
  }

  void _initializeVariantsAndPresentations() {
    final Map<String, Map<String, dynamic>> variantMap = {};
    final Map<String, Map<String, dynamic>> presentationMap = {};

    // Process variants from variantesDisponibles
    if (widget.product.variantesDisponibles.isNotEmpty) {
      for (final varianteDisponible in widget.product.variantesDisponibles) {
        if (varianteDisponible['variante'] != null) {
          final variant = varianteDisponible['variante'];
          if (variant['opciones'] != null && variant['opciones'] is List) {
            final opciones = variant['opciones'] as List<dynamic>;
            for (final opcion in opciones) {
              final variantKey = '${variant['id']}_${opcion['id']}';
              if (!variantMap.containsKey(variantKey)) {
                variantMap[variantKey] = {
                  'id': variant['id'],
                  'atributo': variant['atributo'],
                  'opcion': opcion,
                };
              }
            }
          } else {
            final variantKey = '${variant['id']}_no_option';
            if (!variantMap.containsKey(variantKey)) {
              variantMap[variantKey] = {
                'id': variant['id'],
                'atributo': variant['atributo'],
                'opcion': null,
              };
            }
          }
        }

        // Process presentations
        if (varianteDisponible['presentaciones'] != null) {
          final presentaciones =
              varianteDisponible['presentaciones'] as List<dynamic>;
          for (final presentation in presentaciones) {
            final presentationKey = presentation['id'].toString();
            if (!presentationMap.containsKey(presentationKey)) {
              presentationMap[presentationKey] = presentation;
            }
          }
        }
      }
    }

    // Add direct presentations from product
    for (int i = 0; i < widget.product.presentaciones.length; i++) {
      final presentation = widget.product.presentaciones[i];
      final presentationKey = presentation['id']?.toString() ?? i.toString();
      if (!presentationMap.containsKey(presentationKey)) {
        presentationMap[presentationKey] = presentation;
      }
    }

    _availableVariants = variantMap.values.toList();
    _availablePresentations = presentationMap.values.toList();
    _selectedVariant = null;
    _selectedPresentation = null;

    // Selección temporal hasta que llegue la cadena canónica. No se infiere la
    // base por el nombre; `_cargarCadenaMixta` la sustituye usando `esBase`.
    if (_availablePresentations.isNotEmpty) {
      _selectedPresentation = _availablePresentations.first;
      _loadAveragePriceForPresentation(_selectedPresentation!);
    }
  }

  String _getPresentationName(Map<String, dynamic> presentation) {
    return presentation['denominacion'] ??
        presentation['presentacion'] ??
        presentation['nombre'] ??
        presentation['tipo'] ??
        'Sin nombre';
  }

  Future<void> _loadLastPurchasePrice() async {
    setState(() => _isLoadingLastPrice = true);
    try {
      final response = await Supabase.instance.client
          .from('app_dat_recepcion_productos')
          .select('precio_unitario, created_at')
          .eq('id_producto', widget.product.id)
          .order('created_at', ascending: false)
          .limit(1);

      if (response.isNotEmpty) {
        final lastRecord = response.first;
        final precioUnitario = lastRecord['precio_unitario'];
        if (precioUnitario != null) {
          setState(() {
            _lastPurchasePrice = (precioUnitario as num).toDouble();
            _lastPurchaseDate = lastRecord['created_at'];
            _precioUnitarioController.text = _lastPurchasePrice.toString();
          });
        } else {
          _setDefaultPrice();
        }
      } else {
        _setDefaultPrice();
      }
    } catch (e) {
      _setDefaultPrice();
    } finally {
      setState(() => _isLoadingLastPrice = false);
    }
  }

  Future<void> _loadAveragePriceForPresentation(
    Map<String, dynamic> presentation,
  ) async {
    if (presentation['id'] == null) return;

    setState(() => _isLoadingAveragePrice = true);
    try {
      final response = await Supabase.instance.client
          .from('app_dat_producto_presentacion')
          .select('precio_promedio')
          .eq('id', presentation['id'])
          .single();

      if (response != null) {
        final precioPromedio = response['precio_promedio'];
        if (precioPromedio != null) {
          setState(() {
            _averagePrice = (precioPromedio as num).toDouble();
          });
        } else {
          setState(() => _averagePrice = null);
        }
      }
    } catch (e) {
      print('Error loading average price: $e');
      setState(() => _averagePrice = null);
    } finally {
      setState(() => _isLoadingAveragePrice = false);
    }
  }

  void _setDefaultPrice() {
    setState(() {
      _lastPurchasePrice = null;
      _lastPurchaseDate = null;
      _precioUnitarioController.text = widget.product.basePrice.toString();
    });
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays == 0) return 'Hoy';
      if (difference.inDays == 1) return 'Ayer';
      if (difference.inDays < 7) return 'hace ${difference.inDays} días';
      if (difference.inDays < 30) {
        final weeks = (difference.inDays / 7).floor();
        return 'hace ${weeks} semana${weeks > 1 ? 's' : ''}';
      }
      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');
      final year = date.year;
      return '$day/$month/$year';
    } catch (e) {
      return 'Fecha inválida';
    }
  }

  void _submitForm() async {
    // ── Modo mixto: una linea por presentacion con cantidad ─────────────────
    if (_modoMixto) {
      await _submitMixto();
      return;
    }

    if (_formKey.currentState!.validate()) {
      if (!_validarLoteSiAplica()) return;

      final cantidad =
          double.tryParse(
            _quantityController.text.trim().replaceAll(',', '.'),
          ) ??
          0.0;
      final precioUnitario =
          double.tryParse(_precioUnitarioController.text) ?? 0;
      final precioConvertido = _finalPriceInUSD ?? precioUnitario;
      final precioReferencia =
          double.tryParse(_precioReferenciaController.text) ?? 0;
      final descuentoPorcentaje =
          double.tryParse(_descuentoPorcentajeController.text) ?? 0;
      final descuentoMonto =
          double.tryParse(_descuentoMontoController.text) ?? 0;
      final bonificacionCantidad =
          double.tryParse(_bonificacionCantidadController.text) ?? 0;
      // _finalCurrency nunca es null (arranca en 'USD' y el convertidor solo lo
      // reasigna), asi que el `??` de antes era codigo muerto.
      final monedaGuardar = _finalCurrency;

      try {
        final baseProductData = {
          'id_producto': widget.product.id,
          'precio_referencia': precioReferencia,
          'descuento_porcentaje': descuentoPorcentaje,
          'descuento_monto': descuentoMonto,
          'bonificacion_cantidad': bonificacionCantidad,
          'denominacion': widget.product.name,
          'sku_producto': widget.product.sku,
          'moneda_precio': monedaGuardar,
          ..._lotePayload(),
        };

        if (_selectedVariant != null) {
          baseProductData['id_variante'] = _selectedVariant!['id'];
          if (_selectedVariant!['opcion'] != null) {
            baseProductData['id_opcion_variante'] =
                _selectedVariant!['opcion']['id'];
          }
          baseProductData['variant_info'] = _selectedVariant!;
        }

        final productData =
            await PresentationConverter.processProductForReception(
              productId: widget.product.id,
              selectedPresentation: _selectedPresentation,
              cantidad: cantidad,
              precioUnitario: precioConvertido,
              baseProductData: baseProductData,
            );

        widget.onProductAdded(productData);
        if (mounted) Navigator.of(context).pop();
      } catch (e) {
        _mostrarError('Error al agregar producto: $e');
      }
    }
  }

  /// Emite UNA linea por presentacion con cantidad.
  ///
  /// FASE 2: es el punto donde "4 cajas + 4 unidades" deja de ser un solo
  /// registro aplanado y pasa a ser dos lineas, cada una con su
  /// `id_presentacion` y su precio. La pantalla de recepcion ya deduplica por
  /// `id_producto + id_presentacion`, asi que alcanza con llamar
  /// `onProductAdded` una vez por linea.
  Future<void> _submitMixto() async {
    if (_lineasMixtas.isEmpty) {
      _mostrarError('Escriba la cantidad de al menos una presentación');
      return;
    }

    if (!_validarLoteSiAplica()) return;

    // Todas las lineas necesitan precio: sin el, la recepcion entra con costo 0
    // y arruina el precio_promedio ponderado.
    final sinPrecio = _lineasMixtas
        .where((l) => (l.precioUnitario ?? 0) <= 0)
        .map((l) => l.presentacion.nombre)
        .toList();

    if (sinPrecio.isNotEmpty) {
      _mostrarError('Falta el precio de: ${sinPrecio.join(', ')}');
      return;
    }

    final precioReferencia =
        double.tryParse(_precioReferenciaController.text) ?? 0;
    final descuentoPorcentaje =
        double.tryParse(_descuentoPorcentajeController.text) ?? 0;
    final descuentoMonto = double.tryParse(_descuentoMontoController.text) ?? 0;
    final bonificacionCantidad =
        double.tryParse(_bonificacionCantidadController.text) ?? 0;
    final loteFields = _lotePayload();

    try {
      for (final linea in _lineasMixtas) {
        // Los precios se guardan siempre en USD (igual que el modo simple, que
        // delega esto en PriceCurrencyConverterWidget).
        final precioUSD = _aUSD(linea.precioUnitario!);

        final baseProductData = <String, dynamic>{
          'id_producto': widget.product.id,
          'precio_referencia': precioReferencia,
          // Los datos avanzados son de la operacion, no de la presentacion: se
          // aplican una sola vez, en la primera linea, para no duplicar
          // descuentos ni bonificaciones al partir en varias lineas.
          'descuento_porcentaje': linea == _lineasMixtas.first
              ? descuentoPorcentaje
              : 0,
          'descuento_monto': linea == _lineasMixtas.first ? descuentoMonto : 0,
          'bonificacion_cantidad': linea == _lineasMixtas.first
              ? bonificacionCantidad
              : 0,
          'denominacion': widget.product.name,
          'sku_producto': widget.product.sku,
          'moneda_precio': 'USD',
          ...loteFields,
        };

        if (_selectedVariant != null) {
          baseProductData['id_variante'] = _selectedVariant!['id'];
          if (_selectedVariant!['opcion'] != null) {
            baseProductData['id_opcion_variante'] =
                _selectedVariant!['opcion']['id'];
          }
          baseProductData['variant_info'] = _selectedVariant!;
        }

        final productData =
            await PresentationConverter.processProductForReception(
              productId: widget.product.id,
              selectedPresentation: linea.presentacion.toPresentationMap(),
              cantidad: linea.cantidad,
              precioUnitario: precioUSD,
              baseProductData: baseProductData,
            );

        widget.onProductAdded(productData);
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _mostrarError('Error al agregar producto: $e');
    }
  }

  /// Convierte a USD el precio escrito en la moneda de entrada del modo mixto.
  double _aUSD(double monto) {
    if (_monedaEntradaMixta == 'USD') return monto;
    if (_usdToCupRate != null && _usdToCupRate! > 0) {
      return monto / _usdToCupRate!;
    }
    // Sin tasa no se inventa una conversion: se guarda el valor tal cual y el
    // usuario ve el aviso en la UI.
    return monto;
  }

  void _mostrarError(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: AppColors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final narrow = media.size.width < 420;
    final compact = narrow || media.size.height < 700;
    final hPad = narrow ? 12.0 : 20.0;
    final vPad = compact ? 10.0 : 16.0;

    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: EdgeInsets.symmetric(
        horizontal: narrow ? 8 : 24,
        vertical: narrow ? 12 : 24,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: media.size.height * (narrow ? 0.94 : 0.88),
            minWidth: 0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: EdgeInsets.fromLTRB(hPad, vPad, 4, vPad),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    bottom: BorderSide(color: AppColors.border, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(compact ? 6 : 8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.add_shopping_cart,
                        color: AppColors.primary,
                        size: compact ? 20 : 24,
                      ),
                    ),
                    SizedBox(width: compact ? 8 : 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Agregar Producto',
                            style: TextStyle(
                              fontSize: narrow ? 15 : 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Factura en ${widget.invoiceCurrency}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.blue[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close, color: AppColors.textSecondary),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(hPad, vPad, hPad, vPad),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildProductInfo(compact: compact),
                        if (!_cargandoCadenaMixta &&
                            !_modoMixto &&
                            int.tryParse(widget.product.id) != null)
                          PresentacionEquivalenciaBanner(
                            productId: int.parse(widget.product.id),
                            productPresentaciones:
                                widget.product.presentaciones,
                            unidadMedida: widget.product.um,
                          ),
                        SizedBox(height: compact ? 14 : 20),
                        _buildInputSection(compact: compact),
                        SizedBox(height: compact ? 12 : 16),
                        if (_cargandoFlagLotes)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    'Verificando si requiere lote…',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else if (_requiereLote) ...[
                          _buildLoteSection(),
                          SizedBox(height: compact ? 12 : 16),
                        ],
                        if (!_modoMixto)
                          PriceCurrencyConverterWidget(
                            invoiceCurrency: widget.invoiceCurrency,
                            priceController: _precioUnitarioController,
                            onPriceConverted: (convertedPrice, currency) {
                              print(
                                '💱 Precio convertido a USD: $convertedPrice',
                              );
                              setState(() {
                                _finalPriceInUSD = convertedPrice;
                                _finalCurrency = currency;
                              });
                            },
                          ),
                        SizedBox(height: compact ? 14 : 20),
                        _buildAdvancedOptions(compact: compact),
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.fromLTRB(hPad, 10, hPad, hPad),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: AppColors.border, width: 1),
                  ),
                ),
                child: narrow
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ElevatedButton(
                            onPressed: _submitForm,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              'Agregar',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(
                              'Cancelar',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: Text(
                                'Cancelar',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              onPressed: _submitForm,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text(
                                'Agregar',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductInfo({bool compact = false}) {
    final iconSize = compact ? 40.0 : 60.0;
    return Container(
      padding: EdgeInsets.all(compact ? 10 : 16),
      decoration: BoxDecoration(
        color: AppColors.surface.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: iconSize,
            height: iconSize,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.inventory_2,
              color: AppColors.primary,
              size: compact ? 22 : 30,
            ),
          ),
          SizedBox(width: compact ? 10 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.product.name,
                  style: TextStyle(
                    fontSize: compact ? 14 : 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (widget.product.sku.isNotEmpty)
                  Text(
                    'SKU: ${widget.product.sku}',
                    style: TextStyle(
                      fontSize: compact ? 12 : 14,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Dropdown de variante. Extraido para reusarlo en los dos modos.
  Widget _buildVariantDropdown() {
    return DropdownButtonFormField<Map<String, dynamic>>(
      value: _selectedVariant,
      decoration: InputDecoration(
        labelText: 'Variante',
        border: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      isExpanded: true,
      items: [
        DropdownMenuItem<Map<String, dynamic>>(
          value: null,
          child: Text(
            'Sin variante',
            style: TextStyle(color: AppColors.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        ..._availableVariants.map((variant) {
          final atributo =
              variant['atributo']?['denominacion'] ??
              variant['atributo']?['label'] ??
              '';
          final opcion = variant['opcion']?['valor'] ?? '';
          return DropdownMenuItem<Map<String, dynamic>>(
            value: variant,
            child: Text(
              '$atributo - $opcion',
              style: TextStyle(color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),
      ],
      onChanged: (value) => setState(() => _selectedVariant = value),
    );
  }

  /// Alterna entre captura mixta y captura de una sola presentacion.
  ///
  /// El modo simple se conserva porque para entrar 10 cajas y nada mas, el mixto
  /// es un formulario mas grande sin beneficio. Cambiar de modo descarta lo
  /// escrito en el otro, asi que se avisa.
  Widget _buildSelectorModo({bool compact = false}) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<bool>(
        segments: [
          ButtonSegment<bool>(
            value: false,
            icon: const Icon(Icons.looks_one, size: 17),
            label: Text(compact ? 'Una' : 'Una presentación'),
          ),
          ButtonSegment<bool>(
            value: true,
            icon: const Icon(Icons.view_list, size: 17),
            label: Text(compact ? 'Varias' : 'Varias presentaciones'),
          ),
        ],
        selected: {_modoMixto},
        showSelectedIcon: false,
        style: compact
            ? ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: WidgetStateProperty.all(
                  const TextStyle(fontSize: 12),
                ),
              )
            : null,
        onSelectionChanged: (seleccion) {
          setState(() {
            _modoMixto = seleccion.first;
            // Al salir del mixto se descartan las lineas: dejarlas guardaria
            // cantidades que el formulario simple ya no muestra.
            _lineasMixtas = [];
          });
        },
      ),
    );
  }

  /// Moneda en la que se escriben los precios del modo mixto.
  ///
  /// El modo simple usa PriceCurrencyConverterWidget, que maneja UN precio. Con
  /// N precios ese widget no sirve, asi que la eleccion de moneda se hace una
  /// vez para todas las filas y la conversion la hace _aUSD.
  Widget _buildSelectorMonedaMixta({bool compact = false}) {
    final sinTasa =
        _monedaEntradaMixta == 'CUP' &&
        (_usdToCupRate == null || _usdToCupRate! <= 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'Precios en:',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            ...['USD', 'CUP'].map(
              (m) => ChoiceChip(
                label: Text(m, style: const TextStyle(fontSize: 12)),
                selected: _monedaEntradaMixta == m,
                visualDensity: compact ? VisualDensity.compact : null,
                onSelected: (_) => setState(() => _monedaEntradaMixta = m),
              ),
            ),
            if (_monedaEntradaMixta == 'CUP' &&
                _usdToCupRate != null &&
                _usdToCupRate! > 0)
              Text(
                '1 USD = ${_usdToCupRate!.toStringAsFixed(2)} CUP',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
          ],
        ),
        if (sinTasa)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'No se pudo leer la tasa USD→CUP: los precios se guardarían sin '
              'convertir. Use USD o reintente.',
              style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
            ),
          ),
      ],
    );
  }

  Widget _buildLoteSection() {
    final fecha = _fechaVencimiento;
    final fechaLabel = fecha == null
        ? 'Seleccionar fecha'
        : '${fecha.day.toString().padLeft(2, '0')}/'
            '${fecha.month.toString().padLeft(2, '0')}/'
            '${fecha.year}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Lote y vencimiento',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Obligatorio: este producto está marcado como “por lotes”.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _codigoLoteController,
            decoration: const InputDecoration(
              labelText: 'Código de lote',
              hintText: 'Ej. Lote proveedor / interno',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate:
                    _fechaVencimiento ??
                    DateTime.now().add(const Duration(days: 30)),
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
                helpText: 'Fecha de vencimiento',
              );
              if (picked != null && mounted) {
                setState(() => _fechaVencimiento = picked);
              }
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Fecha de vencimiento',
                border: OutlineInputBorder(),
                isDense: true,
                suffixIcon: Icon(Icons.calendar_today, size: 18),
              ),
              child: Text(
                fechaLabel,
                style: TextStyle(
                  color: fecha == null
                      ? AppColors.textSecondary
                      : AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputSection({bool compact = false}) {
    if (_cargandoCadenaMixta) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(strokeWidth: 2),
              SizedBox(height: 10),
              Text(
                'Cargando presentaciones...',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    if (_modoMixto) {
      // El modo mixto solo se activa cuando la cadena vino de la RPC, y para eso
      // el id ya tuvo que parsearse bien en _cargarCadenaMixta.
      final idProducto = int.parse(widget.product.id);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSelectorModo(compact: compact),
          const SizedBox(height: 12),

          // Variante primero: cambia el saldo que se muestra por presentacion.
          if (_availableVariants.isNotEmpty) ...[
            _buildVariantDropdown(),
            const SizedBox(height: 16),
          ],

          _buildSelectorMonedaMixta(compact: compact),
          const SizedBox(height: 12),

          CantidadMixtaInput(
            // La key fuerza a reconstruir el estado interno cuando cambia la
            // moneda: los precios ya escritos estaban en la moneda anterior y
            // dejarlos seria cambiarles el significado en silencio.
            key: ValueKey('mixto_${idProducto}_$_monedaEntradaMixta'),
            idProducto: idProducto,
            capturarPrecio: true,
            monedaLabel: _monedaEntradaMixta,
            precioSugeridoBase: _lastPurchasePrice,
            onChanged: (lineas) => setState(() => _lineasMixtas = lineas),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_cadena.length > 1) ...[
          _buildSelectorModo(compact: compact),
          const SizedBox(height: 12),
        ],

        // Presentation Selection
        if (_availablePresentations.isNotEmpty) ...[
          DropdownButtonFormField<Map<String, dynamic>>(
            value: _selectedPresentation,
            decoration: InputDecoration(
              labelText: 'Presentación',
              border: OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: AppColors.primary, width: 2),
              ),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            isExpanded: true,
            items: [
              DropdownMenuItem<Map<String, dynamic>>(
                value: null,
                child: Text(
                  'Sin presentación específica',
                  style: TextStyle(color: AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ..._availablePresentations.map((presentation) {
                return DropdownMenuItem<Map<String, dynamic>>(
                  value: presentation,
                  child: Text(
                    _getPresentationName(presentation),
                    style: TextStyle(color: AppColors.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
            ],
            onChanged: (value) {
              setState(() => _selectedPresentation = value);
              if (value != null) {
                _loadAveragePriceForPresentation(value);
              }
            },
          ),
          SizedBox(height: 16),
        ],

        // Variant Selection
        if (_availableVariants.isNotEmpty) ...[
          _buildVariantDropdown(),
          SizedBox(height: 16),
        ],

        // Quantity
        TextFormField(
          controller: _quantityController,
          decoration: InputDecoration(
            labelText: 'Cantidad',
            border: OutlineInputBorder(
              borderSide: BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: AppColors.primary, width: 2),
            ),
            prefixIcon: Icon(Icons.inventory, color: AppColors.primary),
          ),
          keyboardType: TextInputType.numberWithOptions(decimal: true),
          validator: (value) {
            if (value == null || value.isEmpty)
              return 'La cantidad es obligatoria';
            final cantidad = double.tryParse(value.trim().replaceAll(',', '.'));
            if (cantidad == null || cantidad <= 0) {
              return 'Ingrese una cantidad válida';
            }
            return null;
          },
        ),
        SizedBox(height: 16),

        // Purchase Price
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _precioUnitarioController,
              decoration: InputDecoration(
                labelText: compact
                    ? 'Precio de compra'
                    : 'Precio de Compra (por presentación seleccionada)',
                hintText: compact
                    ? 'A ${widget.invoiceCurrency}'
                    : 'Se convertirá automáticamente a ${widget.invoiceCurrency}',
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.primary, width: 2),
                ),
                prefixIcon: _isLoadingLastPrice
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        ),
                      )
                    : Icon(Icons.attach_money, color: AppColors.primary),
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              validator: (value) {
                if (value == null || value.isEmpty)
                  return 'El precio de compra es obligatorio';
                return null;
              },
            ),
            if (_lastPurchaseDate != null && !_isLoadingLastPrice)
              Padding(
                padding: EdgeInsets.only(top: 8, left: 12),
                child: Row(
                  children: [
                    Icon(Icons.history, size: 16, color: AppColors.success),
                    SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Último precio: ${_formatDate(_lastPurchaseDate!)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.success,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            if (_isLoadingAveragePrice)
              Padding(
                padding: EdgeInsets.only(top: 8, left: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    ),
                    SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Cargando precio promedio...',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            if (_averagePrice != null && !_isLoadingAveragePrice)
              Padding(
                padding: EdgeInsets.only(top: 8, left: 12),
                child: Row(
                  children: [
                    Icon(Icons.trending_down, size: 16, color: Colors.orange),
                    SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Precio promedio: \$${_averagePrice!.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildAdvancedOptions({bool compact = false}) {
    final discounts = [
      TextFormField(
        controller: _descuentoPorcentajeController,
        decoration: InputDecoration(
          labelText: 'Descuento %',
          border: OutlineInputBorder(
            borderSide: BorderSide(color: AppColors.warning),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: AppColors.warning),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: AppColors.warning, width: 2),
          ),
          prefixIcon: Icon(Icons.percent, color: AppColors.warning),
          isDense: compact,
        ),
        keyboardType: TextInputType.numberWithOptions(decimal: true),
      ),
      TextFormField(
        controller: _descuentoMontoController,
        decoration: InputDecoration(
          labelText: 'Descuento \$',
          prefixText: '\$ ',
          border: OutlineInputBorder(
            borderSide: BorderSide(color: AppColors.warning),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: AppColors.warning),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: AppColors.warning, width: 2),
          ),
          prefixIcon: Icon(Icons.money_off, color: AppColors.warning),
          isDense: compact,
        ),
        keyboardType: TextInputType.numberWithOptions(decimal: true),
      ),
    ];

    return ExpansionTile(
      title: Text(
        compact ? 'Datos avanzados' : 'Datos Avanzados de Recepción',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
      childrenPadding: EdgeInsets.fromLTRB(
        compact ? 8 : 16,
        0,
        compact ? 8 : 16,
        12,
      ),
      children: [
        SizedBox(height: 12),
        TextFormField(
          controller: _precioReferenciaController,
          decoration: InputDecoration(
            labelText: compact
                ? 'Precio referencia (opc.)'
                : 'Precio de Referencia (Opcional)',
            prefixText: '\$ ',
            border: OutlineInputBorder(
              borderSide: BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: AppColors.primary, width: 2),
            ),
            prefixIcon: Icon(Icons.price_check, color: AppColors.textSecondary),
            isDense: compact,
          ),
          keyboardType: TextInputType.numberWithOptions(decimal: true),
        ),
        SizedBox(height: 16),
        if (compact)
          Column(
            children: [
              discounts[0],
              const SizedBox(height: 12),
              discounts[1],
            ],
          )
        else
          Row(
            children: [
              Expanded(child: discounts[0]),
              SizedBox(width: 12),
              Expanded(child: discounts[1]),
            ],
          ),
        SizedBox(height: 16),
        TextFormField(
          controller: _bonificacionCantidadController,
          decoration: InputDecoration(
            labelText: compact
                ? 'Bonificación (extra)'
                : 'Bonificación (Cantidad Extra)',
            border: OutlineInputBorder(
              borderSide: BorderSide(color: AppColors.success),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: AppColors.success),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: AppColors.success, width: 2),
            ),
            prefixIcon: Icon(
              Icons.add_circle_outline,
              color: AppColors.success,
            ),
            isDense: compact,
          ),
          keyboardType: TextInputType.numberWithOptions(decimal: true),
        ),
      ],
    );
  }
}
