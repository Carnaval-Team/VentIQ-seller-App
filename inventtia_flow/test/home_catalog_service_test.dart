import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/services/home_catalog_service.dart';
import 'package:inventtia_flow/utils/horario_atencion.dart';

/// Pruebas del filtrado/paginado del Home.
///
/// Se ejercita `HomeCatalogService.paginar`, que es puro: no toca Supabase. La
/// versión anterior de este archivo llamaba a `fetchPage`, que sí hace red, así
/// que solo pasaba porque existía un catálogo de respaldo inventado. Ese
/// respaldo ya no existe y estas pruebas construyen el catálogo a mano.
void main() {
  const belleza = HomeCatalogCategory(
    id: 1,
    codigo: 'general',
    nombre: 'General',
  );
  const transporte = HomeCatalogCategory(
    id: 2,
    codigo: 'transporte_omnibus',
    nombre: 'Transporte en ómnibus',
  );

  HomeCatalogItem item({
    required int id,
    required String title,
    required String venue,
    HomeCatalogCategory category = belleza,
    double? price = 20,
    String? currency = 'USD',
    String horario = '8-4',
    String? provincia = 'Villa Clara Province',
  }) => HomeCatalogItem(
    id: id,
    title: title,
    venue: venue,
    category: category,
    price: price,
    currency: currency,
    horarioTexto: horario,
    estadoHorario: HorarioAtencion.parse(horario).evaluar(DateTime.now()),
    provincia: provincia,
  );

  final catalogo = <HomeCatalogItem>[
    item(id: 11, title: 'Arreglo de uñas', venue: 'Manicure'),
    item(id: 12, title: 'Depilación de cejas', venue: 'Ceji'),
    item(
      id: 13,
      title: 'Transportación',
      venue: 'Mi Local',
      category: transporte,
      price: 40,
    ),
    item(
      id: 14,
      title: 'Arreglo uñas naturales',
      venue: 'Uñis',
      provincia: 'Provincia de Camagüey',
      price: 500,
      currency: 'CUP',
    ),
    item(
      id: 15,
      title: 'Gas',
      venue: 'Mi Casa',
      price: null,
      currency: null,
      horario: 'sd',
    ),
    item(
      id: 16,
      title: 'Lifting de pestañas',
      venue: 'Ceji',
      horario: 'Cerrado',
    ),
  ];

  // Lunes 2024-01-01 a las 10:00.
  final lunes10 = DateTime(2024, 1, 1, 10);

  group('paginado', () {
    test('no repite elementos entre páginas', () {
      final primera = HomeCatalogService.paginar(
        catalogo: catalogo,
        page: 1,
        pageSize: 4,
        ahora: lunes10,
      );
      final segunda = HomeCatalogService.paginar(
        catalogo: catalogo,
        page: 2,
        pageSize: 4,
        ahora: lunes10,
      );

      expect(primera.items, hasLength(4));
      expect(segunda.items, hasLength(2));
      expect(primera.hasMore, isTrue);
      expect(segunda.hasMore, isFalse);
      expect(
        primera.items
            .map((i) => i.id)
            .toSet()
            .intersection(segunda.items.map((i) => i.id).toSet()),
        isEmpty,
      );
    });

    test('informa el total antes de paginar', () {
      final pagina = HomeCatalogService.paginar(
        catalogo: catalogo,
        page: 1,
        pageSize: 2,
        ahora: lunes10,
      );
      expect(pagina.total, 6);
    });

    test('una página fuera de rango devuelve vacío sin lanzar', () {
      final pagina = HomeCatalogService.paginar(
        catalogo: catalogo,
        page: 9,
        pageSize: 4,
        ahora: lunes10,
      );
      expect(pagina.items, isEmpty);
      expect(pagina.hasMore, isFalse);
    });
  });

  group('filtros', () {
    test('filtra por tipo de actividad real', () {
      final pagina = HomeCatalogService.paginar(
        catalogo: catalogo,
        page: 1,
        category: transporte,
        ahora: lunes10,
      );
      expect(pagina.items.map((i) => i.id), [13]);
    });

    test('la búsqueda ignora acentos y mayúsculas', () {
      final pagina = HomeCatalogService.paginar(
        catalogo: catalogo,
        page: 1,
        query: 'UNAS',
        ahora: lunes10,
      );
      expect(pagina.items.map((i) => i.id), containsAll([11, 14]));
    });

    test('"abierto ahora" excluye horarios no interpretables', () {
      final pagina = HomeCatalogService.paginar(
        catalogo: catalogo,
        page: 1,
        onlyOpen: true,
        ahora: lunes10,
      );
      final ids = pagina.items.map((i) => i.id).toSet();
      expect(ids, containsAll([11, 12, 13, 14]));
      // 15 tiene horario "sd" y 16 declara "Cerrado": ninguno se afirma abierto.
      expect(ids, isNot(contains(15)));
      expect(ids, isNot(contains(16)));
    });

    test('filtra por provincia del local', () {
      final pagina = HomeCatalogService.paginar(
        catalogo: catalogo,
        page: 1,
        provincia: 'Provincia de Camagüey',
        ahora: lunes10,
      );
      expect(pagina.items.map((i) => i.id), [14]);
    });
  });

  group('presentación honesta de los datos', () {
    test('sin precio configurado no se inventa un monto', () {
      final sinPrecio = catalogo.firstWhere((i) => i.id == 15);
      expect(sinPrecio.priceLabel, isNull);
    });

    test('el precio usa la moneda real del servicio', () {
      final enCup = catalogo.firstWhere((i) => i.id == 14);
      expect(enCup.priceLabel, '500 CUP');
    });

    test('un horario ilegible no se muestra como abierto', () {
      final ilegible = catalogo.firstWhere((i) => i.id == 15);
      expect(ilegible.horarioConocido, isFalse);
      expect(ilegible.abiertoAhora, isFalse);
    });

    test('las etiquetas salen de datos reales, no de adornos', () {
      final conReservaDirecta = HomeCatalogItem(
        id: 99,
        title: 'Transportación',
        venue: 'Carnaval Transportación',
        category: transporte,
        price: 50,
        currency: 'USD',
        permiteReservaDirecta: true,
        cantidadMaxCapacidad: 5,
      );
      expect(conReservaDirecta.tags, [
        'Reserva directa',
        'Hasta 5 por reserva',
      ]);
      expect(catalogo.first.tags, isEmpty);
    });
  });
}
