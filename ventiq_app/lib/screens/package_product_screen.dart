import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../models/payment_method.dart' as pm;
import '../models/product.dart';
import '../services/currency_service.dart';
import '../services/geonames_service.dart';
import '../services/paqueteria_service.dart';
import '../services/payment_method_service.dart';
import '../services/product_detail_service.dart';
import '../services/promotion_service.dart';
import '../services/turno_service.dart';
import '../services/user_preferences_service.dart';
import '../utils/promotion_rules.dart';

/// Pantalla dedicada a productos marcados como "paquete".
/// Muestra detalle del producto, precio con promociones (producto y global),
/// selector de cantidad (sin chequeo de stock, solo > 0) y, tras "Siguiente",
/// un formulario con datos de remitente y destinatario para crear la orden.
class PackageProductScreen extends StatefulWidget {
  final Product product;
  final Color categoryColor;

  const PackageProductScreen({
    Key? key,
    required this.product,
    required this.categoryColor,
  }) : super(key: key);

  @override
  State<PackageProductScreen> createState() => _PackageProductScreenState();
}

class _PackageProductScreenState extends State<PackageProductScreen> {
  final ProductDetailService _productDetailService = ProductDetailService();
  final PromotionService _promotionService = PromotionService();
  final UserPreferencesService _userPreferences = UserPreferencesService();
  final PaqueteriaService _paqueteriaService = PaqueteriaService();

  double _quantity = 1.0;
  final TextEditingController _quantityCtrl = TextEditingController(text: '1');
  bool _isLoading = true;
  bool _checkingShift = true;
  bool _hasOpenShift = false;
  Product? _detailedProduct;

  double _unitPrice = 0;
  double _usdRate = 0.0;

  // Datos crudos de promociones (igual que product_details_screen / preorder)
  List<Map<String, dynamic>>? _productPromotions;
  Map<String, dynamic>? _globalPromotion;

  // Promo activa según método de pago + cantidad seleccionada
  Map<String, dynamic>? _activePromotion;
  double? _discountedPrice; // precio unitario tras aplicar la promo activa

  // Métodos de pago disponibles (para mapear nombre -> id)
  List<pm.PaymentMethod> _paymentMethods = [];

  bool _showShipmentForm = false;
  final _formKey = GlobalKey<FormState>();

  // Datos del paquete (paso 1)
  final _numeroPaqueteCtrl = TextEditingController();
  final _descPaqueteCtrl = TextEditingController();
  String? _metodoPago; // 'Efectivo' | 'Transferencia'
  Uint8List? _packagePhotoBytes;
  String? _packagePhotoName;
  final ImagePicker _imagePicker = ImagePicker();

  bool _isSubmitting = false;

  // Remitente (usa GeoNames: país / estado / ciudad)
  final _sTelefonoCtrl = TextEditingController();
  final _sDireccionCtrl = TextEditingController();
  final _sNombreCtrl = TextEditingController();
  List<Map<String, dynamic>> _sCountries = [];
  List<Map<String, dynamic>> _sStates = [];
  List<Map<String, dynamic>> _sCities = [];
  Map<String, dynamic>? _sSelectedCountry;
  Map<String, dynamic>? _sSelectedState;
  Map<String, dynamic>? _sSelectedCity;
  bool _sLoadingCountries = false;
  bool _sLoadingStates = false;
  bool _sLoadingCities = false;

  // Destinatario (usa GeoNames: país / estado / ciudad)
  final _dTelefonoCtrl = TextEditingController();
  final _dDireccionCtrl = TextEditingController();
  final _dNombreCtrl = TextEditingController();
  List<Map<String, dynamic>> _dStates = [];
  List<Map<String, dynamic>> _dCities = [];
  Map<String, dynamic>? _dSelectedCountry;
  Map<String, dynamic>? _dSelectedState;
  Map<String, dynamic>? _dSelectedCity;
  bool _dLoadingStates = false;
  bool _dLoadingCities = false;

  static const Color _primary = Color(0xFF194B8C);
  static const String _fallbackAsset = 'assets/package.jpg';

  @override
  void initState() {
    super.initState();
    _unitPrice = widget.product.precio;
    _numeroPaqueteCtrl.text = _generatePackageNumber();
    _checkOpenShift();
    _loadData();
  }

  String _generatePackageNumber() {
    final rnd = Random();
    final n = rnd.nextInt(1000000); // 0..999999
    return 'P-${n.toString().padLeft(6, '0')}';
  }

  Future<void> _checkOpenShift() async {
    try {
      setState(() => _checkingShift = true);
      final hasShift = await TurnoService.hasOpenShift();
      if (!mounted) return;
      setState(() {
        _hasOpenShift = hasShift;
        _checkingShift = false;
      });
      if (!hasShift) _showNoShiftDialog();
    } catch (e) {
      debugPrint('❌ Error checking shift: $e');
      if (!mounted) return;
      setState(() {
        _hasOpenShift = false;
        _checkingShift = false;
      });
      _showNoShiftDialog();
    }
  }

