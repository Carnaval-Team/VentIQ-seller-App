BEGIN;

-- BORRADOR M01-R0i anotaciones de turno y venta. NO EJECUTAR.
-- Crea funciones nuevas. No reemplaza cuerpos existentes.
-- El actor es auth.uid(). El replay no vuelve a escribir.
-- No crea columnas.

SET LOCAL app.m01_r0i_anotaciones_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r0i_anotaciones_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador R0i-anotaciones: NO EJECUTAR sin revision del conjunto M01 en newa';
    END IF;
    IF has_schema_privilege('anon', 'public', 'CREATE')
       OR has_schema_privilege('authenticated', 'public', 'CREATE') THEN
        RAISE EXCEPTION 'public permite CREATE a roles no confiables';
    END IF;
    IF to_regprocedure('public.fn_config_tienda_puede_escribir(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Falta el predicado S01';
    END IF;
    IF to_regprocedure('public.fn_m01_marcar_cierre_solicitado(uuid,bigint,timestamptz)') IS NOT NULL
       OR to_regprocedure('public.fn_m01_limpiar_marcador_cierre(uuid,bigint)') IS NOT NULL
       OR to_regprocedure('public.fn_m01_marcar_venta_cxc(uuid,bigint,bigint)') IS NOT NULL
       OR to_regprocedure('public.fn_m01_adjuntar_foto_operacion(uuid,bigint,text)') IS NOT NULL
       OR to_regprocedure('public.fn_m01_actualizar_cliente_venta(uuid,bigint,text,text,boolean)') IS NOT NULL THEN
        RAISE EXCEPTION 'Una funcion de anotacion ya existe';
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
        RAISE EXCEPTION 'Falta la evidencia compartida de idempotencia';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_class
        WHERE oid = 'public.app_dat_operacion_offline_idempotencia'::regclass
          AND NOT relrowsecurity
    ) OR has_any_column_privilege(
        'authenticated', 'public.app_dat_operacion_offline_idempotencia', 'INSERT'
    ) THEN
        RAISE EXCEPTION 'Falta el aislamiento M01 de idempotencia';
    END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.fn_m01_puede_operar_tienda(p_store bigint, p_tpv bigint)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
    SELECT public.fn_config_tienda_puede_escribir(p_store) IS TRUE
        OR EXISTS (
            SELECT 1
            FROM public.app_dat_vendedor s
            JOIN public.app_dat_trabajadores w ON w.id = s.id_trabajador
            WHERE s.uuid = auth.uid()
              AND w.uuid = auth.uid()
              AND w.deleted_at IS NULL
              AND w.id_tienda = p_store
              AND (p_tpv IS NULL OR s.id_tpv = p_tpv)
        );
$function$;

