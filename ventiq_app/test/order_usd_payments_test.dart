import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/models/order.dart';

void main() {
  test('preserves currency and rate in local order serialization', () {
    final order = Order(
      id: 'local-1',
      fechaCreacion: DateTime.utc(2026, 9, 17),
      items: const [],
      total: 840,
      status: OrderStatus.completada,
      pagos: const [
        {'id_medio_pago': 1, 'monto': 2.0, 'moneda': 'USD', 'tasa_usd': 420.0},
      ],
    );

    final restored = Order.fromJson(order.toJson());
    final payment = restored.pagos!.single as Map<String, dynamic>;

    expect(payment['moneda'], 'USD');
    expect(payment['tasa_usd'], 420.0);
    expect(payment['monto'], 2.0);
  });

  test('legacy local orders without currency remain readable', () {
    final order = Order.fromJson({
      'id': 'legacy-1',
      'fechaCreacion': '2026-09-17T00:00:00.000Z',
      'items': <dynamic>[],
      'total': 100,
      'status': OrderStatus.completada.index,
      'pagos': [
        {'id_medio_pago': 1, 'monto': 100},
      ],
    });

    final payment = order.pagos!.single as Map<String, dynamic>;
    expect(payment['moneda'] ?? 'CUP', 'CUP');
  });
}
