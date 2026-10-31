import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/models/tasa_cambio.dart';
import 'package:inventtia_flow/utils/conversion_precio.dart';
import 'package:inventtia_flow/utils/parse_monto.dart';

/// Matriz real de `flow.tasa_cambio.conversiones` (debug, 27-10-2026).
///
/// La base de datos ya entrega el cruce por CUP: `MLC → EUR` = 0,754184
/// (697,62 / 925), así que la app sólo LEE el factor; no lo calcula.
TasasDia _tasasReales() => TasasDia(
  fecha: DateTime(2026, 10, 27),
  hora: '07:00:06',
  vigente: true,
  conversiones: {
    'USD': {'USD': 1.0, 'CUP': 840.0, 'EUR': 0.908108, 'MLC': 1.2},
    'EUR': {'EUR': 1.0, 'CUP': 925.0, 'USD': 1.101189, 'MLC': 1.321728},
    'MLC': {'MLC': 1.0, 'CUP': 697.62, 'USD': 0.8305, 'EUR': 0.754184},
    'CUP': {'CUP': 1.0, 'USD': 0.00119, 'EUR': 0.001081, 'MLC': 0.001433},
  },
);

/// Configuración real por defecto: CUP sin decimales, divisas con dos.
int _decimalesDe(String moneda) => moneda == 'CUP' ? 0 : 2;

void main() {
  group('Redondeo — el precio escrito nunca se relee como millares', () {
    test('redondea a los decimales pedidos', () {
      expect(redondearPrecio(18.375, 2), 18.38);
      expect(redondearPrecio(18.375, 0), 18);
      expect(redondearPrecio(15435.4, 0), 15435);
      expect(redondearPrecio(0.908108 * 20, 2), 18.16);
    });

    test('texto quita ceros sobrantes y no deja punto colgando', () {
      expect(Redondeo.texto(18.5, 2), '18.5');
      expect(Redondeo.texto(840, 0), '840');
      expect(Redondeo.texto(18.375, 2), '18.38');
      expect(Redondeo.texto(1.0, 2), '1');
      expect(Redondeo.texto(0, 0), '0');
    });

    test('texto con 0-2 decimales SIEMPRE se relee igual', () {
      // El fallo que este helper evita: `18.375` (3 decimales) lo lee
      // `parseMonto` como 18375 (tres dígitos = millares).
      expect(parseMonto('18.375'), 18375);

      for (final valor in [18.375, 2.5, 840.0, 15435.4, 0.754184, 1234.567]) {
        for (var decimales = 0; decimales <= 2; decimales++) {
          final texto = Redondeo.texto(valor, decimales);
          expect(
            parseMonto(texto),
            redondearPrecio(valor, decimales),
            reason: 'texto "$texto" (valor $valor, $decimales decimales)',
          );
        }
      }
    });
  });

  group('factorDesde', () {
    test('sin tasas devuelve null, nunca 1', () {
      expect(factorDesde(null, 'USD', 'CUP'), isNull);
    });

    test('lee el factor directo', () {
      expect(factorDesde(_tasasReales(), 'USD', 'CUP'), 840);
      expect(factorDesde(_tasasReales(), 'EUR', 'CUP'), 925);
    });

    test('lee el cruce por CUP que ya trae la base de datos', () {
      // MLC → EUR = MLC→CUP / EUR→CUP = 697,62 / 925.
      expect(factorDesde(_tasasReales(), 'MLC', 'EUR'), closeTo(0.754184, 1e-9));
    });

    test('la identidad sólo existe si la matriz la trae', () {
      expect(factorDesde(_tasasReales(), 'USD', 'USD'), 1);
    });

    test('moneda sin tasa devuelve null (no se inventa el cruce)', () {
      expect(factorDesde(_tasasReales(), 'USD', 'GBP'), isNull);
      expect(factorDesde(_tasasReales(), 'GBP', 'USD'), isNull);
      final sinIdentidad = TasasDia(
        fecha: DateTime(2026, 10, 27),
        conversiones: const {
          'USD': {'CUP': 840.0},
        },
      );
      expect(factorDesde(sinIdentidad, 'USD', 'USD'), isNull);
    });
  });

  group('convertirPrecio', () {
    test('convierte y redondea con los decimales pedidos', () {
      expect(
        convertirPrecio(
          valor: 10,
          origen: 'USD',
          destino: 'CUP',
          tasas: _tasasReales(),
          decimales: 0,
        ),
        8400,
      );
      expect(
        convertirPrecio(
          valor: 18,
          origen: 'USD',
          destino: 'EUR',
          tasas: _tasasReales(),
          decimales: 2,
        ),
        16.35,
      );
    });

    test('sin tasa devuelve null, no 0 ni el mismo valor', () {
      expect(
        convertirPrecio(
          valor: 10,
          origen: 'USD',
          destino: 'CUP',
          tasas: null,
          decimales: 0,
        ),
        isNull,
      );
      expect(
        convertirPrecio(
          valor: 10,
          origen: 'USD',
          destino: 'GBP',
          tasas: _tasasReales(),
          decimales: 2,
        ),
        isNull,
        reason: 'sin tasa para GBP no se toca el precio',
      );
    });
  });

  group('convertirVarios', () {
    test('devuelve todas las monedas pedidas, con null donde no hay tasa', () {
      final out = convertirVarios(
        precios: {'USD': 18},
        origen: 'USD',
        monedas: ['USD', 'EUR', 'CUP', 'MLC', 'GBP'],
        tasas: _tasasReales(),
        decimalesDe: _decimalesDe,
      );
      expect(out.keys.toSet(), {'USD', 'EUR', 'CUP', 'MLC', 'GBP'});
      expect(out['USD'], 18);
      expect(out['EUR'], 16.35);
      expect(out['CUP'], 15120); // 18 × 840, sin decimales
      expect(out['MLC'], 21.6);
      expect(out['GBP'], isNull);
    });

    test('sin tasas todo es null (nunca 0)', () {
      final out = convertirVarios(
        precios: {'USD': 18},
        origen: 'USD',
        monedas: ['USD', 'EUR', 'CUP'],
        tasas: null,
        decimalesDe: _decimalesDe,
      );
      expect(out.values.every((v) => v == null), isTrue);
    });

    test('sin precio de origen todo es null', () {
      final out = convertirVarios(
        precios: {'EUR': 5},
        origen: 'USD',
        monedas: ['USD', 'CUP'],
        tasas: _tasasReales(),
        decimalesDe: _decimalesDe,
      );
      expect(out, {'USD': null, 'CUP': null});
    });

    test('redondea CUP a entero y divisas a dos decimales', () {
      final out = convertirVarios(
        precios: {'USD': 18.375},
        origen: 'USD',
        monedas: ['EUR', 'CUP'],
        tasas: _tasasReales(),
        decimalesDe: _decimalesDe,
      );
      expect(out['CUP'], 15435);
      expect(out['EUR'], 16.69);
    });

    test('preciosConvertidos es el mismo contrato que el plan', () {
      final out = preciosConvertidos(
        precios: {'CUP': 840},
        origen: 'CUP',
        monedas: ['USD'],
        tasas: _tasasReales(),
        decimalesDe: _decimalesDe,
      );
      expect(out['USD'], 1);
    });
  });
}