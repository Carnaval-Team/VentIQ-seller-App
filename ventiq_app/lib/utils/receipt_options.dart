import '../models/order.dart';

class ReceiptOptions {
  final Order order;
  final bool restaurantMode;

  const ReceiptOptions(this.order, {required this.restaurantMode});

  bool get isRestaurant =>
      restaurantMode ||
      order.idMesa != null ||
      (order.mesaNumero?.trim().isNotEmpty ?? false);

  bool get showPaymentMethod =>
      !isRestaurant ||
      ![
        OrderStatus.borrador,
        OrderStatus.enviada,
        OrderStatus.procesando,
        OrderStatus.pendienteDeSincronizacion,
      ].contains(order.status);

  String? get mesaLabel {
    final numero = order.mesaNumero?.trim();
    if (numero != null && numero.isNotEmpty) return numero;
    return order.idMesa?.toString();
  }

  bool get includeWarehouseSlip => !isRestaurant;
  int get copyCount => includeWarehouseSlip ? 3 : 2;
  String get thanksMessage =>
      isRestaurant ? 'Gracias por elegirnos' : 'Gracias por su compra';
}