CREATE OR REPLACE FUNCTION public.fn_m01_marcar_cierre_solicitado(
    p_client_uuid uuid,
    p_id_turno bigint,
    p_fecha timestamptz
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
    v_tpv bigint;
    v_estado integer;
BEGIN
    IF v_actor IS NULL OR p_client_uuid IS NULL OR p_id_turno IS NULL OR p_fecha IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_request := jsonb_build_object(
        'version', 1, 'id_turno', p_id_turno, 'fecha', p_fecha
    );
    PERFORM pg_advisory_xact_lock(hashtextextended(p_client_uuid::text, 0));
    SELECT * INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid
    FOR UPDATE;
    IF FOUND THEN
        IF v_existing.tipo IS DISTINCT FROM 'cierre_solicitado'
           OR v_existing.uuid_usuario IS DISTINCT FROM v_actor
           OR v_existing.m01_solicitud IS DISTINCT FROM v_request
           OR v_existing.m01_id_tienda IS NULL
           OR v_existing.id_operacion IS DISTINCT FROM p_id_turno THEN
            RAISE EXCEPTION 'Clave no verificable o solicitud no autorizada; requiere revision'
                USING ERRCODE = '42501';
        END IF;
        RETURN jsonb_build_object('success', true, 'idempotent', true);
    END IF;
    SELECT t.id_tienda, ct.id_tpv, ct.estado
    INTO v_store, v_tpv, v_estado
    FROM public.app_dat_caja_turno ct
    JOIN public.app_dat_tpv t ON t.id = ct.id_tpv
    WHERE ct.id = p_id_turno
    FOR UPDATE OF ct;
    IF NOT FOUND OR v_store IS NULL OR v_estado IS DISTINCT FROM 1 THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    IF public.fn_m01_puede_operar_tienda(v_store, v_tpv) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    UPDATE public.app_dat_caja_turno
    SET cierre_solicitado_at = p_fecha
    WHERE id = p_id_turno AND estado = 1 AND cierre_solicitado_at IS NULL;
    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES (p_client_uuid, p_id_turno, 'cierre_solicitado', v_actor, v_request, v_store);
    RETURN jsonb_build_object('success', true, 'idempotent', false);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_m01_limpiar_marcador_cierre(
    p_client_uuid uuid,
    p_id_turno bigint
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
    v_tpv bigint;
    v_estado integer;
BEGIN
    IF v_actor IS NULL OR p_client_uuid IS NULL OR p_id_turno IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_request := jsonb_build_object('version', 1, 'id_turno', p_id_turno);
    PERFORM pg_advisory_xact_lock(hashtextextended(p_client_uuid::text, 0));
    SELECT * INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid
    FOR UPDATE;
    IF FOUND THEN
        IF v_existing.tipo IS DISTINCT FROM 'limpiar_cierre'
           OR v_existing.uuid_usuario IS DISTINCT FROM v_actor
           OR v_existing.m01_solicitud IS DISTINCT FROM v_request
           OR v_existing.m01_id_tienda IS NULL
           OR v_existing.id_operacion IS DISTINCT FROM p_id_turno THEN
            RAISE EXCEPTION 'Clave no verificable o solicitud no autorizada; requiere revision'
                USING ERRCODE = '42501';
        END IF;
        RETURN jsonb_build_object('success', true, 'idempotent', true);
    END IF;
    SELECT t.id_tienda, ct.id_tpv, ct.estado
    INTO v_store, v_tpv, v_estado
    FROM public.app_dat_caja_turno ct
    JOIN public.app_dat_tpv t ON t.id = ct.id_tpv
    WHERE ct.id = p_id_turno
    FOR UPDATE OF ct;
    IF NOT FOUND OR v_store IS NULL OR v_estado IS DISTINCT FROM 1 THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    IF public.fn_m01_puede_operar_tienda(v_store, v_tpv) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    UPDATE public.app_dat_caja_turno
    SET fecha_cierre = NULL, cierre_solicitado_at = NULL
    WHERE id = p_id_turno AND estado = 1;
    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES (p_client_uuid, p_id_turno, 'limpiar_cierre', v_actor, v_request, v_store);
    RETURN jsonb_build_object('success', true, 'idempotent', false);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_m01_marcar_venta_cxc(
    p_client_uuid uuid,
    p_id_operacion bigint,
    p_id_cliente_cxc bigint
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
    v_tpv bigint;
BEGIN
    IF v_actor IS NULL OR p_client_uuid IS NULL OR p_id_operacion IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_request := jsonb_build_object(
        'version', 1, 'id_operacion', p_id_operacion, 'id_cliente_cxc', p_id_cliente_cxc
    );
    PERFORM pg_advisory_xact_lock(hashtextextended(p_client_uuid::text, 0));
    SELECT * INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid
    FOR UPDATE;
    IF FOUND THEN
        IF v_existing.tipo IS DISTINCT FROM 'venta_cxc'
           OR v_existing.uuid_usuario IS DISTINCT FROM v_actor
           OR v_existing.m01_solicitud IS DISTINCT FROM v_request
           OR v_existing.m01_id_tienda IS NULL
           OR v_existing.id_operacion IS DISTINCT FROM p_id_operacion THEN
            RAISE EXCEPTION 'Clave no verificable o solicitud no autorizada; requiere revision'
                USING ERRCODE = '42501';
        END IF;
        RETURN jsonb_build_object('success', true, 'idempotent', true);
    END IF;
    SELECT o.id_tienda, ov.id_tpv
    INTO v_store, v_tpv
    FROM public.app_dat_operaciones o
    JOIN public.app_dat_operacion_venta ov ON ov.id_operacion = o.id
    WHERE o.id = p_id_operacion
    FOR UPDATE OF ov;
    IF NOT FOUND OR v_store IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    IF public.fn_m01_puede_operar_tienda(v_store, v_tpv) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    UPDATE public.app_dat_operacion_venta
    SET es_pagada = false,
        id_cliente_cxc = COALESCE(p_id_cliente_cxc, id_cliente_cxc)
    WHERE id_operacion = p_id_operacion;
    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES (p_client_uuid, p_id_operacion, 'venta_cxc', v_actor, v_request, v_store);
    RETURN jsonb_build_object('success', true, 'idempotent', false);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_m01_adjuntar_foto_operacion(
    p_client_uuid uuid,
    p_id_operacion bigint,
    p_url text
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
    v_tpv bigint;
BEGIN
    IF v_actor IS NULL OR p_client_uuid IS NULL OR p_id_operacion IS NULL
       OR p_url IS NULL OR btrim(p_url) = '' OR length(p_url) > 2000 THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_request := jsonb_build_object(
        'version', 1, 'id_operacion', p_id_operacion, 'url', p_url
    );
    PERFORM pg_advisory_xact_lock(hashtextextended(p_client_uuid::text, 0));
    SELECT * INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid
    FOR UPDATE;
    IF FOUND THEN
        IF v_existing.tipo IS DISTINCT FROM 'foto_operacion'
           OR v_existing.uuid_usuario IS DISTINCT FROM v_actor
           OR v_existing.m01_solicitud IS DISTINCT FROM v_request
           OR v_existing.m01_id_tienda IS NULL
           OR v_existing.id_operacion IS DISTINCT FROM p_id_operacion THEN
            RAISE EXCEPTION 'Clave no verificable o solicitud no autorizada; requiere revision'
                USING ERRCODE = '42501';
        END IF;
        RETURN jsonb_build_object('success', true, 'idempotent', true);
    END IF;
    SELECT o.id_tienda, ov.id_tpv
    INTO v_store, v_tpv
    FROM public.app_dat_operaciones o
    JOIN public.app_dat_operacion_venta ov ON ov.id_operacion = o.id
    WHERE o.id = p_id_operacion
    FOR UPDATE OF ov;
    IF NOT FOUND OR v_store IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    IF public.fn_m01_puede_operar_tienda(v_store, v_tpv) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    UPDATE public.app_dat_operacion_venta
    SET foto_operacion_url = p_url
    WHERE id_operacion = p_id_operacion;
    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES (p_client_uuid, p_id_operacion, 'foto_operacion', v_actor, v_request, v_store);
    RETURN jsonb_build_object('success', true, 'idempotent', false);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_m01_actualizar_cliente_venta(
    p_client_uuid uuid,
    p_id_operacion bigint,
    p_nombre text,
    p_telefono text,
    p_actualizar_telefono boolean
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
    v_tpv bigint;
    v_cliente bigint;
    v_cxc bigint;
BEGIN
    IF v_actor IS NULL OR p_client_uuid IS NULL OR p_id_operacion IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_request := jsonb_build_object(
        'version', 1,
        'id_operacion', p_id_operacion,
        'nombre', p_nombre,
        'telefono', p_telefono,
        'actualizar_telefono', p_actualizar_telefono
    );
    PERFORM pg_advisory_xact_lock(hashtextextended(p_client_uuid::text, 0));
    SELECT * INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid
    FOR UPDATE;
    IF FOUND THEN
        IF v_existing.tipo IS DISTINCT FROM 'cliente_venta'
           OR v_existing.uuid_usuario IS DISTINCT FROM v_actor
           OR v_existing.m01_solicitud IS DISTINCT FROM v_request
           OR v_existing.m01_id_tienda IS NULL
           OR v_existing.id_operacion IS DISTINCT FROM p_id_operacion THEN
            RAISE EXCEPTION 'Clave no verificable o solicitud no autorizada; requiere revision'
                USING ERRCODE = '42501';
        END IF;
        RETURN jsonb_build_object('success', true, 'idempotent', true);
    END IF;
    SELECT o.id_tienda, ov.id_tpv, ov.id_cliente, ov.id_cliente_cxc
    INTO v_store, v_tpv, v_cliente, v_cxc
    FROM public.app_dat_operaciones o
    JOIN public.app_dat_operacion_venta ov ON ov.id_operacion = o.id
    WHERE o.id = p_id_operacion;
    IF NOT FOUND OR v_store IS NULL OR v_cliente IS NULL OR v_cxc IS NOT NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    IF public.fn_m01_puede_operar_tienda(v_store, v_tpv) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    UPDATE public.app_dat_clientes
    SET nombre_completo = CASE
            WHEN p_nombre IS NULL OR btrim(p_nombre) = '' THEN nombre_completo
            ELSE btrim(p_nombre)
        END,
        telefono = CASE
            WHEN p_actualizar_telefono IS TRUE THEN NULLIF(btrim(p_telefono), '')
            ELSE telefono
        END
    WHERE id = v_cliente;
    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES (p_client_uuid, p_id_operacion, 'cliente_venta', v_actor, v_request, v_store);
    RETURN jsonb_build_object('success', true, 'idempotent', false);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_m01_puede_operar_tienda(bigint,bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_puede_operar_tienda(bigint,bigint) TO authenticated;
REVOKE ALL ON FUNCTION public.fn_m01_marcar_cierre_solicitado(uuid,bigint,timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_marcar_cierre_solicitado(uuid,bigint,timestamptz) TO authenticated;
REVOKE ALL ON FUNCTION public.fn_m01_limpiar_marcador_cierre(uuid,bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_limpiar_marcador_cierre(uuid,bigint) TO authenticated;
REVOKE ALL ON FUNCTION public.fn_m01_marcar_venta_cxc(uuid,bigint,bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_marcar_venta_cxc(uuid,bigint,bigint) TO authenticated;
REVOKE ALL ON FUNCTION public.fn_m01_adjuntar_foto_operacion(uuid,bigint,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_adjuntar_foto_operacion(uuid,bigint,text) TO authenticated;
REVOKE ALL ON FUNCTION public.fn_m01_actualizar_cliente_venta(uuid,bigint,text,text,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_actualizar_cliente_venta(uuid,bigint,text,text,boolean) TO authenticated;

COMMIT;
