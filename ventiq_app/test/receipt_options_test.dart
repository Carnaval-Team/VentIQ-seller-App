import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/models/order.dart';
import 'package:ventiq_app/utils/receipt_options.dart';

Order makeOrder({
  OrderStatus status = OrderStatus.enviada,
  int? idMesa,
  String? mesaNumero,
}) => Order(
  id: 'ORD-1',
  fechaCreacion: DateTime(2026, 10, 23),
  items: [],
  total: 100,
  status: status,
  idMesa: idMesa,
  mesaNumero: mesaNumero,
);

void main() {
  test('restaurante pendiente no imprime forma de pago', () {
    for (final status in [
      OrderStatus.borrador,
      OrderStatus.enviada,
      OrderStatus.procesando,
      OrderStatus.pendienteDeSincronizacion,
    ]) {
      final options = ReceiptOptions(
        makeOrder(status: status),
        restaurantMode: true,
      );
      expect(options.showPaymentMethod, isFalse);
    }
  });

  test('restaurante pagado conserva forma de pago', () {
    for (final status in [OrderStatus.completada, OrderStatus.pagoConfirmado]) {
      final options = ReceiptOptions(
        makeOrder(status: status),
        restaurantMode: true,
      );
      expect(options.showPaymentMethod, isTrue);
    }
  });

  test('restaurante imprime cliente y caja sin guía de almacén', () {
    final options = ReceiptOptions(makeOrder(), restaurantMode: true);
    expect(options.includeWarehouseSlip, isFalse);
    expect(options.copyCount, 2);
    expect(options.thanksMessage, 'Gracias por elegirnos');
  });

  test('mesa identifica una orden de restaurante aun sin el flag activo', () {
    final options = ReceiptOptions(
      makeOrder(idMesa: 37, mesaNumero: '  Terraza 2  '),
      restaurantMode: false,
    );
    expect(options.isRestaurant, isTrue);
    expect(options.mesaLabel, 'Terraza 2');
    expect(options.showPaymentMethod, isFalse);
    expect(options.copyCount, 2);
  });

  test('usa el ID de mesa cuando falta su número', () {
    final options = ReceiptOptions(makeOrder(idMesa: 37), restaurantMode: true);
    expect(options.mesaLabel, '37');
  });

  test('no inventa una mesa para pedidos de mostrador', () {
    final options = ReceiptOptions(makeOrder(), restaurantMode: true);
    expect(options.mesaLabel, isNull);
  });

  test('venta normal conserva mensaje, pago y tres comprobantes', () {
    final options = ReceiptOptions(makeOrder(), restaurantMode: false);
    expect(options.showPaymentMethod, isTrue);
    expect(options.includeWarehouseSlip, isTrue);
    expect(options.copyCount, 3);
    expect(options.thanksMessage, 'Gracias por su compra');
  });
}
