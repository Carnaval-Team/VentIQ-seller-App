-- ============================================================================
-- 38 tests · Planificador puro de cumplimiento físico v2
-- ============================================================================
-- Requiere 35 y 38_planificador_cumplimiento_v2.sql.
-- Crea catálogos y saldos sintéticos dentro de BEGIN/ROLLBACK.
-- ============================================================================

BEGIN;

DO $test$
DECLARE
    v_id_categoria bigint;
    v_producto_a   bigint;
    v_producto_b   bigint;
    v_producto_c   bigint;
    v_caja_a       bigint;
    v_bulto_a      bigint;
    v_unidad_a     bigint;
    v_caja_b       bigint;
    v_blister_b    bigint;
    v_unidad_b     bigint;
    v_caja_c       bigint;
    v_blister_c    bigint;
    v_unidad_c     bigint;
    v_plan         jsonb;
    v_valor        numeric;
BEGIN
    SELECT p.id_categoria
      INTO v_id_categoria
      FROM public.app_dat_producto AS p
     WHERE p.id_tienda = 223
     ORDER BY p.id
     LIMIT 1;

    IF v_id_categoria IS NULL THEN
        RAISE EXCEPTION 'Los tests requieren una categoría de la tienda 223';
    END IF;

    INSERT INTO public.app_dat_producto (
        id_tienda, id_categoria, denominacion, sku,
        es_vendible, es_inventariable, es_servicio, es_elaborado,
        mostrar_en_catalogo, created_at
    ) VALUES
        (223, v_id_categoria, 'ZZ TEST cumplimiento 10-5-1',
         'ZZ-CUMPLE-1051', true, true, false, false, false, now()),
        (223, v_id_categoria, 'ZZ TEST cumplimiento 10-6-1',
         'ZZ-CUMPLE-1061', true, true, false, false, false, now()),
        (223, v_id_categoria, 'ZZ TEST cumplimiento 40-6-1',
         'ZZ-CUMPLE-4061', true, true, false, false, false, now());

    SELECT p.id INTO v_producto_a
      FROM public.app_dat_producto AS p
     WHERE p.sku = 'ZZ-CUMPLE-1051'
     ORDER BY p.id DESC LIMIT 1;
    SELECT p.id INTO v_producto_b
      FROM public.app_dat_producto AS p
     WHERE p.sku = 'ZZ-CUMPLE-1061'
     ORDER BY p.id DESC LIMIT 1;
    SELECT p.id INTO v_producto_c
      FROM public.app_dat_producto AS p
     WHERE p.sku = 'ZZ-CUMPLE-4061'
     ORDER BY p.id DESC LIMIT 1;

    INSERT INTO public.app_dat_producto_presentacion (
        id_producto, id_presentacion, cantidad, es_base, precio_promedio, created_at
    ) VALUES
        (v_producto_a, 3, 10, false, 0, now()),
        (v_producto_a, 7, 5, false, 0, now()),
        (v_producto_a, 1, 1, true, 0, now()),
        (v_producto_b, 3, 10, false, 0, now()),
        (v_producto_b, 22, 6, false, 0, now()),
        (v_producto_b, 1, 1, true, 0, now()),
        (v_producto_c, 3, 40, false, 0, now()),
        (v_producto_c, 22, 6, false, 0, now()),
        (v_producto_c, 1, 1, true, 0, now());

    SELECT pp.id INTO v_caja_a FROM public.app_dat_producto_presentacion pp
     WHERE pp.id_producto = v_producto_a AND pp.cantidad = 10;
    SELECT pp.id INTO v_bulto_a FROM public.app_dat_producto_presentacion pp
     WHERE pp.id_producto = v_producto_a AND pp.cantidad = 5;
    SELECT pp.id INTO v_unidad_a FROM public.app_dat_producto_presentacion pp
     WHERE pp.id_producto = v_producto_a AND pp.cantidad = 1;
    SELECT pp.id INTO v_caja_b FROM public.app_dat_producto_presentacion pp
     WHERE pp.id_producto = v_producto_b AND pp.cantidad = 10;
    SELECT pp.id INTO v_blister_b FROM public.app_dat_producto_presentacion pp
     WHERE pp.id_producto = v_producto_b AND pp.cantidad = 6;
    SELECT pp.id INTO v_unidad_b FROM public.app_dat_producto_presentacion pp
     WHERE pp.id_producto = v_producto_b AND pp.cantidad = 1;
    SELECT pp.id INTO v_caja_c FROM public.app_dat_producto_presentacion pp
     WHERE pp.id_producto = v_producto_c AND pp.cantidad = 40;
    SELECT pp.id INTO v_blister_c FROM public.app_dat_producto_presentacion pp
     WHERE pp.id_producto = v_producto_c AND pp.cantidad = 6;
    SELECT pp.id INTO v_unidad_c FROM public.app_dat_producto_presentacion pp
     WHERE pp.id_producto = v_producto_c AND pp.cantidad = 1;

    PERFORM public.fn_ingresar_presentacion(v_producto_a, 349, v_caja_a, 2, 1);
    PERFORM public.fn_ingresar_presentacion(v_producto_a, 349, v_bulto_a, 5, 1);
    PERFORM public.fn_ingresar_presentacion(v_producto_a, 349, v_unidad_a, 10, 1);

    v_plan := public.fn_planificar_cumplimiento_presentaciones_v2(
        v_producto_a, 349, v_unidad_a, 10, NULL, NULL
    );
    IF v_plan->>'status' <> 'success'
       OR jsonb_array_length(v_plan->'lineas_fisicas') <> 1
       OR (v_plan#>>'{lineas_fisicas,0,id_presentacion}')::bigint <> v_caja_a
       OR (v_plan#>>'{lineas_fisicas,0,cantidad}')::numeric <> 1 THEN
        RAISE EXCEPTION 'T1 pedido 10: esperaba 1 Caja, obtuvo %', v_plan;
    END IF;

    v_plan := public.fn_planificar_cumplimiento_presentaciones_v2(
        v_producto_a, 349, v_unidad_a, 15, NULL, NULL
    );
    IF v_plan->>'status' <> 'success'
       OR NOT EXISTS (
           SELECT 1 FROM jsonb_array_elements(v_plan->'lineas_fisicas') e
            WHERE (e->>'id_presentacion')::bigint = v_caja_a
              AND (e->>'cantidad')::numeric = 1
       ) OR NOT EXISTS (
           SELECT 1 FROM jsonb_array_elements(v_plan->'lineas_fisicas') e
            WHERE (e->>'id_presentacion')::bigint = v_bulto_a
              AND (e->>'cantidad')::numeric = 1
       ) THEN
        RAISE EXCEPTION 'T2 pedido 15: esperaba 1 Caja + 1 Bulto, obtuvo %', v_plan;
    END IF;

    v_plan := public.fn_planificar_cumplimiento_presentaciones_v2(
        v_producto_a, 349, v_unidad_a, 16, NULL, NULL
    );
    IF v_plan->>'status' <> 'success'
       OR NOT EXISTS (
           SELECT 1 FROM jsonb_array_elements(v_plan->'lineas_fisicas') e
            WHERE (e->>'id_presentacion')::bigint = v_bulto_a
              AND (e->>'cantidad')::numeric = 1
              AND e->>'origen' = 'empaque_cerrado'
       ) OR NOT EXISTS (
           SELECT 1 FROM jsonb_array_elements(v_plan->'lineas_fisicas') e
            WHERE (e->>'id_presentacion')::bigint = v_unidad_a
              AND (e->>'cantidad')::numeric = 10
              AND e->>'origen' = 'propio'
       ) OR NOT EXISTS (
           SELECT 1 FROM jsonb_array_elements(v_plan->'lineas_fisicas') e
            WHERE (e->>'id_presentacion')::bigint = v_unidad_a
              AND (e->>'cantidad')::numeric = 1
              AND e->>'origen' = 'apertura'
       ) THEN
        RAISE EXCEPTION 'T3 pedido 16: desglose físico incorrecto: %', v_plan;
    END IF;

    SELECT (s->>'cantidad')::numeric INTO v_valor
      FROM jsonb_array_elements(v_plan->'saldos_proyectados') s
     WHERE (s->>'id_presentacion')::bigint = v_caja_a;
    IF v_valor <> 2 THEN
        RAISE EXCEPTION 'T3 saldo Caja esperado 2, obtenido %', v_valor;
    END IF;
    SELECT (s->>'cantidad')::numeric INTO v_valor
      FROM jsonb_array_elements(v_plan->'saldos_proyectados') s
     WHERE (s->>'id_presentacion')::bigint = v_bulto_a;
    IF v_valor <> 3 THEN
        RAISE EXCEPTION 'T3 saldo Bulto esperado 3, obtenido %', v_valor;
    END IF;
    SELECT (s->>'cantidad')::numeric INTO v_valor
      FROM jsonb_array_elements(v_plan->'saldos_proyectados') s
     WHERE (s->>'id_presentacion')::bigint = v_unidad_a;
    IF v_valor <> 4 THEN
        RAISE EXCEPTION 'T3 saldo Unidad esperado 4, obtenido %', v_valor;
    END IF;

    PERFORM public.fn_ingresar_presentacion(v_producto_b, 349, v_caja_b, 1, 1);
    PERFORM public.fn_ingresar_presentacion(v_producto_b, 349, v_blister_b, 2, 1);
    v_plan := public.fn_planificar_cumplimiento_presentaciones_v2(
        v_producto_b, 349, v_unidad_b, 12, NULL, NULL
    );
    IF v_plan->>'status' <> 'success'
       OR jsonb_array_length(v_plan->'lineas_fisicas') <> 1
       OR (v_plan#>>'{lineas_fisicas,0,id_presentacion}')::bigint <> v_blister_b
       OR (v_plan#>>'{lineas_fisicas,0,cantidad}')::numeric <> 2 THEN
        RAISE EXCEPTION 'T4 no greedy: esperaba 2 Blíster ×6, obtuvo %', v_plan;
    END IF;

    PERFORM public.fn_ingresar_presentacion(v_producto_c, 349, v_caja_c, 1, 1);
    v_plan := public.fn_planificar_cumplimiento_presentaciones_v2(
        v_producto_c, 349, v_unidad_c, 40, NULL, NULL
    );
    IF v_plan->>'status' <> 'success'
       OR jsonb_array_length(v_plan->'conversiones') <> 0
       OR (v_plan#>>'{lineas_fisicas,0,id_presentacion}')::bigint <> v_caja_c THEN
        RAISE EXCEPTION 'T5 cobertura cerrada 40: esperaba 1 Caja, obtuvo %', v_plan;
    END IF;

    v_plan := public.fn_planificar_cumplimiento_presentaciones_v2(
        v_producto_c, 349, v_blister_c, 6, NULL, NULL
    );
    IF v_plan->>'status' <> 'success'
       OR NOT EXISTS (
           SELECT 1 FROM jsonb_array_elements(v_plan->'conversiones') c,
                         jsonb_array_elements(c->'patas') p
            WHERE p->>'tipo' = 'entrada'
              AND (p->>'id_presentacion')::bigint = v_blister_c
              AND (p->>'cantidad')::numeric = 6
       ) OR NOT EXISTS (
           SELECT 1 FROM jsonb_array_elements(v_plan->'conversiones') c,
                         jsonb_array_elements(c->'patas') p
            WHERE p->>'tipo' = 'entrada'
              AND (p->>'id_presentacion')::bigint = v_unidad_c
              AND (p->>'cantidad')::numeric = 4
       ) THEN
        RAISE EXCEPTION 'T6 Caja 40: esperaba apertura 6 Blíster + 4 Unidad, obtuvo %',
            v_plan;
    END IF;

    v_plan := public.fn_planificar_cumplimiento_presentaciones_v2(
        v_producto_a, 349, NULL, 10, NULL, NULL
    );
    IF v_plan->>'status' <> 'success'
       OR (v_plan->>'id_presentacion_solicitada')::bigint <> v_unidad_a THEN
        RAISE EXCEPTION 'T7 NULL no resolvió la presentación base: %', v_plan;
    END IF;

    v_plan := public.fn_planificar_cumplimiento_presentaciones_v2(
        v_producto_a, 349, v_caja_a, 11, NULL, NULL
    );
    IF v_plan->>'error_code' <> 'INSUFFICIENT_STOCK' THEN
        RAISE EXCEPTION 'T8 insuficiencia: esperaba INSUFFICIENT_STOCK, obtuvo %', v_plan;
    END IF;

    RAISE NOTICE '38_tests_planificador_cumplimiento_v2: 8 bloques OK';
END;
$test$;

ROLLBACK;
