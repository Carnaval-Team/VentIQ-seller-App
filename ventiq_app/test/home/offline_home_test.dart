// Fallback offline del Home nuevo.
//
// Estos tests son la red de seguridad del hueco que tenía el Home: sin red, el
// catálogo salía del snapshot pero `subcategorias()` y `productos()` fallaban y
// el drawer se quedaba vacío. Aquí se prueba el mapeo desde el cache local con
// datos de ejemplo (sin Supabase y sin `sqflite`) y la coherencia del filtro por
// subcategoría que hace `HomeController`.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventiq_app/models/home_catalogo.dart';
import 'package:ventiq_app/services/home_catalog_service.dart';
import 'package:ventiq_app/services/home_offline_mapper.dart';

/// Fila de producto cacheado con la misma forma que guarda el sync.
///
/// `conDetalles: false` simula una fila antigua o de un sync parcial, que solo
/// tiene los campos del listado (sin ids reales de subcategoría).
Map<String, dynamic> _producto({
  required int id,
  required String nombre,
  String? subcategoria,
  int? idSubcategoria,
  String categoria = 'Bebidas',
  int idCategoria = 10,
  double? precio,
  double? cantidad,
  List<double>? inventario,
  bool esElaborado = false,
  bool esServicio = false,
  bool conDetalles = true,
  String? foto,
  String? sku,
  String? descripcion,
  double? precioDetalle,
}) {
  final Map<String, dynamic> fila = <String, dynamic>{
    'id': id,
    'denominacion': nombre,
    'categoria': categoria,
  };
  if (subcategoria != null) fila['subcategoria'] = subcategoria;
  if (idSubcategoria != null) fila['id_subcategoria'] = idSubcategoria;
  if (precio != null) fila['precio'] = precio;
  if (cantidad != null) fila['cantidad'] = cantidad;
  if (foto != null) fila['foto'] = foto;
  if (sku != null) fila['sku'] = sku;
  if (descripcion != null) fila['descripcion'] = descripcion;
  if (esElaborado) fila['es_elaborado'] = true;
  if (esServicio) fila['es_servicio'] = true;

  if (!conDetalles) return fila;

  fila['detalles_completos'] = <String, dynamic>{
    'producto': <String, dynamic>{
      'id': id,
      'denominacion': nombre,
      'sku': sku,
      'descripcion': descripcion,
      'es_elaborado': esElaborado || esServicio,
      'es_servicio': esServicio,
      'imagen': foto,
      'categoria': <String, dynamic>{
        'id': idCategoria,
        'denominacion': categoria,
      },
      'subcategorias':
          subcategoria == null
              ? null
              : <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': idSubcategoria,
                  'denominacion': subcategoria,
                },
              ],
      'precio_actual': precioDetalle ?? precio,
      'multimedias':
          foto == null
              ? null
              : <Map<String, dynamic>>[
                <String, dynamic>{'url': foto},
              ],
    },
    'inventario':
        inventario == null
            ? const <Map<String, dynamic>>[]
            : inventario
                .map((double c) => <String, dynamic>{'cantidad_disponible': c})
                .toList(),
  };
  return fila;
}

Map<int, List<Map<String, dynamic>>> _cacheEjemplo() =>
    <int, List<Map<String, dynamic>>>{
      10: <Map<String, dynamic>>[
        _producto(
          id: 100,
          nombre: 'Jugo de Limón',
          subcategoria: 'Jugos',
          idSubcategoria: 42,
          categoria: 'Alimentos',
          idCategoria: 10,
          precio: 12.5,
          cantidad: 5,
          sku: 'SKU-100',
          descripcion: 'Jugo natural',
          foto: 'https://example.com/jugo.jpg',
        ),
        _producto(
          id: 101,
          nombre: 'Jugo de Naranja',
          subcategoria: 'Jugos',
          idSubcategoria: 42,
          categoria: 'Alimentos',
          idCategoria: 10,
          precio: 10,
          cantidad: 2,
        ),
        _producto(
          id: 102,
          nombre: 'Cerveza',
          subcategoria: 'Cervezas',
          idSubcategoria: 50,
          categoria: 'Alimentos',
          idCategoria: 10,
          precio: 3,
          cantidad: 0,
        ),
      ],
      20: <Map<String, dynamic>>[
        _producto(
          id: 103,
          nombre: 'Refresco',
          subcategoria: 'Refrescos',
          idSubcategoria: 60,
          categoria: 'Bebidas',
          idCategoria: 20,
          precio: 4,
          cantidad: 1,
        ),
      ],
    };

