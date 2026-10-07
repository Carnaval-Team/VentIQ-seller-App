import 'package:flutter_test/flutter_test.dart';

import 'package:inventtia_flow/services/home_catalog_service.dart';

void main() {
  test(
    'el feed del Home pagina sus resultados sin repetir elementos',
    () async {
      await HomeCatalogService.clearCache();

      final firstPage = await HomeCatalogService.fetchPage(
        page: 1,
        pageSize: 4,
      );
      final secondPage = await HomeCatalogService.fetchPage(
        page: 2,
        pageSize: 4,
      );

      expect(firstPage.items, isNotEmpty);
      expect(secondPage.items, isNotEmpty);
      expect(
        firstPage.items
            .map((item) => item.id)
            .toSet()
            .intersection(secondPage.items.map((item) => item.id).toSet()),
        isEmpty,
      );
      expect(
        firstPage.items.first.priceLabel,
        contains(firstPage.items.first.currency),
      );
    },
  );

  test('los filtros de catálogo mantienen el contrato de página', () async {
    final page = await HomeCatalogService.fetchPage(
      page: 1,
      pageSize: 3,
      category: 'Uñas',
    );

    expect(page.items, isNotEmpty);
    expect(page.items.every((item) => item.category == 'Uñas'), isTrue);
  });
}
