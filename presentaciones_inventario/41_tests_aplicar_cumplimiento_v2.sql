-- ============================================================================
-- 41 tests · Ejecutor atómico de cumplimiento físico v2
-- ============================================================================
-- Requiere 35, 38, 39, 40 y 41. Todo termina en ROLLBACK.
-- ============================================================================

BEGIN;

DO $test$
DECLARE
    v_id_categoria     bigint;
    v_producto         bigint;
    v_caja             bigint;
    v_bulto            bigint;
    v_unidad           bigint;
    v_request_uuid     uuid := gen_random_uuid();
    v_request_base     uuid := gen_random_uuid();
    v_request_fallo    uuid := gen_random_uuid();
    v_resultado        jsonb;
    v_replay           jsonb;
    v_rechazo          boolean := false;
    v_ledger_antes     bigint;
    v_eventos_antes    bigint;
    v_solicitudes_antes bigint;
    v_prosecdef        boolean;
    v_proconfig        text[];
BEGIN
    SELECT p.id_categoria INTO v_id_categoria
      FROM public.app_dat_producto p
     WHERE p.id_tienda = 223
     ORDER BY p.id LIMIT 1;

    IF v_id_categoria IS NULL THEN
        RAISE EXCEPTION 'El test requiere una categoría en la tienda 223';
    END IF;

    INSERT INTO public.app_dat_producto (
        id_tienda, id_categoria, denominacion, sku,
        es_vendible, es_inventariable, es_servicio, es_elaborado,
        mostrar_en_catalogo, created_at
    ) VALUES (
        223, v_id_categoria, 'ZZ TEST aplicar cumplimiento v2',
        'ZZ-APLICAR-CUMPLIMIENTO-V2', true, true, false, false, false, now()
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

    PERFORM public.fn_ingresar_presentacion(v_producto, 349, v_caja, 2, 1);
    PERFORM public.fn_ingresar_presentacion(v_producto, 349, v_bulto, 5, 1);
    PERFORM public.fn_ingresar_presentacion(v_producto, 349, v_unidad, 10, 1);

    v_resultado := public.fn_aplicar_cumplimiento_v2(
        v_producto, 349, v_unidad, 16, v_request_uuid
    );

    IF v_resultado->>'status' <> 'success'
       OR v_resultado->>'idempotent_replay' <> 'false'
       OR jsonb_array_length(v_resultado->'eventos_conversion') <> 1
       OR jsonb_array_length(v_resultado->'ledger_ids') <> 4
       OR (SELECT s.saldo FROM public.fn_stock_saldos_presentacion(
               v_producto, NULL, 349, true) s
            WHERE s.id_presentacion = v_caja) <> 2
       OR (SELECT s.saldo FROM public.fn_stock_saldos_presentacion(
               v_producto, NULL, 349, true) s
            WHERE s.id_presentacion = v_bulto) <> 3
       OR (SELECT s.saldo FROM public.fn_stock_saldos_presentacion(
               v_producto, NULL, 349, true) s
            WHERE s.id_presentacion = v_unidad) <> 4 THEN
        RAISE EXCEPTION 'T1 aplicación física 16 incorrecta: %', v_resultado;
    END IF;

    v_replay := public.fn_aplicar_cumplimiento_v2(
        v_producto, 349, v_unidad, 16, v_request_uuid
    );
    IF v_replay->>'idempotent_replay' <> 'true'
       OR v_replay->>'id_solicitud_cumplimiento'
          <> v_resultado->>'id_solicitud_cumplimiento'
       OR v_replay->'ledger_ids' <> v_resultado->'ledger_ids' THEN
        RAISE EXCEPTION 'T2 replay idempotente incorrecto: %', v_replay;
    END IF;

    BEGIN
        PERFORM public.fn_aplicar_cumplimiento_v2(
            v_producto, 349, v_unidad, 1, v_request_uuid
        );
    EXCEPTION WHEN SQLSTATE '22023' THEN
        IF SQLERRM LIKE '%IDEMPOTENCY_KEY_REUSED%' THEN
            v_rechazo := true;
        END IF;
    END;
    IF NOT v_rechazo THEN
        RAISE EXCEPTION 'T3 no rechazó UUID reutilizado con otro payload';
    END IF;

    v_resultado := public.fn_aplicar_cumplimiento_v2(
        v_producto, 349, NULL, 4, v_request_base
    );
    IF v_resultado->>'id_presentacion_solicitada' <> v_unidad::text
       OR (SELECT s.saldo FROM public.fn_stock_saldos_presentacion(
               v_producto, NULL, 349, true) s
            WHERE s.id_presentacion = v_unidad) <> 0 THEN
        RAISE EXCEPTION 'T4 NULL no resolvió/descontó la base: %', v_resultado;
    END IF;

    SELECT count(*) INTO v_ledger_antes
      FROM public.app_dat_inventario_productos
     WHERE id_producto = v_producto;
    SELECT count(*) INTO v_eventos_antes
      FROM public.app_dat_conversion_presentacion_evento
     WHERE id_producto = v_producto;
    SELECT count(*) INTO v_solicitudes_antes
      FROM public.app_dat_cumplimiento_inventario_solicitud
     WHERE id_producto = v_producto;

    v_rechazo := false;
    BEGIN
        PERFORM public.fn_aplicar_cumplimiento_v2(
            v_producto, 349, v_unidad, 1000, v_request_fallo
        );
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        v_rechazo := true;
    END;
    IF NOT v_rechazo
       OR (SELECT count(*) FROM public.app_dat_inventario_productos
            WHERE id_producto = v_producto) <> v_ledger_antes
       OR (SELECT count(*) FROM public.app_dat_conversion_presentacion_evento
            WHERE id_producto = v_producto) <> v_eventos_antes
       OR (SELECT count(*) FROM public.app_dat_cumplimiento_inventario_solicitud
            WHERE id_producto = v_producto) <> v_solicitudes_antes THEN
        RAISE EXCEPTION 'T5 insuficiencia no fue atómica';
    END IF;

    SELECT p.prosecdef, p.proconfig
      INTO v_prosecdef, v_proconfig
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'fn_aplicar_cumplimiento_v2';

    IF v_prosecdef
       OR v_proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
       OR has_function_privilege('public',
              'public.fn_aplicar_cumplimiento_v2(bigint,bigint,bigint,numeric,uuid,bigint,bigint,bigint,uuid,text,integer,bigint,bigint,bigint,bigint)',
              'EXECUTE')
       OR has_function_privilege('anon',
              'public.fn_aplicar_cumplimiento_v2(bigint,bigint,bigint,numeric,uuid,bigint,bigint,bigint,uuid,text,integer,bigint,bigint,bigint,bigint)',
              'EXECUTE')
       OR has_function_privilege('authenticated',
              'public.fn_aplicar_cumplimiento_v2(bigint,bigint,bigint,numeric,uuid,bigint,bigint,bigint,uuid,text,integer,bigint,bigint,bigint,bigint)',
              'EXECUTE')
       OR NOT has_function_privilege('service_role',
              'public.fn_aplicar_cumplimiento_v2(bigint,bigint,bigint,numeric,uuid,bigint,bigint,bigint,uuid,text,integer,bigint,bigint,bigint,bigint)',
              'EXECUTE')
       OR NOT (SELECT c.relrowsecurity FROM pg_class c
                WHERE c.oid = 'public.app_dat_cumplimiento_inventario_solicitud'::regclass)
       OR has_table_privilege('anon',
              'public.app_dat_cumplimiento_inventario_solicitud', 'SELECT')
       OR has_table_privilege('authenticated',
              'public.app_dat_cumplimiento_inventario_solicitud', 'INSERT') THEN
        RAISE EXCEPTION 'T6 metadatos, RLS o ACL inseguros en ejecutor v2';
    END IF;

    IF pg_get_functiondef('public.fn_sincronizar_stock_producto'::regproc)
           NOT LIKE '%NEW.id_conversion_evento IS NOT NULL%'
       OR pg_get_functiondef('public.fn_notificar_producto_disponible'::regproc)
           NOT LIKE '%NEW.id_conversion_evento IS NOT NULL%'
       OR (SELECT p.prosecdef
             FROM pg_proc p
            WHERE p.oid =
                  'public.fn_validar_cantidad_final_inventario(bigint,numeric)'::regprocedure)
       OR (SELECT p.proconfig
             FROM pg_proc p
            WHERE p.oid =
                  'public.fn_validar_cantidad_final_inventario(bigint,numeric)'::regprocedure)
          IS DISTINCT FROM ARRAY['search_path=""']::text[]
       OR pg_get_functiondef(
              'public.fn_validar_cantidad_final_inventario(bigint,numeric)'::regprocedure
          ) NOT LIKE '%FROM public.app_dat_producto p%'
       OR pg_get_functiondef(
              'public.fn_validar_cantidad_final_inventario(bigint,numeric)'::regprocedure
          ) NOT LIKE '%JOIN public.app_dat_configuracion_tienda ct%'
       OR NOT has_function_privilege('public',
              'public.fn_validar_cantidad_final_inventario(bigint,numeric)', 'EXECUTE')
       OR NOT has_function_privilege('anon',
              'public.fn_validar_cantidad_final_inventario(bigint,numeric)', 'EXECUTE')
       OR NOT has_function_privilege('authenticated',
              'public.fn_validar_cantidad_final_inventario(bigint,numeric)', 'EXECUTE')
       OR NOT has_function_privilege('service_role',
              'public.fn_validar_cantidad_final_inventario(bigint,numeric)', 'EXECUTE') THEN
        RAISE EXCEPTION 'T7 guardas o dependencia del constraint incorrectas';
    END IF;

    RAISE NOTICE '41_tests_aplicar_cumplimiento_v2: 7 bloques OK';
END;
$test$;

DO $real_11001$
DECLARE
    v_unidad             bigint;
    v_request_uuid       uuid := gen_random_uuid();
    v_ledger_antes       bigint;
    v_eventos_antes      bigint;
    v_solicitudes_antes  bigint;
    v_rechazo            boolean := false;
BEGIN
    IF EXISTS (
        SELECT 1
          FROM public.fn_presentaciones_producto_v2(11001) c
          JOIN public.fn_stock_saldos_presentacion(11001, NULL, 349, true) s
            ON s.id_presentacion = c.id_presentacion
         WHERE NOT c.es_fraccionable
           AND trunc(s.saldo) <> s.saldo
    ) THEN
        SELECT c.id_presentacion INTO v_unidad
          FROM public.fn_presentaciones_producto_v2(11001) c
         WHERE c.es_base LIMIT 1;
        SELECT count(*) INTO v_ledger_antes
          FROM public.app_dat_inventario_productos WHERE id_producto = 11001;
        SELECT count(*) INTO v_eventos_antes
          FROM public.app_dat_conversion_presentacion_evento WHERE id_producto = 11001;
        SELECT count(*) INTO v_solicitudes_antes
          FROM public.app_dat_cumplimiento_inventario_solicitud WHERE id_producto = 11001;

        BEGIN
            PERFORM public.fn_aplicar_cumplimiento_v2(
                11001, 349, v_unidad, 1, v_request_uuid
            );
        EXCEPTION WHEN SQLSTATE 'P0001' THEN
            v_rechazo := true;
        END;

        IF NOT v_rechazo
           OR (SELECT count(*) FROM public.app_dat_inventario_productos
                WHERE id_producto = 11001) <> v_ledger_antes
           OR (SELECT count(*) FROM public.app_dat_conversion_presentacion_evento
                WHERE id_producto = 11001) <> v_eventos_antes
           OR (SELECT count(*) FROM public.app_dat_cumplimiento_inventario_solicitud
                WHERE id_producto = 11001) <> v_solicitudes_antes THEN
            RAISE EXCEPTION 'T8 el saldo decimal real 11001 no se rechazó atómicamente';
        END IF;
        RAISE NOTICE 'T8 11001: saldo decimal rechazado sin escrituras';
    ELSE
        RAISE NOTICE 'T8 11001 omitido: el saldo físico ya fue reconciliado';
    END IF;
END;
$real_11001$;

ROLLBACK;
