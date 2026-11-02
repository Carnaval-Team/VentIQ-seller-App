import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/theme/ventiq_home_theme.dart';
import 'package:ventiq_app/widgets/home/tarjeta_exploracion.dart';

/// Envuelve la tarjeta en un tamaño realista de rejilla: 2 columnas en 360 pt
/// con padding 16 y separación 12 ⇒ ~154 pt de ancho y ~122 de alto.
Widget _envolver(Widget child, {double textScale = 1.0}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: SizedBox(width: 154, height: 122, child: child),
        ),
      ),
    ),
  );
}

TarjetaExploracion _tarjeta({
  String chip = '12 PRODUCTOS',
  String titulo = 'Combustibles',
  String subtitulo = 'Especial',
  String? imagenUrl,
  String? accionEtiqueta,
  VoidCallback? onAccion,
  VoidCallback? onTap,
}) {
  return TarjetaExploracion(
    chip: chip,
    titulo: titulo,
    subtitulo: subtitulo,
    icono: Icons.local_gas_station_rounded,
    colores: VentiqHomeTheme.cardGradients.first,
    onTap: onTap ?? () {},
    imagenUrl: imagenUrl,
    accionEtiqueta: accionEtiqueta,
    onAccion: onAccion,
  );
}

void main() {
  group('contenido', () {
    testWidgets('pinta chip, título y subtítulo', (WidgetTester tester) async {
      await tester.pumpWidget(_envolver(_tarjeta()));

      expect(find.text('12 PRODUCTOS'), findsOneWidget);
      expect(find.text('Combustibles'), findsOneWidget);
      expect(find.text('Especial'), findsOneWidget);
    });

    testWidgets('el título largo se recorta, no desborda',
        (WidgetTester tester) async {
      const String largo = 'Categoría con un nombre absurdamente largo de verdad';
      await tester.pumpWidget(_envolver(_tarjeta(titulo: largo)));

      expect(tester.takeException(), isNull);
      final Text titulo = tester.widget<Text>(find.text(largo));
      expect(titulo.maxLines, 1);
      expect(titulo.overflow, TextOverflow.ellipsis);
    });

    testWidgets('no desborda con el texto del sistema al 130 %',
        (WidgetTester tester) async {
      await tester.pumpWidget(_envolver(_tarjeta(), textScale: 1.3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('es un solo botón para accesibilidad',
        (WidgetTester tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(_envolver(_tarjeta()));

      final SemanticsNode nodo =
          tester.getSemantics(find.byType(TarjetaExploracion));

      // Un solo nodo, marcado como botón, y que anuncia la categoría. El texto
      // de dentro (chip incluido) se funde en la misma etiqueta.
      expect(nodo.hasFlag(SemanticsFlag.isButton), isTrue);
      expect(nodo.label, contains('Combustibles'));
      expect(nodo.label, contains('Especial'));

      handle.dispose();
    });
  });

  group('gestos', () {
    testWidgets('tocar la tarjeta dispara onTap una vez',
        (WidgetTester tester) async {
      int toques = 0;
      await tester.pumpWidget(_envolver(_tarjeta(onTap: () => toques++)));

      await tester.tap(find.text('Combustibles'));
      await tester.pump();

      expect(toques, 1);
    });

    testWidgets('el pie "Ver todos" NO dispara el toque de la tarjeta',
        (WidgetTester tester) async {
      int toquesTarjeta = 0;
      int toquesPie = 0;

      await tester.pumpWidget(_envolver(_tarjeta(
        accionEtiqueta: 'Ver todos',
        onAccion: () => toquesPie++,
        onTap: () => toquesTarjeta++,
      )));

      await tester.tap(find.text('Ver todos'));
      await tester.pump();

      // Son dos destinos distintos: abrir la carpeta y ver el listado.
      expect(toquesPie, 1);
      expect(toquesTarjeta, 0);
    });

    testWidgets('sin acción, el pie se pinta apagado y no responde',
        (WidgetTester tester) async {
      int toquesTarjeta = 0;
      await tester.pumpWidget(_envolver(_tarjeta(
        accionEtiqueta: 'Sin productos',
        onAccion: null,
        onTap: () => toquesTarjeta++,
      )));

      expect(find.text('Sin productos'), findsOneWidget);

      await tester.tap(find.text('Sin productos'));
      await tester.pump();

      // El toque cae en la tarjeta, no en un pie muerto.
      expect(toquesTarjeta, 1);
    });
  });

  group('modo degradado (sin imagen)', () {
    testWidgets('no intenta cargar ninguna imagen', (WidgetTester tester) async {
      await tester.pumpWidget(_envolver(_tarjeta()));
      // Ninguna petición de red: en tests eso sería un fallo explícito.
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('una url vacía cae al degradado', (WidgetTester tester) async {
      await tester.pumpWidget(_envolver(_tarjeta(imagenUrl: '   ')));
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('VentiqHomeTheme.cardExtent', () {
    testWidgets('escala con el texto del sistema', (WidgetTester tester) async {
      late double normal;
      late double grande;

      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (BuildContext context) {
          normal = VentiqHomeTheme.cardExtent(context);
          return const SizedBox.shrink();
        }),
      ));

      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Builder(builder: (BuildContext context) {
            grande = VentiqHomeTheme.cardExtent(context);
            return const SizedBox.shrink();
          }),
        ),
      ));

      expect(normal, VentiqHomeTheme.cardExtentBase);
      expect(grande, closeTo(VentiqHomeTheme.cardExtentBase * 1.3, 0.01));
    });

    testWidgets('el escalado se acota a 1.4', (WidgetTester tester) async {
      late double acotado;

      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(3.0)),
          child: Builder(builder: (BuildContext context) {
            acotado = VentiqHomeTheme.cardExtent(context);
            return const SizedBox.shrink();
          }),
        ),
      ));

      expect(acotado, closeTo(VentiqHomeTheme.cardExtentBase * 1.4, 0.01));
    });
  });
}
