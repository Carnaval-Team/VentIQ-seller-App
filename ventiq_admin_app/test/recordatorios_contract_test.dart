// Contrato de los recordatorios de compras sin completar (Fase 9).
//
// Prueba SOLO la lógica pura de `lib/services/recordatorios_calculo.dart`:
// no necesita Flutter, ni Supabase, ni `SharedPreferences`. El JSON simula la
// forma exacta de `fn_fdi_pendientes_panel` (ver `lib/sql/compra/09_pendientes.sql`).
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/services/recordatorios_calculo.dart';

Map<String, dynamic> _panel({
  List<Map<String, dynamic>> compras = const <Map<String, dynamic>>[],
  List<Map<String, dynamic>> totales = const <Map<String, dynamic>>[],
}) {
  return <String, dynamic>{
    'id_tienda': 7,
    'generado_at': '2026-11-23T10:00:00Z',
    'orden': 'antiguedad',
    'compras': compras,
    'totales_por_moneda': totales,
  };
}

Map<String, dynamic> _compra({
  required int id,
  required int dias,
  String moneda = 'USD',
  double total = 0,
  double pendiente = 0,
}) {
  return <String, dynamic>{
    'id_compra': id,
    'numero_compra': 'C-$id',
    'numero_factura': null,
    'proveedor': 'Proveedor $id',
    'fecha_factura': '2026-11-01',
    'estado': 'creada',
    'moneda': moneda,
    'dias_antiguedad': dias,
    'lineas': 2,
    'pedido': 10,
    'recibido': 4,
    'recibido_pct': 0.4,
    'monto_total': total,
    'monto_pendiente': pendiente,
    'ultima_recepcion': null,
    'dias_sin_movimiento': dias,
  };
}

Map<String, dynamic> _total(
  String moneda, {
  required int compras,
  required double pendiente,
  double total = 0,
}) {
  return <String, dynamic>{
    'moneda': moneda,
    'compras': compras,
    'monto_total': total,
    'monto_pendiente': pendiente,
  };
}

