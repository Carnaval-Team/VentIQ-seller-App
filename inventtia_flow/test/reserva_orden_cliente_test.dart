import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/models/agenda.dart';
import 'package:inventtia_flow/models/entidad.dart';
import 'package:inventtia_flow/utils/reserva_listado.dart';

/// Reserva de prueba con el constructor normal (sin Supabase).
Agenda _r({
  required DateTime fecha,
  String? estado = 'Reservado',
  int id = 1,
}) {
  final creada = DateTime(2029, 12, 1, 8, 0);
  return Agenda(
    id: id,
    uuidUsuario: 'uuid-cliente',
    idLocalServicio: 7,
    idEstado: 1,
    fechaHoraReserva: fecha,
    createdAt: creada,
    updatedAt: creada,
    estado: estado == null ? null : EstadoAgenda(id: 1, nombre: estado),
    entidad: Entidad(
      id: 3,
      denominacion: 'Local de prueba',
      ownerUuid: 'uuid-admin',
      createdAt: creada,
      updatedAt: creada,
    ),
  );
}

/// Ids en el orden en que quedan, para comparar de un golpe.
List<int> _ids(List<Agenda> lista) => lista.map((a) => a.id).toList();

void main() {
  // Instante fijo de referencia para que los tests sean deterministas.
  final ahora = DateTime(2030, 1, 10, 12, 0);

  group('prioridadEstadoReserva', () {
    test('activa < cancelada < completada', () {
      expect(
        prioridadEstadoReserva(_r(fecha: ahora, estado: 'Reservado')),
        0,
      );
      expect(
        prioridadEstadoReserva(_r(fecha: ahora, estado: 'Cancelado')),
        1,
      );
      expect(
        prioridadEstadoReserva(_r(fecha: ahora, estado: 'Completado')),
        2,
      );
    });

    test('estado desconocido o ausente cuenta como activa', () {
      expect(prioridadEstadoReserva(_r(fecha: ahora, estado: 'Pendiente')), 0);
      expect(prioridadEstadoReserva(_r(fecha: ahora, estado: null)), 0);
    });
  });

  group('ordenarReservasCliente', () {
    test('agrupa por estado: activas, después canceladas, al final completadas',
        () {
      final completada = _r(
        fecha: ahora.subtract(const Duration(days: 1)),
        estado: 'Completado',
        id: 1,
      );
      final activa = _r(
        fecha: ahora.add(const Duration(days: 2)),
        id: 2,
      );
      final cancelada = _r(
        fecha: ahora.add(const Duration(days: 1)),
        estado: 'Cancelado',
        id: 3,
      );

      final orden = ordenarReservasCliente(
        [completada, cancelada, activa],
        ahora: ahora,
      );

      expect(_ids(orden), [2, 3, 1]);
    });

    test('dentro de las activas, primero la cita más cercana a hoy', () {
      final lejana = _r(fecha: ahora.add(const Duration(days: 20)), id: 1);
      final cercana = _r(fecha: ahora.add(const Duration(days: 1)), id: 2);
      final media = _r(fecha: ahora.add(const Duration(days: 5)), id: 3);

      final orden = ordenarReservasCliente(
        [lejana, cercana, media],
        ahora: ahora,
      );

      expect(_ids(orden), [2, 3, 1]);
    });

    test('dentro de las completadas, primero la más reciente', () {
      final vieja = _r(
        fecha: ahora.subtract(const Duration(days: 30)),
        estado: 'Completado',
        id: 1,
      );
      final reciente = _r(
        fecha: ahora.subtract(const Duration(days: 2)),
        estado: 'Completado',
        id: 2,
      );
      final media = _r(
        fecha: ahora.subtract(const Duration(days: 10)),
        estado: 'Completado',
        id: 3,
      );

      final orden = ordenarReservasCliente(
        [vieja, reciente, media],
        ahora: ahora,
      );

      expect(_ids(orden), [2, 3, 1]);
    });

    test('una activa de hoy va arriba aunque su hora ya haya pasado', () {
      final deHoy = _r(
        fecha: ahora.subtract(const Duration(hours: 2)),
        id: 1,
      );
      final proxima = _r(fecha: ahora.add(const Duration(days: 3)), id: 2);

      final orden = ordenarReservasCliente([proxima, deHoy], ahora: ahora);

      expect(_ids(orden), [1, 2]);
    });

    test('mezcla completa: cada grupo ordenado por cercanía', () {
      final lista = <Agenda>[
        _r(
          fecha: ahora.subtract(const Duration(days: 40)),
          estado: 'Completado',
          id: 10,
        ),
        _r(fecha: ahora.add(const Duration(days: 9)), id: 11),
        _r(
          fecha: ahora.subtract(const Duration(days: 3)),
          estado: 'Cancelado',
          id: 12,
        ),
        _r(fecha: ahora.add(const Duration(days: 1)), id: 13),
        _r(
          fecha: ahora.subtract(const Duration(days: 1)),
          estado: 'Completado',
          id: 14,
        ),
        _r(
          fecha: ahora.subtract(const Duration(days: 8)),
          estado: 'Cancelado',
          id: 15,
        ),
      ];

      final orden = ordenarReservasCliente(lista, ahora: ahora);

      // Activas: 13 (1 día) y 11 (9 días).
      // Canceladas: 12 (3 días) y 15 (8 días).
      // Completadas: 14 (1 día) y 10 (40 días).
      expect(_ids(orden), [13, 11, 12, 15, 14, 10]);
    });

    test('misma fecha: el id mayor (lo último creado) va primero', () {
      final fecha = ahora.add(const Duration(days: 3));
      final a = _r(fecha: fecha, id: 7);
      final b = _r(fecha: fecha, id: 9);

      final orden = ordenarReservasCliente([a, b], ahora: ahora);

      expect(_ids(orden), [9, 7]);
    });

    test('no muta la lista original', () {
      final original = <Agenda>[
        _r(fecha: ahora.add(const Duration(days: 5)), id: 1),
        _r(fecha: ahora.add(const Duration(days: 1)), id: 2),
      ];

      ordenarReservasCliente(original, ahora: ahora);

      expect(_ids(original), [1, 2]);
    });

    test('lista vacía y de un solo elemento', () {
      expect(ordenarReservasCliente(const <Agenda>[], ahora: ahora), isEmpty);

      final solo = _r(fecha: ahora.add(const Duration(days: 2)), id: 4);
      expect(_ids(ordenarReservasCliente([solo], ahora: ahora)), [4]);
    });
  });
}