import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/models/home_catalogo.dart';
import 'package:ventiq_app/models/product.dart';

HomeCategoria _cat(
  int id,
  String nombre, {
  bool especial = false,
  int orden = 0,
  int productos = 0,
  int subcategorias = 0,
  List<int> grupo = const <int>[],
  String? imagen,
}) {
  return HomeCategoria(
    id: id,
    nombre: nombre,
    especial: especial,
    ordenHome: orden,
    totalProductos: productos,
    totalSubcategorias: subcategorias,
    grupoIds: grupo,
    imagen: imagen,
  );
}

void main() {
  group('HomeCatalogo.agrupar', () {
    test('sin especiales, todo cae en Tienda', () {
      final HomeCatalogo c = HomeCatalogo.agrupar(<HomeCategoria>[
        _cat(1, 'Comida', productos: 10),
        _cat(2, 'Recreación', productos: 4),
      ]);

      expect(c.especiales, isEmpty);
      expect(c.tienda.map((HomeCategoria e) => e.nombre), <String>[
        'Comida',
        'Recreación',
      ]);
      expect(c.mostrarTarjetaTienda, isTrue);
      expect(c.totalCategorias, 2);
    });

    test('si todo es especial, la tarjeta Tienda no se muestra', () {
      final HomeCatalogo c = HomeCatalogo.agrupar(<HomeCategoria>[
        _cat(1, 'Combustibles', especial: true),
        _cat(2, 'Servicios', especial: true),
      ]);

      expect(c.especiales.length, 2);
      expect(c.tienda, isEmpty);
      expect(
        c.mostrarTarjetaTienda,
        isFalse,
        reason: 'una tarjeta "Tienda" vacía es un toque muerto',
      );
    });

    test('el caso del enunciado: 2 especiales + 2 dentro de Tienda', () {
      final HomeCatalogo c = HomeCatalogo.agrupar(<HomeCategoria>[
        _cat(1, 'Combustibles', especial: true),
        _cat(2, 'Servicios', especial: true),
        _cat(3, 'Comida', productos: 20),
        _cat(4, 'Recreacion', productos: 5),
      ]);

      expect(c.especiales.map((HomeCategoria e) => e.nombre), <String>[
        'Combustibles',
        'Servicios',
      ]);
      expect(c.tienda.map((HomeCategoria e) => e.nombre), <String>[
        'Comida',
        'Recreacion',
      ]);
    });

    test('las especiales se ordenan por ordenHome y desempatan por nombre', () {
      final HomeCatalogo c = HomeCatalogo.agrupar(<HomeCategoria>[
        _cat(1, 'Zeta', especial: true, orden: 5),
        _cat(2, 'Beta', especial: true, orden: 1),
        _cat(3, 'Alfa', especial: true, orden: 1),
        _cat(4, 'Omega', especial: true),
      ]);

      // `orden 0` = sin orden manual, y va antes que cualquier orden puesto.
      expect(c.especiales.map((HomeCategoria e) => e.nombre), <String>[
        'Omega',
        'Alfa',
        'Beta',
        'Zeta',
      ]);
    });

    test('la tarjeta virtual "Tienda" colada en la lista se ignora', () {
      final HomeCatalogo c = HomeCatalogo.agrupar(<HomeCategoria>[
        _cat(kIdTiendaVirtual, kNombreTienda),
        _cat(1, 'Comida'),
      ]);

      expect(c.tienda.map((HomeCategoria e) => e.nombre), <String>['Comida']);
    });
  });

  group('HomeCatalogo.agrupar · colapso de homónimos', () {
    test('une los homónimos y suma sus contadores', () {
      final HomeCatalogo c = HomeCatalogo.agrupar(<HomeCategoria>[
        _cat(189, 'Alimentos', productos: 43, subcategorias: 1),
        _cat(191, 'Alimentos', productos: 12, subcategorias: 2),
        _cat(192, 'Alimentos', productos: 5, subcategorias: 3),
      ]);

      expect(c.tienda.length, 1, reason: 'tres "Alimentos" son una tarjeta');
      final HomeCategoria unica = c.tienda.single;
      expect(unica.id, 189, reason: 'canónica = min(id)');
      expect(unica.totalProductos, 60);
      expect(unica.totalSubcategorias, 6);
      expect(unica.miembros, 3);
      expect(unica.grupoIds, <int>[189, 191, 192]);
    });

    test('si una copia es especial, el grupo entero lo es', () {
      final HomeCatalogo c = HomeCatalogo.agrupar(<HomeCategoria>[
        _cat(10, 'Combustibles'),
        _cat(11, 'Combustibles', especial: true, orden: 3),
      ]);

      expect(c.tienda, isEmpty);
      expect(c.especiales.single.especial, isTrue);
      expect(
        c.especiales.single.ordenHome,
        3,
        reason: 'hereda el orden que eligió el gerente',
      );
    });

    test('el grupo hereda la primera imagen disponible', () {
      final HomeCatalogo c = HomeCatalogo.agrupar(<HomeCategoria>[
        _cat(10, 'Bebidas'),
        _cat(11, 'Bebidas', imagen: 'https://x/y.png'),
      ]);

      expect(c.tienda.single.imagen, 'https://x/y.png');
    });

    test('no une plurales ni palabras parecidas', () {
      // En la tienda 174 son dos categorías reales (53 y 25 productos).
      final HomeCatalogo c = HomeCatalogo.agrupar(<HomeCategoria>[
        _cat(1, 'Confituras', productos: 53),
        _cat(2, 'Confitura', productos: 25),
      ]);

      expect(c.tienda.length, 2);
    });

    test('el colapso es idempotente: volver a agrupar no cambia nada', () {
      final HomeCatalogo primera = HomeCatalogo.agrupar(<HomeCategoria>[
        _cat(189, 'Alimentos', productos: 43),
        _cat(191, 'Alimentos', productos: 12),
        _cat(2, 'Bebidas', productos: 7),
      ]);

      final HomeCatalogo segunda = HomeCatalogo.agrupar(<HomeCategoria>[
        ...primera.especiales,
        ...primera.tienda,
      ]);

      expect(
        segunda.tienda.map((HomeCategoria e) => e.nombre),
        primera.tienda.map((HomeCategoria e) => e.nombre),
      );
      expect(segunda.tienda.first.totalProductos, 55);
      expect(segunda.tienda.first.grupoIds, <int>[189, 191]);
    });

    test('una categoría sin grupo declarado se autoasigna una', () {
      final HomeCatalogo c = HomeCatalogo.agrupar(<HomeCategoria>[
        _cat(77, 'Sola'),
      ]);

      expect(c.tienda.single.idsConsulta, <int>[77]);
    });
  });

  group('claveNombre', () {
    test('ignora acentos, mayúsculas y espacios de más', () {
      expect(claveNombre('  Electrónica  '), claveNombre('electronica'));
      expect(claveNombre('Hogar   Y  Oficinas'), 'hogar y oficinas');
    });

    test('distingue plural de singular', () {
      expect(claveNombre('Confituras'), isNot(claveNombre('Confitura')));
    });
  });

  group('HomeSubcategoria.agruparPorNombre', () {
    test('une homónimas y suma productos', () {
      final List<HomeSubcategoria> r = HomeSubcategoria.agruparPorNombre(
        <HomeSubcategoria>[
          const HomeSubcategoria(id: 1, nombre: 'Gaseosas', totalProductos: 3),
          const HomeSubcategoria(id: 2, nombre: 'gaseosas', totalProductos: 4),
          const HomeSubcategoria(id: 3, nombre: 'Cervezas', totalProductos: 1),
        ],
      );

      expect(r.length, 2);
      expect(r.first.nombre.toLowerCase(), 'cervezas');
      final HomeSubcategoria gaseosas = r.firstWhere(
        (HomeSubcategoria s) => s.nombre.toLowerCase() == 'gaseosas',
      );
      expect(gaseosas.totalProductos, 7);
      expect(gaseosas.grupoIds, <int>[1, 2]);
      expect(gaseosas.idsConsulta, <int>[1, 2]);
    });

    test('con una sola, deja el id y se autoasigna el grupo', () {
      final List<HomeSubcategoria> r = HomeSubcategoria.agruparPorNombre(
        <HomeSubcategoria>[
          const HomeSubcategoria(id: 9, nombre: 'Única', totalProductos: 2),
        ],
      );

      expect(r.single.idsConsulta, <int>[9]);
    });

    test('lista vacía no revienta', () {
      expect(
        HomeSubcategoria.agruparPorNombre(const <HomeSubcategoria>[]),
        isEmpty,
      );
    });
  });

  group('serialización', () {
    test('HomeCategoria va y vuelve sin perder nada', () {
      final HomeCategoria original = _cat(
        189,
        'Alimentos',
        especial: true,
        orden: 2,
        productos: 60,
        subcategorias: 6,
        grupo: <int>[189, 191, 192],
        imagen: 'https://x/y.png',
      );

      final HomeCategoria vuelta = HomeCategoria.fromJson(original.toJson());

      expect(vuelta.id, original.id);
      expect(vuelta.nombre, original.nombre);
      expect(vuelta.especial, isTrue);
      expect(vuelta.ordenHome, 2);
      expect(vuelta.totalProductos, 60);
      expect(vuelta.grupoIds, <int>[189, 191, 192]);
      expect(vuelta.imagen, 'https://x/y.png');
    });

    test('el catálogo completo va y vuelve', () {
      final HomeCatalogo original = HomeCatalogo.agrupar(<HomeCategoria>[
        _cat(1, 'Combustibles', especial: true),
        _cat(2, 'Comida', productos: 9),
      ]);

      final HomeCatalogo vuelto = HomeCatalogo.fromJson(original.toJson());

      expect(vuelto.especiales.single.nombre, 'Combustibles');
      expect(vuelto.tienda.single.nombre, 'Comida');
      expect(vuelto.mostrarTarjetaTienda, isTrue);
    });
  });

  group('fromJson tolerante con lo que manda PostgREST', () {
    test('acepta numeric como texto', () {
      final HomeCategoria c = HomeCategoria.fromJson(<String, dynamic>{
        'id': '189',
        'nombre': 'Alimentos',
        'total_productos': '43',
        'orden_home': '2',
        'grupo_ids': <dynamic>['189', '191'],
      });

      expect(c.id, 189);
      expect(c.totalProductos, 43);
      expect(c.ordenHome, 2);
      expect(c.grupoIds, <int>[189, 191]);
    });

    test('sin grupo_ids, idsConsulta cae al propio id', () {
      final HomeCategoria c = HomeCategoria.fromJson(<String, dynamic>{
        'id': 5,
        'nombre': 'Sola',
      });

      expect(c.idsConsulta, <int>[5]);
    });

    test('sin nombre no revienta', () {
      final HomeCategoria c = HomeCategoria.fromJson(<String, dynamic>{
        'id': 1,
      });
      expect(c.nombre, 'Sin nombre');
    });

    test('un producto lee metadata para elaborado y servicio', () {
      final HomeProducto p = HomeProducto.fromJson(<String, dynamic>{
        'id_producto': 7,
        'denominacion': 'Pizza',
        'precio_venta': '150.50',
        'stock_disponible': 3,
        'tiene_stock': true,
        'id_subcategoria': '42',
        'metadata': <String, dynamic>{
          'es_elaborado': true,
          'es_servicio': false,
        },
      });

      expect(p.id, 7);
      expect(p.precio, 150.50);
      expect(p.stock, 3);
      expect(p.tieneStock, isTrue);
      expect(p.esElaborado, isTrue);
      expect(p.esServicio, isFalse);
      expect(p.idSubcategoria, 42);
      expect(p.disponible, isTrue);
    });

    test('un servicio está disponible aunque no tenga stock', () {
      final HomeProducto p = HomeProducto.fromJson(<String, dynamic>{
        'id_producto': 8,
        'denominacion': 'Corte de pelo',
        'tiene_stock': false,
        'metadata': <String, dynamic>{'es_servicio': true},
      });

      expect(p.disponible, isTrue);
    });

    test('un producto agotado no está disponible', () {
      final HomeProducto p = HomeProducto.fromJson(<String, dynamic>{
        'id_producto': 9,
        'denominacion': 'Agotado',
        'tiene_stock': false,
        'metadata': <String, dynamic>{},
      });

      expect(p.disponible, isFalse);
    });
  });

  test('HomeCategoria.tienda fabrica la tarjeta virtual', () {
    final HomeCategoria t = HomeCategoria.tienda(
      totalProductos: 100,
      totalSubcategorias: 10,
    );

    expect(t.esTiendaVirtual, isTrue);
    expect(t.nombre, kNombreTienda);
    expect(t.especial, isFalse);
    expect(t.totalProductos, 100);
  });

  test('HomeProducto.desdeProducto adapta un Product de la búsqueda', () {
    // La búsqueda global devuelve `Product`; la fila del Home usa
    // `HomeProducto`, así reutiliza el mismo `ProductoTile` y el mismo alta
    // rápida que el drawer.
    final Product producto = Product(
      id: 10808,
      denominacion: 'Jugo de Limón Concentrado',
      sku: 'SKU-10808',
      foto: 'https://example.com/jugo.jpg',
      precio: 12,
      cantidad: 5,
      esRefrigerado: false,
      esFragil: false,
      esPeligroso: false,
      esVendible: true,
      esComprable: true,
      esInventariable: true,
      esPorLotes: false,
      esElaborado: false,
      esServicio: false,
      categoria: 'Alimentos',
    );

    final HomeProducto p = HomeProducto.desdeProducto(producto);

    expect(p.id, 10808);
    expect(p.nombre, 'Jugo de Limón Concentrado');
    expect(p.sku, 'SKU-10808');
    expect(p.imagen, 'https://example.com/jugo.jpg');
    expect(p.precio, 12);
    expect(p.stock, 5);
    expect(p.tieneStock, isTrue);
    expect(p.disponible, isTrue);
    expect(p.categoriaNombre, 'Alimentos');
  });
}
