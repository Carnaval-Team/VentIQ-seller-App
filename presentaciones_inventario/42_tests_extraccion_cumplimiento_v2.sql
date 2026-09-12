-- ============================================================================
-- 42 tests · Extracción administrativa atómica con cumplimiento físico v2
-- ============================================================================
-- Requiere 35, 38, 39, 40, 41 y 42. Todo termina en ROLLBACK.
-- ============================================================================

BEGIN;

DO $test$
DECLARE
    v_actor             uuid;
    v_id_categoria      bigint;
    v_id_motivo         bigint;
    v_producto          bigint;
    v_producto_fallo    bigint;
    v_id_ubicacion      bigint;
    v_caja              bigint;
    v_bulto             bigint;
    v_unidad            bigint;
    v_unidad_fallo      bigint;
    v_request_uuid      uuid := gen_random_uuid();
    v_request_base      uuid := gen_random_uuid();
    v_request_fallo     uuid := gen_random_uuid();
    v_resultado         jsonb;
    v_replay            jsonb;
    v_id_operacion      bigint;
    v_rechazo           boolean := false;
    v_operaciones_antes bigint;
    v_ledger_antes      bigint;
    v_eventos_antes     bigint;
    v_solicitudes_antes bigint;
    v_prosecdef         boolean;
    v_proconfig         text[];
