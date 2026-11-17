import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/money/exact_money.dart';
import 'package:ventiq_app/money/line_money.dart';
import 'package:ventiq_app/models/order.dart';
import 'package:ventiq_app/models/product.dart';
import 'package:ventiq_app/money/product_currency_order.dart';

void main() {
  final fixtures =
      jsonDecode(
            File(
              '../docs/plan-multimoneda/product_currency_v1_fixtures.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;

  test('los vectores de la linea coinciden con el fixture', () {
    final cases = (fixtures['money_cases'] as List).cast<Map<String, dynamic>>();
    for (final c in cases) {
      final result = LineMoneyCalculator.calcular(
        moneda: c['currency'] as String,
        cantidad: c['quantity'] as String,
        precioUnitario: c['unit_price'] as String,
        automaticoTipo: c['automatic_type'] as String,
        automaticoValor: c['automatic_value'] as String,
        manualUnitario: c['manual_unit_discount'] as String,
        tasaCup: c['rate_cup'] as String,
      );
      final expected = Map<String, String>.from(c['expected'] as Map);
      expect(result.toFixture(), expected, reason: c['id'] as String);
    }
    final cero = cases.singleWhere((c) => c['id'] == 'authorized_zero_net');
    final gratuidad = LineMoneyCalculator.calcular(
      moneda: cero['currency'] as String,
      cantidad: cero['quantity'] as String,
      precioUnitario: cero['unit_price'] as String,
      automaticoTipo: cero['automatic_type'] as String,
      automaticoValor: cero['automatic_value'] as String,
      manualUnitario: cero['manual_unit_discount'] as String,
      tasaCup: cero['rate_cup'] as String,
    );
    expect(gratuidad.esGratuidad, isTrue);
    expect(gratuidad.neto, ExactMoney.cero);
  });

  test('el precio ausente o cero no se trata como gratuidad', () {
    expect(
      () => LineMoneyCalculator.calcular(
        moneda: 'CUP',
        cantidad: '1',
        precioUnitario: null,
        automaticoTipo: 'none',
        automaticoValor: '0',
        manualUnitario: '0',
        tasaCup: '1',
      ),
      throwsA(
        isA<LineMoneyException>().having(
          (e) => e.code,
          'code',
          'NATIVE_PRICE_UNAVAILABLE',
        ),
      ),
    );
    expect(
      () => LineMoneyCalculator.calcular(
        moneda: 'CUP',
        cantidad: '1',
        precioUnitario: '0',
        automaticoTipo: 'none',
        automaticoValor: '0',
        manualUnitario: '0',
        tasaCup: '1',
      ),
      throwsA(isA<LineMoneyException>()),
    );
  });

  test('tres lineas de un centimo suman tres centimos', () {
    LineMoney una() {
      return LineMoneyCalculator.calcular(
        moneda: 'USD',
        cantidad: '1',
        precioUnitario: '0.005',
        automaticoTipo: 'none',
        automaticoValor: '0',
        manualUnitario: '0',
        tasaCup: '400',
      );
    }

    final suma = LineMoneyCalculator.sumarNetos([una(), una(), una()]);
    expect(suma.toFixed(2), '0.03');
  });

  test('dos lineas del mismo producto conservan moneda y medio', () {
    final cup = _seleccion(
      id: '44444444-4444-4444-8444-444444444441',
      moneda: 'CUP',
      medio: 1,
    );
    final usd = _seleccion(
      id: '44444444-4444-4444-8444-444444444442',
      moneda: 'USD',
      medio: 4,
    );
    final order = _orden([cup, usd]);
    final restored = Order.fromJson(order.toJson());
    expect(restored.versionMonetaria, 'producto-v1');
    expect(restored.clientUuid, order.clientUuid);
    expect(restored.items.map((e) => e.seleccion!.monedaVenta), ['CUP', 'USD']);
    expect(restored.items.map((e) => e.seleccion!.idMedioPago), [1, 4]);
    expect(
      restored.items.map((e) => e.producto.id).toSet(),
      {order.items.first.producto.id},
    );
  });

  test('una orden vieja no toma la moneda de los pagos', () {
    final order = Order(
      id: 'legacy-1',
      fechaCreacion: DateTime.utc(2026, 1, 1),
      items: [_item(null)],
      total: 10,
      status: OrderStatus.borrador,
    );
    final raw = order.toJson();
    expect(raw.containsKey('version_monetaria'), isFalse);
    raw['desglose_pagos'] = [
      {'moneda': 'USD', 'monto': 5},
    ];
    final read = PendingSaleCodec.leer(raw);
    expect(read['items'].single.containsKey('seleccion'), isFalse);
    expect(Order.fromJson(read).versionMonetaria, isNull);
  });

  test('una version desconocida o una linea incompleta se rechazan', () {
    final raw = _orden([
      _seleccion(
        id: '44444444-4444-4444-8444-444444444441',
        moneda: 'CUP',
        medio: 1,
      ),
    ]).toJson();
    raw['version_monetaria'] = 'producto-v999';
    expect(
      () => Order.fromJson(raw),
      throwsA(isA<ProductCurrencyException>()),
    );
    final incompleta = Map<String, dynamic>.from(raw);
    incompleta['version_monetaria'] = 'producto-v1';
    (incompleta['items'] as List).single['seleccion']['precio_unitario_nativo'] =
        0.1;
    expect(
      () => PendingSaleCodec.leer(incompleta),
      throwsA(
        isA<ProductCurrencyException>().having(
          (e) => e.code,
          'code',
          'DECIMAL_STRING_REQUIRED',
        ),
      ),
    );
  });

  test('el esquema no reescribe pagos ni omite RLS', () {
    final extraccion =
        File(
          '../docs/plan-multimoneda/m01_r12_extraccion_v1_propuesta.sql',
        ).readAsStringSync();
    final aplicacion =
        File(
          '../docs/plan-multimoneda/m01_r12_pago_aplicacion_propuesta.sql',
        ).readAsStringSync();
    expect(extraccion.contains('UPDATE public.app_dat_'), isFalse);
    expect(aplicacion.contains('INSERT INTO public.app_dat_pago_venta'), isFalse);
    expect(aplicacion.contains('ENABLE ROW LEVEL SECURITY'), isTrue);
    expect(aplicacion.contains('FORCE ROW LEVEL SECURITY'), isTrue);
    expect(aplicacion.contains('WITH CHECK (false)'), isTrue);
  });
}

ProductCurrencySeleccion _seleccion({
  required String id,
  required String moneda,
  required int medio,
}) {
  return ProductCurrencySeleccion(
    idLineaCliente: id,
    idProducto: '101',
    cantidad: '1',
    monedaVenta: moneda,
    tipoCobro: 'medio_pago',
    idMedioPago: medio,
    precioUnitarioNativo: moneda == 'CUP' ? '100' : '1.05',
    descuentoManualUnitario: '0',
    snapshotPrecio: {'tipo': 'general', 'valor_publicado': '1'},
    snapshotTasa:
        moneda == 'USD'
            ? {'valor_publicado': '400', 'evidencia_publicacion': 'fixture-only'}
            : {'valor_publicado': '1'},
    ajustesAutomaticos: const [],
  );
}

OrderItem _item(ProductCurrencySeleccion? seleccion) {
  return OrderItem(
    id: seleccion?.idLineaCliente ?? 'legacy-item',
    producto: Product.fromJson({
      'id': 101,
      'denominacion': 'Cafe',
      'precio': 100,
      'precio_venta_usd': 1.05,
    }),
    cantidad: 1,
    precioUnitario: 100,
    ubicacionAlmacen: 'mostrador',
    seleccion: seleccion,
  );
}

Order _orden(List<ProductCurrencySeleccion> lineas) {
  return Order(
    id: 'orden-1',
    fechaCreacion: DateTime.utc(2030, 1, 15),
    items: lineas.map(_item).toList(),
    total: 0,
    status: OrderStatus.borrador,
    versionMonetaria: ProductCurrencySeleccion.version,
    clientUuid: '11111111-1111-4111-8111-111111111111',
  );
}
