import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String sql;

  setUpAll(() {
    sql = File(
      '../docs/plan-multimoneda/m01_r0a_duenos_propuesta.sql',
    ).readAsStringSync();
  });

  test('el borrador exige revision y el baseline exacto de newa', () {
    expect(sql.trimLeft(), startsWith('BEGIN;'));
    expect(sql.trimRight(), endsWith('COMMIT;'));
    expect(sql, contains("current_user <> 'postgres'"));
    expect(
      sql,
      contains("current_setting('app.m01_r0a_duenos_approved', true)"),
    );
    expect(sql, contains('c4360cbdbd89585ab687c878a9536a5a'));
    expect(sql, contains("SET LOCAL lock_timeout = '5s'"));
  });

  test('usa un predicado acotado sin cambiar helpers compartidos ni FDI', () {
    expect(
      sql,
      contains('CREATE FUNCTION public.fn_m01_fuentes_puede_gestionar_duenos'),
    );
    expect(sql, contains('SET search_path = pg_catalog'));
    expect(sql, contains('auth.uid() IS NOT NULL'));
    expect(sql, contains('p_id_tienda IS NOT NULL'));
    expect(sql, contains('s.activo = true AND s.nivel_acceso = 1'));
    expect(sql, isNot(contains('CREATE OR REPLACE FUNCTION')));
    expect(sql, isNot(contains('FUNCTION public.fn_user_is_dueno(')));
    expect(sql, isNot(contains('fdi_')));
  });

  test('reemplaza solo las cuatro policies conocidas y conserva RLS', () {
    for (final action in ['select', 'insert', 'update', 'delete']) {
      expect(
        sql,
        contains('DROP POLICY app_dat_dueno_$action ON public.app_dat_dueno;'),
      );
      expect(sql, contains('CREATE POLICY app_dat_dueno_$action'));
    }
    expect(RegExp('CREATE POLICY').allMatches(sql), hasLength(4));
    expect(
      sql,
      contains('ALTER TABLE public.app_dat_dueno ENABLE ROW LEVEL SECURITY;'),
    );
    expect(sql, contains('FOR UPDATE TO authenticated'));
    expect(sql, contains('FOR INSERT TO authenticated'));
    expect(sql, isNot(contains('DROP POLICY IF EXISTS')));
    expect(
      RegExp(r'USING\s*\(true\)', caseSensitive: false).hasMatch(sql),
      isFalse,
    );
    expect(sql, isNot(contains('CREATE TABLE')));
  });

  test('limita privilegios sin editar datos ni convertir historicos', () {
    expect(sql, contains('FROM PUBLIC, anon, authenticated;'));
    expect(
      sql,
      contains(
        'GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.app_dat_dueno TO authenticated;',
      ),
    );
    expect(sql, contains('FROM PUBLIC, anon;'));
    expect(sql, isNot(contains('UPDATE public.app_dat_')));
    expect(sql, isNot(contains('INSERT INTO public.app_dat_')));
    expect(sql, isNot(contains('DELETE FROM public.app_dat_')));
    expect(sql, isNot(contains('TRUNCATE TABLE')));
    expect(sql, isNot(contains('permitir_moneda_por_producto')));
  });

  test('preflight y verificador son de lectura, no una prueba RLS funcional', () {
    for (final name in [
      'preflight_m01_fuentes_autorizacion.sql',
      'verificar_m01_r0a_duenos.sql',
    ]) {
      final query = File('../docs/plan-multimoneda/$name').readAsStringSync();
      expect(query, contains('ISOLATION LEVEL REPEATABLE READ, READ ONLY'));
      expect(
        RegExp(
          r'^\s*(CREATE|ALTER|DROP|GRANT|REVOKE|INSERT|UPDATE|DELETE|TRUNCATE)\s',
          multiLine: true,
          caseSensitive: false,
        ).hasMatch(query),
        isFalse,
      );
    }
    final verifier = File(
      '../docs/plan-multimoneda/verificar_m01_r0a_duenos.sql',
    ).readAsStringSync();
    expect(verifier, contains('no demuestra permisos funcionales'));
  });
}
