import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/widgets/exploracion_rapida_grid.dart';

/// Monta la rejilla sin anclas del tutorial: el registro de anclas es un
/// singleton global y aquí solo interesa el pintado y los toques.
Widget _montar({
  required int categoriasActivas,
  VoidCallback? onCategorias,
  VoidCallback? onServicios,
  VoidCallback? onEstablecimientos,
  VoidCallback? onMasPopulares,
  double ancho = 390,
  double escalaTexto = 1.0,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(ancho, 844),
        textScaler: TextScaler.linear(escalaTexto),
      ),
      child: Scaffold(
        body: SingleChildScrollView(
          child: ExploracionRapidaGrid(
            categoriasActivas: categoriasActivas,
            onCategorias: onCategorias ?? () {},
            onServicios: onServicios ?? () {},
            onEstablecimientos: onEstablecimientos ?? () {},
            onMasPopulares: onMasPopulares ?? () {},
            anchorId: null,
            trailingAnchorId: null,
            categoriasAnchorId: null,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('pinta las cuatro tarjetas con sus textos', (tester) async {
    await tester.pumpWidget(_montar(categoriasActivas: 6));

    expect(find.byType(TarjetaExploracion), findsNWidgets(4));
    expect(find.text('EXPLORACIÓN RÁPIDA'), findsOneWidget);
    expect(find.text('Ver catálogo ›'), findsOneWidget);
    expect(find.text('6 ACTIVAS'), findsOneWidget);
    expect(find.text('Categorías'), findsOneWidget);
    expect(find.text('Todos los rubros'), findsOneWidget);
    expect(find.text('CATÁLOGO'), findsOneWidget);
    expect(find.text('Servicios'), findsOneWidget);
    expect(find.text('Explorar catálogo'), findsOneWidget);
    expect(find.text('LOCALES'), findsOneWidget);
    expect(find.text('Establecimientos'), findsOneWidget);
    // Sin distancias no se promete cercanía.
    expect(find.text('Todos los locales'), findsOneWidget);
    expect(find.text('Cerca de ti'), findsNothing);
    expect(find.text('TOP 10'), findsOneWidget);
    expect(find.text('Más populares'), findsOneWidget);
    // La ventana del ranking es semanal: no se dice «hoy».
    expect(find.text('Tendencias de la semana'), findsOneWidget);
    expect(find.text('Tendencias hoy'), findsNothing);
  });

  testWidgets('sin nomenclador el chip no dice «0 ACTIVAS»', (tester) async {
    await tester.pumpWidget(_montar(categoriasActivas: 0));
    expect(find.text('TODOS LOS RUBROS'), findsOneWidget);
    expect(find.text('0 ACTIVAS'), findsNothing);
  });

  testWidgets('cada tarjeta dispara su callback', (tester) async {
    var categorias = 0;
    var servicios = 0;
    var establecimientos = 0;
    var populares = 0;

    await tester.pumpWidget(
      _montar(
        categoriasActivas: 6,
        onCategorias: () => categorias++,
        onServicios: () => servicios++,
        onEstablecimientos: () => establecimientos++,
        onMasPopulares: () => populares++,
      ),
    );

    await tester.tap(find.text('Categorías'));
    await tester.tap(find.text('Servicios'));
    await tester.tap(find.text('Establecimientos'));
    await tester.tap(find.text('Más populares'));
    await tester.pump();

    expect(categorias, 1);
    expect(servicios, 1);
    expect(establecimientos, 1);
    expect(populares, 1);
  });

  testWidgets('«Ver catálogo» es el mismo destino que la tarjeta Servicios', (
    tester,
  ) async {
    var servicios = 0;
    await tester.pumpWidget(
      _montar(categoriasActivas: 6, onServicios: () => servicios++),
    );

    await tester.tap(find.text('Ver catálogo ›'));
    await tester.pump();

    expect(servicios, 1);
  });

  testWidgets('no desborda en un teléfono de 320 pt', (tester) async {
    await tester.pumpWidget(_montar(categoriasActivas: 6, ancho: 320));
    expect(tester.takeException(), isNull);
  });

  testWidgets('no desborda con el texto al 130 %', (tester) async {
    await tester.pumpWidget(
      _montar(categoriasActivas: 6, ancho: 320, escalaTexto: 1.3),
    );
    expect(tester.takeException(), isNull);
  });
}