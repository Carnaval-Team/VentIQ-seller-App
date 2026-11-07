import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/controllers/home_controller.dart';
import 'package:ventiq_app/models/home_catalogo.dart';
import 'package:ventiq_app/services/home_catalog_service.dart';

/// Doble del gateway: nada de Supabase, nada de red, y registra las llamadas
/// para poder afirmar sobre ellas.
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
  String? ultimoTexto;
  bool? ultimoSoloDisponibles;

  Duration retardoProductos = Duration.zero;

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
    ultimoTexto = texto;
    ultimoSoloDisponibles = soloDisponibles;
    if (retardoProductos > Duration.zero) {
      await Future<void>.delayed(retardoProductos);
    }
    if (fallaProductos != null) throw fallaProductos!;
    return productosFijos;
  }
}

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

HomeProducto _prod(int id, String nombre, {int? sub, bool stock = true}) =>
    HomeProducto(
      id: id,
      nombre: nombre,
      idSubcategoria: sub,
      tieneStock: stock,
    );

const HomeContexto _ctx = HomeContexto(idTienda: 173, idTpv: 5);

void main() {
  group('carga', () {
    test('reparte especiales y Tienda y queda en listo', () async {
      final _GatewayFake g = _GatewayFake(
        categorias: <HomeCategoria>[
          _cat(1, 'Combustibles', especial: true),
          _cat(2, 'Servicios', especial: true),
          _cat(3, 'Comida', productos: 20),
          _cat(4, 'Recreacion', productos: 5),
        ],
      );
      final HomeController c = HomeController(gateway: g);

      await c.cargar(_ctx);

      expect(c.estado, HomeEstado.listo);
      expect(c.especiales.map((HomeCategoria e) => e.nombre), <String>[
        'Combustibles',
        'Servicios',
      ]);
      expect(c.categoriasTienda.map((HomeCategoria e) => e.nombre), <String>[
        'Comida',
        'Recreacion',
      ]);
      expect(c.mostrarTarjetaTienda, isTrue);
      expect(c.productosEnTienda, 25);
      expect(c.mensajeError, isNull);
    });

    test('sin especiales, Tienda lo agrupa todo', () async {
      final _GatewayFake g = _GatewayFake(
        categorias: <HomeCategoria>[_cat(1, 'Comida'), _cat(2, 'Recreacion')],
      );
      final HomeController c = HomeController(gateway: g);

      await c.cargar(_ctx);

      expect(c.especiales, isEmpty);
      expect(c.rubrosEnTienda, 2);
    });

    test('si no hay nada y falla, queda en error con mensaje', () async {
      final _GatewayFake g =
          _GatewayFake()..fallaCatalogo = Exception('sin red');
      final HomeController c = HomeController(gateway: g);

      await c.cargar(_ctx);

      expect(c.estado, HomeEstado.error);
      expect(c.mensajeError, isNotNull);
    });

    test('si ya había catálogo y falla, NO se tira lo que hay', () async {
      final _GatewayFake g = _GatewayFake(
        categorias: <HomeCategoria>[_cat(1, 'Comida')],
      );
      final HomeController c = HomeController(gateway: g);
      await c.cargar(_ctx);

      g.fallaCatalogo = Exception('sin red');
      await c.refrescar();

      expect(
        c.estado,
        HomeEstado.listo,
        reason: 'mejor un Home algo viejo que un Home vacío en un turno',
      );
      expect(c.categoriasTienda.length, 1);
    });

    test('cambiar de contexto limpia el drawer', () async {
      final _GatewayFake g = _GatewayFake(
        categorias: <HomeCategoria>[
          _cat(1, 'Combustibles', especial: true, subcategorias: 2),
        ],
      );
      final HomeController c = HomeController(gateway: g);
      await c.cargar(_ctx);
      await c.abrirEspecial(c.especiales.single);
      expect(c.drawerAbierto, isTrue);

      await c.cargar(const HomeContexto(idTienda: 999, idTpv: 1));

      expect(c.drawerAbierto, isFalse);
    });

    test('refrescar pide saltándose la caché', () async {
      final _GatewayFake g = _GatewayFake(
        categorias: <HomeCategoria>[_cat(1, 'Comida')],
      );
      final HomeController c = HomeController(gateway: g);

      await c.cargar(_ctx);
      await c.refrescar();

      expect(g.llamadasCatalogo, 2);
    });
  });

  group('búsqueda', () {
    test('espera el debounce antes de consultar', () async {
      final _GatewayFake g = _GatewayFake(
        categorias: <HomeCategoria>[_cat(1, 'Comida')],
        productos: <HomeProducto>[_prod(1, 'Arroz')],
      );
      final HomeController c = HomeController(
        gateway: g,
        debounceBusqueda: const Duration(milliseconds: 30),
      );
      await c.cargar(_ctx);

      c.buscar('arr');
      expect(
        g.llamadasProductos,
        0,
        reason: 'todavía no debe haber consultado',
      );
      expect(c.buscando, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(g.llamadasProductos, 1);
      expect(g.ultimoTexto, 'arr');
      expect(c.resultados.single.nombre, 'Arroz');
      expect(c.buscando, isFalse);
    });

    test('teclear rápido no dispara una consulta por letra', () async {
      final _GatewayFake g = _GatewayFake();
      final HomeController c = HomeController(
        gateway: g,
        debounceBusqueda: const Duration(milliseconds: 50),
      );
      await c.cargar(_ctx);

      c.buscar('a');
      c.buscar('ar');
      c.buscar('arr');
      c.buscar('arro');
      c.buscar('arroz');
      await Future<void>.delayed(const Duration(milliseconds: 90));

      expect(g.llamadasProductos, 1);
      expect(g.ultimoTexto, 'arroz');
    });

    test('una respuesta vieja no pisa a la nueva', () async {
      final _GatewayFake g = _GatewayFake();
      final HomeController c = HomeController(
        gateway: g,
        debounceBusqueda: Duration.zero,
      );
      await c.cargar(_ctx);

      // La primera búsqueda tarda; la segunda llega antes.
      g.retardoProductos = const Duration(milliseconds: 60);
      g.productosFijos = <HomeProducto>[_prod(1, 'Resultado viejo')];
      final Future<void> lenta = c.buscarAhora('viejo');

      g.retardoProductos = Duration.zero;
      g.productosFijos = <HomeProducto>[_prod(2, 'Resultado nuevo')];
      await c.buscarAhora('nuevo');

      await lenta;

      expect(c.resultados.single.nombre, 'Resultado nuevo');
    });

    test('limpiar deja el lienzo en categorías', () async {
      final _GatewayFake g = _GatewayFake(
        categorias: <HomeCategoria>[_cat(1, 'Comida')],
        productos: <HomeProducto>[_prod(1, 'Arroz')],
      );
      final HomeController c = HomeController(
        gateway: g,
        debounceBusqueda: Duration.zero,
      );
      await c.cargar(_ctx);
      await c.buscarAhora('arroz');
      expect(c.hayBusquedaActiva, isTrue);

      c.limpiarBusqueda();

      expect(c.hayBusquedaActiva, isFalse);
      expect(c.resultados, isEmpty);
      expect(c.buscando, isFalse);
    });

    test('buscar en vacío no consulta y no deja el spinner', () async {
      final _GatewayFake g = _GatewayFake();
      final HomeController c = HomeController(
        gateway: g,
        debounceBusqueda: Duration.zero,
      );
      await c.cargar(_ctx);

      c.buscar('   ');

      expect(g.llamadasProductos, 0);
      expect(c.buscando, isFalse);
    });

    test('si la búsqueda falla, no deja el spinner colgado', () async {
      final _GatewayFake g = _GatewayFake(
        categorias: <HomeCategoria>[_cat(1, 'Comida')],
      )..fallaProductos = Exception('sin red');
      final HomeController c = HomeController(
        gateway: g,
        debounceBusqueda: Duration.zero,
      );
      await c.cargar(_ctx);

      await c.buscarAhora('arroz');

      expect(c.buscando, isFalse);
      expect(c.resultados, isEmpty);
    });
  });

  group('drawer · entrada desde el Home', () {
    test('"Tienda" abre el nivel de categorías', () async {
      final _GatewayFake g = _GatewayFake(
        categorias: <HomeCategoria>[
          _cat(1, 'Combustibles', especial: true),
          _cat(2, 'Comida'),
          _cat(3, 'Recreacion'),
        ],
      );
      final HomeController c = HomeController(gateway: g);
      await c.cargar(_ctx);

      c.abrirTienda();

      expect(c.drawerAbierto, isTrue);
      expect(c.pasoActual!.nivel, HomeNivelDrawer.categorias);
      expect(c.pasoActual!.titulo, kNombreTienda);
      expect(c.pasoActual!.categorias.length, 2);
      expect(
        c.puedeVolverAtras,
        isFalse,
        reason: 'la raíz no tiene a dónde volver, se cierra',
      );
    });

    test('tocar "Tienda" sin nada dentro no abre nada', () async {
      final _GatewayFake g = _GatewayFake(
        categorias: <HomeCategoria>[_cat(1, 'Combustibles', especial: true)],
      );
      final HomeController c = HomeController(gateway: g);
      await c.cargar(_ctx);

      c.abrirTienda();

      expect(c.drawerAbierto, isFalse);
    });

    test(
      'una especial CON subcategorías abre el nivel de subcategorías',
      () async {
        final _GatewayFake g = _GatewayFake(
          categorias: <HomeCategoria>[
            _cat(1, 'Servicios', especial: true, subcategorias: 2),
          ],
          subcategorias: <HomeSubcategoria>[
            const HomeSubcategoria(id: 10, nombre: 'Corte', totalProductos: 3),
            const HomeSubcategoria(id: 11, nombre: 'Tinte', totalProductos: 1),
          ],
        );
        final HomeController c = HomeController(gateway: g);
        await c.cargar(_ctx);

        await c.abrirEspecial(c.especiales.single);

        expect(c.pasoActual!.nivel, HomeNivelDrawer.subcategorias);
        expect(c.subcategorias.length, 2);
        expect(c.subcategorias.first.nombre, 'Corte');
        expect(g.ultimosIdsSubcategorias, <int>[1]);
      },
    );

    test('una especial SIN subcategorías va directo a productos', () async {
      final _GatewayFake g = _GatewayFake(
        categorias: <HomeCategoria>[
          _cat(1, 'Combustibles', especial: true, productos: 4),
        ],
        productos: <HomeProducto>[_prod(1, 'Especial 95')],
      );
      final HomeController c = HomeController(gateway: g);
      await c.cargar(_ctx);

      await c.abrirEspecial(c.especiales.single);

      expect(c.pasoActual!.nivel, HomeNivelDrawer.productos);
      expect(c.productosNivel.single.nombre, 'Especial 95');
      expect(g.llamadasSubcategorias, 0, reason: 'no hay nada que pedir');
    });
  });

  group('drawer · navegación', () {
    Future<HomeController> montar(_GatewayFake g) async {
      final HomeController c = HomeController(gateway: g);
      await c.cargar(_ctx);
      return c;
    }

    _GatewayFake gatewayCompleto() => _GatewayFake(
      categorias: <HomeCategoria>[
        _cat(1, 'Combustibles', especial: true, productos: 2),
        _cat(2, 'Bebidas', productos: 5, subcategorias: 2),
        _cat(3, 'Comida', productos: 3),
      ],
      subcategorias: <HomeSubcategoria>[
        const HomeSubcategoria(id: 20, nombre: 'Gaseosas', totalProductos: 2),
        const HomeSubcategoria(id: 21, nombre: 'Cervezas', totalProductos: 3),
      ],
      productos: <HomeProducto>[
        _prod(100, 'Cola', sub: 20),
        _prod(101, 'Malta', sub: 20),
        _prod(102, 'Cerveza', sub: 21),
        _prod(103, 'Sin subcategoria'),
      ],
    );

    test(
      'categoría con subcategorías empuja un nivel y atrás vuelve',
      () async {
        final HomeController c = await montar(gatewayCompleto());

        c.abrirTienda();
        await c.abrirCategoria(
          c.pasoActual!.categorias.firstWhere(
            (HomeCategoria e) => e.nombre == 'Bebidas',
          ),
        );

        expect(c.pila.length, 2);
        expect(c.pasoActual!.nivel, HomeNivelDrawer.subcategorias);
        expect(c.puedeVolverAtras, isTrue);
        expect(c.migajas, <String>[kNombreTienda, 'Bebidas']);

        final bool sigueAbierto = c.volverNivel();

        expect(sigueAbierto, isTrue);
        expect(c.pila.length, 1);
        expect(c.pasoActual!.nivel, HomeNivelDrawer.categorias);
      },
    );

    test('atrás desde la raíz cierra el drawer y devuelve false', () async {
      final HomeController c = await montar(gatewayCompleto());
      c.abrirTienda();

      final bool sigueAbierto = c.volverNivel();

      expect(sigueAbierto, isFalse);
      expect(c.drawerAbierto, isFalse);
    });

    test('atrás sin drawer no hace nada', () async {
      final HomeController c = await montar(gatewayCompleto());

      expect(c.volverNivel(), isFalse);
      expect(c.drawerAbierto, isFalse);
    });

    test(
      'tocar una subcategoría filtra sus productos y no sale del drawer',
      () async {
        final HomeController c = await montar(gatewayCompleto());

        c.abrirTienda();
        await c.abrirCategoria(
          c.pasoActual!.categorias.firstWhere(
            (HomeCategoria e) => e.nombre == 'Bebidas',
          ),
        );
        // Las subcategorías vienen ordenadas por nombre, así que se elige por
        // nombre y no por posición.
        await c.abrirSubcategoria(
          c.subcategorias.firstWhere(
            (HomeSubcategoria s) => s.nombre == 'Gaseosas',
          ),
        );

        expect(c.pasoActual!.nivel, HomeNivelDrawer.productos);
        expect(c.pila.length, 3);
        expect(c.migajas, <String>[kNombreTienda, 'Bebidas', 'Gaseosas']);
        expect(c.productosNivel.map((HomeProducto p) => p.nombre), <String>[
          'Cola',
          'Malta',
        ]);
      },
    );

    test(
      'volverARaiz conserva las subcategorías cuando la raíz es una especial',
      () async {
        // Regresión del bug real: al «Seguir añadiendo» desde los productos de una
        // subcategoría, el nivel de subcategorías se quedaba vacío y pintaba
        // «esta categoría no tiene subcategorías».
        final HomeController c = await montar(
          _GatewayFake(
            categorias: <HomeCategoria>[
              _cat(
                2,
                'Bebidas',
                especial: true,
                productos: 5,
                subcategorias: 2,
              ),
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
                totalProductos: 3,
              ),
            ],
            productos: <HomeProducto>[
              _prod(100, 'Cola', sub: 20),
              _prod(101, 'Malta', sub: 20),
            ],
          ),
        );

        await c.abrirEspecial(c.especiales.single);
        expect(c.pasoActual!.nivel, HomeNivelDrawer.subcategorias);
        await c.abrirSubcategoria(
          c.subcategorias.firstWhere(
            (HomeSubcategoria s) => s.nombre == 'Gaseosas',
          ),
        );
        expect(c.pila.length, 2);
        expect(c.pasoActual!.nivel, HomeNivelDrawer.productos);

        c.volverARaiz();

        expect(c.pila.length, 1);
        expect(c.pasoActual!.nivel, HomeNivelDrawer.subcategorias);
        expect(
          c.subcategorias.map((HomeSubcategoria s) => s.nombre),
          <String>['Cervezas', 'Gaseosas'],
          reason: 'la lista ya cargada no se puede tirar al volver a la raíz',
        );
      },
    );

    test('volverARaiz desde productos de Tienda vuelve a categorías', () async {
      final HomeController c = await montar(gatewayCompleto());

      c.abrirTienda();
      await c.abrirCategoria(
        c.pasoActual!.categorias.firstWhere(
          (HomeCategoria e) => e.nombre == 'Comida',
        ),
      );
      expect(c.pila.length, 2);
      expect(c.pasoActual!.nivel, HomeNivelDrawer.productos);

      c.volverARaiz();

      expect(c.pila.length, 1);
      expect(c.pasoActual!.nivel, HomeNivelDrawer.categorias);
    });

    test('el filtro por subcategoría usa TODO el grupo de ids', () async {
      // Subcategoría colapsada: ids 20 y 22 son la misma "Gaseosas".
      final _GatewayFake g = _GatewayFake(
        categorias: <HomeCategoria>[
          _cat(2, 'Bebidas', productos: 3, subcategorias: 2),
        ],
        subcategorias: <HomeSubcategoria>[
          const HomeSubcategoria(id: 20, nombre: 'Gaseosas'),
          const HomeSubcategoria(id: 22, nombre: 'gaseosas'),
        ],
        productos: <HomeProducto>[
          _prod(1, 'Cola', sub: 20),
          _prod(2, 'Malta', sub: 22),
          _prod(3, 'Cerveza', sub: 21),
        ],
      );
      final HomeController c = await montar(g);

      c.abrirTienda();
      await c.abrirCategoria(c.pasoActual!.categorias.single);
      final HomeSubcategoria gaseosas = c.subcategorias.single;
      await c.abrirSubcategoria(gaseosas);

      expect(gaseosas.idsConsulta, <int>[20, 22]);
      expect(
        c.productosNivel.map((HomeProducto p) => p.nombre),
        <String>['Cola', 'Malta'],
        reason: 'un producto de la subcategoría 22 también es de "Gaseosas"',
      );
    });

    test(
      '"ver todos" de la categoría lleva a sus productos sin subcategoría',
      () async {
        final HomeController c = await montar(gatewayCompleto());

        c.abrirTienda();
        final HomeCategoria bebidas = c.pasoActual!.categorias.firstWhere(
          (HomeCategoria e) => e.nombre == 'Bebidas',
        );
        await c.abrirCategoria(bebidas);
        await c.abrirProductosDeCategoria(bebidas);

        expect(c.pasoActual!.nivel, HomeNivelDrawer.productos);
        expect(c.pasoActual!.subcategoria, isNull);
        expect(c.productosNivel.length, 4, reason: 'sin filtro: todos');
      },
    );

    test('una categoría sin subcategorías va directo a productos', () async {
      final HomeController c = await montar(gatewayCompleto());

      c.abrirTienda();
      await c.abrirCategoria(
        c.pasoActual!.categorias.firstWhere(
          (HomeCategoria e) => e.nombre == 'Comida',
        ),
      );

      expect(
        c.pila.length,
        2,
        reason: 'raíz + productos: no hay nivel intermedio',
      );
      expect(c.pasoActual!.nivel, HomeNivelDrawer.productos);
    });

    test('los productos salen con los disponibles primero', () async {
      final _GatewayFake g = _GatewayFake(
        categorias: <HomeCategoria>[_cat(1, 'Comida', productos: 3)],
        productos: <HomeProducto>[
          _prod(1, 'Zeta agotado', stock: false),
          _prod(2, 'Beta disponible'),
          _prod(3, 'Alfa agotado', stock: false),
        ],
      );
      final HomeController c = await montar(g);

      await c.abrirEspecial(_cat(1, 'Comida'));
      await c.abrirCategoria(c.todasLasCategorias.single);
      expect(
        c.productosNivel.map((HomeProducto p) => p.nombre).toList(),
        <String>['Beta disponible', 'Alfa agotado', 'Zeta agotado'],
      );
    });

    test('pide productos a TODAS las categorías del grupo colapsado', () async {
      final _GatewayFake g = _GatewayFake(
        categorias: <HomeCategoria>[
          _cat(1, 'Alimentos', productos: 3, grupo: <int>[1, 2]),
        ],
        productos: <HomeProducto>[_prod(1, 'Arroz')],
      );
      final HomeController c = await montar(g);

      await c.abrirEspecial(
        c.especiales.isEmpty ? c.categoriasTienda.single : c.especiales.single,
      );

      expect(g.ultimosIdsProductos, <int>[1, 2]);
    });

    test('cerrar deja todo limpio', () async {
      final HomeController c = await montar(gatewayCompleto());

      c.abrirTienda();
      await c.abrirCategoria(c.pasoActual!.categorias.first);
      c.cerrarDrawer();

      expect(c.drawerAbierto, isFalse);
      expect(c.pila, isEmpty);
      expect(c.migajas, isEmpty);
      expect(c.subcategorias, isEmpty);
      expect(c.productosNivel, isEmpty);
      expect(c.cargandoNivel, isFalse);
    });
  });

  group('drawer · errores', () {
    test(
      'si fallan las subcategorías, el nivel lo dice y no queda cargando',
      () async {
        final _GatewayFake g = _GatewayFake(
          categorias: <HomeCategoria>[_cat(1, 'Bebidas', subcategorias: 1)],
        )..fallaSubcategorias = Exception('sin red');
        final HomeController c = HomeController(gateway: g);
        await c.cargar(_ctx);

        c.abrirTienda();
        await c.abrirCategoria(c.pasoActual!.categorias.single);

        expect(c.cargandoNivel, isFalse);
        expect(c.errorNivel, isNotNull);
        expect(c.subcategorias, isEmpty);
      },
    );

    test(
      'si fallan los productos, el nivel lo dice y no queda cargando',
      () async {
        final _GatewayFake g = _GatewayFake(
          categorias: <HomeCategoria>[_cat(1, 'Comida')],
        )..fallaProductos = Exception('sin red');
        final HomeController c = HomeController(gateway: g);
        await c.cargar(_ctx);

        await c.abrirEspecial(c.categoriasTienda.single);

        expect(c.cargandoNivel, isFalse);
        expect(c.errorNivel, isNotNull);
      },
    );

    test('reintentar vuelve a pedir el nivel actual', () async {
      final _GatewayFake g = _GatewayFake(
        categorias: <HomeCategoria>[_cat(1, 'Comida')],
        productos: <HomeProducto>[_prod(1, 'Arroz')],
      )..fallaProductos = Exception('sin red');
      final HomeController c = HomeController(gateway: g);
      await c.cargar(_ctx);
      await c.abrirEspecial(c.categoriasTienda.single);
      expect(c.errorNivel, isNotNull);

      g.fallaProductos = null;
      await c.reintentarNivel();

      expect(c.errorNivel, isNull);
      expect(c.productosNivel.single.nombre, 'Arroz');
    });
  });

  group('notificaciones', () {
    test('avisa a sus oyentes al cargar y al navegar', () async {
      final _GatewayFake g = _GatewayFake(
        categorias: <HomeCategoria>[_cat(1, 'Comida')],
      );
      final HomeController c = HomeController(gateway: g);
      int avisos = 0;
      c.addListener(() => avisos++);

      await c.cargar(_ctx);
      final int trasCargar = avisos;
      expect(trasCargar, greaterThan(0));
      expect(trasCargar, lessThanOrEqualTo(2));

      c.abrirTienda();
      expect(avisos, greaterThan(trasCargar));
    });

    test('tras dispose no avisa (evita el "setState after dispose")', () async {
      final _GatewayFake g = _GatewayFake(
        categorias: <HomeCategoria>[_cat(1, 'Comida')],
      );
      final HomeController c = HomeController(gateway: g);
      await c.cargar(_ctx);

      c.dispose();

      expect(() => c.abrirTienda(), returnsNormally);
    });
  });
}
