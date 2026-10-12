import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/models/disponibilidad_dia.dart';
import 'package:inventtia_flow/models/recurso.dart';

/// Hora de inicio y fin de un turno (punto 7 del plan).
///
/// Es sólo presentación: no cambia cupo ni reserva. Pero las tres pantallas que
/// la muestran (config de recursos del admin, ficha del cliente y selector de
/// turno) tienen que decir exactamente lo mismo, y por eso la etiqueta vive en
/// una única función pura.
void main() {
  group('etiquetaHoraTurno', () {
    test('con las dos horas devuelve un rango', () {
      expect(etiquetaHoraTurno('09:00', '11:00'), '09:00 – 11:00');
    });

    test('con una sola hora devuelve esa hora', () {
      expect(etiquetaHoraTurno('09:00', null), '09:00');
      expect(etiquetaHoraTurno(null, '11:00'), '11:00');
    });

    test('sin horas no hay etiqueta', () {
      expect(etiquetaHoraTurno(null, null), isNull);
    });

    test('una hora vacía o con espacios cuenta como ausente', () {
      expect(etiquetaHoraTurno('', ''), isNull);
      expect(etiquetaHoraTurno('  ', null), isNull);
      expect(etiquetaHoraTurno(' 09:00 ', ' 11:00 '), '09:00 – 11:00');
    });
  });

  group('Turno.fromJson', () {
    test('lee las horas tal como las manda la RPC (`HH24:MI`)', () {
      final t = Turno.fromJson({
        'id': 1,
        'nombre': 'Mañana',
        'hora_inicio': '09:00',
        'hora_fin': '11:00',
      });
      expect(t.horaInicio, '09:00');
      expect(t.horaFin, '11:00');
      expect(t.etiquetaHora, '09:00 – 11:00');
    });

    test('normaliza `09:00:00` de una consulta directa a la tabla', () {
      final t = Turno.fromJson({
        'id': 1,
        'nombre': 'Mañana',
        'hora_inicio': '09:00:00',
        'hora_fin': '11:30:00',
      });
      expect(t.etiquetaHora, '09:00 – 11:30');
    });

    test('una hora ilegible no rompe el turno: queda sin hora', () {
      final t = Turno.fromJson({
        'id': 1,
        'nombre': 'Mañana',
        'hora_inicio': 'por la mañana',
        'hora_fin': '25:99',
      });
      expect(t.horaInicio, isNull);
      expect(t.horaFin, isNull);
      expect(t.etiquetaHora, isNull);
      // El resto del turno se conserva.
      expect(t.nombre, 'Mañana');
    });

    test('sin columnas de hora el turno sigue siendo válido', () {
      final t = Turno.fromJson({'id': 2, 'nombre': 'Solo ida'});
      expect(t.etiquetaHora, isNull);
    });

    test('conserva precios y tramos', () {
      final t = Turno.fromJson({
        'id': 3,
        'nombre': 'Ida y vuelta',
        'precios': {'USD': 12.5},
        'tramos': [7, 8],
      });
      expect(t.precios['USD'], 12.5);
      expect(t.tramosIds, [7, 8]);
    });
  });

  group('TurnoDisponible', () {
    test('lee las horas que añade la migración 42', () {
      final t = TurnoDisponible.fromJson({
        'id_recurso': 1,
        'recurso': 'Carro 1',
        'id_turno': 5,
        'turno': 'Ida',
        'disponibles': 3,
        'hora_inicio': '07:00',
        'hora_fin': '09:30',
      });
      expect(t.etiquetaHora, '07:00 – 09:30');
    });

    test('acepta `HH:MM:SS` y descarta lo que no sea hora', () {
      final t = TurnoDisponible.fromJson({
        'id_recurso': 1,
        'id_turno': 5,
        'hora_inicio': '07:00:00',
        'hora_fin': 'tarde',
      });
      expect(t.horaInicio, '07:00');
      expect(t.horaFin, isNull);
      expect(t.etiquetaHora, '07:00');
    });

    test('sin horas (migración 42 sin aplicar) no muestra nada raro', () {
      final t = TurnoDisponible.fromJson({
        'id_recurso': 1,
        'id_turno': 5,
        'turno': 'Mañana',
        'disponibles': 1,
      });
      expect(t.etiquetaHora, isNull);
      expect(t.turno, 'Mañana');
    });
  });
}
