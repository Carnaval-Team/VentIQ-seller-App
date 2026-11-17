BEGIN;

-- HARNESS de rol y concurrencia. NO EJECUTAR.
-- No contiene IDs. Quien lo corra, en la misma sesión y antes del archivo,
-- fija las GUC con identificadores de prueba revisados. No usar vendedores
-- reales ni main. Todo queda dentro de esta transacción y termina en ROLLBACK.
-- No abre una segunda sesión: el replay concurrente se comprueba en secuencia
-- bajo el mismo candado. Dos pestañas del SQL Editor siguen siendo una prueba
-- manual aparte, después de aplicar los scripts.

SET LOCAL app.m01_r0i_rol_harness_approved = 'yes';
SET LOCAL app.m01_fixture_vendor_uuid = 'd99d3333-83a9-4f33-8b53-3dbe744fb0ec';
SET LOCAL app.m01_fixture_other_store_id = '5';
SET LOCAL app.m01_fixture_store_id = '4';
SET LOCAL app.m01_fixture_admin_uuid = '2f29fed6-e1d8-44d3-b5e4-5268dadad8a3';

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $harness$
DECLARE
    v_vendor uuid;
    v_other_store bigint;
    v_store bigint;
    v_admin uuid;
    v_uuid uuid := gen_random_uuid();
    v_first jsonb;
    v_second jsonb;
    v_denied boolean;
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r0i_rol_harness_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Harness de rol: NO EJECUTAR sin revision y sin GUC de prueba';
    END IF;
    BEGIN
        v_vendor := current_setting('app.m01_fixture_vendor_uuid', true)::uuid;
        v_other_store := current_setting('app.m01_fixture_other_store_id', true)::bigint;
        v_store := current_setting('app.m01_fixture_store_id', true)::bigint;
        v_admin := current_setting('app.m01_fixture_admin_uuid', true)::uuid;
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'Faltan GUC de prueba: vendor, otra tienda, tienda y admin';
    END;
    IF v_vendor IS NULL OR v_other_store IS NULL
       OR v_store IS NULL OR v_admin IS NULL OR v_vendor = v_admin THEN
        RAISE EXCEPTION 'GUC de prueba incompletas o vendor y admin son la misma persona';
    END IF;
    IF to_regprocedure('public.fn_m01_actualizar_config_tienda(uuid,bigint,text,jsonb)') IS NULL
       OR to_regprocedure('public.fn_m01_marcar_tienda_prueba(bigint,boolean)') IS NULL
       OR to_regprocedure('public.fn_m01_validar_tienda_catalogo(bigint,boolean)') IS NULL THEN
        RAISE EXCEPTION 'Faltan las funciones de los scripts 21 y 22';
    END IF;

    -- Vendedor de otra tienda.
    PERFORM set_config('request.jwt.claim.sub', v_vendor::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_vendor)::text, true);
    v_denied := false;
    BEGIN
        EXECUTE 'SET LOCAL ROLE authenticated';
        PERFORM public.fn_m01_actualizar_config_tienda(
            v_uuid, v_other_store, 'modo_restaurante', 'false'::jsonb
        );
    EXCEPTION WHEN insufficient_privilege THEN
        v_denied := true;
    END;
    EXECUTE 'RESET ROLE';
    IF v_denied IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'El vendedor de otra tienda no fue rechazado';
    END IF;

    -- newa no tiene un superadmin inactivo. Ese rechazo no se prueba aqui.
    -- El vendedor no escala a marcar la tienda como prueba.
    PERFORM set_config('request.jwt.claim.sub', v_vendor::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_vendor)::text, true);
    v_denied := false;
    BEGIN
        EXECUTE 'SET LOCAL ROLE authenticated';
        PERFORM public.fn_m01_marcar_tienda_prueba(v_store, true);
    EXCEPTION WHEN insufficient_privilege THEN
        v_denied := true;
    END;
    EXECUTE 'RESET ROLE';
    IF v_denied IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'El vendedor pudo escalar a marcar la tienda de prueba';
    END IF;

    -- Replay: la segunda llamada con la misma clave no vuelve a escribir.
    PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin)::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    v_first := public.fn_m01_actualizar_config_tienda(
        v_uuid, v_store, 'guardar_impresora_por_defecto', 'false'::jsonb
    );
    v_second := public.fn_m01_actualizar_config_tienda(
        v_uuid, v_store, 'guardar_impresora_por_defecto', 'false'::jsonb
    );
    IF (v_second->>'idempotent') IS DISTINCT FROM 'true' THEN
        RAISE EXCEPTION 'El replay no devolvio la clave original';
    END IF;
    v_denied := false;
    BEGIN
        PERFORM public.fn_m01_actualizar_config_tienda(
            v_uuid, v_store, 'guardar_impresora_por_defecto', 'true'::jsonb
        );
    EXCEPTION WHEN insufficient_privilege THEN
        v_denied := true;
    END;
    EXECUTE 'RESET ROLE';
    IF v_denied IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'La misma clave acepto otra solicitud';
    END IF;
    IF (SELECT count(*) FROM public.app_dat_operacion_offline_idempotencia
        WHERE client_uuid = v_uuid) IS DISTINCT FROM 1 THEN
        RAISE EXCEPTION 'El replay dejo mas de una clave';
    END IF;
    RAISE NOTICE 'Harness de rol: vendedor ajeno, escalacion y replay secuencial pasaron. Se revierte.';
END;
$harness$;

ROLLBACK;
