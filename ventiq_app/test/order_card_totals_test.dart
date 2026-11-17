import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/models/order.dart';
import 'package:ventiq_app/money/product_currency_order.dart';
import 'package:ventiq_app/screens/orders_screen.dart';
import 'preorder_totales_moneda_test.dart' as fixtures;

void main() {
  testWidgets(
    'listado offline conserva CUP y USD sin convertir el total escalar',
    (tester) async {
      final saved = fixtures
          .orden(
            version: 'producto-v1',
            items: [
              fixtures.item(
                idProducto: 1,
                precio: 100,
                cantidad: 2,
                sel: ProductCurrencySeleccion.fromJson({
                  ...fixtures.seleccion(moneda: 'CUP', precio: '100').toJson(),
                  'cantidad': '2',
                }),
              ),
              fixtures.item(
                idProducto: 2,
                precio: 1.05,
                cantidad: 3,
                sel: ProductCurrencySeleccion.fromJson({
                  ...fixtures
                      .seleccion(moneda: 'USD', precio: '1.05', tasa: '400')
                      .toJson(),
                  'cantidad': '3',
                }),
              ),
            ],
          )
          .copyWith(
            isOfflineOrder: true,
            clientUuid: '00000000-0000-4000-8000-000000000001',
          );
      final restored = Order.fromJson(jsonDecode(jsonEncode(saved.toJson())));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: OrderCardNativeTotals(order: restored)),
        ),
      );
      expect(find.text('200.00 CUP'), findsOneWidget);
      expect(find.text('3.15 USD'), findsOneWidget);
      expect(find.text('Equiv. CUP: 1\u202F460.00 CUP'), findsOneWidget);
      expect(find.textContaining('203.15'), findsNothing);
    },
  );

  testWidgets('una orden offline solo USD muestra su importe nativo', (
    tester,
  ) async {
    final order = fixtures
        .orden(
          version: 'producto-v1',
          items: [
            fixtures.item(
              idProducto: 2,
              precio: 2,
              cantidad: 3,
              sel: ProductCurrencySeleccion.fromJson({
                ...fixtures
                    .seleccion(moneda: 'USD', precio: '2', tasa: '400')
                    .toJson(),
                'cantidad': '3',
              }),
            ),
          ],
        )
        .copyWith(isOfflineOrder: true, total: 2400);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: OrderCardNativeTotals(order: order))),
    );
    expect(find.text('6.00 USD'), findsOneWidget);
    expect(find.text('Equiv. CUP: 2\u202F400.00 CUP'), findsOneWidget);
  });
}
