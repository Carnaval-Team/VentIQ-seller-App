import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final directory = '../docs/plan-multimoneda';
  String read(String name) => File('$directory/$name').readAsStringSync();

  test('el calculador usa el snapshot y no el precio vigente', () {
    final sql = read('m01_r13_calcular_linea_propuesta.sql');
    expect(sql.contains('round(v_cantidad * v_unit, 2)'), isTrue);
    expect(sql.contains('valor_publicado'), isTrue);
    expect(sql.contains('app_dat_precio'), isFalse);
    expect(sql.contains('app_v_precio'), isFalse);
    expect(sql.contains('ON CONFLICT'), isFalse);
  });

  test('el alta no reutiliza el registro viejo y conserva la clave', () {
    final sql = read('m01_r14_registrar_venta_v1_propuesta.sql');
    expect(sql.contains('fn_registrar_venta'), isFalse);
    expect(sql.contains('fn_descontar_venta_enrutada_v2'), isTrue);
    expect(sql.contains("'venta_v1'"), isTrue);
    expect(sql.contains('ON CONFLICT'), isFalse);
    expect(sql.contains('Activacion de moneda por producto no autorizada'), isTrue);
  });

  test('la preorden entra por el mismo alta y la mesa sigue fuera', () {
    final sql = read('m01_r26_preorden_v1_propuesta.sql');
    expect(sql.trimLeft().startsWith('BEGIN;'), isTrue);
    expect(sql.trimRight().endsWith('COMMIT;'), isTrue);
    expect(sql.contains("current_setting('app.m01_r26_preorden_approved'"), isTrue);
    expect(
      sql.contains(
        'CREATE OR REPLACE FUNCTION public.fn_m01_registrar_venta_v1(p_solicitud jsonb)',
      ),
      isTrue,
    );
    expect(sql.contains("NOT IN ('mostrador', 'preorden')"), isTrue);
    // app_dat_operaciones.uuid referencia users: el actor, no client_uuid.
    expect(sql.contains('VALUES (2, v_actor, v_tienda)'), isTrue);
    expect(sql.contains('VALUES (2, v_uuid, v_tienda)'), isFalse);
    expect(
      sql.contains("position('IS DISTINCT FROM ''mostrador''' in prosrc)"),
      isTrue,
    );
    expect(sql.contains("'venta_v1'"), isTrue);
    expect(sql.contains('ON CONFLICT'), isFalse);
    expect(
      sql.contains('Activacion de moneda por producto no autorizada'),
      isTrue,
    );
    expect(
      sql.contains(
        'GRANT EXECUTE ON FUNCTION public.fn_m01_registrar_venta_v1(jsonb) TO authenticated;',
      ),
      isTrue,
    );
  });

  test('el cobro v1 localiza la venta por idempotencia, no por uuid', () {
    final sql = File(
      '../docs/plan-multimoneda/m01_r27_pagos_v1_operacion_lookup_propuesta.sql',
    ).readAsStringSync();
    expect(sql.contains('BEGIN;'), isTrue);
    expect(sql.contains('COMMIT;'), isTrue);
    expect(sql.contains('app.m01_r27_pagos_lookup_approved'), isTrue);
    expect(
      sql.contains(
        'CREATE OR REPLACE FUNCTION public.fn_m01_registrar_pagos_v1(',
      ),
      isTrue,
    );
    // El vinculo client_uuid -> id_operacion vive en la idempotencia.
    expect(sql.contains('WHERE i.client_uuid = v_venta'), isTrue);
    expect(sql.contains("i.tipo = 'venta_v1'"), isTrue);
    // El lookup viejo por operaciones.uuid solo puede aparecer en el
    // preflight, como literal aceptado del cuerpo anterior.
    expect('WHERE o.uuid = v_venta'.allMatches(sql).length, 1);
    expect(sql.contains('ON CONFLICT'), isFalse);
    expect(
      sql.contains(
        'GRANT EXECUTE ON FUNCTION public.fn_m01_registrar_pagos_v1(jsonb) TO authenticated',
      ),
      isTrue,
    );
  });

  test('la devolucion resuelve la presentacion base cuando la linea es v1', () {
    final sql = File(
      '../docs/plan-multimoneda/m01_r28_estado_devolucion_presentacion_propuesta.sql',
    ).readAsStringSync();
    expect(sql.contains('BEGIN;'), isTrue);
    expect(sql.contains('COMMIT;'), isTrue);
    expect(sql.contains('app.m01_r28_estado_devolucion_approved'), isTrue);
    expect(
      sql.contains(
        'CREATE OR REPLACE FUNCTION public.fn_registrar_cambio_estado_operacion(',
      ),
      isTrue,
    );
    // NULL en la linea v1 -> fila es_base de app_dat_producto_presentacion.
    expect(sql.contains('v_presentacion_devolver'), isTrue);
    expect(sql.contains('AND pp.es_base'), isTrue);
    expect(
      sql.contains(
        'COALESCE(id_presentacion, 0) = COALESCE(v_presentacion_devolver, 0)',
      ),
      isTrue,
    );
    // El INSERT del ledger usa la presentacion resuelta, no el NULL crudo.
    expect(
      sql.contains('v_productos_extraidos.id_presentacion,\n'
          '                v_productos_extraidos.id_ubicacion'),
      isFalse,
    );
  });

  test('el listado expone el contrato v1 por linea y por operacion', () {
    final sql = File(
      '../docs/plan-multimoneda/m01_r29_listar_ordenes_v1_propuesta.sql',
    ).readAsStringSync();
    expect(sql.contains('BEGIN;'), isTrue);
    expect(sql.contains('COMMIT;'), isTrue);
    expect(sql.contains('app.m01_r29_listar_ordenes_approved'), isTrue);
    expect(
      sql.contains(
        'CREATE OR REPLACE FUNCTION public.fn_listar_ordenes(',
      ),
      isTrue,
    );
    // Campos de linea necesarios para rearmar `seleccion`.
    for (final campo in [
      'version_monetaria',
      'id_linea_cliente',
      'moneda_venta',
      'seleccion_pendiente',
      'precio_unitario_nativo',
      'descuento_manual_unitario_nativo',
      'snapshot_precio',
      'snapshot_tasa',
      'snapshot_descuentos',
    ]) {
      expect(sql.contains("'$campo',"), isTrue, reason: campo);
    }
    // El client_uuid sale de la huella de idempotencia, no se inventa.
    expect(sql.contains("i.tipo = 'venta_v1'"), isTrue);
    // No recalcula precios: solo lee columnas persistidas.
    expect(sql.contains('app_v_precio_venta'), isFalse);
  });

  test('flag por producto y moneda forzada son mutuamente excluyentes', () {
    final sql = File(
      '../docs/plan-multimoneda/m01_r30_flag_forzada_exclusion_propuesta.sql',
    ).readAsStringSync();
    expect(sql.contains('BEGIN;'), isTrue);
    expect(sql.contains('COMMIT;'), isTrue);
    expect(sql.contains('app.m01_r30_forzada_exclusion_approved'), isTrue);
    expect(
      sql.contains(
        'CREATE OR REPLACE FUNCTION public.fn_m01_fijar_moneda_por_producto(',
      ),
      isTrue,
    );
    expect(
      sql.contains('CREATE OR REPLACE FUNCTION public.fn_validar_moneda_forzada()'),
      isTrue,
    );
    // Al activar el flag, la forzada se apaga en el mismo UPDATE.
    expect(
      sql.contains('forzar_moneda_venta = CASE WHEN p_activar THEN FALSE'),
      isTrue,
    );
    expect(
      sql.contains('moneda_venta_forzada = CASE WHEN p_activar THEN NULL'),
      isTrue,
    );
    // El trigger rechaza la combinacion desde cualquier escritura.
    expect(
      sql.contains(
        'La moneda por producto es incompatible con forzar la moneda de venta',
      ),
      isTrue,
    );
    // Mantiene la guarda de capacidad y la GUC del flag.
    expect(sql.contains('fn_m01_registrar_venta_v1'), isTrue);
    expect(sql.contains('m01_politica_flag_autorizada'), isTrue);
    // No toca el selector legacy ni recalcula precios.
    expect(sql.contains('mostrar_selector_moneda ='), isFalse);
    expect(sql.contains('app_v_precio_venta'), isFalse);
  });

  test('el cobro no cruza moneda ni atribuye un pendiente', () {
    final sql = read('m01_r15_pagos_v1_propuesta.sql');
    expect(sql.contains('fn_registrar_pago_venta'), isFalse);
    expect(sql.contains('seleccion_pendiente'), isTrue);
    expect(sql.contains('app_dat_pago_aplicacion'), isTrue);
    expect(sql.contains('ON CONFLICT'), isFalse);
  });

  test('una venta nueva sin version no entra si el flag esta encendido', () {
    final sql = read('m01_r17_legacy_con_flag_propuesta.sql');
    expect(sql.contains('BEFORE INSERT'), isTrue);
    expect(sql.contains('Una venta nueva no puede omitir el contrato de moneda'), isTrue);
    expect(sql.contains('SECURITY DEFINER'), isTrue);
    expect(sql.contains('UPDATE public.app_dat_operacion_venta'), isFalse);
    expect(sql.contains('DELETE FROM'), isFalse);
  });

  test('el ajuste no reparte pagos y el harness termina en rollback', () {
    final ajuste = read('m01_r16_ajustar_linea_v1_propuesta.sql');
    final harness = read('m01_r16_harness_v1.sql');
    expect(ajuste.contains('fn_distribuir_pagos_orden'), isFalse);
    expect(ajuste.contains('fn_eliminar_producto_orden'), isFalse);
    expect(ajuste.contains('SNAPSHOT_INVALID'), isTrue);
    expect(harness.trimRight().endsWith('ROLLBACK;'), isTrue);
    expect(harness.contains('COMMIT;'), isFalse);
  });

  test('el reporte de ordenes v2 es aditivo, versionado y sin fan-out', () {
    final sql = File(
      '../docs/plan-multimoneda/m01_r31_reporte_ordenes_v1_propuesta.sql',
    ).readAsStringSync();
    expect(sql.contains('BEGIN;'), isTrue);
    expect(sql.contains('COMMIT;'), isTrue);
    expect(sql.contains('app.m01_r31_ordenes_approved'), isTrue);
    // Funcion nueva: no reescribe la legacy que consumen clientes viejos.
    expect(sql.contains('reporte_ordenes_json_v2('), isTrue);
    expect(sql.contains('CREATE OR REPLACE FUNCTION public.reporte_ordenes_json'), isFalse);
    // Envelope R01.
    for (final campo in [
      'version_reporte',
      'versiones_monetarias',
      'base_temporal',
      'completitud',
    ]) {
      expect(sql.contains("'$campo'"), isTrue, reason: campo);
    }
    // Linea v1 con sus componentes persistidos como decimales exactos.
    for (final campo in [
      'id_linea_cliente',
      'moneda_venta',
      'importe_bruto_nativo',
      'importe_neto_nativo',
      'importe_neto_cup_equivalente',
      'tasa_cambio_cup',
      'seleccion_pendiente',
      'id_medio_pago_seleccionado',
    ]) {
      expect(sql.contains(campo), isTrue, reason: campo);
    }
    // Cobros por identidad de pago con aplicaciones; sin filtrar medios
    // inactivos (no borrar cobros historicos) y sin join detalle x pago.
    expect(sql.contains('app_dat_pago_aplicacion'), isTrue);
    expect(sql.contains('LEFT JOIN public.app_nom_medio_pago mp'), isTrue);
    expect(sql.contains('mp.es_activo'), isFalse);
    // Autorizacion en servidor: la v1 legacy no la tenia.
    expect(sql.contains('fn_config_tienda_puede_leer'), isTrue);
    expect(sql.contains('REVOKE EXECUTE'), isTrue);
    // No recalcula con catalogo ni tasa vigente: lee snapshots persistidos.
    expect(sql.contains('app_v_precio_venta'), isFalse);
  });

  test('el reporte por moneda v2 declara su semantica de cohorte', () {
    final sql = File(
      '../docs/plan-multimoneda/m01_r32_ventas_por_moneda_v2_propuesta.sql',
    ).readAsStringSync();
    expect(sql.contains('BEGIN;'), isTrue);
    expect(sql.contains('COMMIT;'), isTrue);
    expect(sql.contains('app.m01_r32_moneda_cohorte_approved'), isTrue);
    // Funcion nueva: la v1 queda para los consumidores actuales.
    expect(sql.contains('fn_reporte_ventas_por_moneda_v2('), isTrue);
    expect(
      sql.contains('CREATE OR REPLACE FUNCTION public.fn_reporte_ventas_por_moneda'),
      isFalse,
    );
    // La semantica real queda declarada: cohorte de ventas, no caja.
    expect(sql.contains("'cohorte_ventas'"), isTrue);
    expect(sql.contains("'cobrado'"), isTrue);
    expect(sql.contains('version_reporte'), isTrue);
    expect(sql.contains('completitud'), isTrue);
    // Cohorte: filtra por fecha de la operacion y ultimo estado 2, no por
    // fecha_pago.
    expect(sql.contains('o.created_at::date BETWEEN'), isTrue);
    expect(sql.contains('eo.estado = 2'), isTrue);
    expect(sql.contains('pv.fecha_pago'), isFalse);
    // La incompletitud se declara: pago sin equivalente no es un 0.
    expect(sql.contains('PAGOS_SIN_EQUIVALENTE_CUP'), isTrue);
    // Medio de pago por LEFT JOIN: la baja del medio no borra el cobro.
    expect(sql.contains('LEFT JOIN public.app_nom_medio_pago'), isTrue);
    // Autorizacion en servidor.
    expect(sql.contains('fn_config_tienda_puede_leer'), isTrue);
    expect(sql.contains('REVOKE EXECUTE'), isTrue);
    // El consolidado usa la tasa actual solo como presentacion.
    expect(sql.contains('fn_moneda_consolidacion'), isTrue);
  });
}