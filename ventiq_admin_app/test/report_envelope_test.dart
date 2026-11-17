import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/models/report_envelope.dart';

Map<String, dynamic> envelopeValido() => {
  'version_reporte': 'r1',
  'versiones_monetarias': ['legacy', 'producto-v1'],
  'magnitud': 'venta_neta',
  'completitud': 'completo',
  'base_temporal': 'comercial',
  'filas': [],
};

void main() {
  group('ReporteEnvelope.parse', () {
    test('acepta un envelope completo válido', () {
      final e = ReporteEnvelope.parse(envelopeValido());
      expect(e.versionReporte, 'r1');
      expect(e.versionesMonetarias, ['legacy', 'producto-v1']);
      expect(e.magnitud, MagnitudReporte.ventaNeta);
      expect(e.completitud, CompletitudReporte.completo);
      expect(e.baseTemporal, BaseTemporal.comercial);
      expect(e.esTotalConfiable, isTrue);
    });

    test('version_reporte ausente o vacía es error de contrato', () {
      expect(
        () => ReporteEnvelope.parse({...envelopeValido()}..remove('version_reporte')),
        throwsA(isA<ReporteContratoException>()),
      );
      expect(
        () => ReporteEnvelope.parse({...envelopeValido(), 'version_reporte': '  '}),
        throwsA(isA<ReporteContratoException>()),
      );
    });

    test('magnitud desconocida es error, no se asume', () {
      expect(
        () => ReporteEnvelope.parse({...envelopeValido(), 'magnitud': 'ingreso'}),
        throwsA(isA<ReporteContratoException>()),
      );
    });

    test('completitud inválida es error; incompleto exige motivos', () {
      expect(
        () => ReporteEnvelope.parse({...envelopeValido(), 'completitud': 'parcial'}),
        throwsA(isA<ReporteContratoException>()),
      );
      expect(
        () => ReporteEnvelope.parse({...envelopeValido(), 'completitud': 'incompleto'}),
        throwsA(isA<ReporteContratoException>()),
      );
      final e = ReporteEnvelope.parse({
        ...envelopeValido(),
        'completitud': 'incompleto',
        'motivos': ['3 lineas sin tasa'],
        'registros_no_atribuibles': 3,
      });
      expect(e.completitud, CompletitudReporte.incompleto);
      expect(e.motivos, ['3 lineas sin tasa']);
      expect(e.registrosNoAtribuibles, 3);
      expect(e.esTotalConfiable, isFalse);
    });

    test('la completitud anidada de las RPC v2 se lee igual que el código plano', () {
      final e = ReporteEnvelope.parse({
        ...envelopeValido(),
        'magnitud': 'cobrado',
        'base_temporal': 'cohorte_ventas',
        'completitud': {
          'estado': 'incompleto',
          'motivos': ['PAGOS_SIN_EQUIVALENTE_CUP'],
          'pagos_sin_equivalente': 2,
        },
      });
      expect(e.completitud, CompletitudReporte.incompleto);
      expect(e.motivos, ['PAGOS_SIN_EQUIVALENTE_CUP']);
      expect(e.magnitud, MagnitudReporte.cobrado);
      expect(e.baseTemporal, BaseTemporal.cohorteVentas);
      expect(e.esTotalConfiable, isFalse);
    });

    test('base_temporal requerida y acotada al vocabulario', () {
      expect(
        () => ReporteEnvelope.parse({...envelopeValido()}..remove('base_temporal')),
        throwsA(isA<ReporteContratoException>()),
      );
      expect(
        () => ReporteEnvelope.parse({...envelopeValido(), 'base_temporal': 'mes'}),
        throwsA(isA<ReporteContratoException>()),
      );
    });

    test('versiones_monetarias requeridas como lista', () {
      expect(
        () => ReporteEnvelope.parse({...envelopeValido()}..remove('versiones_monetarias')),
        throwsA(isA<ReporteContratoException>()),
      );
      final e = ReporteEnvelope.parse({
        ...envelopeValido(),
        'versiones_monetarias': ['producto-v1', ' ', 12],
      });
      expect(e.versionesMonetarias, ['producto-v1', '12']);
    });
  });

  group('MontoReporte.decimalExacto', () {
    test('acepta int, double finito y string decimal', () {
      expect(MontoReporte.decimalExacto(40000, 'm'), '40000');
      expect(MontoReporte.decimalExacto(30.5, 'm'), '30.5');
      expect(MontoReporte.decimalExacto('25500.00', 'm'), '25500.00');
      expect(MontoReporte.decimalExacto('-6.75', 'm'), '-6.75');
    });

    test('rechaza nulos, no finitos y malformados sin fabricar 0', () {
      for (final malo in [null, 'abc', '', '1.2.3', double.nan, double.infinity, true]) {
        expect(
          () => MontoReporte.decimalExacto(malo, 'm'),
          throwsA(isA<ReporteContratoException>()),
          reason: 'valor: $malo',
        );
      }
    });
  });

  group('MontoReporte suma', () {
    test('suma exacta solo dentro de la misma moneda', () {
      final a = MontoReporte(valor: '30.00', moneda: 'USD');
      final b = MontoReporte(valor: '6.50', moneda: 'USD');
      expect((a + b).valor, '36.5');

      final c = MontoReporte(valor: '40000', moneda: 'CUP');
      final d = MontoReporte(valor: '25500.25', moneda: 'CUP');
      expect((c + d).valor, '65500.25');
    });

    test('sumar monedas distintas es error de contrato', () {
      final a = MontoReporte(valor: '30.00', moneda: 'USD');
      final b = MontoReporte(valor: '40000', moneda: 'CUP');
      expect(() => a + b, throwsA(isA<ReporteContratoException>()));
    });

    test('respeta signos en agregados con devoluciones', () {
      final a = MontoReporte(valor: '100.00', moneda: 'CUP');
      final b = MontoReporte(valor: '-40.50', moneda: 'CUP');
      expect((a + b).valor, '59.5');
    });
  });
}
