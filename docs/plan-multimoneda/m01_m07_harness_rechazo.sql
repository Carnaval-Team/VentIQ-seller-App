BEGIN;

-- BORRADOR MC-048. NO EJECUTAR en main. Termina en ROLLBACK.
-- La sesión del SQL Editor no tiene auth.uid(). Cada alta tiene que
-- rechazarse antes de escribir. No enciende el flag. No prueba dos
-- pestañas, una venta aceptada ni un vendedor real.

SET LOCAL app.m01_m07_harness_approved = 'yes';

DO $harness$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_m07_harness_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Harness MC-048: NO EJECUTAR sin revision';
    END IF;
    IF auth.uid() IS NOT NULL THEN
        RAISE EXCEPTION 'Este harness solo cubre la sesion sin usuario';
    END IF;
    IF has_function_privilege('anon', 'public.fn_m01_pedir_item_mesa_v1(jsonb)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.fn_m01_cancelar_item_mesa_v1(jsonb)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.fn_m01_finalizar_cuenta_v1(jsonb)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.fn_m01_cxc_registrar_v1(jsonb)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.fn_m01_cxc_saldo_v1(bigint)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.fn_m01_cxc_liquidar_v1(jsonb)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.fn_m01_devolver_linea_v1(jsonb)', 'EXECUTE') THEN
        RAISE EXCEPTION 'anon todavia ejecuta una funcion de mesa, deuda o devolucion';
    END IF;
    BEGIN
        PERFORM public.fn_m01_pedir_item_mesa_v1('{"version_monetaria":"producto-v1"}'::jsonb);
        RAISE EXCEPTION 'El pedido sin actor no fue rechazado';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    BEGIN
        PERFORM public.fn_m01_cancelar_item_mesa_v1('{"version_monetaria":"producto-v1"}'::jsonb);
        RAISE EXCEPTION 'La cancelacion sin actor no fue rechazada';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    BEGIN
        PERFORM public.fn_m01_finalizar_cuenta_v1('{"version_monetaria":"producto-v1"}'::jsonb);
        RAISE EXCEPTION 'El cierre sin actor no fue rechazado';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    BEGIN
        PERFORM public.fn_m01_cxc_registrar_v1('{"version_monetaria":"producto-v1"}'::jsonb);
        RAISE EXCEPTION 'La deuda sin actor no fue rechazada';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    BEGIN
        PERFORM public.fn_m01_cxc_liquidar_v1('{"version_monetaria":"producto-v1"}'::jsonb);
        RAISE EXCEPTION 'La liquidacion sin actor no fue rechazada';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    BEGIN
        PERFORM public.fn_m01_devolver_linea_v1('{"version_monetaria":"producto-v1"}'::jsonb);
        RAISE EXCEPTION 'La devolucion sin actor no fue rechazada';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    RAISE NOTICE 'Harness M07: anon sin EXECUTE y sesion sin actor rechazada. Se revierte.';
END;
$harness$;

ROLLBACK;
