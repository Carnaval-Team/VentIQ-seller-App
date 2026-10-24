import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/models/categoria_con_conteo.dart';
import 'package:inventtia_flow/screens/categorias_screen.dart';
import 'package:inventtia_flow/services/home_catalog_service.dart';
import 'package:inventtia_flow/utils/exploracion_navegacion.dart';

/// Tests del panel lateral de categorías.
///
/// POR QUE NO SE PINTA LA PANTALLA COMPLETA
///   `CategoriasScreen` lee `flow.cliente_categorias_resumen()` en `initState`.
///   Para no tocar Supabase se pintan sus dos piezas puras —[CategoriasCabecera]
///   y [CategoriasCuerpo]— montadas como lo está en la app (cabecera fija arriba,
///   cuerpo con el resto del alto): es exactamente lo que la pantalla les pasa
///   cuando ya tiene los datos.
///
/// Los dos casos que sí pintan la pantalla entera son el estado de error (sin
/// Supabase inicializado la lectura falla sola) y el del cajón cerrándose.
void main() {
  CategoriaConConteo belleza({List<SubcategoriaConConteo>? hijas}) =>
      CategoriaConConteo(
        categoria: const HomeCatalogCategory(
          id: 1,
          codigo: 'belleza',
          nombre: 'Belleza',
        ),
        servicios: 5,
        establecimientos: 3,
        subcategorias:
            hijas ??
            const [
              SubcategoriaConConteo(
                categoria: HomeCatalogCategory(
                  id: 11,
                  codigo: 'unas',
                  nombre: 'Uñas',
                ),
                servicios: 2,
                establecimientos: 2,
              ),
              SubcategoriaConConteo(
                categoria: HomeCatalogCategory(
                  id: 12,
                  codigo: 'peluqueria',
                  nombre: 'Peluquería',
                ),
                servicios: 3,
                establecimientos: 1,
              ),
            ],
      );

  ResumenCategorias resumenCompleto() => ResumenCategorias(
    categorias: [
      belleza(),
      CategoriaConConteo(
        categoria: const HomeCatalogCategory(
          id: 2,
          codigo: 'gastronomia',
          nombre: 'Gastronomía',
        ),
        servicios: 4,
        establecimientos: 4,
      ),
      CategoriaConConteo(
        categoria: const HomeCatalogCategory(
          id: 3,
          codigo: 'alojamiento',
          nombre: 'Alojamiento',
        ),
        servicios: 2,
        establecimientos: 1,
      ),
      CategoriaConConteo(
        categoria: const HomeCatalogCategory(
          id: 6,
          codigo: 'juridicos',
          nombre: 'Servicios jurídicos y contables',
        ),
      ),
    ],
    totalServicios: 11,
    totalEstablecimientos: 8,
  );

  /// Monta cabecera + cuerpo como lo hace el panel (el cuerpo con el resto del
  /// alto, que es lo que necesita su lista para poder desplazarse).
  Future<void> pintar(
    WidgetTester tester,
    ResumenCategorias resumen, {
    void Function(CategoriaConConteo categoria)? onVerCategoria,
    void Function(CategoriaConConteo categoria, SubcategoriaConConteo hija)?
    onVerSubcategoria,
    VoidCallback? onVerTodos,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              CategoriasCabecera(resumen: resumen),
              Expanded(
                child: CategoriasCuerpo(
                  resumen: resumen,
                  onVerCategoria: onVerCategoria,
                  onVerSubcategoria: onVerSubcategoria,
                  onVerTodosLosEstablecimientos: onVerTodos,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('pinta los totales globales y los locales de cada rubro', (
    tester,
  ) async {
    await pintar(tester, resumenCompleto());

    // Cabecera: los totales del resumen, no la suma de las tarjetas.
    expect(
      find.text('6 categorías · 8 establecimientos · 11 servicios'),
      findsNothing,
    );
    expect(
      find.text('4 categorías · 8 establecimientos · 11 servicios'),
      findsOneWidget,
    );
    expect(find.text('Categorías'), findsOneWidget);
    expect(find.text('Todos los rubros'), findsOneWidget);

    // El chip de cada tarjeta: el dato que se pidió (total de locales).
    expect(find.text('3 LOCALES'), findsOneWidget);
    expect(find.text('4 LOCALES'), findsOneWidget);
    expect(find.text('1 LOCAL'), findsOneWidget);
    expect(find.text('SIN LOCALES'), findsOneWidget);

    // Y el subtítulo con los servicios.
    expect(find.text('5 servicios'), findsOneWidget);
    expect(find.text('Servicios jurídicos y contables'), findsOneWidget);
  });

  testWidgets('la tarjeta abre la carpeta y «Ver todos» navega: dos acciones', (
    tester,
  ) async {
    CategoriaConConteo? pedida;
    await pintar(
      tester,
      ResumenCategorias(
        categorias: [belleza()],
        totalServicios: 5,
        totalEstablecimientos: 3,
      ),
      onVerCategoria: (categoria) => pedida = categoria,
    );

    // Arranca en la rejilla: no hay subcategorías a la vista.
    expect(find.text('Uñas'), findsNothing);

    // «Ver todos» navega al listado del rubro… y NO abre la carpeta.
    await tester.tap(find.text('Ver todos'));
    await tester.pumpAndSettle();
    expect(pedida?.categoria.nombre, 'Belleza');
    expect(find.text('Uñas'), findsNothing);

    // …y tocar la tarjeta abre la carpeta sin navegar.
    pedida = null;
    await tester.tap(find.text('Belleza'));
    await tester.pumpAndSettle();
    expect(pedida, isNull, reason: 'abrir la carpeta no navega a ningún sitio');
    expect(find.text('Uñas'), findsOneWidget);
  });

  testWidgets('la carpeta despliega las subcategorías y navega con su rubro', (
    tester,
  ) async {
    CategoriaConConteo? padre;
    SubcategoriaConConteo? hija;

    await pintar(
      tester,
      ResumenCategorias(
        categorias: [belleza()],
        totalServicios: 5,
        totalEstablecimientos: 3,
      ),
      onVerSubcategoria: (categoria, subcategoria) {
        padre = categoria;
        hija = subcategoria;
      },
    );

    await tester.tap(find.text('Belleza'));
    await tester.pumpAndSettle();

    // La carpeta abierta: banner del rubro + sus subcategorías en tarjetas.
    expect(find.text('Subcategorías de Belleza'), findsOneWidget);
    expect(find.text('Uñas'), findsOneWidget);
    expect(find.text('Peluquería'), findsOneWidget);
    expect(find.text('2 LOCALES'), findsOneWidget);
    expect(find.text('1 LOCAL'), findsOneWidget);
    expect(find.text('Ver todos los establecimientos'), findsOneWidget);

    await tester.tap(find.text('Uñas'));
    await tester.pumpAndSettle();
    expect(padre?.categoria.nombre, 'Belleza');
    expect(hija?.categoria.nombre, 'Uñas');

    // Volver cierra la carpeta y deja la rejilla.
    await tester.tap(find.byTooltip('Volver a los rubros'));
    await tester.pumpAndSettle();
    expect(find.text('Uñas'), findsNothing);
    expect(find.text('Belleza'), findsOneWidget);
  });

  testWidgets('un rubro sin subcategorías lo dice y su botón lleva al listado', (
    tester,
  ) async {
    CategoriaConConteo? pedida;
    await pintar(
      tester,
      ResumenCategorias(
        categorias: [
          CategoriaConConteo(
            categoria: const HomeCatalogCategory(
              id: 4,
              codigo: 'transporte',
              nombre: 'Transporte',
            ),
            servicios: 2,
            establecimientos: 2,
          ),
        ],
        totalServicios: 2,
        totalEstablecimientos: 2,
      ),
      onVerCategoria: (categoria) => pedida = categoria,
    );

    await tester.tap(find.text('Transporte'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Este rubro no tiene subcategorías'),
      findsOneWidget,
    );

    await tester.tap(find.text('Ver todos los establecimientos'));
    await tester.pump();
    expect(pedida?.categoria.nombre, 'Transporte');
  });

  testWidgets('sin categorías publicadas pinta el estado vacío', (tester) async {
    await pintar(tester, ResumenCategorias.vacio);

    expect(
      find.text('El catálogo todavía no tiene categorías publicadas'),
      findsOneWidget,
    );
    expect(find.textContaining('categorías ·'), findsNothing);
    expect(find.text('SIN LOCALES'), findsNothing);
  });

  testWidgets('la tarjeta «Otras» enseña sus conteos y lleva al listado', (
    tester,
  ) async {
    var verTodos = false;
    await pintar(
      tester,
      const ResumenCategorias(
        totalServicios: 5,
        totalEstablecimientos: 3,
        otrosServicios: 2,
        otrosEstablecimientos: 1,
      ),
      onVerTodos: () => verTodos = true,
    );

    expect(find.text('Otras'), findsOneWidget);
    expect(find.text('1 LOCAL'), findsOneWidget);
    expect(find.text('2 servicios'), findsOneWidget);

    await tester.tap(find.text('Ver todos'));
    await tester.pump();
    expect(verTodos, isTrue);
  });

  testWidgets('sin Supabase la pantalla real cae en el error de conexión', (
    tester,
  ) async {
    // Sin `Supabase.initialize` la lectura lanza al instante: es un fallo real
    // (no una migración ausente) y debe verse el mensaje de conexión.
    await tester.pumpWidget(const MaterialApp(home: CategoriasScreen()));
    await tester.pumpAndSettle();

    expect(find.text('No pudimos leer las categorías'), findsOneWidget);
    expect(
      find.text('Revisa tu conexión y vuelve a intentarlo.'),
      findsOneWidget,
    );
    expect(find.text('Reintentar'), findsOneWidget);
    // La cabecera y su ancla siguen montadas aunque no haya datos.
    expect(find.text('Todos los rubros'), findsOneWidget);
  });

  testWidgets('el panel entra como cajón y se cierra tocando el velo', (
    tester,
  ) async {
    // `tester.view.physicalSize` (y no `setSurfaceSize`) porque es lo que
    // alimenta de verdad al `MediaQuery` del que sale el ancho del panel.
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () =>
                    ExploracionNavegacion.abrirCategorias(context),
                child: const Text('Abrir categorías'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir categorías'));
    await tester.pumpAndSettle();

    // El panel está: cabecera del cajón presente y velo montado por debajo.
    expect(find.text('Todos los rubros'), findsOneWidget);
    expect(find.byKey(CategoriasScreen.claveVelo), findsOneWidget);

    // El velo que cierra el panel. Se toca a la derecha del panel (88 % de 390 =
    // 343 px): en el centro del velo está el propio panel.
    await tester.tapAt(const Offset(380, 400));
    await tester.pumpAndSettle();

    expect(find.text('Todos los rubros'), findsNothing);

    // La X de la cabecera cierra igual (segunda vía, la que se ve).
    await tester.tap(find.text('Abrir categorías'));
    await tester.pumpAndSettle();
    expect(find.text('Todos los rubros'), findsOneWidget);

    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.text('Todos los rubros'), findsNothing);
  });

  testWidgets('a 320 pt de ancho y con nombres largos no desborda', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pintar(tester, resumenCompleto());
    expect(find.text('Servicios jurídicos y contables'), findsOneWidget);

    // Y con la carpeta abierta, que es donde hay más piezas.
    await tester.tap(find.text('Belleza'));
    await tester.pumpAndSettle();

    expect(find.text('Peluquería'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
