import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/utils/price_utils.dart';

/// Cimientos de la Fase 3: que la moneda deje de colapsarse a CUP/USD.
///
/// El bug original era `paymentCurrency` devolviendo `'USD'` o `'CUP'` y nada
/// más, con lo que una fila `EUR` se leía como CUP en todo el flujo (listados,
/// tickets, arqueo y la guarda de idempotencia de pagos).
void main() {
  group('price_utils · moneda genérica', () {
    test('paymentCurrency NO colapsa otras divisas a CUP', () {
      expect(PriceUtils.paymentCurrency({'moneda': 'EUR'}), 'EUR');
      expect(PriceUtils.paymentCurrency({'moneda': 'eur'}), 'EUR');
      expect(PriceUtils.paymentCurrency({'moneda': 'MLC'}), 'MLC');
      expect(PriceUtils.paymentCurrency({'currency': 'USD'}), 'USD');
    });

    test('paymentCurrency cae a CUP si falta o no es ISO-4217', () {
      expect(PriceUtils.paymentCurrency({}), 'CUP');
      expect(PriceUtils.paymentCurrency({'moneda': ''}), 'CUP');
      expect(PriceUtils.paymentCurrency({'moneda': 'eu'}), 'CUP');
      expect(PriceUtils.paymentCurrency({'moneda': 'EUROS'}), 'CUP');
      expect(PriceUtils.paymentCurrency({'moneda': '???'}), 'CUP');
    });

    test('paymentRate prioriza tasa_cambio sobre tasa_usd', () {
      final pago = <String, dynamic>{
        'monto': 10,
        'moneda': 'EUR',
        'tasa_cambio': 990,
        'tasa_usd': 900,
      };
      expect(PriceUtils.paymentRate(pago), 990);
    });

    test('paymentRate usa tasa_usd cuando no hay tasa_cambio', () {
      final pago = <String, dynamic>{
        'monto': 10,
        'moneda': 'USD',
        'tasa_usd': 900,
      };
      expect(PriceUtils.paymentRate(pago), 900);
    });

    test('paymentRate deriva del equivalente guardado', () {
      final pago = <String, dynamic>{
        'monto': 10,
        'moneda': 'USD',
        'monto_cup_equivalente': 9000,
      };
      expect(PriceUtils.paymentRate(pago), closeTo(900, 0.000001));
    });

    test('paymentCupEquivalent convierte cualquier divisa, no solo USD', () {
      final eur = <String, dynamic>{
        'monto': 5,
        'moneda': 'EUR',
        'tasa_cambio': 1200,
      };
      expect(PriceUtils.paymentCupEquivalent(eur), closeTo(6000, 0.000001));

      final cup = <String, dynamic>{'monto': 1000, 'moneda': 'CUP'};
      expect(PriceUtils.paymentCupEquivalent(cup), 1000);
    });

    test('una venta 100% en EUR se rotula EUR, no CUP', () {
      final pagos = <Map<String, dynamic>>[
        {'monto': 5, 'moneda': 'EUR', 'tasa_cambio': 1200},
      ];
      expect(PriceUtils.paymentDisplayCurrency(pagos), 'EUR');

      final ticket = PriceUtils.formatTicketMoney(6000, pagos);
      expect(ticket, contains('EUR'));
      expect(ticket, isNot(contains('CUP')));
    });

    test('paymentTotalIn suma solo la divisa pedida', () {
      final pagos = <Map<String, dynamic>>[
        {'monto': 1000, 'moneda': 'CUP'},
        {'monto': 20, 'moneda': 'USD', 'tasa_cambio': 900},
        {'monto': 5, 'moneda': 'EUR', 'tasa_cambio': 1200},
      ];
      expect(PriceUtils.paymentTotalIn(pagos, 'USD'), 20);
      expect(PriceUtils.paymentTotalIn(pagos, 'EUR'), 5);
      expect(PriceUtils.paymentTotalIn(pagos, 'CUP'), 1000);
      // Consolidado: 1.000 + 20×900 + 5×1.200
      expect(PriceUtils.paymentTotalCup(pagos), 25000);
    });

    test('una venta mixta se presenta en la moneda base', () {
      final pagos = <Map<String, dynamic>>[
        {'monto': 1000, 'moneda': 'CUP'},
        {'monto': 20, 'moneda': 'USD', 'tasa_cambio': 900},
      ];
      expect(PriceUtils.paymentDisplayCurrency(pagos), 'CUP');
    });

    test('normalizePaymentMap unifica tasa_cambio y tasa_usd', () {
      final sinCambio = PriceUtils.normalizePaymentMap(<String, dynamic>{
        'monto': 10,
        'moneda': 'USD',
        'tasa_usd': 900,
      });
      expect(sinCambio['tasa_cambio'], 900);

      final sinUsd = PriceUtils.normalizePaymentMap(<String, dynamic>{
        'monto': 10,
        'moneda': 'USD',
        'tasa_cambio': 900,
      });
      expect(sinUsd['tasa_usd'], 900);
    });
  });
}