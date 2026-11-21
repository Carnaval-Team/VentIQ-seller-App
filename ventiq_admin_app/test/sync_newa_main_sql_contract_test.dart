import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contrato estático de los scripts del pase newa -> main decididos el
/// 19/11/2026 (docs/plan-multimoneda/analisis_8_funciones_pendientes.md).
/// Inspeccionan el texto: no ejecutan PL/pgSQL ni sustituyen correrlos en
/// PostgreSQL. Su ejecución en newa se verificó por separado con consultas
/// de lectura (ver tasks/plan_sync_newa_main.md).
String _leer(String ruta) =>
    File(ruta).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  late String mejorado;
  late String turno;
  late String traer;
  late String tipoPago;
  late String r29;
  late String pantalla;

  setUpAll(() {
    mejorado = _leer(
      '../sql_updates/fix_cambio_estado_operacion_mejorado_recepcion.sql',
    );
    turno = _leer('../sql_updates/fix_reporte_ventas_por_turno_sin_cierre.sql');
    traer = _leer('../sql_updates/newa_traer_funciones_main.sql');
    tipoPago = _leer('../sql_updates/fix_listar_ordenes_tipo_pago.sql');
    r29 = _leer(
      '../docs/plan-multimoneda/m01_r29_listar_ordenes_v1_propuesta.sql',
    );
    pantalla = _leer('lib/screens/inventory_operations_screen.dart');
  });

  group('cancelar o devolver una recepcion', () {
    test('conserva la firma y corre como una sola transaccion', () {
      expect(mejorado.trimLeft(), startsWith('-- ===='));
      expect(mejorado, contains('\nBEGIN;\n'));
      expect(mejorado.trimRight(), endsWith('COMMIT;'));
      expect(
        mejorado,
        contains(
          'fn_registrar_cambio_estado_operacion_mejorado(p_id_operacion bigint, '
          'p_nuevo_estado smallint, p_uuid_usuario uuid DEFAULT NULL::uuid)',
        ),
      );
      expect(mejorado, contains('RETURNS jsonb'));
    });

    test('exige las columnas que usa antes de reemplazar la funcion', () {
      expect(mejorado, contains('cambiar_fecha_creacion_operacion_al_cierre'));
      expect(mejorado, contains("column_name = 'id_lote'"));
      expect(mejorado, contains("current_user <> 'postgres'"));
    });

    test('bloquea con un codigo y lista los productos con problema', () {
      expect(mejorado, contains("'error_code', 'RECEPCION_INVENTARIO_USADO'"));
      expect(mejorado, contains("'productos_con_problema', v_problemas"));
      expect(mejorado, contains("'saldo_actual'"));
      expect(mejorado, contains("'cantidad_recibida'"));
      expect(mejorado, contains("'motivo'"));
      expect(
        mejorado,
        contains("NOT LIKE '%RECEPCION_INVENTARIO_USADO%'"),
        reason: 'el script verifica que el cuerpo quedó instalado',
      );
    });

    test('devuelve la cantidad con movimientos compensatorios, sin borrar', () {
      final inicio = mejorado.indexOf('Pasada 1');
      expect(inicio, greaterThan(0));
      final bloque = mejorado.substring(inicio);
      final cancelacion = bloque.substring(0, bloque.indexOf('COMMIT;'));
      expect(cancelacion, contains('Pasada 2'));
      expect(cancelacion, contains('INSERT INTO app_dat_inventario_productos'));
      expect(
        mejorado.indexOf('DELETE FROM app_dat_inventario_productos'),
        lessThan(inicio),
        reason: 'el DELETE heredado solo limpia filas prematuras al completar',
      );
      final borrados = RegExp(
        r'DELETE FROM app_dat_inventario_productos',
      ).allMatches(mejorado).length;
      expect(borrados, 1, reason: 'cancelar no puede borrar historial');
      // 4 = devolucion, 5 = cancelacion en origen_cambio.
      expect(
        cancelacion,
        contains('CASE WHEN p_nuevo_estado = 3 THEN 4 ELSE 5 END'),
      );
    });

    test('aplica el flag de fecha de newa al completar', () {
      expect(mejorado, contains('v_cambiar_fecha_creacion'));
      expect(mejorado, contains('created_at'));
    });

    test('Admin manda el usuario y muestra el aviso al gerente', () {
      expect(pantalla, contains("'p_uuid_usuario': userUuid"));
      expect(
        pantalla,
        contains("result['error_code'] == 'RECEPCION_INVENTARIO_USADO'"),
      );
      expect(pantalla, contains('_showReceptionInventoryUsedDialog'));
      expect(pantalla, contains('No se puede cancelar la recepción'));
      expect(pantalla, contains('productos_con_problema'));
      expect(pantalla, contains('saldo_actual'));
    });
  });

  group('reporte de ventas por turno', () {
    test(
      'conserva el cuerpo de main y solo cambia la pertenencia al turno',
      () {
        expect(turno, contains('\nBEGIN;\n'));
        expect(turno.trimRight(), endsWith('COMMIT;'));
        expect(turno, contains('fn_reporte_ventas_por_turno'));
        expect(turno, contains('STABLE SECURITY DEFINER'));
        expect(turno, contains('SET search_path'));
        expect(turno, contains('fn_reporte_ventas_por_turno_v2'));
      },
    );

    test(
      'turno cerrado por id, abierto por fecha hasta la siguiente apertura',
      () {
        expect(turno, contains('ct.id_operacion_cierre AS op_cierre'));
        expect(
          turno,
          contains('COALESCE(ct.fecha_cierre, now()) AS turno_fin'),
        );
        expect(turno, contains('op_siguiente_apertura'));
        expect(
          turno,
          contains('WHEN t.op_cierre IS NOT NULL THEN o.id <= t.op_cierre'),
        );
        expect(turno, contains('ELSE o.created_at <= t.turno_fin'));
        expect(
          turno,
          contains(
            '(t.op_siguiente_apertura IS NULL OR o.id < t.op_siguiente_apertura)',
          ),
        );
      },
    );

    test('no deja ventas de otra tienda ni filas duplicadas', () {
      expect(turno, contains('o.id_tienda'));
      expect(turno, contains('DISTINCT ON (o.id)'));
    });
  });

  group('funciones de main que newa debe traer', () {
    test('crea el indice parcial de lotes y no toca datos', () {
      expect(
        traer,
        contains('CREATE INDEX IF NOT EXISTS idx_inv_prod_lote_producto'),
      );
      expect(traer, contains('WHERE id_lote IS NOT NULL'));
      expect(traer.toLowerCase(), isNot(contains('create table')));
      expect(
        RegExp(r'\n\s*(INSERT INTO|DELETE FROM|UPDATE )').hasMatch(traer),
        isFalse,
      );
      expect(traer.trimRight(), endsWith('COMMIT;'));
    });

    test(
      'verifica por md5 que las cuatro funciones quedan idénticas a main',
      () {
        for (final par in const {
          'fn_dashboard_carnaval_proveedor(bigint,date,date)': '8734944d',
          'fn_stock_producto_almacen_detalle(bigint,bigint)': '1f2ef38a',
          'fn_stock_saldos_presentacion(bigint,bigint,bigint,boolean)':
              '8005bbfa',
          'fn_reporte_ventas_con_proveedor_por_turno(bigint,date,date,bigint)':
              'f6f60db6',
        }.entries) {
          expect(traer, contains("('${par.key}', '${par.value}')"));
        }
      },
    );

    test('el tablero de Carnaval conserva los campos que lee Admin', () {
      final cuerpo = _leer('../sql_updates/newa_traer_funciones_main.sql');
      for (final campo in [
        'ordenes_completadas',
        'por_estado',
        'top_productos',
      ]) {
        expect(cuerpo, contains(campo));
      }
      final modelo = _leer('lib/models/carnaval_provider_dashboard_data.dart');
      expect(modelo, contains('ordenes_completadas'));
    });
  });

  group('las otras 12 funciones de main en newa', () {
    late String doce;
    setUpAll(() {
      doce = _leer('../sql_updates/newa_traer_12_funciones_main.sql');
    });

    test('es una sola transaccion que no toca datos', () {
      expect(doce, startsWith('-- Solo newa'));
      expect(doce, contains('\nBEGIN;\n'));
      expect(doce.trimRight(), endsWith('COMMIT;'));
      expect(doce.toLowerCase(), isNot(contains('create table')));
      expect(
        RegExp(r'\n(INSERT INTO|DELETE FROM|UPDATE |DROP )').hasMatch(doce),
        isFalse,
      );
    });

    test('el catalogo pasa al precio vigente por id mayor', () {
      expect(
        doce,
        contains("v_viejo constant text := 'ORDER BY id_producto, fecha_desde DESC'"),
      );
      expect(
        doce,
        contains("v_nuevo constant text := 'ORDER BY id_producto, id DESC'"),
      );
      expect(doce, contains('IF v_veces <> 1 THEN'));
    });

    test('verifica las 12 huellas de main y el permiso de fn_check_update', () {
      for (final par in const {
        'buscar_producto_por_codigo_barras_v3(text)':
            '73306441fd99a92b3765105f88385b45',
        'fn_check_update(character varying,character varying,integer)':
            '112e9101d04c14ff417ef7c04feffa1a',
        'fn_listar_motivos_extraccion()': 'b5ffeaf89dc49a1421b4d490a346e0cf',
        'fn_update_carnaval_product_prices()':
            '039a999ba1c1b2f0ffa5c614ab7ea1bb',
        'get_productos_completos_by_tienda_optimized_provider(bigint,bigint,boolean,integer)':
            'b03f3caabaa10363a9b6e2cf09865a9f',
        'get_productos_completos_by_tienda_optimized_provider2(bigint,bigint,boolean,integer,boolean)':
            'fbcc3d5daf34bf19350d58f5f1f461cd',
        'get_productos_completos_by_tienda_optimized_provider2(bigint,bigint,boolean,integer)':
            'd300f4f919acd0e9cfdeb41e9f11d289',
        'get_productos_completos_by_tienda_optimized_v2(bigint,bigint,boolean,boolean)':
            '9ac2d5649de0290ef21d84b133f8fdfd',
        'get_productos_completos_by_tienda_optimized(integer,integer,boolean)':
            'ade12329400851570521ca6a47cc1214',
        'get_productos_completos_by_tienda_optimized2(bigint,bigint,boolean,boolean)':
            'b83f9858420d0a1424df31bcb2fcc752',
        'get_productos_completos_by_tienda_with_supplier(integer,integer,boolean,integer)':
            '322e5dd3ce0bc1fe0a4759e2de30e4dd',
        'sync_price_to_carnaval()': '6401eca8bc810a3951033661f76c4b3b',
      }.entries) {
        expect(doce, contains("('public.${par.key}', '${par.value}')"));
      }
      expect(
        doce,
        contains(
          'REVOKE ALL ON FUNCTION public.fn_check_update(character varying, character varying, integer) FROM PUBLIC;',
        ),
      );
    });
  });

  group('fn_listar_ordenes devuelve tipo_pago', () {
    test('la fuente aplicada en newa ya no tiene el typo', () {
      expect(r29, isNot(contains('tipo_paago')));
      expect(r29, contains("'tipo_pago',"));
    });

    test('el parche es idempotente y conserva el resto de la funcion', () {
      expect(tipoPago, contains('\nBEGIN;\n'));
      expect(tipoPago.trimRight(), endsWith('COMMIT;'));
      expect(tipoPago, contains('pg_get_functiondef'));
      expect(
        tipoPago,
        contains("replace(v_def, '''tipo_paago''', '''tipo_pago''')"),
      );
      expect(tipoPago, contains('ya emite tipo_pago'));
      expect(
        tipoPago,
        contains('fn_listar_ordenes(bigint,bigint,uuid,smallint'),
      );
    });

    test('el TPV lee la clave corregida', () {
      final ordenes = _leer('../ventiq_app/lib/screens/orders_screen.dart');
      expect(ordenes, contains("payment['tipo_pago']"));
    });
  });

  group('apertura de turno offline devuelve el id del turno', () {
    late String apertura;

    setUpAll(() {
      apertura = _leer('../sql_updates/fix_apertura_turno_offline_id_turno.sql');
    });

    test('resuelve el turno desde la operacion que devuelve v3', () {
      expect(apertura, contains('v_new_op := public.registrar_apertura_turno_v3('));
      expect(
        apertura,
        contains('WHERE ct.id_operacion_apertura = v_new_op'),
      );
      // La alineacion y la evidencia de idempotencia usan el id del turno.
      expect(
        apertura,
        contains('fn_turno_alinear_fecha_apertura(v_new_id, p_fecha_apertura)'),
      );
      expect(apertura, contains("VALUES (p_client_uuid, v_new_id, 'apertura_turno'"));
      expect(apertura, contains("'id_turno', v_new_id"));
      expect(apertura, contains("'id_operacion', v_new_op"));
    });

    test('el replay resuelve claves antiguas acotadas a TPV y vendedor', () {
      expect(apertura, contains('v_turno_resuelto'));
      expect(apertura, contains('ct.id_operacion_apertura = v_existing.id_operacion'));
      expect(apertura, contains('AND ct.id_tpv = p_id_tpv'));
      expect(apertura, contains('AND ct.id_vendedor = p_id_vendedor'));
    });

    test('no cambia la firma, el search_path ni los permisos', () {
      expect(
        apertura,
        contains("SET search_path TO 'pg_catalog'"),
      );
      expect(apertura, isNot(contains('GRANT ')));
      expect(apertura, isNot(contains('REVOKE ')));
      expect(apertura.trimRight(), endsWith('COMMIT;'));
    });
  });
}
