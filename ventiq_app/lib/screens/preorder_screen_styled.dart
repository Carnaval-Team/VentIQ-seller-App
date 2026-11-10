// Pantalla de Pre-orden — VARIANTE VISUAL (`PreorderScreenStyled`).
//
// Es una COPIA de `preorder_screen.dart`: misma lógica, misma navegación y mismo
// cobro; solo cambian los métodos `_build*` (presentación). Se hizo así a
// propósito para poder volver a la pantalla anterior sin deshacer nada:
//
//   · `kPreorderStyled = true`  → esta pantalla (la que sirve la ruta /preorder)
//   · `kPreorderStyled = false` → la original `PreorderScreen`
//
// El interruptor se usa en `main.dart`, en el registro de la ruta '/preorder'.
// Ver `docs/design/preorder-styled.md` para el detalle y para el día en que esta
// variante sustituya definitivamente a la anterior.
//
// REGLA AL MANTENERLA: si se corrige lógica (cobro, stock, turno, offline) en
// `preorder_screen.dart`, hay que replicarla aquí. La duplicación es el precio
// de poder revertir con un flag; cuando la variante se apruebe, lo correcto es
// borrar la original (o dejarla como envoltorio) y quedarse solo con esta.

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../models/payment_method.dart' as pm;
import '../services/order_service.dart';
import '../services/turno_service.dart';
import '../services/payment_method_service.dart';
import '../services/product_detail_service.dart';
import '../services/user_preferences_service.dart';
import '../services/store_config_service.dart';
import '../services/product_recipe_cache_service.dart';
import '../services/bank_sms_service.dart';
import '../services/server_time_service.dart';
import '../theme/ventiq_home_theme.dart';
import '../utils/price_utils.dart';
import '../services/moneda_venta_service.dart';
import '../utils/navigation_helper.dart';
import '../utils/desarme_bulto_local.dart';
import '../utils/presentacion_cadena_local.dart';
import '../widgets/bottom_navigation.dart';
import '../widgets/app_drawer.dart';
import '../widgets/scrolling_text.dart';
import '../widgets/notification_widget.dart';
import '../utils/app_snackbar.dart';
import '../utils/uuid_generator.dart';
import '../widgets/bill_count_dialog.dart';
import 'checkout_screen.dart';
import 'orders_screen.dart';
import 'payment_method_picker_screen.dart';
import '../tutorial/tutorial_anchor.dart';

/// Interruptor de despliegue de la variante visual.
///
/// `true` = la ruta '/preorder' sirve `PreorderScreenStyled`.
/// `false` = sirve la `PreorderScreen` de siempre.
const bool kPreorderStyled = true;

class PreorderScreenStyled extends StatefulWidget {
  const PreorderScreenStyled({Key? key}) : super(key: key);

  @override
  State<PreorderScreenStyled> createState() => _PreorderScreenStyledState();
}

class _PreorderScreenStyledState extends State<PreorderScreenStyled> {
  final OrderService _orderService = OrderService();
  final ProductDetailService _productDetailService = ProductDetailService();
  final UserPreferencesService _userPreferencesService =
      UserPreferencesService();
  List<pm.PaymentMethod> _paymentMethods = [];
  bool _loadingPaymentMethods = false;
  bool _checkingShift = true;
  bool _hasOpenShift = false;
  bool _elaboratingProducts = false;
  pm.PaymentMethod? _globalPaymentMethod;
  double _fractionStep = 0.5;
  bool _isShowSkuEnabled = false;
  bool _isCheckingInventory = false;
  bool _procesandoOrden = false;

  /// Caché por envío de orden: el chequeo de stock, la verificación de
  /// ingredientes y la descomposición pedían las mismas recetas y rutas al
  /// servidor hasta 3 veces por elaborado. Se limpia al iniciar cada envío
  /// para no arrastrar stock viejo entre órdenes.
  final Map<String, Future<List<Map<String, dynamic>>>> _ingredientesCache = {};
  final Map<int, Future<int?>> _almacenVentaCache = {};
  final Map<int, Future<bool>> _esElaboradoCache = {};

  void _limpiarCacheEnvio() {
    _ingredientesCache.clear();
    _almacenVentaCache.clear();
    _esElaboradoCache.clear();
  }

  Future<int?> _almacenVentaCached(int idProducto) => _almacenVentaCache
      .putIfAbsent(idProducto, () => _resolverAlmacenDeVenta(idProducto));

  Future<List<Map<String, dynamic>>> _ingredientesCached(
    int idProducto, {
    int? idAlmacen,
  }) => _ingredientesCache.putIfAbsent(
    '$idProducto|${idAlmacen ?? ''}',
    () => _productDetailService.getProductIngredients(
      idProducto,
      idAlmacen: idAlmacen,
    ),
  );

  /// Solo la receta (ids y cantidades), sin importar el almacén medido:
  /// reutiliza cualquier consulta ya hecha para ese producto.
  Future<List<Map<String, dynamic>>> _recetaCached(int idProducto) {
    final prefijo = '$idProducto|';
    for (final entry in _ingredientesCache.entries) {
      if (entry.key.startsWith(prefijo)) return entry.value;
    }
    return _ingredientesCached(idProducto);
  }

  /// Llena [_esElaboradoCache] para varios productos con una sola consulta.
  /// Offline o ante error no hace nada: [_esElaboradoCached] resuelve por id
  /// con la lógica offline-aware de siempre.
  Future<void> _precargarEsElaborado(List<int> ids) async {
    final faltan =
        ids.where((id) => !_esElaboradoCache.containsKey(id)).toSet();
    if (faltan.isEmpty) return;
    if (await _userPreferencesService.shouldUseLocalData()) return;
    try {
      final rows = await Supabase.instance.client
          .from('app_dat_producto')
          .select('id, es_elaborado, es_servicio')
          .inFilter('id', faltan.toList());
      for (final r in rows) {
        final id = (r['id'] as num?)?.toInt();
        if (id == null) continue;
        _esElaboradoCache[id] = Future.value(
          r['es_elaborado'] == true || r['es_servicio'] == true,
        );
      }
    } catch (e) {
      debugPrint('⚠️ Precarga es_elaborado falló, se resuelve por id: $e');
    }
  }

  Future<bool> _esElaboradoCached(int idProducto) =>
      _esElaboradoCache.putIfAbsent(
        idProducto,
        () => _productDetailService.isProductElaborated(idProducto),
      );

  @override
  void initState() {
    super.initState();
    _loadPersistentPreorder();
    _checkOpenShift();
    _loadFractionStep();
  }

  Future<void> _loadFractionStep() async {
    final step = await _userPreferencesService.getFractionStep();
    if (mounted) {
      setState(() {
        _fractionStep = step;
      });
    }
  }

  /// Cargar preorden persistente al inicializar la pantalla
  Future<void> _loadPersistentPreorder() async {
    try {
      await _orderService.loadPersistentPreorder();
      final isOfflineModeEnabled =
          await _userPreferencesService.isOfflineModeEnabled();
      if (isOfflineModeEnabled) {
        await _orderService.refreshPromotionsFromCache();
      }

      // Si la orden está vacía (nueva), aplicar los productos por defecto
      final currentOrder = _orderService.currentOrder;
      final hasRealItems =
          currentOrder != null && currentOrder.items.any((i) => i.cantidad > 0);
      if (!hasRealItems) {
        await _applyDefaultOrderItems();
      }

      if (mounted) {
        setState(() {});
      }
      print('📱 PreorderScreen: Preorden persistente cargada al inicializar');
    } catch (e) {
      print('❌ PreorderScreen: Error cargando preorden persistente: $e');
    }
  }

  /// Aplica los productos por defecto configurados por el vendedor a la preorden actual.
  Future<void> _applyDefaultOrderItems() async {
    try {
      final defaultItems = await _userPreferencesService.getDefaultOrderItems();
      if (defaultItems.isEmpty) return;

      print(
        '🛒 PreorderScreen: Aplicando ${defaultItems.length} productos por defecto',
      );

      for (final entry in defaultItems) {
        try {
          final product = Product.fromJson(
            entry['product'] as Map<String, dynamic>,
          );
          final cantidad = (entry['cantidad'] as num).toDouble();
          if (cantidad <= 0) continue;

          await _orderService.addItemToCurrentOrder(
            producto: product,
            cantidad: cantidad,
            ubicacionAlmacen: 'Por defecto',
          );
          print(
            '✅ Producto por defecto agregado: ${product.denominacion} x$cantidad',
          );
        } catch (e) {
          print('⚠️ Error agregando producto por defecto: $e');
        }
      }
    } catch (e) {
      print('❌ Error aplicando productos por defecto: $e');
    }
  }

  Future<void> _checkOpenShift() async {
    try {
      setState(() {
        _checkingShift = true;
      });

      print('🔍 PreorderScreen: Verificando turno abierto...');
      final hasShift = await TurnoService.hasOpenShift();
      print('📋 PreorderScreen: Resultado verificación turno: $hasShift');

      setState(() {
        _hasOpenShift = hasShift;
        _checkingShift = false;
      });

      if (_hasOpenShift) {
        print(
          '✅ PreorderScreen: Turno encontrado, cargando métodos de pago...',
        );
        _loadPaymentMethods();
      } else {
        print('❌ PreorderScreen: No hay turno abierto, mostrando diálogo...');
        _showNoShiftDialog();
      }
    } catch (e) {
      print('❌ PreorderScreen: Error checking shift: $e');
      setState(() {
        _checkingShift = false;
        _hasOpenShift = false;
      });
      _showNoShiftDialog();
    }
  }

