import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/models/payment_method.dart';
import 'package:ventiq_app/services/user_preferences_service.dart';
import 'package:ventiq_app/widgets/bill_count_dialog.dart';
import 'preorder_totales_moneda_test.dart' as fixtures;

class _Preferences extends Fake implements UserPreferencesService {
  @override
  Future<Set<int>> getHiddenDenominations() async => {};

  @override
  Future<List<String>> getMonedasDisponibles() async => ['CUP', 'USD'];

  @override
  Future<List<Map<String, dynamic>>> getDenominacionesPorMoneda(
    String currency,
  ) async => [
    {
      'id': currency == 'CUP' ? 1 : 2,
      'denominacion': currency == 'CUP' ? 100 : 1,
    },
  ];
}

void main() {
  testWidgets('exige el importe nativo de cada moneda y conserva los conteos', (
    tester,
  ) async {
    var confirmed = false;
    Map<String, double>? totals;
    final order = fixtures.orden(
      version: 'producto-v1',
      items: [
        fixtures.item(
          idProducto: 1,
          precio: 100,
          cantidad: 1,
          sel: fixtures.seleccion(moneda: 'CUP', precio: '100'),
        ),
        fixtures.item(
          idProducto: 2,
          precio: 2,
          cantidad: 1,
          sel: fixtures.seleccion(moneda: 'USD', precio: '2', tasa: '400'),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BillCountDialog(
            order: order,
            expectedAmount: 900,
            userPreferencesService: _Preferences(),
            onConfirmPayment: () => confirmed = true,
            onConfirmWithTotals: (value) => totals = value,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    ElevatedButton confirmButton() => tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Confirmar Pago'),
    );
    await tester.enterText(find.byType(TextField).first, '9');
    await tester.pump();
    expect(confirmButton().onPressed, isNull);
    await tester.enterText(find.byType(TextField).first, '1');
    await tester.pump();
    expect(confirmButton().onPressed, isNull);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('USD').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '3');
    await tester.pump();
    expect(confirmButton().onPressed, isNull);
    await tester.enterText(find.byType(TextField).first, '2');
    await tester.pump();
    expect(confirmButton().onPressed, isNotNull);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CUP').last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '1',
    );
    await tester.tap(find.text('Confirmar Pago'));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
    expect(totals, {'CUP': 100, 'USD': 2});
  });

  testWidgets('preorden muestra diferencias sin incluir transferencias', (
    tester,
  ) async {
    final order = fixtures.orden(
      version: 'producto-v1',
      items: [
        fixtures.item(
          idProducto: 1,
          precio: 100,
          cantidad: 2,
          sel: fixtures.seleccion(moneda: 'CUP', precio: '100'),
        ),
        fixtures
            .item(
              idProducto: 2,
              precio: 2,
              cantidad: 1,
              sel: fixtures.seleccion(moneda: 'USD', precio: '2', tasa: '400'),
            )
            .copyWith(
              paymentMethod: PaymentMethod(
                id: 2,
                denominacion: 'Transferencia',
                esDigital: true,
                esEfectivo: false,
                esActivo: true,
              ),
            ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BillCountDialog(
            order: order,
            userPreferencesService: _Preferences(),
            closeOnly: true,
            confirmLabel: 'Cerrar',
            onConfirmPayment: () => fail('Cerrar no debe confirmar un pago'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('CUP: 0.00 / 200.00 · Falta 200.00'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '2');
    await tester.pump();
    expect(find.text('CUP: 200.00 / 200.00 · Exacto'), findsOneWidget);
    expect(find.textContaining('USD:'), findsNothing);
    expect(
      tester
          .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Cerrar'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('no permite sustituir CUP por una moneda no seleccionada', (
    tester,
  ) async {
    final order = fixtures.orden(
      version: 'producto-v1',
      items: [
        fixtures.item(
          idProducto: 1,
          precio: 100,
          cantidad: 1,
          sel: fixtures.seleccion(moneda: 'CUP', precio: '100'),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BillCountDialog(
            order: order,
            userPreferencesService: _Preferences(),
            onConfirmPayment: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '1');
    await tester.pump();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('USD').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '1');
    await tester.pump();
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Confirmar Pago'),
          )
          .onPressed,
      isNull,
    );
    expect(find.text('Sobra:'), findsOneWidget);
  });
}
