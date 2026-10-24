import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/models/order.dart';
import 'package:ventiq_app/models/product.dart';
import 'package:ventiq_app/widgets/order_product_summary.dart';
import 'package:ventiq_app/utils/price_utils.dart';

OrderItem makeItem({String? name, double quantity = 2, String? presentation}) =>
    OrderItem(
      id: 'item-1',
      producto: Product(
        id: 1,
        denominacion: name ?? 'Amoxicilina 500mg (Cápsulas)',
        descripcion: 'Caja de cápsulas',
        sku: 'AMOX-500',
        precio: 620,
        cantidad: 100,
        esRefrigerado: false,
        esFragil: false,
        esPeligroso: false,
        esVendible: true,
        esComprable: true,
        esInventariable: true,
        esPorLotes: false,
        esElaborado: false,
        esServicio: false,
        categoria: 'Medicamentos',
      ),
      cantidad: quantity,
      precioUnitario: 620,
      ubicacionAlmacen: 'Almacén Principal',
      presentacionNombre: presentation,
    );

Future<void> pumpSummary(
  WidgetTester tester, {
  OrderItem? item,
  double width = 360,
  double scale = 1,
  double rate = 850,
  String currency = 'CUP',
  bool showSku = false,
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
              padding: const EdgeInsets.all(12),
              child: OrderProductSummary(
                item: item ?? makeItem(),
                currency: currency,
                usdRate: rate,
                showSku: showSku,
                formatAmount:
                    (amount) =>
                        currency == 'USD'
                            ? '${(amount / rate).toMoneyString(2)} USD'
                            : '${amount.toMoneyString(2)} CUP',
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('separa cantidad, nombre, total, almacén y precio unitario', (
    tester,
  ) async {
    await pumpSummary(tester);
    expect(find.text('2x'), findsOneWidget);
    expect(find.text('Amoxicilina 500mg (Cápsulas)'), findsOneWidget);
    expect(find.text('1\u202F240.00 CUP'), findsOneWidget);
    expect(find.text('Almacén Principal'), findsOneWidget);
    expect(find.text('620.00 CUP c/u'), findsOneWidget);
    expect(find.text('≈ 1.46 USD'), findsOneWidget);
    expect(find.text('0.73 USD / unid. aprox.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mantiene USD como moneda principal cuando corresponde', (
    tester,
  ) async {
    await pumpSummary(tester, currency: 'USD');
    expect(find.text('1.46 USD'), findsOneWidget);
    expect(find.text('≈ 1\u202F240.00 CUP'), findsOneWidget);
    expect(find.text('620.00 CUP / unid.'), findsOneWidget);
  });

  testWidgets('no inventa equivalentes sin tasa y respeta el flag SKU', (
    tester,
  ) async {
    await pumpSummary(tester, rate: 0);
    expect(find.textContaining('USD'), findsNothing);
    expect(find.text('SKU: AMOX-500'), findsNothing);
    await pumpSummary(
      tester,
      showSku: true,
      item: makeItem(presentation: 'Caja'),
    );
    expect(find.text('SKU: AMOX-500'), findsOneWidget);
    expect(find.text('Caja de cápsulas'), findsOneWidget);
    expect(find.text('Caja'), findsOneWidget);
  });

  testWidgets('el nombre y total preceden a los metadatos secundarios', (
    tester,
  ) async {
    await pumpSummary(tester);
    final name = tester.getTopLeft(find.text('Amoxicilina 500mg (Cápsulas)'));
    final total = tester.getTopLeft(find.text('1\u202F240.00 CUP'));
    final warehouse = tester.getTopLeft(find.text('Almacén Principal'));
    final unitPrice = tester.getTopLeft(find.text('620.00 CUP c/u'));
    expect(total.dx, greaterThan(name.dx));
    expect(warehouse.dy, greaterThan(name.dy));
    expect(unitPrice.dy, greaterThan(warehouse.dy));
  });

  testWidgets('nombres largos y texto ampliado no generan overflow', (
    tester,
  ) async {
    for (final width in [228.0, 320.0, 768.0]) {
      await pumpSummary(
        tester,
        width: width,
        scale: 1.8,
        showSku: true,
        item: makeItem(
          name:
              'Amoxicilina 500mg (Cápsulas) presentación especial de nombre muy largo',
          quantity: 125.5,
        ),
      );
      expect(find.text('125.5x'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Ancho $width');
    }
  });
}
