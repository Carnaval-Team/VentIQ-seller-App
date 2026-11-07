import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/theme/ventiq_home_theme.dart';
import 'package:ventiq_app/widgets/home/home_buscador.dart';
import 'package:ventiq_app/widgets/home/home_hero_header.dart';
import 'package:ventiq_app/widgets/home/home_quick_chips.dart';
import 'package:ventiq_app/widgets/home/tienda_card.dart';
import 'package:ventiq_app/widgets/home/ventiq_skeleton.dart';

Widget _app(Widget child, {double ancho = 400, double alto = 700}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: ancho, height: alto, child: child)),
    ),
  );
}

void main() {
  group('VentiqSkeleton', () {
    testWidgets('pinta un bloque con el alto pedido', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_app(const VentiqSkeleton(height: 20)));

      final SizedBox caja = tester.widget<SizedBox>(
        find.descendant(
          of: find.byType(VentiqSkeleton),
          matching: find.byType(SizedBox),
        ),
      );
      expect(caja.height, 20);
    });

    testWidgets('con movimiento reducido no late', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: const Scaffold(body: VentiqSkeleton()),
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(VentiqSkeleton),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
      );
    });

    testWidgets('la rejilla de skeletons no desborda', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const SingleChildScrollView(
            child: VentiqSkeletonRejilla(cantidad: 4, columnas: 2),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('HomeHeroHeader', () {
    testWidgets('el buscador se pinta SIEMPRE, sin condición', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(
          HomeHeroHeader(
            saludo: 'Hola, César 👋',
            subtitulo: '¿Qué vas a vender?',
            buscador: HomeBuscador(
              controller: TextEditingController(),
              onChanged: (_) {},
              onLimpiar: () {},
            ),
          ),
        ),
      );

      expect(find.byType(HomeBuscador), findsOneWidget);
      expect(find.text('Hola, César 👋'), findsOneWidget);
      expect(
        find.text('EXPLORA'),
        findsNothing,
        reason: 'el rótulo EXPLORA se quitó de la cabecera',
      );
    });

    testWidgets(
      'el estado de conexión va debajo de las acciones, a la derecha',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        const Key claveEstado = Key('estado-conexion');
        await tester.pumpWidget(
          _app(
            HomeHeroHeader(
              saludo: 'Hola, César',
              acciones: <Widget>[
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.notifications),
                ),
              ],
              estadoConexion: const SizedBox(
                key: claveEstado,
                width: 80,
                height: 24,
              ),
            ),
          ),
        );

        final Offset saludo = tester.getCenter(find.text('Hola, César'));
        final Offset acciones = tester.getCenter(
          find.byIcon(Icons.notifications),
        );
        final Offset estado = tester.getCenter(find.byKey(claveEstado));

        // El nombre va a la izquierda y el bloque de estado a la derecha, por
        // debajo de las acciones: es el orden que se pidió para el app bar.
        expect(saludo.dx, lessThan(200));
        expect(acciones.dx, greaterThan(saludo.dx));
        expect(estado.dx, greaterThan(saludo.dx));
        expect(
          estado.dy,
          greaterThan(acciones.dy),
          reason: 'la conexión va en el piso de abajo, no en la misma fila',
        );
      },
    );

    testWidgets('sin buscador no pinta la franja de solape', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_app(const HomeHeroHeader(saludo: 'Hola')));

      expect(find.byType(HomeBuscador), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('pinta el hueco de acciones', (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(
          HomeHeroHeader(
            saludo: 'Hola',
            acciones: <Widget>[
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.qr_code_scanner),
              ),
            ],
          ),
        ),
      );

      expect(find.byIcon(Icons.qr_code_scanner), findsOneWidget);
    });

    testWidgets('un saludo muy largo no rompe la cabecera', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(
          HomeHeroHeader(
            saludo: 'Hola, César Augusto de la Cruz Rodríguez 👋',
            buscador: HomeBuscador(
              controller: TextEditingController(),
              onChanged: (_) {},
              onLimpiar: () {},
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('HomeBuscador', () {
    testWidgets('sin texto no muestra limpiar', (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(
          HomeBuscador(
            controller: TextEditingController(),
            onChanged: (_) {},
            onLimpiar: () {},
          ),
        ),
      );

      expect(find.byIcon(Icons.close_rounded), findsNothing);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    });

    testWidgets('con texto aparece limpiar y llama al callback', (
      WidgetTester tester,
    ) async {
      int limpiezas = 0;
      final TextEditingController c = TextEditingController();

      await tester.pumpWidget(
        _app(
          HomeBuscador(
            controller: c,
            onChanged: (_) {},
            onLimpiar: () => limpiezas++,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'arroz');
      await tester.pump();

      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      expect(limpiezas, 1);
    });

    testWidgets('propaga lo que se teclea', (WidgetTester tester) async {
      final List<String> tecleado = <String>[];

      await tester.pumpWidget(
        _app(
          HomeBuscador(
            controller: TextEditingController(),
            onChanged: tecleado.add,
            onLimpiar: () {},
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'col');
      await tester.pump();

      expect(tecleado, contains('col'));
    });

    testWidgets('los filtros solo salen si hay callback', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(
          HomeBuscador(
            controller: TextEditingController(),
            onChanged: (_) {},
            onLimpiar: () {},
          ),
        ),
      );
      expect(find.byIcon(Icons.tune_rounded), findsNothing);

      await tester.pumpWidget(
        _app(
          HomeBuscador(
            controller: TextEditingController(),
            onChanged: (_) {},
            onLimpiar: () {},
            onAbrirFiltros: () {},
            filtrosActivos: 2,
          ),
        ),
      );
      expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
      expect(
        find.text('2'),
        findsOneWidget,
        reason: 'el badge dice cuántos hay',
      );
    });
  });

  group('HomeQuickChip', () {
    testWidgets('apagado y encendido se distinguen en el color', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Column(
            children: <Widget>[
              HomeQuickChip(label: 'Apagado', onTap: () {}),
              HomeQuickChip(label: 'Encendido', onTap: () {}, selected: true),
            ],
          ),
        ),
      );

      final Material apagado = tester.widget<Material>(
        find
            .ancestor(of: find.text('Apagado'), matching: find.byType(Material))
            .first,
      );
      final Material encendido = tester.widget<Material>(
        find
            .ancestor(
              of: find.text('Encendido'),
              matching: find.byType(Material),
            )
            .first,
      );

      expect(apagado.color, isNot(equals(encendido.color)));
    });

    testWidgets('el chip "vivo" lleva su punto verde', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(HomeQuickChip(label: 'Ahorro', onTap: () {}, live: true)),
      );

      final Iterable<Container> puntos = tester
          .widgetList<Container>(find.byType(Container))
          .where(
            (Container c) =>
                c.decoration is BoxDecoration &&
                (c.decoration! as BoxDecoration).shape == BoxShape.circle,
          );

      expect(puntos, isNotEmpty);
      expect(
        (puntos.first.decoration! as BoxDecoration).color,
        VentiqHomeTheme.success,
      );
    });

    testWidgets('el riel no desborda con muchos chips', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(
          HomeQuickChips(
            chips: <Widget>[
              for (int i = 0; i < 12; i++)
                HomeQuickChip(label: 'Chip número $i', onTap: () {}),
            ],
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('TiendaCard', () {
    testWidgets('lleva la cuenta de categorías y productos', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(TiendaCard(categorias: 3, productos: 25, onTap: () {})),
      );

      expect(find.text('Tienda'), findsOneWidget);
      expect(find.text('3 CATEG'), findsOneWidget);
      expect(find.text('25 productos en 3 categ'), findsOneWidget);
    });

    testWidgets('singular bien puesto', (WidgetTester tester) async {
      await tester.pumpWidget(
        _app(TiendaCard(categorias: 1, productos: 1, onTap: () {})),
      );

      expect(find.text('1 CATEG'), findsOneWidget);
      expect(find.text('1 producto en 1 categ'), findsOneWidget);
    });

    testWidgets('sin productos no promete un número', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(TiendaCard(categorias: 2, productos: 0, onTap: () {})),
      );

      expect(find.text('2 categ'), findsOneWidget);
    });

    testWidgets('tocar dispara onTap', (WidgetTester tester) async {
      int toques = 0;
      await tester.pumpWidget(
        _app(TiendaCard(categorias: 2, productos: 5, onTap: () => toques++)),
      );

      await tester.tap(find.text('Tienda'));
      await tester.pump();

      expect(toques, 1);
    });
  });
}
