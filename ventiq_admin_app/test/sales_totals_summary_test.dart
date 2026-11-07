import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/widgets/sales_totals_summary.dart';

void main() {
  for (final width in [320.0, 768.0, 1024.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('totales sin overflow a ancho $width y escala $scale', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: const Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: SalesTotalsSummary(
                      ventas: 1234567890.12,
                      costo: 999999999.99,
                      ganancia: 234567890.13,
                      showProfit: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Ventas Totales'), findsOneWidget);
        expect(find.text('Costo Total'), findsOneWidget);
        expect(find.text('Ganancia Total'), findsOneWidget);
        final venta = tester.getRect(find.text('Ventas Totales'));
        final costo = tester.getRect(find.text('Costo Total'));
        expect(venta.overlaps(costo), isFalse);
        final monto = find.text('\$1,234,567,890.12');
        expect(monto, findsOneWidget);
        expect(tester.getRect(monto).top, greaterThanOrEqualTo(venta.bottom));
        expect(tester.widget<Text>(monto).style!.fontSize, 28);
      });
    }
  }
  testWidgets('oculta costo y ganancia para roles sin permiso', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SalesTotalsSummary(
            ventas: 10,
            costo: 5,
            ganancia: 5,
            showProfit: false,
          ),
        ),
      ),
    );
    expect(find.text('Costo Total'), findsNothing);
    expect(find.text('Ganancia Total'), findsNothing);
  });
}
