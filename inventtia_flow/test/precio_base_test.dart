import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/models/config_precio.dart';
import 'package:inventtia_flow/utils/precio_reserva.dart';

/// El catálogo real mezcla monedas (USD y CUP) y tiene servicios con
/// `config_precio = '{}'`, es decir **sin precio**. La regla tiene que devolver
/// `null` en ese caso para que la tarjeta diga "Consultar" en vez de mentir con
/// un `0`.
void main() {
  group('precioBaseDe', () {
    test('usa la moneda por defecto cuando existe', () {
      final config = ConfigPrecio.fromJson({
        'monedas': ['USD', 'CUP'],
        'precios_base': {'USD': 40, 'CUP': 12000},
        'moneda_default': 'USD',
      });
      final base = precioBaseDe(config);
      expect(base, isNotNull);
      expect(base!.precio, 40);
      expect(base.moneda, 'USD');
    });

    test('respeta una moneda por defecto que no es la primera', () {
      // Caso real: 'Arreglo de uñas' tiene moneda_default CUP con USD también
      // configurado. Si se tomara la primera clave alfabética saldría CUP por
      // casualidad, así que se ordena distinto para forzar la comprobación.
      final config = ConfigPrecio.fromJson({
        'monedas': ['CUP', 'USD'],
        'precios_base': {'CUP': 1500, 'USD': 2},
        'moneda_default': 'CUP',
      });
      final base = precioBaseDe(config);
      expect(base!.moneda, 'CUP');
      expect(base.precio, 1500);
    });

    test('cae a cualquier moneda si la default no está en precios_base', () {
      final config = ConfigPrecio.fromJson({
        'monedas': ['EUR'],
        'precios_base': {'EUR': 30},
        'moneda_default': 'USD',
      });
      final base = precioBaseDe(config);
      expect(base!.moneda, 'EUR');
      expect(base.precio, 30);
    });

    test('sin precio configurado devuelve null, no cero', () {
      // `config_precio = '{}'` es el caso real de los servicios 1, 3 y 4.
      expect(precioBaseDe(ConfigPrecio.fromJson({})), isNull);
      expect(precioBaseDe(null), isNull);
      expect(
        precioBaseDe(ConfigPrecio.fromJson({'moneda_default': 'USD'})),
        isNull,
      );
    });

    test('un precio base de 0 se trata como ausente', () {
      final config = ConfigPrecio.fromJson({
        'precios_base': {'USD': 0},
        'moneda_default': 'USD',
      });
      expect(precioBaseDe(config), isNull);
    });
  });

  group('etiquetaPrecioBase', () {
    test('omite decimales cuando el precio es entero', () {
      expect(
        etiquetaPrecioBase(
          ConfigPrecio.fromJson({
            'precios_base': {'CUP': 1500},
            'moneda_default': 'CUP',
          }),
        ),
        '1500 CUP',
      );
      expect(
        etiquetaPrecioBase(
          ConfigPrecio.fromJson({
            'precios_base': {'USD': 60},
            'moneda_default': 'USD',
          }),
        ),
        '60 USD',
      );
    });

    test('conserva dos decimales cuando el precio no es entero', () {
      expect(
        etiquetaPrecioBase(
          ConfigPrecio.fromJson({
            'precios_base': {'USD': 2.5},
            'moneda_default': 'USD',
          }),
        ),
        '2.50 USD',
      );
    });

    test('devuelve null sin precio', () {
      expect(etiquetaPrecioBase(ConfigPrecio.fromJson({})), isNull);
      expect(etiquetaPrecioBase(null), isNull);
    });
  });
}
