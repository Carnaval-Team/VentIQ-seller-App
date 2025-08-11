import '../models/order.dart';
import '../models/product.dart';

class OrderService {
  static final OrderService _instance = OrderService._internal();
  factory OrderService() => _instance;
  OrderService._internal();

  Order? _currentOrder;
  final List<Order> _orders = [];

  // Getter para la orden actual
  Order? get currentOrder => _currentOrder;
  List<Order> get orders => List.from(_orders);

  // Crear una nueva orden o obtener la actual
  Order getCurrentOrCreateOrder() {
    if (_currentOrder == null || _currentOrder!.status != OrderStatus.borrador) {
      _currentOrder = Order(
        id: 'ORD-${DateTime.now().millisecondsSinceEpoch}',
        fechaCreacion: DateTime.now(),
        items: [],
        total: 0.0,
        status: OrderStatus.borrador,
      );
    }
    return _currentOrder!;
  }

  // Agregar item a la orden actual
  void addItemToCurrentOrder({
    required Product producto,
    ProductVariant? variante,
    required int cantidad,
    required String ubicacionAlmacen,
  }) {
    final order = getCurrentOrCreateOrder();
    final precioUnitario = variante?.precio ?? producto.precio;
    
    // Verificar si ya existe un item similar
    final existingItemIndex = order.items.indexWhere((item) =>
        item.producto.id == producto.id &&
        ((item.variante == null && variante == null) ||
         (item.variante?.id == variante?.id)));

    if (existingItemIndex != -1) {
      // Actualizar cantidad del item existente
      final existingItem = order.items[existingItemIndex];
      final updatedItem = existingItem.copyWith(
        cantidad: existingItem.cantidad + cantidad,
      );
      order.items[existingItemIndex] = updatedItem;
    } else {
      // Crear nuevo item
      final newItem = OrderItem(
        id: 'ITEM-${DateTime.now().millisecondsSinceEpoch}-${order.items.length}',
        producto: producto,
        variante: variante,
        cantidad: cantidad,
        precioUnitario: precioUnitario,
        ubicacionAlmacen: ubicacionAlmacen,
      );
      order.items.add(newItem);
    }

    // Actualizar total de la orden
    _updateOrderTotal(order);
  }

  // Actualizar cantidad de un item
  void updateItemQuantity(String itemId, int newQuantity) {
    if (_currentOrder == null) return;

    final itemIndex = _currentOrder!.items.indexWhere((item) => item.id == itemId);
    if (itemIndex != -1) {
      if (newQuantity <= 0) {
        _currentOrder!.items.removeAt(itemIndex);
      } else {
        _currentOrder!.items[itemIndex] = _currentOrder!.items[itemIndex].copyWith(
          cantidad: newQuantity,
        );
      }
      _updateOrderTotal(_currentOrder!);
    }
  }

  // Remover item de la orden
  void removeItemFromCurrentOrder(String itemId) {
    if (_currentOrder == null) return;
    
    _currentOrder!.items.removeWhere((item) => item.id == itemId);
    _updateOrderTotal(_currentOrder!);
  }

  // Actualizar total de la orden
  void _updateOrderTotal(Order order) {
    final newTotal = order.items.fold(0.0, (sum, item) => sum + item.subtotal);
    _currentOrder = order.copyWith(total: newTotal);
  }

  // Finalizar orden actual
  void finalizeCurrentOrder({String? notas}) {
    if (_currentOrder == null || _currentOrder!.items.isEmpty) return;

    final finalizedOrder = _currentOrder!.copyWith(
      status: OrderStatus.enviada,
      notas: notas,
    );

    _orders.add(finalizedOrder);
    _currentOrder = null; // Limpiar orden actual
  }

  // Finalizar orden con detalles completos del checkout
  void finalizeOrderWithDetails(Order order, Map<String, dynamic> orderData) {
    if (order.items.isEmpty) return;

    final finalizedOrder = order.copyWith(
      status: OrderStatus.enviada,
    );

    _orders.add(finalizedOrder);
    _currentOrder = null; // Limpiar orden actual
  }

  // Cancelar orden actual
  void cancelCurrentOrder() {
    _currentOrder = null;
  }

  // Obtener orden por ID
  Order? getOrderById(String orderId) {
    try {
      return _orders.firstWhere((order) => order.id == orderId);
    } catch (e) {
      return null;
    }
  }

  // Actualizar estado de una orden
  void updateOrderStatus(String orderId, OrderStatus newStatus) {
    final orderIndex = _orders.indexWhere((order) => order.id == orderId);
    if (orderIndex != -1) {
      final updatedOrder = _orders[orderIndex].copyWith(status: newStatus);
      _orders[orderIndex] = updatedOrder;
    }
  }

  // Limpiar todas las órdenes (para testing)
  void clearAllOrders() {
    _orders.clear();
    _currentOrder = null;
  }

  // Estadísticas rápidas
  int get totalOrders => _orders.length;
  int get currentOrderItemCount => _currentOrder?.totalItems ?? 0;
  double get currentOrderTotal => _currentOrder?.total ?? 0.0;
}
