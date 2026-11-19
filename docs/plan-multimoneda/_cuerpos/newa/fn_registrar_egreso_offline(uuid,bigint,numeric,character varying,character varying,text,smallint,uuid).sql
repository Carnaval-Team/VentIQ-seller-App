CREATE OR REPLACE FUNCTION public.fn_registrar_egreso_offline(p_client_uuid uuid, p_id_turno bigint, p_monto_entrega numeric, p_nombre_recibe character varying, p_nombre_autoriza character varying, p_motivo_entrega text, p_id_medio_pago smallint DEFAULT NULL::smallint, p_uuid_usuario uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_request jsonb;
    v_existing public.app_dat_operacion_offline_idempotencia%ROWTYPE;
    v_store bigint;
    v_result jsonb;
    v_new_id bigint;
BEGIN
    IF v_actor IS NULL OR p_client_uuid IS NULL OR p_id_turno IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_request := jsonb_build_object(
        'version', 1,
        'id_turno', p_id_turno,
        'monto_entrega', p_monto_entrega,
        'nombre_recibe', p_nombre_recibe,
        'nombre_autoriza', p_nombre_autoriza,
        'motivo_entrega', p_motivo_entrega,
        'id_medio_pago', p_id_medio_pago,
        'uuid_usuario', p_uuid_usuario,
        'moneda', 'CUP'
    );
    PERFORM pg_advisory_xact_lock(hashtextextended(p_client_uuid::text, 0));
    SELECT * INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid
    FOR UPDATE;
    IF FOUND THEN
        IF v_existing.tipo IS DISTINCT FROM 'egreso'
           OR v_existing.uuid_usuario IS DISTINCT FROM v_actor
           OR v_existing.m01_solicitud IS DISTINCT FROM v_request
           OR v_existing.m01_id_tienda IS NULL THEN
            RAISE EXCEPTION 'Clave no verificable o solicitud no autorizada; requiere revision'
                USING ERRCODE = '42501';
        END IF;
        IF public.fn_config_tienda_puede_escribir(v_existing.m01_id_tienda) IS DISTINCT FROM true
           AND NOT EXISTS (
                SELECT 1
                FROM public.app_dat_vendedor s
                JOIN public.app_dat_trabajadores w ON w.id = s.id_trabajador
                WHERE s.uuid = v_actor AND w.uuid = v_actor
                  AND w.deleted_at IS NULL
                  AND w.id_tienda = v_existing.m01_id_tienda
           ) THEN
            RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
        END IF;
        RETURN jsonb_build_object(
            'success', true, 'idempotent', true,
            'egreso_id', v_existing.id_operacion,
            'message', 'Egreso ya registrado previamente (idempotente)'
        );
    END IF;

    SELECT t.id_tienda INTO v_store
    FROM public.app_dat_caja_turno ct
    JOIN public.app_dat_tpv t ON t.id = ct.id_tpv
    WHERE ct.id = p_id_turno
    FOR SHARE OF ct;
    IF NOT FOUND OR v_store IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    IF (p_uuid_usuario IS NOT NULL AND p_uuid_usuario IS DISTINCT FROM v_actor
        AND public.fn_config_tienda_puede_escribir(v_store) IS DISTINCT FROM true)
       OR (public.fn_config_tienda_puede_escribir(v_store) IS DISTINCT FROM true
           AND NOT EXISTS (
                SELECT 1
                FROM public.app_dat_vendedor s
                JOIN public.app_dat_trabajadores w ON w.id = s.id_trabajador
                WHERE s.uuid = v_actor AND w.uuid = v_actor
                  AND w.deleted_at IS NULL AND w.id_tienda = v_store
           )) THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    v_result := public.registrar_egreso_parcial_v2(
        p_id_turno := p_id_turno,
        p_monto_entrega := p_monto_entrega,
        p_nombre_recibe := p_nombre_recibe,
        p_nombre_autoriza := p_nombre_autoriza,
        p_motivo_entrega := p_motivo_entrega,
        p_id_medio_pago := p_id_medio_pago
    );
    IF v_result IS NULL OR (v_result->>'success') IS DISTINCT FROM 'true' THEN
        RETURN COALESCE(v_result, jsonb_build_object(
            'success', false, 'message', 'El servidor rechazó el egreso'
        ));
    END IF;
    v_new_id := NULLIF(v_result->>'egreso_id', '')::bigint;
    IF v_new_id IS NULL THEN
        RAISE EXCEPTION 'El servidor rechazó el egreso' USING ERRCODE = '42501';
    END IF;
    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES (p_client_uuid, v_new_id, 'egreso', v_actor, v_request, v_store);
    RETURN v_result || jsonb_build_object('idempotent', false, 'client_uuid', p_client_uuid);
END;
$function$

