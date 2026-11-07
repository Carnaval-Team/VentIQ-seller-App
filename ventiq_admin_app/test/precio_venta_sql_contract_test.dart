import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File('lib/sql/precio_venta_vigente.sql').readAsStringSync();

  test('la fuente vigente usa fecha del servidor e ID, no created_at', () {
    final view = sql.substring(0, sql.indexOf('REVOKE ALL ON'));
    expect(view, contains('WITH (security_invoker = true)'));
    expect(view, contains('pv.fecha_desde <= CURRENT_DATE'));
    expect(view, contains('pv.fecha_hasta >= CURRENT_DATE'));
    expect(view, contains('COALESCE(pv.id_variante, 0), pv.id DESC'));
    expect(view, isNot(contains('created_at DESC')));
  });

  test('no añade filtros de variantes a cualquier WHERE de producto', () {
    expect(sql, isNot(contains(r"'WHERE\s+id_producto\s*=\s*p\.id'")));
  });

  test('repara solo los filtros inválidos y conserva el filtro del precio', () {
    final repair = File(
      'lib/sql/fix_detalle_producto_filtro_variante.sql',
    ).readAsStringSync();
    final operations = RegExp(
      r"regexp_replace\(\w+,\s*'([^']+)',\s*'([^']+)', 'gi'\)",
    ).allMatches(repair).toList();
    expect(operations, hasLength(2));
    String transform(String input) {
      for (final operation in operations) {
        final source = operation.group(1)!;
        expect(sql, contains("'$source'"));
        final pattern = RegExp(
          source.replaceAll(r'\m', r'\b').replaceAll(r'\M', r'\b'),
          caseSensitive: false,
        );
        final replacement = operation.group(2)!;
        input = input.replaceAllMapped(
          pattern,
          (m) => replacement == r'\1' ? m.group(1)! : replacement,
        );
      }
      return input;
    }

    for (final newline in ['\n', '\r\n']) {
      final fixture =
          '''
SELECT precio_venta_cup FROM public.app_v_precio_venta_vigente
WHERE id_producto = p.id AND COALESCE(id_variante, 0) = 0;
SELECT jsonb_agg(media) FROM app_dat_producto_multimedias
WHERE id_producto = p.id AND COALESCE(id_variante, 0) = 0;
SELECT jsonb_agg(etiqueta) FROM public.app_dat_producto_etiquetas
WHERE id_producto = p.id AND COALESCE(id_variante, 0) = 0;
SELECT * FROM app_dat_producto_presentacion WHERE id_producto = p.id;
'''
              .replaceAll('\n', newline);
      final fixed = transform(fixture);
      expect(RegExp('COALESCE').allMatches(fixed), hasLength(1));
      expect(fixed, contains('FROM public.app_v_precio_venta_base_vigente'));
      expect(
        fixed,
        contains('app_dat_producto_presentacion WHERE id_producto = p.id;'),
      );
      expect(transform(fixed), fixed);
      expect(
        transform(
          fixture.replaceAll(
            'public.app_v_precio_venta_vigente',
            'app_dat_precio_venta',
          ),
        ),
        fixed,
      );
    }
    expect(repair, isNot(contains('UPDATE public.app_dat_')));
    expect(repair, isNot(contains('INSERT INTO')));
    expect(repair, isNot(contains('DELETE FROM')));
  });

  test('el precio específico se resuelve antes del precio base', () {
    expect(sql, contains('pv.id_variante = NULLIF(p_id_variante, 0)'));
    expect(
      sql,
      contains('ORDER BY (COALESCE(pv.id_variante, 0) <> 0) DESC, pv.id DESC'),
    );
  });

  test('la migración no reescribe reportes históricos ni FDI', () {
    final patch = RegExp(
      r'FOREACH v_name IN ARRAY ARRAY\[([\s\S]*?)\] LOOP',
    ).firstMatch(sql)!.group(1)!;
    final functions = RegExp(
      r"'([^']+)'",
    ).allMatches(patch).map((m) => m.group(1)).toSet();
    expect(functions, {
      'get_detalle_producto',
      'get_detalles_productos_batch',
      'get_productos_by_categoria_tpv_search_meta_v3',
      'get_productos_completos_by_tienda_optimized_v2',
      'rpc_get_products_last_price2',
      'fn_reporte_ventas_con_proveedor_precios_actuales',
      'get_precios_productos_tienda',
      'fn_productos_cocina_tpv',
      'rpc_apply_global_price_change',
      'rpc_apply_selected_price_change',
    });
    expect(sql, isNot(contains('fdi_dat_')));
    expect(sql, isNot(contains('fn_reporte_ventas_con_proveedor5')));
    expect(sql, isNot(contains('fn_reporte_ventas_con_proveedor_por_turno')));
  });

  test('crear la migración no ejecuta reparaciones de datos', () {
    final outsideBodies = sql
        .replaceAll(RegExp(r'\$\$[\s\S]*?\$\$;'), '')
        .replaceAll(RegExp(r'\$migration\$[\s\S]*?\$migration\$;'), '')
        .replaceAll(RegExp(r'\$offline\$[\s\S]*?\$offline\$;'), '');
    expect(
      RegExp(
        r'^\s*(INSERT|UPDATE|DELETE|TRUNCATE)\b',
        multiLine: true,
        caseSensitive: false,
      ).hasMatch(outsideBodies),
      isFalse,
    );
    expect(sql, startsWith('BEGIN;'));
    expect(sql.trim(), endsWith('COMMIT;'));
  });

  test('las escrituras exigen autorización y serializan por producto', () {
    expect(sql, contains('auth.uid() IS NULL'));
    expect(sql, contains('fn_user_is_gerente_or_superadmin(v_tienda)'));
    expect(sql, contains('fn_user_is_dueno(v_tienda)'));
    expect(sql, contains('p.id = p_id_producto FOR UPDATE'));
    expect(sql, contains('GREATEST(pv.fecha_desde, CURRENT_DATE - 1)'));
    expect(
      sql,
      contains('precio_descuento, fecha_desde, fecha_hasta, created_at'),
    );
    expect(sql, contains('FROM PUBLIC, anon'));
  });
}
