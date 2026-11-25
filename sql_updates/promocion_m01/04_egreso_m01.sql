-- ============================================================================
-- PROMOCION M01 · 04 · Egreso de caja offline (_m01)
-- ============================================================================
-- Aditivo: crea fn_registrar_egreso_offline_m01 y fn_registrar_egreso_offline_v2_m01.
-- Los nombres antiguos NO se tocan.
-- Cuerpos: newa vigente (2026-11-23).
--   * v2 vigente en newa NO envuelve a la v1: llama directo a
--     registrar_egreso_parcial_v2, por eso no hay cableado v2_m01 -> v1_m01.
--   * v2_m01 incluye C14: fn_caja_disponible_para_egreso + EGRESO_SIN_SALDO
--     (requiere 01_helpers_alineacion.sql).
-- ============================================================================

DO $preflight$
BEGIN
    IF to_regprocedure('public.fn_caja_disponible_para_egreso(bigint,text,smallint)') IS NULL THEN
        RAISE EXCEPTION 'Falta fn_caja_disponible_para_egreso: aplicar 01_helpers_alineacion.sql';
    END IF;
    IF to_regprocedure('public.fn_operacion_completada(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Falta public.fn_operacion_completada(bigint) (usada por fn_caja_disponible_para_egreso)';
    END IF;
    IF to_regprocedure('public.fn_operacion_en_turno(bigint,bigint,timestamp with time zone)') IS NULL THEN
        RAISE EXCEPTION 'Falta public.fn_operacion_en_turno(bigint,bigint,timestamptz)';
    END IF;
    IF to_regprocedure('public.fn_config_tienda_puede_escribir(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Falta public.fn_config_tienda_puede_escribir(bigint) en este proyecto';
    END IF;
    IF to_regprocedure('public.registrar_egreso_parcial_v2(bigint,numeric,character varying,character varying,text,smallint)') IS NULL THEN
        RAISE EXCEPTION 'Falta public.registrar_egreso_parcial_v2';
    END IF;
    IF (SELECT count(*) FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'app_dat_operacion_offline_idempotencia'
          AND column_name IN ('m01_solicitud', 'm01_id_tienda')) < 2 THEN
        RAISE EXCEPTION 'app_dat_operacion_offline_idempotencia sin columnas m01_solicitud / m01_id_tienda';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'app_dat_entregas_parciales_caja'
          AND column_name = 'moneda'
    ) THEN
        RAISE EXCEPTION 'app_dat_entregas_parciales_caja sin columna moneda';
    END IF;
END
$preflight$;

-- ---------------------------------------------------------------------------
-- 1) fn_registrar_egreso_offline_m01
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_registrar_egreso_offline_m01(p_client_uuid uuid, p_id_turno bigint, p_monto_entrega numeric, p_nombre_recibe character varying, p_nombre_autoriza character varying, p_motivo_entrega text, p_id_medio_pago smallint DEFAULT NULL::smallint, p_uuid_usuario uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
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
$function$;

REVOKE ALL ON FUNCTION public.fn_registrar_egreso_offline_m01(uuid, bigint, numeric, character varying, character varying, text, smallint, uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_registrar_egreso_offline_m01(uuid, bigint, numeric, character varying, character varying, text, smallint, uuid)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2) fn_registrar_egreso_offline_v2_m01  (C14: EGRESO_SIN_SALDO)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_registrar_egreso_offline_v2_m01(p_client_uuid uuid, p_id_turno bigint, p_monto_entrega numeric, p_nombre_recibe character varying, p_nombre_autoriza character varying, p_motivo_entrega text, p_id_medio_pago smallint DEFAULT NULL::smallint, p_uuid_usuario uuid DEFAULT NULL::uuid, p_moneda text DEFAULT 'CUP'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_moneda text := upper(btrim(COALESCE(NULLIF(p_moneda, ''), 'CUP')));
    v_request jsonb;
    v_existing public.app_dat_operacion_offline_idempotencia%ROWTYPE;
    v_store bigint;
    v_result jsonb;
    v_new_id bigint;
    v_disponible numeric;
    v_es_efectivo boolean;
    v_donde text;
BEGIN
    IF v_actor IS NULL OR p_client_uuid IS NULL OR p_id_turno IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    IF p_monto_entrega IS NULL OR p_monto_entrega <= 0 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error_code', 'EGRESO_MONTO_INVALIDO',
            'message', 'El monto del egreso debe ser mayor que cero'
        );
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.monedas m WHERE m.codigo = v_moneda AND m.activo
    ) THEN
        RAISE EXCEPTION 'La moneda % no existe o no está activa en el catálogo', v_moneda;
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
        'moneda', v_moneda
    );
    PERFORM pg_advisory_xact_lock(hashtextextended(p_client_uuid::text, 0));
    PERFORM pg_advisory_xact_lock(
        hashtextextended('egreso-saldo:' || p_id_turno::text, 0)
    );

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
        RETURN jsonb_build_object(
            'success', true, 'idempotent', true,
            'egreso_id', v_existing.id_operacion,
            'message', 'Egreso ya registrado previamente (idempotente)'
        );
    END IF;

    SELECT t.id_tienda INTO v_store
    FROM public.app_dat_caja_turno ct
    JOIN public.app_dat_tpv t ON t.id = ct.id_tpv
    WHERE ct.id = p_id_turno;
    IF NOT FOUND OR v_store IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    v_disponible := public.fn_caja_disponible_para_egreso(
        p_id_turno, v_moneda, p_id_medio_pago
    );
    IF round(p_monto_entrega, 2) > COALESCE(v_disponible, 0) THEN
        IF p_id_medio_pago IS NULL THEN
            v_es_efectivo := true;
        ELSE
            SELECT COALESCE(m.es_efectivo, false)
              INTO v_es_efectivo
            FROM public.app_nom_medio_pago m
            WHERE m.id = p_id_medio_pago;
            IF NOT FOUND THEN
                v_es_efectivo := false;
            END IF;
        END IF;
        IF v_es_efectivo THEN
            v_donde := 'en efectivo';
        ELSE
            SELECT COALESCE(m.denominacion, 'este medio')
              INTO v_donde
            FROM public.app_nom_medio_pago m
            WHERE m.id = p_id_medio_pago;
            v_donde := 'en ' || COALESCE(v_donde, 'este medio');
        END IF;
        RETURN jsonb_build_object(
            'success', false,
            'error_code', 'EGRESO_SIN_SALDO',
            'disponible', COALESCE(v_disponible, 0),
            'moneda', v_moneda,
            'message', format(
                'No hay dinero suficiente: disponible %s %s %s',
                to_char(COALESCE(v_disponible, 0), 'FM999999990.00'),
                v_moneda,
                v_donde
            )
        );
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
    UPDATE public.app_dat_entregas_parciales_caja
    SET moneda = v_moneda
    WHERE id = v_new_id;
    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES (p_client_uuid, v_new_id, 'egreso', v_actor, v_request, v_store);
    RETURN v_result || jsonb_build_object('idempotent', false, 'client_uuid', p_client_uuid);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_registrar_egreso_offline_v2_m01(uuid, bigint, numeric, character varying, character varying, text, smallint, uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_registrar_egreso_offline_v2_m01(uuid, bigint, numeric, character varying, character varying, text, smallint, uuid, text)
  TO authenticated, service_role;
