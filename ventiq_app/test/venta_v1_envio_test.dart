import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/money/line_money.dart';
import 'package:ventiq_app/money/venta_v1_envio.dart';

void main() {
  final fixtures = jsonDecode(
    File('../docs/plan-multimoneda/product_currency_v1_fixtures.json')
        .readAsStringSync(),
  ) as Map<String, dynamic>;

  test('3 x 1.05 con 10 por ciento se cobra en 2.84 y no se redistribuye', () {
    final linea = LineMoneyCalculator.calcular(
      moneda: 'USD',
      cantidad: '3',
      precioUnitario: '1.05',
      automaticoTipo: 'discount_percent',
      automaticoValor: '10',
      manualUnitario: '0',
      tasaCup: '400',
    );
    final grupos = CheckoutV1.agrupar([
      LineaCobro(
        idLinea: 'a',
        moneda: 'USD',
        medio: 1,
        pendiente: false,
        neto: linea.neto.toFixed(2),
        cup: linea.equivalenteCup.toFixed(2),
        tasaDisponible: true,
      ),
    ]);
    expect(grupos.single.neto, '2.84');
    expect(
      CheckoutV1.rechazoEdicion(grupos, [
        {'moneda': 'USD', 'id_medio_pago': 1, 'monto_nativo': '2.00'},
      ]),
      'El cobro no se redistribuye. Vuelve al detalle.',
    );
  });

  test('tasas distintas siguen en el mismo medio y no se suman como una sola tasa', () {
    final group = (fixtures['group_cases'] as List).first as Map<String, dynamic>;
    final grupos = CheckoutV1.agrupar([
      for (final raw in group['lines'] as List)
        LineaCobro(
          idLinea: raw['line_id'].toString(),
          moneda: raw['currency'].toString(),
          medio: raw['method_id'] as int,
          pendiente: false,
          neto: raw['net'].toString(),
          cup: raw['cup_net'].toString(),
          tasaDisponible: true,
        ),
    ]);
    final expected = group['expected'] as Map<String, dynamic>;
    expect(grupos, hasLength(expected.length));
    for (final grupo in grupos) {
      final row = expected['${grupo.moneda}|${grupo.medio}'] as Map;
      expect(grupo.neto, row['net']);
      expect(grupo.cup, row['cup_net']);
    }
    final mixto = grupos.singleWhere((g) => g.moneda == 'USD' && g.medio == 1);
    expect(mixto.aplicaciones, hasLength(2));
    expect(mixto.neto, '10.00');
    expect(mixto.cup, '4100.00');
  });

  test('una orden vieja sigue su cobro y una nueva no lo usa para evadir el flag', () {
    expect(
      EnvioV1.decidir(
        version: null,
        modoActivo: false,
        bloqueaOrdenNueva: false,
        tieneTasa: true,
        lineasCompletas: true,
        origen: 'mostrador',
      ).ruta,
      RutaEnvio.legacy,
    );
    expect(
      EnvioV1.decidir(
        version: null,
        modoActivo: true,
        bloqueaOrdenNueva: false,
        tieneTasa: true,
        lineasCompletas: true,
        origen: 'mostrador',
      ).ruta,
      RutaEnvio.rechazar,
    );
  });

  test('sin tasa la orden se conserva y la preorden sale por su contrato', () {
    expect(
      EnvioV1.decidir(
        version: 'producto-v1',
        modoActivo: true,
        bloqueaOrdenNueva: false,
        tieneTasa: false,
        lineasCompletas: true,
        origen: 'mostrador',
      ).ruta,
      RutaEnvio.retener,
    );
    expect(
      EnvioV1.decidir(
        version: 'producto-v1',
        modoActivo: true,
        bloqueaOrdenNueva: false,
        tieneTasa: true,
        lineasCompletas: true,
        origen: 'preorden',
      ).ruta,
      RutaEnvio.productoV1,
    );
    for (final origen in ['mesa', 'desconocido']) {
      expect(
        EnvioV1.decidir(
          version: 'producto-v1',
          modoActivo: true,
          bloqueaOrdenNueva: false,
          tieneTasa: true,
          lineasCompletas: true,
          origen: origen,
        ).ruta,
        RutaEnvio.retener,
      );
    }
  });

  test('la preorden vieja conserva su desglose y la nueva no hereda CUP', () {
    final vieja = <String, dynamic>{
      'desglose_pagos': [
        {'moneda': 'CUP'},
      ],
      'items': <Map<String, dynamic>>[],
    };
    ContratoPendiente.aplicar(
      pending: vieja,
      version: null,
      origen: 'preorden',
      selecciones: const [],
    );
    expect(vieja.containsKey('desglose_pagos'), isTrue);
    expect(vieja.containsKey('version_monetaria'), isFalse);

    final nueva = <String, dynamic>{
      'desglose_pagos': [
        {'moneda': 'CUP'},
      ],
      'items': [<String, dynamic>{}],
    };
    ContratoPendiente.aplicar(
      pending: nueva,
      version: 'producto-v1',
      origen: 'preorden',
      selecciones: const [null],
    );
    expect(nueva.containsKey('desglose_pagos'), isFalse);
    expect(nueva['origen'], {'tipo': 'preorden'});
  });

  test('un fallo v1 no abre el registro anterior', () {
    final cliente = File('lib/services/venta_v1_cliente.dart').readAsStringSync();
    expect(cliente.contains('fn_registrar_venta'), isFalse);
    expect(cliente.contains('fn_registrar_pago_venta'), isFalse);
    final orden = File('lib/services/order_service.dart').readAsStringSync();
    final altaOnline = orden.indexOf(
      'Future<Map<String, dynamic>> _registerSaleInSupabase',
    );
    expect(
      orden.indexOf('_rutaProductoV1(', altaOnline),
      lessThan(orden.indexOf('fn_registrar_venta_v3', altaOnline)),
    );
    final sync = File('lib/services/auto_sync_service.dart').readAsStringSync();
    final altaOffline = sync.indexOf('Future<void> _registerSaleInSupabase');
    expect(
      sync.indexOf('RutaEnvio.productoV1', altaOffline),
      lessThan(sync.indexOf('_pagosParaSincronizar(orderData)', altaOffline)),
    );
    expect(
      sync.contains("orderData['version_monetaria'] == 'producto-v1'"),
      isTrue,
    );
  });
}
