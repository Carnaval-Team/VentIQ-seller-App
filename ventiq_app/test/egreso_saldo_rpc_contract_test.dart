import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File(
    '../sql_updates/fn_egreso_validar_saldo_caja.sql',
  ).readAsStringSync();

  test('el helper calcula disponible por moneda y medio', () {
    expect(sql, contains('CREATE OR REPLACE FUNCTION public.fn_caja_disponible_para_egreso'));
    expect(sql, contains('fn_operacion_completada'));
    expect(sql, contains('fn_operacion_en_turno'));
    expect(sql, contains('IS DISTINCT FROM 998'));
    expect(sql, contains('app_dat_caja_turno_moneda'));
    expect(sql, contains('efectivo_inicial_usd'));
  });

  test('la v2 rechaza egreso sin saldo y serializa por turno', () {
    expect(sql, contains('CREATE OR REPLACE FUNCTION public.fn_registrar_egreso_offline_v2'));
    expect(sql, contains("'EGRESO_SIN_SALDO'"));
    expect(sql, contains('fn_caja_disponible_para_egreso'));
    expect(sql, contains("'egreso-saldo:'"));
    expect(sql, contains('pg_advisory_xact_lock'));
  });

  test('el TPV y la cola siguen usando la v2 con moneda', () {
    final pantalla = File('lib/screens/egreso_screen.dart').readAsStringSync();
    final sync = File('lib/services/auto_sync_service.dart').readAsStringSync();
    expect(pantalla, contains("'fn_registrar_egreso_offline_v2'"));
    expect(pantalla, contains("'p_moneda': _selectedDivisa"));
    expect(sync, contains("'fn_registrar_egreso_offline_v2'"));
    expect(sync, contains("'p_moneda': moneda"));
  });
}
