import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final fix = File(
    '../sql_updates/fix_m01_venta_v1_pago_directo_tg_table.sql',
  ).readAsStringSync();
  final r15 = File(
    '../docs/plan-multimoneda/m01_r15_pagos_v1_propuesta.sql',
  ).readAsStringSync();

  test('H9 usa IF anidados por TG_TABLE_NAME', () {
    expect(fix, contains("IF TG_TABLE_NAME = 'app_dat_pago_venta' THEN"));
    expect(fix, contains("ELSIF TG_TABLE_NAME = 'app_dat_operacion_venta' THEN"));
    expect(
      fix,
      isNot(
        contains(
          "IF TG_TABLE_NAME = 'app_dat_operacion_venta'\n"
          "       AND NEW.version_monetaria",
        ),
      ),
    );
  });

  test('R15 propuesta ya incluye el arreglo H9', () {
    final body = r15.substring(
      r15.indexOf('CREATE FUNCTION public.fn_m01_venta_v1_pago_directo'),
      r15.indexOf('DROP TRIGGER IF EXISTS m01_pago_v1_directo'),
    );
    expect(body, contains("IF TG_TABLE_NAME = 'app_dat_pago_venta' THEN"));
    expect(body, contains('ELSIF TG_TABLE_NAME'));
  });
}
