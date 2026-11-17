import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File(
    '../docs/plan-multimoneda/m01_r0f_invoker_roles_propuesta.sql',
  ).readAsStringSync().replaceAll('\r\n', '\n');

  test('instalacion explicita, baseline y dependencias R0b/R0c', () {
    expect(sql.trimLeft(), startsWith('BEGIN;'));
    expect(sql.trimRight(), endsWith('COMMIT;'));
    expect(sql, contains("current_user <> 'postgres'"));
    expect(sql, contains("current_setting('app.m01_r0f_approved', true)"));
    expect(sql, contains('fn_m01_personal_tienda_de_almacen'));
    expect(sql, contains('fn_m01_personal_tienda_de_cocina'));
    expect(sql, isNot(contains('CREATE OR REPLACE')));
  });

  test('cuatro wrappers DEFINER pg_catalog con firma compatible', () {
    for (final nombre in [
      'fn_m01_editar_trabajador_basico',
      'fn_m01_agregar_rol_trabajador',
      'fn_m01_actualizar_datos_rol_trabajador',
      'fn_m01_eliminar_rol_trabajador',
    ]) {
      expect(sql, contains('CREATE FUNCTION public.$nombre('));
      expect(
        RegExp('GRANT EXECUTE ON FUNCTION public\\.$nombre\\(').hasMatch(sql),
        isTrue,
      );
    }
    expect(
      RegExp(
        'SECURITY DEFINER\\s+SET search_path = pg_catalog',
      ).allMatches(sql),
      hasLength(4),
    );
  });

  test('actor real y ambito derivado; identidad excluida y dueno protegido', () {
    expect(sql, contains('IF auth.uid() IS NULL'));
    expect(sql, isNot(contains('auth.uid() :=')));
    expect(
      sql,
      contains(
        "'La identidad se gestiona por fn_m01_personal_vincular_usuario_trabajador'",
      ),
    );
    expect(
      RegExp(
        "lower\\(coalesce\\(p_tipo_rol, ''\\)\\) = 'dueno'",
      ).allMatches(sql),
      hasLength(3),
    );
    expect(sql, contains('p_id_tienda IS DISTINCT FROM v_tienda'));
    expect(sql, contains('p_usuario_uuid IS DISTINCT FROM v_uuid'));
    expect(RegExp('FOR UPDATE OF t;').allMatches(sql), hasLength(4));
  });

  test('legacy bloqueadas para cliente y delegacion con parametros derivados', () {
    expect(
      RegExp(
        'REVOKE EXECUTE ON FUNCTION public\\.fn_(editar|agregar|actualizar|eliminar)\\w*\\(',
      ).allMatches(sql),
      hasLength(4),
    );
    expect(
      sql,
      contains(
        'public.fn_agregar_rol_trabajador(\n        p_trabajador_id, v_tienda, p_tipo_rol, v_uuid,',
      ),
    );
    expect(sql, contains('RETURN public.fn_editar_trabajador_basico('));
    expect(sql, contains('RETURN public.fn_actualizar_datos_rol_trabajador('));
    expect(sql, contains('RETURN public.fn_eliminar_rol_trabajador('));
    expect(sql, isNot(contains('TO anon')));
    expect(sql, isNot(contains('TO PUBLIC')));
  });
}
