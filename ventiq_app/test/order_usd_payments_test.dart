import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/models/order.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventiq_app/services/order_service.dart';
import 'package:ventiq_app/services/user_preferences_service.dart';
import 'package:ventiq_app/utils/price_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final fullTransfer in [false, true]) {
    for (final existingCup in [false, true]) {
      test(
        'moving USD preserves currency (full=$fullTransfer, CUP=$existingCup)',
        () async {
          SharedPreferences.setMockInitialValues({});
          final prefs = UserPreferencesService();
          await prefs.setOfflineMode(true);
          final id = 'move-usd-$fullTransfer-$existingCup';
          final data = <String, dynamic>{
            'id': id,
            'fecha_creacion': '2026-11-11T10:00:00',
            'items': <dynamic>[],
            'total': existingCup ? 940 : 840,
            'desglose_pagos': [
              {
                'id_medio_pago': 1,
                'monto': 2.0,
                'moneda': 'USD',
                'tasa_usd': 420.0,
                'monto_cup_equivalente': 840.0,
              },
              if (existingCup)
                {'id_medio_pago': 2, 'monto': 100.0, 'moneda': 'CUP'},
            ],
          };
          await prefs.savePendingOrder(data);
          final service = OrderService();
          service.addPendingOrdersToList([data]);
          final result = await service.moveSalePaymentAmount(
            orderId: id,
            fromPaymentMethodId: 1,
            toPaymentMethodId: 2,
            amount: fullTransfer ? 2 : 1,
          );
          expect(result['success'], true);
          final saved = (await prefs.getPendingOrders()).single;
          final payments = List<Map<String, dynamic>>.from(
            saved['desglose_pagos'] as List,
          );
          final destination = payments.singleWhere(
            (p) => p['id_medio_pago'] == 2 && p['moneda'] == 'USD',
          );
          expect(destination['monto'], fullTransfer ? 2 : 1);
          expect(PriceUtils.paymentRate(destination), 420);
          expect(PriceUtils.paymentTotalUsd(payments), 2);
          expect(PriceUtils.paymentTotalCup(payments), existingCup ? 940 : 840);
          if (!fullTransfer) {
            final source = payments.singleWhere((p) => p['id_medio_pago'] == 1);
            expect(source['monto_cup_equivalente'], 420);
          }
          if (existingCup) {
            expect(
              payments.singleWhere((p) => p['moneda'] == 'CUP')['monto'],
              100,
            );
          }
        },
      );
    }
  }

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
