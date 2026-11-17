import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final infra = File(
    '../docs/plan-multimoneda/m01_r0c_policies_tpv_almacen_cocina_propuesta.sql',
  ).readAsStringSync().replaceAll('\r\n', '\n');

  final roles = File(
    '../docs/plan-multimoneda/m01_r0c_policies_roles_propuesta.sql',
  ).readAsStringSync().replaceAll('\r\n', '\n');

  group('R0c-infra: tpv, almacen y cocina acotadas por tienda', () {
    test('instalacion explicita y baseline exacto de newa', () {
      expect(infra.trimLeft(), startsWith('BEGIN;'));
      expect(infra.trimRight(), endsWith('COMMIT;'));
      expect(infra, contains("current_user <> 'postgres'"));
      expect(
        infra,
        contains("current_setting('app.m01_r0c_infra_approved', true)"),
      );
      expect(infra, contains("'Open access to tpv', 'all on tpv'"));
      expect(infra, contains("'almacne'"));
      expect(infra, isNot(contains('CREATE OR REPLACE FUNCTION')));
      expect(
        infra,
        contains(
          "to_regprocedure('public.fn_config_tienda_puede_escribir(bigint)') IS NULL",
        ),
      );
    });

    test(
      'helpers de ambito DEFINER pg_catalog y ejecutables por authenticated',
      () {
        for (final h in [
          'fn_m01_personal_tienda_de_almacen',
          'fn_m01_personal_tienda_de_cocina',
        ]) {
          expect(infra, contains('CREATE FUNCTION public.$h('));
          expect(
            infra,
            contains(
              'GRANT EXECUTE ON FUNCTION public.$h(bigint) TO authenticated;',
            ),
          );
        }
        expect(
          RegExp(
            'STABLE\nSECURITY DEFINER\nSET search_path = pg_catalog',
          ).allMatches(infra),
          hasLength(2),
        );
      },
    );

    test('sustituye policies permisivas y activa RLS en cocina', () {
      for (final p in [
        'DROP POLICY "Open access to tpv" ON public.app_dat_tpv;',
        'DROP POLICY "all on tpv" ON public.app_dat_tpv;',
        'DROP POLICY "almacne" ON public.app_dat_almacen;',
      ]) {
        expect(infra, contains(p));
      }
      expect(
        infra,
        contains(
          'ALTER TABLE public.app_dat_cocina ENABLE ROW LEVEL SECURITY;',
        ),
      );
      expect(
        RegExp('CREATE POLICY m01_(tpv|almacen|cocina)_').allMatches(infra),
        hasLength(12),
      );
      expect(
        RegExp(
          'FOR (SELECT|INSERT|UPDATE|DELETE) TO authenticated',
        ).allMatches(infra),
        hasLength(12),
      );
      expect(infra, isNot(contains('TO public')));
      expect(infra, isNot(contains('USING (true)')));
      expect(infra, isNot(contains('WITH CHECK (true)')));
    });

    test('coherencia almacen-tienda y columnas operativas solamente', () {
      expect(
        RegExp(
          'fn_m01_personal_tienda_de_almacen\\(id_almacen\\) = id_tienda',
        ).allMatches(infra),
        hasLength(4),
      );
      for (final grant in [
        'GRANT UPDATE (denominacion, modo_servicentro, servicentro_columnas)\n'
            '    ON TABLE public.app_dat_tpv TO authenticated;',
        'GRANT UPDATE (denominacion, direccion, ubicacion, es_cocina)\n'
            '    ON TABLE public.app_dat_almacen TO authenticated;',
        'GRANT UPDATE (denominacion, descripcion, impresora, orden, activa)\n'
            '    ON TABLE public.app_dat_cocina TO authenticated;',
      ]) {
        expect(infra, contains(grant));
      }
      expect(
        RegExp(
          'REVOKE ALL ON TABLE public.app_dat_\\w+ FROM anon;',
        ).allMatches(infra),
        hasLength(3),
      );
      expect(
        RegExp(
          'REVOKE UPDATE ON TABLE public.app_dat_\\w+ FROM authenticated;',
        ).allMatches(infra),
        hasLength(3),
      );
      expect(infra, isNot(contains('INSERT INTO public.app_dat_')));
      expect(infra, isNot(contains('DELETE FROM public.app_dat_')));
      expect(infra, isNot(contains('UPDATE public.app_dat_')));
    });
  });

  group('R0c-roles: membresias acotadas, sin UPDATE en sitio', () {
    test('instalacion explicita, baseline y dependencia de helpers', () {
      expect(roles.trimLeft(), startsWith('BEGIN;'));
      expect(roles.trimRight(), endsWith('COMMIT;'));
      expect(roles, contains("current_user <> 'postgres'"));
      expect(
        roles,
        contains("current_setting('app.m01_r0c_roles_approved', true)"),
      );
      for (final dep in [
        "to_regprocedure('public.fn_m01_personal_tienda_de_almacen(bigint)') IS NULL",
        "to_regprocedure('public.fn_m01_personal_tienda_de_cocina(bigint)') IS NULL",
        "to_regprocedure('public.fn_is_superadmin_full_access()') IS NULL",
      ]) {
        expect(roles, contains(dep));
      }
      expect(roles, contains("'almacenero'"));
      expect(roles, contains("'geneente'"));
      expect(roles, contains("'seg_toll'"));
      expect(roles, isNot(contains('CREATE OR REPLACE FUNCTION')));
    });

    test('activa RLS en las tres tablas expuestas y crea 20 policies', () {
      for (final t in [
        'ALTER TABLE public.app_dat_jefe_cocina ENABLE ROW LEVEL SECURITY;',
        'ALTER TABLE public.app_dat_supervisor ENABLE ROW LEVEL SECURITY;',
        'ALTER TABLE public.auditor ENABLE ROW LEVEL SECURITY;',
      ]) {
        expect(roles, contains(t));
      }
      for (final p in [
        'DROP POLICY "almacenero" ON public.app_dat_almacenero;',
        'DROP POLICY "geneente" ON public.app_dat_gerente;',
        'DROP POLICY "seg_toll" ON public.seg_roll;',
      ]) {
        expect(roles, contains(p));
      }
      expect(RegExp('CREATE POLICY m01_').allMatches(roles), hasLength(20));
      expect(
        RegExp(
          'FOR (SELECT|INSERT|UPDATE|DELETE) TO authenticated',
        ).allMatches(roles),
        hasLength(20),
      );
      expect(roles, isNot(contains('TO public')));
      expect(roles, isNot(contains('USING (true)')));
    });

    test(
      'lectura propia y escritura solo admin con coherencia de trabajador',
      () {
        expect(
          RegExp('uuid = auth.uid\\(\\)').allMatches(roles),
          hasLength(6),
        );
        expect(
          RegExp(
            'fn_m01_personal_tienda_de_trabajador\\(id_trabajador\\)',
          ).allMatches(roles),
          hasLength(5),
        );
        expect(
          RegExp('fn_config_tienda_puede_escribir').allMatches(roles).length,
          greaterThanOrEqualTo(13),
        );
      },
    );

    test(
      'membresias sin UPDATE salvo es_jefe; seg_roll global solo superadmin',
      () {
        expect(
          RegExp('REVOKE UPDATE ON TABLE').allMatches(roles),
          hasLength(6),
        );
        expect(
          roles,
          contains(
            'GRANT UPDATE (es_jefe) ON TABLE public.app_dat_jefe_cocina TO authenticated;',
          ),
        );
        expect(
          roles,
          contains(
            'GRANT UPDATE (denominacion, descripcion) ON TABLE public.seg_roll TO authenticated;',
          ),
        );
        expect(
          RegExp(
            'id_tienda IS NULL AND public.fn_is_superadmin_full_access\\(\\)',
          ).allMatches(roles),
          hasLength(4),
        );
        expect(
          RegExp('GRANT SELECT, INSERT, DELETE ON TABLE').allMatches(roles),
          hasLength(5),
        );
        expect(RegExp('REVOKE ALL ON TABLE').allMatches(roles), hasLength(6));
        expect(roles, isNot(contains('UPDATE public.app_dat_')));
        expect(roles, isNot(contains('INSERT INTO public.app_dat_')));
        expect(roles, isNot(contains('DELETE FROM public.app_dat_')));
      },
    );
  });
}
