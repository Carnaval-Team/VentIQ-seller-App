// Tests de widget del drawer jerárquico del Home (Fase 4 del rediseño).
//
// Se prueba el widget **real** (`CategoriaDrawer`, `CategoriaDrawerRoute` y las
// tarjetas de categoría y de producto) con un doble de `HomeCatalogoGateway`:
// sin Supabase, sin red y sin `SharedPreferences`. El drawer se monta dentro de
// una ruta de verdad (`abrirCategoriaDrawer`), igual que lo abre el Home, porque
// el botón atrás del sistema y el cierre por arrastre solo tienen sentido con
// una ruta real.
//
// Detalle importante de tiempos: el drawer tendrá una animación «boom»
// (~190 ms) antes de cambiar de nivel y una transición de nivel de 280 ms. Por
// eso, tras cada toque se usa [_asentar] (pump + varios pumps con duración) y no
// `pumpAndSettle()` a secas: un skeleton con animación infinita o un
// temporizador pendiente pueden colgar `pumpAndSettle`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ventiq_app/controllers/home_controller.dart';
import 'package:ventiq_app/models/home_catalogo.dart';
import 'package:ventiq_app/services/home_catalog_service.dart';
import 'package:ventiq_app/widgets/home/categoria_drawer.dart';
import 'package:ventiq_app/widgets/home/categoria_drawer_route.dart';
import 'package:ventiq_app/widgets/home/producto_tile.dart';
import 'package:ventiq_app/widgets/home/tarjeta_exploracion.dart';

// ── Doble del gateway ──────────────────────────────────────────────────────
//
// Copiado del patrón de `test/home/home_controller_test.dart` (clase
// `_GatewayFake`): nada de Supabase, nada de red, y registra las llamadas.

class _GatewayFake implements HomeCatalogoGateway {
  _GatewayFake({
    this.categorias = const <HomeCategoria>[],
    List<HomeSubcategoria> subcategorias = const <HomeSubcategoria>[],
    List<HomeProducto> productos = const <HomeProducto>[],
  }) : subcategoriasFijas = subcategorias,
       productosFijos = productos;

  List<HomeCategoria> categorias;

  /// Ojo con los nombres: `subcategorias` y `productos` ya son métodos de la
  /// interfaz, así que los datos se guardan con otro nombre.
  List<HomeSubcategoria> subcategoriasFijas;
  List<HomeProducto> productosFijos;

  Object? fallaCatalogo;
  Object? fallaSubcategorias;
  Object? fallaProductos;

  int llamadasCatalogo = 0;
  int llamadasSubcategorias = 0;
  int llamadasProductos = 0;

  List<int>? ultimosIdsSubcategorias;
  List<int>? ultimosIdsProductos;

  @override
  Future<List<HomeCategoria>> catalogo({
    required HomeContexto contexto,
    bool forceRefresh = false,
  }) async {
    llamadasCatalogo++;
    if (fallaCatalogo != null) throw fallaCatalogo!;
    return categorias;
  }

  @override
  Future<List<HomeSubcategoria>> subcategorias({
    required List<int> idsCategorias,
    required HomeContexto contexto,
  }) async {
    llamadasSubcategorias++;
    ultimosIdsSubcategorias = idsCategorias;
    if (fallaSubcategorias != null) throw fallaSubcategorias!;
    return subcategoriasFijas;
  }

  @override
  Future<List<HomeProducto>> productos({
    required HomeContexto contexto,
    List<int> idsCategorias = const <int>[],
    String? texto,
    bool soloDisponibles = false,
  }) async {
    llamadasProductos++;
    ultimosIdsProductos = idsCategorias;
    if (fallaProductos != null) throw fallaProductos!;
    return productosFijos;
  }
}

// ── Datos de apoyo ─────────────────────────────────────────────────────────

HomeCategoria _cat(
  int id,
  String nombre, {
  bool especial = false,
  int orden = 0,
  int productos = 0,
  int subcategorias = 0,
  List<int> grupo = const <int>[],
}) => HomeCategoria(
  id: id,
  nombre: nombre,
  especial: especial,
  ordenHome: orden,
  totalProductos: productos,
  totalSubcategorias: subcategorias,
  grupoIds: grupo,
);

HomeProducto _prod(
  int id,
  String nombre, {
  int? sub,
  bool disponible = true,
  double precio = 1,
  double stock = 5,
  String? sku,
  String? imagen,
  bool servicio = false,
}) => HomeProducto(
  id: id,
  nombre: nombre,
  idSubcategoria: sub,
  precio: precio,
  stock: disponible ? stock : 0,
  tieneStock: disponible,
  esServicio: servicio,
  sku: sku,
  imagen: imagen,
);

