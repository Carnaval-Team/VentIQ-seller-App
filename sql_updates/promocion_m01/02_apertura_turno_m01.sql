-- ============================================================================
-- PROMOCION M01 · 02 · Cadena de apertura de turno offline (_m01)
-- ============================================================================
-- Aditivo: crea fn_apertura_turno_offline_m01 / _usd_m01 / _monedas_m01.
-- Los nombres antiguos (fn_apertura_turno_offline, _usd, _monedas) NO se tocan.
-- Cuerpos: newa vigente (2026-11-23), con H1 (id_turno en la respuesta idempotente
-- y resolución de claves antiguas que guardaron id_operacion).
-- Cableado interno: monedas_m01 -> usd_m01 -> apertura_m01.
-- Orden: aplicar DESPUÉS de 01_helpers_alineacion.sql.
-- Las _m01 usan CREATE OR REPLACE sobre su propio nombre para que el script sea
-- repetible; nunca reemplazan un nombre antiguo.
-- ============================================================================

-- Preflight: dependencias que main debe tener antes de crear las _m01.
DO $preflight$
BEGIN
    IF to_regprocedure('public.fn_turno_alinear_fecha_apertura(bigint,timestamp with time zone)') IS NULL THEN
        RAISE EXCEPTION 'Falta fn_turno_alinear_fecha_apertura: aplicar 01_helpers_alineacion.sql';
    END IF;
    IF to_regprocedure('public.fn_config_tienda_puede_escribir(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Falta public.fn_config_tienda_puede_escribir(bigint) en este proyecto';
    END IF;
    IF to_regprocedure('public.fn_jsonb_monto(jsonb,text)') IS NULL THEN
        RAISE EXCEPTION 'Falta public.fn_jsonb_monto(jsonb,text)';
    END IF;
    IF to_regprocedure('public.registrar_apertura_turno_v3(numeric,bigint,bigint,uuid,boolean,jsonb,text)') IS NULL THEN
        RAISE EXCEPTION 'Falta public.registrar_apertura_turno_v3';
    END IF;
    IF (SELECT count(*) FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'app_dat_operacion_offline_idempotencia'
          AND column_name IN ('m01_solicitud', 'm01_id_tienda')) < 2 THEN
        RAISE EXCEPTION 'app_dat_operacion_offline_idempotencia sin columnas m01_solicitud / m01_id_tienda';
    END IF;
    IF to_regclass('public.app_dat_caja_turno_moneda') IS NULL
       OR to_regclass('public.monedas') IS NULL THEN
        RAISE EXCEPTION 'Faltan app_dat_caja_turno_moneda / monedas';
    END IF;
END
$preflight$;

-- ---------------------------------------------------------------------------
-- 1) fn_apertura_turno_offline_m01  (base)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_apertura_turno_offline_m01(p_client_uuid uuid, p_efectivo_inicial numeric, p_id_tpv bigint, p_id_vendedor bigint, p_usuario uuid, p_maneja_inventario boolean DEFAULT false, p_productos jsonb DEFAULT '[]'::jsonb, p_observaciones text DEFAULT NULL::text, p_fecha_apertura timestamp with time zone DEFAULT NULL::timestamp with time zone)
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
    v_new_op bigint;
    v_new_id bigint;
    v_turno_resuelto bigint;
    v_allowed boolean;
    v_extra text;
