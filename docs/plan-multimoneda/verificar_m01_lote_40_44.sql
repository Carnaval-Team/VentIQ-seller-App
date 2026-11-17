-- Solo lectura. Ejecutar despues de los scripts 40 a 44.
-- No demuestra una cuenta cerrada ni dos sesiones: el flag sigue apagado
-- y estas funciones rechazan el alta antes de escribir.
SELECT
    to_regclass('public.app_dat_mesa_v1_idempotencia') IS NOT NULL AS clave_mesa,
    to_regclass('public.app_dat_obligacion_linea_v1') IS NOT NULL AS obligacion,
    to_regclass('public.app_dat_ajuste_linea_v1') IS NOT NULL AS ajuste,
    (
        SELECT c.relrowsecurity AND c.relforcerowsecurity
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relname = 'app_dat_obligacion_linea_v1'
    ) AS obligacion_rls,
    to_regprocedure('public.fn_m01_pedir_item_mesa_v1(jsonb)') IS NOT NULL AS pedir,
    to_regprocedure('public.fn_m01_finalizar_cuenta_v1(jsonb)') IS NOT NULL AS cerrar,
    to_regprocedure('public.fn_m01_cxc_liquidar_v1(jsonb)') IS NOT NULL AS liquidar,
    to_regprocedure('public.fn_m01_devolver_linea_v1(jsonb)') IS NOT NULL AS devolver,
    has_function_privilege('anon', 'public.fn_m01_pedir_item_mesa_v1(jsonb)', 'EXECUTE') IS FALSE
        AND has_function_privilege('anon', 'public.fn_m01_cancelar_item_mesa_v1(jsonb)', 'EXECUTE') IS FALSE
        AND has_function_privilege('anon', 'public.fn_m01_finalizar_cuenta_v1(jsonb)', 'EXECUTE') IS FALSE
        AND has_function_privilege('anon', 'public.fn_m01_cxc_registrar_v1(jsonb)', 'EXECUTE') IS FALSE
        AND has_function_privilege('anon', 'public.fn_m01_cxc_saldo_v1(bigint)', 'EXECUTE') IS FALSE
        AND has_function_privilege('anon', 'public.fn_m01_cxc_liquidar_v1(jsonb)', 'EXECUTE') IS FALSE
        AND has_function_privilege('anon', 'public.fn_m01_devolver_linea_v1(jsonb)', 'EXECUTE') IS FALSE AS anon_pedir,
    (
        SELECT c.permitir_moneda_por_producto
        FROM public.app_dat_configuracion_tienda c
        WHERE c.permitir_moneda_por_producto IS TRUE
        LIMIT 1
    ) IS NULL AS flag_apagado;
