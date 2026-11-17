BEGIN;

SET LOCAL app.m01_r0b_guard_approved = 'yes';

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r0b_guard_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador parcial R0b: requiere revision del conjunto M01 y ejecucion manual en newa';
    END IF;
    IF has_schema_privilege('anon', 'public', 'CREATE')
       OR has_schema_privilege('authenticated', 'public', 'CREATE') THEN
        RAISE EXCEPTION 'public permite CREATE a roles no confiables; revisar antes de aplicar';
    END IF;
    IF to_regprocedure('public.fn_config_tienda_puede_escribir(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Falta el contrato S01; no reemplazarlo por un permiso generico';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'fn_m01_personal_exigir_reasignacion_vendedor'
    ) THEN
        RAISE EXCEPTION 'La guarda ya existe; revisar avances de newa antes de continuar';
    END IF;
END;
$preflight$;

CREATE FUNCTION public.fn_m01_personal_exigir_reasignacion_vendedor(
    p_id_vendedor bigint,
    p_id_tpv bigint
)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_uuid uuid;
    v_worker_id bigint;
    v_old_tpv_id bigint;
    v_worker_uuid uuid;
    v_worker_store bigint;
    v_old_tpv_store bigint;
    v_old_store bigint;
    v_new_store bigint;
BEGIN
    IF auth.uid() IS NULL OR p_id_vendedor IS NULL THEN
        RAISE EXCEPTION 'No autorizado para modificar este vendedor' USING ERRCODE = '42501';
    END IF;

    SELECT v.uuid, v.id_trabajador, v.id_tpv
    INTO v_uuid, v_worker_id, v_old_tpv_id
    FROM public.app_dat_vendedor v
    WHERE v.id = p_id_vendedor
    FOR UPDATE;

    IF NOT FOUND OR v_uuid IS NULL THEN
        RAISE EXCEPTION 'No autorizado para modificar este vendedor' USING ERRCODE = '42501';
    END IF;

    IF v_worker_id IS NOT NULL THEN
        SELECT w.uuid, w.id_tienda INTO v_worker_uuid, v_worker_store
        FROM public.app_dat_trabajadores w
        WHERE w.id = v_worker_id
        FOR SHARE;
        IF NOT FOUND OR v_worker_store IS NULL
           OR (v_worker_uuid IS NOT NULL AND v_worker_uuid IS DISTINCT FROM v_uuid) THEN
            RAISE EXCEPTION 'No autorizado para modificar este vendedor' USING ERRCODE = '42501';
        END IF;
    END IF;

    IF v_old_tpv_id IS NOT NULL THEN
        SELECT t.id_tienda INTO v_old_tpv_store
        FROM public.app_dat_tpv t WHERE t.id = v_old_tpv_id
        FOR SHARE;
        IF NOT FOUND OR v_old_tpv_store IS NULL THEN
            RAISE EXCEPTION 'No autorizado para modificar este vendedor' USING ERRCODE = '42501';
        END IF;
    END IF;

    IF v_worker_store IS NOT NULL AND v_old_tpv_store IS NOT NULL
       AND v_worker_store IS DISTINCT FROM v_old_tpv_store THEN
        RAISE EXCEPTION 'No autorizado para modificar este vendedor' USING ERRCODE = '42501';
    END IF;

    v_old_store := COALESCE(v_worker_store, v_old_tpv_store);
    IF v_old_store IS NULL OR public.fn_config_tienda_puede_escribir(v_old_store) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'No autorizado para modificar este vendedor' USING ERRCODE = '42501';
    END IF;

    IF p_id_tpv IS NULL THEN
        v_new_store := v_worker_store;
    ELSE
        SELECT t.id_tienda INTO v_new_store
        FROM public.app_dat_tpv t WHERE t.id = p_id_tpv
        FOR SHARE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'No autorizado para modificar este vendedor' USING ERRCODE = '42501';
        END IF;
    END IF;

    IF v_new_store IS NULL
       OR public.fn_config_tienda_puede_escribir(v_new_store) IS DISTINCT FROM true
       OR (v_worker_store IS NOT NULL AND v_worker_store IS DISTINCT FROM v_new_store) THEN
        RAISE EXCEPTION 'No autorizado para modificar este vendedor' USING ERRCODE = '42501';
    END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_m01_personal_exigir_reasignacion_vendedor(bigint, bigint)
    FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
