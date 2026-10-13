import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/utils/horario_atencion.dart';

/// Formatos tomados literalmente de `flow.app_dat_locales.horario_atencion`
/// en producción. El parser anterior (`home_catalog_service._isOpen`) solo
/// buscaba la palabra "cerrado" y devolvía `true` para todos estos casos,
/// incluidos `"sd"` y `null`.
void main() {
  // 2024-01-01 fue lunes.
  DateTime lunes(int hora, [int minuto = 0]) =>
      DateTime(2024, 1, 1, hora, minuto);
  final sabado = DateTime(2024, 1, 6, 12);
  final domingo = DateTime(2024, 1, 7, 12);

  group('formatos reales de la base de datos', () {
    test('"8-4" se interpreta como 08:00 a 16:00', () {
      final horario = HorarioAtencion.parse('8-4');
      expect(horario.esDesconocido, isFalse);
      expect(horario.evaluar(lunes(7, 59)), EstadoHorario.cerrado);
      expect(horario.evaluar(lunes(8)), EstadoHorario.abierto);
      expect(horario.evaluar(lunes(15, 59)), EstadoHorario.abierto);
      expect(horario.evaluar(lunes(16)), EstadoHorario.cerrado);
    });

    test('"8:00 a 17:00"', () {
      final horario = HorarioAtencion.parse('8:00 a 17:00');
      expect(horario.evaluar(lunes(9)), EstadoHorario.abierto);
      expect(horario.evaluar(lunes(18)), EstadoHorario.cerrado);
    });

    test('"Lun - Dom, 8:30 - 16:00" cubre toda la semana', () {
      final horario = HorarioAtencion.parse('Lun - Dom, 8:30 - 16:00');
      expect(horario.dias, {1, 2, 3, 4, 5, 6, 7});
      expect(horario.evaluar(domingo), EstadoHorario.abierto);
      expect(horario.evaluar(DateTime(2024, 1, 7, 20)), EstadoHorario.cerrado);
    });

    test('"Lun-Sab 8:00am - 6:00pm" excluye el domingo', () {
      final horario = HorarioAtencion.parse('Lun-Sab 8:00am - 6:00pm');
      expect(horario.dias, {1, 2, 3, 4, 5, 6});
      expect(horario.evaluar(sabado), EstadoHorario.abierto);
      expect(horario.evaluar(domingo), EstadoHorario.cerrado);
      expect(horario.evaluar(lunes(18)), EstadoHorario.cerrado);
    });

    test('"8:30am a 4:00pm" respeta el meridiano', () {
      final horario = HorarioAtencion.parse('8:30am a 4:00pm');
      expect(horario.evaluar(lunes(8, 29)), EstadoHorario.cerrado);
      expect(horario.evaluar(lunes(8, 30)), EstadoHorario.abierto);
      expect(horario.evaluar(lunes(16)), EstadoHorario.cerrado);
    });

    test('"9:00am - 3:00pm"', () {
      final horario = HorarioAtencion.parse('9:00am - 3:00pm');
      expect(horario.evaluar(lunes(10)), EstadoHorario.abierto);
      expect(horario.evaluar(lunes(15)), EstadoHorario.cerrado);
    });
  });

  group('texto no interpretable: nunca se afirma "abierto"', () {
    test('"sd" queda desconocido', () {
      final horario = HorarioAtencion.parse('sd');
      expect(horario.esDesconocido, isTrue);
      expect(horario.esFiable, isFalse);
      expect(horario.evaluar(lunes(10)), EstadoHorario.desconocido);
      expect(horario.etiqueta, 'Horario no disponible');
    });

    test('null y vacío quedan desconocidos', () {
      expect(HorarioAtencion.parse(null).esDesconocido, isTrue);
      expect(HorarioAtencion.parse('   ').esDesconocido, isTrue);
      expect(
        HorarioAtencion.parse(null).evaluar(lunes(10)),
        EstadoHorario.desconocido,
      );
    });

    test('una sola hora no alcanza para definir una franja', () {
      expect(HorarioAtencion.parse('desde las 8').esDesconocido, isTrue);
    });

    test('texto mixto con cierre y horas no se adivina', () {
      final horario = HorarioAtencion.parse('Lun-Vie 8-4, Sáb cerrado');
      expect(horario.esDesconocido, isTrue);
      expect(horario.evaluar(lunes(10)), EstadoHorario.desconocido);
    });
  });

  group('cierres explícitos y franjas que cruzan medianoche', () {
    test('"Cerrado" se declara cerrado', () {
      final horario = HorarioAtencion.parse('Cerrado');
      expect(horario.esDesconocido, isFalse);
      expect(horario.evaluar(lunes(10)), EstadoHorario.cerrado);
      expect(horario.etiqueta, 'Cerrado');
    });

    test('"22:00 - 02:00" cubre la madrugada', () {
      final horario = HorarioAtencion.parse('22:00 - 02:00');
      expect(horario.evaluar(lunes(23)), EstadoHorario.abierto);
      expect(horario.evaluar(lunes(1)), EstadoHorario.abierto);
      expect(horario.evaluar(lunes(12)), EstadoHorario.cerrado);
    });
  });

  group('etiqueta', () {
    test('conserva el texto original cuando es interpretable', () {
      expect(HorarioAtencion.parse('8-4').etiqueta, '8-4');
      expect(
        HorarioAtencion.parse('Lun-Sab 8:00am - 6:00pm').etiqueta,
        'Lun-Sab 8:00am - 6:00pm',
      );
    });
  });
}
