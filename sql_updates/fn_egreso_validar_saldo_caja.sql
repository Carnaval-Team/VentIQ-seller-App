-- ============================================================================
-- C14: validar saldo de caja en el RPC de egreso (misma regla que el TPV)
-- ============================================================================
-- ⚠ MAIN FASE 1: NO APLICAR ESTE ARCHIVO COMPLETO.
--   Reemplaza `fn_registrar_egreso_offline_v2` (nombre que usa el cliente
--   publicado) con EGRESO_SIN_SALDO + idempotencia M01 → viola la regla de oro.
--   En Fase 1 el saldo vive solo en `fn_registrar_egreso_offline_v2_m01`
--   (`promocion_m01/04_egreso_m01.sql`). El helper ya está en
--   `01_helpers_alineacion.sql`. Fondo v2 llama a `_v2_m01`.
--   Fase 3 (contrato / flota actualizada):
--   `fn_egreso_validar_saldo_caja_fase3_nombre_antiguo.sql`.
--
-- newa: ya aplicado (2026-11-23). Este archivo queda como referencia/replay.
--
-- Regla (importe nativo, sin conversión entre monedas):
--   * Efectivo: inicial de esa moneda + cobros en efectivo − egresos en
--     efectivo (el medio en efectivo elegido no importa: el cajón es uno).
--   * Digital: cobros de ese medio+moneda − egresos de ese medio+moneda.
--   * Pagos pendientes (medio 998) no cuentan.
--   * Solo operaciones completadas (fn_operacion_completada) y pertenecientes
--     al turno (fn_operacion_en_turno).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_caja_disponible_para_egreso(
    p_id_turno bigint,
    p_moneda text,
    p_id_medio_pago smallint DEFAULT NULL
)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $$
DECLARE
    v_moneda text := upper(btrim(COALESCE(NULLIF(p_moneda, ''), 'CUP')));
    v_es_efectivo boolean;
    v_inicial numeric := 0;
    v_cobros numeric := 0;
    v_egresos numeric := 0;
BEGIN
    IF p_id_turno IS NULL THEN
        RETURN 0;
    END IF;

    IF p_id_medio_pago IS NULL THEN
        v_es_efectivo := true;
    ELSE
        SELECT COALESCE(m.es_efectivo, false)
          INTO v_es_efectivo
        FROM public.app_nom_medio_pago m
        WHERE m.id = p_id_medio_pago;
        IF NOT FOUND THEN
            -- Medio desconocido: tratar como digital del id pedido (disponible 0
            -- salvo cobros/egresos con ese id).
            v_es_efectivo := false;
        END IF;
    END IF;

    IF v_es_efectivo THEN
        SELECT COALESCE(ctm.efectivo_inicial, 0)
          INTO v_inicial
        FROM public.app_dat_caja_turno_moneda ctm
        WHERE ctm.id_turno = p_id_turno
          AND upper(btrim(ctm.moneda::text)) = v_moneda;

        IF NOT FOUND THEN
            SELECT CASE
                WHEN v_moneda = 'CUP' THEN COALESCE(ct.efectivo_inicial, 0)
                WHEN v_moneda = 'USD' THEN COALESCE(ct.efectivo_inicial_usd, 0)
                ELSE 0
            END
              INTO v_inicial
            FROM public.app_dat_caja_turno ct
            WHERE ct.id = p_id_turno;
            v_inicial := COALESCE(v_inicial, 0);
        END IF;
    END IF;

    SELECT COALESCE(SUM(p.monto), 0)
      INTO v_cobros
    FROM public.app_dat_pago_venta p
    JOIN public.app_dat_operaciones o ON o.id = p.id_operacion_venta
    LEFT JOIN public.app_nom_medio_pago m ON m.id = p.id_medio_pago
    WHERE p.id_medio_pago IS DISTINCT FROM 998
      AND upper(btrim(COALESCE(NULLIF(p.moneda::text, ''), 'CUP'))) = v_moneda
      AND public.fn_operacion_completada(o.id)
      AND public.fn_operacion_en_turno(p_id_turno, o.id, o.created_at)
      AND (
          (v_es_efectivo AND COALESCE(m.es_efectivo, false))
          OR (
              NOT v_es_efectivo
              AND p.id_medio_pago IS NOT DISTINCT FROM p_id_medio_pago
              AND NOT COALESCE(m.es_efectivo, false)
          )
      );

    SELECT COALESCE(SUM(e.monto_entrega), 0)
      INTO v_egresos
    FROM public.app_dat_entregas_parciales_caja e
    LEFT JOIN public.app_nom_medio_pago m ON m.id = e.id_medio_pago
    WHERE e.id_turno = p_id_turno
      AND upper(btrim(COALESCE(NULLIF(e.moneda::text, ''), 'CUP'))) = v_moneda
      AND (
          (v_es_efectivo AND COALESCE(m.es_efectivo, e.id_medio_pago IS NULL, false))
          OR (
              NOT v_es_efectivo
              AND e.id_medio_pago IS NOT DISTINCT FROM p_id_medio_pago
              AND NOT COALESCE(m.es_efectivo, false)
          )
      );

    RETURN round(COALESCE(v_inicial, 0) + COALESCE(v_cobros, 0) - COALESCE(v_egresos, 0), 2);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_caja_disponible_para_egreso(bigint, text, smallint)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_caja_disponible_para_egreso(bigint, text, smallint)
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_registrar_egreso_offline_v2(
    p_client_uuid uuid,
    p_id_turno bigint,
    p_monto_entrega numeric,
    p_nombre_recibe character varying,
    p_nombre_autoriza character varying,
    p_motivo_entrega text,
    p_id_medio_pago smallint DEFAULT NULL::smallint,
    p_uuid_usuario uuid DEFAULT NULL::uuid,
    p_moneda text DEFAULT 'CUP'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
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
    -- Serializa egresos del mismo turno para que dos subidas concurrentes
    -- no lean el mismo disponible.
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

    -- C14: misma regla que CajaDisponible del TPV.
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
