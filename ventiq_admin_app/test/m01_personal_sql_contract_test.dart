import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File(
    '../docs/plan-multimoneda/m01_r0b_guard_reasignacion_vendedor_propuesta.sql',
  ).readAsStringSync().replaceAll('\r\n', '\n');

  test('contrato estatico R0b: instalacion explicita y guarda interna', () {
    expect(sql.trimLeft(), startsWith('BEGIN;'));
    expect(sql.trimRight(), endsWith('COMMIT;'));
    expect(sql, contains("current_user <> 'postgres'"));
    expect(
      sql,
      contains("current_setting('app.m01_r0b_guard_approved', true)"),
    );
    expect(
      sql,
      contains('VOLATILE\nSECURITY DEFINER\nSET search_path = pg_catalog'),
    );
    expect(sql, contains('FROM PUBLIC, anon, authenticated, service_role;'));
    expect(sql, isNot(contains('GRANT EXECUTE')));
    expect(sql, isNot(contains('CREATE TABLE')));
    expect(sql, isNot(contains('CREATE POLICY')));
    expect(sql, isNot(contains('CREATE OR REPLACE FUNCTION')));
  });

  test('contrato estatico R0b: actor real y ambos ambitos derivados en DB', () {
    final signature = sql.substring(
      sql.indexOf('CREATE FUNCTION'),
      sql.indexOf('RETURNS void'),
    );
    expect(signature, contains('p_id_vendedor bigint'));
    expect(signature, contains('p_id_tpv bigint'));
    expect(signature, isNot(contains('p_uuid')));
    expect(signature, isNot(contains('p_id_tienda')));
    expect(sql, contains('auth.uid() IS NULL'));
    expect(sql, contains('FROM public.app_dat_vendedor v'));
    expect(sql, contains('FROM public.app_dat_trabajadores w'));
    expect(sql, contains('FROM public.app_dat_tpv t'));
    for (final scope in ['v_old_store', 'v_new_store']) {
      expect(
        sql,
        contains(
          'fn_config_tienda_puede_escribir($scope) IS DISTINCT FROM true',
        ),
      );
    }
    expect(sql, contains("USING ERRCODE = '42501'"));
  });

  test('contrato estatico R0b: coherencia y locks sin modificar registros', () {
    expect(sql, contains('FOR UPDATE;'));
    expect(RegExp('FOR SHARE;').allMatches(sql), hasLength(3));
    expect(sql, contains('v_worker_uuid IS DISTINCT FROM v_uuid'));
    expect(sql, contains('v_worker_store IS DISTINCT FROM v_old_tpv_store'));
    expect(sql, contains('v_worker_store IS DISTINCT FROM v_new_store'));
    expect(
      sql,
      contains(
        'IF p_id_tpv IS NULL THEN\n        v_new_store := v_worker_store;',
      ),
    );
    expect(sql, isNot(contains('UPDATE public.app_dat_')));
    expect(sql, isNot(contains('INSERT INTO public.app_dat_')));
    expect(sql, isNot(contains('DELETE FROM public.app_dat_')));
    expect(sql, isNot(contains('app_dat_operacion_offline_idempotencia')));
  });

  group('contrato estatico R0b-RPC: entrada reasignacion vendedor', () {
    final rpc = File(
      '../docs/plan-multimoneda/m01_r0b_rpc_reasignacion_vendedor_propuesta.sql',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    test('instalacion explicita, dependencia de la guarda y preflight', () {
      expect(rpc.trimLeft(), startsWith('BEGIN;'));
      expect(rpc.trimRight(), endsWith('COMMIT;'));
      expect(rpc, contains("current_user <> 'postgres'"));
      expect(
        rpc,
        contains("current_setting('app.m01_r0b_rpc_approved', true)"),
      );
      expect(
        rpc,
        contains(
          "to_regprocedure('public.fn_m01_personal_exigir_reasignacion_vendedor(bigint,bigint)') IS NULL",
        ),
      );
      expect(rpc, isNot(contains('CREATE OR REPLACE FUNCTION')));
      expect(rpc, isNot(contains('CREATE POLICY')));
    });

    test(
      'firma sin actor ni ambito declarados y DEFINER con search_path fijo',
      () {
        final signature = rpc.substring(
          rpc.indexOf('CREATE FUNCTION'),
          rpc.indexOf('RETURNS boolean'),
        );
        expect(signature, contains('p_id_vendedor bigint'));
        expect(signature, contains('p_id_tpv bigint'));
        expect(signature, isNot(contains('p_uuid')));
        expect(signature, isNot(contains('p_id_tienda')));
        expect(
          rpc,
          contains('VOLATILE\nSECURITY DEFINER\nSET search_path = pg_catalog'),
        );
      },
    );

    test('valida con la guarda y solo reasigna id_tpv del vendedor', () {
      expect(
        rpc,
        contains(
          'PERFORM public.fn_m01_personal_exigir_reasignacion_vendedor(',
        ),
      );
      expect(
        rpc,
        contains(
          'UPDATE public.app_dat_vendedor v\n'
          '       SET id_tpv = p_id_tpv\n'
          '     WHERE v.id = p_id_vendedor;',
        ),
      );
      expect(rpc, contains("USING ERRCODE = '42501'"));
      expect(rpc, isNot(contains('INSERT INTO public.app_dat_')));
      expect(rpc, isNot(contains('DELETE FROM public.app_dat_')));
    });

    test('ejecutable solo por authenticated', () {
      expect(
        rpc,
        contains(
          'REVOKE ALL ON FUNCTION public.fn_m01_personal_reasignar_vendedor(bigint, bigint)\n'
          '    FROM PUBLIC, anon;',
        ),
      );
      expect(
        rpc,
        contains(
          'GRANT EXECUTE ON FUNCTION public.fn_m01_personal_reasignar_vendedor(bigint, bigint)\n'
          '    TO authenticated;',
        ),
      );
      expect(rpc, isNot(contains('TO service_role')));
      expect(rpc, isNot(contains('TO PUBLIC')));
    });
  });

  group('contrato estatico R0b-policies: personal acotado', () {
    final pol = File(
      '../docs/plan-multimoneda/m01_r0b_policies_personal_propuesta.sql',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    test('instalacion explicita, baseline exacto y helpers S01/RH requeridos', () {
      expect(pol.trimLeft(), startsWith('BEGIN;'));
      expect(pol.trimRight(), endsWith('COMMIT;'));
      expect(pol, contains("current_user <> 'postgres'"));
      expect(
        pol,
        contains("current_setting('app.m01_r0b_policies_approved', true)"),
      );
      expect(
        pol,
        contains(
          "to_regprocedure('public.fn_config_tienda_puede_escribir(bigint)') IS NULL",
        ),
      );
      expect(
        pol,
        contains(
          "to_regprocedure('public.fn_config_tienda_puede_leer(bigint)') IS NULL",
        ),
      );
      expect(
        pol,
        contains("to_regclass('public.app_dat_recursos_humanos') IS NULL"),
      );
      expect(pol, contains("'all workers', 'worker police select'"));
      expect(
        pol,
        contains("'Open access to vendedor', 'all vednedor', 'select all'"),
      );
      expect(pol, isNot(contains('CREATE OR REPLACE FUNCTION')));
    });

    test(
      'sustituye las cinco policies permisivas por policies authenticated',
      () {
        for (final p in [
          'DROP POLICY "all workers" ON public.app_dat_trabajadores;',
          'DROP POLICY "worker police select" ON public.app_dat_trabajadores;',
          'DROP POLICY "Open access to vendedor" ON public.app_dat_vendedor;',
          'DROP POLICY "all vednedor" ON public.app_dat_vendedor;',
          'DROP POLICY "select all" ON public.app_dat_vendedor;',
        ]) {
          expect(pol, contains(p));
        }
        for (final p in [
          'm01_trabajadores_leer',
          'm01_trabajadores_insertar',
          'm01_trabajadores_actualizar',
          'm01_trabajadores_eliminar',
          'm01_vendedor_leer',
          'm01_vendedor_insertar',
          'm01_vendedor_actualizar',
          'm01_vendedor_eliminar',
        ]) {
          expect(pol, contains('CREATE POLICY $p'));
        }
        expect(
          RegExp(
            'FOR (SELECT|INSERT|UPDATE|DELETE) TO authenticated',
          ).allMatches(pol),
          hasLength(8),
        );
        expect(pol, isNot(contains('TO public')));
        expect(pol, isNot(contains('USING (true)')));
        expect(pol, isNot(contains('WITH CHECK (true)')));
      },
    );

    test('lectura propia, tienda y RH; escritura solo admin de tienda', () {
      expect(pol, contains('uuid = auth.uid()'));
      expect(pol, contains('public.fn_config_tienda_puede_leer(id_tienda)'));
      expect(
        pol,
        contains('public.fn_m01_personal_es_recursos_humanos(id_tienda)'),
      );
      expect(
        RegExp('fn_config_tienda_puede_escribir').allMatches(pol).length,
        greaterThanOrEqualTo(5),
      );
      expect(pol, contains('public.fn_m01_personal_vendedor_id_tienda(id)'));
      expect(
        pol,
        contains(
          'public.fn_m01_personal_tienda_para_vinculos(id_trabajador, id_tpv)',
        ),
      );
    });

    test('helpers DEFINER pg_catalog, columnas restringidas y anon sin tabla', () {
      expect(
        RegExp(
          'STABLE\nSECURITY DEFINER\nSET search_path = pg_catalog',
        ).allMatches(pol),
        hasLength(3),
      );
      expect(
        pol,
        contains(
          'REVOKE UPDATE ON TABLE public.app_dat_trabajadores FROM authenticated;',
        ),
      );
      expect(
        pol,
        contains(
          'GRANT UPDATE (nombres, apellidos, maneja_apertura_control)\n'
          '    ON TABLE public.app_dat_trabajadores TO authenticated;',
        ),
      );
      expect(
        pol,
        contains(
          'REVOKE UPDATE ON TABLE public.app_dat_vendedor FROM authenticated;',
        ),
      );
      expect(
        pol,
        contains(
          'GRANT UPDATE (numero_confirmacion, permitir_customizar_precio_venta)\n'
          '    ON TABLE public.app_dat_vendedor TO authenticated;',
        ),
      );
      expect(
        pol,
        contains('REVOKE ALL ON TABLE public.app_dat_trabajadores FROM anon;'),
      );
      expect(
        pol,
        contains('REVOKE ALL ON TABLE public.app_dat_vendedor FROM anon;'),
      );
      expect(
        RegExp(
          'GRANT EXECUTE ON FUNCTION public.fn_m01_personal_',
        ).allMatches(pol),
        hasLength(3),
      );
      expect(pol, isNot(contains('INSERT INTO public.app_dat_')));
      expect(pol, isNot(contains('DELETE FROM public.app_dat_')));
    });
  });

  group('contrato estatico R0b-identidad: vincular usuario trabajador', () {
    final rpc = File(
      '../docs/plan-multimoneda/m01_r0b_identidad_trabajador_propuesta.sql',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    test('instalacion explicita y dependencia S01', () {
      expect(rpc.trimLeft(), startsWith('BEGIN;'));
      expect(rpc.trimRight(), endsWith('COMMIT;'));
      expect(rpc, contains("current_user <> 'postgres'"));
      expect(
        rpc,
        contains("current_setting('app.m01_r0b_identidad_approved', true)"),
      );
      expect(
        rpc,
        contains(
          "to_regprocedure('public.fn_config_tienda_puede_escribir(bigint)') IS NULL",
        ),
      );
      expect(rpc, isNot(contains('CREATE OR REPLACE FUNCTION')));
      expect(rpc, isNot(contains('CREATE POLICY')));
    });

    test(
      'firma sin actor ni ambito declarados y DEFINER con search_path fijo',
      () {
        final signature = rpc.substring(
          rpc.indexOf('CREATE FUNCTION'),
          rpc.indexOf('RETURNS boolean'),
        );
        expect(signature, contains('p_id_trabajador bigint'));
        expect(signature, contains('p_uuid uuid'));
        expect(signature, isNot(contains('p_id_tienda')));
        expect(signature, isNot(contains('p_modificado_por')));
        expect(
          rpc,
          contains('VOLATILE\nSECURITY DEFINER\nSET search_path = pg_catalog'),
        );
      },
    );

    test('valida actor, trabajador, uuid destino y excluye dueno/superadmin', () {
      expect(rpc, contains('auth.uid() IS NULL'));
      expect(rpc, contains('FOR UPDATE;'));
      expect(rpc, contains('v_deleted_at IS NOT NULL'));
      expect(
        rpc,
        contains(
          'fn_config_tienda_puede_escribir(v_id_tienda) IS DISTINCT FROM true',
        ),
      );
      expect(rpc, contains('FROM auth.users u WHERE u.id = p_uuid'));
      expect(rpc, contains('w2.deleted_at IS NULL'));
      expect(
        rpc,
        contains(
          'FROM public.app_dat_dueno d WHERE d.id_trabajador = p_id_trabajador',
        ),
      );
      expect(
        rpc,
        contains('FROM public.app_dat_superadmin s WHERE s.uuid = v_old_uuid'),
      );
      expect(rpc, contains('v_old_uuid IS NOT DISTINCT FROM p_uuid'));
    });

    test('actualiza identidad y filas de rol atomicamente por trabajador', () {
      for (final tabla in [
        'app_dat_trabajadores',
        'app_dat_vendedor',
        'app_dat_almacenero',
        'app_dat_supervisor',
        'auditor',
        'app_dat_gerente',
        'app_dat_jefe_cocina',
        'app_dat_recursos_humanos',
      ]) {
        expect(rpc, contains('UPDATE public.$tabla'), reason: tabla);
      }
      expect(
        RegExp('WHERE id_trabajador = p_id_trabajador').allMatches(rpc).length,
        7,
      );
      expect(rpc, isNot(contains('INSERT INTO public.app_dat_')));
      expect(rpc, isNot(contains('DELETE FROM public.app_dat_')));
      expect(rpc, isNot(contains('UPDATE public.app_dat_dueno')));
    });

    test('ejecutable solo por authenticated', () {
      expect(
        rpc,
        contains(
          'REVOKE ALL ON FUNCTION public.fn_m01_personal_vincular_usuario_trabajador(bigint, uuid)\n'
          '    FROM PUBLIC, anon;',
        ),
      );
      expect(
        rpc,
        contains(
          'GRANT EXECUTE ON FUNCTION public.fn_m01_personal_vincular_usuario_trabajador(bigint, uuid)\n'
          '    TO authenticated;',
        ),
      );
      expect(rpc, isNot(contains('TO service_role')));
      expect(rpc, isNot(contains('TO PUBLIC')));
    });
  });

  group('contrato estatico R0b-RH: fuente de pertenencia protegida', () {
    final rh = File(
      '../docs/plan-multimoneda/m01_r0b_policies_recursos_humanos_propuesta.sql',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    test('instalacion explicita y baseline sin RLS/policies', () {
      expect(rh.trimLeft(), startsWith('BEGIN;'));
      expect(rh.trimRight(), endsWith('COMMIT;'));
      expect(rh, contains("current_user <> 'postgres'"));
      expect(rh, contains("current_setting('app.m01_r0b_rh_approved', true)"));
      expect(
        rh,
        contains(
          "to_regprocedure('public.fn_m01_personal_es_recursos_humanos(bigint)') IS NULL",
        ),
      );
      expect(rh, contains('relrowsecurity'));
      expect(rh, isNot(contains('CREATE OR REPLACE FUNCTION')));
      expect(rh, isNot(contains('DROP POLICY')));
    });

    test('activa RLS con lectura propia/tienda/RH y escritura solo admin', () {
      expect(
        rh,
        contains(
          'ALTER TABLE public.app_dat_recursos_humanos ENABLE ROW LEVEL SECURITY;',
        ),
      );
      for (final p in [
        'm01_rrhh_leer',
        'm01_rrhh_insertar',
        'm01_rrhh_eliminar',
      ]) {
        expect(rh, contains('CREATE POLICY $p'));
      }
      expect(rh, isNot(contains('FOR UPDATE')));
      expect(rh, contains('uuid = auth.uid()'));
      expect(rh, contains('public.fn_config_tienda_puede_leer(id_tienda)'));
      expect(
        rh,
        contains('public.fn_m01_personal_es_recursos_humanos(id_tienda)'),
      );
      expect(rh, contains('public.fn_config_tienda_puede_escribir(id_tienda)'));
      expect(rh, isNot(contains('TO public')));
      expect(rh, isNot(contains('USING (true)')));
    });

    test('anon sin tabla y authenticated sin UPDATE', () {
      expect(
        rh,
        contains(
          'REVOKE ALL ON TABLE public.app_dat_recursos_humanos FROM anon;',
        ),
      );
      expect(
        rh,
        contains(
          'GRANT SELECT, INSERT, DELETE ON TABLE public.app_dat_recursos_humanos TO authenticated;',
        ),
      );
      expect(rh, isNot(contains('UPDATE public.app_dat_')));
      expect(rh, isNot(contains('INSERT INTO public.app_dat_')));
      expect(rh, isNot(contains('DELETE FROM public.app_dat_')));
    });
  });
}
