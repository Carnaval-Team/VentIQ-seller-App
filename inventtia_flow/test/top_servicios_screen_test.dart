import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/screens/top_servicios_screen.dart';
import 'package:inventtia_flow/services/home_catalog_service.dart';
import 'package:inventtia_flow/widgets/resenas.dart';

/// Pintado del ranking con datos inyectados.
///
/// La pantalla lee el RPC en su `State` (Supabase), así que aquí se monta solo
/// el cuerpo público `TopServiciosCuerpo`, que es donde viven el orden, el tope
/// de 10 puestos, la ausencia de estrellas y el estado vacío. Nada de red.
void main() {
  const categoria = HomeCatalogCategory(
    id: 1,
    codigo: 'general',
    nombre: 'General',
  );

  HomeCatalogItem item({
    required int id,
    String? title,
    String venue = 'Local de prueba',
    double? rating,
    int totalResenas = 0,
    int? lugaresSemana,
  }) => HomeCatalogItem(
    id: id,
    title: title ?? 'Servicio $id',
    venue: venue,
    category: categoria,
    rating: rating,
    totalResenas: totalResenas,
    lugaresSemana: lugaresSemana,
  );

  /// Monta solo el cuerpo. La `Builder` conserva el tamaño real de la vista y
  /// únicamente cambia la escala del texto.
  Widget montar(
    List<HomeCatalogItem> items, {
    int limite = 10,
    double escalaTexto = 1.0,
    ValueChanged<HomeCatalogItem>? onAbrir,
    VoidCallback? onVerCatalogo,
  }) {
    return MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(escalaTexto)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: TopServiciosCuerpo(
                items: items,
                limite: limite,
                onAbrir: onAbrir ?? (_) {},
                onVerCatalogo: onVerCatalogo,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Diez puestos con textos largos: el caso que más aprieta el layout.
  List<HomeCatalogItem> rankingLargo() => [
    for (var i = 1; i <= 10; i++)
      item(
        id: i,
        title: 'Servicio con un nombre bastante largo $i',
        venue: 'Local con nombre largo de prueba $i',
        rating: 4.5,
        totalResenas: 40,
        lugaresSemana: 20 - i,
      ),
  ];

  testWidgets('nunca pinta más de 10 puestos aunque lleguen más', (
    tester,
  ) async {
    // El RPC ya recibe `p_limite`, pero el tope se vuelve a aplicar al pintar:
    // ningún dato de más puede convertirse en un puesto 11.
    final items = [
      for (var i = 1; i <= 12; i++)
        item(id: i, title: 'Servicio $i', lugaresSemana: 20 - i),
    ];

    await tester.pumpWidget(montar(items));

    expect(find.text('Servicio 1'), findsOneWidget);
    expect(find.text('Servicio 10'), findsOneWidget);
    expect(find.text('Servicio 11'), findsNothing);
    expect(find.text('Servicio 12'), findsNothing);
  });

  testWidgets('respeta el orden que manda el servidor', (tester) async {
    final items = [
      item(id: 1, title: 'Alfa', lugaresSemana: 30),
      item(id: 2, title: 'Bravo', lugaresSemana: 20),
      item(id: 3, title: 'Charlie', lugaresSemana: 10),
      item(id: 4, title: 'Delta', lugaresSemana: 5),
    ];

    await tester.pumpWidget(montar(items));

    // El orden es el del ranking, no el del catálogo ni el alfabético: si se
    // reordenara en el cliente, el podio dejaría de significar algo.
    final alfa = tester.getTopLeft(find.text('Alfa')).dy;
    final bravo = tester.getTopLeft(find.text('Bravo')).dy;
    final charlie = tester.getTopLeft(find.text('Charlie')).dy;
    final delta = tester.getTopLeft(find.text('Delta')).dy;
    expect(alfa, lessThan(bravo));
    expect(bravo, lessThan(charlie));
    expect(charlie, lessThan(delta));
  });

  testWidgets('muestra el puesto y los lugares reservados de la semana', (
    tester,
  ) async {
    await tester.pumpWidget(
      montar([item(id: 1, title: 'Corte', lugaresSemana: 3)]),
    );

    expect(find.text('1'), findsOneWidget);
    // La ventana del dato es la semana: nunca «hoy».
    expect(find.text('3 lugares reservados esta semana'), findsOneWidget);
    expect(find.textContaining('hoy'), findsNothing);
  });

  testWidgets('el estado vacío no se rellena con nada', (tester) async {
    var catalogo = 0;
    await tester.pumpWidget(
      montar(const <HomeCatalogItem>[], onVerCatalogo: () => catalogo++),
    );

    expect(find.text('Todavía no hay reservas esta semana'), findsOneWidget);
    expect(find.text('Ver el catálogo'), findsOneWidget);

    await tester.tap(find.text('Ver el catálogo'));
    await tester.pump();
    expect(catalogo, 1);
  });

  testWidgets('un ítem sin reseñas no muestra estrellas', (tester) async {
    await tester.pumpWidget(
      montar([
        item(id: 1, title: 'Sin reseñas', lugaresSemana: 9),
        item(
          id: 2,
          title: 'Con reseñas',
          rating: 4.6,
          totalResenas: 12,
          lugaresSemana: 8,
        ),
      ]),
    );

    // `Estrellas` pinta siempre cinco iconos (vacíos si no hay valoración), así
    // que la única prueba de que no se le supone una opinión es que el widget
    // no se monte: ni estrellas ni «0.0» para el servicio sin reseñas.
    expect(find.byType(Estrellas), findsOneWidget);
    expect(find.text('4.6'), findsOneWidget);
    expect(find.text('0.0'), findsNothing);
    expect(find.text('Sin valoraciones'), findsNothing);
  });

  testWidgets('tocar un puesto avisa con el ítem tocado', (tester) async {
    HomeCatalogItem? tocado;
    await tester.pumpWidget(
      montar([
        item(id: 7, title: 'Masaje', lugaresSemana: 4),
      ], onAbrir: (i) => tocado = i),
    );

    await tester.tap(find.text('Masaje'));
    await tester.pump();

    expect(tocado?.id, 7);
  });

  testWidgets('no desborda en un teléfono de 320 pt', (tester) async {
    // El ancho hay que cambiarlo en la vista: un `MediaQuery` de mentira no
    // relaya el layout.
    tester.view.physicalSize = const Size(320 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(montar(rankingLargo()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('no desborda con el texto al 130 %', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(montar(rankingLargo(), escalaTexto: 1.3));
    expect(tester.takeException(), isNull);
  });
}
