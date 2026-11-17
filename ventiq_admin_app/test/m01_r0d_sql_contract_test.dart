import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File(
    '../docs/plan-multimoneda/m01_r0d_entradas_protegidas_propuesta.sql',
  ).readAsStringSync().replaceAll('\r\n', '\n');

  test('instalacion explicita, dependencias M01/S01 y baseline', () {
    expect(sql.trimLeft(), startsWith('BEGIN;'));
    expect(sql.trimRight(), endsWith('COMMIT;'));
    expect(sql, contains("current_user <> 'postgres'"));
    expect(sql, contains("current_setting('app.m01_r0d_approved', true)"));
    expect(
      sql,
      contains(
        "to_regprocedure('public.fn_m01_personal_tienda_de_trabajador(bigint)') IS NULL",
      ),
    );
    expect(sql, contains("'fn_m01_crear_estructura_tienda'"));
    expect(sql, isNot(contains('CREATE OR REPLACE FUNCTION')));
    expect(sql, isNot(contains('CREATE POLICY')));
    expect(sql, isNot(contains('DROP FUNCTION')));
  });

  test('search_path fijo en las DEFINER legacy', () {
    expect(
      RegExp(
        'ALTER FUNCTION public.\\w+\\([^)]*\\) SET search_path = pg_catalog, public;',
      ).allMatches(sql),
      hasLength(15),
    );
  });

  test('legacy sensibles solo por service_role, nunca por cliente', () {
    expect(
      RegExp(
        'REVOKE EXECUTE ON FUNCTION public.(?!fn_m01_)\\w+\\([^)]*\\) FROM PUBLIC, anon, authenticated;',
      ).allMatches(sql),
      hasLength(8),
    );
    expect(
      RegExp(
        'GRANT EXECUTE ON FUNCTION public.(?!fn_m01_)\\w+\\([^)]*\\) TO service_role;',
      ).allMatches(sql),
      hasLength(8),
    );
  });

  test('ocho wrappers DEFINER validados delegando en legacy', () {
    expect(
      RegExp('CREATE FUNCTION public.fn_m01_').allMatches(sql),
      hasLength(8),
    );
    expect(
      RegExp(
        'VOLATILE\nSECURITY DEFINER\nSET search_path = pg_catalog',
      ).allMatches(sql),
      hasLength(8),
    );
    expect(
      RegExp('REVOKE ALL ON FUNCTION public.fn_m01_').allMatches(sql),
      hasLength(8),
    );
    expect(
      RegExp(
        'GRANT EXECUTE ON FUNCTION public.fn_m01_\\w+\\([^)]*\\) TO authenticated;',
      ).allMatches(sql),
      hasLength(8),
    );
    for (final call in [
      'RETURN public.fn_asignar_vendedor(',
      'RETURN public.fn_desasignar_vendedor(',
      'RETURN public.fn_asignar_supervisor(',
      'RETURN public.fn_desasignar_supervisor(',
      'RETURN public.fn_asignar_jefe_cocina(',
      'RETURN public.crear_tpv_completo(',
      'FROM public.create_gerente_from_email(',
      'RETURN public.crear_estructura_tienda(',
    ]) {
      expect(sql, contains(call));
    }
  });

  test('actor real y ambito derivado, nunca parametros de identidad', () {
    expect(
      RegExp('fn_config_tienda_puede_escribir').allMatches(sql).length,
      greaterThanOrEqualTo(7),
    );
    expect(
      RegExp(
        'fn_m01_personal_tienda_de_trabajador\\(p_id_trabajador\\)',
      ).allMatches(sql),
      hasLength(3),
    );
    expect(sql, contains('fn_m01_personal_tienda_de_almacen(p_id_almacen)'));
    expect(sql, contains('fn_m01_personal_tienda_de_cocina(p_id_cocina)'));
    // usuario_registrador lo fija el servidor, no el cliente.
    expect(sql, contains('auth.uid()\n    );'));
    // El creador de tienda es auth.uid(). Un usuario nuevo no tiene rol previo.
    expect(sql, contains('v_uuid uuid := auth.uid();'));
    expect(sql, contains('IF v_uuid IS NULL THEN'));
    final inicioEstructura = sql.indexOf(
      'CREATE FUNCTION public.fn_m01_crear_estructura_tienda(',
    );
    final cuerpoEstructura = sql.substring(
      inicioEstructura,
      sql.indexOf('\$function\$;', inicioEstructura),
    );
    expect(cuerpoEstructura, isNot(contains('Superadmin')));
    expect(cuerpoEstructura, isNot(contains('Gerente General')));
    expect(cuerpoEstructura, isNot(contains('fn_is_superadmin_full_access')));
    final firmaEstructura = sql.substring(
      inicioEstructura,
      sql.indexOf('RETURNS jsonb', inicioEstructura),
    );
    expect(firmaEstructura, isNot(contains('uuid')));
    expect(firmaEstructura, isNot(contains('usuario_creador')));
  });
}
