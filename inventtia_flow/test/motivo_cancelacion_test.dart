import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/models/agenda.dart';
import 'package:inventtia_flow/utils/motivo_cancelacion.dart';
import 'package:inventtia_flow/utils/reserva_listado.dart';

/// Tests del **motivo de cancelación** (punto 2 del plan, §3.1).
///
/// Todo lo que se prueba aquí es puro: reglas del motivo, traducción de los
/// errores del servidor y el texto que acaba pintado en la tarjeta. No toca
/// Supabase ni widgets.
void main() {
  Agenda agenda({
    int id = 1,
    String? motivo,
    String? rol,
    String estado = 'Cancelado',
  }) {
    final creada = DateTime(2030, 1, 1, 8, 0);
    return Agenda(
      id: id,
      uuidUsuario: 'uuid-cliente',
      idLocalServicio: 7,
      idEstado: estado == 'Cancelado' ? 2 : 1,
      fechaHoraReserva: DateTime(2030, 1, 10, 10, 0),
      createdAt: creada,
      updatedAt: creada,
      estado: EstadoAgenda(id: 2, nombre: estado),
      motivoCancelacion: motivo,
      canceladoPorRol: rol,
    );
  }

  group('validarMotivo', () {
    test('sin motivo (nulo o vacío) → error', () {
      expect(validarMotivo(null), isNotNull);
      expect(validarMotivo(''), isNotNull);
      expect(validarMotivo('   '), isNotNull);
      expect(validarMotivo('\n\t '), isNotNull);
    });

    test('menos de 3 caracteres tras trim → error', () {
      expect(validarMotivo('a'), isNotNull);
      expect(validarMotivo('ab'), isNotNull);
      // Los espacios de fuera no cuentan: ' ab ' son 2 caracteres reales.
      expect(validarMotivo(' ab '), isNotNull);
    });

    test('3 caracteres o más → válido, incluidos los bordes', () {
      expect(validarMotivo('abc'), isNull);
      expect(validarMotivo('  abc  '), isNull);
      expect(validarMotivo('No pudo asistir'), isNull);
    });

    test('exactamente 500 caracteres → válido; 501 → error', () {
      expect(validarMotivo('a' * 500), isNull);
      expect(validarMotivo('a' * 501), isNotNull);
    });

    test('el error de longitud mínima dice cuántos caracteres hacen falta', () {
      final error = validarMotivo('ab');
      expect(error, contains('$motivoCancelacionMinLength'));
    });

    test('el error de longitud máxima dice cuál es el límite', () {
      final error = validarMotivo('a' * 501);
      expect(error, contains('$motivoCancelacionMaxLength'));
    });
  });

  group('mensajeErrorCancelacion', () {
    test('motivo ausente → mensaje que pide escribirlo', () {
      expect(
        mensajeErrorCancelacion(
          Exception('Debes indicar el motivo de la cancelacion'),
        ),
        contains('motivo'),
      );
    });

    test('reserva ya no activa → explica que solo se cancelan activas', () {
      expect(
        mensajeErrorCancelacion(
          Exception('Solo se pueden cancelar reservas activas'),
        ),
        contains('activas'),
      );
    });

    test('sin permisos → lo dice (no expone el error crudo)', () {
      final msg = mensajeErrorCancelacion(
        Exception('No tiene permisos sobre esta reserva'),
      );
      expect(msg.toLowerCase(), contains('permisos'));
      expect(msg, isNot(contains('Exception')));
    });

    test('reserva inexistente → pide actualizar el listado', () {
      expect(
        mensajeErrorCancelacion(Exception('Reserva no encontrada')),
        contains('no existe'),
      );
    });

    test('migración 61 sin aplicar (PGRST202) → aviso de migración', () {
      final msg = mensajeErrorCancelacion(
        Exception(
          'Could not find the function flow.staff_cancelar_reserva'
          '(p_id_agenda, p_motivo) in the schema cache (PGRST202)',
        ),
      );
      expect(msg, contains('migración 61'));
    });

    test('un mensaje ya legible pierde el prefijo Exception:', () {
      expect(
        mensajeErrorCancelacion(
          Exception('Solo puedes cancelar hasta 24 horas antes de la reserva'),
        ),
        'Solo puedes cancelar hasta 24 horas antes de la reserva',
      );
    });

    test('un error desconocido no se queda vacío ni rompe', () {
      expect(mensajeErrorCancelacion(Exception('boom')).isNotEmpty, isTrue);
      expect(mensajeErrorCancelacion('texto suelto'), 'texto suelto');
    });
  });

  group('textoMotivoCancelacion / hayMotivoCancelacion', () {
    test('nulo o en blanco → vacío (las tarjetas no pintan nada)', () {
      expect(textoMotivoCancelacion(null), '');
      expect(textoMotivoCancelacion('   '), '');
      expect(hayMotivoCancelacion(null), isFalse);
      expect(hayMotivoCancelacion('  '), isFalse);
    });

    test('recorta los espacios de los extremos', () {
      expect(textoMotivoCancelacion('  No pudo asistir  '), 'No pudo asistir');
      expect(hayMotivoCancelacion('  No pudo asistir  '), isTrue);
    });

    test('el alias del plan devuelve el mismo texto', () {
      expect(textoMotivo('  x y  '), textoMotivoCancelacion('  x y  '));
    });
  });

  group('textoCanceladoPor', () {
    test('traduce los roles de la BD a la etiqueta que se pinta', () {
      expect(textoCanceladoPor('cliente'), 'cliente');
      expect(textoCanceladoPor('admin'), 'administración');
      expect(textoCanceladoPor('staff'), 'vendedor');
      expect(textoCanceladoPor('sistema'), 'sistema');
    });

    test('rol nulo o vacío → cadena vacía (no se pinta la línea)', () {
      expect(textoCanceladoPor(null), '');
      expect(textoCanceladoPor('  '), '');
    });

    test('acepta mayúsculas y espacios', () {
      expect(textoCanceladoPor(' ADMIN '), 'administración');
    });
  });

  group('ReservaListItem.motivoCancelacion', () {
    test('toma el motivo de la reserva cancelada', () {
      final item = ReservaListItem(
        principal: agenda(motivo: 'No pudo asistir', rol: 'cliente'),
      );
      expect(item.motivoCancelacion, 'No pudo asistir');
      expect(item.canceladoPorRol, 'cliente');
    });

    test('reserva sin motivo (cancelada antes de la migración) → null', () {
      final item = ReservaListItem(principal: agenda());
      expect(item.motivoCancelacion, isNull);
      expect(item.canceladoPorRol, isNull);
    });

    test('un motivo en blanco no cuenta como motivo', () {
      final item = ReservaListItem(principal: agenda(motivo: '   '));
      expect(item.motivoCancelacion, isNull);
    });

    test('par ida+vuelta: usa el motivo de la pierna que lo tenga', () {
      final item = ReservaListItem(
        principal: agenda(id: 1),
        pareja: agenda(id: 2, motivo: 'Cambio de planes', rol: 'admin'),
      );
      expect(item.motivoCancelacion, 'Cambio de planes');
      expect(item.canceladoPorRol, 'admin');
    });
  });

  group('Agenda.fromJson con las columnas de la migración 61', () {
    Map<String, dynamic> json({Object? motivo, Object? rol}) => {
      'id': 5,
      'id_local_servicio': 9,
      'fecha_hora_reserva': '2030-01-10T10:00:00',
      'created_at': '2030-01-01T08:00:00',
      'updated_at': '2030-01-01T08:00:00',
      'motivo_cancelacion': motivo,
      'cancelado_por_rol': rol,
    };

    test('lee motivo y rol', () {
      final a = Agenda.fromJson(json(motivo: 'No pudo ir', rol: 'staff'));
      expect(a.motivoCancelacion, 'No pudo ir');
      expect(a.canceladoPorRol, 'staff');
    });

    test('texto vacío se normaliza a null (tarjeta sin bloque)', () {
      final a = Agenda.fromJson(json(motivo: '  ', rol: ''));
      expect(a.motivoCancelacion, isNull);
      expect(a.canceladoPorRol, isNull);
    });

    test('sin las columnas (respuesta antigua) no revienta', () {
      final a = Agenda.fromJson(json());
      expect(a.motivoCancelacion, isNull);
      expect(a.canceladoPorRol, isNull);
    });
  });
}