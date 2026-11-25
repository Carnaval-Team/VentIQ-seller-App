-- ============================================================================
-- PROMOCION M01 · 03 · Cadena de cierre de turno offline (_m01)
-- ============================================================================
-- Aditivo: crea fn_cerrar_turno_offline_m01 / _usd_m01 / _monedas_m01.
-- Los nombres antiguos (fn_cerrar_turno_offline, _usd, _monedas) NO se tocan.
-- Cuerpos: newa vigente (2026-11-23).
-- Cableado interno: cerrar_monedas_m01 -> cerrar_usd_m01 -> cerrar_m01.
-- Orden: aplicar tras 01 y 02.
-- ============================================================================

DO $preflight$
BEGIN
    IF to_regprocedure('public.fn_config_tienda_puede_escribir(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Falta public.fn_config_tienda_puede_escribir(bigint) en este proyecto';
    END IF;
    IF to_regprocedure('public.fn_jsonb_monto(jsonb,text)') IS NULL THEN
        RAISE EXCEPTION 'Falta public.fn_jsonb_monto(jsonb,text)';
    END IF;
    IF to_regprocedure('public.fn_cerrar_turno_tpv(bigint,numeric,uuid,jsonb,text)') IS NULL THEN
        RAISE EXCEPTION 'Falta public.fn_cerrar_turno_tpv(bigint,numeric,uuid,jsonb,text)';
    END IF;
    IF to_regprocedure('public.fn_esperado_turno_por_moneda(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Falta public.fn_esperado_turno_por_moneda(bigint)';
    END IF;
    IF (SELECT count(*) FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'app_dat_operacion_offline_idempotencia'
          AND column_name IN ('m01_solicitud', 'm01_id_tienda')) < 2 THEN
        RAISE EXCEPTION 'app_dat_operacion_offline_idempotencia sin columnas m01_solicitud / m01_id_tienda';
    END IF;
    IF to_regclass('public.app_dat_caja_turno_moneda') IS NULL THEN
        RAISE EXCEPTION 'Falta app_dat_caja_turno_moneda';
    END IF;
END
$preflight$;

-- ---------------------------------------------------------------------------
-- 1) fn_cerrar_turno_offline_m01  (base)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_cerrar_turno_offline_m01(p_client_uuid uuid, p_id_tpv bigint, p_efectivo_real numeric, p_usuario uuid, p_productos jsonb DEFAULT '[]'::jsonb, p_observaciones text DEFAULT NULL::text, p_fecha_cierre timestamp with time zone DEFAULT NULL::timestamp with time zone)
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
    v_open bigint;
    v_ok boolean;
    v_extra text;
    v_fecha_apertura timestamptz;
BEGIN
    IF v_actor IS NULL OR p_client_uuid IS NULL OR p_id_tpv IS NULL OR p_usuario IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_extra := current_setting('app.m01_caja_extra', true);
    PERFORM set_config('app.m01_caja_extra', '', true);
    v_request := jsonb_build_object(
        'version', 1,
        'id_tpv', p_id_tpv,
        'efectivo_real', p_efectivo_real,
        'usuario', p_usuario,
        'productos', COALESCE(p_productos, '[]'::jsonb),
        'observaciones', p_observaciones,
        'fecha_cierre', p_fecha_cierre,
        'extra', CASE
            WHEN v_extra IS NULL OR btrim(v_extra) = '' THEN '{}'::jsonb
            ELSE v_extra::jsonb
        END
    );
    PERFORM pg_advisory_xact_lock(hashtextextended(p_client_uuid::text, 0));
    SELECT * INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid
    FOR UPDATE;
    IF FOUND THEN
        IF v_existing.tipo IS DISTINCT FROM 'cierre_turno'
           OR v_existing.uuid_usuario IS DISTINCT FROM v_actor
           -- R33: la fecha no entra en la comparación.
           OR (v_existing.m01_solicitud - 'fecha_cierre') IS DISTINCT FROM (v_request - 'fecha_cierre')
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
            'status', 'success', 'idempotent', true,
            'message', 'Cierre ya procesado'
        );
    END IF;

    SELECT t.id_tienda, ct.id
    INTO v_store, v_open
    FROM public.app_dat_tpv t
    LEFT JOIN public.app_dat_caja_turno ct
      ON ct.id_tpv = t.id AND ct.estado = 1 AND ct.creado_por = p_usuario
    WHERE t.id = p_id_tpv
    ORDER BY ct.fecha_apertura DESC NULLS LAST
    LIMIT 1;
    IF v_store IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    IF public.fn_config_tienda_puede_escribir(v_store) IS DISTINCT FROM true
       AND NOT EXISTS (
            SELECT 1
            FROM public.app_dat_vendedor s
            JOIN public.app_dat_trabajadores w ON w.id = s.id_trabajador
            WHERE s.uuid = v_actor AND s.id_tpv = p_id_tpv
              AND w.uuid = v_actor AND w.deleted_at IS NULL
              AND w.id_tienda = v_store
       ) THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    IF v_open IS NULL THEN
        RETURN jsonb_build_object(
            'status', 'success', 'idempotent', true,
            'message', 'No hay turno abierto; nada que cerrar'
        );
    END IF;
    SELECT fecha_apertura INTO v_fecha_apertura
    FROM public.app_dat_caja_turno
    WHERE id = v_open;

    v_ok := public.fn_cerrar_turno_tpv(
        p_id_tpv := p_id_tpv,
        p_efectivo_real := p_efectivo_real,
        p_usuario := p_usuario,
        p_productos := p_productos,
        p_observaciones := p_observaciones
    );
    IF v_ok IS DISTINCT FROM true THEN
        RETURN jsonb_build_object(
            'status', 'error',
            'message', 'El servidor rechazó el cierre del turno'
        );
    END IF;
    IF p_fecha_cierre IS NOT NULL THEN
        -- R33: nunca futura ni anterior a la apertura (antes: sin acotar).
        UPDATE public.app_dat_caja_turno
        SET fecha_cierre = GREATEST(v_fecha_apertura, LEAST(p_fecha_cierre, now()))
        WHERE id = v_open;
    END IF;
    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES (p_client_uuid, v_open, 'cierre_turno', v_actor, v_request, v_store);
    RETURN jsonb_build_object('status', 'success', 'idempotent', false);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_cerrar_turno_offline_m01(uuid, bigint, numeric, uuid, jsonb, text, timestamp with time zone)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_cerrar_turno_offline_m01(uuid, bigint, numeric, uuid, jsonb, text, timestamp with time zone)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2) fn_cerrar_turno_offline_usd_m01  (llama a cerrar_m01)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_cerrar_turno_offline_usd_m01(p_client_uuid uuid, p_id_tpv bigint, p_efectivo_real numeric, p_usuario uuid, p_productos jsonb DEFAULT '[]'::jsonb, p_observaciones text DEFAULT NULL::text, p_fecha_cierre timestamp with time zone DEFAULT NULL::timestamp with time zone, p_efectivo_real_usd numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
    v_result jsonb;
    v_turno_id bigint;
    v_efectivo_esperado_usd numeric := 0;
BEGIN
    IF NULLIF(btrim(COALESCE(current_setting('app.m01_caja_extra', true), '')), '') IS NULL THEN
        PERFORM set_config(
            'app.m01_caja_extra',
            jsonb_build_object('efectivo_usd', p_efectivo_real_usd)::text,
            true
        );
    END IF;
    SELECT id INTO v_turno_id
    FROM public.app_dat_caja_turno
    WHERE id_tpv = p_id_tpv AND estado = 1
    ORDER BY fecha_apertura DESC NULLS LAST
    LIMIT 1;

    v_result := public.fn_cerrar_turno_offline_m01(
        p_client_uuid, p_id_tpv, p_efectivo_real, p_usuario,
        p_productos, p_observaciones, p_fecha_cierre
    );
    IF COALESCE((v_result->>'idempotent')::boolean, false) THEN
        RETURN v_result;
    END IF;

    SELECT COALESCE(SUM(pv.monto), 0) INTO v_efectivo_esperado_usd
    FROM public.app_dat_pago_venta pv
    JOIN public.app_dat_operacion_venta ov ON ov.id_operacion = pv.id_operacion_venta
    JOIN public.app_nom_medio_pago mp ON mp.id = pv.id_medio_pago
    WHERE pv.moneda = 'USD' AND mp.es_efectivo IS TRUE
      AND ov.id_turno_apertura = v_turno_id;

    IF v_turno_id IS NOT NULL AND (v_result->>'status') = 'success' THEN
        UPDATE public.app_dat_caja_turno
        SET efectivo_real_usd = p_efectivo_real_usd,
            diferencia_usd = CASE
                WHEN p_efectivo_real_usd IS NULL THEN NULL
                ELSE p_efectivo_real_usd
                     - (COALESCE(efectivo_inicial_usd, 0) + v_efectivo_esperado_usd)
            END
        WHERE id = v_turno_id;
    END IF;
    RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_cerrar_turno_offline_usd_m01(uuid, bigint, numeric, uuid, jsonb, text, timestamp with time zone, numeric)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_cerrar_turno_offline_usd_m01(uuid, bigint, numeric, uuid, jsonb, text, timestamp with time zone, numeric)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3) fn_cerrar_turno_offline_monedas_m01  (llama a cerrar_usd_m01)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_cerrar_turno_offline_monedas_m01(p_client_uuid uuid, p_id_tpv bigint, p_usuario uuid, p_productos jsonb, p_efectivo_real_por_moneda jsonb, p_observaciones text DEFAULT NULL::text, p_fecha_cierre timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
    v_res jsonb;
    v_turno_id bigint;
    v_cup numeric;
    v_usd numeric;
    v_esperado record;
BEGIN
    IF p_efectivo_real_por_moneda IS NULL
       OR jsonb_typeof(p_efectivo_real_por_moneda) <> 'object' THEN
        RAISE EXCEPTION 'Se esperaba un objeto {"MONEDA": monto} de efectivo real';
    END IF;
    v_cup := COALESCE(public.fn_jsonb_monto(p_efectivo_real_por_moneda, 'CUP'), 0);
    v_usd := COALESCE(public.fn_jsonb_monto(p_efectivo_real_por_moneda, 'USD'), 0);
    PERFORM set_config(
        'app.m01_caja_extra',
        jsonb_build_object(
            'efectivo_por_moneda', p_efectivo_real_por_moneda,
            'efectivo_usd', v_usd
        )::text,
        true
    );
    SELECT ct.id INTO v_turno_id
    FROM public.app_dat_caja_turno ct
    WHERE ct.id_tpv = p_id_tpv AND ct.estado = 1 AND ct.creado_por = p_usuario
    ORDER BY ct.fecha_apertura DESC
    LIMIT 1;
    v_res := public.fn_cerrar_turno_offline_usd_m01(
        p_client_uuid := p_client_uuid,
        p_id_tpv := p_id_tpv,
        p_efectivo_real := v_cup,
        p_usuario := p_usuario,
        p_productos := p_productos,
        p_observaciones := p_observaciones,
        p_fecha_cierre := p_fecha_cierre,
        p_efectivo_real_usd := v_usd
    );
    IF COALESCE((v_res->>'idempotent')::boolean, false) THEN
        RETURN v_res;
    END IF;
    IF (v_res->>'status') = 'success' AND v_turno_id IS NOT NULL THEN
        FOR v_esperado IN
            SELECT moneda, esperado FROM public.fn_esperado_turno_por_moneda(v_turno_id)
        LOOP
            INSERT INTO public.app_dat_caja_turno_moneda
                (id_turno, moneda, efectivo_inicial, efectivo_esperado, efectivo_real)
            VALUES (
                v_turno_id, v_esperado.moneda,
                COALESCE((
                    SELECT m.efectivo_inicial
                    FROM public.app_dat_caja_turno_moneda m
                    WHERE m.id_turno = v_turno_id AND m.moneda = v_esperado.moneda
                ), 0),
                v_esperado.esperado,
                public.fn_jsonb_monto(p_efectivo_real_por_moneda, v_esperado.moneda)
            )
            ON CONFLICT (id_turno, moneda) DO UPDATE
                SET efectivo_esperado = excluded.efectivo_esperado,
                    efectivo_real = COALESCE(
                        excluded.efectivo_real,
                        public.app_dat_caja_turno_moneda.efectivo_real
                    ),
                    updated_at = now();
        END LOOP;
    END IF;
    RETURN v_res;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_cerrar_turno_offline_monedas_m01(uuid, bigint, uuid, jsonb, jsonb, text, timestamp with time zone)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_cerrar_turno_offline_monedas_m01(uuid, bigint, uuid, jsonb, jsonb, text, timestamp with time zone)
  TO authenticated, service_role;
