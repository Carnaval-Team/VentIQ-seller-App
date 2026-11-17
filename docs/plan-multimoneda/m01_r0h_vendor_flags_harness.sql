BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
DECLARE
    v_vendor bigint := NULLIF(current_setting('app.m01_fixture_vendor_id', true), '')::bigint;
    v_admin uuid := NULLIF(current_setting('app.m01_fixture_admin_uuid', true), '')::uuid;
    v_denied uuid := NULLIF(current_setting('app.m01_fixture_denied_uuid', true), '')::uuid;
    v_store bigint;
    v_legacy uuid := gen_random_uuid();
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r0h_flags_harness_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Harness NO EJECUTAR sin autorizacion especifica y fixtures de prueba en newa';
    END IF;
    IF v_vendor IS NULL OR v_admin IS NULL OR v_denied IS NULL OR v_admin = v_denied THEN
        RAISE EXCEPTION 'Configurar fixture_vendor_id, fixture_admin_uuid y fixture_denied_uuid de M01';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid IN ('public.app_dat_vendedor'::regclass,
                          'public.app_dat_operacion_offline_idempotencia'::regclass)
          AND NOT tgisinternal AND tgenabled <> 'D'
    ) THEN
        RAISE EXCEPTION 'Revisar efectos de triggers antes de modificar fixtures, incluso con ROLLBACK';
    END IF;
    PERFORM id FROM public.app_dat_vendedor WHERE id = v_vendor FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Fixture vendedor inexistente';
    END IF;
    v_store := public.fn_m01_personal_vendedor_id_tienda(v_vendor);
    IF v_store IS NULL THEN
        RAISE EXCEPTION 'Fixture sin ambito verificable';
    END IF;
    PERFORM set_config('app.m01_fixture_store_id', v_store::text, true);
    PERFORM set_config('app.m01_fixture_legacy_uuid', v_legacy::text, true);
    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario)
    VALUES (v_legacy, v_vendor, 'admin_vendor_flags', v_admin);
END;
$preflight$;

SET LOCAL ROLE authenticated;

DO $tests$
DECLARE
    v_vendor bigint := current_setting('app.m01_fixture_vendor_id')::bigint;
    v_admin uuid := current_setting('app.m01_fixture_admin_uuid')::uuid;
    v_denied uuid := current_setting('app.m01_fixture_denied_uuid')::uuid;
    v_store bigint := current_setting('app.m01_fixture_store_id')::bigint;
    v_legacy uuid := current_setting('app.m01_fixture_legacy_uuid')::uuid;
    v_key uuid := gen_random_uuid();
    v_second_key uuid := gen_random_uuid();
    v_null_key uuid := gen_random_uuid();
    v_target boolean;
    v_actual boolean;
    v_reply jsonb;
BEGIN
    PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    IF auth.uid() IS DISTINCT FROM v_admin
       OR public.fn_config_tienda_puede_escribir(v_store) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Fixture admin no tiene permiso administrativo real sobre tienda';
    END IF;
    SELECT permitir_customizar_precio_venta IS DISTINCT FROM true INTO v_target
    FROM public.app_dat_vendedor WHERE id = v_vendor;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Admin no puede leer fixture vendedor bajo RLS';
    END IF;

    v_reply := public.fn_admin_caja_vendor_flags_offline(v_key, v_vendor, v_target);
    IF v_reply IS DISTINCT FROM jsonb_build_object('success', true, 'idempotent', false, 'id_vendedor', v_vendor) THEN
        RAISE EXCEPTION 'Respuesta de primer envio invalida';
    END IF;
    SELECT permitir_customizar_precio_venta INTO v_actual
    FROM public.app_dat_vendedor WHERE id = v_vendor;
    IF v_actual IS DISTINCT FROM v_target THEN
        RAISE EXCEPTION 'Primer envio no cambio el flag';
    END IF;

    PERFORM public.fn_admin_caja_vendor_flags_offline(v_second_key, v_vendor, NOT v_target);
    v_reply := public.fn_admin_caja_vendor_flags_offline(v_key, v_vendor, v_target);
    SELECT permitir_customizar_precio_venta INTO v_actual
    FROM public.app_dat_vendedor WHERE id = v_vendor;
    IF v_actual IS DISTINCT FROM (NOT v_target)
       OR v_reply IS DISTINCT FROM jsonb_build_object('success', true, 'idempotent', true, 'id_vendedor', v_vendor) THEN
        RAISE EXCEPTION 'Replay altero un cambio posterior';
    END IF;

    BEGIN
        PERFORM public.fn_admin_caja_vendor_flags_offline(v_key, v_vendor, NOT v_target);
        RAISE EXCEPTION 'Payload distinto aceptado';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    BEGIN
        PERFORM public.fn_admin_caja_vendor_assign_tpv_offline(v_key, v_vendor, NULL);
        RAISE EXCEPTION 'Tipo distinto aceptado';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    BEGIN
        PERFORM public.fn_admin_caja_vendor_flags_offline(v_legacy, v_vendor, v_target);
        RAISE EXCEPTION 'UUID legacy aceptado';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;

    PERFORM public.fn_admin_caja_vendor_flags_offline(v_null_key, v_vendor, NULL);
    SELECT permitir_customizar_precio_venta INTO v_actual
    FROM public.app_dat_vendedor WHERE id = v_vendor;
    IF v_actual IS DISTINCT FROM false THEN
        RAISE EXCEPTION 'NULL no conserva normalizacion legacy a false';
    END IF;
    BEGIN
        PERFORM public.fn_admin_caja_vendor_flags_offline(v_null_key, v_vendor, false);
        RAISE EXCEPTION 'Solicitud false sustituye incorrectamente solicitud NULL';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;

    PERFORM set_config('request.jwt.claim.sub', v_denied::text, true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_denied, 'role', 'authenticated')::text, true);
    IF auth.uid() IS DISTINCT FROM v_denied
       OR public.fn_config_tienda_puede_escribir(v_store) IS DISTINCT FROM false THEN
        RAISE EXCEPTION 'Fixture denegado tiene acceso o identidad inesperados';
    END IF;
    BEGIN
        PERFORM public.fn_admin_caja_vendor_flags_offline(v_key, v_vendor, v_target);
        RAISE EXCEPTION 'Actor ajeno aceptado en replay';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    BEGIN
        PERFORM public.fn_admin_caja_vendor_flags_offline(gen_random_uuid(), v_vendor, true);
        RAISE EXCEPTION 'Actor ajeno aceptado en primer envio';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;

    PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
    PERFORM set_config('request.jwt.claims', jsonb_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    SELECT permitir_customizar_precio_venta INTO v_actual
    FROM public.app_dat_vendedor WHERE id = v_vendor;
    IF NOT FOUND OR v_actual IS DISTINCT FROM false THEN
        RAISE EXCEPTION 'Denegacion altero el fixture';
    END IF;
END;
$tests$;

RESET ROLE;
SET LOCAL ROLE anon;

DO $anon$
BEGIN
    BEGIN
        PERFORM public.fn_admin_caja_vendor_flags_offline(
            gen_random_uuid(), current_setting('app.m01_fixture_vendor_id')::bigint, true);
        RAISE EXCEPTION 'Anon obtuvo EXECUTE';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
END;
$anon$;

RESET ROLE;
SELECT 'R0h flags: comprobaciones de una sesion finalizadas; concurrencia pendiente' AS resultado;
ROLLBACK;
