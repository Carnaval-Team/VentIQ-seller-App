import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/models/payment_method.dart';
import 'package:ventiq_app/money/detalle_moneda.dart';

void main() {
  test('sin precio configurado en la moneda elegida no hay linea', () {
    expect(
      DetalleMoneda.precioConfigurado(
        moneda: 'USD',
        precioCup: 100,
        precioUsd: null,
        origenUsd: 'no_disponible',
        factor: 1,
        esVariante: false,
      ),
      isNull,
    );
    expect(
      DetalleMoneda.precioConfigurado(
        moneda: 'USD',
        precioCup: 100,
        precioUsd: null,
        origenUsd: 'general',
        factor: 2,
        esVariante: true,
      ),
      isNull,
    );
    expect(
      DetalleMoneda.precioConfigurado(
        moneda: 'USD',
        precioCup: 100,
        precioUsd: 5,
        origenUsd: 'general',
        factor: 2,
        esVariante: true,
      ),
      '10.00',
    );
    expect(
      DetalleMoneda.precioConfigurado(
        moneda: 'USD',
        precioCup: 100,
        precioUsd: 5,
        origenUsd: 'general',
        factor: 2,
        esVariante: false,
      ),
      '10.00',
    );
    expect(
      DetalleMoneda.precioConfigurado(
        moneda: 'CUP',
        precioCup: 12.5,
        precioUsd: null,
        origenUsd: null,
        factor: 1,
        esVariante: false,
      ),
      '12.50',
    );
  });

  test('la linea usa el precio configurado y un medio real', () {
    final efectivo = PaymentMethod(
      id: 3,
      denominacion: 'Efectivo',
      esDigital: false,
      esEfectivo: true,
      esActivo: true,
    );
    final medio = DetalleMoneda.medioReal([
      PaymentMethod.pagoPendiente(),
      efectivo,
    ]);
    expect(medio?.id, 3);
    final linea = DetalleMoneda.seleccion(
      idProducto: 8,
      cantidad: 2,
      moneda: 'USD',
      precio: '10.00',
      tasa: '400.00',
      idMedioPago: 3,
    );
    expect(linea.precioUnitarioNativo, '10.00');
    expect(linea.snapshotPrecio['valor_publicado'], '10.00');
    expect(linea.monedaVenta, 'USD');
  });

  test('el script deja guardar el flag y no lo enciende solo', () {
    final sql = File(
      '../docs/plan-multimoneda/m01_r25_activar_flag_tienda_propuesta.sql',
    ).readAsStringSync();
    expect(sql.contains('DROP CONSTRAINT IF EXISTS m01_politica_flag_apagada'), isTrue);
    expect(sql.contains('permitir_moneda_por_producto = p_activar'), isTrue);
    expect(sql.contains('UPDATE public.app_dat_configuracion_tienda\n    SET permitir_moneda_por_producto = true'), isFalse);
  });
}
