import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/services/fondo_inversion_service.dart';

/// La adaptación decide cuánto sale del fondo en una transferencia: es la
/// aritmética que, mal hecha, convertía 1.000 USD en 1 CUP (riesgo X2).
/// Por eso se prueba aparte, sin red ni Supabase.
void main() {
  group('adaptarTransferenciaV2', () {
    test('monto destino 1.000 con tasa 0,001 → 1,00 de origen y T = 1.000', () {
      final r = FondoInversionService.adaptarTransferenciaV2(
        montoDestino: 1000,
        tasa: 0.001,
      );
      expect(r.montoOrigen, 1.0);
      expect(r.tasaOrigenADestino, 1000.0);
    });

    test('el monto destino se recupera con la tasa que devuelve', () {
      final r = FondoInversionService.adaptarTransferenciaV2(
        montoDestino: 2000,
        tasa: 0.95,
      );
      expect(r.montoOrigen * r.tasaOrigenADestino, closeTo(2000, 0.01));
    });

    test('tasa 0, negativa o NaN cae a 1 y no revienta', () {
      for (final t in [0.0, -5.0, double.nan]) {
        final r = FondoInversionService.adaptarTransferenciaV2(
          montoDestino: 100,
          tasa: t,
        );
        expect(r.tasaOrigenADestino, 1.0, reason: 'tasa=$t');
        expect(r.montoOrigen, 100.0, reason: 'tasa=$t');
      }
    });

    test('redondea el monto de origen a dos decimales', () {
      final r = FondoInversionService.adaptarTransferenciaV2(
        montoDestino: 333.33,
        tasa: 1 / 3,
      );
      expect(r.montoOrigen, 111.11);
    });

    test('origen y destino en la misma moneda (tasa 1) no altera el monto', () {
      final r = FondoInversionService.adaptarTransferenciaV2(
        montoDestino: 1234.56,
        tasa: 1,
      );
      expect(r.montoOrigen, 1234.56);
      expect(r.tasaOrigenADestino, 1.0);
    });
  });
}