/// Doble de [HomeOfflineSource]: datos en memoria, sin SQLite ni prefs.
class _FuenteOfflineFake implements HomeOfflineSource {
  _FuenteOfflineFake({required this.cache, this.local = true});

  final Map<int, List<Map<String, dynamic>>> cache;

  /// Lo que devuelve `debeUsarDatosLocales`.
  bool local;

  /// Cuántas veces se pidió el cache (para comprobar que no se toca de más).
  int consultas = 0;
  List<int>? ultimasIds;

  @override
  Future<bool> debeUsarDatosLocales() async => local;

  @override
  Future<Map<int, List<Map<String, dynamic>>>> productosPorCategoria({
    List<int> idsCategorias = const <int>[],
  }) async {
    consultas++;
    ultimasIds = idsCategorias;
    if (idsCategorias.isEmpty) return cache;

    final Map<int, List<Map<String, dynamic>>> salida =
        <int, List<Map<String, dynamic>>>{};
    for (final int id in idsCategorias) {
      final List<Map<String, dynamic>>? filas = cache[id];
      if (filas != null) salida[id] = filas;
    }
    return salida;
  }
}

const HomeContexto _contexto = HomeContexto(idTienda: 174, idTpv: 3);

void main() {
  group('idOfflineDeSubcategoria', () {
    test('es determinista, negativo y no pisa el id de "Tienda" virtual', () {
      final int id = idOfflineDeSubcategoria('Jugos');

      expect(id, idOfflineDeSubcategoria('Jugos'));
      expect(id, isNegative);
      expect(id, isNot(kIdTiendaVirtual));
      expect(id, isNot(0));
    });

    test('distingue nombres distintos y junta sus variantes de acento', () {
      expect(
        idOfflineDeSubcategoria('Jugos'),
        isNot(idOfflineDeSubcategoria('Cervezas')),
      );
      expect(
        idOfflineDeSubcategoria('  Electrónica  '),
        idOfflineDeSubcategoria('electronica'),
      );
    });
  });

  group('mapearProductoOffline', () {
    test('mapea todos los campos del cache (con detalles_completos)', () {
      final HomeProducto p = mapearProductoOffline(
        _producto(
          id: 100,
          nombre: 'Jugo de Limón',
          subcategoria: 'Jugos',
          idSubcategoria: 42,
          categoria: 'Alimentos',
          idCategoria: 3,
          precio: 12.5,
          cantidad: 5,
          sku: 'SKU-100',
          descripcion: 'Jugo natural',
          foto: 'https://example.com/jugo.jpg',
        ),
      );

      expect(p.id, 100);
      expect(p.nombre, 'Jugo de Limón');
      expect(p.sku, 'SKU-100');
      expect(p.descripcion, 'Jugo natural');
      expect(p.imagen, 'https://example.com/jugo.jpg');
      expect(p.precio, 12.5);
      expect(p.stock, 5);
      expect(p.tieneStock, isTrue);
      expect(p.esElaborado, isFalse);
      expect(p.esServicio, isFalse);
      expect(p.idCategoria, 3);
      expect(p.categoriaNombre, 'Alimentos');
      expect(p.idSubcategoria, 42);
      expect(p.subcategoriaNombre, 'Jugos');
      expect(p.disponible, isTrue);
    });

    test(
      'sin precio ni cantidad en la fila cae al detalle y al inventario',
      () {
        final HomeProducto p = mapearProductoOffline(
          _producto(
            id: 101,
            nombre: 'Jugo de Naranja',
            subcategoria: 'Jugos',
            precioDetalle: 15.25,
            inventario: <double>[2, 3],
          ),
        );

        expect(p.precio, 15.25);
        expect(
          p.stock,
          5,
          reason: 'suma de cantidad_disponible del inventario',
        );
        expect(p.tieneStock, isTrue);
      },
    );

    test('tolera una fila mínima sin reventar', () {
      final HomeProducto p = mapearProductoOffline(<String, dynamic>{
        'id': 7,
        'denominacion': 'Suelto',
      });

      expect(p.id, 7);
      expect(p.nombre, 'Suelto');
      expect(p.subcategoriaNombre, kSubcategoriaOfflineSinNombre);
      expect(p.idSubcategoria, idOfflineDeSubcategoria('General'));
      expect(p.precio, 0);
      expect(p.stock, 0);
      expect(p.disponible, isFalse);
      expect(p.imagen, isNull);
    });

    test('acepta numeric como texto (PostgREST/SQLite)', () {
      final HomeProducto p = mapearProductoOffline(<String, dynamic>{
        'id': '9',
        'denominacion': 'Texto',
        'precio': '12.50',
        'cantidad': '3',
        'subcategoria': 'Refrescos',
        'id_subcategoria': '60',
      });

      expect(p.id, 9);
      expect(p.precio, 12.5);
      expect(p.stock, 3);
      expect(p.tieneStock, isTrue);
      expect(p.idSubcategoria, 60);
    });

    test('lee las banderas de elaborado y servicio', () {
      final HomeProducto elaborado = mapearProductoOffline(
        _producto(id: 1, nombre: 'Pizza', esElaborado: true, cantidad: 0),
      );
      final HomeProducto servicio = mapearProductoOffline(
        _producto(
          id: 2,
          nombre: 'Corte de pelo',
          esServicio: true,
          cantidad: 0,
        ),
      );

      expect(elaborado.esElaborado, isTrue);
      expect(elaborado.esServicio, isFalse);
      expect(servicio.esServicio, isTrue);
      expect(
        servicio.disponible,
        isTrue,
        reason: 'un servicio se vende sin stock',
      );
    });

    test('la imagen sale de multimedias si no hay foto suelta', () {
      final Map<String, dynamic> fila = _producto(
        id: 3,
        nombre: 'Sin foto directa',
        foto: 'https://example.com/media.jpg',
      );
      fila.remove('foto');
      (fila['detalles_completos']['producto'] as Map<String, dynamic>).remove(
        'imagen',
      );

      expect(
        mapearProductoOffline(fila).imagen,
        'https://example.com/media.jpg',
      );
    });
  });

  group('construirSubcategoriasOffline', () {
    test('agrupa homónimos y suma sus productos', () {
      final List<HomeSubcategoria> subs =
          construirSubcategoriasOffline(<Map<String, dynamic>>[
            _producto(
              id: 1,
              nombre: 'A',
              subcategoria: 'Gaseosas',
              idSubcategoria: 5,
            ),
            _producto(
              id: 2,
              nombre: 'B',
              subcategoria: 'gaseosas',
              idSubcategoria: 6,
            ),
            _producto(
              id: 3,
              nombre: 'C',
              subcategoria: 'Cervezas',
              idSubcategoria: 7,
            ),
          ]);

      expect(subs.length, 2, reason: 'gaseosas/gaseosas son una entrada');
      final HomeSubcategoria gaseosas = subs.firstWhere(
        (HomeSubcategoria s) => claveNombre(s.nombre) == 'gaseosas',
      );
      expect(gaseosas.totalProductos, 2);
      expect(gaseosas.idsConsulta, containsAll(<int>[5, 6]));
    });

    test('cuenta productos distintos: una fila repetida no suma dos veces', () {
      final Map<String, dynamic> fila = _producto(
        id: 1,
        nombre: 'A',
        subcategoria: 'Jugos',
        idSubcategoria: 42,
      );

      final List<HomeSubcategoria> subs = construirSubcategoriasOffline(
        <Map<String, dynamic>>[fila, fila],
      );

      expect(subs.single.totalProductos, 1);
    });

    test('sin ids reales usa ids sintéticos estables', () {
      final List<HomeSubcategoria> subs =
          construirSubcategoriasOffline(<Map<String, dynamic>>[
            _producto(
              id: 1,
              nombre: 'A',
              subcategoria: 'Jugos',
              conDetalles: false,
            ),
            _producto(
              id: 2,
              nombre: 'B',
              subcategoria: 'Jugos',
              conDetalles: false,
            ),
          ]);

      expect(subs.single.idsConsulta, <int>[idOfflineDeSubcategoria('Jugos')]);
      expect(subs.single.totalProductos, 2);
    });

    test('acepta el mapa vacío sin reventar', () {
      expect(
        construirSubcategoriasOffline(const <Map<String, dynamic>>[]),
        isEmpty,
      );
    });
  });

  group('productosOfflineDesdeCache', () {
    test('filtra por las categorías pedidas', () {
      final List<HomeProducto> productos = productosOfflineDesdeCache(
        _cacheEjemplo(),
        idsCategorias: <int>[10],
      );

      expect(productos.map((HomeProducto p) => p.id).toSet(), <int>{
        100,
        101,
        102,
      });
    });

    test('sin ids devuelve todo el cache (búsqueda global)', () {
      final List<HomeProducto> productos = productosOfflineDesdeCache(
        _cacheEjemplo(),
      );

      expect(productos.map((HomeProducto p) => p.id).toSet(), <int>{
        100,
        101,
        102,
        103,
      });
    });

    test('une por id si el producto está en dos claves de categoría', () {
      final Map<String, dynamic> fila = _producto(
        id: 100,
        nombre: 'Jugo de Limón',
        subcategoria: 'Jugos',
      );
      final List<HomeProducto> productos = productosOfflineDesdeCache(
        <int, List<Map<String, dynamic>>>{
          10: <Map<String, dynamic>>[fila],
          11: <Map<String, dynamic>>[fila],
        },
      );

      expect(productos.length, 1);
    });

    test('busca sin acentos ni mayúsculas', () {
      final Map<int, List<Map<String, dynamic>>> cache = _cacheEjemplo();

      expect(
        productosOfflineDesdeCache(
          cache,
          texto: 'limon',
        ).map((HomeProducto p) => p.id),
        <int>[100],
      );
      expect(
        productosOfflineDesdeCache(
          cache,
          texto: 'JUGOS',
        ).map((HomeProducto p) => p.id).toSet(),
        <int>{100, 101},
      );
    });

    test('con soloDisponibles descarta los agotados que no son servicio', () {
      final List<HomeProducto> productos = productosOfflineDesdeCache(
        _cacheEjemplo(),
        idsCategorias: <int>[10],
        soloDisponibles: true,
      );

      expect(productos.map((HomeProducto p) => p.id), isNot(contains(102)));
      expect(
        productos.map((HomeProducto p) => p.id),
        containsAll(<int>[100, 101]),
      );
    });
  });

  group('coherencia con el filtro del drawer', () {
    test('cada subcategoría filtra exactamente sus productos', () {
      final Map<int, List<Map<String, dynamic>>> cache = _cacheEjemplo();
      final List<HomeSubcategoria> subs = subcategoriasOfflineDesdeCache(
        cache,
        idsCategorias: <int>[10],
      );
      final List<HomeProducto> productos = productosOfflineDesdeCache(
        cache,
        idsCategorias: <int>[10],
      );

      for (final HomeSubcategoria sub in subs) {
        final List<HomeProducto> filtrados =
            productos
                .where(
                  (HomeProducto p) =>
                      p.idSubcategoria != null &&
                      sub.idsConsulta.contains(p.idSubcategoria),
                )
                .toList();

        expect(
          filtrados.length,
          sub.totalProductos,
          reason: 'el contador del drawer debe cuadrar con la lista',
        );
        for (final HomeProducto p in filtrados) {
          expect(claveNombre(p.subcategoriaNombre!), claveNombre(sub.nombre));
        }
      }
    });

    test('si un producto no tiene id real, el sintético entra en el grupo', () {
      final Map<int, List<Map<String, dynamic>>> cache =
          <int, List<Map<String, dynamic>>>{
            10: <Map<String, dynamic>>[
              // Uno con id real y otro de un sync parcial sin id: el grupo los
              // tiene que cubrir a los dos.
              _producto(
                id: 1,
                nombre: 'A',
                subcategoria: 'Jugos',
                idSubcategoria: 42,
              ),
              _producto(
                id: 2,
                nombre: 'B',
                subcategoria: 'jugos',
                conDetalles: false,
              ),
            ],
          };

      final HomeSubcategoria sub =
          subcategoriasOfflineDesdeCache(
            cache,
            idsCategorias: <int>[10],
          ).single;
      final List<HomeProducto> productos = productosOfflineDesdeCache(
        cache,
        idsCategorias: <int>[10],
      );

      expect(sub.idsConsulta, contains(42));
      expect(sub.idsConsulta, contains(idOfflineDeSubcategoria('jugos')));
      expect(
        productos
            .where(
              (HomeProducto p) => sub.idsConsulta.contains(p.idSubcategoria),
            )
            .length,
        2,
      );
    });
  });

  group('HomeCatalogService · fallback offline', () {
    test('en modo offline cae al cache sin tocar la red', () async {
      final _FuenteOfflineFake fuente = _FuenteOfflineFake(
        cache: _cacheEjemplo(),
      );
      final HomeCatalogService servicio = HomeCatalogService(offline: fuente);

      final List<HomeSubcategoria> subs = await servicio.subcategorias(
        idsCategorias: <int>[10],
        contexto: _contexto,
      );
      final List<HomeProducto> productos = await servicio.productos(
        contexto: _contexto,
        idsCategorias: <int>[10],
      );

      expect(fuente.consultas, 2);
      expect(fuente.ultimasIds, <int>[10]);
      expect(
        subs.map((HomeSubcategoria s) => claveNombre(s.nombre)).toSet(),
        <String>{'jugos', 'cervezas'},
      );
      expect(productos.length, 3);
    });

    test('la subcategoría del offline navega hasta sus productos', () async {
      final HomeCatalogService servicio = HomeCatalogService(
        offline: _FuenteOfflineFake(cache: _cacheEjemplo()),
      );

      final List<HomeSubcategoria> subs = await servicio.subcategorias(
        idsCategorias: <int>[10],
        contexto: _contexto,
      );
      final HomeSubcategoria jugos = subs.firstWhere(
        (HomeSubcategoria s) => claveNombre(s.nombre) == 'jugos',
      );
      final List<HomeProducto> productos = await servicio.productos(
        contexto: _contexto,
        idsCategorias: <int>[10],
      );

      final List<HomeProducto> deJugos =
          productos
              .where(
                (HomeProducto p) =>
                    p.idSubcategoria != null &&
                    jugos.idsConsulta.contains(p.idSubcategoria),
              )
              .toList();

      expect(deJugos.map((HomeProducto p) => p.id).toSet(), <int>{100, 101});
    });

    test('la búsqueda global offline filtra el cache por texto', () async {
      final HomeCatalogService servicio = HomeCatalogService(
        offline: _FuenteOfflineFake(cache: _cacheEjemplo()),
      );

      final List<HomeProducto> encontrados = await servicio.productos(
        contexto: _contexto,
        texto: 'limon',
      );

      expect(encontrados.map((HomeProducto p) => p.id), <int>[100]);
    });

    test('sin cache devuelve listas vacías y no lanza', () async {
      final HomeCatalogService servicio = HomeCatalogService(
        offline: _FuenteOfflineFake(cache: <int, List<Map<String, dynamic>>>{}),
      );

      expect(
        await servicio.subcategorias(
          idsCategorias: <int>[10],
          contexto: _contexto,
        ),
        isEmpty,
      );
      expect(
        await servicio.productos(contexto: _contexto, idsCategorias: <int>[10]),
        isEmpty,
      );
      expect(
        await servicio.productos(contexto: _contexto, texto: 'jugo'),
        isEmpty,
      );
    });

    test(
      'si falla la red, usa el cache local en vez de propagar el error',
      () async {
        // Sin modo offline, el servicio intenta la red; en test no hay Supabase
        // inicializado, así que la RPC falla y el fallback tiene que salvar la
        // pantalla devolviendo lo cacheado.
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final HomeCatalogService servicio = HomeCatalogService(
          offline: _FuenteOfflineFake(cache: _cacheEjemplo(), local: false),
        );

        final List<HomeProducto> productos = await servicio.productos(
          contexto: _contexto,
          idsCategorias: <int>[10],
        );

        expect(productos.map((HomeProducto p) => p.id).toSet(), <int>{
          100,
          101,
          102,
        });
      },
    );

    test(
      'sin ids de categoría no consulta el cache de subcategorías',
      () async {
        final _FuenteOfflineFake fuente = _FuenteOfflineFake(
          cache: _cacheEjemplo(),
        );
        final HomeCatalogService servicio = HomeCatalogService(offline: fuente);

        expect(
          await servicio.subcategorias(
            idsCategorias: const <int>[],
            contexto: _contexto,
          ),
          isEmpty,
        );
        expect(fuente.consultas, 0);
      },
    );
  });
}
