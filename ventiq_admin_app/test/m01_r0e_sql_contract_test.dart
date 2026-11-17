import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File(
    '../docs/plan-multimoneda/m01_r0e_operaciones_tienda_idempotencia_propuesta.sql',
  ).readAsStringSync().replaceAll('\r\n', '\n');

  test('instalacion explicita y baseline exacto', () {
    expect(sql.trimLeft(), startsWith('BEGIN;'));
    expect(sql.trimRight(), endsWith('COMMIT;'));
    expect(sql, contains("current_user <> 'postgres'"));
    expect(sql, contains("current_setting('app.m01_r0e_approved', true)"));
    expect(sql, contains("'tienda policy'"));
    expect(
      sql,
      contains("'Open access to operaciones', 'operaciones permitidas'"),
    );
    expect(sql, contains('relrowsecurity'));
    expect(sql, isNot(contains('CREATE OR REPLACE FUNCTION')));
    expect(sql, isNot(contains('ON public.app_dat_superadmin')));
    expect(sql, isNot(contains('ON TABLE public.app_dat_superadmin')));
  });

  test('helper operar DEFINER pg_catalog distinto de leer', () {
    expect(
      sql,
      contains('CREATE FUNCTION public.fn_m01_operaciones_puede_operar('),
    );
    expect(
      sql,
      contains('STABLE\nSECURITY DEFINER\nSET search_path = pg_catalog'),
    );
    expect(sql, contains('FROM public.app_dat_vendedor v'));
    expect(sql, contains('FROM public.app_dat_almacenero a'));
    expect(sql, contains('FROM public.app_dat_jefe_cocina j'));
    expect(
      sql,
      contains(
        'GRANT EXECUTE ON FUNCTION public.fn_m01_operaciones_puede_operar(bigint) TO authenticated;',
      ),
    );
  });

  test(
    'tienda y operaciones: leer amplio, escribir acotado, sin policies publicas',
    () {
      for (final p in [
        'DROP POLICY "tienda policy" ON public.app_dat_tienda;',
        'DROP POLICY "Open access to operaciones" ON public.app_dat_operaciones;',
        'DROP POLICY "operaciones permitidas" ON public.app_dat_operaciones;',
      ]) {
        expect(sql, contains(p));
      }
      expect(RegExp('CREATE POLICY m01_').allMatches(sql), hasLength(7));
      // INSERT de operaciones exige operar; UPDATE/DELETE solo admin.
      expect(
        sql,
        contains(
          'FOR INSERT TO authenticated\n'
          '    WITH CHECK (public.fn_m01_operaciones_puede_operar(id_tienda))',
        ),
      );
      // Tienda no tiene policy INSERT ni DELETE.
      expect(sql, isNot(contains('m01_tienda_insertar')));
      expect(sql, isNot(contains('m01_tienda_eliminar')));
      expect(sql, isNot(contains('USING (true)')));
      expect(sql, isNot(contains('TO public')));
    },
  );

  test('idempotencia revoca privilegios efectivos tabulares y por columna', () {
    expect(
      sql,
      contains(
        'REVOKE ALL ON TABLE public.app_dat_operacion_offline_idempotencia FROM PUBLIC, anon, authenticated;',
      ),
    );
    expect(sql, contains('FROM pg_attribute'));
    expect(sql, contains('NOT attisdropped'));
    expect(sql, contains('REVOKE ALL (%s) ON TABLE public.app_dat_operacion_offline_idempotencia FROM PUBLIC, anon, authenticated'));
    expect(sql, contains('has_any_column_privilege'));
    expect(sql, contains("'TRUNCATE'"));
    expect(sql, contains("'TRIGGER'"));
  });

  test('enmienda R0e2: cierra PUBLIC y columnas sobre R0e ya aplicado', () {
    final enmienda = File(
      '../docs/plan-multimoneda/m01_r0e2_idempotencia_revokes_propuesta.sql',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    expect(enmienda.trimLeft(), startsWith('BEGIN;'));
    expect(enmienda.trimRight(), endsWith('COMMIT;'));
    expect(enmienda, contains("current_setting('app.m01_r0e2_approved', true)"));
    expect(enmienda, contains('m01_idempotencia_leer'));
    expect(
      enmienda,
      contains(
        'REVOKE ALL ON TABLE public.app_dat_operacion_offline_idempotencia FROM PUBLIC, anon, authenticated;',
      ),
    );
    expect(enmienda, contains('FROM pg_attribute'));
    expect(enmienda, contains('NOT attisdropped'));
    expect(
      enmienda,
      contains(
        'REVOKE ALL (%s) ON TABLE public.app_dat_operacion_offline_idempotencia FROM PUBLIC, anon, authenticated',
      ),
    );
    expect(
      enmienda,
      contains(
        "has_table_privilege('authenticated', 'public.app_dat_operacion_offline_idempotencia', 'TRUNCATE')",
      ),
    );
    expect(enmienda, isNot(contains('CREATE POLICY')));
    expect(enmienda, isNot(contains('DROP POLICY')));
  });

  test('idempotencia: RLS on, lectura propia, sin escritura cliente', () {
    expect(
      sql,
      contains(
        'ALTER TABLE public.app_dat_operacion_offline_idempotencia ENABLE ROW LEVEL SECURITY;',
      ),
    );
    expect(sql, contains('m01_idempotencia_leer'));
    expect(sql, contains('uuid_usuario = auth.uid()'));
    expect(
      sql,
      contains(
        'GRANT SELECT ON TABLE public.app_dat_operacion_offline_idempotencia TO authenticated;',
      ),
    );
    expect(
      RegExp(
        'REVOKE ALL ON TABLE public.app_dat_\\w+ FROM anon;',
      ).allMatches(sql),
      hasLength(2),
    );
    expect(sql, isNot(contains('INSERT INTO public.app_dat_')));
    expect(sql, isNot(contains('UPDATE public.app_dat_')));
    expect(sql, isNot(contains('DELETE FROM public.app_dat_')));
  });
}
