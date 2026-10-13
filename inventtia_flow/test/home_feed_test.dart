import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/services/home_catalog_service.dart';

/// Contrato del feed consolidado y del ranking semanal.
///
/// Lo que se blinda aquí es que el cliente no invente nada cuando el servidor no
/// manda un dato: contadores en cero, `has_more` apagado y, sobre todo, que un
/// item sin `lugares_semana` (el feed normal) no se pinte como si estuviera en el
/// ranking.
void main() {
  const categoria = HomeCatalogCategory(
    id: 1,
    codigo: 'general',
    nombre: 'General',
  );

  HomeCatalogItem item({int? lugaresSemana}) => HomeCatalogItem(
    id: 1,
    title: 'Lifting De Cejas',
    venue: 'Salon 1 Cejas',
    category: categoria,
    lugaresSemana: lugaresSemana,
  );

  group('HomeContadores', () {
    test('lee los dos contadores', () {
      final c = HomeContadores.fromJson(const {
        'notificaciones': 4,
        'reservas': 2,
      });
      expect(c.notificaciones, 4);
      expect(c.reservas, 2);
    });

    test('sin contadores deja todo en cero, no en null', () {
      final c = HomeContadores.fromJson(null);
      expect(c.notificaciones, 0);
      expect(c.reservas, 0);
    });

    test('un contador ausente no arrastra al otro', () {
      final c = HomeContadores.fromJson(const {'reservas': 3});
      expect(c.notificaciones, 0);
      expect(c.reservas, 3);
    });

    test('vacio es cero y cero', () {
      expect(HomeContadores.vacio.notificaciones, 0);
      expect(HomeContadores.vacio.reservas, 0);
    });
  });

  group('lugaresSemana', () {
    test('el feed normal no trae ranking, así que no hay etiqueta', () {
      final normal = item();
      expect(normal.lugaresSemana, isNull);
      expect(normal.lugaresSemanaLabel, isNull);
    });

    test('un solo lugar va en singular', () {
      expect(item(lugaresSemana: 1).lugaresSemanaLabel, '1 lugar reservado');
    });

    test('varios lugares van en plural', () {
      // El dato real de la semana del 2026-10-05 para el LS 21.
      expect(
        item(lugaresSemana: 11).lugaresSemanaLabel,
        '11 lugares reservados',
      );
    });

    test('cero no se disfraza de etiqueta', () {
      // El servidor no devuelve items con 0 (`inner join` con la ventana), pero
      // si algún día lo hiciera, decir "0 lugares reservados" sería ruido.
      expect(item(lugaresSemana: 0).lugaresSemanaLabel, '0 lugares reservados');
    });
  });

  group('HomeFeed', () {
    test('el contrato de paginación viaja apagado', () {
      const feed = HomeFeed(items: [], total: 0);
      expect(feed.hasMore, isFalse);
      expect(feed.nextCursor, isNull);
    });

    test('sin categorías del servidor queda solo "Todas"', () {
      const feed = HomeFeed(items: [], total: 0);
      expect(feed.categorias, hasLength(1));
      expect(feed.categorias.single.esTodas, isTrue);
    });

    test('las secciones opcionales empiezan vacías, no con relleno', () {
      const feed = HomeFeed(items: [], total: 0);
      expect(feed.patrocinados, isEmpty);
      expect(feed.colecciones, isEmpty);
      expect(feed.contadores.reservas, 0);
      expect(feed.contadores.notificaciones, 0);
    });
  });
}