const HomeContexto _ctx = HomeContexto(idTienda: 173, idTpv: 5);

/// Catálogo con las tres formas que le importan al drawer:
///  * una especial (fuera de «Tienda»),
///  * una categoría con subcategorías (baja un nivel),
///  * una categoría sin subcategorías (va directo a productos).
_GatewayFake _gatewayCompleto() => _GatewayFake(
  categorias: <HomeCategoria>[
    _cat(1, 'Combustibles', especial: true, productos: 2),
    _cat(2, 'Bebidas', productos: 3, subcategorias: 2),
    _cat(3, 'Comida', productos: 1),
  ],
  subcategorias: <HomeSubcategoria>[
    const HomeSubcategoria(id: 20, nombre: 'Gaseosas', totalProductos: 2),
    const HomeSubcategoria(id: 21, nombre: 'Cervezas', totalProductos: 2),
  ],
  productos: <HomeProducto>[
    _prod(100, 'Cola', sub: 20, precio: 1.5, stock: 12),
    _prod(101, 'Malta', sub: 20, precio: 2, stock: 8),
    _prod(102, 'Cerveza', sub: 21, precio: 2.5, stock: 5),
    _prod(103, 'Agua sin stock', sub: 21, disponible: false),
  ],
);

// ── Espías y utilidades de montaje ─────────────────────────────────────────

/// Lo que el drawer le contó a la pantalla que lo abrió.
class _Registro {
  final List<HomeProducto> productosTocados = <HomeProducto>[];
  final List<HomeProducto> agregados = <HomeProducto>[];
  int carritoAbierto = 0;
}

/// Cuenta pops para distinguir «subió un nivel» de «cerró la ruta».
class _Rutas extends NavigatorObserver {
  final List<Route<dynamic>> pila = <Route<dynamic>>[];
  int pops = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pila.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pila.remove(route);
    pops++;
  }
}

Widget _drawer(
  HomeController controller,
  _Registro registro, {
  bool mostrarSku = false,
  bool conAgregar = true,
  ValueNotifier<int>? carrito,
}) {
  return CategoriaDrawer(
    controller: controller,
    mostrarSku: mostrarSku,
    carrito: carrito ?? ValueNotifier<int>(0),
    onAbrirCarrito: () => registro.carritoAbierto++,
    onAbrirProducto: (HomeProducto p) => registro.productosTocados.add(p),
    onAgregarProducto:
        conAgregar ? (HomeProducto p) => registro.agregados.add(p) : null,
  );
}

