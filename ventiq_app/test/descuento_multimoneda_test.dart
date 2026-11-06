import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/utils/price_utils.dart';

/// Tests del arreglo del descuento manual (`OrderService`, Fase 3).
///
/// El bug: al aplicar un descuento se ordenaban los pagos por `monto` NATIVO
/// (comparar CUP con USD no significa nada) y se escribía `monto = precioFinal`
/// (un importe en CUP) sin tocar `moneda`, `tasa_usd` ni
/// `monto_cup_equivalente`. En una venta en USD grababa 40.500 CUP como si
/// fueran dólares y desincronizaba el equivalente.
void main() {
  group('PriceUtils.ajustarPagoPorDescuento', () {
    test('CUP: el importe nativo baja exactamente el descuento', () {
      final pago = <String, dynamic>{'monto': 1000, 'moneda': 'CUP'};

      final r = PriceUtils.ajustarPagoPorDescuento(
        pago,
        montoDescontado: 100,
        montoBaseTotal: 1000,
      );

      expect(r.montoNativo, 900);
      expect(r.equivalenteBase, 900);
      expect(r.baseNativo, 1000);
    });

    test('USD: el importe nativo se recalcula con la tasa, NO en CUP', () {
      // 50 USD × 900 = 45.000 CUP. Descuento de 4.500 CUP.
      final pago = <String, dynamic>{
        'monto': 50,
        'moneda': 'USD',
        'tasa_usd': 900,
        'monto_cup_equivalente': 45000,
      };

      final r = PriceUtils.ajustarPagoPorDescuento(
        pago,
        montoDescontado: 4500,
        montoBaseTotal: 45000,
      );

      expect(r.equivalenteBase, 40500);
      // Este `expect` es el bug: antes se escribía 40500 como importe en USD.
      expect(r.montoNativo, closeTo(45, 0.000001));
      expect(r.baseNativo, closeTo(50, 0.000001));
      // Invariante que debe cumplir siempre la fila guardada:
      expect(r.montoNativo * 900, closeTo(r.equivalenteBase, 0.000001));
    });

    test('USD sin tasa_usd: la deriva del equivalente guardado', () {
      // 10 USD → 9.000 CUP ⇒ tasa 900. Descuento de 900 CUP.
      final pago = <String, dynamic>{
        'monto': 10,
        'moneda': 'USD',
        'monto_cup_equivalente': 9000,
      };

      final r = PriceUtils.ajustarPagoPorDescuento(
        pago,
        montoDescontado: 900,
        montoBaseTotal: 9000,
      );

      expect(r.equivalenteBase, 8100);
      expect(r.montoNativo, closeTo(9, 0.000001));
      expect(r.baseNativo, closeTo(10, 0.000001));
    });

    test('divisa sin tasa: corrige el equivalente pero no inventa el importe', () {
      final pago = <String, dynamic>{'monto': 5, 'moneda': 'EUR'};

      final r = PriceUtils.ajustarPagoPorDescuento(
        pago,
        montoDescontado: 2,
        montoBaseTotal: 5,
      );

      expect(r.montoNativo, 5); // se conserva: no hay tasa con la que dividir
      expect(r.equivalenteBase, 3);
    });

    test('un descuento mayor que el pago no produce importes negativos', () {
      final pago = <String, dynamic>{'monto': 500, 'moneda': 'CUP'};

      final r = PriceUtils.ajustarPagoPorDescuento(
        pago,
        montoDescontado: 900,
        montoBaseTotal: 500,
      );

      expect(r.montoNativo, 0);
      expect(r.equivalenteBase, 0);
    });

    test('regresión: los totales de una venta mixta no cambian', () {
      final pagos = <Map<String, dynamic>>[
        {'monto': 420, 'moneda': 'CUP'},
        {'monto': 2, 'moneda': 'USD', 'tasa_usd': 420},
      ];

      expect(PriceUtils.paymentTotalCup(pagos), 1260);
      expect(PriceUtils.paymentTotalUsd(pagos), 2);
    });
  });
}
