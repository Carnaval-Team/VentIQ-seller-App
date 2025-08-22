import '../models/order.dart';
import '../models/product.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_preferences_service.dart';

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
    Map<String, dynamic>? inventoryData,
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
      // Crear nuevo item con datos completos de inventario
      final newItem = OrderItem(
        id: 'ITEM-${DateTime.now().millisecondsSinceEpoch}-${order.items.length}',
        producto: producto,
        variante: variante,
        cantidad: cantidad,
        precioUnitario: precioUnitario,
        ubicacionAlmacen: ubicacionAlmacen,
        inventoryData: inventoryData,
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
  Future<Map<String, dynamic>> finalizeOrderWithDetails(Order order, Map<String, dynamic> orderData) async {
    if (order.items.isEmpty) {
      throw Exception('No hay productos en la orden');
    }

    try {
      // Registrar venta en Supabase usando fn_registrar_venta
      final result = await _registerSaleInSupabase(order, orderData);
      
      if (result['success'] == true) {
        final finalizedOrder = order.copyWith(
          status: OrderStatus.enviada,
          buyerName: orderData['buyerName'],
          buyerPhone: orderData['buyerPhone'],
          extraContacts: orderData['extraContacts'],
          paymentMethod: orderData['paymentMethod'],
          notas: orderData['notas'],
        );

        _orders.add(finalizedOrder);
        _currentOrder = null; // Limpiar orden actual
        
        return {
          'success': true,
          'operationId': result['operationId'],
          'message': 'Orden registrada exitosamente'
        };
      } else {
        return {
          'success': false,
          'error': result['error'] ?? 'Error desconocido al registrar la venta'
        };
      }
    } catch (e) {
      print('Error al finalizar orden: $e');
      return {
        'success': false,
        'error': 'Error al procesar la orden: ${e.toString()}'
      };
    }
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

  // Registrar venta en Supabase usando fn_registrar_venta
  Future<Map<String, dynamic>> _registerSaleInSupabase(Order order, Map<String, dynamic> orderData) async {
    try {
      final userPrefs = UserPreferencesService();
      final userData = await userPrefs.getUserData();
      
      // Obtener IDs por separado usando los nuevos métodos
      final idTienda = await userPrefs.getIdTienda(); // Desde app_dat_trabajadores
      final idTpv = await userPrefs.getIdTpv(); // Desde app_dat_vendedor
      final userId = userData['userId'];
      
      print('=== DEBUG PARAMETROS SUPABASE (IDs SEPARADOS) ===');
      print('userData completo: $userData');
      print('idTienda (app_dat_trabajadores): $idTienda');
      print('idTpv (app_dat_vendedor): $idTpv');
      print('userId: $userId');
      print('================================================');
      
      if (idTpv == null || idTienda == null || userId == null) {
        throw Exception('Datos de usuario incompletos - idTpv: $idTpv, idTienda: $idTienda, userId: $userId');
      }

      // Preparar productos para fn_registrar_venta
      final productos = order.items.map((item) {
        final inventoryData = item.inventoryData ?? {};
        
        return {
          'id_producto': item.producto.id,
          'id_variante': item.variante?.id,
          'id_opcion_variante': inventoryData['id_opcion_variante'],
          'id_ubicacion': inventoryData['id_ubicacion'],
          'id_presentacion': inventoryData['id_presentacion'],
          'cantidad': item.cantidad,
          'precio_unitario': item.precioUnitario,
          'sku_producto': inventoryData['sku_producto'] ?? item.producto.id.toString(),
          'sku_ubicacion': inventoryData['sku_ubicacion'],
        };
      }).toList();

      // Preparar parámetros para fn_registrar_venta
      final rpcParams = {
        'p_codigo_promocion': orderData['promoCode'],
        'p_denominacion': 'Venta App Vendedor - ${order.id}',
        'p_estado_inicial': 1,
        'p_id_tpv': idTpv,
        'p_observaciones': orderData['notas'] ?? 'Venta realizada desde app móvil',
        'p_productos': productos,
        'p_uuid': userId,
        'p_id_cliente':orderData['idCliente']
      };

      print('=== PARAMETROS RPC fn_registrar_venta ===');
      print('p_codigo_promocion: ${rpcParams['p_codigo_promocion']}');
      print('p_denominacion: ${rpcParams['p_denominacion']}');
      print('p_estado_inicial: ${rpcParams['p_estado_inicial']}');
      print('p_id_tpv: ${rpcParams['p_id_tpv']}');
      print('p_observaciones: ${rpcParams['p_observaciones']}');
      print('p_uuid: ${rpcParams['p_uuid']}');
      print('p_productos (${productos.length} items): $productos');
      print('order_cli ${orderData['idCliente']}');
      print('========================================');

      // Llamar a fn_registrar_venta
      final response = await Supabase.instance.client.rpc(
        'fn_registrar_venta',
        params: rpcParams,
      );

      print('Respuesta fn_registrar_venta: $response');
      
      if (response != null && response['status'] == 'success') {
        return {
          'success': true,
          'operationId': response['operation_id'],
          'data': response
        };
      } else {
        return {
          'success': false,
          'error': response?['message'] ?? 'Error en el registro de venta'
        };
      }
    } catch (e) {
      print('Error en _registerSaleInSupabase: $e');
      return {
        'success': false,
        'error': e.toString()
      };
    }
  }

  // Listar órdenes desde Supabase
  Future<void> listOrdersFromSupabase() async {
    try {
      final userPrefs = UserPreferencesService();
      final userData = await userPrefs.getUserData();
      
      // Obtener IDs necesarios
      final idTienda = await userPrefs.getIdTienda();
      final idTpv = await userPrefs.getIdTpv();
      final userId = userData['userId'];
      
      // Configurar fechas del día actual
      final now = DateTime.now();
      final fechaDesde = DateTime(now.year, now.month, now.day);
      final fechaHasta = DateTime(now.year, now.month, now.day);
      
      print('=== DEBUG PARAMETROS LISTAR ORDENES ===');
      print('idTienda: $idTienda');
      print('idTpv: $idTpv');
      print('userId: $userId');
      print('fechaDesde: $fechaDesde');
      print('fechaHasta: $fechaHasta');
      print('======================================');
      
      // Preparar parámetros para listar_ordenes
      final rpcParams = {
        'con_inventario_param': false,
        'fecha_desde_param': fechaDesde.toIso8601String().split('T')[0], // Solo fecha YYYY-MM-DD
        'fecha_hasta_param': fechaDesde.toIso8601String().split('T')[0], // Solo fecha YYYY-MM-DD
        'id_estado_param': null, // Todos los estados
        'id_tienda_param': idTienda,
        'id_tipo_operacion_param': null, // Todas las operaciones
        'id_tpv_param': idTpv,
        'id_usuario_param': userId,
        'limite_param': null, // 0 para traer todas
        'pagina_param': null,
        'solo_pendientes_param': false,
      };

      print('=== PARAMETROS RPC listar_ordenes ===');
      print('con_inventario_param: ${rpcParams['con_inventario_param']}');
      print('fecha_desde_param: ${rpcParams['fecha_desde_param']}');
      print('fecha_hasta_param: ${rpcParams['fecha_hasta_param']}');
      print('id_estado_param: ${rpcParams['id_estado_param']}');
      print('id_tienda_param: ${rpcParams['id_tienda_param']}');
      print('id_tipo_operacion_param: ${rpcParams['id_tipo_operacion_param']}');
      print('id_tpv_param: ${rpcParams['id_tpv_param']}');
      print('id_usuario_param: ${rpcParams['id_usuario_param']}');
      print('limite_param: ${rpcParams['limite_param']}');
      print('pagina_param: ${rpcParams['pagina_param']}');
      print('solo_pendientes_param: ${rpcParams['solo_pendientes_param']}');
      print('==========================================');

      // Llamar a listar_ordenes
      final response = await Supabase.instance.client.rpc(
        'listar_ordenes',
        params: rpcParams,
      );

      print('=== RESPUESTA listar_ordenes ===');
      print('Tipo de respuesta: ${response.runtimeType}');
      print('Cantidad de órdenes: ${response is List ? response.length : 'No es lista'}');
      print('Respuesta completa:');
      print(response);
      print('===============================');
      
      if (response is List && response.isNotEmpty) {
        print('=== PRIMERA ORDEN (EJEMPLO) ===');
        print(response.first);
        print('==============================');
      }
      
    } catch (e) {
      print('Error en listOrdersFromSupabase: $e');
    }
  }

  // Estadísticas rápidas
  int get totalOrders => _orders.length;
  int get currentOrderItemCount => _currentOrder?.totalItems ?? 0;
  double get currentOrderTotal => _currentOrder?.total ?? 0.0;
}
