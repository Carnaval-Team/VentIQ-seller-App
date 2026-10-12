import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/models/disponibilidad_dia.dart';
import 'package:inventtia_flow/utils/turnos_servicio.dart';

/// Día de prueba, con la fecha desplazada [dias] desde hoy.
DisponibilidadDia _dia(
  int dias, {
  int disponibles = 5,
  List<TurnoDisponible> turnos = const [],
}) {
  final hoy = DateTime.now();
  return DisponibilidadDia(
    fecha: DateTime(hoy.year, hoy.month, hoy.day).add(Duration(days: dias)),
    cantidad: 10,
    agendados: 10 - disponibles,
    disponibles: disponibles,
    turnos: turnos,
  );
}

TurnoDisponible _turno({
  int id = 1,
  String nombre = 'Mañana',
  String recurso = 'Carro 1',
  int disponibles = 3,
}) => TurnoDisponible(
  idRecurso: 3,
  recurso: recurso,
  idTurno: id,
  turno: nombre,
  disponibles: disponibles,
);

void main() {
  group('diaDeTurnosAMostrar', () {
    test('sin días no hay turnos que enseñar', () {
      expect(diaDeTurnosAMostrar(const []), isNull);
    });

    test('un servicio sin turnos (cupo por día) no tiene sección', () {
      // `turnos` vacío = el servicio no usa recursos: la disponibilidad es un
      // número por día, no una lista de turnos.
      final dia = _dia(0);
      expect(dia.tieneTurnos, isFalse);
      expect(diaDeTurnosAMostrar([dia]), isNull);
    });

    test('prefiere el primer día con cupo aunque antes haya llenos', () {
      // El primer día tiene turnos, pero todos sin cupo: enseñarlo daría la
      // impresión de que el servicio está agotado cuando sí hay hueco después.
      final lleno = _dia(0, disponibles: 0, turnos: [_turno(disponibles: 0)]);
      final libre = _dia(
        2,
        disponibles: 4,
        turnos: [_turno(id: 2, disponibles: 4)],
      );

      final elegido = diaDeTurnosAMostrar([lleno, libre]);
      expect(elegido, same(libre));
    });

    test('si ningún turno tiene cupo devuelve el primero con turnos', () {
      final primero = _dia(
        1,
        disponibles: 0,
        turnos: [_turno(id: 7, disponibles: 0)],
      );
      final segundo = _dia(
        3,
        disponibles: 0,
        turnos: [_turno(id: 8, disponibles: 0)],
      );

      expect(diaDeTurnosAMostrar([primero, segundo]), same(primero));
    });

    test('un día con cupo agregado pero turnos llenos no se elige', () {
      // Con recursos manda el cupo del turno: el agregado del día no basta.
      final mixto = _dia(0, disponibles: 9, turnos: [_turno(disponibles: 0)]);
      final bueno = _dia(
        1,
        disponibles: 2,
        turnos: [_turno(id: 2, disponibles: 2)],
      );

      expect(diaDeTurnosAMostrar([mixto, bueno]), same(bueno));
    });
  });

  group('etiquetaCupoTurno', () {
    test('cuenta en singular, plural y sin cupo', () {
      expect(etiquetaCupoTurno(1), '1 libre');
      expect(etiquetaCupoTurno(7), '7 libres');
      expect(etiquetaCupoTurno(0), 'Sin cupo');
      // Un cupo negativo (dato raro de la RPC) tampoco es "libre".
      expect(etiquetaCupoTurno(-2), 'Sin cupo');
    });
  });

  group('etiquetaRelativaDia', () {
    final ahora = DateTime(2026, 4, 14, 23, 30);

    test('hoy y mañana se dicen con palabras', () {
      expect(etiquetaRelativaDia(DateTime(2026, 4, 14), ahora), 'Hoy');
      expect(etiquetaRelativaDia(DateTime(2026, 4, 15, 7), ahora), 'Mañana');
    });

    test('una fecha más lejana (o pasada) no tiene etiqueta relativa', () {
      expect(etiquetaRelativaDia(DateTime(2026, 4, 16), ahora), isNull);
      expect(etiquetaRelativaDia(DateTime(2026, 4, 13), ahora), isNull);
    });

    test('la hora no cambia el día: solo cuenta la fecha', () {
      // 23:30 de hoy contra 00:05 de hoy sigue siendo "Hoy".
      expect(etiquetaRelativaDia(DateTime(2026, 4, 14, 0, 5), ahora), 'Hoy');
    });
  });

  group('combinarTurnosConConfig', () {
    test('sin configuración se queda con los del día', () {
      final delDia = [_turno(id: 1), _turno(id: 2)];
      final salida = combinarTurnosConConfig(delDia, const []);
      expect(salida.map((t) => t.idTurno), [1, 2]);
    });

    test('sin turnos del día valen todos los configurados', () {
      // Es el caso de la lista de espera: el día está lleno y la RPC no
      // devuelve ni un turno, pero el admin tiene tres configurados.
      final config = [
        _turno(id: 1, disponibles: 0),
        _turno(id: 2, disponibles: 0),
        _turno(id: 3, disponibles: 0),
      ];
      final salida = combinarTurnosConConfig(const [], config);
      expect(salida.map((t) => t.idTurno), [1, 2, 3]);
      expect(salida.every((t) => t.disponibles == 0), isTrue);
    });

    test('el cupo real del día manda sobre el configurado', () {
      // Los míos (id 2, con 0 de relleno) no deben pisar el cupo del día.
      final delDia = [_turno(id: 2, disponibles: 4)];
      final config = [
        _turno(id: 1, disponibles: 0),
        _turno(id: 2, disponibles: 0),
      ];

      final salida = combinarTurnosConConfig(delDia, config);
      expect(salida.map((t) => t.idTurno), [2, 1]);
      expect(salida.first.disponibles, 4);
    });

    test('no repite un turno que ya venía del día', () {
      final salida = combinarTurnosConConfig(
        [_turno(id: 7)],
        [_turno(id: 7), _turno(id: 8)],
      );
      expect(salida.map((t) => t.idTurno), [7, 8]);
    });
  });
}
