-- ============================================================================
-- PROMOCION M01 · 01 · Helpers aditivos (alineación de apertura + caja C14)
-- ============================================================================
-- Destino: main (cuando se autorice). NO se aplica desde este repo automáticamente.
-- Aditivo: main no tiene estas funciones; ningún nombre existente se reemplaza.
-- Cuerpos: newa vigente (pg_get_functiondef, 2026-11-23).
--
--   fn_turno_alinear_fecha_apertura        (interno; solo service_role)
--   fn_alinear_apertura_turno_offline      (authenticated, service_role)
--   fn_caja_disponible_para_egreso         (authenticated, service_role)
--
-- Dependencias externas (deben existir en main antes de ejecutar las RPC):
--   public.fn_config_tienda_puede_escribir(bigint)   -- usada por fn_alinear_*
--   public.fn_operacion_completada(bigint)           -- usada por fn_caja_disponible_*
--   public.fn_operacion_en_turno(bigint,bigint,timestamptz)
--   public.monedas, public.app_dat_caja_turno_moneda
-- plpgsql no valida estas llamadas al crear, así que el script se aplica aunque
-- falten; el preflight de 02..06 sí las exige antes de crear las _m01.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- fn_turno_alinear_fecha_apertura
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_turno_alinear_fecha_apertura(p_id_turno bigint, p_fecha_apertura timestamp with time zone)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
    v_turno record;
    v_cierre_previo timestamptz;
    v_fecha timestamptz;
BEGIN
    IF p_id_turno IS NULL OR p_fecha_apertura IS NULL THEN
        RETURN false;
    END IF;

    SELECT ct.id, ct.id_tpv, ct.id_vendedor, ct.estado, ct.fecha_apertura
    INTO v_turno
    FROM public.app_dat_caja_turno ct
    WHERE ct.id = p_id_turno
    FOR UPDATE;
    IF NOT FOUND OR v_turno.estado IS DISTINCT FROM 1 OR v_turno.fecha_apertura IS NULL THEN
        RETURN false;
    END IF;

    -- Nunca en el futuro (reloj o zona horaria del dispositivo).
    v_fecha := LEAST(p_fecha_apertura, now());
    -- Solo hacia atrás.
    IF v_fecha >= v_turno.fecha_apertura THEN
        RETURN false;
    END IF;
    -- Tope de cordura: más de 3 días offline se revisa a mano.
    IF v_turno.fecha_apertura - v_fecha > interval '72 hours' THEN
        RAISE WARNING 'fn_turno_alinear_fecha_apertura: turno % salto % rechazado',
            p_id_turno, v_turno.fecha_apertura - v_fecha;
        RETURN false;
    END IF;

    -- No solapar con el turno anterior del mismo TPV + vendedor.
    SELECT max(COALESCE(p.fecha_cierre, p.fecha_apertura))
    INTO v_cierre_previo
    FROM public.app_dat_caja_turno p
    WHERE p.id_tpv = v_turno.id_tpv
      AND p.id_vendedor = v_turno.id_vendedor
      AND p.id <> v_turno.id
      AND p.fecha_apertura < v_turno.fecha_apertura;
    IF v_cierre_previo IS NOT NULL AND v_fecha <= v_cierre_previo THEN
        v_fecha := v_cierre_previo + interval '1 millisecond';
    END IF;
    IF v_fecha >= v_turno.fecha_apertura THEN
        RETURN false;
    END IF;

    UPDATE public.app_dat_caja_turno
    SET fecha_apertura = v_fecha
    WHERE id = p_id_turno;
    RETURN true;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_turno_alinear_fecha_apertura(bigint, timestamp with time zone)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_turno_alinear_fecha_apertura(bigint, timestamp with time zone)
  TO service_role;

-- ---------------------------------------------------------------------------
-- fn_alinear_apertura_turno_offline
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_alinear_apertura_turno_offline(p_id_turno bigint, p_fecha_apertura timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
    v_actor uuid := auth.uid();
    v_store bigint;
    v_tpv bigint;
    v_vendedor bigint;
    v_ok boolean;
BEGIN
    IF v_actor IS NULL OR p_id_turno IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    SELECT t.id_tienda, ct.id_tpv, ct.id_vendedor
    INTO v_store, v_tpv, v_vendedor
    FROM public.app_dat_caja_turno ct
    JOIN public.app_dat_tpv t ON t.id = ct.id_tpv
    WHERE ct.id = p_id_turno;
    IF v_store IS NULL THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    -- Administrador de la tienda o el propio vendedor del turno.
    IF public.fn_config_tienda_puede_escribir(v_store) IS DISTINCT FROM true
       AND NOT EXISTS (
            SELECT 1
            FROM public.app_dat_vendedor s
            JOIN public.app_dat_trabajadores w ON w.id = s.id_trabajador
            WHERE s.id = v_vendedor
              AND s.uuid = v_actor AND w.uuid = v_actor
              AND w.deleted_at IS NULL
              AND w.id_tienda = v_store
       ) THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;

    PERFORM pg_advisory_xact_lock(
        hashtextextended(format('apertura_turno:%s:%s', v_tpv, v_vendedor), 0)
    );
    v_ok := public.fn_turno_alinear_fecha_apertura(p_id_turno, p_fecha_apertura);

    RETURN jsonb_build_object(
        'status', 'success',
        'alineado', v_ok,
        'fecha_apertura', (SELECT fecha_apertura FROM public.app_dat_caja_turno WHERE id = p_id_turno)
    );
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_alinear_apertura_turno_offline(bigint, timestamp with time zone)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_alinear_apertura_turno_offline(bigint, timestamp with time zone)
  TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- fn_caja_disponible_para_egreso (C14) — fuente: fn_egreso_validar_saldo_caja.sql
-- ---------------------------------------------------------------------------
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
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_caja_disponible_para_egreso(bigint, text, smallint)
  TO authenticated, service_role;
