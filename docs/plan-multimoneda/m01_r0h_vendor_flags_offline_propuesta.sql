BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r0h_flags_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador parcial R0h-flags: NO EJECUTAR sin revision del conjunto M01 en newa';
    END IF;
    IF has_schema_privilege('anon', 'public', 'CREATE')
       OR has_schema_privilege('authenticated', 'public', 'CREATE') THEN
        RAISE EXCEPTION 'public permite CREATE a roles no confiables';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc
        WHERE oid = to_regprocedure('public.fn_admin_caja_vendor_flags_offline(uuid,bigint,boolean)')
          AND md5(prosrc) = '9034dcd2f4ad7c8c5d2cee664c3bc709'
          AND prosecdef AND proowner = 'postgres'::regrole
    ) THEN
        RAISE EXCEPTION 'La entrada de flags difiere del baseline newa; revisar sin reemplazar avances';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = 'public.app_dat_operacion_offline_idempotencia'::regclass
          AND attname = 'm01_solicitud' AND atttypid = 'jsonb'::regtype AND NOT attisdropped
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = 'public.app_dat_operacion_offline_idempotencia'::regclass
          AND attname = 'm01_id_tienda' AND atttypid = 'bigint'::regtype AND NOT attisdropped
    ) OR to_regprocedure('public.fn_config_tienda_puede_escribir(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Falta la evidencia compartida de idempotencia o el predicado S01';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_class
        WHERE oid IN (
            'public.app_dat_operacion_offline_idempotencia'::regclass,
            'public.app_dat_vendedor'::regclass,
            'public.app_dat_trabajadores'::regclass,
            'public.app_dat_tpv'::regclass
        ) AND (NOT relrowsecurity OR relowner <> 'postgres'::regrole)
    ) OR has_any_column_privilege('authenticated', 'public.app_dat_operacion_offline_idempotencia', 'INSERT')
       OR has_any_column_privilege('authenticated', 'public.app_dat_operacion_offline_idempotencia', 'UPDATE')
       OR has_table_privilege('authenticated', 'public.app_dat_operacion_offline_idempotencia', 'DELETE') THEN
        RAISE EXCEPTION 'Falta aislamiento M01 de fuentes/idempotencia';
    END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.fn_admin_caja_vendor_flags_offline(
    p_client_uuid uuid,
    p_id_vendedor bigint,
    p_permitir_customizar_precio_venta boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_request jsonb;
    v_existing public.app_dat_operacion_offline_idempotencia%ROWTYPE;
    v_vendor public.app_dat_vendedor%ROWTYPE;
    v_worker public.app_dat_trabajadores%ROWTYPE;
    v_tpv_store bigint;
    v_store bigint;
BEGIN
    IF v_actor IS NULL OR p_client_uuid IS NULL OR p_id_vendedor IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    v_request := jsonb_build_object('version', 1, 'id_vendedor', p_id_vendedor,
        'permitir_customizar_precio_venta', p_permitir_customizar_precio_venta);
    PERFORM pg_advisory_xact_lock(hashtextextended(p_client_uuid::text, 0));

    SELECT * INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid
    FOR UPDATE;

    IF FOUND THEN
        IF v_existing.tipo IS DISTINCT FROM 'admin_vendor_flags'
           OR v_existing.uuid_usuario IS DISTINCT FROM v_actor
           OR v_existing.id_operacion IS DISTINCT FROM p_id_vendedor
           OR v_existing.m01_solicitud IS DISTINCT FROM v_request
           OR public.fn_config_tienda_puede_escribir(v_existing.m01_id_tienda) IS DISTINCT FROM true THEN
            RAISE EXCEPTION 'Clave no verificable o solicitud no autorizada; requiere revision'
                USING ERRCODE = '42501';
        END IF;
        RETURN jsonb_build_object('success', true, 'idempotent', true, 'id_vendedor', p_id_vendedor);
    END IF;

    SELECT * INTO v_vendor
    FROM public.app_dat_vendedor WHERE id = p_id_vendedor
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    IF v_vendor.id_trabajador IS NOT NULL THEN
        SELECT * INTO v_worker
        FROM public.app_dat_trabajadores WHERE id = v_vendor.id_trabajador
        FOR SHARE;
        IF NOT FOUND OR v_worker.id_tienda IS NULL OR v_worker.deleted_at IS NOT NULL
           OR v_worker.uuid IS DISTINCT FROM v_vendor.uuid THEN
            RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF v_vendor.id_tpv IS NOT NULL THEN
        SELECT id_tienda INTO v_tpv_store
        FROM public.app_dat_tpv WHERE id = v_vendor.id_tpv
        FOR SHARE;
        IF NOT FOUND OR v_tpv_store IS NULL THEN
            RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF v_vendor.id_trabajador IS NOT NULL AND v_vendor.id_tpv IS NOT NULL
       AND v_worker.id_tienda IS DISTINCT FROM v_tpv_store THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_store := COALESCE(v_worker.id_tienda, v_tpv_store);
    IF v_store IS NULL OR public.fn_config_tienda_puede_escribir(v_store) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    UPDATE public.app_dat_vendedor
    SET permitir_customizar_precio_venta = COALESCE(p_permitir_customizar_precio_venta, false)
    WHERE id = p_id_vendedor;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES
        (p_client_uuid, p_id_vendedor, 'admin_vendor_flags', v_actor, v_request, v_store);

    RETURN jsonb_build_object('success', true, 'idempotent', false, 'id_vendedor', p_id_vendedor);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_admin_caja_vendor_flags_offline(uuid,bigint,boolean)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_admin_caja_vendor_flags_offline(uuid,bigint,boolean)
    TO authenticated;

COMMIT;