  void _showNoShiftDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(VentiqHomeTheme.radiusBlock),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: VentiqHomeTheme.warning.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: VentiqHomeTheme.warning,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Turno Requerido',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: VentiqHomeTheme.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            content: const Text(
              'Debe tener un turno abierto para crear órdenes. Por favor, vaya a la sección de Apertura para abrir un turno.',
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: VentiqHomeTheme.textSecondary,
              ),
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pushReplacementNamed(context, '/apertura');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: VentiqHomeTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
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

  Future<void> _loadPaymentMethods() async {
    setState(() {
      _loadingPaymentMethods = true;
    });

    try {
      // Verificar si el modo offline está activado
      final isOfflineModeEnabled =
          await _userPreferencesService.isOfflineModeEnabled();

      final paymentMethods =
          await PaymentMethodService.getPaymentMethodsWithCache(
            isOfflineModeEnabled: isOfflineModeEnabled,
          );
      print('✅ Métodos de pago cargados: ${paymentMethods.length}');

      // Solo métodos activos de BD/cache. CxC (998) no se gestiona en el TPV.
      setState(() {
        _paymentMethods = paymentMethods;
        _loadingPaymentMethods = false;
      });
    } catch (e) {
      setState(() {
        _loadingPaymentMethods = false;
      });
      print('Error loading payment methods: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingShift) {
      return Scaffold(
        backgroundColor: VentiqHomeTheme.surface,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_hasOpenShift) {
      return Scaffold(
        backgroundColor: VentiqHomeTheme.surface,
        body: Center(child: Text('No tiene un turno abierto')),
      );
    }

    final currentOrder = _orderService.currentOrder;

    return Scaffold(
      backgroundColor: VentiqHomeTheme.surface,
      appBar: AppBar(
        backgroundColor: VentiqHomeTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Preorden Abierta',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        centerTitle: true,
        actions: [
          const NotificationWidget(),
          if (currentOrder != null && currentOrder.items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all, color: Colors.white),
              onPressed: _showClearOrderDialog,
              tooltip: 'Limpiar orden',
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
      body:
          currentOrder == null || currentOrder.items.isEmpty
              ? _buildEmptyState()
              : _buildOrderContent(currentOrder),
      endDrawer: const AppDrawer(),
      bottomNavigationBar: AppBottomNavigation(
        currentIndex: 1, // Preorden tab
        onTap: _onBottomNavTap,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(VentiqHomeTheme.sectionPadding),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: VentiqHomeTheme.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shopping_cart_outlined,
                size: 44,
                color: VentiqHomeTheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No hay productos en la preorden',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: VentiqHomeTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Agrega productos desde el catálogo',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: VentiqHomeTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _onBottomNavTap(0), // Ir a Home
              icon: const Icon(Icons.home_rounded, size: 20),
              label: const Text('Ir al Catálogo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: VentiqHomeTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderContent(Order order) {
    return Column(
      children: [
        // Header con información de la orden
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: const BoxDecoration(
            color: VentiqHomeTheme.card,
            border: Border(bottom: BorderSide(color: VentiqHomeTheme.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Orden: ${order.id}',
                    style: VentiqHomeTheme.tituloSeccion,
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: VentiqHomeTheme.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(
                        VentiqHomeTheme.radiusChip,
                      ),
                    ),
                    child: Text(
                      order.status.displayName,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: VentiqHomeTheme.warning,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${order.distinctItemCount} producto${order.distinctItemCount == 1 ? '' : 's'} • Total: ${MonedaVentaService.formatearPrecio(PriceUtils.roundDiscountPrice(order.total), conSimbolo: true)}',
                style: const TextStyle(
                  fontSize: 13.5,
                  color: VentiqHomeTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              // Global payment method selector
              _buildGlobalPaymentMethodSelector(),
            ],
          ),
        ),
        // Lista de items
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: order.items.length,
            itemBuilder: (context, index) {
              final item = order.items[index];
              return _buildOrderItem(item);
            },
          ),
        ),
        // Footer con acciones
        TutorialAnchor(id: 'preorder_footer', child: _buildOrderFooter(order)),
      ],
    );
  }

  /// Tarjeta de una línea del pedido.
  ///
  /// Jerarquía pensada para escanear de un vistazo en el móvil: **nombre y total
  /// arriba**, debajo una sola línea «cantidad × precio unitario», la ubicación
  /// en gris y, al pie, el medio de pago de la línea junto a los controles de
  /// cantidad. Antes eran cinco filas y dos de ellas repetían información.
  Widget _buildOrderItem(OrderItem item) {
    final String cantidad = PriceUtils.formatQuantity(item.cantidad);
    final String total = MonedaVentaService.formatearPrecio(
      PriceUtils.roundDiscountPrice(item.subtotal),
      conSimbolo: true,
    );
    final String unitario = MonedaVentaService.formatearPrecio(
      PriceUtils.roundDiscountPrice(item.displayPrice),
      conSimbolo: true,
    );
    final double step = (item.cantidad % 1 != 0) ? _fractionStep : 1.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: VentiqHomeTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: VentiqHomeTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  item.nombre,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: VentiqHomeTheme.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                total,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  color: VentiqHomeTheme.primary,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          // Cantidad × precio unitario en UNA sola línea (antes eran dos filas).
          Text(
            '$cantidad × $unitario',
            style: const TextStyle(
              fontSize: 12.5,
              color: VentiqHomeTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              const Icon(
                Icons.location_on_outlined,
                size: 14,
                color: VentiqHomeTheme.textSecondary,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: ScrollingText(
                  text: item.ubicacionAlmacen,
                  style: const TextStyle(
                    fontSize: 12,
                    color: VentiqHomeTheme.textSecondary,
                  ),
                  maxWidth: 220,
                  scrollDuration: const Duration(seconds: 4),
                  pauseDuration: const Duration(seconds: 2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Medio de pago de la línea a la izquierda, cantidad a la derecha.
          Row(
            children: <Widget>[
              Expanded(child: _buildPaymentMethodSelector(item)),
              _buildControlesCantidad(item, step),
            ],
          ),
        ],
      ),
    );
  }

  /// − / + / borrar en una fila. 38 px por control: tres caben junto a la
  /// píldora sin apretar y siguen siendo cómodos al tacto en un móvil.
  Widget _buildControlesCantidad(OrderItem item, double step) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _botonCantidad(
          icono: Icons.remove_circle_outline,
          color: VentiqHomeTheme.danger,
          onTap: () => _updateItemQuantity(item.id, item.cantidad - step),
        ),
        _botonCantidad(
          icono: Icons.add_circle_outline,
          color: VentiqHomeTheme.primary,
          onTap: () => _updateItemQuantity(item.id, item.cantidad + step),
        ),
        _botonCantidad(
          icono: Icons.delete_outline,
          color: VentiqHomeTheme.danger,
          onTap: () => _removeItem(item.id),
        ),
      ],
    );
  }

  Widget _botonCantidad({
    required IconData icono,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkResponse(
      onTap: onTap,
      radius: 22,
      child: SizedBox(
        width: 38,
        height: 38,
        child: Icon(icono, size: 22, color: color),
      ),
    );
  }

  Widget _buildOrderFooter(Order order) {
    final hasEfectivo = order.items.any(
      (item) => item.paymentMethod?.esEfectivo ?? false,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: const BoxDecoration(
        color: VentiqHomeTheme.card,
        border: Border(top: BorderSide(color: VentiqHomeTheme.border)),
        boxShadow: VentiqHomeTheme.shadowCard,
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total de la Orden:',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: VentiqHomeTheme.textPrimary,
                ),
              ),
              Text(
                MonedaVentaService.formatearPrecio(
                  PriceUtils.roundDiscountPrice(order.total),
                  conSimbolo: true,
                ),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: VentiqHomeTheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (hasEfectivo)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showBillCountDialog(order),
                icon: const Icon(Icons.calculate_outlined, size: 18),
                label: const Text('Contar Billetes'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: VentiqHomeTheme.primary,
                  side: const BorderSide(color: VentiqHomeTheme.primary),
                  backgroundColor: VentiqHomeTheme.primary.withValues(
                    alpha: 0.04,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          if (hasEfectivo) const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _showClearOrderDialog,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: VentiqHomeTheme.danger,
                    side: const BorderSide(color: VentiqHomeTheme.danger),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Cancelar Orden'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed:
                      (_procesandoOrden ||
                              _elaboratingProducts ||
                              _isCheckingInventory)
                          ? null
                          : _finalizeOrder,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: VentiqHomeTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child:
                      (_procesandoOrden || _isCheckingInventory)
                          ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Procesando...',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          )
                          : const Text(
                            'Enviar Orden',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showBillCountDialog(Order order) {
    final cashExpected = order.items
        .where((item) => item.paymentMethod?.esEfectivo ?? false)
        .fold<double>(0.0, (sum, item) => sum + item.subtotal);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => Scaffold(
              backgroundColor: VentiqHomeTheme.card,
              body: BillCountDialog(
                order: order,
                expectedAmount: cashExpected > 0 ? cashExpected : order.total,
                userPreferencesService: _userPreferencesService,
                closeOnly: true,
                confirmLabel: 'Cerrar',
                onConfirmPayment: () {},
              ),
            ),
      ),
    );
  }

  /// Píldora compacta del medio de pago de UNA línea.
  ///
  /// Antes cada tarjeta llevaba un bloque grande con el selector y su aviso; eso
  /// empujaba a resolver el cobro línea a línea. Ahora el selector principal es
  /// el global de la cabecera y aquí queda solo el medio de ESTA línea, con un
  /// chevron para cambiarla. Tocar abre el mismo `PaymentMethodPickerScreen` de
  /// siempre, así que los medios siguen siendo los reales de la tienda.
  Widget _buildPaymentMethodSelector(OrderItem item) {
    if (_loadingPaymentMethods) {
      return const SizedBox(
        height: 32,
        child: Center(
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final pm.PaymentMethod? elegido = item.paymentMethod;
    final bool difiere = _lineaDifiereDelGlobal(elegido);
    final Color color =
        elegido == null
            ? VentiqHomeTheme.danger
            : (elegido.esEfectivo
                ? VentiqHomeTheme.success
                : VentiqHomeTheme.primary);

    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap:
              (_paymentMethods.isEmpty || _loadingPaymentMethods)
                  ? null
                  : () => _elegirMedioDeLinea(item),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // Punto ámbar: esta línea se sale del medio de referencia.
                if (difiere) ...<Widget>[
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: VentiqHomeTheme.warning,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Icon(
                  elegido?.typeIcon ?? Icons.payment,
                  size: 15,
                  color: color,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    elegido?.displayName ?? 'Sin medio',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(Icons.expand_more_rounded, size: 16, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Abre el selector real para cambiar SOLO esta línea.
  Future<void> _elegirMedioDeLinea(OrderItem item) async {
    final pm.PaymentMethod? elegido = await PaymentMethodPickerScreen.pick(
      context,
      methods: _paymentMethods,
      selected: item.paymentMethod,
      title: 'Medio de pago',
      subtitle: item.nombre,
    );
    // Cancelar no borra el medio que ya tenía la línea: `null` aquí significa
    // «el usuario cerró la hoja», no «déjala sin medio».
    if (elegido != null) _updateItemPaymentMethod(item.id, elegido);
  }

  /// Medio «de referencia» para marcar excepciones: el global si está elegido y,
  /// si no (orden mixta), el más frecuente entre las líneas con medio.
  pm.PaymentMethod? _medioDeReferencia() {
    if (_globalPaymentMethod != null) return _globalPaymentMethod;
    final Order? orden = _orderService.currentOrder;
    if (orden == null || orden.items.isEmpty) return null;

    final Map<int, int> conteo = <int, int>{};
    final Map<int, pm.PaymentMethod> porId = <int, pm.PaymentMethod>{};
    for (final OrderItem it in orden.items) {
      final pm.PaymentMethod? m = it.paymentMethod;
      if (m == null) continue;
      conteo[m.id] = (conteo[m.id] ?? 0) + 1;
      porId[m.id] = m;
    }
    if (conteo.isEmpty) return null;
    final MapEntry<int, int> mayor = conteo.entries.reduce(
      (MapEntry<int, int> a, MapEntry<int, int> b) =>
          a.value >= b.value ? a : b,
    );
    return porId[mayor.key];
  }

  bool _lineaDifiereDelGlobal(pm.PaymentMethod? linea) {
    final pm.PaymentMethod? ref = _medioDeReferencia();
    if (ref == null || linea == null) return false;
    return linea.id != ref.id;
  }

  /// «Mixto · 2 Efectivo, 1 Transferencia», o `null` si todas las líneas
  /// comparten medio (o no hay medio todavía).
  String? _resumenMezcla() {
    final Order? orden = _orderService.currentOrder;
    if (orden == null) return null;

    final Map<int, int> conteo = <int, int>{};
    final Map<int, String> nombres = <int, String>{};
    for (final OrderItem it in orden.items) {
      final pm.PaymentMethod? m = it.paymentMethod;
      if (m == null) continue;
      conteo[m.id] = (conteo[m.id] ?? 0) + 1;
      nombres[m.id] = m.displayName;
    }
    if (conteo.length < 2) return null;

    final List<MapEntry<int, int>> entradas =
        conteo.entries.toList()..sort(
          (MapEntry<int, int> a, MapEntry<int, int> b) =>
              b.value.compareTo(a.value),
        );
    final String detalle = entradas
        .map((MapEntry<int, int> e) => '${e.value} ${nombres[e.key]}')
        .join(', ');
    return 'Mixto · $detalle';
  }

  void _updateItemPaymentMethod(
    String itemId,
    pm.PaymentMethod? paymentMethod,
  ) {
    setState(() {
      _orderService.updateItemPaymentMethod(itemId, paymentMethod);
    });
  }

  void _updateItemQuantity(String itemId, double newQuantity) {
    setState(() {
      _orderService.updateItemQuantity(itemId, newQuantity);
    });
  }

  void _removeItem(String itemId) {
    setState(() {
      _orderService.removeItemFromCurrentOrder(itemId);
    });
  }

  void _showClearOrderDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(VentiqHomeTheme.radiusBlock),
            ),
            title: const Text(
              'Cancelar Orden',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: VentiqHomeTheme.textPrimary,
              ),
            ),
            content: const Text(
              '¿Estás seguro de que quieres cancelar esta orden? Se perderán todos los productos agregados.',
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: VentiqHomeTheme.textSecondary,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () {
                  _orderService.cancelCurrentOrder();
                  Navigator.pop(context);
                  setState(() {});
                },
                style: TextButton.styleFrom(
                  foregroundColor: VentiqHomeTheme.danger,
                ),
                child: const Text('Confirmar'),
              ),
            ],
          ),
    );
  }

  /// Un solo estado para todo el envío (chequeo → config → elaborados →
  /// checkout/registro): el botón queda deshabilitado de punta a punta en vez
  /// de habilitarse y deshabilitarse entre pasos, y se ignoran dobles toques.
  Future<void> _finalizeOrder() async {
    if (_procesandoOrden) return;
    setState(() => _procesandoOrden = true);
    try {
      await _finalizeOrderInner();
    } finally {
      if (mounted) setState(() => _procesandoOrden = false);
    }
  }

  Future<void> _finalizeOrderInner() async {
    final currentOrder = _orderService.currentOrder;
    if (currentOrder == null || currentOrder.items.isEmpty) {
      AppSnackBar.showPersistent(
        context,
        message: 'No hay productos en la orden',
        backgroundColor: VentiqHomeTheme.danger,
      );
      return;
    }

    // Validate that all items have payment methods assigned
    final itemsWithoutPayment =
        currentOrder.items.where((item) => item.paymentMethod == null).toList();

    if (itemsWithoutPayment.isNotEmpty) {
      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Métodos de Pago Requeridos'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Los siguientes productos necesitan un método de pago:',
                  ),
                  const SizedBox(height: 8),
                  ...itemsWithoutPayment.map(
                    (item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '• ${item.nombre}',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Entendido'),
                ),
              ],
            ),
      );
      return;
    }

    // Si algún producto se paga por transferencia, empezar a escuchar el SMS
    // de confirmación de PAGOxMOVIL YA — antes de navegar al checkout — para
    // no perder el mensaje del cliente que transfiere mientras el cajero
    // termina de armar la orden. Es best-effort: si no hay permiso/soporte,
    // el cobro sigue igual (la confirmación es informativa).
    final tieneTransferencia = currentOrder.items.any(
      (item) => item.paymentMethod?.esTransferencia ?? false,
    );
    if (tieneTransferencia) {
      // No se espera (await) para no retrasar la navegación.
      BankSmsService().startListening();
    }

    // Verificar si el modo offline / full offline está activado
    final isOfflineModeEnabled =
        await _userPreferencesService.isOfflineModeEnabled();
    final stayFullyOffline =
        await _userPreferencesService.shouldStayFullyOffline();
    final useOfflinePath = isOfflineModeEnabled || stayFullyOffline;

    // La configuración de tienda se pide EN PARALELO con el chequeo de stock
    // (antes se esperaba a que terminara el chequeo para empezar a pedirla).
    final storeConfigFuture = () async {
      final storeId = await UserPreferencesService().getIdTienda();
      if (storeId == null) return null;
      return StoreConfigService.getStoreConfig(storeId);
    }().catchError((Object e) {
      print('⚠️ Error cargando configuración de tienda: $e');
      return null;
    });

    // Deshabilitar botón y mostrar indicador de carga mientras se verifica inventario
    _limpiarCacheEnvio();
    setState(() {
      _isCheckingInventory = true;
    });

    try {
      // Verificar disponibilidad en inventario (cache local si offline)
      final stockProblems = await _checkInventoryAvailability(
        currentOrder.items,
        forceOffline: useOfflinePath,
      );
      if (!mounted) return;

      if (stockProblems.isNotEmpty) {
        _showStockProblemsDialog(stockProblems);
        return;
      }
    } on _StockCheckNetworkException catch (e) {
      if (!mounted) return;
      // En full offline nunca deberíamos llegar aquí; si ocurre, no bloquear.
      if (useOfflinePath) {
        print(
          '📦 Full/offline: se ignora fallo de red en verificación de stock: $e',
        );
      } else {
        print('🌐 Verificación de stock falló por red: $e');
        _showStockNetworkErrorDialog();
        return;
      }
    } catch (e) {
      if (!mounted) return;
      if (useOfflinePath) {
        print('📦 Full/offline: error stock no bloqueante: $e');
      } else if (_isNetworkError(e)) {
        print('🌐 Verificación de stock falló por red (catch general): $e');
        _showStockNetworkErrorDialog();
        return;
      } else {
        print('⚠️ Error inesperado verificando stock: $e');
        AppSnackBar.showPersistent(
          context,
          message: 'No se pudo verificar el stock: ${e.toString()}',
          backgroundColor: VentiqHomeTheme.danger,
        );
        return;
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingInventory = false;
        });
      }
    }

    // Cargar la configuración completa antes de decidir cómo crear la orden.
    bool noSolicitarCliente = false;
    bool solicitarImagenOperacion = false;
    bool permiteVenderSinDisponibilidad = false;
    try {
      final storeConfig = await storeConfigFuture;
      if (storeConfig == null) {
        throw StateError('No se pudo cargar la configuración de la tienda');
      }
      noSolicitarCliente = storeConfig['no_solicitar_cliente'] == true;
      solicitarImagenOperacion =
          storeConfig['solicitar_imagen_operacion'] == true;
      permiteVenderSinDisponibilidad =
          storeConfig['permite_vender_aun_sin_disponibilidad'] == true;
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.showPersistent(
        context,
        message:
            'No se pudo cargar la configuración de la tienda. Intenta nuevamente.',
        backgroundColor: VentiqHomeTheme.danger,
      );
      return;
    }

    // Las ventas con "Pago Pendiente" (cuenta por cobrar) siempre deben pasar
    // por el checkout: necesitan sí o sí un cliente asociado (buscado o
    // creado ahí), sin importar que la tienda tenga activado
    // "no_solicitar_cliente" para las ventas normales.
    final tienePagoPendiente = currentOrder.items.any(
      (item) => item.paymentMethod?.esPagoPendiente ?? false,
    );

    if (useOfflinePath) {
      // MODO OFFLINE / FULL OFFLINE: sin servidor
      // En offline la foto de operación no se puede gestionar, se ignora el requisito.
      if (noSolicitarCliente && !tienePagoPendiente) {
        print(
          '🔌 Modo offline + no_solicitar_cliente - Creando orden localmente',
        );
        currentOrder.isOfflineOrder = true;
        await _processElaboratedProducts(
          currentOrder,
          permiteVenderSinDisponibilidad: permiteVenderSinDisponibilidad,
        );
        await _submitOrderDirect(currentOrder, offline: true);
      } else {
        print(
          '🔌 Modo offline - Continuando al checkout para datos del cliente',
        );
        currentOrder.isOfflineOrder = true;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CheckoutScreen(order: currentOrder),
          ),
        ).then((_) {
          setState(() {});
        });
      }
    } else if (noSolicitarCliente &&
        !solicitarImagenOperacion &&
        !tienePagoPendiente) {
      // MODO DIRECTO: No se requieren datos del cliente, crear orden inmediatamente
      print('⚡ No se solicita cliente - Creando orden directamente');
      await _processElaboratedProducts(
        currentOrder,
        permiteVenderSinDisponibilidad: permiteVenderSinDisponibilidad,
      );
      await _submitOrderDirect(currentOrder, offline: false);
    } else {
      // MODO NORMAL: Elaborar productos y continuar al checkout
      print(
        '🌐 Modo online - Procesando elaboración y continuando al checkout',
      );
      await _processElaboratedProducts(
        currentOrder,
        permiteVenderSinDisponibilidad: permiteVenderSinDisponibilidad,
      );

      // Navigate to checkout screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CheckoutScreen(order: currentOrder),
        ),
      ).then((_) {
        setState(() {});
      });
    }
  }

  /// Busca el stock actual de un producto en el cache offline.
  /// Navega por detalles_completos.inventario y filtra por ubicacion, variante y presentacion.
  /// Si no hay filas de inventario, usa la cantidad del listado cacheado.
  /// Retorna null si no encuentra el producto en cache.
  Future<double?> _getStockFromCache({
    required int idProducto,
    int? idUbicacion,
    int? idVariante,
    int? idPresentacion,
  }) async {
    try {
      final offlineData = await _userPreferencesService.getOfflineData();
      if (offlineData == null || offlineData['products'] == null) return null;

      final productsData = Map<String, dynamic>.from(
        offlineData['products'] as Map,
      );

      for (final categoryProducts in productsData.values) {
        final productList = List<dynamic>.from(categoryProducts as List);
        for (final prodDataRaw in productList) {
          final prodData = Map<String, dynamic>.from(prodDataRaw as Map);
          final pid = prodData['id'];
          final id = pid is int ? pid : (pid is num ? pid.toInt() : null);
          if (id != idProducto) continue;

          final detalles = prodData['detalles_completos'];
          if (detalles is Map) {
            final inventarioList = List<dynamic>.from(
              detalles['inventario'] as List? ?? [],
            );

            double? matched;
            double invSum = 0;
            var hasInvRows = false;

            for (final invRaw in inventarioList) {
              if (invRaw is! Map) continue;
              final inv = Map<String, dynamic>.from(invRaw);
              hasInvRows = true;
              final qty =
                  (inv['cantidad_disponible'] as num?)?.toDouble() ?? 0.0;
              invSum += qty;

              final ubicacion =
                  inv['ubicacion'] is Map
                      ? Map<String, dynamic>.from(inv['ubicacion'] as Map)
                      : null;
              final variante =
                  inv['variante'] is Map
                      ? Map<String, dynamic>.from(inv['variante'] as Map)
                      : null;
              final presentacion =
                  inv['presentacion'] is Map
                      ? Map<String, dynamic>.from(inv['presentacion'] as Map)
                      : null;

              final invUbicacionId = ubicacion?['id'] as int?;
              final invVarianteId = variante?['id'] as int?;
              final invPresentacionId = presentacion?['id'] as int?;

              final ubicacionMatch =
                  idUbicacion == null || invUbicacionId == idUbicacion;
              // id_variante del cliente puede ser secuencial sintético; no exigir match estricto
              final varianteMatch =
                  idVariante == null ||
                  invVarianteId == null ||
                  invVarianteId == idVariante;
              final presentacionMatch =
                  idPresentacion == null || invPresentacionId == idPresentacion;

              if (ubicacionMatch && varianteMatch && presentacionMatch) {
                matched = qty;
                break;
              }
            }

            if (matched != null) return matched;
            if (hasInvRows && invSum > 0) return invSum;
          }

          final cachedCantidad = (prodData['cantidad'] as num?)?.toDouble();
          if (cachedCantidad != null) return cachedCantidad;
          return null;
        }
      }
    } catch (e) {
      print('⚠️ Error leyendo stock desde cache offline: $e');
    }
    return null;
  }

  /// Cadena de presentaciones y saldos por presentación de un producto desde
  /// el cache offline, para evaluar el desarme sin red.
  ///
  /// Las presentaciones pueden vivir en DOS sitios del cache, según cómo se
  /// sincronizó: dentro de `detalles_completos.presentaciones` o al nivel del
  /// producto (`prodData['presentaciones']`, la forma que lee
  /// `_loadProductPresentations`). Se prueban ambas. Los saldos vienen de
  /// `detalles_completos.inventario`; si el cache no trae nada utilizable se
  /// devuelve null y se conserva el problema original de stock.
  Future<({List<PresentacionLocal> cadena, Map<int, double> stocks})?>
  _cadenaYStocksOffline(int idProducto) async {
    try {
      final offlineData = await _userPreferencesService.getOfflineData();
      final productsData = offlineData?['products'] as Map<String, dynamic>?;
      if (productsData == null) return null;

      for (final categoryProducts in productsData.values) {
        if (categoryProducts is! List) continue;
        for (final raw in categoryProducts) {
          if (raw is! Map) continue;
          final prodData = Map<String, dynamic>.from(raw);
          final pid = prodData['id'];
          final id = pid is int ? pid : (pid is num ? pid.toInt() : null);
          if (id != idProducto) continue;

          // Presentaciones: detalles_completos.presentaciones ?? nivel producto.
          List<Map<String, dynamic>>? crudas;
          final detalles = prodData['detalles_completos'];
          if (detalles is Map) {
            final d = Map<String, dynamic>.from(detalles);
            crudas =
                (d['presentaciones'] as List?)
                    ?.whereType<Map>()
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList();
          }
          crudas ??=
              (prodData['presentaciones'] as List?)
                  ?.whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList();
          if (crudas == null || crudas.isEmpty) return null;

          final cadena = PresentacionCadenaLocal.resolverDesdeCrudas(crudas);
          if (cadena.isEmpty) return null;

          final stocks = <int, double>{};
          if (detalles is Map) {
            final d = Map<String, dynamic>.from(detalles);
            for (final invRaw in d['inventario'] as List? ?? []) {
              if (invRaw is! Map) continue;
              final inv = Map<String, dynamic>.from(invRaw);
              final pres =
                  inv['presentacion'] is Map
                      ? Map<String, dynamic>.from(inv['presentacion'] as Map)
                      : null;
              final idPres = (pres?['id'] as num?)?.toInt();
              final qty =
                  (inv['cantidad_disponible'] as num?)?.toDouble() ?? 0.0;
              if (idPres != null) {
                stocks[idPres] = (stocks[idPres] ?? 0) + qty;
              }
            }
          }

          return (cadena: cadena, stocks: stocks);
        }
      }
    } catch (e) {
      print(
        '⚠️ Error leyendo cadena/stocks offline para producto $idProducto: $e',
      );
    }
    return null;
  }

  /// Cadena y saldos por presentación desde el servidor (online), para el
  /// fallback del chequeo cuando `fn_preview_rebalanceo` no se puede evaluar
  /// (item sin id_ubicacion/id_presentacion, típico de cuentas de mesa).
  ///
  /// Usa `get_detalle_producto`, que ya incluye la fila de la presentación
  /// base aunque esté en cero (migración get_detalle_producto_incluir_base_cero).
  Future<({List<PresentacionLocal> cadena, Map<int, double> stocks})?>
  _cadenaYStocksOnline(int idProducto) async {
    try {
      final supabase = Supabase.instance.client;
      final detalle = await supabase.rpc(
        'get_detalle_producto',
        params: {'id_producto_param': idProducto},
      );
      if (detalle is! Map) return null;
      final d = Map<String, dynamic>.from(detalle);

      final prod =
          d['producto'] is Map
              ? Map<String, dynamic>.from(d['producto'] as Map)
              : null;
      var crudas =
          (prod?['presentaciones'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
      // get_detalle_producto no siempre anida las presentaciones: consultar
      // la tabla directamente, igual que hace ProductDetailService.
      if (crudas == null || crudas.isEmpty) {
        final presRows = await supabase
            .from('app_dat_producto_presentacion')
            .select(
              'id, cantidad, es_base, presentacion:app_nom_presentacion(id, denominacion, sku_codigo)',
            )
            .eq('id_producto', idProducto);
        crudas =
            presRows
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
      }
      if (crudas.isEmpty) return null;

      final cadena = PresentacionCadenaLocal.resolverDesdeCrudas(crudas);
      if (cadena.isEmpty) return null;

      final stocks = <int, double>{};
      for (final invRaw in d['inventario'] as List? ?? []) {
        if (invRaw is! Map) continue;
        final inv = Map<String, dynamic>.from(invRaw);
        final pres =
            inv['presentacion'] is Map
                ? Map<String, dynamic>.from(inv['presentacion'] as Map)
                : null;
        final idPres = (pres?['id'] as num?)?.toInt();
        final qty = (inv['cantidad_disponible'] as num?)?.toDouble() ?? 0.0;
        if (idPres != null) {
          stocks[idPres] = (stocks[idPres] ?? 0) + qty;
        }
      }

      return (cadena: cadena, stocks: stocks);
    } catch (e) {
      print(
        '⚠️ Error leyendo cadena/stocks online para producto $idProducto: $e',
      );
      return null;
    }
  }

  /// Verifica disponibilidad de inventario para todos los items de la orden.
  /// Para productos elaborados/servicios, verifica el stock de sus ingredientes.
  /// Para productos normales, verifica directamente en inventario.
  /// Retorna lista de problemas: [{nombre, cantidad_pedida, stock_disponible, diferencia, presentacion}]
  ///
  /// FASE 7 P0 (docs/PLAN_CONSUMO_INGREDIENTES_ELABORADOS_PRESENTACIONES.md §0):
  /// para elaborados la comparación es en UNIDADES BASE, con el
  /// `cantidad_disponible` que ya devuelve `getProductIngredients`.
  ///
  /// task-12 (FASE 7 P1): además se mide con el almacén del TPV que usará la
  /// venta (`fn_resolver_origen_venta`); si no se puede resolver con certeza, se
  /// mide con todos los almacenes y el cartel lo etiqueta.
  ///
  /// ⚠️ GATE DE RELEASE — NO PUBLICAR este cambio sin las Fases 0.5 + 1 + 3
  /// aplicadas en AMBOS proyectos: con el descuento SQL actual
  /// (`fn_descontar_ingredientes_elaborado`, `LEAST` mixto, y
  /// `fn_registrar_venta` que RETORNA el error sin `RAISE`) dejar pasar esta
  /// venta descuenta 2500 u + 2500 kg de Frijoles y saquea el almacén.
  /// Primero el SQL, después este APK.
  Future<List<Map<String, dynamic>>> _checkInventoryAvailability(
    List<OrderItem> items, {
    bool forceOffline = false,
  }) async {
    final supabase = Supabase.instance.client;
    final problems = <Map<String, dynamic>>[];
    final isOfflineMode =
        forceOffline ||
        await _userPreferencesService.isOfflineModeEnabled() ||
        await _userPreferencesService.shouldStayFullyOffline();

    // Pozo compartido por producto: cada línea procesada reserva sus
    // unidades base, así "1 Caja + 5 Latas" compiten por el mismo stock
    // y no pasan sueltas si juntas sobreven-nden.
    final reservadoBasePorProducto = <int, double>{};
    final conteoPorProducto = <int, int>{};
    for (final i in items) {
      conteoPorProducto[i.producto.id] =
          (conteoPorProducto[i.producto.id] ?? 0) + 1;
    }
    final productosMultilinea = {
      for (final e in conteoPorProducto.entries)
        if (e.value > 1) e.key,
    };

    // Online: todas las consultas de red se lanzan EN PARALELO antes de
    // evaluar. La evaluación sigue siendo secuencial (el pozo compartido
    // depende del orden de las líneas), pero ya no espera N viajes en serie.
    final stockFilaFutures = <int, Future<List<Map<String, dynamic>>>>{};
    if (!isOfflineMode) {
      final pendientes = <Future<Object?>>[];
      for (var idx = 0; idx < items.length; idx++) {
        final item = items[idx];
        if (item.producto.esElaborado || item.producto.esServicio) {
          final soloServicio =
              item.producto.esServicio && !item.producto.esElaborado;
          pendientes.add(
            (soloServicio
                    ? Future<int?>.value(null)
                    : _almacenVentaCached(item.producto.id))
                .then(
                  (alm) =>
                      _ingredientesCached(item.producto.id, idAlmacen: alm),
                ),
          );
        } else if (item.inventoryData?['stock_movido'] != true) {
          final f = _consultarStockFila(item);
          stockFilaFutures[idx] = f;
          pendientes.add(f);
        }
      }
      // Los errores se re-lanzan al esperar cada futuro dentro del bucle
      // (mismo manejo de red que antes); aquí solo se espera a que terminen.
      await Future.wait(pendientes).catchError((_) => <Object?>[]);
    }

    for (var idx = 0; idx < items.length; idx++) {
      final item = items[idx];
      try {
        final isElaboradoOrServicio =
            item.producto.esElaborado || item.producto.esServicio;

        if (isElaboradoOrServicio) {
          print(
            '🍽️ Verificando ingredientes para producto elaborado/servicio: ${item.nombre} (offline=$isOfflineMode)',
          );

          if (isOfflineMode) {
            // OFFLINE: buscar receta del elaborado en cache
            final offlineData = await _userPreferencesService.getOfflineData();
            final productsData =
                offlineData?['products'] as Map<String, dynamic>?;
            List<dynamic>? ingredientesCache;

            if (productsData != null) {
              outer:
              for (final categoryProducts in productsData.values) {
                for (final prodDataRaw in List<dynamic>.from(
                  categoryProducts as List,
                )) {
                  final prodData = Map<String, dynamic>.from(
                    prodDataRaw as Map,
                  );
                  if ((prodData['id'] as int?) != item.producto.id) continue;
                  final detalles =
                      prodData['detalles_completos'] as Map<String, dynamic>?;
                  ingredientesCache =
                      detalles?['ingredientes'] as List<dynamic>?;
                  break outer;
                }
              }
            }

            if (ingredientesCache == null || ingredientesCache.isEmpty) {
              print(
                '⚠️ Elaborado/servicio ${item.nombre} sin receta en cache offline, se permite continuar',
              );
              continue;
            }

            for (final ingRaw in ingredientesCache) {
              final ing = Map<String, dynamic>.from(ingRaw as Map);
              final idIngrediente = ing['producto_id'] as int?;
              if (idIngrediente == null) continue;

              final cantidadNecesaria =
                  ((ing['cantidad_necesaria'] as num?)?.toDouble() ?? 0.0) *
                  item.cantidad;
              final nombreIngrediente =
                  ing['producto_nombre'] as String? ??
                  'Ingrediente desconocido';

              final stockIngrediente = await _getStockFromCache(
                idProducto: idIngrediente,
              );
              final cantidadDisponible = stockIngrediente ?? 0.0;

              if (cantidadDisponible < cantidadNecesaria) {
                final unidadIngrediente = _unidadDeIngrediente(ing);
                problems.add({
                  'nombre': '${item.nombre} → $nombreIngrediente',
                  'cantidad_pedida': cantidadNecesaria,
                  'stock_disponible': cantidadDisponible,
                  'diferencia': cantidadNecesaria - cantidadDisponible,
                  'ubicacion': item.ubicacionAlmacen,
                  'unidad': unidadIngrediente,
                  // Fuera de línea no hay almacén de venta resoluble: el dato
                  // viene del cache y se etiqueta como tal (task-12).
                  'alcance_stock': ProductDetailService.alcanceCacheOffline,
                  'presentacion':
                      ' (ingrediente • cache offline${unidadIngrediente.isEmpty ? '' : ' • $unidadIngrediente'})',
                });
              }
            }
          } else {
            // ONLINE: verificar stock de cada ingrediente en Supabase
            //
            // task-12 (FASE 7 P1): el servidor valida con UN almacén, resuelto
            // por `fn_resolver_origen_venta(elaborado, tpv)` — el mismo origen
            // que usa la venta (order_service manda solo `p_id_tpv` y el
            // servidor resuelve la ruta, barra o cocina). Se mide con el mismo
            // almacén para no sobreestimar y provocar un bloqueo confuso del
            // servidor. Si no se resuelve con certeza, `idAlmacen` va null, se
            // mide con todos los almacenes y cada ingrediente queda etiquetado
            // como tal (`alcance_stock`).
            // Un servicio puro no tiene receta que medir (`fn_resolver_origen_venta`
            // devolvería `descontar: nada`): no se resuelve la ruta y se ahorra
            // una RPC por item.
            final idAlmacenVenta =
                (item.producto.esServicio && !item.producto.esElaborado)
                    ? null
                    : await _almacenVentaCached(item.producto.id);
            final ingredientes = await _ingredientesCached(
              item.producto.id,
              idAlmacen: idAlmacenVenta,
            );

            if (ingredientes.isEmpty) {
              print(
                '⚠️ Producto elaborado/servicio ${item.nombre} sin ingredientes definidos, se permite continuar',
              );
              continue;
            }

            for (final ingrediente in ingredientes) {
              final idIngrediente = ingrediente['producto_id'] as int?;
              final cantidadNecesaria =
                  ((ingrediente['cantidad_necesaria'] as num?)?.toDouble() ??
                      0.0) *
                  item.cantidad;
              // FASE 7 P0/P1: `cantidad_disponible` ya es el EQUIVALENTE BASE
              // (Σ cantidad_final × factor_rel de las presentaciones vigentes
              // del alcance medido), calculado por `getProductIngredients`; por
              // eso se compara directamente contra `cantidad_necesaria`, que la
              // receta trae en unidades base. Antes esto comparaba una sola fila
              // del ledger (p. ej. 2000 Unidad) contra 6000 base y bloqueaba la
              // venta. Ver docs/PLAN_CONSUMO_INGREDIENTES_ELABORADOS_PRESENTACIONES.md §0.
              final cantidadDisponible =
                  (ingrediente['cantidad_disponible'] as num?)?.toDouble() ??
                  0.0;
              final nombreIngrediente =
                  ingrediente['producto_nombre'] as String? ??
                  'Ingrediente desconocido';
              final unidadIngrediente = _unidadDeIngrediente(ingrediente);

              if (idIngrediente == null) continue;

              if (cantidadDisponible < cantidadNecesaria) {
                problems.add({
                  'nombre': '${item.nombre} → $nombreIngrediente',
                  'cantidad_pedida': cantidadNecesaria,
                  'stock_disponible': cantidadDisponible,
                  'diferencia': cantidadNecesaria - cantidadDisponible,
                  'ubicacion': item.ubicacionAlmacen,
                  'unidad': unidadIngrediente,
                  // task-12: con qué alcance se midió (almacén del TPV,
                  // todos los almacenes o desconocido). La UI lo etiqueta.
                  'id_almacen': ingrediente['id_almacen'],
                  'alcance_stock': ingrediente['alcance_stock'],
                  'presentacion':
                      ' (ingrediente${unidadIngrediente.isEmpty ? '' : ' • $unidadIngrediente'})',
                });
              }
            }
          }
        } else {
          // Para productos normales: verificar directamente en inventario
          final idProducto = item.producto.id;
          final idUbicacion = item.inventoryData?['id_ubicacion'] as int?;
          final idVariante = item.inventoryData?['id_variante'] as int?;
          final idPresentacion = item.inventoryData?['id_presentacion'] as int?;

          // Items de cuenta que YA descontaron inventario al pedirse
          // (fn_pedir_item_cuenta, stock_movido=true): el cobro no vuelve a
          // mover stock, así que no hay nada que verificar.
          final stockMovidoAlPedir =
              item.inventoryData?['stock_movido'] == true;
          if (stockMovidoAlPedir) {
            print(
              '✅ ${item.nombre}: stock ya descontado al pedir (cuenta de mesa), '
              'se omite verificación de inventario',
            );
            continue;
          }

          double stockActual = 0.0;
          String origenStock = 'Supabase';
          int? idUbicacionResuelta = idUbicacion;

          if (isOfflineMode) {
            // OFFLINE: leer desde cache, fallback a cantidadInicial / producto
            final stockCache = await _getStockFromCache(
              idProducto: idProducto,
              idUbicacion: idUbicacion,
              idVariante: idVariante,
              idPresentacion: idPresentacion,
            );

            if (stockCache != null) {
              stockActual = stockCache;
              origenStock = 'cache offline';
              print(
                '🔌 Stock offline desde cache para ${item.nombre}: $stockActual',
              );
            } else {
              stockActual =
                  item.cantidadInicial ?? item.producto.cantidad.toDouble();
              origenStock = 'snapshot/listado';
              print(
                '🔌 Stock offline fallback para ${item.nombre}: $stockActual',
              );
            }
          } else {
            final response =
                await (stockFilaFutures[idx] ?? _consultarStockFila(item));

            if (response.isNotEmpty) {
              stockActual =
                  (response.first['cantidad_final'] as num?)?.toDouble() ?? 0.0;
              // Resolución de ubicación idéntica a fn_registrar_venta_v2:
              // última fila (mayor id) de producto+presentación. Sin esto,
              // items de mesa sin id_ubicacion no podían evaluar el desarme.
              idUbicacionResuelta =
                  (response.first['id_ubicacion'] as num?)?.toInt();
            }
          }

          List<PresentacionLocal>? cadenaEvaluada;
          if (stockActual < item.cantidad) {
            // Desarme de bultos: el saldo propio de la presentación no alcanza,
            // pero el total convertible (abriendo empaques mayores) sí.
            // - Online: se consulta fn_preview_rebalanceo (misma regla que
            //   usará la venta: fn_rebalancear_presentaciones).
            // - Offline: se evalúa con el resolutor local sobre el cache.
            // Si la evaluación falla, se conserva el problema original: el
            // error real lo reportará la venta al sincronizar.
            var cubreConDesarme = false;
            var desarmeEvaluado = false;

            if (isOfflineMode) {
              try {
                final datos = await _cadenaYStocksOffline(item.producto.id);
                if (datos != null) {
                  cadenaEvaluada = datos.cadena;
                  cubreConDesarme = _cubreConPozoCompartido(
                    cadena: datos.cadena,
                    stocks: datos.stocks,
                    idPresentacionPedida: idPresentacion,
                    cantidadPedida: item.cantidad,
                    reservadoBase:
                        reservadoBasePorProducto[item.producto.id] ?? 0,
                  );
                  desarmeEvaluado = true;
                }
              } catch (e) {
                print(
                  '⚠️ Evaluación local de desarme falló para ${item.nombre}: $e',
                );
              }
            } else if (idUbicacionResuelta != null &&
                // El preview evalúa UNA línea contra la BD sin saber qué
                // otras líneas de la orden ya reservaron stock. Con varias
                // líneas del mismo producto manda el pozo local.
                !productosMultilinea.contains(idProducto)) {
              try {
                final preview = await supabase.rpc(
                  'fn_preview_rebalanceo',
                  params: {
                    'p_id_producto': idProducto,
                    'p_id_ubicacion': idUbicacionResuelta,
                    'p_id_presentacion': idPresentacion,
                    'p_cantidad': item.cantidad,
                    'p_id_variante': idVariante,
                    'p_id_opcion_variante':
                        item.inventoryData?['id_opcion_variante'] as int?,
                  },
                );
                final estrategia =
                    preview is Map ? preview['estrategia']?.toString() : null;
                // 'abrir' = desarmar bultos; 'empaquetar' = juntar unidades
                // en la presentación pedida (vender Caja teniendo Latas).
                cubreConDesarme =
                    estrategia == 'abrir' || estrategia == 'empaquetar';
                desarmeEvaluado = true;
                if (cubreConDesarme) {
                  print(
                    '📦 ${item.nombre}: saldo propio $stockActual < '
                    '${item.cantidad} pero el desarme de bultos lo cubre',
                  );
                }
              } catch (e) {
                print('⚠️ fn_preview_rebalanceo falló para ${item.nombre}: $e');
              }
            }

            // Fallback online: el preview no se pudo evaluar (item de cuenta
            // sin id_ubicacion/id_presentacion, o RPC falló). Se evalúa
            // localmente con cadena+stocks frescos de get_detalle_producto,
            // que ya incluye la fila base aunque esté en cero.
            if (!desarmeEvaluado && idProducto != null && !isOfflineMode) {
              try {
                final datos = await _cadenaYStocksOnline(idProducto);
                if (datos != null) {
                  cadenaEvaluada = datos.cadena;
                  cubreConDesarme = _cubreConPozoCompartido(
                    cadena: datos.cadena,
                    stocks: datos.stocks,
                    idPresentacionPedida: idPresentacion,
                    cantidadPedida: item.cantidad,
                    reservadoBase:
                        reservadoBasePorProducto[item.producto.id] ?? 0,
                  );
                }
              } catch (e) {
                print(
                  '⚠️ Evaluación local (online fallback) falló para ${item.nombre}: $e',
                );
              }
            }

            if (!cubreConDesarme) {
              final presentacionInfo =
                  idPresentacion != null
                      ? ' (Presentación ID: $idPresentacion • $origenStock)'
                      : ' ($origenStock)';
              problems.add({
                'nombre': item.nombre,
                'cantidad_pedida': item.cantidad,
                'stock_disponible': stockActual,
                'diferencia': item.cantidad - stockActual,
                'ubicacion': item.ubicacionAlmacen,
                'presentacion': presentacionInfo,
              });
            }
          }

          // Esta línea ya comprometió unidades base del pozo del producto
          // para las siguientes líneas de la orden (todas las
          // presentaciones comparten el mismo stock convertible).
          var factorRes = item.presentacionFactor ?? 1.0;
          final c = cadenaEvaluada;
          if (c != null && idPresentacion != null) {
            for (final p in c) {
              if (p.idPresentacion == idPresentacion) {
                factorRes = p.factorRel;
                break;
              }
            }
          }
          reservadoBasePorProducto[idProducto] =
              (reservadoBasePorProducto[idProducto] ?? 0) +
              item.cantidad * factorRes;
        }
      } catch (e) {
        print('⚠️ Error verificando stock para ${item.nombre}: $e');
        if (_isNetworkError(e)) {
          throw _StockCheckNetworkException(item.nombre, e);
        }
      }
    }

    return problems;
  }

  /// Última fila de inventario (saldo propio) de la línea: producto +
  /// ubicación + presentación, mayor `id`. Misma resolución que la venta.
  Future<List<Map<String, dynamic>>> _consultarStockFila(OrderItem item) async {
    final idUbicacion = item.inventoryData?['id_ubicacion'] as int?;
    final idPresentacion = item.inventoryData?['id_presentacion'] as int?;
    var query = Supabase.instance.client
        .from('app_dat_inventario_productos')
        .select('cantidad_final, id_ubicacion')
        .eq('id_producto', item.producto.id);

    if (idUbicacion != null) query = query.eq('id_ubicacion', idUbicacion);
    // NOTA: NO filtramos por id_variante. Los items provenientes de la vista de
    // mesa pueden traer id_variante=1 (ID secuencial generado en el cliente, no
    // un id real de DB). En el inventario real `id_variante` es null para estos
    // productos, así que filtrar por ese valor sintético devuelve 0 filas.
    if (idPresentacion != null) {
      query = query.eq('id_presentacion', idPresentacion);
    }

    final response = await query.order('id', ascending: false).limit(1);
    return List<Map<String, dynamic>>.from(response);
  }

  /// true si la cantidad pedida entra en el pozo compartido del producto:
  /// todo el stock convertible (todas las presentaciones en unidades base)
  /// menos lo ya reservado por líneas previas de esta orden.
  ///
  /// Sin cadena o con presentación desconocida cae al evaluador de desarme
  /// clásico para no bloquear de más.
  bool _cubreConPozoCompartido({
    required List<PresentacionLocal> cadena,
    required Map<int, double> stocks,
    required int? idPresentacionPedida,
    required double cantidadPedida,
    required double reservadoBase,
  }) {
    if (idPresentacionPedida != null) {
      final disp =
          DesarmeBultoLocal.disponiblesPorPresentacion(
            cadena: cadena,
            stocks: stocks,
            reservadoBase: reservadoBase,
          )[idPresentacionPedida];
      if (disp != null) return cantidadPedida <= disp.disponible;
    }
    final eval = DesarmeBultoLocal.evaluar(
      cadena: cadena,
      stocks: stocks,
      idPresentacionPedida: idPresentacionPedida ?? 0,
      cantidadPedida: cantidadPedida,
    );
    return eval.requiereDesarme || eval.alcanza;
  }

  /// Unidad/presentación que se muestra en los carteles de ingredientes.
  ///
  /// FASE 7 P0: la receta del caso real trae `unidad_medida = null`, así que la
  /// unidad sale de la presentación base que resolvió `getProductIngredients`
  /// (`presentacion_base`). Nunca se muestra una cadena vacía si hay base.
  String _unidadDeIngrediente(Map<String, dynamic> ingrediente) {
    final unidad = (ingrediente['unidad_medida'] as String?)?.trim() ?? '';
    if (unidad.isNotEmpty) return unidad;
    return (ingrediente['presentacion_base'] as String?)?.trim() ?? '';
  }

  /// Almacén con el que la VENTA va a validar/descontar este elaborado.
  ///
  /// task-12 (FASE 7 P1): el servidor no recibe el almacén desde la app
  /// (`order_service` manda solo `p_id_tpv`), lo resuelve con
  /// `fn_resolver_origen_venta(elaborado, tpv)` —barra o cocina—. Se usa esa
  /// misma función para medir el ingrediente en el mismo almacén y que el
  /// cartel no sobreestime.
  ///
  /// Devuelve `null` si no se puede resolver **con certeza** (sin TPV en prefs,
  /// ruta con error o RPC no disponible): en ese caso la medición se hace con
  /// todos los almacenes y se etiqueta como tal. Preferimos sobreestimar —y que
  /// el servidor bloquee— antes que bloquear en falso midiendo el almacén
  /// equivocado (p. ej. una ruta de cocina).
  ///
  /// `SECURITY DEFINER` + `SET search_path = public` + grant a `authenticated`:
  /// es de solo lectura y no depende del guard (no le afecta C9).
  Future<int?> _resolverAlmacenDeVenta(int idProductoElaborado) async {
    try {
      final idTpv = await _userPreferencesService.getIdTpv();
      if (idTpv == null) {
        debugPrint('⚠️ Sin TPV en prefs: no se puede resolver el almacén');
        return null;
      }

      final ruta = await Supabase.instance.client.rpc(
        'fn_resolver_origen_venta',
        params: {'p_id_producto': idProductoElaborado, 'p_id_tpv': idTpv},
      );
      if (ruta is! Map) return null;

      final mapa = Map<String, dynamic>.from(ruta);
      if (mapa['status']?.toString() != 'success') {
        debugPrint(
          '⚠️ fn_resolver_origen_venta sin ruta para $idProductoElaborado: '
          '${mapa['error_code'] ?? mapa['message']}',
        );
        return null;
      }

      final idAlmacen = (mapa['id_almacen'] as num?)?.toInt();
      if (idAlmacen == null || idAlmacen <= 0) return null;
      debugPrint(
        '🏬 Elaborado $idProductoElaborado: almacén de venta $idAlmacen '
        '(origen=${mapa['origen']})',
      );
      return idAlmacen;
    } catch (e) {
      debugPrint(
        '⚠️ fn_resolver_origen_venta falló para $idProductoElaborado: $e',
      );
      return null;
    }
  }

  /// Texto humano del alcance con el que se midió un ingrediente (task-12).
  ///
  /// Devuelve `null` si el dato no trae alcance (productos no elaborados), para
  /// no añadir ruido al cartel.
  String? _etiquetaAlcanceStock(Map<String, dynamic> datos) {
    final alcance = datos['alcance_stock']?.toString();
    if (alcance == null || alcance.isEmpty) return null;
    if (alcance == ProductDetailService.alcanceAlmacenTpv) {
      return 'almacén del TPV';
    }
    if (alcance == ProductDetailService.alcanceTodosLosAlmacenes) {
      return 'todos los almacenes';
    }
    if (alcance == ProductDetailService.alcanceCacheOffline) {
      return 'cache offline';
    }
    if (alcance == ProductDetailService.alcanceTienda) {
      // Reservado para la decisión de alcance «tienda» (Fase 5).
      return 'toda la tienda';
    }
    return 'alcance no determinado';
  }

  bool _isNetworkError(Object error) {
    if (error is SocketException) return true;
    if (error is TimeoutException) return true;
    if (error is HttpException) return true;
    final msg = error.toString().toLowerCase();
    return msg.contains('socketexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('connection closed') ||
        msg.contains('connection refused') ||
        msg.contains('connection reset') ||
        msg.contains('network is unreachable') ||
        msg.contains('clientexception') ||
        msg.contains('timeoutexception') ||
        msg.contains('xmlhttprequest error');
  }

  /// Muestra diálogo cuando la verificación de stock falla por problemas de red
  void _showStockNetworkErrorDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(VentiqHomeTheme.radiusBlock),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: VentiqHomeTheme.warning.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.wifi_off_rounded,
                    color: VentiqHomeTheme.warning,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Sin conexión',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: VentiqHomeTheme.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            content: const Text(
              'No se pudo verificar el stock disponible porque hay un problema de conexión con el servidor.\n\nRevisa tu conexión a internet e inténtalo de nuevo.',
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: VentiqHomeTheme.textSecondary,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Entendido'),
              ),
            ],
          ),
    );
  }

  /// Muestra diálogo con los problemas de stock encontrados
  void _showStockProblemsDialog(List<Map<String, dynamic>> problems) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(VentiqHomeTheme.radiusBlock),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: VentiqHomeTheme.warning.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.inventory_2_outlined,
                    color: VentiqHomeTheme.warning,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Problema de Inventario',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: VentiqHomeTheme.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Los siguientes productos no tienen suficiente existencia:',
                    style: TextStyle(
                      fontSize: 13.5,
                      color: VentiqHomeTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...problems.map((p) {
                    final cantPedida = (p['cantidad_pedida'] as double);
                    final stock = (p['stock_disponible'] as double);
                    final diff = (p['diferencia'] as double);
                    // FASE 7 P0/P1: la unidad/presentación de los números y el
                    // alcance real de la medición. En elaborados son unidades
                    // base del ingrediente (p. ej. "Unidad"); sale de la
                    // presentación base cuando la receta trae
                    // `unidad_medida = null`. Si el almacén del TPV no se pudo
                    // resolver, se dice "todos los almacenes" (task-12).
                    final unidad = (p['unidad'] as String?)?.trim() ?? '';
                    final etiquetaAlcance = _etiquetaAlcanceStock(p);
                    final nota = <String>[
                      if (unidad.isNotEmpty) 'Unidad base: $unidad',
                      if (etiquetaAlcance != null) etiquetaAlcance,
                    ].join(' · ');
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: VentiqHomeTheme.danger.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: VentiqHomeTheme.danger.withValues(alpha: 0.22),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p['nombre'] as String,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: VentiqHomeTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: _buildStockChip(
                                  'Pedido',
                                  cantPedida,
                                  VentiqHomeTheme.primary,
                                  VentiqHomeTheme.primary.withValues(
                                    alpha: 0.08,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: _buildStockChip(
                                  'En stock',
                                  stock,
                                  VentiqHomeTheme.success,
                                  VentiqHomeTheme.success.withValues(
                                    alpha: 0.08,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: _buildStockChip(
                                  'Faltante',
                                  diff,
                                  VentiqHomeTheme.danger,
                                  VentiqHomeTheme.danger.withValues(
                                    alpha: 0.08,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (nota.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              nota,
                              style: const TextStyle(
                                fontSize: 11,
                                color: VentiqHomeTheme.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Revisar Orden'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: VentiqHomeTheme.warning,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Entendido'),
              ),
            ],
          ),
    );
  }

  Widget _buildStockChip(
    String label,
    double value,
    Color textColor,
    Color bgColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(VentiqHomeTheme.radiusChip),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value % 1 == 0
                ? value.toInt().toString()
                : value.toStringAsFixed(2),
            style: TextStyle(
              fontSize: 13,
              color: textColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  /// Crea la orden directamente sin pasar por CheckoutScreen (cuando no_solicitar_cliente=true)
  Future<void> _submitOrderDirect(Order order, {bool offline = false}) async {
    setState(() {
      _elaboratingProducts = true;
    });

    try {
      final Map<String, double> paymentBreakdownSimple = {};
      for (final item in order.items) {
        if (item.paymentMethod != null) {
          final methodName = item.paymentMethod!.denominacion;
          paymentBreakdownSimple[methodName] =
              (paymentBreakdownSimple[methodName] ?? 0.0) + item.subtotal;
        }
      }

      final orderData = {
        'buyerName': 'Cliente',
        'buyerPhone': '',
        'extraContacts': '',
        'paymentMethod': 'Múltiples métodos',
        'promoCode': null,
        'promoDiscount': 0.0,
        'finalTotal': order.total,
        'originalTotal': order.total,
        'idCliente': null,
        'paymentBreakdown': paymentBreakdownSimple,
      };

      final updatedOrder = order.copyWith(
        total: order.total,
        buyerName: 'Cliente',
        buyerPhone: '',
        paymentMethod: 'Múltiples métodos',
      );

      // Full offline / modo offline: guardar pendiente local, sin RPC.
      final useOffline =
          offline ||
          await _userPreferencesService.shouldStayFullyOffline() ||
          await _userPreferencesService.isOfflineModeEnabled();

      if (useOffline) {
        await _submitOrderOfflineDirect(updatedOrder);
        return;
      }

      final result = await _orderService.finalizeOrderWithDetails(
        updatedOrder,
        orderData,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        final operationId = result['operationId'];
        final createdOrderId = operationId != null ? 'ORD-$operationId' : null;

        // Update the order ID in the cache with the operationId from Supabase
        if (createdOrderId != null) {
          _orderService.updateOrderIdInCache(updatedOrder.id, createdOrderId);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Orden registrada exitosamente!'),
            backgroundColor: VentiqHomeTheme.success,
            duration: Duration(seconds: 2),
          ),
        );
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => OrdersScreen(autoOpenOrderId: createdOrderId),
          ),
          (route) => false,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al registrar la venta: ${result['error']}'),
            backgroundColor: VentiqHomeTheme.danger,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al crear la orden: $e'),
          backgroundColor: VentiqHomeTheme.danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _elaboratingProducts = false;
        });
      }
    }
  }

  /// Persiste la orden localmente (mismo formato que CheckoutScreen offline).
  Future<void> _submitOrderOfflineDirect(Order order) async {
    final userData = await _userPreferencesService.getUserData();
    final idTienda = await _userPreferencesService.getIdTienda();
    final idTpv = await _userPreferencesService.getIdTpv();
    final idSeller = await _userPreferencesService.getIdSeller();

    final offlineOrderId = '${DateTime.now().millisecondsSinceEpoch}';
    final clientUuid = UuidGenerator.v4();

    double subtotal = 0.0;
    final paymentBreakdown = <String, Map<String, dynamic>>{};

    for (final item in order.items) {
      final itemTotal = item.subtotal;
      subtotal += itemTotal;
      final paymentMethodId = item.paymentMethod?.id.toString() ?? 'sin_metodo';
      if (!paymentBreakdown.containsKey(paymentMethodId)) {
        paymentBreakdown[paymentMethodId] = {
          'id_medio_pago': item.paymentMethod?.id,
          'denominacion': item.paymentMethod?.denominacion ?? 'Sin método',
          'monto': 0.0,
          // Explícito a propósito: la preorden no ofrece selección de moneda,
          // así que sus líneas son en CUP. Sin declararlo, el sincronizador
          // tendría que adivinarlo y una divisa nueva se leería como CUP.
          'moneda': 'CUP',
          'es_digital': item.paymentMethod?.esDigital ?? false,
          'es_efectivo': item.paymentMethod?.esEfectivo ?? false,
        };
      }
      paymentBreakdown[paymentMethodId]!['monto'] =
          (paymentBreakdown[paymentMethodId]!['monto'] as double) + itemTotal;
    }

    // Hora corregida contra el servidor (ver ServerTimeService) para que
    // fecha_creacion no quede desfasada por un reloj de dispositivo mal
    // ajustado, y así la orden se siga asociando al turno correcto.
    final nowServerCorrected = ServerTimeService().now();

    final pending = {
      'id': offlineOrderId,
      'client_uuid': clientUuid,
      'id_tienda': idTienda,
      'id_tpv': idTpv,
      'id_vendedor': idSeller,
      'id_usuario': userData['userId'],
      'fecha_creacion': nowServerCorrected.toIso8601String(),
      'subtotal': subtotal,
      'total_descuentos': 0.0,
      'total': subtotal,
      'estado': 'pendiente_sincronizacion',
      'estado_final': 'completada',
      'is_pending_sync': true,
      'created_offline_at': nowServerCorrected.toIso8601String(),
      'buyer_name': order.buyerName ?? 'Cliente',
      'buyer_phone': order.buyerPhone ?? '',
      'extra_contacts': '',
      'items': await Future.wait(
        order.items.map((item) async {
          final ingredientes = await ProductRecipeCacheService()
              .snapshotIngredientsForItem(item);
          return {
            'id_producto': item.producto.id,
            'denominacion': item.producto.denominacion,
            'cantidad': item.cantidad,
            'precio_unitario': item.precioUnitario,
            'subtotal': item.subtotal,
            'id_medio_pago': item.paymentMethod?.id,
            'metodo_pago': item.paymentMethod?.denominacion,
            'inventory_metadata': item.inventoryData,
            'es_elaborado': item.producto.esElaborado,
            'es_servicio': item.producto.esServicio,
            if (ingredientes != null) 'ingredientes': ingredientes,
            // FASE 4: igual que en checkout_screen — la cantidad está en la
            // presentación elegida, así que la preorden pendiente debe llevarla.
            'id_presentacion': item.idPresentacion,
            'presentacion_nombre': item.presentacionNombre,
            'presentacion_factor': item.presentacionFactor,
          };
        }),
      ),
      'desglose_pagos': paymentBreakdown.values.toList(),
    };

    final openTurno = await _userPreferencesService.getOfflineTurno();
    final localTurnoId =
        openTurno?['local_id']?.toString() ??
        openTurno?['local_turno_id']?.toString();
    if (localTurnoId != null) {
      pending['local_turno_id'] = localTurnoId;
    }

    await _userPreferencesService.savePendingOrder(pending);

    for (final item in order.items) {
      if (item.producto.esElaborado || item.producto.esServicio) continue;
      final inventoryMetadata = item.inventoryData;
      if (inventoryMetadata != null) {
        // FASE 5: igual que en checkout_screen — delta por presentación y sin
        // truncar la cantidad.
        await _userPreferencesService.updateProductInventoryInCache(
          item.producto.id,
          (inventoryMetadata['id_variante'] as num?)?.toInt(),
          item.cantidad,
          inventoryId: (inventoryMetadata['id_inventario'] as num?)?.toInt(),
          locationId: (inventoryMetadata['id_ubicacion'] as num?)?.toInt(),
          presentationId:
              item.idPresentacion ??
              (inventoryMetadata['id_presentacion'] as num?)?.toInt(),
        );
      } else {
        await _userPreferencesService.updateProductInventoryInCache(
          item.producto.id,
          null,
          item.cantidad,
          presentationId: item.idPresentacion,
        );
      }
    }

    _orderService.cancelCurrentOrder();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          '¡Orden offline creada exitosamente!\nSe sincronizará cuando tengas conexión.',
        ),
        backgroundColor: VentiqHomeTheme.success,
        duration: Duration(seconds: 2),
      ),
    );
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => OrdersScreen(autoOpenOrderId: offlineOrderId),
      ),
      (route) => false,
    );
  }

  /// Procesa productos elaborados en la orden
  ///
  /// [permiteVenderSinDisponibilidad]: si el llamador ya cargó la
  /// configuración de tienda, se pasa aquí y no se vuelve a pedir.
  Future<void> _processElaboratedProducts(
    Order order, {
    bool? permiteVenderSinDisponibilidad,
  }) async {
    try {
      setState(() {
        _elaboratingProducts = true;
      });

      // Verificar si hay productos elaborados en la orden
      // El flag ya viene en el producto (catálogo/sync): antes se hacía un
      // SELECT a app_dat_producto por cada item de la orden.
      final productosElaborados = <Map<String, dynamic>>[];
      for (final item in order.items) {
        final productId = item.producto.id;
        final isElaborated =
            item.producto.esElaborado || item.producto.esServicio;
        if (isElaborated) {
          productosElaborados.add({
            'id_producto': productId,
            'cantidad': item.cantidad,
            'nombre': item.nombre,
          });
        }
      }

      // Si no hay productos elaborados, salir temprano
      if (productosElaborados.isEmpty) {
        debugPrint(
          '✅ No hay productos elaborados en la orden - saltando proceso',
        );
        return;
      }

      debugPrint(
        '🔍 Productos elaborados encontrados: ${productosElaborados.length}',
      );

      // Diálogo de carga.
      //
      // Antes decía "Elaborando productos... / Descomponiendo ingredientes y
      // verificando stock": jerga interna del modelo de datos que al vendedor no
      // le dice nada y encima es engañosa (aquí no se elabora nada, se comprueba
      // stock). Se sustituye por un "Procesando venta" neutro y más limpio.
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 24,
                ),
                decoration: BoxDecoration(
                  color: VentiqHomeTheme.card,
                  borderRadius: BorderRadius.circular(
                    VentiqHomeTheme.radiusBlock,
                  ),
                  boxShadow: VentiqHomeTheme.shadowBuscador,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          VentiqHomeTheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Procesando venta',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: VentiqHomeTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Un momento...',
                      style: TextStyle(
                        fontSize: 12,
                        color: VentiqHomeTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );

      // Verificar disponibilidad de ingredientes solo en modo ONLINE y si la configuración lo requiere
      final isOfflineModeEnabled =
          await _userPreferencesService.isOfflineModeEnabled();

      if (!isOfflineModeEnabled) {
        debugPrint('🌐 Modo online - Verificando configuración de tienda...');

        // Obtener ID de tienda
        final idTienda = await _userPreferencesService.getIdTienda();
        if (idTienda != null) {
          // Verificar configuración de tienda (reutiliza la ya cargada)
          final permiteSinDisp =
              permiteVenderSinDisponibilidad ??
              await StoreConfigService.getPermiteVenderAunSinDisponibilidad(
                idTienda,
              );

          if (permiteSinDisp) {
            debugPrint(
              '⚙️ Configuración permite vender sin disponibilidad - Saltando verificación de ingredientes',
            );
          } else {
            debugPrint(
              '⚙️ Configuración requiere verificar disponibilidad - Verificando ingredientes',
            );
            await _checkIngredientsAvailability(productosElaborados);
          }
        } else {
          debugPrint(
            '⚠️ No se pudo obtener ID de tienda - Verificando ingredientes por seguridad',
          );
          await _checkIngredientsAvailability(productosElaborados);
        }
      } else {
        debugPrint('🔌 Modo offline - Saltando verificación de disponibilidad');
      }

      // Convert order items to the format expected by decomposition functions
      final productos =
          order.items
              .map((item) {
                // Use the product ID from the Product object, not the OrderItem ID
                final productId = item.producto.id;
                debugPrint(
                  '🔄 Convirtiendo OrderItem - ID: ${item.id}, ProductoID: $productId, Nombre: ${item.nombre}',
                );
                return {
                  'id_producto': productId,
                  'cantidad': item.cantidad,
                  'nombre': item.nombre,
                  'precio_unitario': item.precioUnitario,
                  'es_elaborado':
                      item.producto.esElaborado || item.producto.esServicio,
                };
              })
              .where((producto) => producto['id_producto'] != 0)
              .toList();

      debugPrint(
        '🔄 Procesando ${productos.length} productos para elaboración',
      );

      // Log all products being processed
      for (final producto in productos) {
        debugPrint(
          '📋 Producto en orden: ID=${producto['id_producto']}, Nombre=${producto['nombre']}, Cantidad=${producto['cantidad']}',
        );
      }

      // Decompose elaborated products using the same logic as inventory service
      final productosDescompuestos = await _decomposeElaboratedProducts(
        productos,
      );

      debugPrint(
        '✅ Descomposición completada: ${productosDescompuestos.length} productos finales',
      );

      // Update the order with decomposed products for inventory management
      await _updateOrderWithDecomposedProducts(order, productosDescompuestos);

      // Show detailed results
      final elaboratedCount =
          productosDescompuestos
              .where((p) => p['producto_elaborado'] != null)
              .length;
      final simpleCount = productosDescompuestos.length - elaboratedCount;

      // Close loading dialog
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }

      // Show success message with details solo si hay productos elaborados
      if (elaboratedCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white),
                    const SizedBox(width: 8),
                    const Text('Productos elaborados procesados'),
                  ],
                ),
                if (elaboratedCount > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '🍽️ $elaboratedCount ingredientes de productos elaborados',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
                if (simpleCount > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '📦 $simpleCount productos simples',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ],
            ),
            backgroundColor: VentiqHomeTheme.success,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      // Close loading dialog if still open (solo si se mostró)
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }

      debugPrint('❌ Error procesando productos elaborados: $e');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text('Error procesando productos: $e')),
            ],
          ),
          backgroundColor: VentiqHomeTheme.danger,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      setState(() {
        _elaboratingProducts = false;
      });
    }
  }

  /// Descompone productos elaborados recursivamente (similar a inventory_service.dart)
  Future<List<Map<String, dynamic>>> _decomposeElaboratedProducts(
    List<Map<String, dynamic>> productos,
  ) async {
    final decomposedProducts = <Map<String, dynamic>>[];

    debugPrint('🔄 Descomponiendo productos elaborados...');

    for (final producto in productos) {
      final productId = producto['id_producto'] as int;
      final cantidadOriginal = (producto['cantidad'] as num).toDouble();

      debugPrint('🔄 Procesando producto ID: $productId');
      debugPrint('🔄 Cantidad original: $cantidadOriginal');
      debugPrint('🔄 Nombre producto: ${producto['nombre']}');

      final isElaborated =
          producto['es_elaborado'] as bool? ??
          await _esElaboradoCached(productId);
      debugPrint(
        '🔄 Resultado isElaborated para producto $productId: $isElaborated',
      );

      if (isElaborated) {
        debugPrint('🔍 Producto $productId es elaborado');

        final consolidatedIngredients = <int, double>{};

        await _decomposeRecursively(
          productId,
          cantidadOriginal,
          consolidatedIngredients,
        );

        debugPrint('📦 Ingredientes consolidados:');
        for (final entry in consolidatedIngredients.entries) {
          debugPrint('   - ID: ${entry.key}, Cantidad: ${entry.value}');
        }

        // Create decomposed products for each ingredient
        for (final entry in consolidatedIngredients.entries) {
          final ingredientId = entry.key;
          final cantidad = entry.value;

          final ingredientProduct = Map<String, dynamic>.from(producto);
          ingredientProduct['id_producto'] = ingredientId;
          ingredientProduct['cantidad'] = cantidad;
          ingredientProduct['cantidad_original'] = cantidadOriginal;
          ingredientProduct['producto_elaborado'] = productId;
          ingredientProduct['conversion_applied'] = true;

          decomposedProducts.add(ingredientProduct);
        }
      } else {
        debugPrint(
          '🔄 Producto $productId NO es elaborado - agregando como simple',
        );
        // Add simple products as-is
        decomposedProducts.add(producto);
      }
    }

    debugPrint(
      '✅ Descomposición completada: ${decomposedProducts.length} productos',
    );
    return decomposedProducts;
  }

  /// Descompone un producto elaborado recursivamente
  Future<void> _decomposeRecursively(
    int productId,
    double quantity,
    Map<int, double> consolidatedIngredients,
  ) async {
    debugPrint('🔄 Descomponiendo producto $productId con cantidad $quantity');

    final ingredients = await _recetaCached(productId);
    // Una sola consulta para saber cuáles ingredientes son a su vez
    // elaborados (antes: un SELECT por ingrediente).
    await _precargarEsElaborado([
      for (final i in ingredients)
        if (i['producto_id'] is int) i['producto_id'] as int,
    ]);

    if (ingredients.isEmpty) {
      debugPrint(
        '⚠️ Producto $productId sin ingredientes - tratando como simple',
      );
      _addToConsolidated(consolidatedIngredients, productId, quantity);
      return;
    }

    for (final ingredient in ingredients) {
      final ingredientId = ingredient['producto_id'] as int;
      final cantidadNecesaria =
          (ingredient['cantidad_necesaria'] as num).toDouble();
      final totalQuantity = cantidadNecesaria * quantity;

      final isElaborated = await _esElaboradoCached(ingredientId);

      if (isElaborated) {
        await _decomposeRecursively(
          ingredientId,
          totalQuantity,
          consolidatedIngredients,
        );
      } else {
        _addToConsolidated(
          consolidatedIngredients,
          ingredientId,
          totalQuantity,
        );
      }
    }
  }

  /// Agrega cantidad a ingredientes consolidados
  void _addToConsolidated(
    Map<int, double> consolidatedIngredients,
    int productId,
    double quantity,
  ) {
    if (consolidatedIngredients.containsKey(productId)) {
      consolidatedIngredients[productId] =
          consolidatedIngredients[productId]! + quantity;
    } else {
      consolidatedIngredients[productId] = quantity;
    }
    debugPrint(
      '📦 Consolidado: Producto $productId -> ${consolidatedIngredients[productId]}',
    );
  }

  /// Actualiza la orden con los productos descompuestos para manejo de inventario
  Future<void> _updateOrderWithDecomposedProducts(
    Order order,
    List<Map<String, dynamic>> productosDescompuestos,
  ) async {
    debugPrint('🔄 Actualizando orden con productos descompuestos...');

    // Store the decomposed products in the order for later use by OrderService
    // This allows the OrderService to send both elaborated products (for sales record)
    // and their ingredients (for inventory deduction) to fn_registrar_venta

    final elaboratedProductsData = <String, dynamic>{};
    final ingredientsData = <Map<String, dynamic>>[];

    for (final producto in productosDescompuestos) {
      if (producto['producto_elaborado'] != null) {
        // This is an ingredient from an elaborated product
        ingredientsData.add({
          'id_producto': producto['id_producto'],
          'cantidad': producto['cantidad'],
          'producto_elaborado_id': producto['producto_elaborado'],
          'es_ingrediente': true,
        });

        // Group by elaborated product
        final elaboratedId = producto['producto_elaborado'].toString();
        if (!elaboratedProductsData.containsKey(elaboratedId)) {
          elaboratedProductsData[elaboratedId] = {
            'id_producto': producto['producto_elaborado'],
            'cantidad_original': producto['cantidad_original'],
            'ingredientes': <Map<String, dynamic>>[],
          };
        }
        elaboratedProductsData[elaboratedId]['ingredientes'].add({
          'id_producto': producto['id_producto'],
          'cantidad': producto['cantidad'],
        });
      }
    }

    // Store the decomposition data in the order for OrderService to use
    // This will be used when calling fn_registrar_venta
    for (final item in order.items) {
      final productId = item.producto.id;
      final elaboratedId = productId.toString();

      if (elaboratedProductsData.containsKey(elaboratedId)) {
        // Add decomposition metadata to the order item
        final decompositionData = {
          'es_elaborado': true,
          'ingredientes_descompuestos':
              elaboratedProductsData[elaboratedId]['ingredientes'],
          'requiere_descomposicion_inventario': true,
        };

        // Store in inventoryData or create a new field for this
        final currentInventoryData = item.inventoryData ?? {};
        currentInventoryData['decomposition_data'] = decompositionData;

        debugPrint(
          '📦 Producto elaborado ${item.nombre} actualizado con ${elaboratedProductsData[elaboratedId]['ingredientes'].length} ingredientes',
        );
      }
    }

    debugPrint('✅ Orden actualizada con datos de descomposición');
  }

  /// Control GLOBAL de medio de pago: una píldora por medio REAL de la tienda.
  ///
  /// Un toque aplica ese medio a TODAS las líneas (`_applyGlobalPaymentMethod`
  /// sigue siendo el mismo de siempre, no se toca la lógica de cobro). Si las
  /// líneas no comparten medio, no se resalta ninguna y el subtítulo lo dice:
  /// «Mixto · 2 Efectivo, 1 Transferencia». Con muchas píldoras la fila se
  /// desplaza en horizontal, así que el ancho del móvil nunca rompe.
  Widget _buildGlobalPaymentMethodSelector() {
    if (_loadingPaymentMethods) {
      return const SizedBox(
        height: 56,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_paymentMethods.isEmpty) return const SizedBox.shrink();

    final String? mezcla = _resumenMezcla();
    final bool hayGlobal = _globalPaymentMethod != null && mezcla == null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: VentiqHomeTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VentiqHomeTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'MEDIO DE PAGO',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                    color: VentiqHomeTheme.textSecondary,
                  ),
                ),
              ),
              if (_globalPaymentMethod != null)
                InkWell(
                  onTap: _clearGlobalPaymentMethod,
                  borderRadius: BorderRadius.circular(20),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 15,
                      color: VentiqHomeTheme.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            // Con mezcla se explica qué hay en vez de fingir un medio único.
            mezcla ?? 'Se aplica a todos los productos',
            style: TextStyle(
              fontSize: 11,
              fontWeight: mezcla != null ? FontWeight.w700 : FontWeight.w500,
              color:
                  mezcla != null
                      ? VentiqHomeTheme.warning
                      : VentiqHomeTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                for (final pm.PaymentMethod m in _paymentMethods) ...<Widget>[
                  _buildPillMedioGlobal(
                    m,
                    hayGlobal && _globalPaymentMethod?.id == m.id,
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Píldora de un medio en el control global (48 px de alto: cómodo al tacto).
  Widget _buildPillMedioGlobal(pm.PaymentMethod m, bool seleccionado) {
    final Color color =
        m.esEfectivo ? VentiqHomeTheme.success : VentiqHomeTheme.primary;
    return Material(
      color: seleccionado ? color : VentiqHomeTheme.card,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _applyGlobalPaymentMethod(m),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: seleccionado ? color : VentiqHomeTheme.border,
              width: seleccionado ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                m.typeIcon,
                size: 18,
                color: seleccionado ? Colors.white : color,
              ),
              const SizedBox(width: 8),
              Text(
                m.displayName,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color:
                      seleccionado ? Colors.white : VentiqHomeTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _applyGlobalPaymentMethod(pm.PaymentMethod? paymentMethod) {
    if (paymentMethod == null) return;

    setState(() {
      _globalPaymentMethod = paymentMethod;

      // Apply to all items in the current order
      final currentOrder = _orderService.currentOrder;
      if (currentOrder != null) {
        for (final item in currentOrder.items) {
          _orderService.updateItemPaymentMethod(item.id, paymentMethod);
        }
      }
    });
  }

  void _clearGlobalPaymentMethod() {
    setState(() {
      _globalPaymentMethod = null;
    });
  }

  /// Verifica la disponibilidad de ingredientes para productos elaborados
  ///
  /// FASE 7 P0: la comparación es en UNIDADES BASE (`cantidad_disponible` es el
  /// equivalente base que resuelve `getProductIngredients`; `cantidad_necesaria`
  /// es la cantidad de receta, también en base). La unidad mostrada sale de la
  /// presentación base cuando la receta trae `unidad_medida = null`.
  ///
  /// ⚠️ GATE DE RELEASE — NO PUBLICAR sin las Fases 0.5 + 1 + 3 en ambos
  /// proyectos (ver §0 del plan).
  ///
  /// task-12: se mide con el almacén que usará la venta
  /// (`fn_resolver_origen_venta`); si no se resuelve, con todos los almacenes y
  /// el alcance viaja en cada alerta para poder etiquetarlo.
  Future<void> _checkIngredientsAvailability(
    List<Map<String, dynamic>> productosElaborados,
  ) async {
    try {
      final ingredientesProximosAgotar = <Map<String, dynamic>>[];
      final ingredientesSinStock = <Map<String, dynamic>>[];

      for (final producto in productosElaborados) {
        final productId = producto['id_producto'] as int;
        final cantidadProducto = (producto['cantidad'] as num).toDouble();
        final nombreProducto = producto['nombre'] as String;

        final ingredientes = await _ingredientesCached(
          productId,
          idAlmacen: await _almacenVentaCached(productId),
        );

        for (final ingrediente in ingredientes) {
          final cantidadNecesaria =
              (ingrediente['cantidad_necesaria'] as num?)?.toDouble() ?? 0.0;
          final cantidadDisponible =
              (ingrediente['cantidad_disponible'] as num?)?.toDouble();
          final nombreIngrediente = ingrediente['producto_nombre'] as String;
          final unidadMedida = _unidadDeIngrediente(ingrediente);

          final cantidadTotalNecesaria = cantidadNecesaria * cantidadProducto;

          if (cantidadDisponible == null) {
            debugPrint(
              '⚠️ Ingrediente sin datos de inventario: $nombreIngrediente',
            );
            continue;
          }

          // Verificar si no hay stock suficiente (base vs base)
          if (cantidadDisponible < cantidadTotalNecesaria) {
            ingredientesSinStock.add({
              'nombre': nombreIngrediente,
              'producto': nombreProducto,
              'necesaria': cantidadTotalNecesaria,
              'disponible': cantidadDisponible,
              'unidad': unidadMedida,
              // task-12: alcance real de la medición (la UI lo etiqueta).
              'alcance_stock': ingrediente['alcance_stock'],
            });
          }
          // Verificar si está próximo a agotarse (menos del 20% extra de lo necesario)
          else if (cantidadDisponible < cantidadTotalNecesaria * 1.2) {
            ingredientesProximosAgotar.add({
              'nombre': nombreIngrediente,
              'producto': nombreProducto,
              'necesaria': cantidadTotalNecesaria,
              'disponible': cantidadDisponible,
              'unidad': unidadMedida,
              // task-12: alcance real de la medición (la UI lo etiqueta).
              'alcance_stock': ingrediente['alcance_stock'],
            });
          }
        }
      }

      // Mostrar alertas si hay problemas
      if (ingredientesSinStock.isNotEmpty) {
        _showStockAlert(
          title: '⚠️ Stock Insuficiente',
          message: 'Los siguientes ingredientes no tienen stock suficiente:',
          ingredientes: ingredientesSinStock,
          isError: true,
        );
      } else if (ingredientesProximosAgotar.isNotEmpty) {
        _showStockAlert(
          title: '⚡ Ingredientes Próximos a Agotarse',
          message: 'Los siguientes ingredientes están próximos a agotarse:',
          ingredientes: ingredientesProximosAgotar,
          isError: false,
        );
      }
    } catch (e) {
      debugPrint('❌ Error verificando disponibilidad de ingredientes: $e');
    }
  }

  /// Muestra alerta de stock de ingredientes
  void _showStockAlert({
    required String title,
    required String message,
    required List<Map<String, dynamic>> ingredientes,
    required bool isError,
  }) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(VentiqHomeTheme.radiusBlock),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (isError
                          ? VentiqHomeTheme.danger
                          : VentiqHomeTheme.warning)
                      .withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isError ? Icons.error_outline : Icons.warning_amber_rounded,
                  color:
                      isError
                          ? VentiqHomeTheme.danger
                          : VentiqHomeTheme.warning,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color:
                        isError
                            ? VentiqHomeTheme.danger
                            : VentiqHomeTheme.warning,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.35,
                    color: VentiqHomeTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                ...ingredientes.map((ing) {
                  final nombre = ing['nombre'] as String;
                  final producto = ing['producto'] as String;
                  final necesaria = ing['necesaria'] as double;
                  final disponible = ing['disponible'] as double;
                  final unidad = (ing['unidad'] as String?)?.trim() ?? '';
                  // task-12: alcance real de la medición; `null` si el dato no
                  // lo trae (no se inventa nada).
                  final etiquetaAlcance = _etiquetaAlcanceStock(ing);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (isError
                              ? VentiqHomeTheme.danger
                              : VentiqHomeTheme.warning)
                          .withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: (isError
                                ? VentiqHomeTheme.danger
                                : VentiqHomeTheme.warning)
                            .withValues(alpha: 0.22),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.inventory_2,
                              size: 16,
                              color:
                                  isError
                                      ? VentiqHomeTheme.danger
                                      : VentiqHomeTheme.warning,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                nombre,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color:
                                      isError
                                          ? VentiqHomeTheme.danger
                                          : VentiqHomeTheme.warning,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Para: $producto',
                          style: const TextStyle(
                            fontSize: 12,
                            color: VentiqHomeTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Necesario: ${necesaria.toStringAsFixed(2)} $unidad',
                              style: const TextStyle(
                                fontSize: 12,
                                color: VentiqHomeTheme.textPrimary,
                              ),
                            ),
                            Text(
                              'Disponible: ${disponible.toStringAsFixed(2)} $unidad',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color:
                                    isError
                                        ? VentiqHomeTheme.danger
                                        : VentiqHomeTheme.warning,
                              ),
                            ),
                          ],
                        ),
                        if (etiquetaAlcance != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Medido en: $etiquetaAlcance',
                            style: const TextStyle(
                              fontSize: 11,
                              color: VentiqHomeTheme.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Entendido'),
            ),
          ],
        );
      },
    );
  }

  void _onBottomNavTap(int index) {
    switch (index) {
      case 0: // Home → /mesas si modo restaurante, /categories si no
        NavigationHelper.goHome(context, removeStack: false);
        break;
      case 1: // Preorden (current)
        break;
      case 2: // Órdenes
        Navigator.pushNamed(context, '/orders');
        break;
      case 3: // Configuración
        Navigator.pushNamed(context, '/settings');
        break;
    }
  }
}

class _StockCheckNetworkException implements Exception {
  final String itemName;
  final Object original;
  _StockCheckNetworkException(this.itemName, this.original);

  @override
  String toString() => '_StockCheckNetworkException($itemName): $original';
}
