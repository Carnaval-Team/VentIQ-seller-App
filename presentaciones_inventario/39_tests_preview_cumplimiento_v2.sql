-- ============================================================================
-- 39 tests · Preview pública de cumplimiento físico v2
-- ============================================================================
-- Requiere 35, 38 y 39. Todo el escenario sintético termina en ROLLBACK.
-- ============================================================================

BEGIN;

DO $test$
DECLARE
    v_uuid             uuid;
    v_uuid_sin_acceso  uuid := gen_random_uuid();
    v_id_categoria     bigint;
    v_producto         bigint;
    v_caja             bigint;
    v_bulto            bigint;
    v_unidad           bigint;
    v_otra_ubicacion   bigint;
    v_plan             jsonb;
    v_rechazo          boolean := false;
    v_prosecdef        boolean;
    v_proconfig        text[];
BEGIN
    SELECT acceso.uuid
      INTO v_uuid
      FROM (
          SELECT g.uuid FROM public.app_dat_gerente g
           WHERE g.id_tienda = 223
          UNION ALL
          SELECT s.uuid FROM public.app_dat_supervisor s
           WHERE s.id_tienda = 223
          UNION ALL
          SELECT a.uuid
            FROM public.app_dat_almacenero a
            JOIN public.app_dat_almacen al ON al.id = a.id_almacen
           WHERE al.id_tienda = 223
          UNION ALL
          SELECT v.uuid
            FROM public.app_dat_vendedor v
            JOIN public.app_dat_tpv t ON t.id = v.id_tpv
           WHERE t.id_tienda = 223
      ) AS acceso
     WHERE acceso.uuid IS NOT NULL
     LIMIT 1;

    IF v_uuid IS NULL THEN
        RAISE EXCEPTION 'El test requiere un usuario con acceso a la tienda 223';
    END IF;

    PERFORM set_config(
        'request.jwt.claims',
        json_build_object('sub', v_uuid, 'role', 'authenticated')::text,
        true
    );

    SELECT p.id_categoria INTO v_id_categoria
      FROM public.app_dat_producto p
     WHERE p.id_tienda = 223
     ORDER BY p.id LIMIT 1;

    SELECT la.id INTO v_otra_ubicacion
      FROM public.app_dat_layout_almacen la
      JOIN public.app_dat_almacen a ON a.id = la.id_almacen
     WHERE a.id_tienda <> 223
       AND la.deleted_at IS NULL
       AND a.deleted_at IS NULL
     ORDER BY la.id LIMIT 1;

    INSERT INTO public.app_dat_producto (
        id_tienda, id_categoria, denominacion, sku,
        es_vendible, es_inventariable, es_servicio, es_elaborado,
        mostrar_en_catalogo, created_at
    ) VALUES (
        223, v_id_categoria, 'ZZ TEST preview cumplimiento',
        'ZZ-PREVIEW-CUMPLIMIENTO', true, true, false, false, false, now()
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

    v_plan := public.fn_preview_cumplimiento_v2(
        v_producto, 349, v_unidad, 10, NULL, NULL
    );
    IF v_plan->>'status' <> 'success'
       OR (v_plan->>'maximo_servible')::numeric <> 55
       OR (v_plan#>>'{lineas_fisicas,0,id_presentacion}')::bigint <> v_caja THEN
        RAISE EXCEPTION 'T1 preview autorizada incorrecta: %', v_plan;
    END IF;

    v_plan := public.fn_preview_cumplimiento_v2(
        v_producto, 349, v_caja, 6, NULL, NULL
    );
    IF v_plan->>'error_code' <> 'INSUFFICIENT_STOCK'
       OR (v_plan->>'maximo_servible')::numeric <> 5 THEN
        RAISE EXCEPTION 'T2 máximo servible esperado 5 Cajas: %', v_plan;
    END IF;

    IF v_otra_ubicacion IS NOT NULL THEN
        v_plan := public.fn_preview_cumplimiento_v2(
            v_producto, v_otra_ubicacion, v_unidad, 1, NULL, NULL
        );
        IF v_plan->>'error_code' <> 'LOCATION_NOT_IN_PRODUCT_STORE' THEN
            RAISE EXCEPTION 'T3 no rechazó ubicación de otra tienda: %', v_plan;
        END IF;
    END IF;

    PERFORM set_config(
        'request.jwt.claims',
        json_build_object('sub', v_uuid_sin_acceso, 'role', 'authenticated')::text,
        true
    );
    BEGIN
        PERFORM public.fn_preview_cumplimiento_v2(
            v_producto, 349, v_unidad, 1, NULL, NULL
        );
    EXCEPTION WHEN SQLSTATE '42501' THEN
        v_rechazo := true;
    END;
    IF NOT v_rechazo THEN
        RAISE EXCEPTION 'T4 la preview no rechazó al usuario sin acceso';
    END IF;

    SELECT p.prosecdef, p.proconfig
      INTO v_prosecdef, v_proconfig
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'fn_preview_cumplimiento_v2';

    IF NOT v_prosecdef
       OR v_proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
       OR has_function_privilege('public',
              'public.fn_preview_cumplimiento_v2(bigint,bigint,bigint,numeric,bigint,bigint)',
              'EXECUTE')
       OR has_function_privilege('anon',
              'public.fn_preview_cumplimiento_v2(bigint,bigint,bigint,numeric,bigint,bigint)',
              'EXECUTE')
       OR NOT has_function_privilege('authenticated',
              'public.fn_preview_cumplimiento_v2(bigint,bigint,bigint,numeric,bigint,bigint)',
              'EXECUTE') THEN
        RAISE EXCEPTION 'T5 metadatos o ACL inseguros en preview v2';
    END IF;

    RAISE NOTICE '39_tests_preview_cumplimiento_v2: 5 bloques OK';
END;
$test$;

ROLLBACK;
