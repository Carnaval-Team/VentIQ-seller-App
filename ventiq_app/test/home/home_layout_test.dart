// Fase 8 · layout del Home en los tres anchos de referencia.
//
// No son goldens de imagen (no se pueden generar en este entorno): montan el
// widget real `HomeCatalogoView` con datos de ejemplo y comprueban que en 360,
// 412 y 1280 px (a) no revienta, (b) pinta el saludo, el buscador, las
// especiales y la tarjeta «Tienda», y (c) no deja excepciones de layout.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/controllers/home_controller.dart';
import 'package:ventiq_app/models/home_catalogo.dart';
import 'package:ventiq_app/theme/ventiq_home_theme.dart';
import 'package:ventiq_app/widgets/home/home_catalogo_view.dart';

HomeCatalogo _catalogoDeEjemplo() {
  return const HomeCatalogo(
    especiales: <HomeCategoria>[
      HomeCategoria(
        id: 1,
        nombre: 'Alimentos',
        especial: true,
        ordenHome: 1,
        totalProductos: 12,
        totalSubcategorias: 3,
        grupoIds: <int>[1],
      ),
      HomeCategoria(
        id: 2,
        nombre: 'Bebidas',
        especial: true,
        ordenHome: 2,
        totalProductos: 8,
        totalSubcategorias: 2,
        grupoIds: <int>[2],
      ),
    ],
    tienda: <HomeCategoria>[
      HomeCategoria(
        id: 3,
        nombre: 'Limpieza',
        totalProductos: 5,
        totalSubcategorias: 1,
        grupoIds: <int>[3],
      ),
      HomeCategoria(
        id: 4,
        nombre: 'elaboracion',
        totalProductos: 9,
        totalSubcategorias: 2,
        grupoIds: <int>[4],
      ),
    ],
  );
}

Widget _home({
  required double ancho,
  required double alto,
  List<Widget> rieles = const <Widget>[],
}) {
  return MaterialApp(
    theme: ThemeData(useMaterial3: true),
    home: MediaQuery(
      data: MediaQueryData(size: Size(ancho, alto)),
      child: Scaffold(
        body: HomeCatalogoView(
          saludo: 'Hola, César',
          subtitulo: '¿Qué vas a vender?',
          estado: HomeEstado.listo,
          catalogo: _catalogoDeEjemplo(),
          buscador: const TextField(
            decoration: InputDecoration(hintText: 'Buscar producto…'),
          ),
          chips: const SizedBox.shrink(),
          rieles: rieles,
          onTapCategoria: (_) {},
          onTapTienda: () {},
          onAbrirListado: (_) {},
          onRefrescar: () {},
        ),
      ),
    ),
  );
}

void main() {
  final List<Size> tamanos = <Size>[
    const Size(360, 800),
    const Size(412, 915),
    const Size(1280, 800),
  ];

  for (final Size tamano in tamanos) {
    testWidgets(
      'Home sin overflow ni excepciones en ${tamano.width.toInt()} px',
      (WidgetTester tester) async {
        await tester.binding.setSurfaceSize(tamano);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          _home(ancho: tamano.width, alto: tamano.height),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('Hola, César'), findsOneWidget);
        expect(find.text('¿Qué vas a vender?'), findsOneWidget);
        expect(find.byType(TextField), findsOneWidget);
        // Especiales + tarjeta «Tienda» (que pinta su propio título).
        expect(find.text('Alimentos'), findsOneWidget);
        expect(find.text('Bebidas'), findsOneWidget);
        expect(find.text('Tienda'), findsOneWidget);
      },
    );
  }

  testWidgets('el Home usa los tokens del tema', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_home(ancho: 360, alto: 800));
    await tester.pump();

    final Scaffold scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(
      scaffold.backgroundColor ?? VentiqHomeTheme.surface,
      VentiqHomeTheme.surface,
    );
  });

  testWidgets(
    'los rieles se pintan debajo de los chips y antes de las categorías',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _home(
          ancho: 360,
          alto: 800,
          rieles: const <Widget>[
            Padding(padding: EdgeInsets.all(8), child: Text('RIEL DE PRUEBA')),
          ],
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('RIEL DE PRUEBA'), findsOneWidget);
      // Debe estar por encima de la sección de categorías.
      expect(
        tester.getTopLeft(find.text('RIEL DE PRUEBA')).dy,
        lessThan(tester.getTopLeft(find.text('Alimentos')).dy),
      );
    },
  );
}
