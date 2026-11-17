import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('el descuento y el traslado prueban la RPC antes de escribir', () {
    final src = File(
      'lib/services/order_service.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final discount = src.substring(
      src.indexOf('Future<Map<String, dynamic>> applyManualDiscount'),
      src.indexOf('Future<Map<String, dynamic>> updateCustomerInfo'),
    );
    final move = src.substring(
      src.indexOf('Future<Map<String, dynamic>> moveSalePaymentAmount'),
      src.indexOf('Future<Map<String, dynamic>> _moveSalePaymentAmountOffline'),
    );
    expect(
      discount.indexOf('fn_m01_aplicar_descuento_manual'),
      lessThan(discount.indexOf('app_dat_descuentos_vendedor')),
    );
    expect(
      discount.indexOf("_isRpcUnavailable"),
      lessThan(discount.indexOf('app_dat_descuentos_vendedor')),
    );
    expect(
      move.indexOf('fn_m01_mover_pago_venta'),
      lessThan(move.indexOf('app_dat_pago_venta')),
    );
    expect(
      move.indexOf("_isRpcUnavailable"),
      lessThan(move.indexOf('app_dat_pago_venta')),
    );
  });
}
