-- ============================================================================
-- 40 tests · Registro de conversiones físicas N→N v2
-- ============================================================================
-- Requiere 35 y 40. Todo el escenario sintético termina en ROLLBACK.
-- ============================================================================

BEGIN;

DO $test$
DECLARE
    v_id_categoria bigint;
    v_producto bigint;
    v_caja bigint;
    v_blister bigint;
    v_unidad bigint;
    v_evento bigint;
    v_rechazo boolean := false;
    v_prosecdef boolean;
    v_proconfig text[];
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
        223, v_id_categoria, 'ZZ TEST conversión N a N',
        'ZZ-CONVERSION-N-N', true, true, false, false, false, now()
    ) RETURNING id INTO v_producto;

    INSERT INTO public.app_dat_producto_presentacion (
        id_producto, id_presentacion, cantidad, es_base, precio_promedio, created_at
    ) VALUES
        (v_producto, 3, 40, false, 0, now()),
        (v_producto, 22, 6, false, 0, now()),
        (v_producto, 1, 1, true, 0, now());

    SELECT id INTO v_caja FROM public.app_dat_producto_presentacion
     WHERE id_producto = v_producto AND cantidad = 40;
    SELECT id INTO v_blister FROM public.app_dat_producto_presentacion
     WHERE id_producto = v_producto AND cantidad = 6;
    SELECT id INTO v_unidad FROM public.app_dat_producto_presentacion
     WHERE id_producto = v_producto AND cantidad = 1;

    v_evento := public.fn_registrar_conversion_v2(
        v_producto, 349, 'apertura',
        jsonb_build_array(
            jsonb_build_object('tipo', 'salida', 'id_presentacion', v_caja,
                               'cantidad', 1, 'factor_entero', 40),
            jsonb_build_object('tipo', 'entrada', 'id_presentacion', v_blister,
                               'cantidad', 6, 'factor_entero', 6),
            jsonb_build_object('tipo', 'entrada', 'id_presentacion', v_unidad,
                               'cantidad', 4, 'factor_entero', 1)
        )
    );

    IF NOT EXISTS (
        SELECT 1
          FROM public.app_dat_conversion_presentacion_evento e
         WHERE e.id = v_evento
           AND e.tipo = 'apertura'
           AND e.id_producto = v_producto
           AND e.id_ubicacion = 349
    ) OR (SELECT count(*) FROM public.app_dat_conversion_presentacion_pata p
           WHERE p.id_conversion_evento = v_evento) <> 3
       OR (SELECT sum(CASE WHEN p.tipo = 'salida' THEN p.equivalente ELSE 0 END)
             FROM public.app_dat_conversion_presentacion_pata p
            WHERE p.id_conversion_evento = v_evento) <> 40
       OR (SELECT sum(CASE WHEN p.tipo = 'entrada' THEN p.equivalente ELSE 0 END)
             FROM public.app_dat_conversion_presentacion_pata p
            WHERE p.id_conversion_evento = v_evento) <> 40
       OR EXISTS (
            SELECT 1 FROM public.app_dat_conversion_presentacion_pata p
             WHERE p.id_conversion_evento = v_evento
               AND trunc(p.cantidad) <> p.cantidad
       ) THEN
        RAISE EXCEPTION 'T1 conversión 40 -> 6x6 + 4x1 incorrecta';
    END IF;

    BEGIN
        PERFORM public.fn_registrar_conversion_v2(
            v_producto, 349, 'apertura',
            jsonb_build_array(
                jsonb_build_object('tipo', 'salida', 'id_presentacion', v_caja,
                                   'cantidad', 1, 'factor_entero', 40),
                jsonb_build_object('tipo', 'entrada', 'id_presentacion', v_blister,
                                   'cantidad', 6, 'factor_entero', 6)
            )
        );
    EXCEPTION WHEN SQLSTATE '22023' THEN
        v_rechazo := true;
    END;
    IF NOT v_rechazo THEN
        RAISE EXCEPTION 'T2 no rechazó una conversión no neutral';
    END IF;

    v_rechazo := false;
    BEGIN
        PERFORM public.fn_registrar_conversion_v2(
            v_producto, 349, 'apertura',
            jsonb_build_array(
                jsonb_build_object('tipo', 'salida', 'id_presentacion', v_caja,
                                   'cantidad', 1, 'factor_entero', 40),
                jsonb_build_object('tipo', 'entrada', 'id_presentacion', v_unidad,
                                   'cantidad', 40, 'factor_entero', 2)
            )
        );
    EXCEPTION WHEN SQLSTATE '22023' THEN
        v_rechazo := true;
    END;
    IF NOT v_rechazo THEN
        RAISE EXCEPTION 'T3 no rechazó un factor manipulado';
    END IF;

    SELECT p.prosecdef, p.proconfig
      INTO v_prosecdef, v_proconfig
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'fn_registrar_conversion_v2';

    IF v_prosecdef
       OR v_proconfig IS DISTINCT FROM ARRAY['search_path=""']::text[]
       OR has_function_privilege('public',
              'public.fn_registrar_conversion_v2(bigint,bigint,text,jsonb,bigint,bigint,bigint,uuid,text)',
              'EXECUTE')
       OR has_function_privilege('anon',
              'public.fn_registrar_conversion_v2(bigint,bigint,text,jsonb,bigint,bigint,bigint,uuid,text)',
              'EXECUTE')
       OR has_function_privilege('authenticated',
              'public.fn_registrar_conversion_v2(bigint,bigint,text,jsonb,bigint,bigint,bigint,uuid,text)',
              'EXECUTE')
       OR NOT has_function_privilege('service_role',
              'public.fn_registrar_conversion_v2(bigint,bigint,text,jsonb,bigint,bigint,bigint,uuid,text)',
              'EXECUTE')
       OR NOT (SELECT c.relrowsecurity FROM pg_class c
                WHERE c.oid = 'public.app_dat_conversion_presentacion_evento'::regclass)
       OR NOT (SELECT c.relrowsecurity FROM pg_class c
                WHERE c.oid = 'public.app_dat_conversion_presentacion_pata'::regclass)
       OR has_table_privilege('anon',
              'public.app_dat_conversion_presentacion_evento', 'SELECT')
       OR has_table_privilege('authenticated',
              'public.app_dat_conversion_presentacion_pata', 'SELECT') THEN
        RAISE EXCEPTION 'T4 metadatos, RLS o ACL inseguros en conversiones v2';
    END IF;

    IF NOT public.fn_conversion_inventario_es_interna_v2(NULL, v_evento)
       OR public.fn_conversion_inventario_es_interna_v2(NULL, NULL) THEN
        RAISE EXCEPTION 'T5 guarda compartida de conversión incorrecta';
    END IF;

    RAISE NOTICE '40_tests_conversion_evento_v2: 5 bloques OK';
END;
$test$;

ROLLBACK;
