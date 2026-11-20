import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/money/checkout_totales_moneda.dart';

void main() {
  double tasa(String moneda) => const {'CUP': 1.0, 'USD': 400.0}[moneda] ?? 0;

  group('CheckoutTotalesMoneda', () {
    test('cobro mezclado se desglosa por moneda sin sumarlas', () {
      final importes = CheckoutTotalesMoneda.desdeLineas(
        [
          (cup: 800.0, moneda: 'USD'),
          (cup: 500.0, moneda: 'CUP'),
          (cup: 400.0, moneda: 'USD'),
        ],
        tasa: tasa,
        base: 'CUP',
      );
      expect(importes, {'USD': closeTo(3.0, 1e-9), 'CUP': 500.0});
    });

    test('el descuento promocional se reparte en cada moneda', () {
      final sub = CheckoutTotalesMoneda.desdeLineas(
        [(cup: 800.0, moneda: 'USD'), (cup: 200.0, moneda: 'CUP')],
        tasa: tasa,
        base: 'CUP',
      );
      final total = CheckoutTotalesMoneda.desdeLineas(
        [(cup: 800.0, moneda: 'USD'), (cup: 200.0, moneda: 'CUP')],
        tasa: tasa,
        base: 'CUP',
        factor: 0.9,
      );
      expect(total, {'USD': closeTo(1.8, 1e-9), 'CUP': closeTo(180, 1e-9)});
      expect(CheckoutTotalesMoneda.diferencia(sub, total), {
        'USD': closeTo(0.2, 1e-9),
        'CUP': closeTo(20, 1e-9),
      });
    });

    test('moneda sin tasa queda en la moneda base', () {
      final importes = CheckoutTotalesMoneda.desdeLineas(
        [(cup: 300.0, moneda: 'EUR'), (cup: 100.0, moneda: 'CUP')],
        tasa: tasa,
        base: 'CUP',
      );
      expect(importes, {'CUP': 400.0});
    });

    test('desglose editado usa los importes nativos de cada pago', () {
      final importes = CheckoutTotalesMoneda.desdePagos([
        {'id_medio_pago': 1, 'moneda': 'USD', 'monto': 2.5, 'tasa_cambio': 400},
        {'id_medio_pago': 2, 'moneda': 'CUP', 'monto': 150},
        {'id_medio_pago': 3, 'moneda': 'USD', 'monto': 0.5, 'tasa_cambio': 400},
      ]);
      expect(importes, {'USD': 3.0, 'CUP': 150.0});
    });

    test('formato: una línea por moneda en el orden de la tienda', () {
      final texto = CheckoutTotalesMoneda.formatear(
        {'CUP': 500.0, 'USD': 3.0},
        orden: const ['USD', 'CUP'],
        base: 'CUP',
      );
      expect(texto.split('\n'), ['3.00 USD', '500.00 CUP']);
      expect(
        CheckoutTotalesMoneda.formatear(
          {'USD': 0.2},
          orden: const ['CUP'],
          base: 'CUP',
          prefijo: '-',
        ),
        '-0.20 USD',
      );
      expect(
        CheckoutTotalesMoneda.formatear({}, orden: const [], base: 'CUP'),
        '0.00 CUP',
      );
    });
  });

  test('el checkout muestra resumen, subtotal y total final por moneda', () {
    final fuente =
        File('lib/screens/checkout_screen.dart').readAsStringSync();
    expect(fuente, isNot(contains('_formatCheckoutAmount(subtotal)')));
    expect(fuente, isNot(contains('_formatCheckoutAmount(finalTotal)')));
    expect(fuente, contains('_formatImportesPorMoneda(subtotales)'));
    expect(fuente, contains('_formatImportesPorMoneda(totales)'));
    expect(
      fuente,
      contains('if (_esV1) return TicketV1.totalesNativos(widget.order);'),
    );
    expect(fuente, contains('TicketV1.equivalenteCupOrden(widget.order)'));
  });
}
