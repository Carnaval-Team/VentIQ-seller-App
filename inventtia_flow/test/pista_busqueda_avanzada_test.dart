import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/widgets/pista_busqueda_avanzada.dart';

void main() {
  /// Monta la pista anclada arriba a la derecha, como la coloca el catálogo.
  Future<void> montar(
    WidgetTester tester, {
    required VoidCallback onTap,
    required VoidCallback onCerrar,
    Size tamano = const Size(360, 640),
  }) async {
    await tester.binding.setSurfaceSize(tamano);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 90, right: 20),
              child: PistaBusquedaAvanzada(onTap: onTap, onCerrar: onCerrar),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('dice que no encuentras lo que buscas y dónde buscar', (
    tester,
  ) async {
    await montar(tester, onTap: () {}, onCerrar: () {});

    expect(find.text('¿No encuentras lo que buscas?'), findsOneWidget);
    expect(
      find.text(
        'Haz una búsqueda avanzada aquí: precio, valoración, '
        'establecimiento y más.',
      ),
      findsOneWidget,
    );
    // La flecha que apunta al botón de filtros.
    expect(find.byKey(PistaBusquedaAvanzada.claveFlecha), findsOneWidget);
  });

  testWidgets('tocar el cuerpo abre la búsqueda avanzada', (tester) async {
    var abiertos = 0;
    var cerrados = 0;
    await montar(tester, onTap: () => abiertos++, onCerrar: () => cerrados++);

    await tester.tap(find.text('¿No encuentras lo que buscas?'));
    await tester.pump();

    expect(abiertos, 1);
    expect(cerrados, 0);
  });

  testWidgets('la X cierra la pista sin abrir el sheet', (tester) async {
    var abiertos = 0;
    var cerrados = 0;
    await montar(tester, onTap: () => abiertos++, onCerrar: () => cerrados++);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();

    expect(cerrados, 1);
    expect(abiertos, 0);
  });

  testWidgets('no desborda en una pantalla estrecha', (tester) async {
    // 320 px es el ancho más pequeño que se sigue usando en Android: el texto
    // largo tiene que poder partirse sin desbordar.
    await montar(
      tester,
      onTap: () {},
      onCerrar: () {},
      tamano: const Size(320, 640),
    );

    expect(tester.takeException(), isNull);
  });
}
