BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r0h_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador parcial R0h: NO EJECUTAR sin revision del conjunto M01 en newa';
    END IF;
    IF has_schema_privilege('anon', 'public', 'CREATE')
       OR has_schema_privilege('authenticated', 'public', 'CREATE') THEN
        RAISE EXCEPTION 'public permite CREATE a roles no confiables';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc
        WHERE oid = to_regprocedure('public.fn_admin_caja_vendor_assign_tpv_offline(uuid,bigint,bigint)')
          AND md5(prosrc) = '505a3b0c355f07ca4e6fa14fa8d7dd93'
          AND prosecdef AND proowner = 'postgres'::regrole
    ) THEN
        RAISE EXCEPTION 'La entrada offline difiere del baseline newa; revisar sin reemplazar avances';
    END IF;
    IF to_regprocedure('public.fn_m01_personal_exigir_reasignacion_vendedor(bigint,bigint)') IS NULL
       OR to_regprocedure('public.fn_config_tienda_puede_escribir(bigint)') IS NULL
       OR NOT EXISTS (
           SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'public' AND p.proname = 'fn_m01_agregar_rol_trabajador'
       ) THEN
        RAISE EXCEPTION 'Faltan dependencias M01 R0b/R0f; no aplicar aisladamente';
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
    IF NOT EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = 'public.app_dat_operacion_offline_idempotencia'::regclass
          AND attname = 'm01_solicitud' AND atttypid = 'jsonb'::regtype AND NOT attisdropped
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = 'public.app_dat_operacion_offline_idempotencia'::regclass
          AND attname = 'm01_id_tienda' AND atttypid = 'bigint'::regtype AND NOT attisdropped
    ) THEN
        RAISE EXCEPTION 'Falta la evidencia compartida de idempotencia; no la crea este corte de Admin Lite';
    END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.fn_admin_caja_vendor_assign_tpv_offline(
    p_client_uuid uuid,
    p_id_vendedor bigint,
    p_id_tpv bigint
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
    v_store bigint;
BEGIN
    IF v_actor IS NULL OR p_client_uuid IS NULL OR p_id_vendedor IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    v_request := jsonb_build_object('version', 1, 'id_vendedor', p_id_vendedor, 'id_tpv', p_id_tpv);
    PERFORM pg_advisory_xact_lock(hashtextextended(p_client_uuid::text, 0));

    SELECT * INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid
    FOR UPDATE;

    IF FOUND THEN
        IF v_existing.tipo IS DISTINCT FROM 'admin_vendor_assign'
           OR v_existing.uuid_usuario IS DISTINCT FROM v_actor
           OR v_existing.id_operacion IS DISTINCT FROM p_id_vendedor
           OR v_existing.m01_solicitud IS DISTINCT FROM v_request
           OR public.fn_config_tienda_puede_escribir(v_existing.m01_id_tienda) IS DISTINCT FROM true THEN
            RAISE EXCEPTION 'Clave no verificable o solicitud no autorizada; requiere revision'
                USING ERRCODE = '42501';
        END IF;
        RETURN jsonb_build_object('success', true, 'idempotent', true, 'id_vendedor', p_id_vendedor);
    END IF;

    PERFORM public.fn_m01_personal_exigir_reasignacion_vendedor(p_id_vendedor, p_id_tpv);

    SELECT COALESCE(w.id_tienda, t.id_tienda) INTO v_store
    FROM public.app_dat_vendedor v
    LEFT JOIN public.app_dat_trabajadores w ON w.id = v.id_trabajador
    LEFT JOIN public.app_dat_tpv t ON t.id = v.id_tpv
    WHERE v.id = p_id_vendedor;

    IF v_store IS NULL OR public.fn_config_tienda_puede_escribir(v_store) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    UPDATE public.app_dat_vendedor
    SET id_tpv = p_id_tpv
    WHERE id = p_id_vendedor;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES
        (p_client_uuid, p_id_vendedor, 'admin_vendor_assign', v_actor, v_request, v_store);

    RETURN jsonb_build_object('success', true, 'idempotent', false, 'id_vendedor', p_id_vendedor);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_admin_caja_vendor_assign_tpv_offline(uuid,bigint,bigint)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_admin_caja_vendor_assign_tpv_offline(uuid,bigint,bigint)
    TO authenticated;

COMMIT;
