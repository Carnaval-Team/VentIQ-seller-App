import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ventiq_app/models/order.dart';
import 'package:ventiq_app/models/payment_method.dart' as pm;
import 'package:ventiq_app/services/order_service.dart';
import 'package:ventiq_app/services/product_detail_service.dart';
import 'package:ventiq_app/services/user_preferences_service.dart';
import 'package:ventiq_app/services/turno_service.dart';
import 'package:ventiq_app/services/payment_method_service.dart';
import 'package:ventiq_app/services/store_config_service.dart';
import 'package:ventiq_app/utils/price_utils.dart';
import 'package:ventiq_app/utils/app_snackbar.dart';
import 'package:ventiq_app/widgets/bottom_navigation.dart';
import 'package:ventiq_app/widgets/app_drawer.dart';
import 'package:ventiq_app/widgets/notification_widget.dart';
import 'package:ventiq_app/screens/checkout_screen.dart';

class PreorderWebScreen extends StatefulWidget {
  const PreorderWebScreen({Key? key}) : super(key: key);

  @override
  State<PreorderWebScreen> createState() => _PreorderWebScreenState();
}

class _PreorderWebScreenState extends State<PreorderWebScreen> {
  final OrderService _orderService = OrderService();
  final ProductDetailService _productDetailService = ProductDetailService();
  final UserPreferencesService _userPreferencesService = UserPreferencesService();
  List<pm.PaymentMethod> _paymentMethods = [];
  bool _loadingPaymentMethods = false;
  bool _checkingShift = true;
  bool _hasOpenShift = false;
  bool _elaboratingProducts = false;
  bool _noSolicitarCliente = false;
  pm.PaymentMethod? _globalPaymentMethod;
  final Map<String, TextEditingController> _qtyControllers = {};
  Timer? _qtyDebounceTimer;

  @override
  void initState() {
    super.initState();
    _loadPersistentPreorder();
    _checkOpenShift();
    _loadNoSolicitarCliente();
  }

  Future<void> _loadNoSolicitarCliente() async {
    final idTienda = await _userPreferencesService.getIdTienda();
    if (idTienda == null) return;
    final value = await StoreConfigService.getNoSolicitarCliente(idTienda);
    if (mounted && value != _noSolicitarCliente) {
      setState(() {
        _noSolicitarCliente = value;
      });
    }
  }

  @override
  void dispose() {
    _qtyDebounceTimer?.cancel();
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    _qtyControllers.clear();
    super.dispose();
  }

