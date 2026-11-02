import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/controllers/home_controller.dart';
import 'package:ventiq_app/models/home_catalogo.dart';
import 'package:ventiq_app/theme/ventiq_home_theme.dart';
import 'package:ventiq_app/widgets/home/home_buscador.dart';
import 'package:ventiq_app/widgets/home/home_catalogo_view.dart';
import 'package:ventiq_app/widgets/home/home_estado_vacio.dart';
import 'package:ventiq_app/widgets/home/tarjeta_exploracion.dart';
import 'package:ventiq_app/widgets/home/tienda_card.dart';
import 'package:ventiq_app/widgets/home/ventiq_skeleton.dart';

/// Se prueba `HomeCatalogoView` y no `HomeShellScreen` a propósito.
///
/// El armazón de la pantalla monta `AppBottomNavigation`,
/// `ConnectionStatusWidget` y `SalesMonitorFAB`, que construyen servicios que
/// leen `Supabase.instance` **al crearse**. Eso hace que montar la pantalla
/// entera en un test arrastre media app; es el motivo por el que el Home viejo
/// no tenía ni un test. El contenido sí es puro, y es donde viven las reglas
/// que importan: qué es destacado, qué va en "Tienda" y cómo se ve todo eso.
const HomeCategoria _combustibles = HomeCategoria(
  id: 1,
  nombre: 'Combustibles',
  especial: true,
  ordenHome: 1,
  totalProductos: 4,
);

const HomeCategoria _servicios = HomeCategoria(
  id: 2,
  nombre: 'Servicios',
  especial: true,
  ordenHome: 2,
  totalProductos: 1,
);

const HomeCategoria _comida = HomeCategoria(id: 3, nombre: 'Comida', totalProductos: 20);
const HomeCategoria _recreacion =
    HomeCategoria(id: 4, nombre: 'Recreacion', totalProductos: 5);