BEGIN
    SELECT acceso.uuid INTO v_actor
      FROM (
          SELECT g.uuid FROM public.app_dat_gerente g WHERE g.id_tienda = 223
          UNION ALL
          SELECT s.uuid FROM public.app_dat_supervisor s WHERE s.id_tienda = 223
          UNION ALL
          SELECT a.uuid
            FROM public.app_dat_almacenero a
            JOIN public.app_dat_almacen al ON al.id = a.id_almacen
           WHERE al.id_tienda = 223
      ) acceso
     WHERE acceso.uuid IS NOT NULL LIMIT 1;

    SELECT p.id_categoria INTO v_id_categoria
      FROM public.app_dat_producto p
     WHERE p.id_tienda = 223 ORDER BY p.id LIMIT 1;
    SELECT m.id INTO v_id_motivo
      FROM public.app_nom_motivo_extraccion m ORDER BY m.id LIMIT 1;

    SELECT la.id INTO v_id_ubicacion
      FROM public.app_dat_layout_almacen la
      JOIN public.app_dat_almacen a ON a.id = la.id_almacen
     WHERE a.id_tienda = 223
       AND la.deleted_at IS NULL
       AND a.deleted_at IS NULL
     ORDER BY CASE WHEN la.id = 349 THEN 0 ELSE 1 END, la.id
     LIMIT 1;

    IF v_actor IS NULL OR v_id_categoria IS NULL OR v_id_motivo IS NULL
       OR v_id_ubicacion IS NULL THEN
        RAISE EXCEPTION 'El test requiere actor, categoría, motivo y ubicación en tienda 223';
    END IF;

    PERFORM set_config(
        'request.jwt.claims',
        json_build_object('sub', v_actor, 'role', 'authenticated')::text,
        true
    );

    INSERT INTO public.app_dat_producto (
        id_tienda, id_categoria, denominacion, sku,
        es_vendible, es_inventariable, es_servicio, es_elaborado,
        mostrar_en_catalogo, created_at
    ) VALUES (
        223, v_id_categoria, 'ZZ TEST extracción física v2',
        'ZZ-EXTRACCION-FISICA-V2', true, true, false, false, false, now()
    ) RETURNING id INTO v_producto;

    INSERT INTO public.app_dat_producto_presentacion (
        id_producto, id_presentacion, cantidad, es_base, precio_promedio, created_at
    ) VALUES
        (v_producto, 3, 10, false, 0, now()),
        (v_producto, 7, 5, false, 0, now()),
        (v_producto, 1, 1, true, 0, now());

    SELECT id INTO v_caja FROM public.app_dat_producto_presentacion
     WHERE id_producto = v_producto AND cantidad = 10;
    SELECT id INTO v_bulto FROM public.app_dat_producto_presentacion
     WHERE id_producto = v_producto AND cantidad = 5;
    SELECT id INTO v_unidad FROM public.app_dat_producto_presentacion
     WHERE id_producto = v_producto AND cantidad = 1;

    PERFORM public.fn_ingresar_presentacion(v_producto, v_id_ubicacion, v_caja, 2, 1);
    PERFORM public.fn_ingresar_presentacion(v_producto, v_id_ubicacion, v_bulto, 5, 1);
    PERFORM public.fn_ingresar_presentacion(v_producto, v_id_ubicacion, v_unidad, 10, 1);

    v_resultado := public.fn_crear_extraccion_con_movimiento_v2(
        'Prueba automatizada', v_id_motivo, 223, 'Extracción de 16 unidades',
        jsonb_build_array(jsonb_build_object(
            'id_producto', v_producto,
            'id_variante', NULL,
            'id_opcion_variante', NULL,
            'id_ubicacion', v_id_ubicacion,
            'id_presentacion', v_unidad,
            'cantidad', 16,
            'precio_unitario', 10,
            'sku_producto', 'ZZ-EXTRACCION-FISICA-V2'
        )),
        v_request_uuid
    );
    v_id_operacion := (v_resultado->>'id_operacion')::bigint;

    IF v_resultado->>'status' <> 'success'
       OR v_resultado->>'idempotent_replay' <> 'false'
       OR jsonb_array_length(v_resultado->'lineas_fisicas') <> 2
       OR jsonb_array_length(v_resultado->'eventos_conversion') <> 1
       OR (SELECT count(*) FROM public.app_dat_extraccion_productos ep
            WHERE ep.id_operacion = v_id_operacion) <> 2
       OR (SELECT COALESCE(sum(ep.importe), 0)
             FROM public.app_dat_extraccion_productos ep
            WHERE ep.id_operacion = v_id_operacion) <> 160
       OR EXISTS (
            SELECT 1
              FROM public.app_dat_extraccion_productos ep
              JOIN public.app_dat_producto_presentacion pp
                ON pp.id = ep.id_presentacion
             WHERE ep.id_operacion = v_id_operacion
               AND ep.precio_unitario <> 10 * pp.cantidad
       )
       OR (SELECT count(DISTINCT ip.id_extraccion)
             FROM public.app_dat_inventario_productos ip
            WHERE ip.id IN (
                SELECT (value)::bigint
                  FROM jsonb_array_elements(v_resultado->'ledger_ids')
            ) AND ip.id_extraccion IS NOT NULL) <> 2
       OR (SELECT eo.estado FROM public.app_dat_estado_operacion eo
            WHERE eo.id_operacion = v_id_operacion ORDER BY eo.id DESC LIMIT 1) <> 2
       OR NOT (SELECT o.contabilizada FROM public.app_dat_operaciones o
                WHERE o.id = v_id_operacion)
       OR (SELECT s.saldo FROM public.fn_stock_saldos_presentacion(
               v_producto, NULL, v_id_ubicacion, true) s
            WHERE s.id_presentacion = v_caja) <> 2
       OR (SELECT s.saldo FROM public.fn_stock_saldos_presentacion(
               v_producto, NULL, v_id_ubicacion, true) s
            WHERE s.id_presentacion = v_bulto) <> 3
       OR (SELECT s.saldo FROM public.fn_stock_saldos_presentacion(
               v_producto, NULL, v_id_ubicacion, true) s
            WHERE s.id_presentacion = v_unidad) <> 4 THEN
        RAISE EXCEPTION 'T1 extracción física 16 incorrecta: %', v_resultado;
    END IF;

    v_replay := public.fn_crear_extraccion_con_movimiento_v2(
        'Prueba automatizada', v_id_motivo, 223, 'Extracción de 16 unidades',
        jsonb_build_array(jsonb_build_object(
            'id_producto', v_producto,
            'id_variante', NULL,
            'id_opcion_variante', NULL,
            'id_ubicacion', v_id_ubicacion,
            'id_presentacion', v_unidad,
            'cantidad', 16,
            'precio_unitario', 10,
            'sku_producto', 'ZZ-EXTRACCION-FISICA-V2'
        )),
        v_request_uuid
    );
    IF v_replay->>'idempotent_replay' <> 'true'
       OR v_replay->>'id_operacion' <> v_id_operacion::text
       OR v_replay->'ledger_ids' <> v_resultado->'ledger_ids' THEN
        RAISE EXCEPTION 'T2 replay idempotente incorrecto: %', v_replay;
    END IF;

    BEGIN
        PERFORM public.fn_crear_extraccion_con_movimiento_v2(
            'Prueba automatizada', v_id_motivo, 223, 'Payload diferente',
            jsonb_build_array(jsonb_build_object(
                'id_producto', v_producto, 'id_ubicacion', v_id_ubicacion,
                'id_presentacion', v_unidad, 'cantidad', 1
            )),
            v_request_uuid
        );
    EXCEPTION WHEN SQLSTATE '22023' THEN
        v_rechazo := SQLERRM LIKE '%IDEMPOTENCY_KEY_REUSED%';
    END;
    IF NOT v_rechazo THEN
        RAISE EXCEPTION 'T3 no rechazó UUID reutilizado con otro payload';
    END IF;

    v_resultado := public.fn_crear_extraccion_con_movimiento_v2(
        'Prueba base', v_id_motivo, 223, 'NULL resuelve base',
        jsonb_build_array(jsonb_build_object(
            'id_producto', v_producto, 'id_ubicacion', v_id_ubicacion,
            'id_presentacion', NULL, 'cantidad', 4
        )),
        v_request_base
    );
    IF (v_resultado#>>'{lineas_logicas,0,id_presentacion}')::bigint <> v_unidad
       OR (SELECT s.saldo FROM public.fn_stock_saldos_presentacion(
               v_producto, NULL, v_id_ubicacion, true) s
            WHERE s.id_presentacion = v_unidad) <> 0 THEN
        RAISE EXCEPTION 'T4 NULL no resolvió la presentación base: %', v_resultado;
    END IF;

    INSERT INTO public.app_dat_producto (
        id_tienda, id_categoria, denominacion, sku,
        es_vendible, es_inventariable, es_servicio, es_elaborado,
        mostrar_en_catalogo, created_at
    ) VALUES (
        223, v_id_categoria, 'ZZ TEST extracción fallo v2',
        'ZZ-EXTRACCION-FALLO-V2', true, true, false, false, false, now()
    ) RETURNING id INTO v_producto_fallo;

    INSERT INTO public.app_dat_producto_presentacion (
        id_producto, id_presentacion, cantidad, es_base, precio_promedio, created_at
    ) VALUES (
        v_producto_fallo, 1, 1, true, 0, now()
    ) RETURNING id INTO v_unidad_fallo;

    PERFORM public.fn_ingresar_presentacion(
        v_producto_fallo, v_id_ubicacion, v_unidad_fallo, 1, 1
    );

    SELECT count(*) INTO v_operaciones_antes FROM public.app_dat_operaciones;
    SELECT count(*) INTO v_ledger_antes
      FROM public.app_dat_inventario_productos WHERE id_producto = v_producto;
    SELECT count(*) INTO v_eventos_antes
      FROM public.app_dat_conversion_presentacion_evento WHERE id_producto = v_producto;
    SELECT count(*) INTO v_solicitudes_antes
      FROM public.app_dat_extraccion_v2_solicitud WHERE id_tienda = 223;

    v_rechazo := false;
    BEGIN
        PERFORM public.fn_crear_extraccion_con_movimiento_v2(
            'Prueba fallo', v_id_motivo, 223, 'Debe revertirse',
            jsonb_build_array(
                jsonb_build_object(
                    'id_producto', v_producto, 'id_ubicacion', v_id_ubicacion,
                    'id_presentacion', v_unidad, 'cantidad', 1
                ),
                jsonb_build_object(
                    'id_producto', v_producto_fallo, 'id_ubicacion', v_id_ubicacion,
                    'id_presentacion', v_unidad_fallo, 'cantidad', 2
                )
            ),
            v_request_fallo
        );
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        v_rechazo := true;
    END;
    IF NOT v_rechazo
       OR (SELECT count(*) FROM public.app_dat_operaciones) <> v_operaciones_antes
       OR (SELECT count(*) FROM public.app_dat_inventario_productos
            WHERE id_producto = v_producto) <> v_ledger_antes
       OR (SELECT count(*) FROM public.app_dat_inventario_productos
            WHERE id_producto = v_producto_fallo) <> 1
       OR (SELECT s.saldo FROM public.fn_stock_saldos_presentacion(
               v_producto_fallo, NULL, v_id_ubicacion, true) s
            WHERE s.id_presentacion = v_unidad_fallo) <> 1
       OR (SELECT count(*) FROM public.app_dat_conversion_presentacion_evento
            WHERE id_producto = v_producto) <> v_eventos_antes
       OR (SELECT count(*) FROM public.app_dat_extraccion_v2_solicitud
            WHERE id_tienda = 223) <> v_solicitudes_antes THEN
        RAISE EXCEPTION 'T5 lote insuficiente no fue atómico';
    END IF;

    SELECT p.prosecdef, p.proconfig INTO v_prosecdef, v_proconfig
      FROM pg_proc p
     WHERE p.oid =
        'public.fn_crear_extraccion_con_movimiento_v2(text,bigint,bigint,text,jsonb,uuid)'::regprocedure;

    IF NOT v_prosecdef
       OR v_proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
       OR has_function_privilege('public',
            'public.fn_crear_extraccion_con_movimiento_v2(text,bigint,bigint,text,jsonb,uuid)',
            'EXECUTE')
       OR has_function_privilege('anon',
            'public.fn_crear_extraccion_con_movimiento_v2(text,bigint,bigint,text,jsonb,uuid)',
            'EXECUTE')
       OR NOT has_function_privilege('authenticated',
            'public.fn_crear_extraccion_con_movimiento_v2(text,bigint,bigint,text,jsonb,uuid)',
            'EXECUTE')
       OR NOT (SELECT c.relrowsecurity FROM pg_class c
                WHERE c.oid = 'public.app_dat_extraccion_v2_solicitud'::regclass)
       OR has_table_privilege('anon',
            'public.app_dat_extraccion_v2_solicitud', 'SELECT')
       OR has_table_privilege('authenticated',
            'public.app_dat_extraccion_v2_solicitud', 'INSERT')
       OR (SELECT p.prosecdef FROM pg_proc p
            WHERE p.oid =
              'public.fn_aplicar_plan_extraccion_v2(jsonb,jsonb,bigint,uuid,text)'::regprocedure)
       OR has_function_privilege('authenticated',
            'public.fn_aplicar_plan_extraccion_v2(jsonb,jsonb,bigint,uuid,text)',
            'EXECUTE')
       OR EXISTS (
            SELECT 1
              FROM pg_proc p
             WHERE p.oid = ANY (ARRAY[
                 'public.validar_recepcion_consignacion_antes_completar(bigint)'::regprocedure,
                 'public.trigger_validar_recepcion_consignacion()'::regprocedure,
                 'public.actualizar_estado_envio_aceptado()'::regprocedure,
                 'public.actualizar_estado_envio_en_transito()'::regprocedure,
                 'public.fn_actualizar_eliminar_pre_asignacion()'::regprocedure,
                 'public.fn_registrar_gasto_por_recepcion()'::regprocedure,
                 'public.fn_sincronizar_estado_orden_inverso()'::regprocedure
             ]::oid[])
               AND p.proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
       )
       OR pg_get_functiondef(
              'public.trigger_validar_recepcion_consignacion()'::regprocedure
          ) NOT LIKE '%FROM public.validar_recepcion_consignacion_antes_completar(%'
       OR EXISTS (
            SELECT 1
              FROM pg_proc p
             WHERE p.oid = ANY (ARRAY[
                 'public.validar_recepcion_consignacion_antes_completar(bigint)'::regprocedure,
                 'public.actualizar_estado_envio_aceptado()'::regprocedure,
                 'public.actualizar_estado_envio_en_transito()'::regprocedure,
                 'public.fn_actualizar_eliminar_pre_asignacion()'::regprocedure,
                 'public.fn_registrar_gasto_por_recepcion()'::regprocedure
             ]::oid[])
               AND (pg_get_functiondef(p.oid) LIKE '%FROM app_%'
                    OR pg_get_functiondef(p.oid) LIKE '%JOIN app_%'
                    OR pg_get_functiondef(p.oid) LIKE '%UPDATE app_%'
                    OR pg_get_functiondef(p.oid) LIKE '%INTO app_%'
                    OR pg_get_functiondef(p.oid) LIKE '%DELETE FROM app_%')
       ) THEN
        RAISE EXCEPTION 'T6 metadatos, RLS, ACL o dependencias inseguras en extracción v2';
    END IF;

    RAISE NOTICE '42_tests_extraccion_cumplimiento_v2: 6 bloques OK';
END;
$test$;

ROLLBACK;
