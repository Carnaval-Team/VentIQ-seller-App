import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/models/product.dart';

void main() {
  test('el catalogo no convierte un USD ausente en cero', () {
    final sinUsd = Product.fromJson({
      'id': 1,
      'denominacion': 'Cafe',
      'precio': 10,
    });
    expect(sinUsd.precio, 10);
    expect(sinUsd.precioUsd, isNull);

    final conCero = Product.fromJson({
      'id': 1,
      'denominacion': 'Cafe',
      'precio': 10,
      'precio_venta_usd': 0,
    });
    expect(conCero.precioUsd, isNull);

    final conUsd = Product.fromJson({
      'id': 1,
      'denominacion': 'Cafe',
      'precio': 10,
      'precio_venta_usd': 1.5,
      'origen_precio_usd': 'tpv',
    });
    expect(conUsd.precioUsd, 1.5);
    expect(conUsd.toJson()['precio_venta_usd'], 1.5);
    expect(conUsd.toJson()['origen_precio_usd'], 'tpv');
  });
}
