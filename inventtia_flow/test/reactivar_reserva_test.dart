import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/models/agenda.dart';
import 'package:inventtia_flow/utils/reactivar_reserva.dart';
import 'package:inventtia_flow/utils/reserva_listado.dart';
import 'package:inventtia_flow/widgets/dialogo_reactivar_reserva.dart';

/// Reserva cancelada con la fecha que se le pase.
Agenda _cancelada(DateTime fecha) => Agenda(
  id: 7,
  idLocalServicio: 3,
  idEstado: 2,
  estado: EstadoAgenda(id: 2, nombre: 'Cancelado'),
  fechaHoraReserva: fecha,
  createdAt: fecha,
  updatedAt: fecha,
);

void main() {
  final hoy = DateTime(2026, 10, 24, 12);
  final manana = DateTime(2026, 10, 25, 10);
  final ayer = DateTime(2026, 10, 23, 10);

  group('destinosReactivacion', () {
    test('una reserva futura solo se puede dejar pendiente', () {
      expect(destinosReactivacion(_cancelada(manana), ahora: hoy), [
        DestinoReactivacion.pendiente,
      ]);
    });

    test('una reserva de hoy admite pendiente y completada', () {
      expect(destinosReactivacion(_cancelada(hoy), ahora: hoy), [
        DestinoReactivacion.pendiente,
        DestinoReactivacion.completado,
      ]);
    });

    test('una reserva pasada solo se puede dar por completada', () {
      expect(destinosReactivacion(_cancelada(ayer), ahora: hoy), [
        DestinoReactivacion.completado,
      ]);
    });

    test('el límite es el día, no la hora', () {
      // Hoy a las 23:59 sigue siendo «hoy»: se puede dejar pendiente.
      final tarde = DateTime(2026, 10, 24, 23, 59);
      expect(
        destinosReactivacion(_cancelada(tarde), ahora: hoy),
        contains(DestinoReactivacion.pendiente),
      );
    });

    test('los ids son el contrato con la RPC', () {
      expect(DestinoReactivacion.pendiente.idEstado, 1); // Reservado
      expect(DestinoReactivacion.completado.idEstado, 3); // Completado
    });
  });

  group('motivoNoDisponible', () {
    test('explica por qué no se ofrece cada opción', () {
      final agenda = _cancelada(manana);
      expect(motivoNoDisponible(DestinoReactivacion.pendiente, agenda, ahora: hoy), isNull);
      expect(
        motivoNoDisponible(DestinoReactivacion.completado, agenda, ahora: hoy),
        contains('hoy o anteriores'),
      );

      final pasada = _cancelada(ayer);
      expect(
        motivoNoDisponible(DestinoReactivacion.pendiente, pasada, ahora: hoy),
        contains('ya pasó'),
      );
      expect(
        motivoNoDisponible(DestinoReactivacion.completado, pasada, ahora: hoy),
        isNull,
      );
    });

    test('motivoSinOpciones nombra la fecha', () {
      expect(
        motivoSinOpciones(_cancelada(hoy), ahora: hoy),
        contains('24/10/2026'),
      );
    });
  });

  group('qué se puede hacer desde el listado', () {
    ReservaListItem item(DateTime fecha, {EstadoAgenda? estado}) => ReservaListItem(
      principal: Agenda(
        id: 9,
        idLocalServicio: 3,
        idEstado: estado?.id,
        estado: estado,
        fechaHoraReserva: fecha,
        createdAt: fecha,
        updatedAt: fecha,
      ),
    );

    final activa = EstadoAgenda(id: 1, nombre: 'Reservado');
    final cancelada = EstadoAgenda(id: 2, nombre: 'Cancelado');
    final completada = EstadoAgenda(id: 3, nombre: 'Completado');

    test('una activa se puede completar (sin mirar la fecha)', () {
      expect(puedeCompletarReserva(item(hoy, estado: activa), ahora: hoy), isTrue);
      expect(
        puedeCompletarReserva(item(manana, estado: activa), ahora: hoy),
        isTrue,
      );
      expect(puedeReactivarReserva(item(hoy, estado: activa), ahora: hoy), isFalse);
    });

    test('una cancelada pasada se puede cerrar como completada', () {
      // Este era el caso muerto: ni «Reactivar» ni «Completar» se ofrecían.
      expect(
        puedeCompletarReserva(item(ayer, estado: cancelada), ahora: hoy),
        isTrue,
      );
      expect(
        puedeReactivarReserva(item(ayer, estado: cancelada), ahora: hoy),
        isFalse,
      );
    });

    test('una cancelada de hoy admite las dos cosas', () {
      expect(
        puedeCompletarReserva(item(hoy, estado: cancelada), ahora: hoy),
        isTrue,
      );
      expect(puedeReactivarReserva(item(hoy, estado: cancelada), ahora: hoy), isTrue);
    });

    test('una cancelada futura solo se puede reactivar', () {
      expect(
        puedeCompletarReserva(item(manana, estado: cancelada), ahora: hoy),
        isFalse,
      );
      expect(
        puedeReactivarReserva(item(manana, estado: cancelada), ahora: hoy),
        isTrue,
      );
    });

    test('una completada no ofrece nada', () {
      expect(
        puedeCompletarReserva(item(ayer, estado: completada), ahora: hoy),
        isFalse,
      );
      expect(
        puedeReactivarReserva(item(ayer, estado: completada), ahora: hoy),
        isFalse,
      );
    });

    test('el par ida+vuelta del mismo día se decide por sus dos piernas', () {
      final par = ReservaListItem(
        principal: Agenda(
          id: 1,
          idLocalServicio: 3,
          idEstado: 2,
          estado: cancelada,
          fechaHoraReserva: ayer,
          createdAt: ayer,
          updatedAt: ayer,
        ),
        pareja: Agenda(
          id: 2,
          idLocalServicio: 3,
          idEstado: 2,
          estado: cancelada,
          fechaHoraReserva: ayer.add(const Duration(hours: 6)),
          createdAt: ayer,
          updatedAt: ayer,
        ),
      );

      expect(puedeCompletarReserva(par, ahora: hoy), isTrue);
      expect(puedeReactivarReserva(par, ahora: hoy), isFalse);
    });
  });

  group('mensajeErrorCambioEstado', () {
    test('el error de estado no permitido apunta a la migración 58', () {
      final mensaje = mensajeErrorCambioEstado(
        Exception('Estado destino no permitido (use Cancelado o Completado)'),
      );
      expect(mensaje, contains('migración 58'));
    });

    test('traduce las reglas de fecha de la RPC', () {
      expect(
        mensajeErrorCambioEstado(
          Exception('Solo se pueden reactivar reservas de hoy o fechas futuras'),
        ),
        contains('ya pasó'),
      );
      expect(
        mensajeErrorCambioEstado(
          Exception(
            'Solo se pueden completar reservas canceladas de hoy o fechas anteriores',
          ),
        ),
        contains('es futura'),
      );
    });

    test('cualquier otro error pasa tal cual, sin el prefijo Exception', () {
      expect(
        mensajeErrorCambioEstado(Exception('No tiene permisos sobre esta reserva')),
        'No tiene permisos sobre esta reserva',
      );
    });
  });

  group('diálogo', () {
    Future<DestinoReactivacion?> abrir(
      WidgetTester tester,
      DateTime fecha,
    ) async {
      DestinoReactivacion? elegido;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    elegido = await mostrarDialogoReactivarReserva(
                      context,
                      item: ReservaListItem(principal: _cancelada(fecha)),
                      ahora: hoy,
                    );
                  },
                  child: const Text('Abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      return elegido;
    }

    testWidgets('en una reserva futura solo ofrece dejarla pendiente', (
      tester,
    ) async {
      await abrir(tester, manana);

      expect(find.text('Dejarla pendiente'), findsOneWidget);
      expect(find.text('Marcarla como completada'), findsNothing);
      // Y dice por qué no se puede completar.
      expect(find.textContaining('hoy o anteriores'), findsOneWidget);
    });

    testWidgets('en una reserva de hoy ofrece las dos opciones', (tester) async {
      await abrir(tester, hoy);

      expect(find.text('Dejarla pendiente'), findsOneWidget);
      expect(find.text('Marcarla como completada'), findsOneWidget);
    });

    testWidgets('en una reserva pasada solo ofrece completarla', (tester) async {
      await abrir(tester, ayer);

      expect(find.text('Marcarla como completada'), findsOneWidget);
      expect(find.text('Dejarla pendiente'), findsNothing);
      expect(find.textContaining('ya pasó'), findsOneWidget);
    });

    testWidgets('el botón elegido es el que devuelve el destino', (tester) async {
      await abrir(tester, hoy);

      await tester.tap(find.text('Marcarla como completada'));
      await tester.pumpAndSettle();

      expect(find.text('Reactivar reserva'), findsNothing);
    });

    testWidgets('cerrar no devuelve nada', (tester) async {
      await abrir(tester, hoy);

      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();

      expect(find.text('Reactivar reserva'), findsNothing);
    });
  });
}