BEGIN
    IF v_actor IS NULL OR p_client_uuid IS NULL
       OR p_id_tpv IS NULL OR p_id_vendedor IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_extra := current_setting('app.m01_caja_extra', true);
    PERFORM set_config('app.m01_caja_extra', '', true);
    v_request := jsonb_build_object(
        'version', 1,
        'efectivo_inicial', p_efectivo_inicial,
        'id_tpv', p_id_tpv,
        'id_vendedor', p_id_vendedor,
        'usuario', p_usuario,
        'maneja_inventario', p_maneja_inventario,
        'productos', COALESCE(p_productos, '[]'::jsonb),
        'observaciones', p_observaciones,
        'fecha_apertura', p_fecha_apertura,
        'extra', CASE
            WHEN v_extra IS NULL OR btrim(v_extra) = '' THEN '{}'::jsonb
            ELSE v_extra::jsonb
        END
    );
    PERFORM pg_advisory_xact_lock(hashtextextended(p_client_uuid::text, 0));
    -- R33: dos claves distintas del mismo TPV + vendedor se serializan.
    PERFORM pg_advisory_xact_lock(
        hashtextextended(format('apertura_turno:%s:%s', p_id_tpv, p_id_vendedor), 0)
    );
    SELECT * INTO v_existing
    FROM public.app_dat_operacion_offline_idempotencia
    WHERE client_uuid = p_client_uuid
    FOR UPDATE;
    IF FOUND THEN
        IF v_existing.tipo IS DISTINCT FROM 'apertura_turno'
           OR v_existing.uuid_usuario IS DISTINCT FROM v_actor
           -- R33: la fecha no entra en la comparación (ver cabecera, punto 6).
           OR (v_existing.m01_solicitud - 'fecha_apertura') IS DISTINCT FROM (v_request - 'fecha_apertura')
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
        -- id_operacion guarda el id del turno; las claves anteriores a este fix
        -- pudieron guardar el id de la operación de apertura. Se resuelve el
        -- turno del mismo TPV + vendedor que ya pasó la comparación de huella.
        SELECT ct.id INTO v_turno_resuelto
        FROM public.app_dat_caja_turno ct
        WHERE (ct.id = v_existing.id_operacion
               OR ct.id_operacion_apertura = v_existing.id_operacion)
          AND ct.id_tpv = p_id_tpv
          AND ct.id_vendedor = p_id_vendedor
        ORDER BY (ct.id = v_existing.id_operacion) DESC, ct.id DESC
        LIMIT 1;
        v_turno_resuelto := COALESCE(v_turno_resuelto, v_existing.id_operacion);
        -- R33: si el turno sigue abierto, recuperar la apertura real.
        PERFORM public.fn_turno_alinear_fecha_apertura(v_turno_resuelto, p_fecha_apertura);
        RETURN jsonb_build_object(
            'status', 'success', 'idempotent', true,
            'id_turno', v_turno_resuelto,
            'message', 'Apertura ya procesada'
        );
    END IF;

    SELECT t.id_tienda INTO v_store
    FROM public.app_dat_tpv t
    WHERE t.id = p_id_tpv
    FOR SHARE;
    IF NOT FOUND OR v_store IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    v_allowed := public.fn_config_tienda_puede_escribir(v_store) IS TRUE
        OR EXISTS (
            SELECT 1
            FROM public.app_dat_vendedor s
            JOIN public.app_dat_trabajadores w ON w.id = s.id_trabajador
            WHERE s.uuid = v_actor AND s.id_tpv = p_id_tpv
              AND w.uuid = v_actor AND w.deleted_at IS NULL
              AND w.id_tienda = v_store
        );
    IF v_allowed IS DISTINCT FROM true
       OR (p_usuario IS NOT NULL AND p_usuario IS DISTINCT FROM v_actor
           AND public.fn_config_tienda_puede_escribir(v_store) IS DISTINCT FROM true) THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    SELECT id INTO v_open
    FROM public.app_dat_caja_turno
    WHERE id_tpv = p_id_tpv AND id_vendedor = p_id_vendedor AND estado = 1
    ORDER BY fecha_apertura DESC NULLS LAST
    LIMIT 1;
    IF v_open IS NOT NULL THEN
        INSERT INTO public.app_dat_operacion_offline_idempotencia
            (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
        VALUES (p_client_uuid, v_open, 'apertura_turno', v_actor, v_request, v_store);
        -- R33: antes se reutilizaba sin fecha → apertura = hora del sync.
        PERFORM public.fn_turno_alinear_fecha_apertura(v_open, p_fecha_apertura);
        RETURN jsonb_build_object(
            'status', 'success', 'idempotent', false,
            'id_turno', v_open,
            'message', 'Turno ya estaba abierto; reutilizado'
        );
    END IF;

    -- registrar_apertura_turno_v3 devuelve el id de la OPERACIÓN de apertura.
    v_new_op := public.registrar_apertura_turno_v3(
        p_efectivo_inicial := p_efectivo_inicial,
        p_id_tpv := p_id_tpv,
        p_id_vendedor := p_id_vendedor,
        p_usuario := COALESCE(p_usuario, v_actor),
        p_maneja_inventario := COALESCE(p_maneja_inventario, false),
        p_productos := p_productos,
        p_observaciones := p_observaciones
    );
    IF v_new_op IS NULL THEN
        RAISE EXCEPTION 'El servidor rechazó la apertura' USING ERRCODE = '42501';
    END IF;
    SELECT ct.id INTO v_new_id
    FROM public.app_dat_caja_turno ct
    WHERE ct.id_operacion_apertura = v_new_op;
    IF v_new_id IS NULL THEN
        RAISE EXCEPTION 'No se encontró el turno de la apertura %', v_new_op;
    END IF;
    -- R33: mismos límites que al reutilizar (antes: UPDATE sin acotar).
    PERFORM public.fn_turno_alinear_fecha_apertura(v_new_id, p_fecha_apertura);
    INSERT INTO public.app_dat_operacion_offline_idempotencia
        (client_uuid, id_operacion, tipo, uuid_usuario, m01_solicitud, m01_id_tienda)
    VALUES (p_client_uuid, v_new_id, 'apertura_turno', v_actor, v_request, v_store);
    RETURN jsonb_build_object(
        'status', 'success', 'id_turno', v_new_id,
        'id_operacion', v_new_op, 'idempotent', false
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_apertura_turno_offline_m01(uuid, numeric, bigint, bigint, uuid, boolean, jsonb, text, timestamp with time zone)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_apertura_turno_offline_m01(uuid, numeric, bigint, bigint, uuid, boolean, jsonb, text, timestamp with time zone)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2) fn_apertura_turno_offline_usd_m01  (llama a apertura_m01)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_apertura_turno_offline_usd_m01(p_client_uuid uuid, p_efectivo_inicial numeric, p_id_tpv bigint, p_id_vendedor bigint, p_usuario uuid, p_maneja_inventario boolean DEFAULT false, p_productos jsonb DEFAULT '[]'::jsonb, p_observaciones text DEFAULT NULL::text, p_fecha_apertura timestamp with time zone DEFAULT NULL::timestamp with time zone, p_efectivo_inicial_usd numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
    v_result jsonb;
    v_turno_id bigint;
BEGIN
    IF NULLIF(btrim(COALESCE(current_setting('app.m01_caja_extra', true), '')), '') IS NULL THEN
        PERFORM set_config(
            'app.m01_caja_extra',
            jsonb_build_object('efectivo_usd', p_efectivo_inicial_usd)::text,
            true
        );
    END IF;
    v_result := public.fn_apertura_turno_offline_m01(
        p_client_uuid, p_efectivo_inicial, p_id_tpv, p_id_vendedor, p_usuario,
        p_maneja_inventario, p_productos, p_observaciones, p_fecha_apertura
    );
    IF COALESCE((v_result->>'idempotent')::boolean, false) THEN
        RETURN v_result;
    END IF;
    v_turno_id := NULLIF(v_result->>'id_turno', '')::bigint;
    IF v_turno_id IS NOT NULL THEN
        UPDATE public.app_dat_caja_turno
        SET efectivo_inicial_usd = COALESCE(p_efectivo_inicial_usd, 0)
        WHERE id = v_turno_id;
    END IF;
    RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_apertura_turno_offline_usd_m01(uuid, numeric, bigint, bigint, uuid, boolean, jsonb, text, timestamp with time zone, numeric)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_apertura_turno_offline_usd_m01(uuid, numeric, bigint, bigint, uuid, boolean, jsonb, text, timestamp with time zone, numeric)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3) fn_apertura_turno_offline_monedas_m01  (llama a usd_m01)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_apertura_turno_offline_monedas_m01(p_client_uuid uuid, p_id_tpv bigint, p_id_vendedor bigint, p_usuario uuid, p_maneja_inventario boolean, p_productos jsonb, p_efectivo_inicial_por_moneda jsonb, p_observaciones text DEFAULT NULL::text, p_fecha_apertura timestamp with time zone DEFAULT NULL::timestamp with time zone)
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
BEGIN
    IF p_efectivo_inicial_por_moneda IS NULL
       OR jsonb_typeof(p_efectivo_inicial_por_moneda) <> 'object' THEN
        RAISE EXCEPTION 'Se esperaba un objeto {"MONEDA": monto} de efectivo inicial';
    END IF;
    v_cup := COALESCE(public.fn_jsonb_monto(p_efectivo_inicial_por_moneda, 'CUP'), 0);
    v_usd := COALESCE(public.fn_jsonb_monto(p_efectivo_inicial_por_moneda, 'USD'), 0);
    PERFORM set_config(
        'app.m01_caja_extra',
        jsonb_build_object(
            'efectivo_por_moneda', p_efectivo_inicial_por_moneda,
            'efectivo_usd', v_usd
        )::text,
        true
    );
    v_res := public.fn_apertura_turno_offline_usd_m01(
        p_client_uuid := p_client_uuid,
        p_efectivo_inicial := v_cup,
        p_id_tpv := p_id_tpv,
        p_id_vendedor := p_id_vendedor,
        p_usuario := p_usuario,
        p_maneja_inventario := p_maneja_inventario,
        p_productos := p_productos,
        p_observaciones := p_observaciones,
        p_fecha_apertura := p_fecha_apertura,
        p_efectivo_inicial_usd := v_usd
    );
    IF COALESCE((v_res->>'idempotent')::boolean, false) THEN
        RETURN v_res;
    END IF;
    IF (v_res->>'status') = 'success' THEN
        v_turno_id := NULLIF(v_res->>'id_turno', '')::bigint;
        IF v_turno_id IS NOT NULL THEN
            INSERT INTO public.app_dat_caja_turno_moneda (id_turno, moneda, efectivo_inicial)
            SELECT v_turno_id, upper(btrim(e.key)),
                   public.fn_jsonb_monto(p_efectivo_inicial_por_moneda, e.key)
            FROM jsonb_each(p_efectivo_inicial_por_moneda) e
            WHERE public.fn_jsonb_monto(p_efectivo_inicial_por_moneda, e.key) IS NOT NULL
              AND EXISTS (
                  SELECT 1 FROM public.monedas m WHERE m.codigo = upper(btrim(e.key))
              )
            ON CONFLICT (id_turno, moneda) DO UPDATE
                SET efectivo_inicial = excluded.efectivo_inicial,
                    updated_at = now();
        END IF;
    END IF;
    RETURN v_res;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_apertura_turno_offline_monedas_m01(uuid, bigint, bigint, uuid, boolean, jsonb, jsonb, text, timestamp with time zone)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_apertura_turno_offline_monedas_m01(uuid, bigint, bigint, uuid, boolean, jsonb, jsonb, text, timestamp with time zone)
  TO authenticated, service_role;
