import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/models/order.dart';
import 'package:ventiq_app/services/mesa_service.dart';

Order order(String id, OrderStatus status, int minute, {int idMesa = 4}) => Order(
  id: id,
  fechaCreacion: DateTime(2026, 10, 23, 12, minute),
  items: [],
  total: 100,
  status: status,
  idMesa: idMesa,
);

void main() {
  test('sin órdenes pendientes conserva la vista por defecto', () {
    expect(MesaService.mostRecentPendingOrder([], idMesa: 4), isNull);
    expect(
      MesaService.mostRecentPendingOrder([
        order('1', OrderStatus.completada, 1),
        order('2', OrderStatus.pagoConfirmado, 2),
        order('3', OrderStatus.cancelada, 3),
        order('4', OrderStatus.devuelta, 4),
      ], idMesa: 4),
      isNull,
    );
  });

  test('abre la orden pendiente más reciente de la mesa', () {
    final older = order('1', OrderStatus.enviada, 1);
    final recent = order('2', OrderStatus.enviada, 2);
    final source = [older, recent, order('3', OrderStatus.completada, 3)];
    expect(
      MesaService.mostRecentPendingOrder(source, idMesa: 4)?.id,
      '2',
    );
    expect(source.map((o) => o.id), ['1', '2', '3']);
  });

  test('nunca abre la orden pendiente de otra mesa', () {
    expect(
      MesaService.mostRecentPendingOrder([
        order('1', OrderStatus.enviada, 1),
        order('2', OrderStatus.enviada, 2, idMesa: 9),
      ], idMesa: 4)?.id,
      '1',
    );
  });

  test('respeta los estados activos actuales del detalle de mesa', () {
    for (final status in [
      OrderStatus.borrador,
      OrderStatus.enviada,
      OrderStatus.procesando,
      OrderStatus.pendienteDeSincronizacion,
    ]) {
      expect(
        MesaService.mostRecentPendingOrder([
          order('1', status, 1),
        ], idMesa: 4)?.id,
        '1',
      );
    }
  });
}
