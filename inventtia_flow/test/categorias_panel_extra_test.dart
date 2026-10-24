import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/models/categoria_con_conteo.dart';
import 'package:inventtia_flow/screens/categorias_screen.dart';
import 'package:inventtia_flow/services/home_catalog_service.dart';
import 'package:inventtia_flow/tutorial/tutorial_anchor.dart';
import 'package:inventtia_flow/tutorial/tutorial_destino.dart';
import 'package:inventtia_flow/tutorial/tutorial_flujos.dart';
import 'package:inventtia_flow/tutorial/tutorial_navegacion.dart';
import 'package:inventtia_flow/tutorial/tutorial_registry.dart';
import 'package:inventtia_flow/utils/exploracion_navegacion.dart';
import 'package:inventtia_flow/utils/ruta_lateral.dart';
import 'package:inventtia_flow/widgets/exploracion_rapida_grid.dart';

/// Verificación **independiente** del panel lateral de categorías (F12).
///
/// Es un fichero aparte de `categorias_screen_test.dart` (el del Lead) y su
/// intención es la contraria: intentar romper el panel, no confirmarlo. Cubre
/// seis frentes que el test del Lead no toca o toca de refilón:
///
///   1. El cajón medido (88 % con tope de 372), el velo, la X y el ancla del
///      tutorial en los cuatro estados.
///   2. Las DOS acciones separadas de cada tarjeta, con los callbacks gancho.
///   3. Accesibilidad: `MediaQuery.disableAnimations` abre la carpeta en el
///      mismo frame y no pide animaciones.
///   4. Casos límite: rubro sin locales, sin subcategorías, nombres largos,
///      resumen vacío y resumen solo con «Otros».
///   5. Tamaños hostiles: 320 pt y texto al 130 %.
///   6. La ruta es NO opaca: `Navigator.popUntil` / `volverAlShell` cierran el
///      panel igual (es lo que usa el tutorial al cambiar de paso).
///
/// POR QUE NO SE PINTA LA PANTALLA CON DATOS INYECTADOS
///   `CategoriasScreen` no tiene costura para inyectar el resumen (lee Supabase
///   en `initState`), así que el cajón se prueba con la pantalla REAL (sin
///   Supabase cae en el estado de error, que monta la misma cabecera y el mismo
///   velo) y todo lo que depende de los datos se prueba sobre las dos piezas
///   puras, `CategoriasCabecera` + `CategoriasCuerpo`, montadas como lo está en
///   la app. Es la misma estrategia que el test del Lead, a propósito: si el
///   panel cambia de costura, los dos ficheros se rompen a la vez.
void main() {
  setUp(TutorialRegistry.instance.limpiar);

  // ── Datos de prueba ─────────────────────────────────────────────────────

  HomeCatalogCategory cat(int id, String nombre) =>
      HomeCatalogCategory(id: id, codigo: 'c$id', nombre: nombre);

  SubcategoriaConConteo hija(
    int id,
    String nombre, {
    int locales = 1,
    int servicios = 1,
  }) => SubcategoriaConConteo(
    categoria: cat(id, nombre),
    servicios: servicios,
    establecimientos: locales,
  );

  CategoriaConConteo rubro(
    int id,
    String nombre, {
    int locales = 3,
    int servicios = 5,
    List<SubcategoriaConConteo> hijas = const <SubcategoriaConConteo>[],
  }) => CategoriaConConteo(
    categoria: cat(id, nombre),
    servicios: servicios,
    establecimientos: locales,
    subcategorias: hijas,
  );

  ResumenCategorias resumenCompleto() => ResumenCategorias(
    categorias: [
      rubro(
        1,
        'Belleza',
        locales: 3,
        servicios: 5,
        hijas: [hija(11, 'Uñas', locales: 2, servicios: 2), hija(12, 'Peluquería')],
      ),
      rubro(2, 'Gastronomía', locales: 4, servicios: 4),
      rubro(6, 'Servicios jurídicos y contables', locales: 0, servicios: 0),
    ],
    totalServicios: 11,
    totalEstablecimientos: 8,
  );

  final anclaLista = find.byWidgetPredicate(
    (w) => w is TutorialAnchor && w.id == 'categorias_lista',
    description: 'ancla del tutorial «categorias_lista»',
  );

  // ── Montajes ────────────────────────────────────────────────────────────

  /// Monta cabecera + cuerpo con datos inyectados (sin Supabase).
  ///
  /// [media] recibe el `MediaQueryData` real para poder modificarlo con
  /// `copyWith`: crear un `MediaQueryData()` de cero pondría `size` a cero y el
  /// ancho del panel (`88 % del ancho`) sería 0 — la trampa clásica.
  Widget panelInyectado({
    required ResumenCategorias resumen,
    void Function(CategoriaConConteo)? onVerCategoria,
    void Function(CategoriaConConteo, SubcategoriaConConteo)? onVerSubcategoria,
    VoidCallback? onVerTodos,
    MediaQueryData Function(MediaQueryData base)? media,
  }) {
    return MaterialApp(
      home: Builder(
        builder: (context) {
          final base = MediaQuery.of(context);
          return MediaQuery(
            data: media == null ? base : media(base),
            child: Scaffold(
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
          );
        },
      ),
    );
  }

  /// Empuja el panel REAL (`CategoriasScreen` vía `ExploracionNavegacion`) sobre
  /// una pantalla cualquiera. Sin Supabase el panel acaba en su estado de error,
  /// que es suficiente: velo, cabecera, ancla y ancho no dependen de los datos.
  Future<void> abrirCajon(
    WidgetTester tester, {
    GlobalKey<NavigatorState>? navigatorKey,
    NavigatorObserver? observer,
    void Function(BuildContext raiz)? onRaiz,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: observer == null ? const [] : [observer],
        home: Builder(
          builder: (context) {
            onRaiz?.call(context);
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => ExploracionNavegacion.abrirCategorias(context),
                  child: const Text('Abrir categorías'),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Abrir categorías'));
    await tester.pumpAndSettle();
  }

  void tamano(WidgetTester tester, Size size) {
    // `physicalSize` (y no `setSurfaceSize`) porque es lo que alimenta de verdad
    // al `MediaQuery` del que sale el ancho del panel.
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  // ═══ 1. El panel como cajón ═════════════════════════════════════════════

  testWidgets('el panel mide 88 % del ancho (343 a 390 pt) y el velo cierra', (
    tester,
  ) async {
    tamano(tester, const Size(390, 800));
    await abrirCajon(tester);

    // 88 % de 390 = 343,2 (por debajo del tope de 372).
    final cabecera = tester.getRect(find.byType(CategoriasCabecera));
    expect(cabecera.left, 0);
    expect(cabecera.width, moreOrLessEquals(343.2, epsilon: 0.6));
    expect(find.byKey(CategoriasScreen.claveVelo), findsOneWidget);

    // Un toque DENTRO del panel no debe cerrarlo (ni en su hueco del contenido).
    await tester.tapAt(const Offset(170, 720));
    await tester.pumpAndSettle();
    expect(
      find.byType(CategoriasScreen),
      findsOneWidget,
      reason: 'el toque dentro del panel no puede cerrar el cajón',
    );

    // Un toque FUERA (x=380 > 343,2) sí lo cierra: es el velo.
    await tester.tapAt(const Offset(380, 400));
    await tester.pumpAndSettle();
    expect(find.byType(CategoriasScreen), findsNothing);

    // Y la X de la cabecera es la segunda vía.
    await tester.tap(find.text('Abrir categorías'));
    await tester.pumpAndSettle();
    expect(find.byType(CategoriasScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.byType(CategoriasScreen), findsNothing);
  });

  testWidgets('en pantalla ancha el panel se queda en el tope de 372 pt', (
    tester,
  ) async {
    tamano(tester, const Size(900, 800));
    await abrirCajon(tester);

    expect(
      tester.getSize(find.byType(CategoriasCabecera)).width,
      moreOrLessEquals(372, epsilon: 0.6),
      reason: 'el cajón no debe crecer más allá del tope de tablet',
    );
  });

  testWidgets('el ancla categorias_lista se monta en carga, vacío y datos', (
    tester,
  ) async {
    // Carga: la cabecera se pinta con `resumen: null` (sin pastilla) y debajo el
    // indicador; es exactamente lo que muestra la pantalla mientras espera.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: const [
              CategoriasCabecera(),
              Expanded(
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
          ),
        ),
      ),
    );
    // Sin `pumpAndSettle`: el indicador gira para siempre y nunca asentaría.
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(anclaLista, findsOneWidget);
    expect(TutorialRegistry.instance.estaVisible('categorias_lista'), isTrue);

    // Vacío.
    await tester.pumpWidget(panelInyectado(resumen: ResumenCategorias.vacio));
    await tester.pumpAndSettle();
    expect(
      find.text('El catálogo todavía no tiene categorías publicadas'),
      findsOneWidget,
    );
    expect(anclaLista, findsOneWidget);
    expect(TutorialRegistry.instance.estaVisible('categorias_lista'), isTrue);

    // Datos.
    await tester.pumpWidget(panelInyectado(resumen: resumenCompleto()));
    await tester.pumpAndSettle();
    expect(find.text('Belleza'), findsOneWidget);
    expect(anclaLista, findsOneWidget);
    expect(TutorialRegistry.instance.estaVisible('categorias_lista'), isTrue);
  });

  testWidgets('el ancla sigue montada en el estado de error de la pantalla', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: CategoriasScreen()));
    // Primer frame: aunque la lectura ya haya fallado, la cabecera está.
    expect(anclaLista, findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('No pudimos leer las categorías'), findsOneWidget);
    expect(anclaLista, findsOneWidget);
    expect(TutorialRegistry.instance.estaVisible('categorias_lista'), isTrue);
  });

  // ═══ 2. Dos acciones separadas ══════════════════════════════════════════

  testWidgets('la tarjeta abre la carpeta SIN navegar y «Ver todos» navega', (
    tester,
  ) async {
    CategoriaConConteo? pedida;
    await tester.pumpWidget(
      panelInyectado(
        resumen: ResumenCategorias(
          categorias: [
            rubro(
              1,
              'Belleza',
              locales: 3,
              servicios: 5,
              hijas: [hija(11, 'Uñas', locales: 2, servicios: 2)],
            ),
          ],
          totalServicios: 5,
          totalEstablecimientos: 3,
        ),
        onVerCategoria: (categoria) => pedida = categoria,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Belleza'));
    await tester.pumpAndSettle();
    expect(pedida, isNull, reason: 'abrir la carpeta no navega');
    expect(find.text('Uñas'), findsOneWidget);

    // Volver y usar el pie: navega y NO abre la carpeta.
    await tester.tap(find.byTooltip('Volver a los rubros'));
    await tester.pumpAndSettle();
    expect(find.text('Uñas'), findsNothing);

    await tester.tap(find.text('Ver todos'));
    await tester.pumpAndSettle();
    expect(pedida?.categoria.nombre, 'Belleza');
    expect(
      find.text('Uñas'),
      findsNothing,
      reason: '«Ver todos» no puede abrir además la carpeta',
    );
  });

  testWidgets('la subcategoría navega con (padre, hija)', (tester) async {
    CategoriaConConteo? padre;
    SubcategoriaConConteo? hijaPedida;
    var verTodos = 0;

    await tester.pumpWidget(
      panelInyectado(
        resumen: ResumenCategorias(
          categorias: [
            rubro(
              1,
              'Belleza',
              hijas: [hija(11, 'Uñas', locales: 2, servicios: 2)],
            ),
          ],
        ),
        onVerSubcategoria: (categoria, subcategoria) {
          padre = categoria;
          hijaPedida = subcategoria;
        },
        onVerTodos: () => verTodos++,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Belleza'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Uñas'));
    await tester.pumpAndSettle();

    expect(padre?.categoria.id, 1);
    expect(hijaPedida?.categoria.id, 11);
    expect(verTodos, 0);
  });

  testWidgets('el banner de la carpeta lleva al RUBRO, no a la subcategoría', (
    tester,
  ) async {
    CategoriaConConteo? verCategoria;
    var verSubcategorias = 0;

    await tester.pumpWidget(
      panelInyectado(
        resumen: ResumenCategorias(
          categorias: [
            rubro(
              1,
              'Belleza',
              hijas: [hija(11, 'Uñas'), hija(12, 'Peluquería')],
            ),
          ],
        ),
        onVerCategoria: (categoria) => verCategoria = categoria,
        onVerSubcategoria: (_, _) => verSubcategorias++,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Belleza'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver todos los establecimientos'));
    await tester.pumpAndSettle();

    expect(verCategoria?.categoria.id, 1);
    expect(verSubcategorias, 0);
  });

  testWidgets('«Otras» navega a todos: desde la tarjeta y desde su pie', (
    tester,
  ) async {
    var verTodos = 0;
    await tester.pumpWidget(
      panelInyectado(
        resumen: const ResumenCategorias(
          totalServicios: 5,
          totalEstablecimientos: 3,
          otrosServicios: 3,
          otrosEstablecimientos: 2,
        ),
        onVerTodos: () => verTodos++,
      ),
    );
    await tester.pumpAndSettle();

    // Resumen solo con «Otros»: una única tarjeta y la pastilla de la cabecera.
    expect(find.byType(TarjetaExploracion), findsOneWidget);
    expect(find.text('Otras'), findsOneWidget);
    expect(find.text('2 LOCALES'), findsOneWidget);
    expect(
      find.text('0 categorías · 3 establecimientos · 5 servicios'),
      findsOneWidget,
    );

    await tester.tap(find.text('Otras'));
    await tester.pumpAndSettle();
    expect(verTodos, 1, reason: 'tocar «Otras» no abre carpeta: navega a todos');

    await tester.tap(find.text('Ver todos'));
    await tester.pumpAndSettle();
    expect(verTodos, 2);
  });

  // ═══ 3. Accesibilidad: sin animaciones ══════════════════════════════════

  testWidgets('con disableAnimations la carpeta se abre en el mismo frame', (
    tester,
  ) async {
    await tester.pumpWidget(
      panelInyectado(
        resumen: ResumenCategorias(
          categorias: [
            rubro(
              1,
              'Belleza',
              hijas: [hija(11, 'Uñas'), hija(12, 'Peluquería')],
            ),
          ],
        ),
        media: (base) => base.copyWith(disableAnimations: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Uñas'), findsNothing);
    await tester.tap(find.text('Belleza'));
    // Un solo frame: sin el «boom» de 190 ms ni la cascada.
    await tester.pump();

    expect(
      find.text('Uñas'),
      findsOneWidget,
      reason: 'con las animaciones desactivadas no puede haber retardo',
    );
    expect(
      find.byType(TweenAnimationBuilder<double>),
      findsNothing,
      reason: 'no se debe pedir ninguna animación explícita',
    );
    expect(find.text('Peluquería'), findsOneWidget);
  });

  testWidgets('sin disableAnimations la carpeta espera al «boom» de 190 ms', (
    tester,
  ) async {
    await tester.pumpWidget(
      panelInyectado(
        resumen: ResumenCategorias(
          categorias: [
            rubro(1, 'Belleza', hijas: [hija(11, 'Uñas')]),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Belleza'));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('Uñas'), findsNothing, reason: 'el boom dura 190 ms');

    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(find.text('Uñas'), findsOneWidget);
  });

  testWidgets('doble toque rápido en dos rubros: gana el último, sin restos', (
    tester,
  ) async {
    await tester.pumpWidget(
      panelInyectado(
        resumen: ResumenCategorias(
          categorias: [
            rubro(1, 'Alfa', hijas: [hija(11, 'HijaAlfa')]),
            rubro(2, 'Beta', hijas: [hija(12, 'HijaBeta')]),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Los dos «boom» se solapan: el segundo toque llega antes de que el primero
    // haya cumplido sus 190 ms.
    await tester.tap(find.text('Alfa'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();

    expect(find.text('HijaBeta'), findsOneWidget);
    expect(
      find.text('HijaAlfa'),
      findsNothing,
      reason: 'no puede quedar abierta la carpeta del primer toque',
    );
    expect(find.text('Subcategorías de Beta'), findsOneWidget);
  });

  // ═══ 4. Casos límite ════════════════════════════════════════════════════

  testWidgets('rubro con 0 locales: SIN LOCALES, pie apagado… pero abre', (
    tester,
  ) async {
    CategoriaConConteo? pedida;
    await tester.pumpWidget(
      panelInyectado(
        resumen: ResumenCategorias(
          categorias: [
            rubro(
              9,
              'Transporte',
              locales: 0,
              servicios: 0,
              hijas: [hija(91, 'Mudanzas', locales: 0, servicios: 0)],
            ),
          ],
        ),
        onVerCategoria: (categoria) => pedida = categoria,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SIN LOCALES'), findsOneWidget);
    expect(find.text('Sin establecimientos'), findsOneWidget);

    // El pie apagado no navega (no hay nada que ver). Ojo: el toque cae en la
    // tarjeta de debajo, así que abre la carpeta —el pie no responde, la tarjeta
    // sí—; lo importante es que NO lleva a un listado vacío.
    await tester.tap(find.text('Sin establecimientos'));
    await tester.pumpAndSettle();
    expect(pedida, isNull, reason: 'el pie apagado no puede llevar a una lista');
    expect(find.text('Subcategorías de Transporte'), findsOneWidget);

    // La carpeta está abierta y el banner avisa de que está vacío.
    expect(find.text('Todavía sin establecimientos'), findsOneWidget);
    // Dos: el chip del banner del rubro y el de su subcategoría, también vacía.
    expect(find.text('SIN LOCALES'), findsNWidgets(2));

    // …y el «Ver todos los establecimientos» del banner también está apagado.
    await tester.tap(find.text('Ver todos los establecimientos'));
    await tester.pumpAndSettle();
    expect(pedida, isNull);
    expect(find.text('Mudanzas'), findsOneWidget);
  });

  testWidgets('rubro sin subcategorías: lo dice y el banner lleva al listado', (
    tester,
  ) async {
    CategoriaConConteo? pedida;
    await tester.pumpWidget(
      panelInyectado(
        resumen: ResumenCategorias(
          categorias: [rubro(4, 'Transporte', locales: 2, servicios: 2)],
          totalEstablecimientos: 2,
          totalServicios: 2,
        ),
        onVerCategoria: (categoria) => pedida = categoria,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Transporte'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Este rubro no tiene subcategorías'),
      findsOneWidget,
    );

    await tester.tap(find.text('Ver todos los establecimientos'));
    await tester.pumpAndSettle();
    expect(pedida?.categoria.nombre, 'Transporte');
  });

  testWidgets('nombres larguísimos: no desbordan ni en la rejilla ni dentro', (
    tester,
  ) async {
    final largo = 'Servicios profesionales integrales de ${'consultoría ' * 8}';
    await tester.pumpWidget(
      panelInyectado(
        resumen: ResumenCategorias(
          categorias: [
            rubro(
              7,
              largo,
              locales: 12345,
              servicios: 999,
              hijas: [hija(71, '$largo (sucursal)', locales: 3, servicios: 4)],
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text(largo));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('12345 LOCALES'), findsOneWidget);
  });

  testWidgets('resumen vacío y resumen sin «Otros»', (tester) async {
    // Vacío de verdad: ni rejilla ni «Otras» ni pastilla en la cabecera.
    await tester.pumpWidget(panelInyectado(resumen: ResumenCategorias.vacio));
    await tester.pumpAndSettle();
    expect(
      find.text('El catálogo todavía no tiene categorías publicadas'),
      findsOneWidget,
    );
    expect(find.byType(TarjetaExploracion), findsNothing);
    expect(find.text('Otras'), findsNothing);
    expect(find.textContaining('categorías ·'), findsNothing);

    // Rubros sin «Otros»: el resumen global se pinta, «Otras» no.
    await tester.pumpWidget(
      panelInyectado(
        resumen: ResumenCategorias(
          categorias: [rubro(1, 'Belleza', locales: 3, servicios: 5)],
          totalEstablecimientos: 3,
          totalServicios: 5,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Otras'), findsNothing);
    expect(
      find.text('1 categoría · 3 establecimientos · 5 servicios'),
      findsOneWidget,
    );
  });

  // ═══ 5. Tamaños hostiles ════════════════════════════════════════════════

  testWidgets('320 pt y texto al 130 %: ni la rejilla ni la carpeta desbordan', (
    tester,
  ) async {
    tamano(tester, const Size(320, 640));
    final resumen = resumenCompleto();

    await tester.pumpWidget(
      panelInyectado(
        resumen: resumen,
        media: (base) => base.copyWith(
          textScaler: const TextScaler.linear(1.3),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.takeException(),
      isNull,
      reason: 'la rejilla no puede desbordar a 320 pt con texto al 130 %',
    );

    // La cabecera con la pastilla de totales (el texto más largo de la cabecera)
    // entra igual: si desbordara, `takeException` lo recogería.
    expect(find.textContaining('categorías ·'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // La lista es perezosa: hay que bajar hasta la tarjeta del nombre largo.
    await tester.drag(find.byType(ListView), const Offset(0, -260));
    await tester.pumpAndSettle();
    expect(find.text('Servicios jurídicos y contables'), findsOneWidget);
    expect(
      tester.takeException(),
      isNull,
      reason: 'la tarjeta del nombre largo, a 320 pt y 130 %',
    );

    // Y la carpeta abierta, que es donde hay más piezas.
    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Belleza'));
    await tester.pumpAndSettle();
    expect(find.text('Peluquería'), findsOneWidget);
    expect(
      tester.takeException(),
      isNull,
      reason: 'la carpeta abierta tampoco puede desbordar',
    );
  });

  testWidgets('320 pt con el texto al 200 % (más allá del tope de escala)', (
    tester,
  ) async {
    // El alto de las tarjetas se topa en 1,4× (`clamp(1.0, 1.4)`) pero el texto
    // del sistema no: este es el caso en el que la cuenta se puede descuadrar.
    tamano(tester, const Size(320, 640));
    await tester.pumpWidget(
      panelInyectado(
        resumen: resumenCompleto(),
        media: (base) => base.copyWith(textScaler: const TextScaler.linear(2)),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.takeException(),
      isNull,
      reason: 'la rejilla a 320 pt con texto al 200 %',
    );

    await tester.drag(find.byType(ListView), const Offset(0, -360));
    await tester.pumpAndSettle();
    expect(find.text('Servicios jurídicos y contables'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.drag(find.byType(ListView), const Offset(0, 480));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Belleza'));
    await tester.pumpAndSettle();
    expect(find.text('Subcategorías de Belleza'), findsOneWidget);
    expect(
      tester.takeException(),
      isNull,
      reason: 'la cabecera de la carpeta a 320 pt con texto al 200 %',
    );

    // El banner es alto a 200 %: hay que bajar para que la rejilla de hijas se
    // construya (la lista es perezosa).
    await tester.drag(find.byType(ListView), const Offset(0, -220));
    await tester.pumpAndSettle();
    expect(find.text('Peluquería'), findsOneWidget);
    expect(
      tester.takeException(),
      isNull,
      reason: 'la carpeta abierta a 320 pt con texto al 200 %',
    );
  });

  // ═══ 6. Ruta NO opaca, popUntil y tutorial ══════════════════════════════

  testWidgets('Navigator.popUntil cierra el panel aunque la ruta sea NO opaca', (
    tester,
  ) async {
    tamano(tester, const Size(390, 800));
    final navegador = GlobalKey<NavigatorState>();
    final espia = _EspiaDeRutas();

    await abrirCajon(tester, navigatorKey: navegador, observer: espia);
    expect(find.byType(CategoriasScreen), findsOneWidget);

    // La premisa del test: la ruta del panel NO es opaca.
    final ruta = espia.empujadas.last;
    expect(ruta, isA<RutaLateral<void>>());
    expect((ruta as ModalRoute<dynamic>).opaque, isFalse);

    navegador.currentState!.popUntil((r) => r.isFirst);
    await tester.pumpAndSettle();

    expect(
      find.byType(CategoriasScreen),
      findsNothing,
      reason: 'popUntil tiene que cerrar el cajón igual que una ruta opaca',
    );
    expect(find.text('Abrir categorías'), findsOneWidget);
  });

  testWidgets('volverAlShell cierra el cajón y el paso del tutorial lo reabre', (
    tester,
  ) async {
    tamano(tester, const Size(390, 800));
    BuildContext? raiz;
    await abrirCajon(tester, onRaiz: (contexto) => raiz = contexto);
    expect(find.byType(CategoriasScreen), findsOneWidget);

    // Lo mismo que hace el tutorial al cambiar de paso.
    TutorialNavegacion.volverAlShell(raiz!);
    await tester.pumpAndSettle();
    expect(find.byType(CategoriasScreen), findsNothing);

    // Y el destino `listaCategorias` del tutorial sigue abriendo ESTA pantalla.
    TutorialNavegacion.irACliente(raiz!, TutorialDestino.listaCategorias);
    await tester.pumpAndSettle();
    expect(find.byType(CategoriasScreen), findsOneWidget);
    expect(find.text('Todos los rubros'), findsOneWidget);
    expect(anclaLista, findsOneWidget);
  });

  test('el guion del tutorial apunta el paso «categorias_lista» a esta lista', () {
    final paso = TutorialFlujos.pasosCliente().firstWhere(
      (p) => p.id == 'categorias_lista',
    );
    expect(paso.destino, TutorialDestino.listaCategorias);
    expect(
      TutorialFlujos.pasosCliente().where((p) => p.id == 'categorias_lista').length,
      1,
      reason: 'el id del ancla y el del paso deben ser únicos',
    );
  });
}

/// Espía mínimo para comprobar que la ruta que se empuja es la esperada.
class _EspiaDeRutas extends NavigatorObserver {
  final List<Route<dynamic>> empujadas = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    empujadas.add(route);
    super.didPush(route, previousRoute);
  }
}
