import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/services/home_catalog_service.dart';
import 'package:inventtia_flow/widgets/filtros_servicios_sheet.dart';

/// Contrato del feed del Home en lo que toca a la taxonomía de dos niveles
/// (migración `48_home_feed_categorias_subcategorias.sql`).
///
/// `itemsDesdeFeed` y `categoriasDesdeFeed` son los DOS únicos sitios donde se
/// interpreta el JSON del RPC, así que se ejercitan aquí sin Supabase: si el
/// mapeo se rompe, el riel marca la categoría equivocada o los chips de
/// subcategoría no aparecen, y ninguna consulta SQL lo detectaría.
void main() {
  /// Item del feed tal como lo emite `cliente_home_feed` con la migración 48.
  Map<String, dynamic> itemFeed({
    int idLocalServicio = 5,
    int idServicio = 8,
    int idHoja = 7,
    int? idPadre = 6,
    String? categoriaCodigo = 'belleza',
    String? categoriaNombre = 'Belleza',
    String? subcategoriaCodigo = 'unas',
    String? subcategoriaNombre = 'Uñas / Manicure',
    String codigoHoja = 'unas',
    Map<String, dynamic>? configPrecio,
    bool servicioActivo = true,
    bool localActivo = true,
    bool lsActivo = true,
    String? fotoServicio,
    double? rating,
    int totalResenas = 0,
  }) => <String, dynamic>{
    'id_local_servicio': idLocalServicio,
    'created_at': '2026-01-01T10:00:00Z',
    'permite_reserva_directa': false,
    'cantidad_default': 1,
    'cantidad_max_capacidad': 1,
    'activo': lsActivo,
    'solo_turnos': false,
    'sin_tramos': false,
    'rating': rating,
    'total_resenas': totalResenas,
    'categoria_codigo': categoriaCodigo,
    'categoria_nombre': categoriaNombre,
    'subcategoria_codigo': subcategoriaCodigo,
    'subcategoria_nombre': subcategoriaNombre,
    'servicio': <String, dynamic>{
      'id': idServicio,
      'nombre': 'Arreglo de uñas',
      'descripcion': 'Manicure completo',
      'foto': fotoServicio,
      'activo': servicioActivo,
      'id_tipo_actividad': idHoja,
      'config_precio': configPrecio,
      'tipo_actividad': <String, dynamic>{
        'id': idHoja,
        'codigo': codigoHoja,
        'nombre': 'Uñas / Manicure',
        'id_padre': idPadre,
      },
    },
    'local': <String, dynamic>{
      'id': 3,
      'nombre': 'Manicure',
      'direccion': 'Calle 1',
      'provincia': 'La Habana',
      'pais': 'Cuba',
      'horario_atencion': '8-4',
      'activo': localActivo,
    },
    'entidad': <String, dynamic>{'id': 1, 'denominacion': 'Entidad'},
  };

  group('itemsDesdeFeed · categoría y subcategoría', () {
    test('la categoría es el PADRE, no la hoja', () {
      // Con la categoría tomada de la hoja, el riel compararía el id de la
      // subcategoría con el de la categoría y no marcaría nada seleccionado.
      final item = HomeCatalogService.itemsDesdeFeed([itemFeed()]).single;
      expect(item.category.id, 6);
      expect(item.category.codigo, 'belleza');
      expect(item.category.nombre, 'Belleza');
    });

    test('la subcategoría es la HOJA', () {
      final item = HomeCatalogService.itemsDesdeFeed([itemFeed()]).single;
      expect(item.subcategoria, isNotNull);
      expect(item.subcategoria!.id, 7);
      expect(item.subcategoria!.codigo, 'unas');
      expect(item.subcategoria!.nombre, 'Uñas / Manicure');
    });

    test('un servicio en una categoría raíz no tiene subcategoría', () {
      final item = HomeCatalogService.itemsDesdeFeed([
        itemFeed(
          idHoja: 6,
          idPadre: null,
          codigoHoja: 'belleza',
          categoriaCodigo: 'belleza',
          categoriaNombre: 'Belleza',
          subcategoriaCodigo: null,
          subcategoriaNombre: null,
        ),
      ]).single;
      expect(item.subcategoria, isNull);
      expect(item.category.id, 6);
      expect(item.category.codigo, 'belleza');
    });

    test('sin `id_padre` en el payload la taxonomía se lee plana', () {
      // Migración 47 sin aplicar (o payload de la migración 22): el servicio es
      // su propia categoría y no hay subcategoría. No debe lanzar.
      final item = HomeCatalogService.itemsDesdeFeed([
        <String, dynamic>{
          'id_local_servicio': 5,
          'created_at': '2026-01-01T10:00:00Z',
          'activo': true,
          'servicio': <String, dynamic>{
            'id': 8,
            'nombre': 'Arreglo de uñas',
            'id_tipo_actividad': 7,
            'tipo_actividad_codigo': 'unas',
          },
          'local': <String, dynamic>{'id': 3, 'nombre': 'Manicure'},
        },
      ]).single;
      expect(item.category.id, 7);
      expect(item.category.codigo, 'unas');
      expect(item.subcategoria, isNull);
    });

    test('el código de la HOJA sigue llegando al modelo del servicio', () {
      // Es lo que enciende el flujo de pasajes: `esTransporteOmnibus` compara
      // `servicio.tipoActividad` con 'transporte_omnibus', y ese código también
      // es una subcategoría desde la migración 47.
      final item = HomeCatalogService.itemsDesdeFeed([
        itemFeed(
          idHoja: 2,
          idPadre: 17,
          codigoHoja: 'transporte_omnibus',
          categoriaCodigo: 'transporte',
          categoriaNombre: 'Transporte',
          subcategoriaCodigo: 'transporte_omnibus',
          subcategoriaNombre: 'Transporte en ómnibus',
        ),
      ]).single;
      expect(item.localServicio!.servicio!.tipoActividad, 'transporte_omnibus');
      expect(item.localServicio!.esTransporteOmnibus, isTrue);
      expect(item.category.codigo, 'transporte');
      expect(item.subcategoria!.codigo, 'transporte_omnibus');
    });

    test('sin `subcategoria_nombre` no se inventa una subcategoría', () {
      // La subcategoría desactivada llega a null desde el RPC: la hoja sigue
      // siendo subcategoría por `id_padre`, pero el cliente no la ofrece.
      final item = HomeCatalogService.itemsDesdeFeed([
        itemFeed(
          subcategoriaCodigo: null,
          subcategoriaNombre: null,
          categoriaNombre: 'Belleza',
        ),
      ]).single;
      expect(item.subcategoria, isNull);
      expect(item.category.id, 6);
    });

    test('sin `categoria_nombre` cae al código legible, no a vacío', () {
      // El RPC anula `categoria_nombre` cuando la categoría está apagada.
      final item = HomeCatalogService.itemsDesdeFeed([
        itemFeed(categoriaNombre: null, categoriaCodigo: 'belleza'),
      ]).single;
      expect(item.category.nombre, 'belleza');
    });

    test('sin nada de categoría queda "General", como antes', () {
      final item = HomeCatalogService.itemsDesdeFeed([
        <String, dynamic>{
          'id_local_servicio': 5,
          'created_at': '2026-01-01T10:00:00Z',
          'activo': true,
          'servicio': <String, dynamic>{'id': 8, 'nombre': 'Gas'},
          'local': <String, dynamic>{'id': 3, 'nombre': 'Mi Casa'},
        },
      ]).single;
      expect(item.category.nombre, 'General');
      expect(item.category.codigo, '');
      expect(item.category.id, isNull);
      // Sin `id_tipo_actividad` la categoría cae en "Todas", que es justo el
      // comportamiento de antes de la migración 47.
      expect(item.category.esTodas, isTrue);
    });
  });

  group('itemsDesdeFeed · filtros del cliente', () {
    test('un servicio en subcategoría no coincide con su categoría hermana',
        () {
      final item = HomeCatalogService.itemsDesdeFeed([itemFeed()]).single;

      // Esto es exactamente lo que hace el Home: el filtro de categoría del
      // riel no participa aquí (lo aplica el servidor), y la subcategoría se
      // compara con la HOJA del item.
      const enUnas = FiltrosServicios(
        idSubcategoria: 7,
        nombreSubcategoria: 'Uñas / Manicure',
      );
      expect(enUnas.coincide(idSubcategoriaItem: item.subcategoria?.id), isTrue);

      const enCejas = FiltrosServicios(idSubcategoria: 8);
      expect(
        enCejas.coincide(idSubcategoriaItem: item.subcategoria?.id),
        isFalse,
      );

      // "Todas" no filtra.
      expect(
        FiltrosServicios.vacio.coincide(
          idSubcategoriaItem: item.subcategoria?.id,
        ),
        isTrue,
      );
    });

    test('el filtro llega nulo cuando el servicio está en la categoría', () {
      final item = HomeCatalogService.itemsDesdeFeed([
        itemFeed(
          idHoja: 6,
          idPadre: null,
          codigoHoja: 'belleza',
          subcategoriaCodigo: null,
          subcategoriaNombre: null,
        ),
      ]).single;
      expect(item.subcategoria, isNull);
      // Con una subcategoría elegida, un servicio sin subcategoría queda fuera:
      // el servidor ya lo filtró, esto es la red de seguridad.
      const enUnas = FiltrosServicios(idSubcategoria: 7);
      expect(enUnas.coincide(idSubcategoriaItem: item.subcategoria?.id), isFalse);
    });
  });

  group('itemsDesdeFeed · descartes', () {
    test('el servicio apagado no llega a la lista', () {
      expect(
        HomeCatalogService.itemsDesdeFeed([itemFeed(servicioActivo: false)]),
        isEmpty,
      );
    });

    test('el local apagado no llega a la lista', () {
      expect(
        HomeCatalogService.itemsDesdeFeed([itemFeed(localActivo: false)]),
        isEmpty,
      );
    });

    test('el par apagado no llega a la lista', () {
      expect(
        HomeCatalogService.itemsDesdeFeed([itemFeed(lsActivo: false)]),
        isEmpty,
      );
    });

    test('un item que no es mapa se ignora sin lanzar', () {
      final items = HomeCatalogService.itemsDesdeFeed([
        'texto',
        42,
        null,
        itemFeed(),
      ]);
      expect(items, hasLength(1));
    });

    test('el precio y el rating salen del payload, no se inventan', () {
      final conPrecio = HomeCatalogService.itemsDesdeFeed([
        itemFeed(
          configPrecio: const {
            'monedas': ['USD'],
            'precios_base': {'USD': 40},
            'moneda_default': 'USD',
          },
          rating: 4.5,
          totalResenas: 3,
        ),
      ]).single;
      expect(conPrecio.price, 40);
      expect(conPrecio.currency, 'USD');
      expect(conPrecio.rating, 4.5);
      expect(conPrecio.totalResenas, 3);

      final sinNada = HomeCatalogService.itemsDesdeFeed([itemFeed()]).single;
      expect(sinNada.price, isNull);
      expect(sinNada.rating, isNull);
      expect(sinNada.totalResenas, 0);
    });
  });

  group('categoriasDesdeFeed', () {
    test('"Todas" va primero y las demás conservan el orden del servidor', () {
      final categorias = HomeCatalogService.categoriasDesdeFeed(const {
        'metadata': {
          'categorias': [
            {'id': 10, 'codigo': 'alojamiento', 'nombre': 'Alojamiento'},
            {'id': 6, 'codigo': 'belleza', 'nombre': 'Belleza'},
          ],
        },
      });
      expect(categorias.first.esTodas, isTrue);
      expect(categorias.map((c) => c.nombre).toList(), [
        'Todas',
        'Alojamiento',
        'Belleza',
      ]);
    });

    test('las subcategorías anidadas se leen', () {
      final belleza = HomeCatalogService.categoriasDesdeFeed(const {
        'metadata': {
          'categorias': [
            {
              'id': 6,
              'codigo': 'belleza',
              'nombre': 'Belleza',
              'id_padre': null,
              'subcategorias': [
                {'id': 7, 'codigo': 'unas', 'nombre': 'Uñas / Manicure'},
                {
                  'id': 9,
                  'codigo': 'peluqueria',
                  'nombre': 'Peluquería / Barbería',
                },
              ],
            },
          ],
        },
      }).firstWhere((c) => c.codigo == 'belleza');

      expect(belleza.tieneSubcategorias, isTrue);
      expect(belleza.subcategorias.map((s) => s.id).toList(), [7, 9]);
      // Una subcategoría no tiene subcategorías propias.
      expect(belleza.subcategorias.first.tieneSubcategorias, isFalse);
    });

    test('una categoría sin subcategorías queda con la lista vacía', () {
      final juridicos = HomeCatalogService.categoriasDesdeFeed(const {
        'metadata': {
          'categorias': [
            {'id': 11, 'codigo': 'juridicos', 'nombre': 'Jurídicos'},
          ],
        },
      }).firstWhere((c) => c.codigo == 'juridicos');
      expect(juridicos.subcategorias, isEmpty);
      expect(juridicos.tieneSubcategorias, isFalse);
    });

    test('sin metadata solo queda "Todas"', () {
      expect(HomeCatalogService.categoriasDesdeFeed(const {}), [
        HomeCatalogCategory.todas,
      ]);
      expect(
        HomeCatalogService.categoriasDesdeFeed(const {'metadata': null}),
        [HomeCatalogCategory.todas],
      );
    });

    test('una categoría sin nombre se descarta', () {
      // El servidor ya las filtra con `btrim(nombre) <> ''`; esto es la red de
      // seguridad del cliente para no pintar un chip en blanco.
      final categorias = HomeCatalogService.categoriasDesdeFeed(const {
        'metadata': {
          'categorias': [
            {'id': 99, 'codigo': 'vacia', 'nombre': '   '},
            {'id': 6, 'codigo': 'belleza', 'nombre': 'Belleza'},
          ],
        },
      });
      expect(categorias.map((c) => c.codigo).toList(), ['', 'belleza']);
    });
  });
}