import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String entrega;

  setUpAll(() {
    entrega = File(
      '../docs/plan-multimoneda/m01_r07_constancia_politica_propuesta.sql',
    ).readAsStringSync().replaceAll('\r\n', '\n');
  });

  test('la entrega queda ligada a la revision y no alarga la licencia', () {
    expect(entrega.trimLeft(), startsWith('BEGIN;'));
    expect(entrega.trimRight(), endsWith('COMMIT;'));
    expect(
      entrega,
      contains("current_setting('app.m01_r07_constancia_approved', true)"),
    );
    expect(entrega, contains('ENABLE ROW LEVEL SECURITY'));
    expect(entrega, contains('FORCE ROW LEVEL SECURITY'));
    expect(entrega, contains('uuid_sujeto = auth.uid()'));
    expect(entrega, contains('fn_config_tienda_puede_leer'));
    expect(entrega, contains('app_dat_politica_moneda_revision'));
    expect(entrega, contains('dias_max_sin_validar_licencia'));
    expect(entrega, contains('permitir_modo_offline_completo'));
    expect(entrega, contains('estado = 1'));
    expect(entrega, contains('Constancia ajena o manipulada'));
    expect(entrega, contains('No hay revision de politica publicada'));
    expect(entrega, contains('La entrega de politica no se edita'));
    expect(entrega, contains("'idempotent', true"));
    expect(entrega, contains('usable_offline'));
    expect(entrega, isNot(contains('UPDATE public.app_suscripciones')));
    expect(entrega, isNot(contains('UPDATE public.app_dat_configuracion_tienda')));
    expect(entrega, isNot(contains('app_dat_licencia_offline_secreto')));
    expect(entrega, isNot(contains('precio_venta')));
    expect(entrega, isNot(contains('p_creado')));
    expect(entrega, isNot(contains('ON CONFLICT')));
    expect(entrega, isNot(contains('FOR INSERT TO')));
    expect(entrega, isNot(contains('FOR UPDATE TO')));
    expect(entrega, isNot(contains('FOR DELETE TO')));
  });
}
