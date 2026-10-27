import 'package:flutter_test/flutter_test.dart';
import '../lib/services/catalogo_service.dart';

void main() {
  final productos = <Map<String, dynamic>>[
    {'id': 1, 'denominacion': 'Arroz', 'sku': 'ARR', 'stock_disponible': 0.5, 'mostrar_en_catalogo': true},
    {'id': 2, 'denominacion': 'Arroz integral', 'sku': 'INT', 'stock_disponible': 0, 'mostrar_en_catalogo': false},
    {'id': 3, 'denominacion': 'Aceite', 'sku': 'ACE', 'stock_disponible': '-2', 'mostrar_en_catalogo': true},
    {'id': 4, 'denominacion': 'Sal', 'sku': 'SAL', 'mostrar_en_catalogo': false},
  ];

  test('sin filtros incluye todos los resultados', () {
    expect(filtrarProductosCatalogo(productos), hasLength(4));
  });

  test('con stock incluye cantidades fraccionarias positivas', () {
    expect(filtrarProductosCatalogo(productos, stock: FiltroStockCatalogo.conStock)
        .map((p) => p['id']), [1]);
  });

  test('sin stock incluye cero y negativos, no cantidades desconocidas', () {
    expect(filtrarProductosCatalogo(productos, stock: FiltroStockCatalogo.sinStock)
        .map((p) => p['id']), [2, 3]);
  });

  test('combina búsqueda, stock y estado de publicación', () {
    expect(filtrarProductosCatalogo(productos, busqueda: ' ARROZ ',
        stock: FiltroStockCatalogo.sinStock,
        publicacion: FiltroPublicacionCatalogo.noPublicados)
        .map((p) => p['id']), [2]);
    expect(filtrarProductosCatalogo(productos, busqueda: 'ace',
        publicacion: FiltroPublicacionCatalogo.publicados)
        .map((p) => p['id']), [3]);
  });

  test('filtrar no cambia productos ni estados', () {
    filtrarProductosCatalogo(productos, stock: FiltroStockCatalogo.conStock).clear();
    expect(productos, hasLength(4));
    expect(productos.first['mostrar_en_catalogo'], isTrue);
  });
}
