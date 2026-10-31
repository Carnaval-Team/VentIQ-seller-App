import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/utils/vista_reservas.dart';

/// «Hoy» fijo para que los tests no dependan de la fecha de ejecución.
final hoy = DateTime(2026, 3, 15, 10, 30);

void main() {
  group('vistaReservasPorDefecto', () {
    test('abre en modo calendario', () {
      expect(vistaReservasPorDefecto(), VistaReservas.calendario);
    });
  });

  group('ultimoDiaDelMes', () {
    test('mes corriente', () {
      expect(ultimoDiaDelMes(DateTime(2026, 3, 15)), DateTime(2026, 3, 31));
    });

    test('febrero bisiesto', () {
      expect(ultimoDiaDelMes(DateTime(2028, 2, 3)), DateTime(2028, 2, 29));
    });

    test('febrero no bisiesto', () {
      expect(ultimoDiaDelMes(DateTime(2026, 2, 3)), DateTime(2026, 2, 28));
    });

    test('diciembre no desborda el año', () {
      expect(ultimoDiaDelMes(DateTime(2026, 12, 1)), DateTime(2026, 12, 31));
    });

    test('el resultado es siempre medianoche del último día', () {
      final fin = ultimoDiaDelMes(DateTime(2026, 3, 15, 23, 59, 59));
      expect(fin, DateTime(2026, 3, 31));
      expect(fin.hour, 0);
      expect(fin.minute, 0);
    });
  });

  group('rangoReservas — sin reservas', () {
    test('sin último día con reserva: mes de hoy completo', () {
      final r = rangoReservas(hoy: hoy);

      expect(r.firstDay, DateTime(2026, 3, 1));
      expect(r.lastDay, DateTime(2026, 3, 31));
    });

    test('null explícito se comporta igual que omitido', () {
      final r = rangoReservas(hoy: hoy, ultimoDiaConReserva: null);

      expect(r.firstDay, DateTime(2026, 3, 1));
      expect(r.lastDay, DateTime(2026, 3, 31));
    });

    test('la hora de «hoy» no afecta al rango', () {
      final temprano = rangoReservas(hoy: DateTime(2026, 3, 1, 0, 0, 1));
      final tarde = rangoReservas(hoy: DateTime(2026, 3, 31, 23, 59, 59));

      expect(temprano.firstDay, DateTime(2026, 3, 1));
      expect(temprano.lastDay, DateTime(2026, 3, 31));
      expect(tarde.firstDay, DateTime(2026, 3, 1));
      expect(tarde.lastDay, DateTime(2026, 3, 31));
    });
  });

  group('rangoReservas — un solo día', () {
    test('una reserva en el mes en curso no sale del mes', () {
      final r = rangoReservas(
        hoy: hoy,
        ultimoDiaConReserva: DateTime(2026, 3, 20),
      );

      expect(r.firstDay, DateTime(2026, 3, 1));
      expect(r.lastDay, DateTime(2026, 3, 31));
    });

    test('una reserva el mismo día de hoy', () {
      final r = rangoReservas(hoy: hoy, ultimoDiaConReserva: hoy);

      expect(r.firstDay, DateTime(2026, 3, 1));
      expect(r.lastDay, DateTime(2026, 3, 31));
    });

    test('el día de la reserva dentro del mes no recorta el rango', () {
      final r = rangoReservas(
        hoy: hoy,
        ultimoDiaConReserva: DateTime(2026, 3, 2),
      );

      expect(r.lastDay, DateTime(2026, 3, 31));
    });
  });

  group('rangoReservas — reservas solo en meses futuros', () {
    test('llega hasta el fin del mes del último dato', () {
      final r = rangoReservas(
        hoy: hoy,
        ultimoDiaConReserva: DateTime(2026, 8, 10),
      );

      expect(r.firstDay, DateTime(2026, 3, 1));
      expect(r.lastDay, DateTime(2026, 8, 31));
    });

    test('el mes más lejano manda', () {
      final r = rangoReservas(
        hoy: hoy,
        ultimoDiaConReserva: DateTime(2027, 3, 14),
      );

      expect(r.firstDay, DateTime(2026, 3, 1));
      expect(r.lastDay, DateTime(2027, 3, 31));
    });

    test('un dato en el último día del mes cubre el mes entero', () {
      final r = rangoReservas(
        hoy: hoy,
        ultimoDiaConReserva: DateTime(2026, 4, 30),
      );

      expect(r.lastDay, DateTime(2026, 4, 30));
    });
  });

  group('rangoReservas — cruce de año', () {
    test('diciembre con datos en enero', () {
      final r = rangoReservas(
        hoy: DateTime(2026, 12, 20),
        ultimoDiaConReserva: DateTime(2027, 1, 5),
      );

      expect(r.firstDay, DateTime(2026, 12, 1));
      expect(r.lastDay, DateTime(2027, 1, 31));
    });

    test('diciembre sin datos: se queda en el mes en curso', () {
      final r = rangoReservas(
        hoy: DateTime(2026, 12, 20),
        ultimoDiaConReserva: DateTime(2026, 12, 24),
      );

      expect(r.firstDay, DateTime(2026, 12, 1));
      expect(r.lastDay, DateTime(2026, 12, 31));
    });

    test('diciembre con datos en diciembre del año siguiente', () {
      final r = rangoReservas(
        hoy: DateTime(2026, 12, 1),
        ultimoDiaConReserva: DateTime(2027, 12, 31),
      );

      expect(r.firstDay, DateTime(2026, 12, 1));
      expect(r.lastDay, DateTime(2027, 12, 31));
    });

    test('enero con datos en febrero del mismo año', () {
      final r = rangoReservas(
        hoy: DateTime(2027, 1, 2),
        ultimoDiaConReserva: DateTime(2027, 2, 28),
      );

      expect(r.firstDay, DateTime(2027, 1, 1));
      expect(r.lastDay, DateTime(2027, 2, 28));
    });
  });

  group('rangoReservas — último dato anterior a hoy', () {
    test('un día del mes pasado devuelve el mes en curso', () {
      final r = rangoReservas(
        hoy: hoy,
        ultimoDiaConReserva: DateTime(2026, 2, 20),
      );

      expect(r.firstDay, DateTime(2026, 3, 1));
      expect(r.lastDay, DateTime(2026, 3, 31));
    });

    test('un dato de años atrás no recorta el rango', () {
      final r = rangoReservas(
        hoy: hoy,
        ultimoDiaConReserva: DateTime(2024, 6, 30),
      );

      expect(r.firstDay, DateTime(2026, 3, 1));
      expect(r.lastDay, DateTime(2026, 3, 31));
    });

    test('ayer (mismo mes) tampoco recorta por debajo del mes', () {
      final r = rangoReservas(
        hoy: hoy,
        ultimoDiaConReserva: DateTime(2026, 3, 14),
      );

      expect(r.firstDay, DateTime(2026, 3, 1));
      expect(r.lastDay, DateTime(2026, 3, 31));
    });
  });

  group('claveDia', () {
    test('rellena mes y día con ceros', () {
      expect(claveDia(DateTime(2026, 1, 2)), '2026-01-02');
      expect(claveDia(DateTime(2026, 12, 31)), '2026-12-31');
    });

    test('ignora la hora', () {
      expect(
        claveDia(DateTime(2026, 10, 27, 23, 59, 59)),
        claveDia(DateTime(2026, 10, 27)),
      );
    });

    test('coincide con el formato de la RPC', () {
      expect(claveDia(DateTime(2027, 3, 14)), '2027-03-14');
    });
  });

  group('agruparPorClaveDia', () {
    test('agrupa por día conservando el orden de entrada', () {
      final items = <DateTime>[
        DateTime(2026, 3, 2, 9),
        DateTime(2026, 3, 2, 18),
        DateTime(2026, 3, 5, 10),
      ];

      final agrupado = agruparPorClaveDia<DateTime>(items, (d) => d);

      expect(agrupado.keys.toList(), ['2026-03-02', '2026-03-05']);
      expect(agrupado['2026-03-02'], hasLength(2));
      expect(agrupado['2026-03-02']!.first.hour, 9);
      expect(agrupado['2026-03-02']!.last.hour, 18);
      expect(agrupado['2026-03-05'], hasLength(1));
    });

    test('lista vacía devuelve mapa vacío', () {
      final agrupado = agruparPorClaveDia<DateTime>(
        const <DateTime>[],
        (d) => d,
      );

      expect(agrupado, isEmpty);
    });

    test('acepta cualquier tipo con su extractor de fecha', () {
      final items = <Map<String, dynamic>>[
        {'id': 1, 'fecha': DateTime(2026, 3, 2)},
        {'id': 2, 'fecha': DateTime(2026, 3, 2)},
        {'id': 3, 'fecha': DateTime(2026, 4, 1)},
      ];

      final agrupado = agruparPorClaveDia<Map<String, dynamic>>(
        items,
        (m) => m['fecha'] as DateTime,
      );

      expect(agrupado['2026-03-02']!.map((m) => m['id']), [1, 2]);
      expect(agrupado['2026-04-01']!.single['id'], 3);
    });

    test('la misma fecha con horas distintas cae en la misma clave', () {
      final agrupado = agruparPorClaveDia<DateTime>([
        DateTime(2026, 3, 2, 1),
        DateTime(2026, 3, 2, 23),
      ], (d) => d);

      expect(agrupado, hasLength(1));
      expect(agrupado['2026-03-02'], hasLength(2));
    });
  });
}
