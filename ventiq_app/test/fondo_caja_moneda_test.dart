import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/money/fondo_caja_moneda.dart';

void main() {
  final cup = {
    'denominacion': 'BPA',
    'moneda': {'codigo': 'cup'},
  };

  test('lee el código de la moneda de la cuenta', () {
    expect(FondoCajaMoneda.codigo(cup), 'CUP');
    expect(FondoCajaMoneda.codigo({'denominacion': 'BPA'}), isNull);
    expect(FondoCajaMoneda.codigo(null), isNull);
  });

  test('solo admite egresos en la moneda de la cuenta', () {
    expect(FondoCajaMoneda.rechazo(cup, 'CUP'), isNull);
    expect(FondoCajaMoneda.rechazo(cup, ' cup '), isNull);
    expect(FondoCajaMoneda.rechazo(cup, 'USD'), contains('solo admite egresos en CUP'));
  });

  test('sin moneda conocida en el caché no se contabiliza', () {
    expect(
      FondoCajaMoneda.rechazo({'denominacion': 'BPA'}, 'CUP'),
      contains('Sincronice online'),
    );
  });

  test('las RPC del fondo mandan la moneda (v2) y el SQL la exige', () {
    final pantalla = File('lib/screens/egreso_screen.dart').readAsStringSync();
    final sync = File('lib/services/auto_sync_service.dart').readAsStringSync();
    expect(pantalla, contains("'fn_registrar_egreso_fondo_caja_v2'"));
    expect(pantalla, contains("'p_moneda': _selectedDivisa"));
    expect(sync, contains("'fn_registrar_egreso_fondo_caja_v2'"));
    expect(sync, contains("'p_moneda': moneda"));
    for (final src in [pantalla, sync]) {
      expect(src, isNot(contains("'fn_registrar_egreso_fondo_caja',")));
    }

    final sql =
        File('../sql_updates/fn_registrar_egreso_fondo_caja_v2_moneda.sql')
            .readAsStringSync();
    expect(sql, contains('v_moneda_banco <> v_moneda'));
    expect(sql, contains('fn_registrar_egreso_offline_v2'));
  });
}
