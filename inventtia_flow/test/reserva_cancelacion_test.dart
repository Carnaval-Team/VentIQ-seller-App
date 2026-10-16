import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/models/agenda.dart';
import 'package:inventtia_flow/models/entidad.dart';
import 'package:inventtia_flow/utils/reserva_listado.dart';

/// Agenda de prueba construida con el constructor normal (sin Supabase).
/// [fecha] es la fecha/hora de la reserva y [horas] el plazo de anticipación
/// de cancelación configurado en la entidad.
Agenda _agenda({
  required DateTime fecha,
  String estado = 'Reservado',
  int horas = 0,
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
    estado: EstadoAgenda(id: 1, nombre: estado),
    entidad: Entidad(
      id: 3,
      denominacion: 'Local de prueba',
      ownerUuid: 'uuid-admin',
      createdAt: creada,
      updatedAt: creada,
      horasAnticipacionCancelacion: horas,
    ),
  );
}

void main() {
  // Instante fijo de referencia para que los tests sean deterministas.
  final ahora = DateTime(2030, 1, 10, 12, 0);

  group('puedeCancelarCliente', () {
    test('reserva futura en estado Reservado → true', () {
      final a = _agenda(fecha: ahora.add(const Duration(days: 3)));
      expect(puedeCancelarCliente(a, ahora: ahora), isTrue);
    });

    test('reserva cancelada → false', () {
      final a = _agenda(
        fecha: ahora.add(const Duration(days: 3)),
        estado: 'Cancelado',
      );
      expect(puedeCancelarCliente(a, ahora: ahora), isFalse);
    });

    test('reserva completada → false', () {
      final a = _agenda(
        fecha: ahora.add(const Duration(days: 3)),
        estado: 'Completado',
      );
      expect(puedeCancelarCliente(a, ahora: ahora), isFalse);
    });

    test('fecha de la reserva ya pasada → false', () {
      final a = _agenda(fecha: ahora.subtract(const Duration(hours: 1)));
      expect(puedeCancelarCliente(a, ahora: ahora), isFalse);
    });

    test('fecha de la reserva igual a ahora → false', () {
      final a = _agenda(fecha: ahora);
      expect(puedeCancelarCliente(a, ahora: ahora), isFalse);
    });

    test('plazo de 24 h y faltan 2 h → false', () {
      final a = _agenda(
        fecha: ahora.add(const Duration(hours: 2)),
        horas: 24,
      );
      expect(puedeCancelarCliente(a, ahora: ahora), isFalse);
    });

    test('plazo de 24 h y faltan 48 h → true', () {
      final a = _agenda(
        fecha: ahora.add(const Duration(hours: 48)),
        horas: 24,
      );
      expect(puedeCancelarCliente(a, ahora: ahora), isTrue);
    });

    test('sin plazo (0 h) y la reserva en 1 minuto → true', () {
      final a = _agenda(
        fecha: ahora.add(const Duration(minutes: 1)),
        horas: 0,
      );
      expect(puedeCancelarCliente(a, ahora: ahora), isTrue);
    });
  });
}