Future<void> _montar(
  WidgetTester tester, {
  required HomeEstado estado,
  required HomeCatalogo catalogo,
  Widget? buscador,
  Widget? contenidoAlternativo,
  void Function(HomeCategoria)? onTapCategoria,
  void Function(HomeCategoria)? onAbrirListado,
  VoidCallback? onTapTienda,
  Size tamano = const Size(400, 800),
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: HomeCatalogoView(
        saludo: 'Hola 👋',
        subtitulo: '¿Qué vas a vender?',
        estado: estado,
        catalogo: catalogo,
        buscador: buscador ??
            HomeBuscador(
              controller: TextEditingController(),
              onChanged: (_) {},
              onLimpiar: () {},
            ),
        contenidoAlternativo: contenidoAlternativo,
        onTapCategoria: onTapCategoria ?? (_) {},
        onAbrirListado: onAbrirListado ?? (_) {},
        onTapTienda: onTapTienda ?? () {},
        onRefrescar: () {},
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  group('el buscador siempre visible', () {
    testWidgets('está en pantalla sin hacer scroll', (WidgetTester tester) async {
      await _montar(
        tester,
        estado: HomeEstado.listo,
        catalogo: HomeCatalogo.agrupar(<HomeCategoria>[_combustibles, _comida]),
      );

      expect(find.byType(HomeBuscador), findsOneWidget);

      // Y está arriba de verdad: su centro cae en el primer tercio.
      final double y = tester.getCenter(find.byType(HomeBuscador)).dy;
      expect(y, lessThan(tester.view.physicalSize.height / 3));
    });

    testWidgets('sigue visible durante la carga y en el error',
        (WidgetTester tester) async {
      await _montar(
        tester,
        estado: HomeEstado.cargando,
        catalogo: const HomeCatalogo(),
      );
      expect(find.byType(HomeBuscador), findsOneWidget);

      await _montar(
        tester,
        estado: HomeEstado.error,
        catalogo: const HomeCatalogo(),
      );
      expect(find.byType(HomeBuscador), findsOneWidget);
    });

    testWidgets('no aparece cuando hay contenido alternativo (búsqueda)',
        (WidgetTester tester) async {
      // El buscador lo pone el armazón en ese caso; aquí se comprueba que el
      // catálogo no se pinta debajo de los resultados.
      await _montar(
        tester,
        estado: HomeEstado.listo,
        catalogo: HomeCatalogo.agrupar(<HomeCategoria>[_combustibles]),
        contenidoAlternativo: const Text('resultados'),
      );

      expect(find.text('resultados'), findsOneWidget);
      expect(find.byType(TarjetaExploracion), findsNothing);
      expect(find.byType(TiendaCard), findsNothing);
    });
  });

  group('reparto destacadas / Tienda', () {
    testWidgets('pinta una tarjeta por especial y la tarjeta Tienda',
        (WidgetTester tester) async {
      await _montar(
        tester,
        estado: HomeEstado.listo,
        catalogo: HomeCatalogo.agrupar(
          <HomeCategoria>[_combustibles, _servicios, _comida, _recreacion],
        ),
      );

      expect(find.byType(TarjetaExploracion), findsNWidgets(2));
      expect(find.text('Combustibles'), findsOneWidget);
      expect(find.text('Servicios'), findsOneWidget);
      expect(find.byType(TiendaCard), findsOneWidget);
      expect(find.text('DESTACADAS'), findsOneWidget);
    });

    testWidgets('sin especiales no agrupa en Tienda: categorías sueltas',
        (WidgetTester tester) async {
      await _montar(
        tester,
        estado: HomeEstado.listo,
        catalogo: HomeCatalogo.agrupar(<HomeCategoria>[_comida, _recreacion]),
      );

      // Sin especiales no hay dos grupos que separar: las categorías salen
      // sueltas (sin el toque extra de "Tienda") y con su nombre visible.
      expect(find.byType(TarjetaExploracion), findsNWidgets(2));
      expect(find.text('Comida'), findsOneWidget);
      expect(find.text('Recreacion'), findsOneWidget);
      expect(find.byType(TiendaCard), findsNothing,
          reason: 'agrupar en "Tienda" cuando todo es Tienda es un toque de más');
      expect(find.text('CATEGORÍAS'), findsOneWidget);
      expect(find.text('Ver tienda ›'), findsNothing);
    });

    testWidgets('sin especiales, tocar una categoría suelta la devuelve',
        (WidgetTester tester) async {
      HomeCategoria? tocada;
      await _montar(
        tester,
        estado: HomeEstado.listo,
        catalogo: HomeCatalogo.agrupar(<HomeCategoria>[_comida, _recreacion]),
        onTapCategoria: (HomeCategoria c) => tocada = c,
      );

      await tester.tap(find.text('Recreacion'));
      await tester.pump();

      expect(tocada?.nombre, 'Recreacion');
    });

    testWidgets('la foto de la categoría llega a la tarjeta de la rejilla',
        (WidgetTester tester) async {
      final HomeCategoria conFoto = HomeCategoria(
        id: 77,
        nombre: 'Con Foto',
        especial: true,
        totalProductos: 3,
        imagen: 'https://example.com/categoria.jpg',
      );

      await _montar(
        tester,
        estado: HomeEstado.listo,
        catalogo: HomeCatalogo.agrupar(<HomeCategoria>[conFoto]),
      );

      final TarjetaExploracion tarjeta =
          tester.widget<TarjetaExploracion>(find.byType(TarjetaExploracion));
      expect(tarjeta.imagenUrl, 'https://example.com/categoria.jpg',
          reason: 'si la categoría tiene foto, la tarjeta la usa de fondo');
    });

    testWidgets('si todo es especial, no hay tarjeta Tienda ni acción',
        (WidgetTester tester) async {
      await _montar(
        tester,
        estado: HomeEstado.listo,
        catalogo:
            HomeCatalogo.agrupar(<HomeCategoria>[_combustibles, _servicios]),
      );

      expect(find.byType(TarjetaExploracion), findsNWidgets(2));
      expect(find.byType(TiendaCard), findsNothing);
      expect(find.text('Ver tienda ›'), findsNothing,
          reason: 'un enlace a una tienda vacía es un toque muerto');
    });

    testWidgets('los homónimos salen como UNA tarjeta',
        (WidgetTester tester) async {
      // El caso real: una tienda con 208 "Alimentos" por un import duplicado.
      // Sin el colapso, aquí habría 8 tarjetas con el mismo nombre.
      await _montar(
        tester,
        estado: HomeEstado.listo,
        catalogo: HomeCatalogo.agrupar(<HomeCategoria>[
          for (int id = 189; id < 197; id++)
            HomeCategoria(
              id: id,
              nombre: 'Alimentos',
              especial: true,
              totalProductos: 5,
            ),
        ]),
      );

      expect(find.text('Alimentos'), findsOneWidget);
      expect(find.byType(TarjetaExploracion), findsOneWidget);
      expect(find.text('40 PRODUCTOS'), findsOneWidget,
          reason: 'los contadores del grupo se suman');
    });
  });

  group('contenido de la tarjeta', () {
    testWidgets('el chip dice cuántos productos hay', (WidgetTester tester) async {
      await _montar(
        tester,
        estado: HomeEstado.listo,
        catalogo: HomeCatalogo.agrupar(<HomeCategoria>[_combustibles]),
      );
      expect(find.text('4 PRODUCTOS'), findsOneWidget);
    });

    testWidgets('singular bien puesto', (WidgetTester tester) async {
      await _montar(
        tester,
        estado: HomeEstado.listo,
        catalogo: HomeCatalogo.agrupar(<HomeCategoria>[_servicios]),
      );
      expect(find.text('1 PRODUCTO'), findsOneWidget);
    });

    testWidgets('una categoría con subcategorías lo dice en el subtítulo',
        (WidgetTester tester) async {
      await _montar(
        tester,
        estado: HomeEstado.listo,
        catalogo: HomeCatalogo.agrupar(<HomeCategoria>[
          const HomeCategoria(
            id: 1,
            nombre: 'Bebidas',
            especial: true,
            totalProductos: 12,
            totalSubcategorias: 3,
          ),
        ]),
      );

      expect(find.text('3 subcategorías'), findsOneWidget);
    });

    testWidgets('el color de la tarjeta es estable para el mismo id',
        (WidgetTester tester) async {
      await _montar(
        tester,
        estado: HomeEstado.listo,
        catalogo: HomeCatalogo.agrupar(<HomeCategoria>[
          const HomeCategoria(id: 42, nombre: 'Única', especial: true),
        ]),
      );

      final TarjetaExploracion t =
          tester.widget<TarjetaExploracion>(find.byType(TarjetaExploracion));
      expect(t.colores, VentiqHomeTheme.cardGradients[42 % 8]);
    });
  });

  group('gestos', () {
    testWidgets('tocar una tarjeta devuelve esa categoría',
        (WidgetTester tester) async {
      HomeCategoria? tocada;
      await _montar(
        tester,
        estado: HomeEstado.listo,
        catalogo: HomeCatalogo.agrupar(<HomeCategoria>[_combustibles, _comida]),
        onTapCategoria: (HomeCategoria c) => tocada = c,
      );

      await tester.tap(find.text('Combustibles'));
      await tester.pump();

      expect(tocada?.nombre, 'Combustibles');
    });

    testWidgets('"Ver todos" de la tarjeta lleva a la misma categoría',
        (WidgetTester tester) async {
      HomeCategoria? tocada;
      await _montar(
        tester,
        estado: HomeEstado.listo,
        catalogo: HomeCatalogo.agrupar(<HomeCategoria>[_combustibles]),
        onAbrirListado: (HomeCategoria c) => tocada = c,
      );

      await tester.tap(find.text('Ver todos'));
      await tester.pump();

      expect(tocada?.nombre, 'Combustibles');
    });

    testWidgets('tocar la tarjeta Tienda dispara su callback',
        (WidgetTester tester) async {
      int toques = 0;
      // La tarjeta "Tienda" solo existe cuando convive con especiales: con
      // todo no-especial las categorías salen sueltas.
      await _montar(
        tester,
        estado: HomeEstado.listo,
        catalogo:
            HomeCatalogo.agrupar(<HomeCategoria>[_combustibles, _comida]),
        onTapTienda: () => toques++,
      );

      await tester.tap(find.text('Tienda'));
      await tester.pump();

      expect(toques, 1);
    });
  });

  group('estados', () {
    testWidgets('cargando pinta skeletons, no un hueco', (WidgetTester tester) async {
      await _montar(
        tester,
        estado: HomeEstado.cargando,
        catalogo: const HomeCatalogo(),
      );

      expect(find.byType(VentiqSkeletonTarjeta), findsWidgets);
      expect(find.byType(HomeEstadoVacio), findsNothing);
    });

    testWidgets('el error ofrece reintentar', (WidgetTester tester) async {
      await _montar(
        tester,
        estado: HomeEstado.error,
        catalogo: const HomeCatalogo(),
      );

      expect(find.byType(HomeEstadoError), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    });

    testWidgets('sin categorías lo explica y ofrece actualizar',
        (WidgetTester tester) async {
      await _montar(
        tester,
        estado: HomeEstado.listo,
        catalogo: const HomeCatalogo(),
      );

      expect(find.text('Todavía no hay categorías'), findsOneWidget);
      expect(find.text('Actualizar'), findsOneWidget);
    });
  });

  group('responsive', () {
    testWidgets('móvil a 2 columnas', (WidgetTester tester) async {
      late int columnas;
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(400, 800)),
          child: Builder(builder: (BuildContext context) {
            columnas = HomeCatalogoView.columnasDe(context);
            return const SizedBox.shrink();
          }),
        ),
      ));
      expect(columnas, 2);
    });

    testWidgets('monitor de TPV a 5 columnas', (WidgetTester tester) async {
      late int columnas;
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(1400, 900)),
          child: Builder(builder: (BuildContext context) {
            columnas = HomeCatalogoView.columnasDe(context);
            return const SizedBox.shrink();
          }),
        ),
      ));
      expect(columnas, 5);
    });

    testWidgets('tablet a 3 columnas', (WidgetTester tester) async {
      late int columnas;
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(700, 900)),
          child: Builder(builder: (BuildContext context) {
            columnas = HomeCatalogoView.columnasDe(context);
            return const SizedBox.shrink();
          }),
        ),
      ));
      expect(columnas, 3);
    });

    testWidgets('la rejilla no desborda en 360 px', (WidgetTester tester) async {
      await _montar(
        tester,
        estado: HomeEstado.listo,
        catalogo: HomeCatalogo.agrupar(
          <HomeCategoria>[_combustibles, _servicios, _comida, _recreacion],
        ),
        tamano: const Size(360, 640),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('no desborda con el texto del sistema al 130 %',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Scaffold(
            body: HomeCatalogoView(
              saludo: 'Hola 👋',
              estado: HomeEstado.listo,
              catalogo: HomeCatalogo.agrupar(
                <HomeCategoria>[_combustibles, _servicios, _comida],
              ),
              buscador: HomeBuscador(
                controller: TextEditingController(),
                onChanged: (_) {},
                onLimpiar: () {},
              ),
              onTapCategoria: (_) {},
              onAbrirListado: (_) {},
              onTapTienda: () {},
              onRefrescar: () {},
            ),
          ),
        ),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
