import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/services/compras_costos_calculo.dart';

void main() {
  group('ComprasCostosCalculo · ajustes por unidad', () {
    test('5.000 de ajuste sobre 25.000 unidades = 0,20 por unidad', () {
      expect(
        ComprasCostosCalculo.ajustesPorUnidad(
          ajustesTotal: 5000,
          cantidadTotal: 25000,
        ),
        closeTo(0.20, 1e-9),
      );
    });

    test('sin cantidad o sin ajuste devuelve 0, nunca infinito', () {
      expect(
        ComprasCostosCalculo.ajustesPorUnidad(
          ajustesTotal: 100,
          cantidadTotal: 0,
        ),
        0,
      );
      expect(
        ComprasCostosCalculo.ajustesPorUnidad(
          ajustesTotal: 0,
          cantidadTotal: 10,
        ),
        0,
      );
    });

    test('el costo de 0,50 sube a 0,70 con 0,20 de ajuste', () {
      expect(
        ComprasCostosCalculo.costoUnitarioAterrizado(
          costoUnitario: 0.50,
          ajustesTotal: 0.20,
          cantidadTotal: 1,
        ),
        closeTo(0.70, 1e-9),
      );
    });

    test('agua 0,50 con 5.000 de flete sobre 25.000 unidades', () {
      expect(
        ComprasCostosCalculo.costoUnitarioAterrizado(
          costoUnitario: 0.50,
          ajustesTotal: 5000,
          cantidadTotal: 25000,
        ),
        closeTo(0.70, 1e-9),
      );
    });
  });

  group('ComprasCostosCalculo · reparto por cantidad', () {
    test('9.000 entre 5.000 y 20.000 unidades', () {
      final cuotas = ComprasCostosCalculo.repartirPorCantidad(
        cantidades: [5000, 20000],
        monto: 9000,
      );
      expect(cuotas[0], closeTo(1800, 0.001));
      expect(cuotas[1], closeTo(7200, 0.001));
      expect(cuotas[0] + cuotas[1], closeTo(9000, 0.001));
    });

    test('el residuo de centavos va a la línea de mayor cantidad', () {
      final cuotas = ComprasCostosCalculo.repartirPorCantidad(
        cantidades: [100, 100, 100],
        monto: 100,
      );
      expect(cuotas.reduce((a, b) => a + b), closeTo(100, 0.001));
      expect(cuotas[0], closeTo(33.34, 0.001));
      expect(cuotas[1], closeTo(33.33, 0.001));
      expect(cuotas[2], closeTo(33.33, 0.001));
    });

    test('suma exacta con muchas líneas desiguales', () {
      final cuotas = ComprasCostosCalculo.repartirPorCantidad(
        cantidades: [1, 2, 3, 7, 11],
        monto: 123.45,
      );
      final suma = cuotas.fold<double>(0, (s, c) => s + c);
      expect(suma, closeTo(123.45, 0.001));
    });

    test('sin cantidades o sin monto no reparte nada', () {
      expect(
        ComprasCostosCalculo.repartirPorCantidad(cantidades: [], monto: 100),
        isEmpty,
      );
      expect(
        ComprasCostosCalculo.repartirPorCantidad(
          cantidades: [10, 20],
          monto: 0,
        ),
        [0.0, 0.0],
      );
    });
  });
}
