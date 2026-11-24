import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/services/rpc_m01.dart';

void main() {
  test('m01Name agrega el sufijo', () {
    expect(RpcM01.m01Name('fn_listar_ordenes'), 'fn_listar_ordenes_m01');
  });

  test('isUnavailable distingue ausencia de denegación', () {
    expect(
      RpcM01.isUnavailable(
        Exception('PGRST202 Could not find the function'),
        'fn_listar_ordenes_m01',
      ),
      isTrue,
    );
    expect(
      RpcM01.isUnavailable(Exception('42501 acceso denegado'), 'fn_x_m01'),
      isFalse,
    );
  });

  test('el helper del admin coincide con el del TPV', () {
    final admin = File('lib/services/rpc_m01.dart').readAsStringSync();
    final tpv =
        File('../ventiq_app/lib/services/rpc_m01.dart').readAsStringSync();
    expect(admin, tpv);
  });
}
