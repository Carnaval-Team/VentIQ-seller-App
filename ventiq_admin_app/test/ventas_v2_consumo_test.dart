import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/models/report_envelope.dart';
import 'package:ventiq_admin_app/models/reporte_ordenes.dart';
import 'package:ventiq_admin_app/models/sales.dart';
import 'package:ventiq_admin_app/services/sales_service.dart';

void main() {
  group('ConsultaVentasPorMoneda', () {
    test('la v2 lee filas de texto y declara cohorte e incompletitud', () {
      final consulta = ConsultaVentasPorMoneda.desdeV2({
        'version_reporte': 'ventas-por-moneda-v2',
        'versiones_monetarias': ['legacy', 'producto-v1'],
        'magnitud': 'cobrado',
        'base_temporal': 'cohorte_ventas',
        'completitud': {
          'estado': 'incompleto',
          'motivos': ['PAGOS_SIN_EQUIVALENTE_CUP'],
        },
        'filas': [
          {
            'moneda': 'usd',
            'operaciones': 2,
            'importe_nativo': '14.50',
            'importe_base': '5220',
            'efectivo_nativo': '14.50',
            'digital_nativo': '0',
            'tasa_promedio': '360',
            'moneda_consolidacion': 'CUP',
            'importe_consolidado': '5220',
          },
        ],
      });

      expect(consulta.filas, hasLength(1));
      expect(consulta.filas.single.moneda, 'USD');
      expect(consulta.filas.single.importeNativo, 14.5);
      expect(consulta.totalConfiable, isFalse);
      expect(consulta.aclaracion, contains('Cohorte de ventas'));
      expect(consulta.aclaracion, contains('PAGOS_SIN_EQUIVALENTE_CUP'));
      expect(consulta.contrato!.magnitud, MagnitudReporte.cobrado);
    });

    test('otra magnitud o una lista que no es envelope no se reetiqueta', () {
      expect(
        () => ConsultaVentasPorMoneda.desdeV2({
          'version_reporte': 'ventas-por-moneda-v2',
          'versiones_monetarias': ['legacy'],
          'magnitud': 'venta_neta',
          'base_temporal': 'cohorte_ventas',
          'completitud': 'completo',
          'filas': [],
        }),
        throwsA(isA<ReporteContratoException>()),
      );
    });

    test('la v1 no inventa aclaración ni marca el total como incompleto', () {
      final consulta = ConsultaVentasPorMoneda.desdeV1([
        {
          'moneda': 'CUP',
          'operaciones': 1,
          'importe_nativo': 100,
          'importe_base': 100,
          'efectivo_nativo': 100,
          'digital_nativo': 0,
          'tasa_promedio': 1,
        },
      ]);
      expect(consulta.contrato, isNull);
      expect(consulta.totalConfiable, isTrue);
      expect(consulta.aclaracion, isEmpty);
      expect(consulta.filas.single.importeNativo, 100);
    });
  });

  group('ReporteOrdenes', () {
    test('la v2 rellena created_at y conserva las dos listas', () {
      final doc = ReporteOrdenes.adaptar({
        'version_reporte': 'ordenes-json-v2',
        'versiones_monetarias': ['producto-v1'],
        'magnitud': 'mixta_declarada_por_campo',
        'base_temporal': 'comercial',
        'completitud': {'estado': 'completo', 'motivos': []},
        'ordenes_completas': [
          {
            'id_operacion': 7,
            'fecha_operacion': '2026-11-16T12:00:00.000Z',
            'venta': {
              'totales_por_moneda': [
                {'moneda': 'USD', 'neto_nativo': '12.50'},
                {'moneda': 'CUP', 'neto_nativo': '500'},
              ],
            },
          },
        ],
        'ordenes_incompletas': [],
      });

      final orden = (doc['ordenes_completas'] as List).single as Map;
      expect(orden['created_at'], '2026-11-16T12:00:00.000Z');
      expect(
        ReporteOrdenes.totalesNativos(orden),
        '12.50 USD · 500 CUP',
      );
    });

    test('la línea v1 muestra el neto nativo y la legacy no', () {
      expect(
        ReporteOrdenes.importeLineaNativo({
          'importe': null,
          'linea_v1': {
            'moneda_venta': 'USD',
            'importe_neto_nativo': '12.50',
            'precio_unitario_neto_nativo': '6.25',
          },
        }),
        '12.50 USD',
      );
      expect(
        ReporteOrdenes.precioUnitarioNativo({
          'linea_v1': {
            'moneda_venta': 'USD',
            'precio_unitario_neto_nativo': '6.25',
          },
        }),
        '6.25 USD',
      );
      expect(
        ReporteOrdenes.importeLineaNativo({'importe': 80, 'linea_v1': null}),
        isNull,
      );
    });

    test('un documento v1 sin envelope se deja igual', () {
      final doc = ReporteOrdenes.adaptar({
        'ordenes_completas': [
          {'id_operacion': 1, 'created_at': '2026-01-01T00:00:00.000Z'},
        ],
      });
      expect(
        (doc['ordenes_completas'] as List).single['created_at'],
        '2026-01-01T00:00:00.000Z',
      );
    });
  });

  group('medios del turno por divisa', () {
    VentasPorMoneda fila({
      required String moneda,
      required double nativo,
      required double base,
      required double efectivo,
      required double digital,
    }) {
      return VentasPorMoneda(
        moneda: moneda,
        operaciones: 1,
        importeNativo: nativo,
        importeBase: base,
        efectivoNativo: efectivo,
        digitalNativo: digital,
        tasaPromedio: nativo == 0 ? 0 : base / nativo,
        monedaConsolidacion: 'CUP',
        importeConsolidado: moneda == 'CUP' ? nativo : base,
      );
    }

    // Turno 13: el reporte suma 90.200 CUP + 132 USD y lo muestra como 90.332.
    // El desglose sí separa. 132 USD × 850 = 112.200 CUP.
    test('el efectivo no suma el nativo de otra divisa', () {
      final filas = [
        fila(
          moneda: 'CUP',
          nativo: 140790,
          base: 140790,
          efectivo: 90200,
          digital: 50590,
        ),
        fila(
          moneda: 'USD',
          nativo: 132,
          base: 112200,
          efectivo: 132,
          digital: 0,
        ),
      ];

      final efectivo = efectivoCobradoPorDivisa(
        filas,
        egresos: 0,
        monedaBase: 'CUP',
      );
      final digital = digitalCobradoPorDivisa(filas);

      expect(efectivo.map((l) => l.moneda), ['CUP', 'USD']);
      expect(efectivo.map((l) => l.importe), [90200, 132]);
      expect(digital.single.moneda, 'CUP');
      expect(digital.single.importe, 50590);
    });

    test('los egresos se restan solo del efectivo en la moneda base', () {
      final filas = [
        fila(
          moneda: 'CUP',
          nativo: 1000,
          base: 1000,
          efectivo: 1000,
          digital: 0,
        ),
        fila(
          moneda: 'USD',
          nativo: 10,
          base: 8500,
          efectivo: 10,
          digital: 0,
        ),
      ];

      final efectivo = efectivoCobradoPorDivisa(
        filas,
        egresos: 100,
        monedaBase: 'CUP',
      );

      expect(efectivo[0].importe, 900);
      expect(efectivo[1].importe, 10);
    });
  });

  group('SalesService.rpcAusente', () {
    test('solo la función inexistente autoriza el fallback', () {
      expect(
        SalesService.rpcAusente(Exception('PGRST202 Could not find the function')),
        isTrue,
      );
      expect(
        SalesService.rpcAusente(Exception('function does not exist')),
        isTrue,
      );
      expect(SalesService.rpcAusente(Exception('42501 permission denied')), isFalse);
      expect(SalesService.rpcAusente(Exception('SocketException: failed host')), isFalse);
    });
  });
}
