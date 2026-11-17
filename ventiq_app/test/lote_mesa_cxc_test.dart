import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/models/mesa_cuenta.dart';
import 'package:ventiq_app/money/cxc_v1.dart';
import 'package:ventiq_app/money/mesa_v1.dart';
import 'package:ventiq_app/money/ticket_v1.dart';

void main() {
  test('una cuenta vieja se lee y una linea nueva conserva moneda', () {
    final vieja = MesaCuentaItem.fromJson({
      'id': 1,
      'id_producto': 8,
      'cantidad': 2,
      'precio_unitario': 10,
      'created_at': '2026-11-14T12:00:00Z',
    });
    expect(vieja.versionMonetaria, isNull);
    final nueva = MesaCuentaItem.fromJson({
      'id': 2,
      'id_producto': 8,
      'cantidad': 1,
      'precio_unitario': 10,
      'created_at': '2026-11-14T12:00:00Z',
      'version_monetaria': 'producto-v1',
      'id_linea_cliente': '00000000-0000-4000-8000-000000000001',
      'moneda_venta': 'USD',
      'importe_neto_nativo': '5.00',
      'snapshot_precio': {'valor_publicado': '5.00'},
    });
    expect(nueva.toJson()['moneda_venta'], 'USD');
    expect(MesaV1.puedeUnir(
      mismaPresentacion: true,
      mismaMoneda: false,
      mismoMedio: true,
    ), isFalse);
    expect(MesaV1.permiteEditar('producto-v1'), isFalse);
    expect(MesaV1.debeDescontarAlCerrar(stockMovido: true), isFalse);
    expect(MesaV1.solicitudCierre(
      clientUuid: '00000000-0000-4000-8000-000000000010',
      clientUuidPago: '00000000-0000-4000-8000-000000000011',
      idCuenta: 4,
    )['version_monetaria'], 'producto-v1');
  });

  test('la deuda nueva no suma monedas y el segundo medio no cambia', () {
    final saldos = CxcV1.saldos([
      {'version_monetaria': 'producto-v1', 'moneda': 'USD', 'saldo_nativo': '5.00'},
      {'version_monetaria': 'producto-v1', 'moneda': 'CUP', 'saldo_nativo': '10.00'},
      {'version_monetaria': null, 'moneda': 'CUP', 'saldo_nativo': '99.00'},
    ]);
    expect(saldos.map((s) => '${s.moneda}:${s.saldo}').toList(), ['USD:5.00', 'CUP:10.00']);
    expect(
      () => CxcV1.validarLiquidacion(
        monedaDeuda: 'USD',
        monedaPago: 'CUP',
        medioFijado: 1,
        medioPago: 1,
        saldo: '5.00',
        monto: '1.00',
      ),
      throwsA(isA<CxcV1Exception>()),
    );
    expect(
      () => CxcV1.validarLiquidacion(
        monedaDeuda: 'USD',
        monedaPago: 'USD',
        medioFijado: 1,
        medioPago: 2,
        saldo: '5.00',
        monto: '1.00',
      ),
      throwsA(isA<CxcV1Exception>()),
    );
  });

  test('la caja nueva no entra en el total CUP', () {
    final partes = CajaV1.porMoneda({
      'version_monetaria': 'producto-v1',
      'items': [
        {
          'seleccion': {
            'id_linea_cliente': '00000000-0000-4000-8000-000000000001',
            'id_producto': '1',
            'cantidad': '1',
            'moneda_venta': 'USD',
            'seleccion_cobro': {'tipo': 'medio_pago', 'id_medio_pago': 1},
            'precio_unitario_nativo': '5.00',
            'descuento_manual_unitario_nativo': '0',
            'snapshot_precio': {'valor_publicado': '5.00'},
            'snapshot_tasa': {
              'valor_publicado': '400',
              'evidencia_publicacion': 'tasa-1',
            },
            'snapshot_ajustes_automaticos': [],
          },
        },
      ],
    });
    expect(partes['USD'], '5.00');
    expect(partes.containsKey('CUP'), isFalse);
    expect(CajaV1.sumar('5.00', '5.00'), '10.00');
  });

  test('los scripts de mesa, deuda y ajuste no reescriben historia', () {
    final dir = '../docs/plan-multimoneda';
    String read(String name) => File('$dir/$name').readAsStringSync();
    final pedido = read('m01_r19_mesa_pedido_v1_propuesta.sql');
    final cierre = read('m01_r20_mesa_cierre_v1_propuesta.sql');
    final cxc = read('m01_r21_cxc_v1_propuesta.sql');
    final ajuste = read('m01_r22_ajuste_v1_propuesta.sql');
    expect(pedido.contains('fn_agregar_item_cuenta_mesa'), isFalse);
    expect(pedido.contains("= 'cocina_al_pedido'"), isTrue);
    expect(cierre.contains('precio_unitario_neto_nativo'), isTrue);
    expect(cxc.contains('fn_m01_cxc_registrar_v1'), isTrue);
    expect(pedido.contains('Activacion de moneda por producto no autorizada'), isTrue);
    expect(cierre.contains('stock_movido IS NOT TRUE'), isTrue);
    expect(cierre.contains('fn_registrar_venta_v3'), isFalse);
    expect(cxc.contains('ENABLE ROW LEVEL SECURITY'), isTrue);
    expect(cxc.contains('GROUP BY o.moneda'), isTrue);
    expect(ajuste.contains('carnaval'), isFalse);
    expect(ajuste.contains('UPDATE public.app_dat_extraccion_productos'), isFalse);
    expect(read('m01_r18_mesa_v1_columnas_propuesta.sql').contains('ENABLE ROW LEVEL SECURITY'), isTrue);
    final revocar = read('m01_r23_revocar_anon_mesa_cxc_propuesta.sql');
    expect(revocar.contains('FROM PUBLIC, anon'), isTrue);
    expect(revocar.contains('permitir_moneda_por_producto'), isFalse);
    expect(read('m01_m07_harness_rechazo.sql').contains('ROLLBACK'), isTrue);
    final enrutado = read('m01_r24_pedir_mesa_enrutado_propuesta.sql');
    expect(enrutado.contains('CREATE OR REPLACE FUNCTION'), isTrue);
    expect(enrutado.contains("= 'cocina_al_pedido'"), isTrue);
    expect(enrutado.contains("IS DISTINCT FROM 'tpv'"), isFalse);
    final admin = File('../ventiq_admin_app/lib/services/cxc_service.dart').readAsStringSync();
    final saldo = admin.substring(admin.indexOf('saldosProductoV1'));
    expect(saldo.contains('return 0'), isFalse);
    AjusteV1.validarDevolucion(
      version: 'producto-v1',
      monedaOriginal: 'USD',
      monedaDevolucion: 'USD',
    );
    expect(
      () => AjusteV1.validarDevolucion(
        version: 'producto-v1',
        monedaOriginal: 'USD',
        monedaDevolucion: 'CUP',
      ),
      throwsA(isA<CxcV1Exception>()),
    );
  });
}
