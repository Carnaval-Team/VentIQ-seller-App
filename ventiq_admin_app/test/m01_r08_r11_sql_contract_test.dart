import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String aislamiento;
  late String capacidad;
  late String columna;
  late String resolver;
  late String alta;

  setUpAll(() {
    String load(String name) => File(
      '../docs/plan-multimoneda/$name',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    aislamiento = load('m01_r08_idempotencia_aislamiento_propuesta.sql');
    capacidad = load('m01_r09_capacidad_politica_propuesta.sql');
    columna = load('m01_r10_precio_tpv_usd_propuesta.sql');
    resolver = load('m01_r11_precio_tpv_resolver_propuesta.sql');
    alta = load('m01_r11_precio_tpv_guardar_propuesta.sql');
  });

  test('la clave ajena no se lee', () {
    expect(aislamiento.trimLeft(), startsWith('BEGIN;'));
    expect(aislamiento.trimRight(), endsWith('COMMIT;'));
    expect(aislamiento, contains('uuid_usuario = auth.uid()'));
    expect(aislamiento, contains('fn_config_tienda_puede_leer(m01_id_tienda)'));
    expect(aislamiento, contains('fn_m01_leer_idempotencia'));
    expect(aislamiento, contains('SECURITY INVOKER'));
    expect(aislamiento, isNot(contains('JOIN public.app_dat_operacion')));
    expect(aislamiento, isNot(contains('fn_admin_caja_')));
  });

  test('el flag no se puede encender', () {
    expect(capacidad.trimRight(), endsWith('COMMIT;'));
    expect(capacidad, contains('Definicion desconocida del flag de moneda por producto'));
    expect(capacidad, contains('Activacion de moneda por producto no autorizada'));
    expect(capacidad, contains("'activacion_permitida', false"));
    expect(capacidad, contains('falta el registro de venta v1'));
    expect(capacidad, contains('fn_m01_publicar_revision_politica'));
    expect(capacidad, isNot(contains('permitir_moneda_por_producto = true')));
  });

  test('el USD del TPV no reemplaza al CUP', () {
    expect(columna, contains('ADD COLUMN precio_venta_usd numeric'));
    expect(columna, contains('m01_precio_tpv_cup_obligatorio'));
    expect(columna, contains('precio_venta_cup > 0'));
    expect(columna, contains('ENABLE ROW LEVEL SECURITY'));
    expect(columna, contains('FORCE ROW LEVEL SECURITY'));
    expect(columna, contains('fn_m01_tienda_precio_tpv'));
    expect(columna, contains('REVOKE ALL ON TABLE public.app_dat_precio_tpv FROM anon'));
    expect(columna, isNot(contains('DROP NOT NULL')));
    expect(columna, isNot(contains('precio_venta_cup numeric')));
  });

  test('el resolver no rescata un USD viejo', () {
    expect(resolver, contains('ORDER BY t.id DESC'));
    expect(resolver, contains('LIMIT 1'));
    expect(resolver, contains("origen_usd := 'tpv'"));
    expect(resolver, contains("origen_usd := 'general'"));
    expect(resolver, contains("origen_usd := 'no_disponible'"));
    expect(resolver, contains('app_v_precio_venta_base_vigente'));
    expect(resolver, contains('v_tpv_id IS NOT NULL AND v_tpv_usd IS NOT NULL'));
    expect(resolver, isNot(contains('WHERE t.precio_venta_usd IS NOT NULL')));
  });

  test('el alta no reescribe la vigencia anterior', () {
    expect(alta.trimRight(), endsWith('COMMIT;'));
    expect(alta, contains('fn_m01_guardar_precio_tpv'));
    expect(alta, contains('auth.uid()'));
    expect(alta, contains('fn_config_tienda_puede_escribir'));
    expect(alta, contains("'idempotent', true"));
    expect(alta, contains('INSERT INTO public.app_dat_precio_tpv'));
    expect(alta, isNot(contains('UPDATE public.app_dat_precio_tpv')));
    expect(alta, isNot(contains('ON CONFLICT')));
  });
}
