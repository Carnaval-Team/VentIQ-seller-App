import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final g2 = File(
    '../sql_updates/fn_config_tienda_puede_leer_g2.sql',
  ).readAsStringSync();
  final s01 = File(
    '../docs/plan-multimoneda/configuracion_tienda_rls_propuesta.sql',
  ).readAsStringSync();

  test('G2 incluye RH y trabajador en puede_leer', () {
    expect(g2, contains('app_dat_recursos_humanos'));
    expect(g2, contains('app_dat_trabajadores'));
    expect(g2, contains('fn_config_tienda_puede_leer'));
    expect(g2, contains("tr.uuid = auth.uid()"));
    expect(g2, contains("rh.uuid = auth.uid()"));
  });

  test('S01 propuesta ya lleva G2 para el pase a main', () {
    final leer = s01.substring(
      s01.indexOf('CREATE FUNCTION public.fn_config_tienda_puede_leer'),
      s01.indexOf('CREATE FUNCTION public.fn_config_tienda_exigir_lectura'),
    );
    expect(leer, contains('app_dat_recursos_humanos'));
    expect(leer, contains('app_dat_trabajadores'));
  });
}