void main() {
  group('umbral de días', () {
    test('el valor por defecto es 15', () {
      expect(umbralDiasPorDefecto, 15);
      expect(normalizarUmbral(null), 15);
      expect(normalizarUmbral(''), 15);
      expect(normalizarUmbral('no-es-un-numero'), 15);
    });

    test('descarta valores fuera del rango 1..365 y acepta el resto', () {
      expect(normalizarUmbral(0), 15);
      expect(normalizarUmbral(-5), 15);
      expect(normalizarUmbral(366), 15);
      expect(normalizarUmbral(30), 30);
      expect(normalizarUmbral(1), 1);
      expect(normalizarUmbral(365), 365);
      expect(normalizarUmbral('21'), 21);
      expect(normalizarUmbral(21.0), 21);
    });

    test('acotarUmbral mete cualquier valor en el rango', () {
      expect(acotarUmbral(0), umbralDiasMinimo);
      expect(acotarUmbral(-100), umbralDiasMinimo);
      expect(acotarUmbral(999), umbralDiasMaximo);
      expect(acotarUmbral(15.4), 15);
      expect(acotarUmbral(15.6), 16);
    });

    test('el resumen vacío conserva el umbral pedido y cae al valor por defecto', () {
      expect(ResumenPendientes.vacio().umbralDias, 15);
      expect(ResumenPendientes.vacio(umbralDias: 30).umbralDias, 30);
      expect(ResumenPendientes.vacio(umbralDias: 0).umbralDias, 15);
    });
  });

  group('compras que superan el umbral', () {
    test('cuenta solo las que llevan MÁS días que el umbral', () {
      final resumen = ResumenPendientes.desdePanel(
        _panel(
          compras: [
            _compra(id: 1, dias: 20),
            _compra(id: 2, dias: 15), // justo el umbral: no lo supera
            _compra(id: 3, dias: 16),
            _compra(id: 4, dias: 3),
          ],
        ),
        umbralDias: 15,
      );

      expect(resumen.totalCompras, 4);
      expect(resumen.comprasSobreUmbral, 2);
      expect(resumen.hayAviso, isTrue);
      expect(
        resumen.comprasQueSuperanUmbral.map((c) => c.idCompra),
        containsAll(<int>[1, 3]),
      );
    });

    test('con umbral más alto baja el conteo (el umbral es configurable)', () {
      final panel = _panel(
        compras: [
          _compra(id: 1, dias: 20),
          _compra(id: 2, dias: 16),
        ],
      );

      expect(ResumenPendientes.desdePanel(panel, umbralDias: 15)
          .comprasSobreUmbral, 2);
      expect(ResumenPendientes.desdePanel(panel, umbralDias: 20)
          .comprasSobreUmbral, 0);
      expect(ResumenPendientes.desdePanel(panel, umbralDias: 20).hayAviso,
          isFalse);
    });

    test('el mensaje de la notificación concuerda con el conteo', () {
      final una = ResumenPendientes.desdePanel(
        _panel(compras: [_compra(id: 1, dias: 40)]),
        umbralDias: 15,
      );
      expect(una.mensajeNotificacion,
          '1 compra lleva más de 15 días sin recibirse completa');

      final varias = ResumenPendientes.desdePanel(
        _panel(compras: [_compra(id: 1, dias: 40), _compra(id: 2, dias: 20)]),
        umbralDias: 15,
      );
      expect(varias.mensajeNotificacion,
          '2 compras llevan más de 15 días sin recibirse completas');
    });
  });

  group('la compra más antigua', () {
    test('es la de mayor antigüedad, no la primera del JSON', () {
      final resumen = ResumenPendientes.desdePanel(
        _panel(
          compras: [
            _compra(id: 1, dias: 3),
            _compra(id: 2, dias: 40),
            _compra(id: 3, dias: 12),
          ],
        ),
        umbralDias: 15,
      );

      expect(resumen.diasMasAntigua, 40);
      expect(resumen.masAntigua?.idCompra, 2);
    });

    test('sin compras no hay antigüedad', () {
      final resumen = ResumenPendientes.desdePanel(_panel(), umbralDias: 15);
      expect(resumen.diasMasAntigua, isNull);
      expect(resumen.masAntigua, isNull);
    });
  });

  group('pendiente por moneda', () {
    test('usa los totales de la RPC sin cruzar monedas', () {
      final resumen = ResumenPendientes.desdePanel(
        _panel(
          compras: [
            _compra(id: 1, moneda: 'USD', dias: 20, total: 200, pendiente: 100.5),
            _compra(id: 2, moneda: 'CUP', dias: 40, total: 5000, pendiente: 2500),
          ],
          totales: [
            _total('USD', compras: 1, total: 200, pendiente: 100.5),
            _total('CUP', compras: 1, total: 5000, pendiente: 2500),
          ],
        ),
        umbralDias: 15,
      );

      expect(resumen.porMoneda.length, 2);
      final usd = resumen.porMoneda.firstWhere((m) => m.moneda == 'USD');
      final cup = resumen.porMoneda.firstWhere((m) => m.moneda == 'CUP');
      expect(usd.montoPendiente, 100.5);
      expect(usd.compras, 1);
      expect(cup.montoPendiente, 2500);
      // Lo que nunca debe aparecer: la suma de monedas distintas.
      for (final moneda in resumen.porMoneda) {
        expect(moneda.montoPendiente, isNot(2600.5));
      }
    });

    test('agrega desde las compras si la RPC no manda totales', () {
      final resumen = ResumenPendientes.desdePanel(
        _panel(
          compras: [
            _compra(id: 1, moneda: 'USD', dias: 20, total: 100, pendiente: 40.25),
            _compra(id: 2, moneda: 'USD', dias: 10, total: 60, pendiente: 12.75),
            _compra(id: 3, moneda: 'CUP', dias: 40, total: 5000, pendiente: 2500),
          ],
          totales: const <Map<String, dynamic>>[],
        ),
        umbralDias: 15,
      );

      expect(resumen.porMoneda.length, 2);
      final usd = resumen.porMoneda.firstWhere((m) => m.moneda == 'USD');
      expect(usd.compras, 2);
      expect(usd.montoPendiente, closeTo(53.0, 0.0001));
      expect(usd.montoTotal, closeTo(160.0, 0.0001));
      final cup = resumen.porMoneda.firstWhere((m) => m.moneda == 'CUP');
      expect(cup.compras, 1);
      expect(cup.montoPendiente, 2500);
    });

    test('una moneda nula es «moneda desconocida» y va al final', () {
      final resumen = ResumenPendientes.desdePanel(
        _panel(
          compras: [
            _compra(id: 1, moneda: 'USD', dias: 20, pendiente: 10),
            _compra(id: 2, moneda: '', dias: 10, pendiente: 5),
          ],
          totales: const <Map<String, dynamic>>[],
        ),
        umbralDias: 15,
      );

      expect(resumen.porMoneda.first.moneda, 'USD');
      expect(resumen.porMoneda.last.moneda, monedaDesconocida);
    });
  });

  group('hayAviso', () {
    test('es falso cuando no hay compras', () {
      final resumen = ResumenPendientes.desdePanel(_panel(), umbralDias: 15);
      expect(resumen.vacio, isTrue);
      expect(resumen.hayAviso, isFalse);
      expect(resumen.comprasSobreUmbral, 0);
      expect(resumen.porMoneda, isEmpty);
    });

    test('es falso cuando hay compras recientes', () {
      final resumen = ResumenPendientes.desdePanel(
        _panel(compras: [_compra(id: 1, dias: 2), _compra(id: 2, dias: 9)]),
        umbralDias: 15,
      );
      expect(resumen.vacio, isFalse);
      expect(resumen.hayAviso, isFalse);
    });

    test('es verdadero en cuanto una compra supera el umbral', () {
      final resumen = ResumenPendientes.desdePanel(
        _panel(compras: [_compra(id: 1, dias: 2), _compra(id: 2, dias: 16)]),
        umbralDias: 15,
      );
      expect(resumen.hayAviso, isTrue);
    });
  });

  group('tolerancia a JSON incompleto', () {
    test('panel nulo o vacío devuelve un resumen vacío', () {
      expect(ResumenPendientes.desdePanel(null).vacio, isTrue);
      expect(ResumenPendientes.desdePanel(<String, dynamic>{}).vacio, isTrue);
    });

    test('compras nulas o con filas inservibles no rompen el cálculo', () {
      final conNull = ResumenPendientes.desdePanel(<String, dynamic>{
        'compras': null,
        'totales_por_moneda': null,
      });
      expect(conNull.vacio, isTrue);
      expect(conNull.porMoneda, isEmpty);

      final conBasura = ResumenPendientes.desdePanel(<String, dynamic>{
        'compras': ['basura', 42, null],
        'totales_por_moneda': 'basura',
      });
      expect(conBasura.vacio, isTrue);
    });

    test('una fila de compra sin claves usa valores por defecto', () {
      final resumen = ResumenPendientes.desdePanel(<String, dynamic>{
        'compras': [
          <String, dynamic>{},
        ],
      });

      expect(resumen.totalCompras, 1);
      expect(resumen.compras.first.diasAntiguedad, 0);
      expect(resumen.compras.first.montoPendiente, 0);
      expect(resumen.compras.first.moneda, monedaDesconocida);
      expect(resumen.umbralDias, umbralDiasPorDefecto);
      expect(resumen.hayAviso, isFalse);
    });

    test('acepta números enviados como texto y claves raras', () {
      final resumen = ResumenPendientes.desdePanel(<String, dynamic>{
        'compras': [
          <String, dynamic>{
            'id_compra': '9',
            'moneda': 'USD',
            'dias_antiguedad': '25',
            'monto_total': '100.5',
            'monto_pendiente': '10.5',
            'recibido_pct': '0.5',
          },
        ],
        'totales_por_moneda': [
          <String, dynamic>{
            'moneda': 'USD',
            'compras': '1',
            'monto_total': '100.5',
            'monto_pendiente': '10.5',
          },
        ],
      }, umbralDias: 15);

      expect(resumen.compras.first.idCompra, 9);
      expect(resumen.compras.first.diasAntiguedad, 25);
      expect(resumen.compras.first.montoPendiente, 10.5);
      expect(resumen.compras.first.recibidoPct, 0.5);
      expect(resumen.hayAviso, isTrue);
      expect(resumen.porMoneda.single.montoPendiente, 10.5);
    });

    test('acota el porcentaje recibido y las antigüedades negativas', () {
      final resumen = ResumenPendientes.desdePanel(<String, dynamic>{
        'compras': [
          <String, dynamic>{'dias_antiguedad': -3, 'recibido_pct': 4},
        ],
      });

      expect(resumen.compras.first.diasAntiguedad, 0);
      expect(resumen.compras.first.recibidoPct, 1);
    });
  });

  group('formato de importes', () {
    test('separa miles y fija dos decimales, sin símbolo de moneda', () {
      expect(formatearMonto(0), '0.00');
      expect(formatearMonto(12.5), '12.50');
      expect(formatearMonto(1234.5), '1,234.50');
      expect(formatearMonto(1234567.891), '1,234,567.89');
      expect(formatearMonto(-45.6), '-45.60');
    });

    test('singular y plural de días', () {
      expect(textoDias(1), '1 día');
      expect(textoDias(0), '0 días');
      expect(textoDias(15), '15 días');
    });
  });
}