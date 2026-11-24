// Responsive de la tabla densa (fase 10).
//
// El fallo que esto vigila: `TablaReporte` metía la tabla en un scroll
// horizontal cuando no cabía. En un móvil de 360-390 px eso dejaba las columnas
// de dinero fuera de la pantalla, sin ninguna pista, y el usuario veía «no se
// ven los números». Aquí se comprueba que por debajo del corte NO hay scroll
// horizontal y que las cifras se renderizan igual.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/screens/reportes/reportes_widgets.dart';

void _tamano(WidgetTester tester, Size tamano) {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _tabla() => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: TablaReporte(
        columnas: const [
          ColumnaReporte('Compra', 200),
          ColumnaReporte('Proveedor', 200),
          ColumnaReporte('Monto pendiente', 140, derecha: true),
          ColumnaReporte('Estado', 120),
        ],
        filas: [
          FilaReporte([
            celdaTexto('A-1042'),
            celdaTexto('Distribuidora Andina'),
            celdaCifra('7.845,50 USD'),
            celdaTexto('Entrega parcial'),
          ]),
        ],
      ),
    ),
  ),
);

/// ¿Hay algún scroll horizontal en el árbol? Es la comprobación que los tests
/// de desborde no hacen: un scroll horizontal no lanza excepción, solo esconde
/// contenido a la derecha.
bool _hayScrollHorizontal(WidgetTester tester) {
  return tester
      .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
      .any((s) => s.scrollDirection == Axis.horizontal);
}

void main() {
  group('TablaReporte en móvil', () {
    testWidgets('a 360 px no hay scroll horizontal y la cifra se ve', (
      tester,
    ) async {
      _tamano(tester, const Size(360, 780));

      await tester.pumpWidget(_tabla());
      await tester.pumpAndSettle();

      expect(_hayScrollHorizontal(tester), isFalse);
      expect(find.text('7.845,50 USD'), findsOneWidget);
      expect(find.text('Distribuidora Andina'), findsOneWidget);
      // Las etiquetas de columna siguen acompañando al valor: sin cabecera, un
      // número suelto no dice nada.
      expect(find.text('MONTO PENDIENTE'), findsOneWidget);
    });

    testWidgets('a 390 px la fila es una tarjeta con todos los pares', (
      tester,
    ) async {
      _tamano(tester, const Size(390, 844));

      await tester.pumpWidget(_tabla());
      await tester.pumpAndSettle();

      expect(_hayScrollHorizontal(tester), isFalse);
      for (final etiqueta in [
        'PROVEEDOR',
        'MONTO PENDIENTE',
        'ESTADO',
      ]) {
        expect(find.text(etiqueta), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('a 800 px vuelve a ser tabla, sin tarjetas', (tester) async {
      _tamano(tester, const Size(800, 900));

      await tester.pumpWidget(_tabla());
      await tester.pumpAndSettle();

      // En ancho, la cabecera va una sola vez en la banda gris de la tabla.
      expect(find.text('COMPRA'), findsOneWidget);
      expect(find.text('7.845,50 USD'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('la fila clicable se puede tocar en modo tarjeta', (
      tester,
    ) async {
      _tamano(tester, const Size(360, 780));

      var tocada = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TablaReporte(
                columnas: const [
                  ColumnaReporte('Compra', 200),
                  ColumnaReporte('Monto', 140, derecha: true),
                ],
                filas: [
                  FilaReporte([
                    celdaTexto('A-1042'),
                    celdaCifra('100,00 USD'),
                  ], onTap: () => tocada = true),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('A-1042'));
      await tester.pump();
      expect(tocada, isTrue);
    });
  });
}