  /// Cargar preorden persistente al inicializar la pantalla
  Future<void> _loadPersistentPreorder() async {
    try {
      await _orderService.loadPersistentPreorder();
      print('📱 PreorderScreen: Preorden persistente cargada al inicializar');
    } catch (e) {
      print('❌ PreorderScreen: Error cargando preorden persistente: $e');
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
        print('✅ PreorderScreen: Turno encontrado, cargando métodos de pago...');
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
            title: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange,
                  size: 28,
                ),
                const SizedBox(width: 8),
                const Text('Turno Requerido'),
              ],
            ),
            content: const Text(
              'Debe tener un turno abierto para crear órdenes. Por favor, vaya a la sección de Apertura para abrir un turno.',
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pushReplacementNamed(context, '/apertura');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4A90E2),
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
      final isOfflineModeEnabled = await _userPreferencesService.isOfflineModeEnabled();
      
      List<pm.PaymentMethod> paymentMethods;
      
      if (isOfflineModeEnabled) {
        print('🔌 Modo offline - Cargando métodos de pago desde cache...');
        final paymentMethodsData = await _userPreferencesService.getPaymentMethodsOffline();
        paymentMethods = paymentMethodsData.map((data) => pm.PaymentMethod.fromJson(data)).toList();
        print('✅ Métodos de pago cargados desde cache offline: ${paymentMethods.length}');
      } else {
        print('🌐 Modo online - Cargando métodos de pago desde Supabase...');
        paymentMethods = await PaymentMethodService.getActivePaymentMethods();
        print('✅ Métodos de pago cargados desde Supabase: ${paymentMethods.length}');
      }
      
      // Agregar método especial "Pago Regular (Efectivo)" hardcoded
      final pagoRegularEfectivo = pm.PaymentMethod(
        id: 999, // ID especial para diferenciarlo
        denominacion: 'Pago Regular (Efectivo)',
        descripcion: 'Pago en efectivo sin descuento aplicado',
        esDigital: false,
        esEfectivo: true,
        esActivo: true,
      );
      
      // Agregar al inicio de la lista para que aparezca primero
      final methodsWithSpecial = [pagoRegularEfectivo, ...paymentMethods];
      
      setState(() {
        _paymentMethods = methodsWithSpecial;
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
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_hasOpenShift) {
      return Scaffold(body: Center(child: Text('No tiene un turno abierto')));
    }

    final currentOrder = _orderService.currentOrder;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A90E2),
        elevation: 1,
        shadowColor: const Color(0xFF4A90E2).withOpacity(0.25),
        toolbarHeight: 72,
        title: const Text(
          'Preorden Abierta',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        centerTitle: true,
        actions: [
          const NotificationWidget(),
          const SizedBox(width: 8),
          if (currentOrder != null && currentOrder.items.isNotEmpty)
            IconButton(
              icon: const Icon(
                Icons.clear_all,
                color: Colors.white,
                size: 26,
              ),
              onPressed: _showClearOrderDialog,
              tooltip: 'Limpiar orden',
            ),
          const SizedBox(width: 4),
          Builder(
            builder:
                (context) => IconButton(
                  icon: const Icon(Icons.menu, color: Colors.white, size: 28),
                  onPressed: () => Scaffold.of(context).openEndDrawer(),
                  tooltip: 'Menú',
                ),
          ),
          const SizedBox(width: 8),
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey[200]!),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4A90E2).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.shopping_cart_outlined,
                    size: 48,
                    color: Color(0xFF4A90E2),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'No hay productos en la preorden',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Agrega productos desde el catálogo para continuar con el pedido.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => _onBottomNavTap(0),
                  icon: const Icon(Icons.home),
                  label: const Text('Ir al Catálogo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4A90E2),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
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
        ),
      ),
    );
  }

  BoxDecoration _panelDecoration({double radius = 16}) {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Colors.grey[200]!),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.06),
          blurRadius: 18,
          offset: const Offset(0, 10),
        ),
      ],
    );
  }

  Widget _buildProductsPanel(Order order) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            title: 'Productos',
            badge: '${order.totalItems} item${order.totalItems == 1 ? '' : 's'}',
          ),
          const SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: order.items.length,
            itemBuilder: (context, index) {
              final item = order.items[index];
              return _buildOrderItem(item);
            },
            separatorBuilder: (context, index) => const SizedBox(height: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderContent(Order order) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1100;
        return isWide
            ? _buildWideOrderContent(order)
            : _buildNarrowOrderContent(order);
      },
    );
  }

  Widget _buildNarrowOrderContent(Order order) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildOrderHeaderCard(order),
                const SizedBox(height: 12),
                _buildGlobalPaymentMethodSelector(),
                const SizedBox(height: 16),
                _buildProductsPanel(order),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
        _buildBottomStickyActions(order),
      ],
    );
  }

  Widget _buildCombinedHeaderActionCard(Order order) {
    return Container(
      padding: const EdgeInsets.all(24),
      height: 155,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          // LADO IZQUIERDO: Información de la Orden y Pago Global
          Expanded(
            flex: 2,
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        'Orden: #${order.id}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1E293B),
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Borrador',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.orange[700],
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Divider(color: Colors.grey[100], thickness: 1),
                const Spacer(),
                _buildMinimalGlobalPaymentSelector(),
              ],
            ),
          ),
          
          // LÍNEA DIVISORA VERTICAL
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: VerticalDivider(
              color: Colors.grey[200],
              thickness: 1,
              width: 1,
            ),
          ),

          // LADO DERECHO: Resumen y Botones de Acción
          Expanded(
            flex: 1,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total (${order.totalItems} productos)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey[600],
                      ),
                    ),
                    Text(
                      '\$${PriceUtils.formatDiscountPrice(order.total)}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: OutlinedButton(
                          onPressed: _showClearOrderDialog,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red[600],
                            side: BorderSide(color: Colors.red[200]!, width: 1.2),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            backgroundColor: Colors.red.withOpacity(0.02),
                            padding: EdgeInsets.zero,
                          ),
                          child: const Text(
                            'CANCELAR',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        height: 42,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF4A90E2).withOpacity(0.25),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: _elaboratingProducts ? null : _finalizeOrder,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4A90E2),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: EdgeInsets.zero,
                          ),
                          child: _elaboratingProducts
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation(Colors.white),
                                  ),
                                )
                              : Text(
                                  _noSolicitarCliente ? 'CREAR ORDEN' : 'ENVIAR ORDEN',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMinimalGlobalPaymentSelector() {
    if (_loadingPaymentMethods) return const SizedBox.shrink();

    return Row(
      children: [
        const Text(
          'Método de pago',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<pm.PaymentMethod>(
                isExpanded: true,
                value: _globalPaymentMethod,
                hint: const Text(
                  'Seleccionar para aplicar a todos los productos...',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
                icon: const Icon(Icons.keyboard_arrow_down, size: 16, color: Color(0xFF4A90E2)),
                items: _paymentMethods.map((m) => DropdownMenuItem(
                  value: m,
                  child: Text(
                    m.displayName,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                )).toList(),
                onChanged: _applyGlobalPaymentMethod,
              ),
            ),
          ),
        ),
        if (_globalPaymentMethod != null)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: IconButton(
              icon: Icon(Icons.cancel, size: 20, color: Colors.grey[400]),
              onPressed: _clearGlobalPaymentMethod,
              tooltip: 'Remover pago global',
            ),
          ),
      ],
    );
  }

  Widget _buildWideOrderContent(Order order) {
    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  color: const Color(0xFFF8FAFC),
                  child: Column(
                    children: [
                      // PARTE FIJA SUPERIOR: Única Card con Divisor Vertical
                      Padding(
                        padding: const EdgeInsets.fromLTRB(32, 32, 32, 0),
                        child: _buildCombinedHeaderActionCard(order),
                      ),
                      const SizedBox(height: 24),
                      // PARTE SCROLLEABLE: Lista de productos
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildProductsPanel(order),
                              const SizedBox(height: 40),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomStickyActions(Order order, {bool isWide = false}) {
    return Container(
      padding: EdgeInsets.fromLTRB(24, 16, 24, isWide ? 24 : 32),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[200]!, width: 1.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Total destacado
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TOTAL A PAGAR',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey[500],
                  letterSpacing: 1.1,
                ),
              ),
              Text(
                '\$${PriceUtils.formatDiscountPrice(order.total)}',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1F2937),
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Acciones integradas
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton.icon(
                onPressed: _showClearOrderDialog,
                icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                label: const Text('CANCELAR'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red[400],
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.5),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _elaboratingProducts ? null : _finalizeOrder,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4A90E2),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _elaboratingProducts
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _noSolicitarCliente ? 'CREAR ORDEN' : 'ENVIAR ORDEN',
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.8),
                            ),
                            const SizedBox(width: 10),
                            const Icon(Icons.arrow_forward_rounded, size: 18),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({required String title, required String badge}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1F2937),
            letterSpacing: 0.2,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF4A90E2).withOpacity(0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            badge,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF4A90E2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOrderHeaderCard(Order order) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: _panelDecoration(radius: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF4A90E2).withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.receipt_long,
              size: 28,
              color: Color(0xFF4A90E2),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Preorden #${order.id}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        order.status.displayName,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                    Text(
                      '${order.totalItems} producto${order.totalItems == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Total',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '\$${PriceUtils.formatDiscountPrice(order.total)}',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF4A90E2),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItem(OrderItem item) {
    final bool hasPayment = item.paymentMethod != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8ECF1), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Barra lateral de acento
            Container(
              width: 5,
              decoration: BoxDecoration(
                color: hasPayment ? const Color(0xFF10B981) : const Color(0xFF4A90E2),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                ),
              ),
            ),
            // Contenido principal
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Fila 1: Nombre + precio subtotal + eliminar
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            item.nombre,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1E293B),
                              letterSpacing: -0.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4A90E2).withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '\$${PriceUtils.formatDiscountPrice(item.subtotal)}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF4A90E2),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () => _removeItem(item.id),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(Icons.close_rounded, size: 16, color: Colors.grey[400]),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Fila 2: Ubicación + desglose precio
                    Row(
                      children: [
                        Icon(Icons.warehouse_outlined, size: 12, color: Colors.grey[400]),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            item.ubicacionAlmacen,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.grey[500],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${item.cantidad} x \$${PriceUtils.formatDiscountPrice(item.displayPrice)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[400],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Fila 3: Controles de cantidad + método de pago
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFF0F2F5)),
                      ),
                      child: Row(
                        children: [
                          // Controles de cantidad
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildQtyBtn(
                                  icon: Icons.remove_rounded,
                                  onPressed: () => _updateItemQuantity(item.id, item.cantidad - 1),
                                  color: const Color(0xFFEF4444),
                                ),
                                SizedBox(
                                  width: 44,
                                  height: 30,
                                  child: _buildInlineQtyField(item),
                                ),
                                _buildQtyBtn(
                                  icon: Icons.add_rounded,
                                  onPressed: () => _updateItemQuantity(item.id, item.cantidad + 1),
                                  color: const Color(0xFF4A90E2),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Selector de pago
                          Expanded(
                            child: _buildMiniPaymentSelector(item),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQtyBtn({
    required IconData icon,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          child: Icon(icon, size: 15, color: color),
        ),
      ),
    );
  }

  TextEditingController _getQtyController(String itemId, double currentQty) {
    if (!_qtyControllers.containsKey(itemId)) {
      _qtyControllers[itemId] = TextEditingController(text: '$currentQty');
    } else if (_qtyControllers[itemId]!.text != '$currentQty') {
      // Sync controller if quantity changed externally (+/- buttons)
      final ctrl = _qtyControllers[itemId]!;
      ctrl.text = '$currentQty';
      ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
    }
    return _qtyControllers[itemId]!;
  }

  Widget _buildInlineQtyField(OrderItem item) {
    final controller = _getQtyController(item.id, item.cantidad);
    return Center(
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        textAlignVertical: TextAlignVertical.center,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          height: 1.0,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 6),
          isCollapsed: true,
        ),
        onChanged: (value) {
          _qtyDebounceTimer?.cancel();
          _qtyDebounceTimer = Timer(const Duration(seconds: 3), () {
            _applyManualQty(item.id, controller.text);
          });
        },
        onSubmitted: (value) {
          _qtyDebounceTimer?.cancel();
          _applyManualQty(item.id, value);
        },
        onTapOutside: (_) {
          _qtyDebounceTimer?.cancel();
          _applyManualQty(item.id, controller.text);
          FocusScope.of(context).unfocus();
        },
      ),
    );
  }

  /// Obtiene el stock máximo disponible para un item de la orden.
  /// Retorna null si no aplica límite (elaborado o servicio).
  double? _getMaxStockForItem(OrderItem item) {
    if (item.producto.esElaborado || item.producto.esServicio) return null;
    if (item.variante != null) {
      return item.variante!.cantidad.toDouble();
    }
    return item.producto.cantidad.toDouble();
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

  void _applyManualQty(String itemId, String value) {
    final newQty = double.tryParse(value);
    if (newQty != null && newQty > 0) {
      // Validar stock
      final currentOrder = _orderService.currentOrder;
      if (currentOrder != null) {
        final item = currentOrder.items.where((i) => i.id == itemId).firstOrNull;
        if (item != null) {
          final maxStock = _getMaxStockForItem(item);
          if (maxStock != null && newQty > maxStock) {
            _updateItemQuantity(itemId, maxStock);
            if (_qtyControllers.containsKey(itemId)) {
              _qtyControllers[itemId]!.text = '$maxStock';
            }
            _showStockWarning(maxStock, variantName: item.variante?.nombre);
            return;
          }
        }
      }
      _updateItemQuantity(itemId, newQty);
    } else {
      // Revert to current quantity if invalid
      final currentOrder = _orderService.currentOrder;
      if (currentOrder != null) {
        final item = currentOrder.items.where((i) => i.id == itemId).firstOrNull;
        if (item != null && _qtyControllers.containsKey(itemId)) {
          _qtyControllers[itemId]!.text = '${item.cantidad}';
        }
      }
    }
  }

  Widget _buildMiniPaymentSelector(OrderItem item) {
    final bool hasMethod = item.paymentMethod != null;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: hasMethod ? const Color(0xFF10B981).withOpacity(0.03) : Colors.orange.withOpacity(0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasMethod ? const Color(0xFF10B981).withOpacity(0.2) : Colors.orange.withOpacity(0.2),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<pm.PaymentMethod>(
          isExpanded: true,
          value: item.paymentMethod,
          hint: Text(
            'Pago...',
            style: TextStyle(fontSize: 11, color: Colors.orange[700]),
          ),
          icon: Icon(Icons.keyboard_arrow_down, size: 14, color: Colors.grey[400]),
          items: _paymentMethods.map((m) => DropdownMenuItem(
            value: m,
            child: Text(m.displayName, style: const TextStyle(fontSize: 11)),
          )).toList(),
          onChanged: (val) => _updateItemPaymentMethod(item.id, val),
        ),
      ),
    );
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
    if (newQuantity < 0) return;
    // Validar stock antes de actualizar
    final currentOrder = _orderService.currentOrder;
    if (currentOrder != null) {
      final item = currentOrder.items.where((i) => i.id == itemId).firstOrNull;
      if (item != null) {
        final maxStock = _getMaxStockForItem(item);
        if (maxStock != null && newQuantity > maxStock) {
          // Si ya está en el máximo, solo mostrar advertencia
          if (item.cantidad >= maxStock) {
            _showStockWarning(maxStock, variantName: item.variante?.nombre);
            return;
          }
          // Si no, ajustar al máximo
          newQuantity = maxStock;
          _showStockWarning(maxStock, variantName: item.variante?.nombre);
        }
      }
    }
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
            title: const Text('Cancelar Orden'),
            content: const Text(
              '¿Estás seguro de que quieres cancelar esta orden? Se perderán todos los productos agregados.',
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
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Confirmar'),
              ),
            ],
          ),
    );
  }

  void _finalizeOrder() async {
    final currentOrder = _orderService.currentOrder;
    if (currentOrder == null || currentOrder.items.isEmpty) {
      AppSnackBar.showPersistent(
        context,
        message: 'No hay productos en la orden',
        backgroundColor: Colors.red,
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

    // Verificar si el modo offline está activado
    final isOfflineModeEnabled = await _userPreferencesService.isOfflineModeEnabled();

    // Si no se solicitan datos del cliente, crear orden directamente
    if (_noSolicitarCliente) {
      await _createOrderDirectly(currentOrder, isOfflineModeEnabled);
      return;
    }

    if (isOfflineModeEnabled) {
      // MODO OFFLINE: No elaborar productos, pero SÍ ir al checkout para capturar datos del cliente
      print('🔌 Modo offline - Saltando elaboración pero continuando al checkout para datos del cliente');

      // Marcar la orden como offline para que el checkout la maneje apropiadamente
      currentOrder.isOfflineOrder = true;

      // Navigate to checkout screen (CRÍTICO: No saltarse el checkout en modo offline)
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CheckoutScreen(order: currentOrder),
        ),
      ).then((_) {
        // Refresh the screen when returning from checkout
        setState(() {});
      });
    } else {
      // MODO ONLINE: Elaborar productos y continuar al checkout
      print('🌐 Modo online - Procesando elaboración y continuando al checkout');
      await _processElaboratedProducts(currentOrder);

      // Navigate to checkout screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CheckoutScreen(order: currentOrder),
        ),
      ).then((_) {
        // Refresh the screen when returning from checkout
        setState(() {});
      });
    }
  }

  /// Crea la orden directamente sin pasar por checkout (cuando no_solicitar_cliente está activo)
  Future<void> _createOrderDirectly(Order currentOrder, bool isOfflineMode) async {
    setState(() {
      _elaboratingProducts = true;
    });

    try {
      // Construir el breakdown de pagos a partir de los items
      final breakdown = <String, double>{};
      for (final item in currentOrder.items) {
        if (item.paymentMethod != null) {
          final methodName = item.paymentMethod!.displayName;
          final amount = item.precioUnitario * item.cantidad;
          breakdown[methodName] = (breakdown[methodName] ?? 0) + amount;
        }
      }

      if (isOfflineMode) {
        // MODO OFFLINE
        currentOrder.isOfflineOrder = true;
        final offlineOrderId = '${DateTime.now().millisecondsSinceEpoch}';
        final orderData = {
          'id': offlineOrderId,
          'items': currentOrder.items.map((item) => {
            'nombre': item.nombre,
            'cantidad': item.cantidad,
            'precio': item.precioUnitario,
            'paymentMethod': item.paymentMethod?.displayName,
          }).toList(),
          'buyerName': '',
          'buyerPhone': '',
          'total': currentOrder.total,
          'paymentBreakdown': breakdown,
          'timestamp': DateTime.now().toIso8601String(),
          'isOf5788flineOrder': true,
        };
        await _userPreferencesService.savePendingOrder(orderData);
        _orderService.clearAllOrders();

        if (mounted) {
          AppSnackBar.showPersistent(
            context,
            message: '¡Orden creada exitosamente!',
            backgroundColor: Colors.green,
          );
          Navigator.pushNamedAndRemoveUntil(
            context, '/orders', (route) => false,
            arguments: {'openOrderId': offlineOrderId},
          );
        }
      } else {
        // MODO ONLINE: Elaborar productos primero
        await _processElaboratedProducts(currentOrder);

        final updatedOrder = currentOrder.copyWith(
          buyerName: '',
          buyerPhone: '',
          paymentMethod: 'Múltiples métodos',
        );

        final orderData = {
          'buyerName': '',
          'buyerPhone': '',
          'extraContacts': '',
          'paymentMethod': 'Múltiples métodos',
          'finalTotal': updatedOrder.total,
          'originalTotal': updatedOrder.total,
          'paymentBreakdown': breakdown,
        };

        final result = await _orderService.finalizeOrderWithDetails(
          updatedOrder,
          orderData,
        );

        if (result['success'] == true) {
          _orderService.clearAllOrders();
          if (mounted) {
            AppSnackBar.showPersistent(
              context,
              message: '¡Orden creada exitosamente!',
              backgroundColor: Colors.green,
            );
            final opId = result['operationId'];
            final orderIdToOpen = opId != null ? 'ORD-$opId' : updatedOrder.id;
            Navigator.pushNamedAndRemoveUntil(
              context, '/orders', (route) => false,
              arguments: {'openOrderId': orderIdToOpen},
            );
          }
        } else {
          if (mounted) {
            AppSnackBar.showPersistent(
              context,
              message: 'Error al crear la orden: ${result['error']}',
              backgroundColor: Colors.red,
            );
          }
        }
      }
    } catch (e) {
      print('❌ Error creando orden directamente: $e');
      if (mounted) {
        AppSnackBar.showPersistent(
          context,
          message: 'Error al crear la orden: $e',
          backgroundColor: Colors.red,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _elaboratingProducts = false;
        });
      }
    }
  }

  /// Procesa productos elaborados en la orden
  Future<void> _processElaboratedProducts(Order order) async {
    try {
      setState(() {
        _elaboratingProducts = true;
      });

      // Verificar si hay productos elaborados en la orden
      final productosElaborados = <Map<String, dynamic>>[];
      for (final item in order.items) {
        final productId = item.producto.id;
        final isElaborated = await _productDetailService.isProductElaborated(productId);
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
        debugPrint('✅ No hay productos elaborados en la orden - saltando proceso');
        return;
      }

      debugPrint('🔍 Productos elaborados encontrados: ${productosElaborados.length}');

      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.orange[600]!),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Elaborando productos...',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Text(
                  'Descomponiendo ingredientes y verificando stock',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
          );
        },
      );

      // Verificar disponibilidad de ingredientes solo en modo ONLINE y si la configuración lo requiere
      final isOfflineModeEnabled = await _userPreferencesService.isOfflineModeEnabled();
      
      if (!isOfflineModeEnabled) {
        debugPrint('🌐 Modo online - Verificando configuración de tienda...');
        
        // Obtener ID de tienda
        final idTienda = await _userPreferencesService.getIdTienda();
        if (idTienda != null) {
          // Verificar configuración de tienda
          final permiteVenderSinDisponibilidad = await StoreConfigService.getPermiteVenderAunSinDisponibilidad(idTienda);
          
          if (permiteVenderSinDisponibilidad) {
            debugPrint('⚙️ Configuración permite vender sin disponibilidad - Saltando verificación de ingredientes');
          } else {
            debugPrint('⚙️ Configuración requiere verificar disponibilidad - Verificando ingredientes');
            await _checkIngredientsAvailability(productosElaborados);
          }
        } else {
          debugPrint('⚠️ No se pudo obtener ID de tienda - Verificando ingredientes por seguridad');
          await _checkIngredientsAvailability(productosElaborados);
        }
      } else {
        debugPrint('🔌 Modo offline - Saltando verificación de disponibilidad');
      }

      // Convert order items to the format expected by decomposition functions
      final productos = order.items.map((item) {
        // Use the product ID from the Product object, not the OrderItem ID
        final productId = item.producto.id;
        debugPrint('🔄 Convirtiendo OrderItem - ID: ${item.id}, ProductoID: $productId, Nombre: ${item.nombre}');
        return {
          'id_producto': productId,
          'cantidad': item.cantidad,
          'nombre': item.nombre,
          'precio_unitario': item.precioUnitario,
        };
      }).where((producto) => producto['id_producto'] != 0).toList();

      debugPrint('🔄 Procesando ${productos.length} productos para elaboración');
      
      // Log all products being processed
      for (final producto in productos) {
        debugPrint('📋 Producto en orden: ID=${producto['id_producto']}, Nombre=${producto['nombre']}, Cantidad=${producto['cantidad']}');
      }

      // Decompose elaborated products using the same logic as inventory service
      final productosDescompuestos = await _decomposeElaboratedProducts(productos);
      
      debugPrint('✅ Descomposición completada: ${productosDescompuestos.length} productos finales');
      
      // Update the order with decomposed products for inventory management
      await _updateOrderWithDecomposedProducts(order, productosDescompuestos);
      
      // Show detailed results
      final elaboratedCount = productosDescompuestos.where((p) => p['producto_elaborado'] != null).length;
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
            backgroundColor: Colors.green[600],
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
          backgroundColor: Colors.red[600],
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
    List<Map<String, dynamic>> productos
  ) async {
    final decomposedProducts = <Map<String, dynamic>>[];
    
    debugPrint('🔄 Descomponiendo productos elaborados...');
    
    for (final producto in productos) {
      final productId = producto['id_producto'] as int;
      final cantidadOriginal = (producto['cantidad'] as num).toDouble();
      
      debugPrint('🔄 Procesando producto ID: $productId');
      debugPrint('🔄 Cantidad original: $cantidadOriginal');
      debugPrint('🔄 Nombre producto: ${producto['nombre']}');
      
      final isElaborated = await _productDetailService.isProductElaborated(productId);
      debugPrint('🔄 Resultado isElaborated para producto $productId: $isElaborated');
      
      if (isElaborated) {
        debugPrint('🔍 Producto $productId es elaborado');
        
        final consolidatedIngredients = <int, double>{};
        
        await _decomposeRecursively(productId, cantidadOriginal, consolidatedIngredients);
        
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
        debugPrint('🔄 Producto $productId NO es elaborado - agregando como simple');
        // Add simple products as-is
        decomposedProducts.add(producto);
      }
    }
    
    debugPrint('✅ Descomposición completada: ${decomposedProducts.length} productos');
    return decomposedProducts;
  }

  /// Descompone un producto elaborado recursivamente
  Future<void> _decomposeRecursively(
    int productId, 
    double quantity, 
    Map<int, double> consolidatedIngredients
  ) async {
    debugPrint('🔄 Descomponiendo producto $productId con cantidad $quantity');
    
    final ingredients = await _productDetailService.getProductIngredients(productId);
    
    if (ingredients.isEmpty) {
      debugPrint('⚠️ Producto $productId sin ingredientes - tratando como simple');
      _addToConsolidated(consolidatedIngredients, productId, quantity);
      return;
    }
    
    for (final ingredient in ingredients) {
      final ingredientId = ingredient['producto_id'] as int;
      final cantidadNecesaria = (ingredient['cantidad_necesaria'] as num).toDouble();
      final totalQuantity = cantidadNecesaria * quantity;
      
      final isElaborated = await _productDetailService.isProductElaborated(ingredientId);
      
      if (isElaborated) {
        await _decomposeRecursively(ingredientId, totalQuantity, consolidatedIngredients);
      } else {
        _addToConsolidated(consolidatedIngredients, ingredientId, totalQuantity);
      }
    }
  }

  /// Agrega cantidad a ingredientes consolidados
  void _addToConsolidated(Map<int, double> consolidatedIngredients, int productId, double quantity) {
    if (consolidatedIngredients.containsKey(productId)) {
      consolidatedIngredients[productId] = consolidatedIngredients[productId]! + quantity;
    } else {
      consolidatedIngredients[productId] = quantity;
    }
    debugPrint('📦 Consolidado: Producto $productId -> ${consolidatedIngredients[productId]}');
  }

  /// Actualiza la orden con los productos descompuestos para manejo de inventario
  Future<void> _updateOrderWithDecomposedProducts(
    Order order, 
    List<Map<String, dynamic>> productosDescompuestos
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
          'ingredientes_descompuestos': elaboratedProductsData[elaboratedId]['ingredientes'],
          'requiere_descomposicion_inventario': true,
        };
        
        // Store in inventoryData or create a new field for this
        final currentInventoryData = item.inventoryData ?? {};
        currentInventoryData['decomposition_data'] = decompositionData;
        
        debugPrint('📦 Producto elaborado ${item.nombre} actualizado con ${elaboratedProductsData[elaboratedId]['ingredientes'].length} ingredientes');
      }
    }
    
    debugPrint('✅ Orden actualizada con datos de descomposición');
  }

  Widget _buildGlobalPaymentMethodSelector() {
    if (_loadingPaymentMethods) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF4A90E2).withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4A90E2).withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF4A90E2).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.payments_outlined, size: 20, color: Color(0xFF4A90E2)),
          ),
          const SizedBox(width: 16),
          const Text(
            'Método de pago',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<pm.PaymentMethod>(
                  isExpanded: true,
                  value: _globalPaymentMethod,
                  hint: const Text('Seleccionar para aplicar a todos los productos...', style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                  icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: Color(0xFF4A90E2)),
                  items: _paymentMethods.map((m) => DropdownMenuItem(
                    value: m,
                    child: Text(m.displayName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  )).toList(),
                  onChanged: _applyGlobalPaymentMethod,
                ),
              ),
            ),
          ),
          if (_globalPaymentMethod != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: IconButton(
                icon: Icon(Icons.cancel, size: 20, color: Colors.grey[400]),
                onPressed: _clearGlobalPaymentMethod,
                tooltip: 'Remover pago global',
              ),
            ),
        ],
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

        final ingredientes = await _productDetailService.getProductIngredients(productId);

        for (final ingrediente in ingredientes) {
          final cantidadNecesaria = (ingrediente['cantidad_necesaria'] as num).toDouble();
          final cantidadDisponible = ingrediente['cantidad_disponible'] as double?;
          final nombreIngrediente = ingrediente['producto_nombre'] as String;
          final unidadMedida = ingrediente['unidad_medida'] as String;

          final cantidadTotalNecesaria = cantidadNecesaria * cantidadProducto;

          if (cantidadDisponible == null) {
            debugPrint('⚠️ Ingrediente sin datos de inventario: $nombreIngrediente');
            continue;
          }

          // Verificar si no hay stock suficiente
          if (cantidadDisponible < cantidadTotalNecesaria) {
            ingredientesSinStock.add({
              'nombre': nombreIngrediente,
              'producto': nombreProducto,
              'necesaria': cantidadTotalNecesaria,
              'disponible': cantidadDisponible,
              'unidad': unidadMedida,
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
          title: Row(
            children: [
              Icon(
                isError ? Icons.error_outline : Icons.warning_amber_rounded,
                color: isError ? Colors.red : Colors.orange,
                size: 28,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isError ? Colors.red : Colors.orange,
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
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                ...ingredientes.map((ing) {
                  final nombre = ing['nombre'] as String;
                  final producto = ing['producto'] as String;
                  final necesaria = ing['necesaria'] as double;
                  final disponible = ing['disponible'] as double;
                  final unidad = ing['unidad'] as String;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isError ? Colors.red[50] : Colors.orange[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isError ? Colors.red[200]! : Colors.orange[200]!,
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
                              color: isError ? Colors.red[700] : Colors.orange[700],
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                nombre,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isError ? Colors.red[900] : Colors.orange[900],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Para: $producto',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Necesario: ${necesaria.toStringAsFixed(2)} $unidad',
                              style: const TextStyle(fontSize: 12),
                            ),
                            Text(
                              'Disponible: ${disponible.toStringAsFixed(2)} $unidad',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isError ? Colors.red[700] : Colors.orange[700],
                              ),
                            ),
                          ],
                        ),
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
      case 0: // Home
        // Usar pushNamed en lugar de pushNamedAndRemoveUntil para mantener la persistencia
        Navigator.pushNamed(context, '/categories');
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
