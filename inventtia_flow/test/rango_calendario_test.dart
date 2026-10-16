import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/utils/rango_calendario.dart';

/// "Hoy" fijo para que los tests no dependan de la fecha de ejecución.
/// 2026-03-15 → el mes actual es marzo de 2026.
final ahora = DateTime(2026, 3, 15, 10, 30);

int mesesEntre(DateTime desde, DateTime hasta) =>
    (hasta.year - desde.year) * 12 + (hasta.month - desde.month);

void main() {
  group('lista vacía', () {
    test('modo espera: mes actual + 12 meses de horizonte', () {
      final r = rangoCalendario(
        diasDisponibles: const [],
        paraEspera: true,
        ahora: ahora,
      );

      expect(r.firstDay, DateTime(2026, 3, 1));
      // Fin del mes actual + 12 → marzo de 2027.
      expect(r.lastDay, DateTime(2027, 3, 31));
      expect(mesesEntre(r.firstDay, r.lastDay), 12);
    });

    test('modo reserva: mes actual + 6 meses de horizonte', () {
      final r = rangoCalendario(
        diasDisponibles: const [],
        paraEspera: false,
        ahora: ahora,
      );

      expect(r.firstDay, DateTime(2026, 3, 1));
      expect(r.lastDay, DateTime(2026, 9, 30));
      expect(mesesEntre(r.firstDay, r.lastDay), 6);
    });
  });

  group('un solo día del mes actual', () {
    test('modo espera: no se queda a fin de mes, hay 12 meses', () {
      final r = rangoCalendario(
        diasDisponibles: [DateTime(2026, 3, 20)],
        paraEspera: true,
        ahora: ahora,
      );

      expect(r.firstDay, DateTime(2026, 3, 1));
      // Antes del arreglo el último día era 2026-03-31 y el PageView rebotaba.
      expect(r.lastDay.isAfter(DateTime(2026, 3, 31)), isTrue);
      expect(r.lastDay, DateTime(2027, 3, 31));
    });

    test('modo reserva: 6 meses de horizonte', () {
      final r = rangoCalendario(
        diasDisponibles: [DateTime(2026, 3, 20)],
        paraEspera: false,
        ahora: ahora,
      );

      expect(r.firstDay, DateTime(2026, 3, 1));
      expect(r.lastDay, DateTime(2026, 9, 30));
    });
  });

  group('días solo del mes actual', () {
    final soloMarzo = [
      DateTime(2026, 3, 5),
      DateTime(2026, 3, 12),
      DateTime(2026, 3, 28),
    ];

    test('modo espera: horizonte de al menos 12 meses navegables', () {
      final r = rangoCalendario(
        diasDisponibles: soloMarzo,
        paraEspera: true,
        ahora: ahora,
      );

      expect(r.firstDay, DateTime(2026, 3, 1));
      expect(mesesEntre(r.firstDay, r.lastDay) >= 12, isTrue);
      // El mes siguiente al de los datos debe quedar navegable.
      expect(r.lastDay.isAfter(DateTime(2026, 4, 1)), isTrue);
    });

    test('modo reserva: horizonte de al menos 6 meses navegables', () {
      final r = rangoCalendario(
        diasDisponibles: soloMarzo,
        paraEspera: false,
        ahora: ahora,
      );

      expect(r.firstDay, DateTime(2026, 3, 1));
      expect(mesesEntre(r.firstDay, r.lastDay) >= 6, isTrue);
      expect(r.lastDay.isAfter(DateTime(2026, 4, 1)), isTrue);
    });
  });

  group('datos que empiezan en un mes futuro', () {
    final futuros = [
      DateTime(2026, 8, 10),
      DateTime(2026, 8, 11),
      DateTime(2026, 10, 2),
    ];

    test('el rango arranca en el mes actual, no en el mes con datos', () {
      final r = rangoCalendario(
        diasDisponibles: futuros,
        paraEspera: false,
        ahora: ahora,
      );

      expect(r.firstDay, DateTime(2026, 3, 1));
      // El último dato (octubre) manda porque supera el horizonte de 6 meses.
      expect(r.lastDay, DateTime(2026, 10, 31));
    });

    test('en modo espera el horizonte (marzo+12) supera al último dato', () {
      final r = rangoCalendario(
        diasDisponibles: futuros,
        paraEspera: true,
        ahora: ahora,
      );

      expect(r.firstDay, DateTime(2026, 3, 1));
      expect(r.lastDay, DateTime(2027, 3, 31));
    });
  });

  group('primer día disponible antes del mes actual', () {
    test('firstDay se ancla al mes de ese primer día', () {
      final r = rangoCalendario(
        diasDisponibles: [
          DateTime(2025, 12, 24),
          DateTime(2026, 1, 8),
          DateTime(2026, 3, 10),
        ],
        paraEspera: false,
        ahora: ahora,
      );

      expect(r.firstDay, DateTime(2025, 12, 1));
      expect(r.lastDay, DateTime(2026, 9, 30));
    });

    test('un dato suelto aún más antiguo tampoco queda fuera', () {
      final r = rangoCalendario(
        diasDisponibles: [
          DateTime(2026, 3, 10),
          DateTime(2025, 6, 30),
        ],
        paraEspera: true,
        ahora: ahora,
      );

      expect(r.firstDay, DateTime(2025, 6, 1));
      expect(r.lastDay, DateTime(2027, 3, 31));
    });
  });

  group('robustez', () {
    test('el orden de la lista no importa', () {
      final desordenado = [
        DateTime(2026, 10, 2),
        DateTime(2026, 8, 11),
        DateTime(2026, 8, 10),
      ];

      final r = rangoCalendario(
        diasDisponibles: desordenado,
        paraEspera: false,
        ahora: ahora,
      );

      expect(r.firstDay, DateTime(2026, 3, 1));
      expect(r.lastDay, DateTime(2026, 10, 31));
    });

    test('firstDay y lastDay siempre son extremos de mes completos', () {
      final r = rangoCalendario(
        diasDisponibles: [DateTime(2026, 7, 4)],
        paraEspera: true,
        ahora: ahora,
      );

      expect(r.firstDay.day, 1);
      expect(
        r.lastDay,
        DateTime(r.lastDay.year, r.lastDay.month + 1, 0),
      );
    });

    test('el rango cruza el fin de año sin desbordar', () {
      final diciembre = DateTime(2026, 12, 20, 9);
      final r = rangoCalendario(
        diasDisponibles: [DateTime(2026, 12, 20)],
        paraEspera: true,
        ahora: diciembre,
      );

      expect(r.firstDay, DateTime(2026, 12, 1));
      expect(r.lastDay, DateTime(2027, 12, 31));
    });
  });
}