  void _showNoShiftDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            const SizedBox(width: 8),
            const Text('Turno Requerido'),
          ],
        ),
        content: const Text(
          'Debe tener un turno abierto para enviar un paquete. Por favor, vaya a la sección de Apertura para abrir un turno.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushReplacementNamed(context, '/apertura');
            },
            style: ElevatedButton.styleFrom(backgroundColor: _primary),
            child: const Text('Ir a Apertura'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Volver'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _sTelefonoCtrl.dispose();
    _sDireccionCtrl.dispose();
    _sNombreCtrl.dispose();
    _dTelefonoCtrl.dispose();
    _dDireccionCtrl.dispose();
    _dNombreCtrl.dispose();
    _numeroPaqueteCtrl.dispose();
    _descPaqueteCtrl.dispose();
    _quantityCtrl.dispose();
    super.dispose();
  }

  // ───────────────── GEONAMES (REMITENTE) ─────────────────

  Future<void> _loadSenderCountries() async {
    print('🌍 [GEO] → Solicitando países a GeoNames...');
    setState(() => _sLoadingCountries = true);
    try {
      final countries = await GeonamesService.getCountries();
      print('🌍 [GEO] ✓ Países recibidos: ${countries.length}');
      if (countries.isNotEmpty) {
        print('🌍 [GEO]   primer país: ${countries.first}');
      }
      if (!mounted) return;
      setState(() {
        _sCountries = countries;
        _sLoadingCountries = false;
      });
    } catch (e, st) {
      print('❌ [GEO] Error cargando países: $e');
      print('❌ [GEO] Stack: $st');
      if (!mounted) return;
      setState(() => _sLoadingCountries = false);
    }
  }

  Future<void> _loadSenderStates(String countryCode) async {
    print('🗺️ [GEO] → Solicitando estados (remitente) para countryCode=$countryCode');
    setState(() {
      _sLoadingStates = true;
      _sStates = [];
      _sSelectedState = null;
      _sCities = [];
      _sSelectedCity = null;
    });
    try {
      final states = await GeonamesService.getStates(countryCode);
      print('🗺️ [GEO] ✓ Estados recibidos (remitente): ${states.length}');
      if (states.isNotEmpty) {
        print('🗺️ [GEO]   primer estado: ${states.first}');
      }
      if (!mounted) return;
      setState(() {
        _sStates = states;
        _sLoadingStates = false;
      });
    } catch (e, st) {
      print('❌ [GEO] Error cargando estados (remitente): $e');
      print('❌ [GEO] Stack: $st');
      if (!mounted) return;
      setState(() => _sLoadingStates = false);
    }
  }

  Future<void> _loadSenderCities(String countryCode, String adminCode) async {
    print('🏙️ [GEO] → Solicitando ciudades (remitente) country=$countryCode admin=$adminCode');
    setState(() {
      _sLoadingCities = true;
      _sCities = [];
      _sSelectedCity = null;
    });
    try {
      final cities = await GeonamesService.getCities(countryCode, adminCode);
      print('🏙️ [GEO] ✓ Ciudades recibidas (remitente): ${cities.length}');
      if (cities.isNotEmpty) {
        print('🏙️ [GEO]   primera ciudad: ${cities.first}');
      }
      if (!mounted) return;
      setState(() {
        _sCities = cities;
        _sLoadingCities = false;
      });
    } catch (e, st) {
      print('❌ [GEO] Error cargando ciudades (remitente): $e');
      print('❌ [GEO] Stack: $st');
      if (!mounted) return;
      setState(() => _sLoadingCities = false);
    }
  }

  // ───────────────── GEONAMES (DESTINATARIO) ─────────────────

  Future<void> _loadReceiverStates(String countryCode) async {
    print('🗺️ [GEO] → Solicitando estados (destinatario) para countryCode=$countryCode');
    setState(() {
      _dLoadingStates = true;
      _dStates = [];
      _dSelectedState = null;
      _dCities = [];
      _dSelectedCity = null;
    });
    try {
      final states = await GeonamesService.getStates(countryCode);
      print('🗺️ [GEO] ✓ Estados recibidos (destinatario): ${states.length}');
      if (states.isNotEmpty) {
        print('🗺️ [GEO]   primer estado: ${states.first}');
      }
      if (!mounted) return;
      setState(() {
        _dStates = states;
        _dLoadingStates = false;
      });
    } catch (e, st) {
      print('❌ [GEO] Error cargando estados (destinatario): $e');
      print('❌ [GEO] Stack: $st');
      if (!mounted) return;
      setState(() => _dLoadingStates = false);
    }
  }

  Future<void> _loadReceiverCities(String countryCode, String adminCode) async {
    print('🏙️ [GEO] → Solicitando ciudades (destinatario) country=$countryCode admin=$adminCode');
    setState(() {
      _dLoadingCities = true;
      _dCities = [];
      _dSelectedCity = null;
    });
    try {
      final cities = await GeonamesService.getCities(countryCode, adminCode);
      print('🏙️ [GEO] ✓ Ciudades recibidas (destinatario): ${cities.length}');
      if (cities.isNotEmpty) {
        print('🏙️ [GEO]   primera ciudad: ${cities.first}');
      }
      if (!mounted) return;
      setState(() {
        _dCities = cities;
        _dLoadingCities = false;
      });
    } catch (e, st) {
      print('❌ [GEO] Error cargando ciudades (destinatario): $e');
      print('❌ [GEO] Stack: $st');
      if (!mounted) return;
      setState(() => _dLoadingCities = false);
    }
  }

  Future<void> _loadData() async {
    try {
      // Cargar países (GeoNames) en paralelo con el detalle del producto.
      // Tanto remitente como destinatario usan el mismo catálogo de países.
      final countriesFuture = _loadSenderCountries();

      // Cargar tasa USD en paralelo
      try {
        _usdRate = await CurrencyService.getUsdRate();
      } catch (e) {
        debugPrint('⚠️ Error cargando tasa USD: $e');
        _usdRate = 420.0;
      }

      final detailed = await _productDetailService.getProductDetail(
        widget.product.id,
      );
      _detailedProduct = detailed;
      if (detailed.precio > 0) _unitPrice = detailed.precio;

      await countriesFuture;

      // Métodos de pago disponibles (para resolver el id de Efectivo/Transferencia)
      try {
        _paymentMethods = await PaymentMethodService.getActivePaymentMethods();
      } catch (e) {
        debugPrint('⚠️ Error cargando métodos de pago: $e');
      }

      // Promociones específicas del producto
      try {
        final productPromos = await _promotionService.getProductPromotions(
          widget.product.id,
        );
        if (productPromos.isNotEmpty) {
          _productPromotions = productPromos;
        }
      } catch (_) {}

      // Promoción global
      try {
        final idTienda = await _userPreferences.getIdTienda();
        if (idTienda != null) {
          _globalPromotion = await _promotionService.getGlobalPromotion(
            idTienda,
          );
        }
      } catch (_) {}

      _recalcPrices();
    } catch (e) {
      debugPrint('❌ Error cargando datos del paquete: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Resuelve el id de método de pago a partir del label seleccionado
  /// ('Efectivo' / 'Transferencia'). Si no se encuentra, retorna null.
  int? get _selectedPaymentMethodId {
    if (_metodoPago == null) return null;
    if (_paymentMethods.isEmpty) {
      // Fallback: 1 = Efectivo (convención del backend); para Transferencia
      // sin catálogo cargado devolvemos null para que las promos que requieran
      // medio de pago no apliquen incorrectamente.
      return _metodoPago == 'Efectivo' ? 1 : null;
    }
    if (_metodoPago == 'Efectivo') {
      final efectivo = _paymentMethods.firstWhere(
        (m) => m.esEfectivo,
        orElse: () => _paymentMethods.first,
      );
      return efectivo.id;
    }
    // Transferencia / otros: tomar el primer método NO efectivo cuyo nombre
    // contenga "transfer" o el primer no-efectivo disponible.
    final transferencia = _paymentMethods.firstWhere(
      (m) => !m.esEfectivo && m.denominacion.toLowerCase().contains('transfer'),
      orElse:
          () => _paymentMethods.firstWhere(
            (m) => !m.esEfectivo,
            orElse: () => _paymentMethods.first,
          ),
    );
    return transferencia.id;
  }

  /// Recalcula la promoción activa y el precio con descuento
  /// según la cantidad y el método de pago seleccionados.
  void _recalcPrices() {
    final paymentId = _selectedPaymentMethodId;

    // Si aún no se eligió método de pago, usar la promo "para display"
    // (sin filtrar por medio de pago) para mostrar el descuento potencial.
    final qtyInt = _quantity.ceil();
    final promo =
        paymentId == null
            ? PromotionRules.pickPromotionForDisplay(
              productPromotions: _productPromotions,
              globalPromotion: _globalPromotion,
              quantity: qtyInt,
            )
            : PromotionRules.pickPromotionForPayment(
              productPromotions: _productPromotions,
              globalPromotion: _globalPromotion,
              paymentMethodId: paymentId,
              quantity: qtyInt,
            );

    if (promo == null) {
      _activePromotion = null;
      _discountedPrice = null;
      return;
    }

    final basePrice = PromotionRules.resolveBasePrice(
      unitPrice: _unitPrice,
      basePrice: _unitPrice,
      promotion: promo,
    );
    final prices = PromotionRules.calculatePromotionPrices(
      basePrice: basePrice,
      promotion: promo,
    );
    final precioFinal = PromotionRules.selectPriceForPayment(
      prices: prices,
      paymentMethodId: paymentId,
      promotion: promo,
    );

    _activePromotion = promo;
    _discountedPrice = precioFinal != _unitPrice ? precioFinal : null;
  }

  double get _effectiveUnitPrice => _discountedPrice ?? _unitPrice;
  double get _total => _effectiveUnitPrice * _quantity;
  bool get _hasActivePromo =>
      _activePromotion != null && _discountedPrice != null;
  bool get _hasSurcharge =>
      _hasActivePromo &&
      PromotionRules.isRecargoPromotionType(_activePromotion!);
  bool get _hasDiscount => _hasActivePromo && !_hasSurcharge;
  int? get _activePromoTipoDescuento =>
      _activePromotion == null
          ? null
          : PromotionRules.resolvePromotionDiscountType(_activePromotion!);
  String? get _activePromoName => _activePromotion?['nombre'] as String?;
  double? get _activePromoValor =>
      (_activePromotion?['valor_descuento'] as num?)?.toDouble();

  bool _isWide(BuildContext context) =>
      kIsWeb && MediaQuery.of(context).size.width >= 900;

  @override
  Widget build(BuildContext context) {
    if (_checkingShift) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_hasOpenShift) {
      return const Scaffold(
        body: Center(child: Text('No tiene un turno abierto')),
      );
    }

    final isWide = _isWide(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        elevation: 0,
        title: Text(
          _showShipmentForm ? 'Datos de envío' : 'Detalle del paquete',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: _primary,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_showShipmentForm) {
              setState(() => _showShipmentForm = false);
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: isWide ? 1400 : 720),
                  child:
                      _showShipmentForm
                          ? _buildShipmentForm(isWide)
                          : _buildProductView(isWide),
                ),
              ),
    );
  }

  // ───────────────────────── PRODUCT VIEW ─────────────────────────

  Widget _buildProductView(bool isWide) {
    final product = _detailedProduct ?? widget.product;

    if (isWide) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 5, child: _buildLeftColumnWeb(product)),
            const SizedBox(width: 24),
            Expanded(flex: 6, child: _buildRightColumnWeb(product)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildImage(product, compact: true),
          const SizedBox(height: 10),
          _buildProductInfo(product, isWide),
        ],
      ),
    );
  }

  Widget _buildLeftColumnWeb(Product product) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildImage(product),
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip('Paquete', Icons.card_giftcard_outlined, _primary),
              if (product.categoria.isNotEmpty)
                _chip(
                  product.categoria,
                  Icons.category_outlined,
                  Colors.blueGrey,
                ),
              if (product.sku != null && product.sku!.isNotEmpty)
                _chip('SKU: ${product.sku}', Icons.qr_code_2, Colors.grey),
            ],
          ),
          if (product.descripcion != null &&
              product.descripcion!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              product.descripcion!,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRightColumnWeb(Product product) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          product.denominacion,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 14),
        if (_hasActivePromo) ...[
          _buildPromotionCard(),
          const SizedBox(height: 12),
        ],
        _buildPriceCard(),
        const SizedBox(height: 12),
        _buildQuantityCard(),
        const SizedBox(height: 12),
        _buildPackageInfoCard(),
        const SizedBox(height: 12),
        _buildPaymentMethodCard(),
        const SizedBox(height: 12),
        _buildTotalCard(),
        const SizedBox(height: 16),
        _buildSiguienteButton(),
      ],
    );
  }

  Widget _buildSiguienteButton() {
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        onPressed: _quantity <= 0 ? null : _onSiguienteFromDetail,
        icon: const Icon(Icons.arrow_forward_rounded),
        label: const Text(
          'Siguiente',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildImage(Product product, {bool compact = false}) {
    final aspect = compact ? 21 / 9 : 4 / 3;
    final maxHeight = compact ? 140.0 : double.infinity;
    return Hero(
      tag: 'package_${product.id}',
      child: Material(
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: AspectRatio(
              aspectRatio: aspect,
              child: Container(color: Colors.white, child: _fallbackImage()),
            ),
          ),
        ),
      ),
    );
  }

  Widget _fallbackImage() {
    return Image.asset(
      _fallbackAsset,
      fit: BoxFit.cover,
      errorBuilder:
          (_, __, ___) => Container(
            color: Colors.grey.shade100,
            child: Icon(
              Icons.inventory_2_rounded,
              size: 80,
              color: Colors.grey.shade400,
            ),
          ),
    );
  }

  Widget _buildProductInfo(Product product, bool isWide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _chip('Paquete', Icons.card_giftcard_outlined, _primary),
            if (product.categoria.isNotEmpty)
              _chip(
                product.categoria,
                Icons.category_outlined,
                Colors.blueGrey,
              ),
            if (product.sku != null && product.sku!.isNotEmpty)
              _chip('SKU: ${product.sku}', Icons.qr_code_2, Colors.grey),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          product.denominacion,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            height: 1.2,
          ),
        ),
        if (product.descripcion != null &&
            product.descripcion!.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            product.descripcion!,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 12.5,
              height: 1.35,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 10),
        if (_hasActivePromo) ...[
          _buildPromotionCard(),
          const SizedBox(height: 10),
        ],
        _buildPriceCard(),
        const SizedBox(height: 10),
        _buildQuantityCard(),
        const SizedBox(height: 10),
        _buildPackageInfoCard(),
        const SizedBox(height: 10),
        _buildPaymentMethodCard(),
        const SizedBox(height: 10),
        _buildTotalCard(),
        const SizedBox(height: 14),
        _buildSiguienteButton(),
      ],
    );
  }

  void _onSiguienteFromDetail() {
    final missing = <String>[];
    if (_numeroPaqueteCtrl.text.trim().isEmpty) {
      _numeroPaqueteCtrl.text = _generatePackageNumber();
    }
    if (_quantity <= 0) missing.add('cantidad de libras');
    if (_descPaqueteCtrl.text.trim().isEmpty) missing.add('descripción');
    if (_metodoPago == null) missing.add('método de pago');

    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.orange.shade700,
          content: Text('Completa: ${missing.join(', ')}'),
        ),
      );
      return;
    }
    setState(() => _showShipmentForm = true);
  }

  Widget _buildPackageInfoCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  color: _primary,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Información del paquete',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _numeroPaqueteCtrl,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Número de paquete (auto-generado)',
              hintText: 'P-XXXXXX',
              labelStyle: const TextStyle(fontSize: 13),
              prefixIcon: const Icon(Icons.tag, size: 18),
              suffixIcon: IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: 'Generar nuevo número',
                onPressed: () => setState(() {
                  _numeroPaqueteCtrl.text = _generatePackageNumber();
                }),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _descPaqueteCtrl,
            minLines: 2,
            maxLines: 3,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Descripción',
              labelStyle: const TextStyle(fontSize: 13),
              alignLabelWithHint: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
            ),
          ),
          const SizedBox(height: 10),
          _buildPhotoPicker(),
        ],
      ),
    );
  }

  Widget _buildPhotoPicker() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        InkWell(
          onTap: _pickPackagePhoto,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            clipBehavior: Clip.antiAlias,
            child:
                _packagePhotoBytes != null
                    ? Image.memory(_packagePhotoBytes!, fit: BoxFit.cover)
                    : Icon(
                      Icons.add_a_photo_outlined,
                      color: Colors.grey.shade500,
                      size: 22,
                    ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Foto (opcional)',
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickPackagePhoto,
                      icon: const Icon(Icons.add_a_photo_outlined, size: 14),
                      label: Text(
                        _packagePhotoBytes == null ? 'Elegir' : 'Cambiar',
                        style: const TextStyle(fontSize: 12),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _primary,
                        side: const BorderSide(color: _primary),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 6,
                        ),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                  if (_packagePhotoBytes != null) ...[
                    const SizedBox(width: 4),
                    InkWell(
                      onTap:
                          () => setState(() {
                            _packagePhotoBytes = null;
                            _packagePhotoName = null;
                          }),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          Icons.close,
                          size: 18,
                          color: Colors.red.shade600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickPackagePhoto() async {
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: _primary),
              title: const Text('Tomar foto con la cámara'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: _primary),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (source == null) return;

    try {
      final XFile? picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1400,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      setState(() {
        _packagePhotoBytes = bytes;
        _packagePhotoName = picked.name;
      });
    } catch (e) {
      debugPrint('❌ Error eligiendo foto: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo abrir la cámara/galería: $e'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }

  Widget _buildPaymentMethodCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.payments_outlined,
                  color: _primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Método de pago',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _paymentOption(
                  label: 'Efectivo',
                  icon: Icons.attach_money_rounded,
                  value: 'Efectivo',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _paymentOption(
                  label: 'Transferencia',
                  icon: Icons.account_balance_outlined,
                  value: 'Transferencia',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _paymentOption({
    required String label,
    required IconData icon,
    required String value,
  }) {
    final selected = _metodoPago == value;
    return InkWell(
      onTap:
          () => setState(() {
            _metodoPago = value;
            _recalcPrices();
          }),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? _primary.withOpacity(0.1) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? _primary : Colors.grey.shade300,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: selected ? _primary : Colors.grey.shade600,
              size: 24,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? _primary : Colors.grey.shade800,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String text, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromotionCard() {
    final valor = _activePromoValor;
    final tipo = _activePromoTipoDescuento;
    if (valor == null || tipo == null) return const SizedBox.shrink();

    final isSurcharge = _hasSurcharge;
    final accent = isSurcharge ? Colors.orange.shade700 : Colors.red.shade600;
    final bg = isSurcharge ? Colors.orange.shade50 : Colors.red.shade50;
    final prefix = isSurcharge ? '+' : '-';
    // tipo_descuento: 1 % desc, 2 fijo desc, 3 % recargo, 4 fijo recargo
    final isPercent = tipo == 1 || tipo == 3;
    final label =
        isPercent
            ? '$prefix${valor.toStringAsFixed(0)}%'
            : '$prefix\$${valor.toStringAsFixed(2)}';

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.local_offer_outlined, color: accent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _activePromoName ?? 'Promoción aplicada',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: accent,
                fontSize: 12.5,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _toUsd(double cup) {
    if (_usdRate <= 0) return '';
    final usd = cup / _usdRate;
    return '≈ USD \$${usd.toStringAsFixed(2)}';
  }

  Widget _buildPriceCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: _primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.sell_outlined, color: _primary, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Precio unitario',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                ),
                const SizedBox(height: 2),
                if (_hasDiscount)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '\$${_discountedPrice!.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                          color: _primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          '\$${_unitPrice.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ),
                    ],
                  )
                else if (_hasSurcharge)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '\$${_discountedPrice!.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          'base \$${_unitPrice.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    '\$${_unitPrice.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                if (_usdRate > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    _toUsd(_effectiveUnitPrice),
                    style: TextStyle(
                      color: Colors.green.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatQty(double q) {
    if (q == q.roundToDouble()) return q.toStringAsFixed(0);
    return q.toString();
  }

  Widget _buildQuantityCard() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Text(
            'Cantidad de libras:',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: Colors.grey.shade700,
            ),
          ),
          const Spacer(),
          _qtyButton(
            icon: Icons.remove_rounded,
            onTap: _quantity > 0.5
                ? () => setState(() {
                      _quantity = (_quantity - 0.5);
                      if (_quantity < 0.1) _quantity = 0.1;
                      _quantityCtrl.text = _formatQty(_quantity);
                      _recalcPrices();
                    })
                : null,
          ),
          SizedBox(
            width: 80,
            child: TextField(
              controller: _quantityCtrl,
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 6),
                border: UnderlineInputBorder(),
              ),
              onChanged: (v) {
                final normalized = v.replaceAll(',', '.');
                final parsed = double.tryParse(normalized);
                if (parsed != null && parsed > 0) {
                  setState(() {
                    _quantity = parsed;
                    _recalcPrices();
                  });
                }
              },
              onSubmitted: (v) {
                final normalized = v.replaceAll(',', '.');
                final parsed = double.tryParse(normalized);
                if (parsed == null || parsed <= 0) {
                  setState(() {
                    _quantity = 1;
                    _quantityCtrl.text = '1';
                    _recalcPrices();
                  });
                }
              },
            ),
          ),
          _qtyButton(
            icon: Icons.add_rounded,
            onTap: () => setState(() {
              _quantity = _quantity + 0.5;
              _quantityCtrl.text = _formatQty(_quantity);
              _recalcPrices();
            }),
          ),
        ],
      ),
    );
  }

  Widget _qtyButton({required IconData icon, VoidCallback? onTap}) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: enabled ? _primary.withOpacity(0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: enabled ? _primary : Colors.grey.shade300),
        ),
        child: Icon(icon, color: enabled ? _primary : Colors.grey, size: 18),
      ),
    );
  }

  Widget _buildTotalCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_primary.withOpacity(0.12), _primary.withOpacity(0.04)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _primary.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Total',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
              Text(
                '${_formatQty(_quantity)} × \$${_effectiveUnitPrice.toStringAsFixed(2)}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${_total.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _primary,
                ),
              ),
              if (_usdRate > 0)
                Text(
                  _toUsd(_total),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ───────────────────────── SHIPMENT FORM ─────────────────────────

  Widget _buildShipmentForm(bool isWide) {
    if (isWide) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSummaryBanner(),
              const SizedBox(height: 16),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 4, child: _buildRemitenteSection()),
                    const SizedBox(width: 14),
                    Expanded(flex: 4, child: _buildDestinatarioSection()),
                    const SizedBox(width: 14),
                    Expanded(flex: 3, child: _buildResumenEnvioCard()),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _buildFinalizarButton(),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSummaryBanner(),
            const SizedBox(height: 14),
            _buildRemitenteSection(),
            const SizedBox(height: 14),
            _buildDestinatarioSection(),
            const SizedBox(height: 20),
            _buildFinalizarButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildFinalizarButton() {
    return SizedBox(
      height: 54,
      child: ElevatedButton.icon(
        onPressed: _isSubmitting ? null : _onFinalizar,
        icon:
            _isSubmitting
                ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
                : const Icon(Icons.check_circle_outline_rounded),
        label: Text(
          _isSubmitting ? 'Procesando...' : 'Finalizar',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  Widget _buildResumenEnvioCard() {
    final product = _detailedProduct ?? widget.product;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
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
                  color: _primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.receipt_long_outlined,
                  color: _primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Resumen',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _kv('Producto', product.denominacion),
          _kv('Cantidad de Libras', _formatQty(_quantity)),
          _kv('Precio unit.', '\$${_effectiveUnitPrice.toStringAsFixed(2)}'),
          const Divider(height: 20),
          _kv(
            'Nº paquete',
            _numeroPaqueteCtrl.text.trim().isEmpty
                ? '-'
                : _numeroPaqueteCtrl.text.trim(),
          ),
          _kv('Método pago', _metodoPago ?? '-'),
          if (_packagePhotoBytes != null) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                _packagePhotoBytes!,
                height: 80,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ],
          if (_descPaqueteCtrl.text.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _descPaqueteCtrl.text.trim(),
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total',
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '\$${_total.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              k,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBanner() {
    final product = _detailedProduct ?? widget.product;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 56,
              height: 56,
              child: Image.asset(_fallbackAsset, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.denominacion,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${_formatQty(_quantity)} × \$${_effectiveUnitPrice.toStringAsFixed(2)}',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                ),
                if (_numeroPaqueteCtrl.text.trim().isNotEmpty ||
                    _metodoPago != null)
                  Text(
                    [
                      if (_numeroPaqueteCtrl.text.trim().isNotEmpty)
                        '#${_numeroPaqueteCtrl.text.trim()}',
                      if (_metodoPago != null) _metodoPago!,
                    ].join(' • '),
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            '\$${_total.toStringAsFixed(2)}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: _primary,
              fontSize: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRemitenteSection() {
    return _partyCard(
      title: 'Remitente',
      icon: Icons.outbox_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _field(_sNombreCtrl, 'Nombre y apellidos', Icons.person_outline),
          const SizedBox(height: 10),
          _field(
            _sTelefonoCtrl,
            'Número de teléfono',
            Icons.phone_outlined,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 10),
          _senderCountryDropdown(),
          const SizedBox(height: 10),
          _senderStateDropdown(),
          const SizedBox(height: 10),
          _senderCityDropdown(),
          const SizedBox(height: 10),
          _field(_sDireccionCtrl, 'Dirección', Icons.location_on_outlined),
        ],
      ),
    );
  }

  Widget _searchableDropdown({
    required String label,
    required IconData icon,
    required List<Map<String, dynamic>> items,
    required String Function(Map<String, dynamic>) labelOf,
    required Map<String, dynamic>? selected,
    required ValueChanged<Map<String, dynamic>> onSelected,
    required String emptyValidatorMessage,
    bool enabled = true,
    bool loading = false,
    String? loadingLabel,
  }) {
    final displayLabel = loading ? (loadingLabel ?? 'Cargando...') : label;
    return FormField<Map<String, dynamic>>(
      validator: (_) => selected == null ? emptyValidatorMessage : null,
      builder: (state) {
        return Autocomplete<Map<String, dynamic>>(
          optionsBuilder: (TextEditingValue value) {
            print('🔎 [Autocomplete:$label] optionsBuilder query="${value.text}" '
                'items=${items.length} enabled=$enabled loading=$loading');
            if (!enabled || loading) {
              return const Iterable<Map<String, dynamic>>.empty();
            }
            final query = value.text.trim().toLowerCase();
            if (query.isEmpty) return items;
            return items.where(
              (e) => labelOf(e).toLowerCase().contains(query),
            );
          },
          displayStringForOption: labelOf,
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            // Mantener el texto sincronizado con el valor seleccionado externamente
            if (selected != null && controller.text != labelOf(selected)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (controller.text != labelOf(selected)) {
                  controller.text = labelOf(selected);
                }
              });
            } else if (selected == null && controller.text.isNotEmpty) {
              // No tocar mientras escribe — solo limpiar si pierde el foco se hace en blur
            }
            return TextFormField(
              controller: controller,
              focusNode: focusNode,
              enabled: enabled && !loading,
              onTap: () {
                // Forzar trigger del optionsBuilder con texto vacío al hacer tap
                if (controller.text.isEmpty) {
                  controller.text = '';
                  controller.selection = TextSelection.fromPosition(
                    TextPosition(offset: controller.text.length),
                  );
                }
              },
              decoration: InputDecoration(
                labelText: displayLabel,
                prefixIcon: Icon(icon, size: 20),
                suffixIcon: controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          controller.clear();
                          state.didChange(null);
                        },
                      )
                    : const Icon(Icons.arrow_drop_down),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                errorText: state.errorText,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
              ),
            );
          },
          optionsViewBuilder: (context, onSelectedOpt, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(10),
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxHeight: 260, maxWidth: 480),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (ctx, i) {
                      final option = options.elementAt(i);
                      return InkWell(
                        onTap: () => onSelectedOpt(option),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Text(
                            labelOf(option),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
          onSelected: (option) {
            print('✓ [Autocomplete:$label] Selected: ${labelOf(option)}');
            state.didChange(option);
            onSelected(option);
          },
        );
      },
    );
  }

  Widget _senderCountryDropdown() {
    return _searchableDropdown(
      label: 'País',
      icon: Icons.public_outlined,
      items: _sCountries,
      labelOf: (c) => c['countryName']?.toString() ?? '',
      selected: _sSelectedCountry,
      enabled: !_sLoadingCountries,
      loading: _sLoadingCountries,
      loadingLabel: 'Cargando países...',
      emptyValidatorMessage: 'Selecciona país',
      onSelected: (country) {
        setState(() {
          _sSelectedCountry = country;
          _sSelectedState = null;
          _sSelectedCity = null;
          _sStates = [];
          _sCities = [];
        });
        _loadSenderStates(country['countryCode']?.toString() ?? '');
      },
    );
  }

  Widget _senderStateDropdown() {
    final enabled = _sSelectedCountry != null && !_sLoadingStates;
    return _searchableDropdown(
      label: 'Estado/Provincia',
      icon: Icons.map_outlined,
      items: _sStates,
      labelOf: (s) => s['name']?.toString() ?? '',
      selected: _sSelectedState,
      enabled: enabled,
      loading: _sLoadingStates,
      loadingLabel: 'Cargando estados...',
      emptyValidatorMessage: 'Selecciona estado/provincia',
      onSelected: (state) {
        setState(() {
          _sSelectedState = state;
          _sSelectedCity = null;
          _sCities = [];
        });
        final countryCode =
            _sSelectedCountry?['countryCode']?.toString() ?? '';
        final adminCode = state['adminCode1']?.toString() ?? '';
        if (countryCode.isNotEmpty && adminCode.isNotEmpty) {
          _loadSenderCities(countryCode, adminCode);
        }
      },
    );
  }

  Widget _senderCityDropdown() {
    final enabled = _sSelectedState != null && !_sLoadingCities;
    return _searchableDropdown(
      label: 'Ciudad/Municipio',
      icon: Icons.location_city_outlined,
      items: _sCities,
      labelOf: (c) => c['name']?.toString() ?? '',
      selected: _sSelectedCity,
      enabled: enabled,
      loading: _sLoadingCities,
      loadingLabel: 'Cargando ciudades...',
      emptyValidatorMessage: 'Selecciona ciudad',
      onSelected: (city) => setState(() => _sSelectedCity = city),
    );
  }

  Widget _buildDestinatarioSection() {
    return _partyCard(
      title: 'Destinatario',
      icon: Icons.inbox_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _field(_dNombreCtrl, 'Nombre y apellidos', Icons.person_outline),
          const SizedBox(height: 10),
          _field(
            _dTelefonoCtrl,
            'Número de teléfono',
            Icons.phone_outlined,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 10),
          _receiverCountryDropdown(),
          const SizedBox(height: 10),
          _receiverStateDropdown(),
          const SizedBox(height: 10),
          _receiverCityDropdown(),
          const SizedBox(height: 10),
          _field(_dDireccionCtrl, 'Dirección', Icons.location_on_outlined),
        ],
      ),
    );
  }

  Widget _receiverCountryDropdown() {
    return _searchableDropdown(
      label: 'País',
      icon: Icons.public_outlined,
      items: _sCountries,
      labelOf: (c) => c['countryName']?.toString() ?? '',
      selected: _dSelectedCountry,
      enabled: !_sLoadingCountries,
      loading: _sLoadingCountries,
      loadingLabel: 'Cargando países...',
      emptyValidatorMessage: 'Selecciona país',
      onSelected: (country) {
        setState(() {
          _dSelectedCountry = country;
          _dSelectedState = null;
          _dSelectedCity = null;
          _dStates = [];
          _dCities = [];
        });
        _loadReceiverStates(country['countryCode']?.toString() ?? '');
      },
    );
  }

  Widget _receiverStateDropdown() {
    final enabled = _dSelectedCountry != null && !_dLoadingStates;
    return _searchableDropdown(
      label: 'Estado/Provincia',
      icon: Icons.map_outlined,
      items: _dStates,
      labelOf: (s) => s['name']?.toString() ?? '',
      selected: _dSelectedState,
      enabled: enabled,
      loading: _dLoadingStates,
      loadingLabel: 'Cargando estados...',
      emptyValidatorMessage: 'Selecciona estado/provincia',
      onSelected: (state) {
        setState(() {
          _dSelectedState = state;
          _dSelectedCity = null;
          _dCities = [];
        });
        final countryCode =
            _dSelectedCountry?['countryCode']?.toString() ?? '';
        final adminCode = state['adminCode1']?.toString() ?? '';
        if (countryCode.isNotEmpty && adminCode.isNotEmpty) {
          _loadReceiverCities(countryCode, adminCode);
        }
      },
    );
  }

  Widget _receiverCityDropdown() {
    final enabled = _dSelectedState != null && !_dLoadingCities;
    return _searchableDropdown(
      label: 'Ciudad/Municipio',
      icon: Icons.location_city_outlined,
      items: _dCities,
      labelOf: (c) => c['name']?.toString() ?? '',
      selected: _dSelectedCity,
      enabled: enabled,
      loading: _dLoadingCities,
      loadingLabel: 'Cargando ciudades...',
      emptyValidatorMessage: 'Selecciona ciudad',
      onSelected: (city) => setState(() => _dSelectedCity = city),
    );
  }

  Widget _partyCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
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
                  color: _primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: _primary, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
      ),
      validator:
          (v) => (v == null || v.trim().isEmpty) ? 'Campo requerido' : null,
    );
  }

  Future<void> _onFinalizar() async {
    if (_isSubmitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // Pre-condiciones del paso 1
    if (_numeroPaqueteCtrl.text.trim().isEmpty ||
        _descPaqueteCtrl.text.trim().isEmpty ||
        _metodoPago == null) {
      setState(() => _showShipmentForm = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Completa los datos del paquete antes de continuar.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    _showLoadingOverlay();

    try {
      final product = _detailedProduct ?? widget.product;

      // Resolver IDs del vendedor / tienda
      final idTienda = await _userPreferences.getIdTienda();
      final uuidVendedor = await _userPreferences.getUserId();

      if (idTienda == null) {
        _closeOverlay();
        _showError('No se pudo determinar la tienda actual.');
        return;
      }
// 
      int? idProveedorCarnaval = await _paqueteriaService
          .resolveProveedorCarnaval(idTienda);

      if (idProveedorCarnaval == null) {
        // _closeOverlay();
        // _showError(
        //     'La tienda no tiene proveedor Carnaval (id_tienda_carnaval) configurado.');
        // return;
        idProveedorCarnaval = 38;
      }

      // Subir foto si existe
      String? fotoUrl;
      if (_packagePhotoBytes != null) {
        fotoUrl = await _paqueteriaService.uploadPackagePhoto(
          bytes: _packagePhotoBytes!,
          filename: _packagePhotoName ?? 'paquete.jpg',
        );
      }

      final payload = <String, dynamic>{
        'id_producto_inventtia': product.id,
        'cantidad': _quantity,
        'precio_unitario': _unitPrice,
        'precio_descuento': _discountedPrice,
        'id_proveedor_carnaval': idProveedorCarnaval,
        'id_tienda': idTienda,
        'uuid_vendedor': uuidVendedor,
        'metodo_pago': _metodoPago,
        'paquete': {
          'numero': _numeroPaqueteCtrl.text.trim(),
          'descripcion': _descPaqueteCtrl.text.trim(),
          'foto_url': fotoUrl,
        },
        'remitente': {
          'nombre': _sNombreCtrl.text.trim(),
          'telefono': _sTelefonoCtrl.text.trim(),
          'direccion': _sDireccionCtrl.text.trim(),
          'pais_codigo': _sSelectedCountry?['countryCode'],
          'pais_nombre': _sSelectedCountry?['countryName'],
          'estado_codigo': _sSelectedState?['adminCode1'],
          'estado_nombre': _sSelectedState?['name'],
          'ciudad_geoname_id': _sSelectedCity?['geonameId'],
          'ciudad_nombre': _sSelectedCity?['name'],
        },
        'destinatario': {
          'nombre': _dNombreCtrl.text.trim(),
          'telefono': _dTelefonoCtrl.text.trim(),
          'direccion': _dDireccionCtrl.text.trim(),
          'pais_codigo': _dSelectedCountry?['countryCode'],
          'pais_nombre': _dSelectedCountry?['countryName'],
          'estado_codigo': _dSelectedState?['adminCode1'],
          'estado_nombre': _dSelectedState?['name'],
          'ciudad_geoname_id': _dSelectedCity?['geonameId'],
          'ciudad_nombre': _dSelectedCity?['name'],
        },
      };

      final result = await _paqueteriaService.registrarOrdenPaqueteria(payload);
      _closeOverlay();

      if (result['status'] == 'success') {
        await _showSuccessDialog(result);
        if (mounted) Navigator.of(context).pop();
      } else {
        _showError(result['message']?.toString() ?? 'Error desconocido');
      }
    } catch (e) {
      _closeOverlay();
      _showError('Error inesperado: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showLoadingOverlay() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    SizedBox(width: 16),
                    Text('Registrando orden...'),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  void _closeOverlay() {
    if (Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<void> _showSuccessDialog(Map<String, dynamic> result) async {
    final product = _detailedProduct ?? widget.product;
    await showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            title: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green.shade600),
                const SizedBox(width: 8),
                const Text('Orden creada'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Producto: ${product.denominacion}'),
                  Text('Cantidad: ${_formatQty(_quantity)} lb'),
                  Text('Total: \$${_total.toStringAsFixed(2)}'),
                  Text('Método pago: ${_metodoPago ?? '-'}'),
                  const Divider(),
                  Text(
                    'Orden Carnaval: #${result['id_orden_carnaval'] ?? '-'}',
                  ),
                  Text(
                    'Operación Inventtia: #${result['id_operacion'] ?? '-'}',
                  ),
                  Text('Paquete: ${_numeroPaqueteCtrl.text.trim()}'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
            ],
          ),
    );
  }

}
