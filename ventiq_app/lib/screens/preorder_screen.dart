import 'package:flutter/material.dart';
import '../models/order.dart';
import '../models/payment_method.dart' as pm;
import '../services/order_service.dart';
import '../services/turno_service.dart';
import '../services/payment_method_service.dart';
import '../services/product_detail_service.dart';
import '../utils/price_utils.dart';
import '../widgets/bottom_navigation.dart';
import '../widgets/app_drawer.dart';
import '../widgets/scrolling_text.dart';
import 'checkout_screen.dart';

class PreorderScreen extends StatefulWidget {
  const PreorderScreen({Key? key}) : super(key: key);

  @override
  State<PreorderScreen> createState() => _PreorderScreenState();
}

class _PreorderScreenState extends State<PreorderScreen> {
  final OrderService _orderService = OrderService();
  final ProductDetailService _productDetailService = ProductDetailService();
  List<pm.PaymentMethod> _paymentMethods = [];
  bool _loadingPaymentMethods = false;
  bool _checkingShift = true;
  bool _hasOpenShift = false;
  bool _elaboratingProducts = false;
  pm.PaymentMethod? _globalPaymentMethod;

  @override
  void initState() {
    super.initState();
    _checkOpenShift();
  }

  Future<void> _checkOpenShift() async {
    try {
      setState(() {
        _checkingShift = true;
      });

      final hasShift = await TurnoService.hasOpenShift();

      setState(() {
        _hasOpenShift = hasShift;
        _checkingShift = false;
      });

      if (_hasOpenShift) {
        _loadPaymentMethods();
      } else {
        _showNoShiftDialog();
      }
    } catch (e) {
      print('Error checking shift: $e');
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
      final paymentMethods =
          await PaymentMethodService.getActivePaymentMethods();
      
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
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A90E2),
        elevation: 0,
        title: const Text(
          'Preorden Abierta',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        actions: [
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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shopping_cart_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No hay productos en la preorden',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Agrega productos desde el catálogo',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _onBottomNavTap(0), // Ir a Home
            icon: const Icon(Icons.home),
            label: const Text('Ir al Catálogo'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4A90E2),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderContent(Order order) {
    return Column(
      children: [
        // Header con información de la orden
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey, width: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Orden: ${order.id}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      order.status.displayName,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${order.totalItems} producto${order.totalItems == 1 ? '' : 's'} • Total: \$${PriceUtils.formatDiscountPrice(order.total)}',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
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
        _buildOrderFooter(order),
      ],
    );
  }

  Widget _buildOrderItem(OrderItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  item.nombre,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '\$${PriceUtils.formatDiscountPrice(item.subtotal)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF4A90E2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 16,
                color: Colors.grey[600],
              ),
              const SizedBox(width: 4),
              Expanded(
                flex: 2,
                child: ScrollingText(
                  text: item.ubicacionAlmacen,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  maxWidth: 180, // Further increased width for longer text
                  scrollDuration: const Duration(
                    seconds: 4,
                  ), // Slower animation
                  pauseDuration: const Duration(seconds: 2), // Longer pause
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Precio: \$${PriceUtils.formatDiscountPrice(item.displayPrice)}',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Cantidad: ${item.cantidad}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1F2937),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed:
                        () => _updateItemQuantity(item.id, item.cantidad - 1),
                    icon: const Icon(Icons.remove_circle_outline),
                    color: Colors.red,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed:
                        () => _updateItemQuantity(item.id, item.cantidad + 1),
                    icon: const Icon(Icons.add_circle_outline),
                    color: const Color(0xFF4A90E2),
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => _removeItem(item.id),
                    icon: const Icon(Icons.delete_outline),
                    color: Colors.red,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Payment method selector
          _buildPaymentMethodSelector(item),
        ],
      ),
    );
  }

  Widget _buildOrderFooter(Order order) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total de la Orden:',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1F2937),
                ),
              ),
              Text(
                '\$${PriceUtils.formatDiscountPrice(order.total)}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF4A90E2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _showClearOrderDialog,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Cancelar Orden'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _elaboratingProducts ? null : _finalizeOrder,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4A90E2),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Enviar Orden',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodSelector(OrderItem item) {
    if (_loadingPaymentMethods) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue[200]!),
        ),
        child: Row(
          children: [
            Icon(Icons.payment, size: 18, color: Colors.blue[600]),
            const SizedBox(width: 10),
            const Text(
              'Cargando métodos de pago...',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    if (_paymentMethods.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange[200]!),
        ),
        child: Row(
          children: [
            Icon(Icons.warning, size: 18, color: Colors.orange[600]),
            const SizedBox(width: 10),
            const Text(
              'Sin métodos de pago disponibles',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    // Highlight if no payment method is selected
    final bool hasPaymentMethod = item.paymentMethod != null;
    final Color borderColor =
        hasPaymentMethod ? const Color(0xFF10B981) : Colors.red[300]!;
    final Color backgroundColor =
        hasPaymentMethod
            ? const Color(0xFF10B981).withOpacity(0.05)
            : Colors.red[50]!;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasPaymentMethod ? Icons.check_circle : Icons.payment,
                size: 18,
                color:
                    hasPaymentMethod
                        ? const Color(0xFF10B981)
                        : Colors.red[600],
              ),
              const SizedBox(width: 8),
              Text(
                hasPaymentMethod
                    ? 'Método de pago asignado:'
                    : 'Método de pago requerido:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color:
                      hasPaymentMethod
                          ? const Color(0xFF10B981)
                          : Colors.red[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<pm.PaymentMethod>(
                isExpanded: true,
                value: item.paymentMethod,
                hint: const Text(
                  'Seleccionar método de pago',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                style: const TextStyle(fontSize: 14, color: Colors.black87),
                items:
                    _paymentMethods.map((pm.PaymentMethod method) {
                      // Identificar si es el método especial "Pago Regular (Efectivo)"
                      final isSpecialCash = method.id == 999;
                      
                      return DropdownMenuItem<pm.PaymentMethod>(
                        value: method,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                          decoration: BoxDecoration(
                            color: isSpecialCash ? Colors.red.withOpacity(0.1) : null,
                            borderRadius: BorderRadius.circular(6),
                            border: isSpecialCash 
                                ? Border.all(color: Colors.red.withOpacity(0.3), width: 1)
                                : null,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                method.typeIcon,
                                size: 18,
                                color: isSpecialCash ? Colors.red[700] : Colors.grey[600],
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  method.displayName,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isSpecialCash ? Colors.red[700] : Colors.black87,
                                    fontWeight: isSpecialCash ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isSpecialCash) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Text(
                                    'SIN DESC.',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                onChanged: (pm.PaymentMethod? newMethod) {
                  _updateItemPaymentMethod(item.id, newMethod);
                },
              ),
            ),
          ),
        ],
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

  void _updateItemQuantity(String itemId, int newQuantity) {
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay productos en la orden'),
          backgroundColor: Colors.red,
        ),
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

    // Check for elaborated products and process them
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

  /// Procesa productos elaborados en la orden
  Future<void> _processElaboratedProducts(Order order) async {
    try {
      setState(() {
        _elaboratingProducts = true;
      });

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
      Navigator.of(context).pop();

      // Show success message with details
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

    } catch (e) {
      // Close loading dialog if still open
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
    if (_loadingPaymentMethods) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.blue[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue[200]!),
        ),
        child: Row(
          children: [
            Icon(Icons.payment, size: 16, color: Colors.blue[600]),
            const SizedBox(width: 8),
            const Text(
              'Cargando métodos de pago...',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    if (_paymentMethods.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.orange[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange[200]!),
        ),
        child: Row(
          children: [
            Icon(Icons.warning, size: 16, color: Colors.orange[600]),
            const SizedBox(width: 8),
            const Text(
              'Sin métodos de pago disponibles',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF4A90E2).withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF4A90E2).withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF4A90E2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.payment, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Aplicar método de pago a todos los productos',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF4A90E2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(
                color: const Color(0xFF4A90E2).withOpacity(0.4),
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(10),
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4A90E2).withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<pm.PaymentMethod>(
                isExpanded: true,
                value: _globalPaymentMethod,
                hint: const Text(
                  'Seleccionar método para aplicar a todos',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
                items:
                    _paymentMethods.map((pm.PaymentMethod method) {
                      // Identificar si es el método especial "Pago Regular (Efectivo)"
                      final isSpecialCash = method.id == 999;
                      
                      return DropdownMenuItem<pm.PaymentMethod>(
                        value: method,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                          decoration: BoxDecoration(
                            color: isSpecialCash ? Colors.red.withOpacity(0.1) : null,
                            borderRadius: BorderRadius.circular(6),
                            border: isSpecialCash 
                                ? Border.all(color: Colors.red.withOpacity(0.3), width: 1)
                                : null,
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: isSpecialCash ? Colors.red.withOpacity(0.2) : Colors.grey[100],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Icon(
                                  method.typeIcon,
                                  size: 18,
                                  color: isSpecialCash ? Colors.red[700] : const Color(0xFF4A90E2),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  method.displayName,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: isSpecialCash ? Colors.red[700] : Colors.black87,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isSpecialCash) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Text(
                                    'SIN DESC.',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                onChanged: (pm.PaymentMethod? newMethod) {
                  _applyGlobalPaymentMethod(newMethod);
                },
              ),
            ),
          ),
          if (_globalPaymentMethod != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.check_circle,
                  size: 16,
                  color: const Color(0xFF10B981),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Método "${_globalPaymentMethod!.displayName}" seleccionado',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF10B981),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _clearGlobalPaymentMethod,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey[600],
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                  ),
                  child: const Text('Limpiar', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
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

    // Show confirmation
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Método "${paymentMethod.displayName}" aplicado a todos los productos',
        ),
        backgroundColor: const Color(0xFF4A90E2),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _clearGlobalPaymentMethod() {
    setState(() {
      _globalPaymentMethod = null;
    });
  }

  void _onBottomNavTap(int index) {
    switch (index) {
      case 0: // Home
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/categories',
          (route) => false,
        );
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
