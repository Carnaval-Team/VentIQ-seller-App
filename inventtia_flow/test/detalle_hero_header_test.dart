import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/models/servicio.dart';
import 'package:inventtia_flow/services/resena_service.dart';
import 'package:inventtia_flow/widgets/detalle_hero_header.dart';

/// La cabecera del detalle vive encima de una foto, así que no se puede
/// comprobar a ojo en un test de unidad: aquí se pinta de verdad y se comprueba
/// que (a) entra en el ancho de un móvil estrecho sin desbordar, (b) el nombre y
/// las fichas están, y (c) el cruce de opacidades del colapso responde al scroll
/// real (si la lectura de `FlexibleSpaceBarSettings` fallara, el bloque grande
/// se quedaría visible al colapsar y el test lo caza).
void main() {
  Local local({String? foto, String? provincia}) => Local.fromJson({
    'id': 2,
    'nombre': 'Carnaval de La Habana',
    'provincia': provincia,
    'foto': foto,
  });

  Servicio servicio({String? nombre, String? tipo}) => Servicio.fromJson({
    'id': 1,
    'nombre': nombre ?? 'Transporte nocturno',
    'tipo_actividad_codigo': tipo,
  });

  Widget envolver(Widget child, {double alto = 300, double ancho = 360}) =>
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(width: ancho, height: alto, child: child),
          ),
        ),
      );

  DetalleHeroHeader hero({
    String nombre = 'Transporte nocturno',
    String? tipo = 'transporte',
    Local? elLocal,
    String? precio,
    ResumenResenas? resenas,
    bool permiteDirecta = true,
  }) => DetalleHeroHeader(
    local: elLocal ?? local(),
    servicio: servicio(nombre: nombre, tipo: tipo),
    nombreServicio: nombre,
    resenas: resenas ?? ResumenResenas.vacio,
    precioTexto: precio,
    permiteDirecta: permiteDirecta,
  );

  testWidgets('pinta el nombre y las fichas sin desbordar a 320px', (
    tester,
  ) async {
    await tester.pumpWidget(
      envolver(
        hero(
          nombre: 'Transporte nocturno con paradas',
          precio: '1500 CUP',
          resenas: const ResumenResenas(total: 4, promedio: 4.5),
        ),
        ancho: 320,
      ),
    );
    await tester.pump();

    // El nombre se pinta dos veces: el bloque grande y el título compacto de la
    // barra (oculto mientras el hero está expandido).
    expect(find.text('Transporte nocturno con paradas'), findsNWidgets(2));
    expect(find.text('4.5 (4)'), findsOneWidget);
    expect(find.text('1500 CUP'), findsOneWidget);
    expect(find.text('Reserva directa'), findsOneWidget);
    expect(find.text('Carnaval de La Habana'), findsOneWidget);
    // Si algo desbordara, `tester.takeException()` devolvería el FlutterError.
    expect(tester.takeException(), isNull);
  });

  testWidgets('el bloque de identidad cabe en el hero de 230px', (
    tester,
  ) async {
    // 230 es el `expandedHeight` real del detalle. Con el nombre más largo y
    // todas las fichas (valoración + precio + modalidad + local · provincia) el
    // bloque es lo más alto que puede llegar a ser; si se pasa, el nombre o la
    // cebecera quedarían cortados por arriba.
    const alto = 230.0;
    await tester.pumpWidget(
      envolver(
        hero(
          nombre: 'Transporte nocturno con paradas y más paradas',
          precio: '1500 CUP',
          resenas: const ResumenResenas(total: 4, promedio: 4.5),
          elLocal: local(provincia: 'La Habana'),
        ),
        ancho: 320,
        alto: alto,
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);

    // La cebecera (lo más alto del bloque) no puede quedar por encima del hero.
    final cebecera = tester.getRect(find.text('TRANSPORTE'));
    expect(cebecera.top, greaterThanOrEqualTo(0.0));

    // Y la última ficha (lo más bajo) tiene que quedar dentro del hero.
    final ultimaFicha = tester.getRect(
      find.textContaining('Carnaval de La Habana'),
    );
    expect(ultimaFicha.bottom, lessThanOrEqualTo(alto));
  });

  testWidgets('sin precio base ni reseñas no inventa fichas', (tester) async {
    await tester.pumpWidget(
      envolver(
        hero(
          nombre: 'Corte de pelo',
          tipo: null,
          elLocal: local(),
          permiteDirecta: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('SERVICIO'), findsOneWidget);
    expect(find.text('Lista de espera'), findsOneWidget);
    expect(find.textContaining('CUP'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin local pinta el degradado de marca y no falla', (
    tester,
  ) async {
    await tester.pumpWidget(
      envolver(
        DetalleHeroHeader(
          nombreServicio: 'Servicio',
          resenas: ResumenResenas.vacio,
          precioTexto: null,
          permiteDirecta: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Servicio'), findsNWidgets(2));
    expect(find.byIcon(Icons.storefront_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('al colapsar el bloque se va y entra el título de la barra', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 300,
                pinned: true,
                flexibleSpace: hero(nombre: 'Transporte nocturno'),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 1200)),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    List<double> opacidades() => tester
        .widgetList<Opacity>(
          find.descendant(
            of: find.byType(DetalleHeroHeader),
            matching: find.byType(Opacity),
          ),
        )
        .map((o) => o.opacity)
        .toList();

    // Expandido: el bloque grande visible (1.0) y el título de la barra oculto
    // (0.0), las dos capas presentes.
    final expandido = opacidades();
    expect(expandido.length, 2);
    expect(expandido, contains(closeTo(1.0, 0.001)));
    expect(expandido, contains(closeTo(0.0, 0.001)));

    // Colapsado: el bloque grande ya no se pinta y queda solo el título de la
    // barra a plena opacidad.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();

    final colapsado = opacidades();
    expect(colapsado, [closeTo(1.0, 0.001)]);
    expect(tester.takeException(), isNull);
  });
}
