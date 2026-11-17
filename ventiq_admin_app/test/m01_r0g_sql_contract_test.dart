import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File(
    '../docs/plan-multimoneda/m01_r0g_offline_definer_propuesta.sql',
  ).readAsStringSync().replaceAll('\r\n', '\n');

  test('instalacion explicita y cobertura por catalogo, no por lista fija', () {
    expect(sql.trimLeft(), startsWith('BEGIN;'));
    expect(sql.trimRight(), endsWith('COMMIT;'));
    expect(sql, contains("current_user <> 'postgres'"));
    expect(sql, contains("current_setting('app.m01_r0g_approved', true)"));
    expect(sql, contains('pg_get_function_identity_arguments'));
    expect(sql, contains('p.prosecdef'));
    expect(sql, isNot(contains('CREATE OR REPLACE FUNCTION')));
    expect(sql, isNot(contains('CREATE FUNCTION')));
  });

  test('fija search_path y acota EXECUTE sin tocar wrappers ni cuerpos', () {
    expect(
      sql,
      contains('ALTER FUNCTION %s SET search_path = pg_catalog, public'),
    );
    expect(sql, contains('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon'));
    expect(sql, contains('GRANT EXECUTE ON FUNCTION %s TO authenticated'));
    expect(sql, contains("p.proname NOT LIKE 'fn_m01_%'"));
    for (final patron in [
      "p.proname LIKE 'fn\\_%\\_offline%' ESCAPE '\\'",
      "p.proname LIKE 'fn_registrar_%'",
      "p.proname LIKE 'fn_admin_caja_%'",
    ]) {
      expect(sql, contains(patron));
    }
    expect(sql, isNot(contains('TO anon\n')));
    expect(sql, isNot(contains('UPDATE public.')));
  });
}
