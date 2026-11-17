import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String politica;
  late String configTienda;

  setUpAll(() {
    politica = File(
      '../docs/plan-multimoneda/m01_r06_politica_revision_propuesta.sql',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    configTienda = File(
      '../docs/plan-multimoneda/m01_r0i_config_tienda_propuesta.sql',
    ).readAsStringSync().replaceAll('\r\n', '\n');
  });

  test('el flag nace apagado y la revision no se edita', () {
    expect(politica.trimLeft(), startsWith('BEGIN;'));
    expect(politica.trimRight(), endsWith('COMMIT;'));
    expect(
      politica,
      contains("current_setting('app.m01_r06_politica_approved', true)"),
    );
    expect(
      politica,
      contains(
        'ADD COLUMN permitir_moneda_por_producto boolean NOT NULL DEFAULT false',
      ),
    );
    expect(politica, contains('CHECK (permitir_moneda_por_producto = false)'));
    expect(politica, contains('ENABLE ROW LEVEL SECURITY'));
    expect(politica, contains('FORCE ROW LEVEL SECURITY'));
    expect(politica, contains('FOR SELECT TO authenticated'));
    expect(politica, contains('fn_config_tienda_puede_leer(id_tienda)'));
    expect(politica, contains('auth.uid()'));
    expect(politica, contains('fn_config_tienda_puede_escribir'));
    expect(politica, contains('forzar_moneda_venta'));
    expect(politica, contains('moneda_venta_forzada'));
    expect(politica, contains('app_dat_tienda_moneda'));
    expect(politica, contains('Activacion de moneda por producto no autorizada'));
    expect(politica, contains('La revision de politica no se edita'));
    expect(politica, contains('permitir_moneda_por_producto = false'));
    expect(politica, isNot(contains('constancia')));
    expect(politica, isNot(contains('ON CONFLICT')));
    expect(politica, isNot(contains('permitir_moneda_por_producto = true')));
    expect(
      politica,
      isNot(contains('UPDATE public.app_dat_politica_moneda_revision')),
    );
    expect(politica, isNot(contains('FOR INSERT TO')));
    expect(politica, isNot(contains('FOR UPDATE TO')));
    expect(politica, isNot(contains('FOR DELETE TO')));
  });

  test('la configuracion del TPV no escribe el flag', () {
    expect(configTienda, isNot(contains('permitir_moneda_por_producto')));
  });
}
