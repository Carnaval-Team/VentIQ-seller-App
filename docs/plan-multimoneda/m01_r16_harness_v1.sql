BEGIN;

-- BORRADOR MC-028. NO EJECUTAR en main.
-- Una sola sesión, sin usuario autenticado. Termina en ROLLBACK.
-- No prueba dos pestañas, ni un vendedor real, ni una venta aceptada:
-- el flag sigue apagado y esta sesión no tiene auth.uid().

SET LOCAL app.m01_r16_harness_approved = 'yes';

DO $harness$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r16_harness_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Harness MC-028: NO EJECUTAR sin revision';
    END IF;
    IF auth.uid() IS NOT NULL THEN
        RAISE EXCEPTION 'Este harness solo cubre la sesion sin usuario';
    END IF;
    IF has_function_privilege('anon', 'public.fn_m01_registrar_venta_v1(jsonb)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.fn_m01_registrar_pagos_v1(jsonb)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.fn_m01_ajustar_linea_v1(jsonb)', 'EXECUTE') THEN
        RAISE EXCEPTION 'anon puede ejecutar el contrato v1' USING ERRCODE = '42501';
    END IF;
    BEGIN
        PERFORM public.fn_m01_registrar_venta_v1('{"version_monetaria":"producto-v1"}'::jsonb);
        RAISE EXCEPTION 'La venta sin actor no fue rechazada';
    EXCEPTION WHEN insufficient_privilege THEN
        NULL;
    END;
    BEGIN
        PERFORM public.fn_m01_registrar_pagos_v1('{"version_monetaria":"producto-v1"}'::jsonb);
        RAISE EXCEPTION 'El cobro sin actor no fue rechazado';
    EXCEPTION WHEN insufficient_privilege THEN
        NULL;
    END;
    BEGIN
        PERFORM public.fn_m01_ajustar_linea_v1('{"version_monetaria":"producto-v1"}'::jsonb);
        RAISE EXCEPTION 'El ajuste sin actor no fue rechazado';
    EXCEPTION WHEN insufficient_privilege THEN
        NULL;
    END;
    RAISE NOTICE 'Harness v1: anon y sesion sin actor fueron rechazados. Se revierte.';
END;
$harness$;

ROLLBACK;
