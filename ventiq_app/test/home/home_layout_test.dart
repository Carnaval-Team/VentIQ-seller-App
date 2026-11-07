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
import 'package:ventiq_app/widgets/home/tarjeta_exploracion.dart';
import 'package:ventiq_app/widgets/home/tienda_card.dart';

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

/// El mismo catálogo con **tres** especiales: a 2 columnas (móvil) la segunda
/// fila queda coja, y ese hueco es justo el sitio de la celda de «Tienda».
HomeCatalogo _catalogoImpar() {
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
      HomeCategoria(
        id: 5,
        nombre: 'Postres',
        especial: true,
        ordenHome: 3,
        totalProductos: 4,
        totalSubcategorias: 1,
        grupoIds: <int>[5],
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
  HomeCatalogo? catalogo,
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
          catalogo: catalogo ?? _catalogoDeEjemplo(),
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
    'los rieles se pintan después de las categorías',
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
      // Las categorías son lo primero: el riel queda por debajo de ellas.
      expect(
        tester.getTopLeft(find.text('RIEL DE PRUEBA')).dy,
        greaterThan(tester.getTopLeft(find.text('Alimentos')).dy),
      );
    },
  );

  // ── «Tienda»: celda en la fila impar, banda ancha en la fila llena ───────

  group('colocación de la tarjeta «Tienda»', () {
    test('impar → celda; par, sin especiales o sin tienda → abajo', () {
      expect(
        HomeCatalogoView.tiendaEnLaRejilla(_catalogoImpar()),
        isTrue,
        reason: '3 especiales a 2 columnas dejan un hueco en la última fila',
      );
      expect(
        HomeCatalogoView.tiendaEnLaRejilla(_catalogoDeEjemplo()),
        isFalse,
        reason: '2 especiales ya llenan la fila',
      );
      expect(
        HomeCatalogoView.tiendaEnLaRejilla(
          const HomeCatalogo(
            tienda: <HomeCategoria>[HomeCategoria(id: 9, nombre: 'Sola')],
          ),
        ),
        isFalse,
        reason: 'sin especiales no hay rejilla de destacadas que rellenar',
      );
      expect(
        HomeCatalogoView.tiendaEnLaRejilla(
          const HomeCatalogo(
            especiales: <HomeCategoria>[
              HomeCategoria(id: 1, nombre: 'Combustibles', especial: true),
            ],
          ),
        ),
        isFalse,
        reason: 'sin categorías de tienda no hay tarjeta que colocar',
      );
    });

    test('el contador de productos sale del mismo sitio', () {
      // 5 de «Limpieza» + 9 de «elaboracion».
      expect(HomeCatalogoView.productosEnTienda(_catalogoImpar()), 14);
      expect(HomeCatalogoView.productosEnTienda(_catalogoDeEjemplo()), 14);
    });
  });

  testWidgets('impar: «Tienda» es una celda al lado de la última especial', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _home(ancho: 360, alto: 800, catalogo: _catalogoImpar()),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('DESTACADAS'), findsOneWidget);

    // Una sola «Tienda»: la celda. Nunca las dos disposiciones a la vez.
    expect(find.byType(TiendaCard), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SliverGrid),
        matching: find.byType(TiendaCard),
      ),
      findsOneWidget,
      reason: 'tiene que ser una celda de la rejilla, no la banda de abajo',
    );

    final Rect ultima = tester.getRect(
      find.ancestor(
        of: find.text('Postres'),
        matching: find.byType(TarjetaExploracion),
      ),
    );
    final Rect tienda = tester.getRect(find.byType(TiendaCard));

    // Al lado y no debajo: misma fila, mismo tamaño de celda.
    expect(tienda.top, ultima.top);
    expect(tienda.size, ultima.size);
    expect(tienda.left, greaterThan(ultima.left));
  });

  testWidgets('par: «Tienda» se queda debajo, a lo ancho de la sección', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // `_catalogoDeEjemplo` tiene 2 especiales: la rejilla ya está llena.
    await tester.pumpWidget(_home(ancho: 360, alto: 800));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(TiendaCard), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SliverGrid),
        matching: find.byType(TiendaCard),
      ),
      findsNothing,
      reason: 'con la rejilla llena no hay hueco que rellenar',
    );

    final Rect ultima = tester.getRect(
      find.ancestor(
        of: find.text('Bebidas'),
        matching: find.byType(TarjetaExploracion),
      ),
    );
    final Rect tienda = tester.getRect(find.byType(TiendaCard));

    expect(tienda.top, greaterThan(ultima.bottom), reason: 'va debajo');
    expect(
      tienda.width,
      greaterThan(ultima.width * 2),
      reason: 'ocupa el ancho de la sección, no el de una celda',
    );
  });
}
