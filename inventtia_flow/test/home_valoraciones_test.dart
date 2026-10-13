import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/services/home_catalog_service.dart';

/// Valoraciones del Home.
///
/// La regla importante se mantiene: un servicio **sin** reseñas no se coloca
/// como si tuviera una valoración. Su tarjeta no pinta estrellas
/// (`tieneValoracion`), y el orden lo resuelve el servidor.
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

  // El orden "Mejor valorados" **ya no se calcula aquí**: lo aplica el servidor
  // en `cliente_home_feed` (`p_mejor_valorados`) con la misma regla — primero
  // los que tienen reseñas, por promedio descendente y, a igual promedio, más
  // reseñas primero; los que no tienen ninguna van al final. Se comprueba
  // contra la base en las consultas de `migraciones/35_home_feed.sql`.

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
    // Es lo que permite que el orden curado de una colección y el de "mejor
    // valorados" lleguen intactos desde el servidor hasta la pantalla.
    expect(page.items.map((i) => i.id), [1, 2]);
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
