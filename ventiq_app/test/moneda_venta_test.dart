import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/services/moneda_venta_service.dart';

/// Resolución de la «moneda de venta» guardada en el teléfono.
///
/// Lo que se prueba aquí son las salvaguardas: que una moneda guardada que ya
/// no sirve NO se use a ciegas. Sin esto, un vendedor que cambia de tienda (o
/// una tienda que desactiva una divisa) se quedaría cobrando en una moneda que
/// la tienda ya no acepta.
void main() {
  group('MonedaVentaService.resolverCodigo', () {
    test('respeta la moneda guardada si sigue disponible', () {
      expect(
        MonedaVentaService.resolverCodigo(
          guardada: 'EUR',
          disponibles: ['CUP', 'USD', 'EUR'],
        ),
        'EUR',
      );
    });

    test('normaliza mayúsculas y espacios', () {
      expect(
        MonedaVentaService.resolverCodigo(
          guardada: ' eur ',
          disponibles: ['cup', ' eur '],
        ),
        'EUR',
      );
    });

    test('si la guardada ya no está, cae a la moneda base', () {
      expect(
        MonedaVentaService.resolverCodigo(
          guardada: 'EUR',
          disponibles: ['CUP', 'USD'],
        ),
        'CUP',
      );
    });

    test('sin nada guardado usa la base', () {
      expect(
        MonedaVentaService.resolverCodigo(
          guardada: null,
          disponibles: ['CUP', 'USD', 'EUR'],
        ),
        'CUP',
      );
    });

    test('si la tienda no acepta CUP usa la primera disponible', () {
      // Caso defensivo: la configuración por tienda debería impedirlo, pero
      // si ocurre no queremos devolver una moneda que la tienda no acepta.
      expect(
        MonedaVentaService.resolverCodigo(
          guardada: 'EUR',
          disponibles: ['USD', 'MLC'],
        ),
        'USD',
      );
    });

    test('lista vacía o con códigos inválidos cae a la base', () {
      expect(
        MonedaVentaService.resolverCodigo(guardada: 'EUR', disponibles: []),
        'CUP',
      );
      expect(
        MonedaVentaService.resolverCodigo(
          guardada: 'EUR',
          disponibles: ['eu', 'XX', ''],
        ),
        'CUP',
      );
    });
  });

  group('MonedaVentaService · conversión de precios', () {
    final tasas = <String, double>{'CUP': 1, 'USD': 900, 'EUR': 990};

    test('la moneda base no convierte', () {
      expect(
        MonedaVentaService.convertirDesdeBase(45000, codigo: 'CUP', tasas: tasas),
        45000,
      );
    });

    test('convierte dividiendo por la tasa', () {
      expect(
        MonedaVentaService.convertirDesdeBase(45000, codigo: 'USD', tasas: tasas),
        closeTo(50, 0.000001),
      );
      expect(
        MonedaVentaService.convertirDesdeBase(45000, codigo: 'EUR', tasas: tasas),
        closeTo(45.454545, 0.00001),
      );
    });

    test('sin tasa devuelve null: no se inventa una conversión', () {
      expect(
        MonedaVentaService.convertirDesdeBase(45000, codigo: 'GBP', tasas: tasas),
        isNull,
      );
      expect(
        MonedaVentaService.convertirDesdeBase(
          45000,
          codigo: 'EUR',
          tasas: const {'EUR': 0},
        ),
        isNull,
      );
    });
  });
}