import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventiq_app/services/user_preferences_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/models/payment_method.dart';
import 'package:ventiq_app/widgets/checkout_payment_lines_editor.dart';
import 'package:ventiq_app/utils/price_utils.dart';

void main() {
  final efectivo = PaymentMethod(
    id: 1,
    denominacion: 'Efectivo',
    esDigital: false,
    esEfectivo: true,
    esActivo: true,
  );

  testWidgets(
    'splits the same method into CUP and USD without changing the total',
    (tester) async {
      List<Map<String, dynamic>>? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CheckoutPaymentLinesEditor(
              initialPayments: const [
                {'id_medio_pago': 1, 'monto': 940.0, 'moneda': 'CUP'},
              ],
              methods: [efectivo],
              rates: const {'CUP': 1, 'USD': 420},
              totalCup: 940,
              onSave: (lines) => saved = lines,
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextFormField).first, '100');
      await tester.tap(find.text('Añadir pago'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('currency-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('USD').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).last, '2');
      await tester.pump();
      await tester.ensureVisible(find.text('Guardar desglose'));
      await tester.tap(find.text('Guardar desglose'));
      await tester.pump();
      expect(saved, hasLength(2));
      expect(saved![0]['moneda'], 'CUP');
      expect(saved![1]['moneda'], 'USD');
      expect(saved![1]['monto'], 2);
      expect(saved![1]['tasa_cambio'], 420);
      expect(PriceUtils.paymentTotalCup(saved!), 940);
    },
  );

  testWidgets(
    'multiple methods and three currencies survive offline persistence',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final transfer = PaymentMethod(
        id: 2,
        denominacion: 'Transferencia',
        esDigital: true,
        esEfectivo: false,
        esActivo: true,
      );
      List<Map<String, dynamic>>? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CheckoutPaymentLinesEditor(
              initialPayments: const [
                {'id_medio_pago': 1, 'monto': 100.0, 'moneda': 'CUP'},
                {'id_medio_pago': 1, 'monto': 2.0, 'moneda': 'USD'},
                {'id_medio_pago': 2, 'monto': 1.0, 'moneda': 'EUR'},
              ],
              methods: [efectivo, transfer],
              rates: const {'CUP': 1, 'USD': 420, 'EUR': 500},
              totalCup: 1440,
              onSave: (lines) => saved = lines,
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.text('Guardar desglose'));
      await tester.tap(find.text('Guardar desglose'));
      await tester.pump();
      expect(saved, hasLength(3));
      expect(saved!.last['es_transferencia'], true);
      expect(saved!.last['tasa_usd'], isNull);
      final prefs = UserPreferencesService();
      await prefs.savePendingOrder({
        'id': 'mixed-checkout',
        'desglose_pagos': saved,
      });
      final restored = List<Map<String, dynamic>>.from(
        (await prefs.getPendingOrders()).single['desglose_pagos'],
      );
      expect(restored, saved);
      expect(PriceUtils.paymentTotalCup(restored), 1440);
      expect(PriceUtils.paymentTotalIn(restored, 'USD'), 2);
      expect(PriceUtils.paymentTotalIn(restored, 'EUR'), 1);
    },
  );

  testWidgets('removing a line does not mutate the original payments', (
    tester,
  ) async {
    final initial = <Map<String, dynamic>>[
      {'id_medio_pago': 1, 'monto': 100.0, 'moneda': 'CUP'},
      {'id_medio_pago': 1, 'monto': 2.0, 'moneda': 'USD'},
    ];
    List<Map<String, dynamic>>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CheckoutPaymentLinesEditor(
            initialPayments: initial,
            methods: [efectivo],
            rates: const {'CUP': 1, 'USD': 420},
            totalCup: 840,
            onSave: (lines) => saved = lines,
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Eliminar pago 1'));
    await tester.pump();
    await tester.tap(find.text('Guardar desglose'));
    await tester.pump();
    expect(saved, hasLength(1));
    expect(saved!.single['moneda'], 'USD');
    expect(initial, hasLength(2));
    expect(initial.first['monto'], 100);
  });

  testWidgets('does not save an unbalanced or invalid breakdown', (
    tester,
  ) async {
    var saved = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CheckoutPaymentLinesEditor(
            initialPayments: const [
              {'id_medio_pago': 1, 'monto': 100.0, 'moneda': 'CUP'},
            ],
            methods: [efectivo],
            rates: const {'CUP': 1},
            totalCup: 940,
            onSave: (_) => saved = true,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Guardar desglose'));
    await tester.pump();
    expect(saved, false);
    await tester.enterText(find.byType(TextFormField), 'NaN');
    await tester.tap(find.text('Guardar desglose'));
    await tester.pump();
    expect(saved, false);
    expect(find.text('Introduce un importe mayor que cero'), findsOneWidget);
  });
}