/// Deja correr la animación «boom» (~190 ms), la transición de nivel (280 ms) y
/// las microtareas de carga. No se usa `pumpAndSettle` para no depender de que
/// no quede ninguna animación infinita (p. ej. el pulso de `VentiqSkeleton`).
Future<void> _asentar(WidgetTester tester) async {
  await tester.pump();
  for (int i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

void _pantallaMovil(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<HomeController> _controladorCon(_GatewayFake g) async {
  final HomeController c = HomeController(gateway: g);
  await c.cargar(_ctx);
  return c;
}

/// Monta el Home mínimo (un botón) y abre el drawer **real** con
/// [abrirCategoriaDrawer], que es exactamente como lo abre `HomeShellScreen`.
Future<_Registro> _abrirDrawer(
  WidgetTester tester, {
  required HomeController controller,
  bool mostrarSku = false,
  bool conAgregar = true,
  ValueNotifier<int>? carrito,
  _Rutas? rutas,
}) async {
  final _Registro registro = _Registro();

  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: <NavigatorObserver>[if (rutas != null) rutas],
      home: Scaffold(
        body: Builder(
          builder:
              (BuildContext context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    await abrirCategoriaDrawer<void>(
                      context,
                      builder:
                          (_) => _drawer(
                            controller,
                            registro,
                            mostrarSku: mostrarSku,
                            conAgregar: conAgregar,
                            carrito: carrito,
                          ),
                    );
                  },
                  child: const Text('Abrir categorías'),
                ),
              ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Abrir categorías'));
  await _asentar(tester);

  return registro;
}

/// «Atrás» del sistema (botón/gesto de Android), el mismo camino que usa
/// `PopScope` en producción.
Future<void> _atrasDelSistema(WidgetTester tester) async {
  // ignore: invalid_use_of_protected_member
  await tester.binding.handlePopRoute();
  await _asentar(tester);
}

/// Toca la primera migaja del breadcrumb («Tienda»).
Future<void> _tocarMigajaTienda(WidgetTester tester) async {
  await tester.tap(find.text('Tienda'));
  await _asentar(tester);
}

Widget _appTile(Widget tile) {
  return MaterialApp(home: Scaffold(body: SafeArea(child: tile)));
}

/// La tarjeta de producto que contiene ese texto.
///
/// En el nivel de productos **todo** lo que hay en la rejilla es una
/// `TarjetaExploracion`, así que el ancestro identifica la tarjeta entera y no
/// solo el texto.
Finder _tarjetaDe(String texto) => find.ancestor(
  of: find.text(texto),
  matching: find.byType(TarjetaExploracion),
);

void main() {
  // ── Nivel 0 ────────────────────────────────────────────────────────────

  group('nivel 0 · rejilla de categorías', () {
    testWidgets(
      'pinta una tarjeta por categoría de «Tienda» y ninguna especial',
      (WidgetTester tester) async {
        _pantallaMovil(tester);
        final HomeController c = await _controladorCon(_gatewayCompleto());
        c.abrirTienda(); // nivel raíz: las categorías no especiales

        await _abrirDrawer(tester, controller: c);

        expect(find.byType(CategoriaDrawer), findsOneWidget);
        expect(find.byType(TarjetaExploracion), findsNWidgets(2));
        expect(find.text('Bebidas'), findsOneWidget);
        expect(find.text('Comida'), findsOneWidget);
        expect(
          find.text('Combustibles'),
          findsNothing,
          reason:
              'las especiales se abren desde el Home, no dentro de "Tienda"',
        );
        expect(find.text('3 PRODUCTOS'), findsOneWidget);
        expect(find.text('1 PRODUCTO'), findsOneWidget);
        expect(
          find.text('2 subcategorías'),
          findsOneWidget,
          reason: 'la tarjeta dice cuántas hijas tiene',
        );
      },
    );
  });

  // ── Bajar de nivel ─────────────────────────────────────────────────────

  group('bajar de nivel', () {
    testWidgets(
      'categoría con subcategorías → nivel de subcategorías y migajas '
      '«Tienda › Bebidas»',
      (WidgetTester tester) async {
        _pantallaMovil(tester);
        final HomeController c = await _controladorCon(_gatewayCompleto());
        c.abrirTienda();
        await _abrirDrawer(tester, controller: c);

        await tester.tap(find.text('Bebidas'));
        await _asentar(tester);

        expect(c.pasoActual!.nivel, HomeNivelDrawer.subcategorias);
        expect(c.migajas, <String>['Tienda', 'Bebidas']);

        // La cabecera muestra las dos migajas, en orden y en la misma línea.
        expect(find.text('Tienda'), findsOneWidget);
        final Offset tienda = tester.getCenter(find.text('Tienda'));
        final Offset bebidas = tester.getCenter(find.text('Bebidas').first);
        expect(
          tienda.dy,
          lessThan(160),
          reason: 'la migaja está en la cabecera',
        );
        expect(
          (tienda.dy - bebidas.dy).abs(),
          lessThan(4),
          reason: '«Tienda» y «Bebidas» comparten línea de migajas',
        );
        expect(
          tienda.dx,
          lessThan(bebidas.dx),
          reason: 'el orden del breadcrumb es Tienda › Bebidas',
        );

        // Y el nivel pinta las subcategorías, con su banner de categoría.
        expect(find.byType(TarjetaExploracion), findsNWidgets(2));
        expect(find.text('Gaseosas'), findsOneWidget);
        expect(find.text('Cervezas'), findsOneWidget);
        // Ya no hay atajo al listado completo desde el banner.
        expect(find.text('Ver todos los productos'), findsNothing);
      },
    );

    testWidgets(
      'categoría sin subcategorías → nivel de productos en tarjetas, con el '
      'banner de la categoría',
      (WidgetTester tester) async {
        _pantallaMovil(tester);
        final HomeController c = await _controladorCon(_gatewayCompleto());
        c.abrirTienda();
        await _abrirDrawer(tester, controller: c);

        await tester.tap(find.text('Comida'));
        await _asentar(tester);

        expect(c.pasoActual!.nivel, HomeNivelDrawer.productos);
        expect(
          c.pila.length,
          2,
          reason: 'no hay nivel intermedio de subcategorías',
        );
        // Una tarjeta por producto; el banner no es tarjeta.
        expect(find.byType(TarjetaExploracion), findsNWidgets(4));
        expect(find.text('Cola'), findsOneWidget);
        // El banner dice el rubro y sus números: es lo que deja claro en qué
        // categoría se está vendiendo.
        expect(find.text('1 producto · 0 subcategorías'), findsOneWidget);
        expect(find.text('Seguir añadiendo'), findsOneWidget);
        expect(find.text('Carrito'), findsOneWidget);
      },
    );

    testWidgets(
      'una especial con UNA subcategoría salta a sus productos y enseña la '
      'categoría, no la hija',
      (WidgetTester tester) async {
        _pantallaMovil(tester);
        final _GatewayFake g = _GatewayFake(
          categorias: <HomeCategoria>[
            _cat(
              1,
              'Combustibles',
              especial: true,
              productos: 2,
              subcategorias: 1,
            ),
          ],
          subcategorias: <HomeSubcategoria>[
            const HomeSubcategoria(
              id: 20,
              nombre: 'Especiales',
              totalProductos: 2,
            ),
          ],
          productos: <HomeProducto>[
            _prod(100, 'Especial 95', sub: 20, precio: 1.5),
            _prod(101, 'Especial 91', sub: 20, precio: 1.25),
          ],
        );
        final HomeController c = await _controladorCon(g);
        await c.abrirEspecial(c.especiales.single);
        await _abrirDrawer(tester, controller: c);

        expect(c.pasoActual!.nivel, HomeNivelDrawer.productos);
        expect(
          g.llamadasSubcategorias,
          0,
          reason: 'no se pide un nivel que no se va a pintar',
        );
        expect(
          find.text('Especiales'),
          findsNothing,
          reason: 'se muestra la categoría, no la única subcategoría',
        );
        expect(find.text('2 productos · 1 subcategoría'), findsOneWidget);
        expect(find.byType(TarjetaExploracion), findsNWidgets(2));
        expect(find.text('Especial 95'), findsOneWidget);
        // La raíz ES el nivel de productos, así que no hay a dónde subir: el
        // pie deja solo el carrito, igual que en una especial sin hijas.
        expect(find.text('Seguir añadiendo'), findsNothing);
        expect(find.text('Carrito'), findsOneWidget);
      },
    );
  });

  // ── Volver atrás ───────────────────────────────────────────────────────

  group('volver atrás', () {
    testWidgets('el «atrás» del sistema sube un nivel y NO cierra', (
      WidgetTester tester,
    ) async {
      _pantallaMovil(tester);
      final _Rutas rutas = _Rutas();
      final HomeController c = await _controladorCon(_gatewayCompleto());
      c.abrirTienda();
      await _abrirDrawer(tester, controller: c, rutas: rutas);

      await tester.tap(find.text('Bebidas'));
      await _asentar(tester);
      expect(c.pila.length, 2);

      await _atrasDelSistema(tester);

      expect(c.pila.length, 1, reason: 'sube un nivel, no cierra');
      expect(c.pasoActual!.nivel, HomeNivelDrawer.categorias);
      expect(
        find.byType(CategoriaDrawer),
        findsOneWidget,
        reason: 'el drawer sigue en pantalla',
      );
      expect(rutas.pops, 0, reason: 'no se hizo pop de la ruta');
      expect(find.byType(TarjetaExploracion), findsNWidgets(2));
    });

    testWidgets('el «atrás» del sistema en la raíz cierra la ruta del drawer', (
      WidgetTester tester,
    ) async {
      _pantallaMovil(tester);
      final _Rutas rutas = _Rutas();
      final HomeController c = await _controladorCon(_gatewayCompleto());
      c.abrirTienda();
      await _abrirDrawer(tester, controller: c, rutas: rutas);

      expect(c.pila.length, 1, reason: 'estamos en la raíz');
      expect(find.byType(CategoriaDrawer), findsOneWidget);

      await _atrasDelSistema(tester);

      expect(find.byType(CategoriaDrawer), findsNothing);
      expect(rutas.pops, 1, reason: 'la ruta del drawer se cerró');
      expect(
        find.text('Abrir categorías'),
        findsOneWidget,
        reason: 'volvemos a la pantalla de debajo',
      );
    });

    testWidgets('tocar la primera migaja vuelve al nivel 0 desde dos niveles '
        'abajo', (WidgetTester tester) async {
      _pantallaMovil(tester);
      final HomeController c = await _controladorCon(_gatewayCompleto());
      c.abrirTienda();
      await _abrirDrawer(tester, controller: c);

      await tester.tap(find.text('Bebidas'));
      await _asentar(tester);
      await tester.tap(find.text('Gaseosas'));
      await _asentar(tester);
      expect(c.migajas, <String>['Tienda', 'Bebidas', 'Gaseosas']);
      expect(c.pila.length, 3);

      await _tocarMigajaTienda(tester);

      expect(c.pila.length, 1);
      expect(c.pasoActual!.nivel, HomeNivelDrawer.categorias);
      expect(find.byType(TarjetaExploracion), findsNWidgets(2));
      expect(find.text('Gaseosas'), findsNothing);
      expect(find.text('Seguir añadiendo'), findsNothing);
    });

    testWidgets('swipe desde el borde izquierdo (> 64 px) sube un nivel', (
      WidgetTester tester,
    ) async {
      _pantallaMovil(tester);
      final HomeController c = await _controladorCon(_gatewayCompleto());
      c.abrirTienda();
      await _abrirDrawer(tester, controller: c);

      await tester.tap(find.text('Bebidas'));
      await _asentar(tester);
      expect(c.pila.length, 2);

      // x ≈ 5: la franja de 28 px del borde izquierdo.
      await tester.dragFrom(const Offset(5, 300), const Offset(160, 0));
      await _asentar(tester);

      expect(c.pila.length, 1);
      expect(c.pasoActual!.nivel, HomeNivelDrawer.categorias);
      expect(find.byType(CategoriaDrawer), findsOneWidget);
    });

    testWidgets('swipe corto desde el borde (< 64 px) NO sube de nivel', (
      WidgetTester tester,
    ) async {
      _pantallaMovil(tester);
      final HomeController c = await _controladorCon(_gatewayCompleto());
      c.abrirTienda();
      await _abrirDrawer(tester, controller: c);

      await tester.tap(find.text('Bebidas'));
      await _asentar(tester);
      expect(c.pila.length, 2);

      await tester.dragFrom(const Offset(5, 300), const Offset(30, 0));
      await _asentar(tester);

      expect(c.pila.length, 2, reason: 'no llegó al umbral: sigue en el nivel');
      expect(c.pasoActual!.nivel, HomeNivelDrawer.subcategorias);
    });

    testWidgets('arrastrar la cabecera hacia abajo (> 120 px) cierra la ruta', (
      WidgetTester tester,
    ) async {
      _pantallaMovil(tester);
      final _Rutas rutas = _Rutas();
      final HomeController c = await _controladorCon(_gatewayCompleto());
      c.abrirTienda();
      await _abrirDrawer(tester, controller: c, rutas: rutas);
      expect(find.byType(CategoriaDrawer), findsOneWidget);

      // Se arrastra desde el breadcrumb: es cabecera, no cuerpo scrolleable.
      await tester.drag(find.text('Tienda'), const Offset(0, 260));
      await _asentar(tester);

      expect(find.byType(CategoriaDrawer), findsNothing);
      expect(rutas.pops, 1, reason: 'cerró la ruta del drawer');
      expect(find.text('Abrir categorías'), findsOneWidget);
    });

    testWidgets('la «X» cierra la ruta aunque se esté en un nivel profundo', (
      WidgetTester tester,
    ) async {
      // El cierre va con `Navigator.pop()` directo: con `maybePop` el `PopScope`
      // de un nivel profundo se lo tragaría y solo subiría un nivel.
      _pantallaMovil(tester);
      final _Rutas rutas = _Rutas();
      final HomeController c = await _controladorCon(_gatewayCompleto());
      c.abrirTienda();
      await _abrirDrawer(tester, controller: c, rutas: rutas);

      await tester.tap(find.text('Bebidas'));
      await _asentar(tester);
      await tester.tap(find.text('Gaseosas'));
      await _asentar(tester);
      expect(
        c.pila.length,
        3,
        reason: 'estamos dos niveles por debajo de la raíz',
      );
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await _asentar(tester);

      expect(find.byType(CategoriaDrawer), findsNothing);
      expect(rutas.pops, 1, reason: 'la «X» cierra la ruta, no sube un nivel');
      expect(find.text('Abrir categorías'), findsOneWidget);
    });
  });

  // ── Pie del drawer: seguir añadiendo / ir al carrito ───────────────────

  group('pie del carrito', () {
    testWidgets('muestra «Seguir añadiendo» y el carrito con su contador', (
      WidgetTester tester,
    ) async {
      _pantallaMovil(tester);
      final ValueNotifier<int> carrito = ValueNotifier<int>(0);
      addTearDown(carrito.dispose);
      final HomeController c = await _controladorCon(_gatewayCompleto());
      c.abrirTienda();
      final _Registro r = await _abrirDrawer(
        tester,
        controller: c,
        carrito: carrito,
      );

      await tester.tap(find.text('Comida'));
      await _asentar(tester);

      expect(find.text('Seguir añadiendo'), findsOneWidget);
      expect(find.text('Carrito'), findsOneWidget);
      expect(
        find.text('Ver listado completo (4)'),
        findsNothing,
        reason: 'el listado completo del drawer ya no se usa',
      );

      // El contador del carrito llega por listenable: se repinta solo.
      carrito.value = 3;
      await tester.pump();
      expect(find.text('Carrito (3)'), findsOneWidget);

      await tester.tap(find.text('Carrito (3)'));
      await tester.pump();
      expect(r.carritoAbierto, 1);
    });

    testWidgets('«Seguir añadiendo» vuelve al nivel de categorías', (
      WidgetTester tester,
    ) async {
      _pantallaMovil(tester);
      final HomeController c = await _controladorCon(_gatewayCompleto());
      c.abrirTienda();
      await _abrirDrawer(tester, controller: c);

      await tester.tap(find.text('Bebidas'));
      await _asentar(tester);
      await tester.tap(find.text('Gaseosas'));
      await _asentar(tester);
      expect(c.pila.length, 3);

      await tester.tap(find.text('Seguir añadiendo'));
      await _asentar(tester);

      expect(c.pila.length, 1, reason: 'vuelve a la raíz sin cerrar');
      expect(c.pasoActual!.nivel, HomeNivelDrawer.categorias);
      expect(find.byType(CategoriaDrawer), findsOneWidget);
      expect(find.byType(TarjetaExploracion), findsNWidgets(2));
    });

    testWidgets(
      '«Seguir añadiendo» con raíz de subcategorías las conserva visibles',
      (WidgetTester tester) async {
        // Regresión: al volver de los productos de una subcategoría, la raíz
        // (subcategorías de la especial) se quedaba vacía y decía que la
        // categoría no tenía subcategorías.
        _pantallaMovil(tester);
        final _GatewayFake g = _GatewayFake(
          categorias: <HomeCategoria>[
            _cat(2, 'Bebidas', especial: true, productos: 3, subcategorias: 2),
          ],
          subcategorias: <HomeSubcategoria>[
            const HomeSubcategoria(
              id: 20,
              nombre: 'Gaseosas',
              totalProductos: 2,
            ),
            const HomeSubcategoria(
              id: 21,
              nombre: 'Cervezas',
              totalProductos: 1,
            ),
          ],
          productos: <HomeProducto>[
            _prod(100, 'Cola', sub: 20),
            _prod(101, 'Malta', sub: 20),
          ],
        );
        final HomeController c = await _controladorCon(g);
        await c.abrirEspecial(c.especiales.single);
        await _abrirDrawer(tester, controller: c);

        await tester.tap(find.text('Gaseosas'));
        await _asentar(tester);
        expect(c.pila.length, 2);
        expect(c.pasoActual!.nivel, HomeNivelDrawer.productos);

        await tester.tap(find.text('Seguir añadiendo'));
        await _asentar(tester);

        expect(c.pila.length, 1);
        expect(c.pasoActual!.nivel, HomeNivelDrawer.subcategorias);
        expect(find.text('Gaseosas'), findsOneWidget);
        expect(find.text('Cervezas'), findsOneWidget);
        expect(
          find.textContaining('no tiene subcategorías'),
          findsNothing,
          reason: 'las subcategorías siguen cargadas al volver',
        );
      },
    );
  });

  // ── Productos dentro del drawer ────────────────────────────────────────

  group('productos', () {
    testWidgets(
      'tocar la tarjeta de un producto llama a la venta rápida, sin cerrar el '
      'drawer',
      (WidgetTester tester) async {
        _pantallaMovil(tester);
        final _Rutas rutas = _Rutas();
        final HomeController c = await _controladorCon(_gatewayCompleto());
        c.abrirTienda();
        final _Registro r = await _abrirDrawer(
          tester,
          controller: c,
          rutas: rutas,
        );

        await tester.tap(find.text('Comida'));
        await _asentar(tester);

        await tester.tap(find.text('Cola'));
        await _asentar(tester);

        expect(r.agregados.map((HomeProducto p) => p.nombre), <String>['Cola']);
        expect(
          r.productosTocados,
          isEmpty,
          reason:
              'la tarjeta entera es el atajo de venta: quién decide entre '
              'carrito y detalle es el alta rápida de la pantalla',
        );
        expect(
          find.byType(CategoriaDrawer),
          findsOneWidget,
          reason: 'la venta rápida no cierra el drawer',
        );
        expect(rutas.pops, 0);
      },
    );

    testWidgets('sin callback de venta rápida la tarjeta abre el detalle', (
      WidgetTester tester,
    ) async {
      // La tarjeta no se queda muerta cuando la pantalla no pasa el atajo.
      _pantallaMovil(tester);
      final HomeController c = await _controladorCon(_gatewayCompleto());
      c.abrirTienda();
      final _Registro r = await _abrirDrawer(
        tester,
        controller: c,
        conAgregar: false,
      );

      await tester.tap(find.text('Comida'));
      await _asentar(tester);

      await tester.tap(find.text('Cola'));
      await _asentar(tester);

      expect(r.productosTocados.map((HomeProducto p) => p.nombre), <String>[
        'Cola',
      ]);
      expect(r.agregados, isEmpty);
    });

    testWidgets('la tarjeta de un agotado va atenuada y no responde al toque', (
      WidgetTester tester,
    ) async {
      _pantallaMovil(tester);
      final HomeController c = await _controladorCon(_gatewayCompleto());
      c.abrirTienda();
      final _Registro r = await _abrirDrawer(tester, controller: c);

      await tester.tap(find.text('Comida'));
      await _asentar(tester);

      // El estado de stock se lee en el chip de la propia tarjeta.
      expect(
        find.descendant(
          of: _tarjetaDe('Agua sin stock'),
          matching: find.text('AGOTADO'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _tarjetaDe('Cola'),
          matching: find.text('STOCK: 12'),
        ),
        findsOneWidget,
      );

      // El agotado va atenuado…
      final Finder atenuada = find.ancestor(
        of: find.text('Agua sin stock'),
        matching: find.byType(Opacity),
      );
      expect(atenuada, findsWidgets);
      expect(
        tester.widgetList<Opacity>(atenuada).every(
          (Opacity o) => o.opacity < 1,
        ),
        isTrue,
        reason: 'un no disponible se sigue viendo, pero apagado',
      );
      // …y un disponible no lleva atenuación ninguna.
      expect(
        find.ancestor(of: find.text('Cola'), matching: find.byType(Opacity)),
        findsNothing,
      );

      // El toque en el agotado no vende ni abre nada. Se toca por coordenadas
      // a propósito: la tarjeta está dentro de un `IgnorePointer` y `tap()`
      // avisaría de que el punto no pertenece al texto.
      await tester.tapAt(tester.getCenter(find.text('Agua sin stock')));
      await _asentar(tester);

      expect(
        r.agregados,
        isEmpty,
        reason: 'un agotado no se vende de un toque',
      );
      expect(r.productosTocados, isEmpty);
    });

    testWidgets('la tarjeta lleva la foto del producto, el precio y el stock', (
      WidgetTester tester,
    ) async {
      _pantallaMovil(tester);
      final _GatewayFake g = _GatewayFake(
        categorias: <HomeCategoria>[_cat(1, 'Comida', productos: 2)],
        productos: <HomeProducto>[
          _prod(
            100,
            'Cola',
            precio: 1.5,
            stock: 12,
            imagen: 'https://cdn.example/cola.png',
          ),
          _prod(101, 'Malta', precio: 2, stock: 8),
        ],
      );
      final HomeController c = await _controladorCon(g);
      c.abrirTienda();
      await _abrirDrawer(tester, controller: c);

      await tester.tap(find.text('Comida'));
      await _asentar(tester);

      final TarjetaExploracion cola = tester.widget<TarjetaExploracion>(
        _tarjetaDe('Cola'),
      );
      expect(cola.titulo, 'Cola');
      expect(cola.imagenUrl, 'https://cdn.example/cola.png');
      // Mismo formateador que la fila y el riel.
      expect(cola.subtitulo, r'$1.50');
      expect(cola.chip, 'STOCK: 12');

      final TarjetaExploracion malta = tester.widget<TarjetaExploracion>(
        _tarjetaDe('Malta'),
      );
      expect(
        malta.imagenUrl,
        isNull,
        reason: 'sin foto manda el degradado, como en las categorías',
      );
      expect(malta.chip, 'STOCK: 8');
    });

    testWidgets('con el ajuste de SKU activo, la tarjeta lo pinta tras el '
        'precio', (WidgetTester tester) async {
      _pantallaMovil(tester);
      final _GatewayFake g = _GatewayFake(
        categorias: <HomeCategoria>[_cat(1, 'Comida', productos: 1)],
        productos: <HomeProducto>[
          _prod(100, 'Cola', precio: 1.5, sku: 'SKU-COLA-1'),
        ],
      );
      final HomeController c = await _controladorCon(g);
      c.abrirTienda();
      await _abrirDrawer(tester, controller: c, mostrarSku: true);

      await tester.tap(find.text('Comida'));
      await _asentar(tester);

      expect(
        tester.widget<TarjetaExploracion>(_tarjetaDe('Cola')).subtitulo,
        r'$1.50 · SKU-COLA-1',
      );
    });
  });

  // ── ProductoTile por separado ──────────────────────────────────────────

  group('ProductoTile', () {
    testWidgets('pinta el subtítulo opcional (categoría en la búsqueda)', (
      WidgetTester tester,
    ) async {
      _pantallaMovil(tester);
      await tester.pumpWidget(
        _appTile(
          ProductoTile(
            producto: _prod(1, 'Arroz'),
            onTap: () {},
            subtitulo: 'Alimentos',
          ),
        ),
      );

      expect(find.text('Alimentos'), findsOneWidget);
    });

    testWidgets('un elaborado pinta «Elaborable: N», no «Stock»', (
      WidgetTester tester,
    ) async {
      _pantallaMovil(tester);
      await tester.pumpWidget(
        _appTile(
          ProductoTile(
            producto: const HomeProducto(
              id: 10800,
              nombre: 'tacos',
              precio: 12,
              stock: 41000,
              tieneStock: true,
              esElaborado: true,
            ),
            onTap: () {},
          ),
        ),
      );

      expect(find.text('Elaborable: 41000'), findsOneWidget);
      expect(find.textContaining('Stock:'), findsNothing);
    });

    testWidgets('mostrarSku pinta el SKU; sin el flag no aparece', (
      WidgetTester tester,
    ) async {
      _pantallaMovil(tester);
      final HomeProducto p = _prod(1, 'Arroz', sku: 'SKU-ARROZ-1', precio: 2.5);

      await tester.pumpWidget(
        _appTile(ProductoTile(producto: p, onTap: () {}, mostrarSku: true)),
      );
      expect(find.text('SKU-ARROZ-1'), findsOneWidget);
      // El precio del tile pasa por el formateador de moneda de venta: sin
      // divisa alternativa activa sale idéntico a antes, con el símbolo `$`
      // (igual que el riel) porque el default de las tasas es CUP.
      expect(find.text(r'$2.50'), findsOneWidget);

      await tester.pumpWidget(
        _appTile(ProductoTile(producto: p, onTap: () {})),
      );
      await tester.pump();
      expect(find.text('SKU-ARROZ-1'), findsNothing);
    });

    testWidgets('un agotado pinta «Agotado» y no ofrece «+»', (
      WidgetTester tester,
    ) async {
      _pantallaMovil(tester);
      await tester.pumpWidget(
        _appTile(
          ProductoTile(
            producto: _prod(2, 'Agua', disponible: false),
            onTap: () {},
            onAgregar: null,
          ),
        ),
      );

      expect(find.text('Agotado'), findsOneWidget);
      expect(find.byIcon(Icons.add_rounded), findsNothing);
    });

    testWidgets('el «+» lleva Semantics «Agregar a la venta» y responde al '
        'toque', (WidgetTester tester) async {
      _pantallaMovil(tester);
      // El handle se libera DENTRO del test: el framework comprueba que no
      // quede ninguno activo antes de ejecutar los `addTearDown`.
      final SemanticsHandle semantica = tester.ensureSemantics();

      int agregados = 0;
      await tester.pumpWidget(
        _appTile(
          ProductoTile(
            producto: _prod(3, 'Refresco', precio: 1.25),
            onTap: () {},
            onAgregar: () => agregados++,
          ),
        ),
      );

      // El nodo de accesibilidad que anuncia el botón.
      expect(find.bySemanticsLabel('Agregar a la venta'), findsWidgets);

      // Y el widget real que lo declara (ojo: `InkWell` mete su propio
      // `Semantics` dentro, así que se busca por la etiqueta, no por ancestro).
      final Finder botonSemantico = find.byWidgetPredicate(
        (Widget w) =>
            w is Semantics && w.properties.label == 'Agregar a la venta',
      );
      expect(botonSemantico, findsOneWidget);
      expect(
        tester.widget<Semantics>(botonSemantico).properties.button,
        isTrue,
      );

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();
      expect(agregados, 1);

      semantica.dispose();
    });

    testWidgets('tocar la fila abre el detalle (onTap), sin cerrar nada', (
      WidgetTester tester,
    ) async {
      _pantallaMovil(tester);
      int toques = 0;
      await tester.pumpWidget(
        _appTile(
          ProductoTile(producto: _prod(4, 'Dado'), onTap: () => toques++),
        ),
      );

      await tester.tap(find.text('Dado'));
      await tester.pump();

      expect(toques, 1);
    });
  });
}
