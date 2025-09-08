import 'package:flutter/material.dart';
import '../models/order.dart';
import '../models/payment_method.dart' as pm;
import '../services/order_service.dart';
import '../services/turno_service.dart';
import '../services/payment_method_service.dart';
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
  List<pm.PaymentMethod> _paymentMethods = [];
  bool _loadingPaymentMethods = false;
  bool _checkingShift = true;
  bool _hasOpenShift = false;
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
                  onPressed: _finalizeOrder,
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
      return Row(
        children: [
          Icon(Icons.payment, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          const Text(
            'Cargando métodos de pago...',
            style: TextStyle(fontSize: 13),
          ),
        ],
      );
    }

    if (_paymentMethods.isEmpty) {
      return Row(
        children: [
          Icon(Icons.payment, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          const Text(
            'Sin métodos de pago disponibles',
            style: TextStyle(fontSize: 13),
          ),
        ],
      );
    }

    return Row(
      children: [
        Icon(Icons.payment, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(6),
              color: Colors.grey[50],
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<pm.PaymentMethod>(
                isExpanded: true,
                value: item.paymentMethod,
                hint: const Text(
                  'Seleccionar método de pago',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                style: const TextStyle(fontSize: 12, color: Colors.black87),
                items:
                    _paymentMethods.map((pm.PaymentMethod method) {
                      return DropdownMenuItem<pm.PaymentMethod>(
                        value: method,
                        child: Row(
                          children: [
                            Icon(
                              method.typeIcon,
                              size: 16,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                method.displayName,
                                style: const TextStyle(fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                onChanged: (pm.PaymentMethod? newMethod) {
                  _updateItemPaymentMethod(item.id, newMethod);
                },
              ),
            ),
          ),
        ),
      ],
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

  void _finalizeOrder() {
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF4A90E2).withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF4A90E2).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.payment, size: 14, color: const Color(0xFF4A90E2)),
              const SizedBox(width: 6),
              const Text(
                'Aplicar método de pago a todos:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF4A90E2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(6),
                    color: Colors.white,
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<pm.PaymentMethod>(
                      isExpanded: true,
                      value: _globalPaymentMethod,
                      hint: const Text(
                        'Seleccionar método para todos los productos',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black87,
                      ),
                      items:
                          _paymentMethods.map((pm.PaymentMethod method) {
                            return DropdownMenuItem<pm.PaymentMethod>(
                              value: method,
                              child: Row(
                                children: [
                                  Icon(
                                    method.typeIcon,
                                    size: 16,
                                    color: Colors.grey[600],
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      method.displayName,
                                      style: const TextStyle(fontSize: 12),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                      onChanged: (pm.PaymentMethod? newMethod) {
                        _applyGlobalPaymentMethod(newMethod);
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              if (_globalPaymentMethod != null)
                IconButton(
                  onPressed: _clearGlobalPaymentMethod,
                  icon: const Icon(Icons.clear, size: 16),
                  color: Colors.grey[600],
                  tooltip: 'Limpiar selección global',
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
            ],
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
