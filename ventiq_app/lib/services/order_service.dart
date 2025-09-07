import '../models/order.dart';
import '../models/product.dart';
import '../models/payment_method.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_preferences_service.dart';
import 'turno_service.dart'; // Import TurnoService

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
    if (_currentOrder == null ||
        _currentOrder!.status != OrderStatus.borrador) {
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
    double? precioUnitario,
    double? precioBase,
  }) {
    final order = getCurrentOrCreateOrder();
    final precio = precioUnitario ?? (variante?.precio ?? producto.precio);
    final precioOriginal = precioBase ?? (variante?.precio ?? producto.precio);

    // Verificar si ya existe un item similar
    final existingItemIndex = order.items.indexWhere(
      (item) =>
          item.producto.id == producto.id &&
          ((item.variante == null && variante == null) ||
              (item.variante?.id == variante?.id)),
    );

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
        precioUnitario: precio,
        precioBase: precioOriginal,
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

    final itemIndex = _currentOrder!.items.indexWhere(
      (item) => item.id == itemId,
    );
    if (itemIndex != -1) {
      if (newQuantity <= 0) {
        _currentOrder!.items.removeAt(itemIndex);
      } else {
        _currentOrder!.items[itemIndex] = _currentOrder!.items[itemIndex]
            .copyWith(cantidad: newQuantity);
      }
      _updateOrderTotal(_currentOrder!);
    }
  }

  // Actualizar método de pago de un item
  void updateItemPaymentMethod(String itemId, PaymentMethod? paymentMethod) {
    if (_currentOrder == null) return;

    final itemIndex = _currentOrder!.items.indexWhere(
      (item) => item.id == itemId,
    );
    if (itemIndex != -1) {
      _currentOrder!.items[itemIndex] = _currentOrder!.items[itemIndex]
          .copyWith(paymentMethod: paymentMethod);

      // Recalcular total ya que el precio puede cambiar según el método de pago
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
  Future<Map<String, dynamic>> finalizeOrderWithDetails(
    Order order,
    Map<String, dynamic> orderData,
  ) async {
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
          'message': 'Orden registrada exitosamente',
        };
      } else {
        return {
          'success': false,
          'error': result['error'] ?? 'Error desconocido al registrar la venta',
        };
      }
    } catch (e) {
      print('Error al finalizar orden: $e');
      return {
        'success': false,
        'error': 'Error al procesar la orden: ${e.toString()}',
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
  Future<Map<String, dynamic>> updateOrderStatus(
    String orderId,
    OrderStatus newStatus,
  ) async {
    try {
      // Extraer el ID de operación del orderId (formato: ORD-{id_operacion})
      final operationId = int.tryParse(orderId.replaceFirst('ORD-', ''));
      if (operationId == null) {
        return {'success': false, 'error': 'ID de orden inválido: $orderId'};
      }

      // Actualizar estado en Supabase
      final supabaseResult = await updateOrderStatusInSupabase(
        operationId,
        newStatus,
      );

      if (supabaseResult['success'] == true) {
        // Actualizar estado local solo si Supabase fue exitoso
        final orderIndex = _orders.indexWhere((order) => order.id == orderId);
        if (orderIndex != -1) {
          final updatedOrder = _orders[orderIndex].copyWith(status: newStatus);
          _orders[orderIndex] = updatedOrder;
        }

        return {'success': true, 'message': 'Estado actualizado correctamente'};
      } else {
        return supabaseResult;
      }
    } catch (e) {
      print('Error en updateOrderStatus: $e');
      return {
        'success': false,
        'error': 'Error al actualizar estado: ${e.toString()}',
      };
    }
  }

  // Actualizar estado de orden en Supabase usando fn_registrar_cambio_estado_operacion
  Future<Map<String, dynamic>> updateOrderStatusInSupabase(
    int operationId,
    OrderStatus newStatus,
  ) async {
    try {
      final userPrefs = UserPreferencesService();
      final userData = await userPrefs.getUserData();
      final userId = userData['userId'];

      if (userId == null) {
        throw Exception('Usuario no encontrado en preferencias');
      }

      // Mapear OrderStatus a valores numéricos de Supabase
      final statusNumber = _mapOrderStatusToSupabaseNumber(newStatus);

      print('=== DEBUG CAMBIO ESTADO ORDEN ===');
      print('operationId: $operationId');
      print('newStatus: $newStatus');
      print('statusNumber: $statusNumber');
      print('userId: $userId');
      print('================================');

      // Llamar a fn_registrar_cambio_estado_operacion
      final response = await Supabase.instance.client.rpc(
        'fn_registrar_cambio_estado_operacion',
        params: {
          'p_id_operacion': operationId,
          'p_nuevo_estado': statusNumber,
          'p_uuid_usuario': userId,
        },
      );

      print('Respuesta fn_registrar_cambio_estado_operacion: $response');

      return {
        'success': true,
        'message': 'Estado actualizado en Supabase',
        'data': response,
      };
    } catch (e) {
      print('Error en updateOrderStatusInSupabase: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // Mapear OrderStatus a valores numéricos de Supabase
  int _mapOrderStatusToSupabaseNumber(OrderStatus status) {
    switch (status) {
      case OrderStatus.enviada:
      case OrderStatus.procesando:
        return 1; // Pendiente
      case OrderStatus.pagoConfirmado:
      case OrderStatus.completada:
        return 2; // Completado
      case OrderStatus.devuelta:
        return 3; // Devuelta
      case OrderStatus.cancelada:
        return 4; // Cancelada
      default:
        return 1; // Por defecto pendiente
    }
  }

  // Limpiar todas las órdenes (para testing y logout)
  void clearAllOrders() {
    _orders.clear();
    _currentOrder = null;
    print('OrderService: Todas las órdenes han sido limpiadas');
  }

  // Obtener desglose de pagos de una venta específica
  Future<List<Map<String, dynamic>>> getSalePayments(int operationId) async {
    try {
      print('=== DEBUG GET SALE PAYMENTS ===');
      print('operationId: $operationId');

      final response = await Supabase.instance.client.rpc(
        'get_sale_payments',
        params: {'p_operacion_venta_id': operationId},
      );

      print('Respuesta get_sale_payments: $response');

      if (response is List) {
        return List<Map<String, dynamic>>.from(response);
      } else {
        print('Respuesta no es una lista: ${response.runtimeType}');
        return [];
      }
    } catch (e) {
      print('Error en getSalePayments: $e');
      return [];
    }
  }

  // Registrar venta en Supabase usando fn_registrar_venta
  Future<Map<String, dynamic>> _registerSaleInSupabase(
    Order order,
    Map<String, dynamic> orderData,
  ) async {
    try {
      // First, validate that there's an open shift
      final turnoAbierto = await TurnoService.getTurnoAbierto();

      if (turnoAbierto == null) {
        return {
          'success': false,
          'error':
              'No se puede crear una operación sin un turno abierto. Debe abrir un turno primero.',
        };
      }

      final userPrefs = UserPreferencesService();
      final userData = await userPrefs.getUserData();

      // Obtener IDs por separado usando los nuevos métodos
      final idTienda =
          await userPrefs.getIdTienda(); // Desde app_dat_trabajadores
      final idTpv = await userPrefs.getIdTpv(); // Desde app_dat_vendedor
      final userId = userData['userId'];

      print('=== DEBUG PARAMETROS SUPABASE (IDs SEPARADOS) ===');
      print('userData completo: $userData');
      print('idTienda (app_dat_trabajadores): $idTienda');
      print('idTpv (app_dat_vendedor): $idTpv');
      print('userId: $userId');
      print('Turno abierto ID: ${turnoAbierto['id']}');
      print('================================================');

      if (idTpv == null || idTienda == null || userId == null) {
        throw Exception(
          'Datos de usuario incompletos - idTpv: $idTpv, idTienda: $idTienda, userId: $userId',
        );
      }

      // Preparar productos para fn_registrar_venta
      final productos =
          order.items.map((item) {
            final inventoryData = item.inventoryData ?? {};

            print('ID del producto: ${item.producto.id}');
            print(
              'ID de la variante (si aplica): ${inventoryData['id_variante']}',
            );
            print('ID de la ubicación: ${inventoryData['id_ubicacion']}');
            print('Cantidad a descontar: ${item.cantidad}');

            return {
              'id_producto': item.producto.id,
              'id_variante': inventoryData['id_variante'],
              'id_opcion_variante': inventoryData['id_opcion_variante'],
              'id_ubicacion': inventoryData['id_ubicacion'],
              'id_presentacion': inventoryData['id_presentacion'],
              'cantidad': item.cantidad,
              'precio_unitario': item.precioUnitario,
              'sku_producto':
                  inventoryData['sku_producto'] ?? item.producto.id.toString(),
              'sku_ubicacion': inventoryData['sku_ubicacion'],
            };
          }).toList();

      // Preparar parámetros para fn_registrar_venta
      final rpcParams = {
        'p_codigo_promocion': orderData['promoCode'],
        'p_denominacion': 'Venta App Vendedor - ${order.id}',
        'p_estado_inicial': 1,
        'p_id_tpv': idTpv,
        'p_observaciones':
            orderData['notas'] ?? 'Venta realizada desde app móvil',
        'p_productos': productos,
        'p_uuid': userId,
        'p_id_cliente': orderData['idCliente'],
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
        // After successful order creation, register payments
        final operationId = response['id_operacion'] as int?;
        if (operationId == null) {
          return {
            'success': false,
            'error': 'No se recibió ID de operación válido del servidor',
          };
        }
        final paymentResult = await _registerPaymentsInSupabase(
          order,
          operationId,
        );

        if (paymentResult['success'] == true) {
          return {
            'success': true,
            'operationId': operationId,
            'data': response,
            'paymentData': paymentResult['data'],
          };
        } else {
          // Order was created but payment registration failed
          print(
            'Warning: Order created but payment registration failed: ${paymentResult['error']}',
          );
          return {
            'success': true,
            'operationId': operationId,
            'data': response,
            'paymentWarning':
                'Orden creada pero falló el registro de pagos: ${paymentResult['error']}',
          };
        }
      } else {
        return {
          'success': false,
          'error': response?['message'] ?? 'Error en el registro de venta',
        };
      }
    } catch (e) {
      print('Error en _registerSaleInSupabase: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // Registrar pagos en Supabase usando fn_registrar_pago_venta
  Future<Map<String, dynamic>> _registerPaymentsInSupabase(
    Order order,
    int operationId,
  ) async {
    try {
      print('=== DEBUG REGISTRO DE PAGOS ===');
      print('operationId: $operationId');
      print('order.items.length: ${order.items.length}');

      // Agrupar pagos por método de pago
      Map<int, double> paymentsByMethod = {};

      for (final item in order.items) {
        if (item.paymentMethod != null) {
          final methodId = item.paymentMethod!.id;
          final itemTotal = item.subtotal;

          paymentsByMethod[methodId] =
              (paymentsByMethod[methodId] ?? 0.0) + itemTotal;

          print('Item: ${item.nombre}');
          print(
            'Payment Method: ${item.paymentMethod!.denominacion} (ID: $methodId)',
          );
          print('Item Total: \$${itemTotal.toStringAsFixed(2)}');
        } else {
          print('Warning: Item ${item.nombre} has no payment method assigned');
        }
      }

      print('Payments by method: $paymentsByMethod');

      if (paymentsByMethod.isEmpty) {
        return {
          'success': false,
          'error':
              'No se encontraron métodos de pago asignados a los productos',
        };
      }

      // Preparar array de pagos para la función RPC
      List<Map<String, dynamic>> pagos = [];

      for (final entry in paymentsByMethod.entries) {
        pagos.add({
          'id_medio_pago': entry.key,
          'monto': entry.value,
          'referencia_pago':
              'Pago App Vendedor - ${DateTime.now().millisecondsSinceEpoch}',
        });
      }

      print('Pagos array: $pagos');

      // Llamar a fn_registrar_pago_venta
      final response = await Supabase.instance.client.rpc(
        'fn_registrar_pago_venta',
        params: {'p_id_operacion_venta': operationId, 'p_pagos': pagos},
      );

      print('Respuesta fn_registrar_pago_venta: $response');

      if (response == true) {
        return {
          'success': true,
          'data': response,
          'paymentsRegistered': pagos.length,
        };
      } else {
        return {
          'success': false,
          'error': 'La función fn_registrar_pago_venta retornó: $response',
        };
      }
    } catch (e) {
      print('Error en _registerPaymentsInSupabase: $e');
      return {
        'success': false,
        'error': 'Error al registrar pagos: ${e.toString()}',
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

      print('=== DEBUG PARAMETROS LISTAR ORDENES ===');
      print('idTienda: $idTienda');
      print('idTpv: $idTpv');
      print('userId: $userId');
      print('Sin filtro de fecha - mostrando todas las órdenes');
      print('======================================');

      // Preparar parámetros para listar_ordenes sin filtro de fecha
      final rpcParams = {
        'con_inventario_param': false,
        'fecha_desde_param': null, // Sin filtro de fecha desde
        'fecha_hasta_param': null, // Sin filtro de fecha hasta
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
      print(
        'fecha_desde_param: ${rpcParams['fecha_desde_param']} (SIN FILTRO)',
      );
      print(
        'fecha_hasta_param: ${rpcParams['fecha_hasta_param']} (SIN FILTRO)',
      );
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
      print(
        'Cantidad de órdenes: ${response is List ? response.length : 'No es lista'}',
      );
      print('Respuesta completa:');
      print(response);
      print('===============================');

      if (response is List && response.isNotEmpty) {
        print('=== PRIMERA ORDEN (EJEMPLO) ===');
        print(response.first);
        print('==============================');

        // Transformar respuesta de Supabase a modelo Order
        _transformSupabaseToOrders(response);
      }
    } catch (e) {
      print('Error en listOrdersFromSupabase: $e');
    }
  }

  // Transformar datos de Supabase al modelo Order existente
  void _transformSupabaseToOrders(List<dynamic> supabaseOrders) {
    try {
      print('=== TRANSFORMANDO ORDENES DE SUPABASE ===');
      print('Órdenes recibidas: ${supabaseOrders.length}');

      // SIEMPRE limpiar órdenes existentes al cargar desde Supabase
      // Esto evita que se mezclen órdenes de usuarios anteriores
      _orders.clear();
      print('Órdenes locales limpiadas');

      // Si no hay órdenes, simplemente retornar con la lista vacía
      if (supabaseOrders.isEmpty) {
        print('No hay órdenes para mostrar - lista queda vacía');
        print('===========================================');
        return;
      }

      for (var supabaseOrder in supabaseOrders) {
        // Extraer items de la respuesta
        List<OrderItem> orderItems = [];
        final detalles = supabaseOrder['detalles'];
        if (detalles != null && detalles['items'] != null) {
          final items = detalles['items'] as List<dynamic>;

          for (var item in items) {
            // Crear producto desde los datos de Supabase
            final product = Product(
              id: item['id_producto'],
              denominacion: item['producto_nombre'] ?? 'Producto',
              precio: (item['precio_unitario'] ?? 0.0).toDouble(),
              cantidad: (item['cantidad'] ?? 1).toInt(),
              esRefrigerado: false,
              esFragil: false,
              esPeligroso: false,
              esVendible: true,
              esComprable: true,
              esInventariable: true,
              esPorLotes: false,
              categoria: 'General',
              descripcion: item['presentacion'] ?? '',
              foto: null,
            );

            // Crear variante si existe
            ProductVariant? variant;
            if (item['variante'] != null) {
              final variantData = item['variante'];
              print(variantData['opcion']);
              variant = ProductVariant(
                id: variantData['id'],
                nombre:
                    '(' +
                    (variantData['atributo'] ?? '') +
                    ' : ' +
                    (variantData['opcion'] ?? '') +
                    ')',
                precio: (item['precio_unitario'] ?? 0.0).toDouble(),
                cantidad: (item['cantidad'] ?? 1).toInt(),
                descripcion: variantData['opcion'],
              );
            }

            // Crear OrderItem
            final orderItem = OrderItem(
              id:
                  'ITEM-${item['id_producto']}-${DateTime.now().millisecondsSinceEpoch}',
              producto: product,
              variante: variant,
              cantidad: (item['cantidad'] ?? 1).toInt(),
              precioUnitario: (item['precio_unitario'] ?? 0.0).toDouble(),
              ubicacionAlmacen: 'Principal', // Valor por defecto
            );

            orderItems.add(orderItem);
          }
        }

        // Extraer información del cliente
        final clienteData = supabaseOrder['detalles']?['cliente'];
        final clienteNombre =
            clienteData?['nombre_completo'] ??
            supabaseOrder['usuario_nombre'] ??
            'Cliente';
        final clienteTelefono = clienteData?['telefono']?.toString() ?? '';

        // Crear orden desde los datos de Supabase
        final order = Order(
          id: 'ORD-${supabaseOrder['id_operacion']}',
          fechaCreacion: DateTime.parse(supabaseOrder['fecha_operacion']),
          status: _mapSupabaseStatusToOrderStatus(supabaseOrder['estado']),
          total: (supabaseOrder['total_operacion'] ?? 0.0).toDouble(),
          items: orderItems,
          buyerName: clienteNombre,
          buyerPhone: clienteTelefono,
          extraContacts: '', // String vacío por defecto
          paymentMethod: 'Efectivo', // Valor por defecto
          notas: supabaseOrder['observaciones'] ?? '',
          operationId: supabaseOrder['id_operacion'],
        );

        _orders.add(order);
      }

      print('Transformadas ${_orders.length} órdenes de Supabase');
      print('===========================================');
    } catch (e) {
      print('Error transformando órdenes de Supabase: $e');
    }
  }

  // Mapear estado numérico de Supabase a OrderStatus
  OrderStatus _mapSupabaseStatusToOrderStatus(int? estado) {
    switch (estado) {
      case 1:
        return OrderStatus
            .enviada; // Pendiente -> enviada para agrupar como pendiente
      case 2:
        return OrderStatus.completada;
      case 3:
        return OrderStatus.devuelta;
      case 4:
        return OrderStatus.cancelada;
      default:
        return OrderStatus.enviada;
    }
  }

  // Extraer nombre del comprador (por ahora no disponible en respuesta)

  // Estadísticas rápidas
  int get totalOrders => _orders.length;
  int get currentOrderItemCount => _currentOrder?.totalItems ?? 0;
  double get currentOrderTotal => _currentOrder?.total ?? 0.0;
}
