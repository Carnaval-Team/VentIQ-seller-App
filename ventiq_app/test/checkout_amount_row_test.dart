import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/utils/price_utils.dart';
import 'package:ventiq_app/widgets/checkout_amount_row.dart';

Future<void> pumpRow(
  WidgetTester tester, {
  double width = 320,
  double scale = 1,
  String label = 'Total Final:',
  String? amount,
  bool loading = false,
}) => tester.pumpWidget(
  MaterialApp(
    builder:
        (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
    home: Scaffold(
      body: SingleChildScrollView(
        child: Center(
          child: SizedBox(
            width: width,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: CheckoutAmountRow(
                label: label,
                amount: amount ?? '${PriceUtils.formatAmount(3000000)} CUP',
                isLoading: loading,
                labelStyle: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                amountStyle: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('muestra el total completo debajo de la etiqueta en móvil', (
    tester,
  ) async {
    final amount = '${PriceUtils.formatAmount(3000000)} CUP';
    await pumpRow(tester);
    expect(find.text(amount), findsOneWidget);
    expect(
      tester.getTopLeft(find.text(amount)).dy,
      greaterThan(tester.getBottomLeft(find.text('Total Final:')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('subtotal y equivalente USD no desbordan con texto ampliado', (
    tester,
  ) async {
    for (final width in [228.0, 320.0, 360.0, 768.0]) {
      for (final label in [
        'Subtotal:',
        'Total Final:',
        'Descuento promocional:',
        'Equivalente USD (1 USD = 850.00 CUP)',
        'Equivalente CUP',
      ]) {
        await pumpRow(
          tester,
          width: width,
          scale: 1.8,
          label: label,
          amount: '${PriceUtils.formatAmount(999999999.99)} USD',
        );
        expect(find.text(label), findsOneWidget);
        expect(tester.takeException(), isNull, reason: '$width / $label');
      }
    }
  });

  testWidgets('mantiene etiqueta e importe en una fila cuando hay espacio', (
    tester,
  ) async {
    await pumpRow(tester, width: 700, amount: '350.00 USD');
    expect(
      tester.getTopLeft(find.text('Total Final:')).dy,
      tester.getTopLeft(find.text('350.00 USD')).dy,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('conserva el indicador de carga de la tasa', (tester) async {
    await pumpRow(
      tester,
      label: 'Equivalente USD (1 USD = 850.00 CUP)',
      amount: 'N/D',
      loading: true,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('N/D'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
