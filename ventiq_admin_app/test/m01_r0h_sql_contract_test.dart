import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('R0h flags offline', () {
    late String flags;

    setUpAll(() {
      flags = File(
        '../docs/plan-multimoneda/m01_r0h_vendor_flags_offline_propuesta.sql',
      ).readAsStringSync().replaceAll('\r\n', '\n');
    });

    test('exige baseline exacto y evidencia creada por el primer corte', () {
      expect(flags.trimLeft(), startsWith('BEGIN;'));
      expect(flags.trimRight(), endsWith('COMMIT;'));
      expect(
        flags,
        contains("current_setting('app.m01_r0h_flags_approved', true)"),
      );
      expect(flags, contains('9034dcd2f4ad7c8c5d2cee664c3bc709'));
      expect(flags, contains('md5(prosrc)'));
      expect(flags, contains("attname = 'm01_solicitud'"));
      expect(flags, contains("atttypid = 'jsonb'::regtype"));
      expect(flags, contains("attname = 'm01_id_tienda'"));
      expect(flags, isNot(contains('ADD COLUMN')));
    });

    test('serializa el UUID y valida replay antes de tocar al vendedor', () {
      final body = flags.substring(flags.indexOf('CREATE OR REPLACE FUNCTION'));
      expect(body, contains('v_actor uuid := auth.uid()'));
      expect(body, contains('SET search_path = pg_catalog'));
      expect(
        body.indexOf('pg_advisory_xact_lock'),
        lessThan(body.indexOf('SELECT * INTO v_existing')),
      );
      expect(
        body,
        contains("v_existing.tipo IS DISTINCT FROM 'admin_vendor_flags'"),
      );
      expect(
        body,
        contains('v_existing.uuid_usuario IS DISTINCT FROM v_actor'),
      );
      expect(
        body,
        contains('v_existing.id_operacion IS DISTINCT FROM p_id_vendedor'),
      );
      expect(
        body,
        contains('v_existing.m01_solicitud IS DISTINCT FROM v_request'),
      );
      expect(
        body,
        contains('fn_config_tienda_puede_escribir(v_existing.m01_id_tienda)'),
      );
      final replay = body.substring(
        body.indexOf('IF FOUND THEN'),
        body.indexOf('SELECT * INTO v_vendor'),
      );
      expect(replay, contains("'idempotent', true"));
      expect(replay, isNot(contains('UPDATE ')));
    });

    test('valida vinculos actuales bloqueados sin reasignar TPV', () {
      expect(flags, contains('v_vendor public.app_dat_vendedor%ROWTYPE'));
      expect(flags, contains('v_worker public.app_dat_trabajadores%ROWTYPE'));
      expect(flags, contains('v_worker.deleted_at IS NOT NULL'));
      expect(flags, contains('v_worker.uuid IS DISTINCT FROM v_vendor.uuid'));
      expect(
        flags,
        contains('v_worker.id_tienda IS DISTINCT FROM v_tpv_store'),
      );
      expect(flags, contains('FOR SHARE;'));
      expect(flags, contains('fn_config_tienda_puede_escribir(v_store)'));
      expect(flags, isNot(contains('SET id_tpv')));
      expect(
        flags,
        isNot(contains('fn_m01_personal_exigir_reasignacion_vendedor(')),
      );
    });

    test('conserva NULL legacy como false pero compara solicitud exacta', () {
      expect(
        flags,
        contains(
          "'permitir_customizar_precio_venta', p_permitir_customizar_precio_venta",
        ),
      );
      expect(
        flags,
        contains(
          'SET permitir_customizar_precio_venta = COALESCE(p_permitir_customizar_precio_venta, false)',
        ),
      );
      expect(flags, contains('IF NOT FOUND THEN'));
      expect(flags, isNot(contains('ON CONFLICT')));
      expect(flags, contains('FROM PUBLIC, anon, authenticated, service_role'));
      expect(flags, contains('TO authenticated;'));
    });
  });

  test(
    'harness funcional exige fixtures autorizados y rollback sin COMMIT',
    () {
      final harness = File(
        '../docs/plan-multimoneda/m01_r0h_vendor_flags_harness.sql',
      ).readAsStringSync();
      expect(harness.trimLeft(), startsWith('BEGIN;'));
      expect(harness.trimRight(), endsWith('ROLLBACK;'));
      expect(harness, isNot(contains('COMMIT;')));
      expect(
        harness,
        contains("current_setting('app.m01_r0h_flags_harness_approved', true)"),
      );
      expect(harness, contains('SET LOCAL ROLE authenticated;'));
      expect(harness, contains('SET LOCAL ROLE anon;'));
      expect(harness, contains('EXCEPTION WHEN insufficient_privilege'));
      expect(harness, contains("'request.jwt.claim.sub'"));
      expect(harness, contains('Replay altero un cambio posterior'));
      expect(harness, contains('Payload distinto aceptado'));
      expect(harness, contains('Tipo distinto aceptado'));
      expect(harness, contains('Actor ajeno aceptado'));
      expect(
        harness,
        contains('INSERT INTO public.app_dat_operacion_offline_idempotencia'),
      );
      expect(harness, contains('UUID legacy aceptado'));
    },
  );

  late String sql;

  setUpAll(() {
    sql = File(
      '../docs/plan-multimoneda/m01_r0h_vendor_assign_offline_propuesta.sql',
    ).readAsStringSync().replaceAll('\r\n', '\n');
  });

  test(
    'R0h exige aprobacion, baseline del cuerpo y dependencias protegidas',
    () {
      expect(sql.trimLeft(), startsWith('BEGIN;'));
      expect(sql.trimRight(), endsWith('COMMIT;'));
      expect(sql, contains("current_user <> 'postgres'"));
      expect(sql, contains("current_setting('app.m01_r0h_approved', true)"));
      expect(sql, contains('md5(prosrc)'));
      expect(sql, contains('505a3b0c355f07ca4e6fa14fa8d7dd93'));
      expect(sql, contains('relrowsecurity'));
      expect(sql, contains('fn_m01_personal_exigir_reasignacion_vendedor'));
    },
  );

  test('R0h valida actor y serializa antes de consultar o mutar', () {
    final body = sql.substring(sql.indexOf('CREATE OR REPLACE FUNCTION'));
    expect(body, contains('SET search_path = pg_catalog'));
    expect(body, contains('v_actor uuid := auth.uid()'));
    expect(body, contains('v_actor IS NULL OR p_client_uuid IS NULL'));
    final lock = body.indexOf('pg_advisory_xact_lock');
    final lookup = body.indexOf('SELECT * INTO v_existing');
    final guard = body.indexOf('PERFORM public.fn_m01_personal_exigir');
    final update = body.indexOf('UPDATE public.app_dat_vendedor');
    expect(lock, greaterThan(0));
    expect(lookup, greaterThan(lock));
    expect(guard, greaterThan(lookup));
    expect(update, greaterThan(guard));
  });

  test('R0h replay exige tipo actor objeto payload y acceso actual', () {
    expect(
      sql,
      contains("v_existing.tipo IS DISTINCT FROM 'admin_vendor_assign'"),
    );
    expect(sql, contains('v_existing.uuid_usuario IS DISTINCT FROM v_actor'));
    expect(
      sql,
      contains('v_existing.id_operacion IS DISTINCT FROM p_id_vendedor'),
    );
    expect(
      sql,
      contains('v_existing.m01_solicitud IS DISTINCT FROM v_request'),
    );
    expect(
      sql,
      contains('fn_config_tienda_puede_escribir(v_existing.m01_id_tienda)'),
    );
    final replay = sql.substring(
      sql.indexOf('IF FOUND THEN'),
      sql.indexOf('PERFORM public.fn_m01_personal_exigir'),
    );
    expect(replay, contains("'idempotent', true"));
    expect(replay, contains('RETURN'));
    expect(replay, isNot(contains('UPDATE ')));
    expect(replay, isNot(contains('INSERT ')));
  });

  test(
    'R0h reutiliza evidencia compartida sin crearla ni aceptar conflictos silenciosos',
    () {
      expect(sql, isNot(contains('ADD COLUMN')));
      expect(sql, contains("attname = 'm01_solicitud'"));
      expect(sql, contains("atttypid = 'jsonb'::regtype"));
      expect(sql, contains("attname = 'm01_id_tienda'"));
      expect(sql, contains('no la crea este corte de Admin Lite'));
      expect(sql, contains("'id_tpv', p_id_tpv"));
      expect(sql, contains('IF NOT FOUND THEN'));
      expect(sql, isNot(contains('ON CONFLICT')));
      expect(
        sql,
        isNot(contains('UPDATE public.app_dat_operacion_offline_idempotencia')),
      );
      expect(sql, contains('FROM PUBLIC, anon, authenticated, service_role'));
      expect(sql, contains('TO authenticated;'));
    },
  );
}
