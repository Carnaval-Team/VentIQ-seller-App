import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/models/tasa_cambio.dart';

/// Payload real de `flow.tasas_actuales()` / Edge Function `flow-tasas`
/// (debug, 27-10-2026). La matriz `conversiones` ya trae el cruce por CUP.
Map<String, dynamic> _payload() => {
  'ok': true,
  'fecha': '2026-10-27',
  'hora': '07:00:06',
  'fuente': 'directoriocubano',
  'actualizado': '2026-10-27 07:00:06',
  'vigente': true,
  'tasas': {
    'USD': {'CUP': 840, 'MLC': 700, 'EUR': 0.908108},
    'EUR': {'CUP': 925, 'MLC': 770, 'USD': 1.101189},
    'MLC': {'CUP': 697.62, 'USD': 0.8305},
  },
  'conversiones': {
    'USD': {'USD': 1, 'CUP': 840, 'EUR': 0.908108, 'MLC': 1.2},
    'EUR': {'EUR': 1, 'CUP': 925, 'USD': 1.101189, 'MLC': 1.321728},
    'MLC': {'MLC': 1, 'CUP': 697.62, 'USD': 0.8305, 'EUR': 0.754184},
    'CUP': {'CUP': 1, 'USD': 0.00119, 'EUR': 0.001081, 'MLC': 0.001433},
  },
};

void main() {
  group('TasasDia.fromJson', () {
    test('lee la respuesta normal del backend', () {
      final tasas = TasasDia.fromJson(_payload());
      expect(tasas.fecha, DateTime(2026, 10, 27));
      expect(tasas.hora, '07:00:06');
      expect(tasas.actualizado, '2026-10-27 07:00:06');
      expect(tasas.vigente, isTrue);
      expect(tasas.fuente, 'directoriocubano');
      expect(tasas.hayDatos, isTrue);
      expect(tasas.tasas['USD'], isA<Map>());
      expect(tasas.conversiones['USD']?['CUP'], 840);
    });

    test('tolera números como texto, fechas raras y campos ausentes', () {
      final tasas = TasasDia.fromJson({
        'fecha': '27/10/2026',
        'vigente': 'true', // texto: no es `true`, se queda en false
        'conversiones': {
          'USD': {'CUP': '840', 'EUR': 0.908108, 'MLC': null, 'GBP': -3},
        },
      });
      expect(tasas.fecha, DateTime(2026, 10, 27));
      expect(tasas.vigente, isFalse);
      expect(tasas.hora, isNull);
      expect(tasas.fuente, isNull);
      expect(tasas.factor('USD', 'CUP'), 840);
      expect(tasas.factor('USD', 'MLC'), isNull, reason: 'el null se descarta');
      expect(tasas.factor('USD', 'GBP'), isNull, reason: 'negativo no sirve');
    });

    test('no lanza con un JSON vacío o basura', () {
      final vacio = TasasDia.fromJson(const {});
      expect(vacio.fecha, isNull);
      expect(vacio.hayDatos, isFalse);
      expect(vacio.fechaTexto, '—');
      expect(vacio.horaTexto, '—');

      final basura = TasasDia.fromJson({'fecha': 'x', 'conversiones': 'no'});
      expect(basura.fecha, isNull);
      expect(basura.conversiones, isEmpty);
    });
  });

  group('TasasDia.factor', () {
    test('factor directo y normalización de mayúsculas/espacios', () {
      final tasas = TasasDia.fromJson(_payload());
      expect(tasas.factor('USD', 'CUP'), 840);
      expect(tasas.factor(' usd ', 'cup'), 840);
      expect(tasas.factor('EUR', 'USD'), closeTo(1.101189, 1e-9));
    });

    test('cruce por CUP: la base de datos ya lo trae (MLC → EUR)', () {
      final tasas = TasasDia.fromJson(_payload());
      // 697,62 / 925 = 0,754184: no lo calcula la app, lo lee.
      expect(tasas.factor('MLC', 'EUR'), closeTo(0.754184, 1e-9));
    });

    test('identidad: X → X vale 1 porque la matriz la incluye', () {
      final tasas = TasasDia.fromJson(_payload());
      expect(tasas.factor('CUP', 'CUP'), 1);
    });

    test('clave ausente devuelve null, NO 1', () {
      final tasas = TasasDia.fromJson(_payload());
      expect(tasas.factor('USD', 'GBP'), isNull);
      expect(tasas.factor('GBP', 'USD'), isNull);
      expect(tasas.factor('', 'USD'), isNull);
      expect(tasas.factor('USD', ''), isNull);
    });

    test('una matriz sin identidad no inventa el 1', () {
      final tasas = TasasDia(
        fecha: DateTime(2026, 10, 27),
        conversiones: const {
          'USD': {'CUP': 840.0},
        },
      );
      expect(tasas.factor('USD', 'USD'), isNull);
    });
  });

  group('TasasDia — fecha y estado', () {
    test('esDelDia / esDeHoy', () {
      final tasas = TasasDia.fromJson(_payload());
      expect(tasas.esDelDia(DateTime(2026, 10, 27, 23, 59)), isTrue);
      expect(tasas.esDelDia(DateTime(2026, 10, 28)), isFalse);
      // No se compara con la fecha real del test: se usan fechas fijas.
      final vieja = TasasDia(fecha: DateTime(2001, 1, 1));
      expect(vieja.esDeHoy, isFalse);
      expect(TasasDia(fecha: null).esDeHoy, isFalse);
    });

    test('fechaTexto se pinta dd/mm/aaaa', () {
      expect(TasasDia.fromJson(_payload()).fechaTexto, '27/10/2026');
    });

    test('horaTexto cae a — cuando no llega', () {
      expect(TasasDia.fromJson({'hora': '  '}).horaTexto, '—');
    });
  });

  group('TasasDia.desdeRespuesta', () {
    test('acepta el payload bueno', () {
      final tasas = TasasDia.desdeRespuesta(_payload());
      expect(tasas, isNotNull);
      expect(tasas!.factor('USD', 'CUP'), 840);
    });

    test('ok:false, sin conversiones o basura devuelven null', () {
      expect(TasasDia.desdeRespuesta({'ok': false, 'error': 'sin tasas'}), isNull);
      expect(TasasDia.desdeRespuesta({'ok': true, 'conversiones': {}}), isNull);
      expect(TasasDia.desdeRespuesta(null), isNull);
      expect(TasasDia.desdeRespuesta('no es json'), isNull);
    });

    test('el aviso del backend se conserva para pintarlo', () {
      final tasas = TasasDia.desdeRespuesta({
        ...(_payload()),
        'aviso': 'No se pudo refrescar (HTTP 502).',
      });
      expect(tasas!.aviso, 'No se pudo refrescar (HTTP 502).');
    });
  });
}