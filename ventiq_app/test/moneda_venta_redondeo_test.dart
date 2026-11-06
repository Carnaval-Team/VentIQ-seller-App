import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/services/moneda_venta_service.dart';

/// Regla de redondeo (b) al cobrar en una divisa distinta de la base.
///
/// El problema que resuelve: los precios están en CUP. Si se convierte y se
/// redondea a la baja, el importe cobrado × tasa queda por debajo del total de
/// la venta y la operación se queda `es_pagada = false`. Redondeando hacia
/// arriba el equivalente siempre cubre el total.
void main() {
  group('redondearAlza', () {
    test('sube al céntimo superior', () {
      expect(
        MonedaVentaService.redondearAlza(45.454545, decimales: 2),
        closeTo(45.46, 0.000001),
      );
    });

    test('un importe exacto NO sube un céntimo de más', () {
      expect(MonedaVentaService.redondearAlza(50, decimales: 2), 50);
      expect(MonedaVentaService.redondearAlza(45.46, decimales: 2), 45.46);
    });

    test('el ruido de coma flotante no provoca un céntimo extra', () {
      // 5000.000000000001 en escalado no debe convertirse en 5001.
      expect(
        MonedaVentaService.redondearAlza(50.0, decimales: 2),
        closeTo(50.0, 1e-9),
      );
    });

    test('cero y negativos devuelven cero', () {
      expect(MonedaVentaService.redondearAlza(0), 0);
      expect(MonedaVentaService.redondearAlza(-5), 0);
    });

    test('respeta los decimales de la divisa', () {
      expect(
        MonedaVentaService.redondearAlza(45.4545, decimales: 0),
        closeTo(46, 1e-9),
      );
    });
  });

  group('montoParaCubrir', () {
    final tasas = <String, double>{'CUP': 1, 'USD': 900, 'EUR': 990};

    test('CUP: sin redondeo ni conversión', () {
      final r = MonedaVentaService.montoParaCubrir(
        45000,
        codigo: 'CUP',
        tasas: tasas,
      );
      expect(r!.montoNativo, 45000);
      expect(r.equivalenteBase, 45000);
    });

    test('USD exacto: no añade céntimos', () {
      final r = MonedaVentaService.montoParaCubrir(
        45000,
        codigo: 'USD',
        tasas: tasas,
      );
      expect(r!.montoNativo, closeTo(50, 1e-9));
      expect(r.equivalenteBase, closeTo(45000, 1e-6));
    });

    test('EUR: redondea al alza y el equivalente CUBRE el total', () {
      final r = MonedaVentaService.montoParaCubrir(
        45000,
        codigo: 'EUR',
        tasas: tasas,
      );
      expect(r!.montoNativo, closeTo(45.46, 1e-9));
      // Invariante clave: nunca por debajo del total de la venta.
      expect(r.equivalenteBase, greaterThanOrEqualTo(45000));
      // Y el equivalente coincide con lo que la base guardará: monto × tasa.
      expect(r.equivalenteBase, closeTo(r.montoNativo * 990, 1e-6));
    });

    test('sin tasa devuelve null (no se inventa la conversión)', () {
      expect(
        MonedaVentaService.montoParaCubrir(45000, codigo: 'GBP', tasas: tasas),
        isNull,
      );
    });
  });
}