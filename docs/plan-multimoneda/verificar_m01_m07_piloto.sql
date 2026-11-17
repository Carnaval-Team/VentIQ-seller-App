-- Solo lectura. MC-049 a MC-051.
-- No enciende el flag, no elige tienda y no demuestra una venta desde la app.
SELECT
    (
        SELECT NOT bool_or(COALESCE(c.permitir_moneda_por_producto, false))
        FROM public.app_dat_configuracion_tienda c
    ) AS flag_apagado,
    has_function_privilege('anon', 'public.fn_m01_pedir_item_mesa_v1(jsonb)', 'EXECUTE') IS FALSE
        AND has_function_privilege('anon', 'public.fn_m01_finalizar_cuenta_v1(jsonb)', 'EXECUTE') IS FALSE
        AND has_function_privilege('anon', 'public.fn_m01_devolver_linea_v1(jsonb)', 'EXECUTE') IS FALSE
        AS anon_sin_ejecutar,
    position(
        '= ''cocina_al_pedido''' in pg_get_functiondef(
            'public.fn_m01_pedir_item_mesa_v1(jsonb)'::regprocedure
        )
    ) > 0 AS comanda_al_pedido,
    position(
        'IS DISTINCT FROM ''tpv''' in pg_get_functiondef(
            'public.fn_m01_pedir_item_mesa_v1(jsonb)'::regprocedure
        )
    ) = 0 AS sin_comanda_por_tpv,
    (
        SELECT pg_get_triggerdef(t.oid) LIKE '%BEFORE INSERT%'
           AND pg_get_functiondef(p.oid) NOT LIKE '%UPDATE public.app_dat_operacion_venta%'
           AND pg_get_functiondef(p.oid) NOT LIKE '%DELETE FROM%'
        FROM pg_trigger t
        JOIN pg_proc p ON p.oid = t.tgfoid
        JOIN pg_class c ON c.oid = t.tgrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND t.tgname = 'm01_venta_legacy_con_flag'
    ) AS apagado_solo_insert,
    (
        SELECT count(*) = 0
        FROM public.app_dat_operacion_venta v
        WHERE v.version_monetaria = 'producto-v1'
    ) AS sin_venta_v1_aceptada;
