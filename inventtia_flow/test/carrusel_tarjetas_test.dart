import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/widgets/carrusel_tarjetas.dart';

/// Alineación del carrusel de sección ("Espacio patrocinado").
///
/// **El fallo que se corrigió:** la primera tarjeta arrancaba en ~41 px, debajo
/// de la "a" de "Espacio patrocinado", mientras todas las demás secciones del
/// Home arrancan en 16 px, debajo de la "E" del título. La causa no estaba en el
/// padding de la tarjeta (que ya era 16) sino en el `PageView`: con
/// `viewportFraction < 1` la página se **centra** y el `PageView` añade por su
/// cuenta `(1 - viewportFraction) / 2 × ancho` a la izquierda.
///
/// El test mide la geometría real, así que no depende de leer el código: si
/// alguien vuelve a un `PageView` centrado, esto se pone rojo.
const double _ancho = 360;
const double _tituloPadding = 16;

Future<void> _montar(
  WidgetTester tester, {
  required int itemCount,
  bool padEnds = false,
  ValueChanged<int>? onPageChanged,
}) async {
  tester.view.physicalSize = const Size(_ancho * 3, 300 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final controller = PageController(viewportFraction: 0.86);
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // El título de la sección, para comparar contra su borde izquierdo.
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: _tituloPadding),
              child: Text('Espacio patrocinado'),
            ),
            if (padEnds)
              SizedBox(
                height: 176,
                child: PageView.builder(
                  controller: controller,
                  itemCount: itemCount,
                  onPageChanged: onPageChanged,
                  itemBuilder: (_, i) => Padding(
                    padding: EdgeInsets.only(left: i == 0 ? 16 : 5),
                    child: _tarjeta(i),
                  ),
                ),
              )
            else
              CarruselTarjetas(
                controller: controller,
                itemCount: itemCount,
                onPageChanged: onPageChanged,
                itemBuilder: (_, i) => _tarjeta(i),
              ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Widget _tarjeta(int i) => Container(
  key: ValueKey('tarjeta-$i'),
  color: Colors.blue,
  alignment: Alignment.center,
  child: Text('$i'),
);

void main() {
  testWidgets('la primera tarjeta arranca alineada con el título de sección', (
    tester,
  ) async {
    await _montar(tester, itemCount: 3);

    final titulo = tester.getTopLeft(find.text('Espacio patrocinado')).dx;
    final primera = tester
        .getTopLeft(find.byKey(const ValueKey('tarjeta-0')))
        .dx;

    expect(titulo, _tituloPadding);
    expect(
      primera,
      titulo,
      reason:
          'La tarjeta debe empezar bajo la "E" del título (x = 16), no bajo la '
          '"a" (x ≈ 41).',
    );
  });

  testWidgets('con `padEnds` por defecto (centrado) la tarjeta se desalinea', (
    tester,
  ) async {
    // Documenta el fallo y por qué el widget existe: es el comportamiento que
    // tenía el Home antes del arreglo.
    await _montar(tester, itemCount: 3, padEnds: true);

    final primera = tester
        .getTopLeft(find.byKey(const ValueKey('tarjeta-0')))
        .dx;

    expect(primera, greaterThan(_tituloPadding + 20));
  });

  testWidgets(
    'la última tarjeta termina alineada con el margen de la sección',
    (tester) async {
      final paginas = <int>[];
      await _montar(tester, itemCount: 3, onPageChanged: paginas.add);

      await tester.drag(find.byType(CarruselTarjetas), const Offset(-600, 0));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CarruselTarjetas), const Offset(-600, 0));
      await tester.pumpAndSettle();

      expect(paginas, isNotEmpty);
      expect(paginas.last, 2);

      final ultima = tester
          .getTopRight(find.byKey(const ValueKey('tarjeta-2')))
          .dx;

      expect(
        ultima,
        moreOrLessEquals(_ancho - _tituloPadding, epsilon: 0.5),
        reason: 'El carrusel debe cerrar en el mismo margen que el título.',
      );
    },
  );

  testWidgets('entre tarjetas queda el asomo de la siguiente', (tester) async {
    await _montar(tester, itemCount: 3);

    final izquierda0 = tester
        .getTopLeft(find.byKey(const ValueKey('tarjeta-0')))
        .dx;
    final derecha0 = tester
        .getTopRight(find.byKey(const ValueKey('tarjeta-0')))
        .dx;
    final izquierda1 = tester
        .getTopLeft(find.byKey(const ValueKey('tarjeta-1')))
        .dx;
    final ancho0 = tester
        .getSize(find.byKey(const ValueKey('tarjeta-0')))
        .width;

    // El hueco visible entre dos tarjetas es la suma de los dos paddings
    // (el derecho de una y el izquierdo de la siguiente).
    expect(izquierda1 - derecha0, moreOrLessEquals(2 * 5, epsilon: 0.5));
    // La segunda sigue asomando por la derecha: el carrusel invita a deslizar.
    expect(izquierda1 + ancho0, greaterThan(_ancho - _tituloPadding));
    // Y la primera no se sale del margen de la sección.
    expect(izquierda0, _tituloPadding);
  });
}
