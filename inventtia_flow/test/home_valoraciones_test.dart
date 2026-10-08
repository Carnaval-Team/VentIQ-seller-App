import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/services/home_catalog_service.dart';

/// El orden "Mejor valorados" del Home usa el promedio real de `flow.resena`.
///
/// La regla importante: un servicio **sin** reseñas no se coloca como si
/// tuviera una valoración. Va al final, y su tarjeta no pinta estrellas.
void main() {
  const categoria = HomeCatalogCategory(
    id: 1,
    codigo: 'general',
    nombre: 'General',
  );

  HomeCatalogItem item({
    required int id,
    required String title,
    double? rating,
    int totalResenas = 0,
  }) => HomeCatalogItem(
    id: id,
    title: title,
    venue: 'Local $id',
    category: categoria,
    rating: rating,
    totalResenas: totalResenas,
  );

  List<int> ordenarTopRated(List<HomeCatalogItem> catalogo) {
    final page = HomeCatalogService.paginar(
      catalogo: catalogo,
      page: 1,
      pageSize: 50,
      topRated: true,
    );
    return page.items.map((i) => i.id).toList();
  }

  test('sin el filtro conserva el orden del catálogo', () {
    final catalogo = [
      item(id: 1, title: 'A', rating: 3, totalResenas: 1),
      item(id: 2, title: 'B', rating: 5, totalResenas: 9),
    ];
    final page = HomeCatalogService.paginar(
      catalogo: catalogo,
      page: 1,
      pageSize: 50,
    );
    expect(page.items.map((i) => i.id), [1, 2]);
  });

  test('ordena por promedio descendente', () {
    final catalogo = [
      item(id: 1, title: 'Malo', rating: 2.0, totalResenas: 4),
      item(id: 2, title: 'Excelente', rating: 4.9, totalResenas: 3),
      item(id: 3, title: 'Bueno', rating: 4.2, totalResenas: 8),
    ];
    expect(ordenarTopRated(catalogo), [2, 3, 1]);
  });

  test('a igual promedio gana el que tiene más reseñas', () {
    final catalogo = [
      item(id: 1, title: 'Pocas', rating: 4.5, totalResenas: 2),
      item(id: 2, title: 'Muchas', rating: 4.5, totalResenas: 30),
    ];
    expect(ordenarTopRated(catalogo), [2, 1]);
  });

  test('los servicios sin reseñas van al final, no primero', () {
    // Sin este cuidado un servicio con `rating = null` podría colarse arriba.
    final catalogo = [
      item(id: 1, title: 'Sin reseñas'),
      item(id: 2, title: 'Con 3.0', rating: 3.0, totalResenas: 1),
      item(id: 3, title: 'Sin reseñas tampoco'),
      item(id: 4, title: 'Con 5.0', rating: 5.0, totalResenas: 2),
    ];
    final orden = ordenarTopRated(catalogo);
    expect(orden, [4, 2, 1, 3]);
  });

  group('tieneValoracion', () {
    test('es false sin reseñas aunque venga un rating', () {
      // Blindaje: si un día el RPC devolviera promedio 0 con total 0, no debe
      // pintarse una valoración.
      const sinResenas = HomeCatalogItem(
        id: 1,
        title: 'X',
        venue: 'Y',
        category: categoria,
        rating: 0,
        totalResenas: 0,
      );
      expect(sinResenas.tieneValoracion, isFalse);
    });

    test('es true con al menos una reseña y promedio positivo', () {
      const conResenas = HomeCatalogItem(
        id: 1,
        title: 'X',
        venue: 'Y',
        category: categoria,
        rating: 4.7,
        totalResenas: 12,
      );
      expect(conResenas.tieneValoracion, isTrue);
    });

    test('es false cuando no hay rating', () {
      const sinRating = HomeCatalogItem(
        id: 1,
        title: 'X',
        venue: 'Y',
        category: categoria,
        totalResenas: 5,
      );
      expect(sinRating.tieneValoracion, isFalse);
    });
  });
}
