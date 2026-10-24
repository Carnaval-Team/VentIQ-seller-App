import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/models/categoria_con_conteo.dart';
import 'package:inventtia_flow/models/establecimiento_resumen.dart';
import 'package:inventtia_flow/services/home_catalog_service.dart';
import 'package:inventtia_flow/utils/exploracion_resumen.dart';
import 'package:inventtia_flow/widgets/filtros_servicios_sheet.dart';

/// Lunes 8 de enero de 2024, 10:00 — dentro de «Lun - Dom, 8:30 - 16:00».
final DateTime _lunesAbierto = DateTime(2024, 1, 8, 10);
final DateTime _lunesCerrado = DateTime(2024, 1, 8, 20);

EstablecimientoResumen _local({
  int id = 1,
  String nombre = 'Local',
  String? provincia = 'Villa Clara Province',
  double? rating,
  int resenas = 0,
  int servicios = 1,
  double? precio,
  String? moneda,
  String? horario,
}) {
  return EstablecimientoResumen(
    idLocal: id,
    nombre: nombre,
    provincia: provincia,
    rating: rating,
    totalResenas: resenas,
    totalServicios: servicios,
    precioDesde: precio,
    monedaDesde: moneda,
    horarioTexto: horario,
  );
}

void main() {
  group('ResumenCategorias', () {
    test('lee el jsonb de la RPC con subcategorías anidadas', () {
      final resumen = ResumenCategorias.fromJson(const {
        'categorias': [
          {
            'id': 6,
            'codigo': 'belleza',
            'nombre': 'Belleza',
            'servicios': 5,
            'establecimientos': 3,
            'subcategorias': [
              {
                'id': 7,
                'codigo': 'unas',
                'nombre': 'Uñas / Manicure',
                'servicios': 2,
                'establecimientos': 2,
              },
            ],
          },
          {
            'id': 14,
            'codigo': 'gastronomia',
            'nombre': 'Gastronomía',
            'servicios': 0,
            'establecimientos': 0,
            'subcategorias': <dynamic>[],
          },
        ],
        'total_servicios': 11,
        'total_establecimientos': 8,
        'otros_servicios': 0,
        'otros_establecimientos': 0,
      });

      expect(resumen.categorias.length, 2);
      expect(resumen.categoriasActivas, 2);
      expect(resumen.totalServicios, 11);
      expect(resumen.totalEstablecimientos, 8);
      expect(resumen.hayOtros, isFalse);
      expect(resumen.categorias.first.categoria.codigo, 'belleza');
      expect(resumen.categorias.first.servicios, 5);
      expect(resumen.categorias.first.establecimientos, 3);
      expect(resumen.categorias.first.subcategorias.single.categoria.id, 7);
      expect(
        resumen.categorias.first.subcategorias.single.etiquetaServicios,
        '2 servicios',
      );
      // Un rubro sin nada se conserva: el cliente pidió ver TODOS los rubros.
      expect(resumen.categorias.last.vacia, isTrue);
      expect(
        resumen.categorias.last.etiquetaEstablecimientos,
        'Todavía sin establecimientos',
      );
    });

    test('json vacío o sin claves no revienta', () {
      expect(ResumenCategorias.fromJson(const {}).categorias, isEmpty);
      expect(ResumenCategorias.fromJson(const {}).categoriasActivas, 0);
      expect(ResumenCategorias.vacio.totalServicios, 0);
    });

    test('detecta los servicios sin categoría', () {
      final resumen = ResumenCategorias.fromJson(const {
        'categorias': <dynamic>[],
        'otros_servicios': 2,
        'otros_establecimientos': 1,
      });
      expect(resumen.hayOtros, isTrue);
      expect(resumen.otrosServicios, 2);
    });
  });

  group('etiquetas de conteo', () {
    test('singular, plural y vacío', () {
      expect(etiquetaConteoEstablecimientos(0), 'Todavía sin establecimientos');
      expect(etiquetaConteoEstablecimientos(1), '1 establecimiento');
      expect(etiquetaConteoEstablecimientos(3), '3 establecimientos');
    });

    test('resumen de una categoría', () {
      const categoria = CategoriaConConteo(
        categoria: HomeCatalogCategory(id: 6, codigo: 'belleza', nombre: 'Belleza'),
        servicios: 5,
        establecimientos: 3,
      );
      expect(categoria.resumen, '3 establecimientos · 5 servicios');
    });
  });

  group('EstablecimientoResumen', () {
    test('lee el jsonb de la RPC y resuelve precio desde el más barato', () {
      final e = EstablecimientoResumen.fromJson(const {
        'id': 11,
        'nombre': 'Salon 2 Cejas',
        'descripcion': 'Salón de belleza',
        'direccion': 'Calle 1',
        'provincia': 'Villa Clara Province',
        'foto': 'https://x/foto.jpg',
        'horario_atencion': 'Lun - Dom, 8:30 - 16:00',
        'total_servicios': 4,
        'tiene_reserva_directa': true,
        'precios': [
          {'monedas': ['CUP'], 'precios_base': {'CUP': 3500}, 'moneda_default': 'CUP'},
          {'monedas': ['CUP'], 'precios_base': {'CUP': 350}, 'moneda_default': 'CUP'},
          {'monedas': ['USD'], 'precios_base': null, 'moneda_default': 'USD'},
        ],
        'total_resenas': 2,
        'rating': 2.5,
        'entidad': {
          'id': 3,
          'denominacion': 'Carnaval',
          'direccion': 'X',
          'telefono': '5555',
        },
      });

      expect(e.idLocal, 11);
      expect(e.nombre, 'Salon 2 Cejas');
      expect(e.totalServicios, 4);
      expect(e.tieneReservaDirecta, isTrue);
      expect(e.precioDesde, 350);
      expect(e.monedaDesde, 'CUP');
      expect(e.precioDesdeLabel, 'Desde 350 CUP');
      expect(e.tieneValoracion, isTrue);
      expect(e.rating, 2.5);
      expect(e.etiquetaResenas, '2 reseñas');
      expect(e.ubicacion, 'Villa Clara Province');
      expect(e.entidad, 'Carnaval');
    });

    test('sin reseñas no hay valoración (no se pinta «0.0»)', () {
      final e = EstablecimientoResumen.fromJson(const {
        'id': 2,
        'nombre': 'Carnaval Tienda',
        'total_resenas': 0,
        'rating': null,
      });
      expect(e.tieneValoracion, isFalse);
      expect(e.etiquetaServicios, '0 servicios');
    });

    test('el «desde» se calcula en la moneda del local, sin mezclar importes', () {
      // Dos servicios en CUP y uno en USD: el local anuncia su importe en CUP.
      // Comparar los números entre monedas (5 < 2500) diría «Desde 5 USD», que no
      // significa nada para quien va a pagar en CUP.
      final e = EstablecimientoResumen.fromJson(const {
        'id': 9,
        'nombre': 'Local mixto',
        'precios': [
          {'precios_base': {'CUP': 3000}, 'moneda_default': 'CUP'},
          {'precios_base': {'CUP': 2500}, 'moneda_default': 'CUP'},
          {'precios_base': {'USD': 5}, 'moneda_default': 'USD'},
        ],
      });

      expect(e.monedaDesde, 'CUP');
      expect(e.precioDesde, 2500);
      expect(e.precioDesdeMontoLabel, '2500 CUP');
      expect(e.precioDesdeLabel, 'Desde 2500 CUP');
    });

    test('con un solo servicio con precio se anuncia en su moneda', () {
      final e = EstablecimientoResumen.fromJson(const {
        'id': 10,
        'nombre': 'Local en dólares',
        'precios': [
          {'precios_base': {'USD': 40}, 'moneda_default': 'USD'},
          {'precios_base': <String, dynamic>{}, 'moneda_default': 'CUP'},
        ],
      });

      expect(e.monedaDesde, 'USD');
      expect(e.precioDesdeMontoLabel, '40 USD');
    });

    test('sin precios configurados no hay «Desde»', () {      final e = EstablecimientoResumen.fromJson(const {
        'id': 3,
        'nombre': 'Sin precio',
        'precios': [
          {'precios_base': <String, dynamic>{}, 'moneda_default': 'USD'},
        ],
      });
      expect(e.precioDesde, isNull);
      expect(e.precioDesdeLabel, isNull);
    });

    test('la ubicación cae a la dirección si no hay provincia', () {
      final e = EstablecimientoResumen.fromJson(const {
        'id': 4,
        'nombre': 'Solo dirección',
        'direccion': 'Calle 42',
      });
      expect(e.ubicacion, 'Calle 42');
    });

    test('el horario se evalúa con el reloj que se le pase', () {
      final e = _local(horario: 'Lun - Dom, 8:30 - 16:00');
      expect(e.abiertoAhora(_lunesAbierto), isTrue);
      expect(e.abiertoAhora(_lunesCerrado), isFalse);
    });
  });

  group('ordenarEstablecimientos', () {
    final sinResenas = _local(id: 1, nombre: 'Alfa', servicios: 9);
    final bueno = _local(id: 2, nombre: 'Zeta', rating: 4.9, resenas: 30);
    final regular = _local(id: 3, nombre: 'Beta', rating: 3.1, resenas: 5);

    test('mejor valorados deja a los sin reseñas al final', () {
      final orden = ordenarEstablecimientos(
        [sinResenas, regular, bueno],
        OrdenEstablecimientos.mejorValorados,
      );
      expect(orden.map((e) => e.nombre), ['Zeta', 'Beta', 'Alfa']);
    });

    test('más servicios ordena por número y desempata por valoración', () {
      final orden = ordenarEstablecimientos(
        [bueno, sinResenas, regular],
        OrdenEstablecimientos.masServicios,
      );
      expect(orden.map((e) => e.nombre), ['Alfa', 'Zeta', 'Beta']);
    });

    test('A-Z ignora la caja', () {
      final orden = ordenarEstablecimientos(
        [_local(nombre: 'zeta'), _local(nombre: 'Alfa')],
        OrdenEstablecimientos.nombre,
      );
      expect(orden.map((e) => e.nombre), ['Alfa', 'zeta']);
    });

    test('no muta la lista de entrada', () {
      final original = [sinResenas, bueno];
      ordenarEstablecimientos(original, OrdenEstablecimientos.nombre);
      expect(original.first.nombre, 'Alfa');
    });
  });

  group('pasaFiltrosEstablecimiento', () {
    test('«solo abiertos» exige horario interpretable y abierto', () {
      final abierto = _local(horario: 'Lun - Dom, 8:30 - 16:00');
      final cerrado = _local(id: 2, horario: 'Lun - Dom, 8:30 - 16:00');
      final sinHorario = _local(id: 3);

      const filtros = FiltrosServicios(soloAbiertos: true);

      expect(
        pasaFiltrosEstablecimiento(abierto, filtros, ahora: _lunesAbierto),
        isTrue,
      );
      expect(
        pasaFiltrosEstablecimiento(cerrado, filtros, ahora: _lunesCerrado),
        isFalse,
      );
      // Un horario que no se pudo interpretar no es «abierto».
      expect(
        pasaFiltrosEstablecimiento(sinHorario, filtros, ahora: _lunesAbierto),
        isFalse,
      );
    });

    test('«★ o más» deja fuera a quien no tiene reseñas', () {
      final conResenas = _local(rating: 4.2, resenas: 8);
      final sinResenas = _local(id: 2);

      const filtros = FiltrosServicios(ratingMinimo: 4);

      expect(pasaFiltrosEstablecimiento(conResenas, filtros), isTrue);
      expect(pasaFiltrosEstablecimiento(sinResenas, filtros), isFalse);
    });

    test('provincia y precio se aplican sobre el dato del local', () {
      final local = _local(provincia: 'La Habana', precio: 500, moneda: 'CUP');

      expect(
        pasaFiltrosEstablecimiento(
          local,
          const FiltrosServicios(provincia: 'La Habana'),
        ),
        isTrue,
      );
      expect(
        pasaFiltrosEstablecimiento(
          local,
          const FiltrosServicios(provincia: 'Villa Clara Province'),
        ),
        isFalse,
      );
      expect(
        pasaFiltrosEstablecimiento(
          local,
          const FiltrosServicios(precioMax: 100),
        ),
        isFalse,
      );
      expect(
        pasaFiltrosEstablecimiento(
          local,
          const FiltrosServicios(precioMin: 100, moneda: 'CUP'),
        ),
        isTrue,
      );
    });

    test('sin filtros pasa todo', () {
      expect(
        pasaFiltrosEstablecimiento(_local(), FiltrosServicios.vacio),
        isTrue,
      );
    });
  });

  group('opcionesFiltrosEstablecimientos', () {
    test('deduce precios, provincias y locales sin inventar nada', () {
      final opciones = opcionesFiltrosEstablecimientos([
        _local(
          id: 1,
          nombre: 'Zeta',
          provincia: 'Villa Clara Province',
          precio: 350,
          moneda: 'CUP',
          rating: 4.0,
          resenas: 2,
        ),
        _local(id: 2, nombre: 'Alfa'),
      ]);

      expect(opciones.precios.single.precio, 350);
      expect(opciones.provincias, ['Villa Clara Province']);
      expect(opciones.locales.map((l) => l.nombre), ['Alfa', 'Zeta']);
      expect(opciones.hayValoraciones, isTrue);
      // Sin subcategorías: el filtro de subcategoría lo aplica el servidor.
      expect(opciones.haySubcategorias, isFalse);
    });

    test('sin reseñas no ofrece el filtro de valoración', () {
      final opciones = opcionesFiltrosEstablecimientos([_local()]);
      expect(opciones.hayValoraciones, isFalse);
      expect(opciones.hayPrecios, isFalse);
    });
  });
}