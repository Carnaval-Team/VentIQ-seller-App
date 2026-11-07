import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/models/fondo_inversion.dart';

void main() {
  test('asigna enteros por porcentaje sin dar el sobrante al último', () {
    expect(repartirGanancia(100, [60, 40]), [60, 40]);
    expect(repartirGanancia(100, [33.3333, 33.3333, 33.3334]), [33, 33, 33]);
    expect(repartirGanancia(0.99, [100]), [0]);
    expect(repartirGanancia(10.99, [100]), [10]);
    expect(repartirGanancia(0, [100]), [0]);
  });

  test('partes iguales no exige que los porcentajes sumen 100', () {
    expect(repartirGanancia(100.99, [30, 30, 30], repartirIgual: true), [
      33,
      33,
      33,
    ]);
    expect(repartirGanancia(99, [10, 20, 30], repartirIgual: true), [
      33,
      33,
      33,
    ]);
    expect(repartirGanancia(2, [50, 50, 50], repartirIgual: true), [0, 0, 0]);
  });

  test('rechaza participaciones incompletas, excesivas o inválidas', () {
    for (final porcentajes in <List<double>>[
      [],
      [60, 30],
      [60, 50],
      [-10, 110],
      [double.nan],
    ]) {
      expect(() => repartirGanancia(100, porcentajes), throwsArgumentError);
    }
    expect(() => repartirGanancia(-1, [100]), throwsArgumentError);
    expect(() => repartirGanancia(0.999, [100]), throwsArgumentError);
  });

  test('conserva cada moneda y deja toda la diferencia al fondo', () {
    final cup = repartirGanancia(125.23, [45, 55]);
    final usd = repartirGanancia(3.17, [45, 55]);
    expect(cup, [56, 68]);
    expect(usd, [1, 1]);
    expect(125.23 - cup.reduce((a, b) => a + b), closeTo(1.23, 0.000001));
    expect(3.17 - usd.reduce((a, b) => a + b), closeTo(1.17, 0.000001));
    for (var cents = 0; cents < 10000; cents += 17) {
      final monto = cents / 100;
      for (final igual in [false, true]) {
        final partes = repartirGanancia(monto, [
          33.3333,
          33.3333,
          33.3334,
        ], repartirIgual: igual);
        expect(partes.every((p) => p == p.truncateToDouble()), isTrue);
        expect(partes.reduce((a, b) => a + b), lessThanOrEqualTo(monto));
      }
    }
  });
}
