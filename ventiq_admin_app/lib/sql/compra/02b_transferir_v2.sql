-- ============================================================================
-- 02b_transferir_v2.sql — Fase 2: tasa con sentido explícito (X2) + ajuste
--                           con motivo estructurado y umbral (X11)
--
-- REQUIERE: 02a_idempotencia.sql aplicado.
--
-- X2: `fn_fdi_transferir` multiplica por una tasa cuyo sentido NO valida.
--     Con la tasa tecleada al revés, 1.000 USD se convierten en 1 CUP y el
--     libro queda conciliado mientras el fondo pierde ~999.999 CUP.
--     Solución: `fn_fdi_transferir_v2` con par explícito
--     T(origen → destino) = unidades de destino por 1 de origen, y cordura
--     contra la última transferencia del mismo par (±20 %).
--     **La v1 no se toca**: cambiar su semántica sin cambiar su firma rompería
--     el cliente desplegado.
--
-- X11: el ajuste deja de ser texto libre. Motivo por código y, por encima del
--     umbral configurado, solo el dueño puede aplicarlo.
--
-- ROLLBACK: 02b_transferir_v2_rollback.sql
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) Columnas de tasa con sentido explícito
--    `tasa` se conserva con la semántica de la v1 (destino→origen) para no
--    romper consumidores. Las dos nuevas son las que mandan.
-- ---------------------------------------------------------------------------
ALTER TABLE public.fdi_dat_transferencia
  ADD COLUMN IF NOT EXISTS tasa_origen_a_destino numeric,
  ADD COLUMN IF NOT EXISTS tasa_destino_a_origen numeric;

ALTER TABLE public.fdi_dat_config
  ADD COLUMN IF NOT EXISTS umbral_ajuste numeric;

-- ---------------------------------------------------------------------------
-- 2) fn_fdi_transferir_v2
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_transferir_v2(
    p_id_tienda                 bigint,
    p_id_cuenta_origen          bigint,
    p_id_medio_pago_origen      smallint,
    p_moneda_origen             text,
    p_id_cuenta_destino         bigint,
    p_id_medio_pago_destino     smallint,
    p_moneda_destino            text,
    p_monto_origen              numeric,
    p_tasa_origen_a_destino     numeric,
    p_porcentaje_costo          numeric DEFAULT 0,
    p_id_transferencia_corregida bigint DEFAULT NULL,
    p_observacion               text DEFAULT NULL,
    p_idempotency_key           uuid DEFAULT NULL,
    p_forzar_salto_tasa         boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_mo      text := upper(btrim(coalesce(p_moneda_origen, '')));
    v_md      text := upper(btrim(coalesce(p_moneda_destino, '')));
    v_tasa    numeric := p_tasa_origen_a_destino;
    v_monto_destino numeric;
    v_comision numeric := 0;
    v_total_origen numeric;
    v_ref     numeric;
    v_existe  bigint;
    v_id      bigint;
BEGIN
    IF NOT public.fn_user_is_gerente_or_superadmin(p_id_tienda) THEN
        RAISE EXCEPTION 'Solo gerente o superadmin' USING ERRCODE = '42501';
    END IF;
    IF p_monto_origen IS NULL OR p_monto_origen <= 0
       OR p_monto_origen <> round(p_monto_origen, 2) THEN
        RAISE EXCEPTION 'El monto de origen debe ser > 0 y de dos decimales' USING ERRCODE = '22023';
    END IF;
    IF v_mo = '' OR v_md = '' THEN
        RAISE EXCEPTION 'Ambas monedas son obligatorias' USING ERRCODE = '22023';
    END IF;
    IF v_tasa IS NULL OR v_tasa <= 0 THEN
        RAISE EXCEPTION 'La tasa T(origen→destino) debe ser > 0' USING ERRCODE = '22023';
    END IF;
    IF p_id_cuenta_origen = p_id_cuenta_destino
       AND p_id_medio_pago_origen = p_id_medio_pago_destino
       AND v_mo = v_md THEN
        RAISE EXCEPTION 'La cuenta, el medio y la moneda deben cambiar' USING ERRCODE = '22023';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.fdi_dat_cuenta
                    WHERE id = p_id_cuenta_origen AND id_tienda = p_id_tienda) THEN
        RAISE EXCEPTION 'Cuenta origen inválida' USING ERRCODE = '42501';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.fdi_dat_cuenta
                    WHERE id = p_id_cuenta_destino AND id_tienda = p_id_tienda) THEN
        RAISE EXCEPTION 'Cuenta destino inválida' USING ERRCODE = '42501';
    END IF;

    -- Cordura: contra la última transferencia del mismo par (±20 %).
    SELECT CASE
             WHEN moneda_origen = v_mo AND moneda_destino = v_md
             THEN tasa_origen_a_destino
             WHEN moneda_origen = v_md AND moneda_destino = v_mo
             THEN 1.0 / NULLIF(tasa_origen_a_destino, 0)
           END
      INTO v_ref
    FROM public.fdi_dat_transferencia
    WHERE id_tienda = p_id_tienda
      AND tasa_origen_a_destino IS NOT NULL
      AND ((moneda_origen = v_mo AND moneda_destino = v_md)
        OR (moneda_origen = v_md AND moneda_destino = v_mo))
    ORDER BY id DESC
    LIMIT 1;

    IF v_ref IS NOT NULL AND v_ref > 0
       AND abs(v_tasa - v_ref) / v_ref > 0.20
       AND NOT COALESCE(p_forzar_salto_tasa, false) THEN
        RAISE EXCEPTION
            'La tasa % se aparta más de un 20%% de la última conocida para % → % (%). Confirma el salto si es intencionado.',
            v_tasa, v_mo, v_md, round(v_ref, 6)
            USING ERRCODE = '22023';
    END IF;

    IF p_idempotency_key IS NOT NULL THEN
        SELECT id INTO v_existe FROM public.fdi_dat_transferencia
        WHERE idempotency_key = p_idempotency_key;
        IF v_existe IS NOT NULL THEN
            RETURN jsonb_build_object('status', 'ok', 'id_transferencia', v_existe, 'duplicada', true);
        END IF;
    END IF;

    v_monto_destino := round(p_monto_origen * v_tasa, 2);
    IF v_monto_destino <= 0 THEN
        RAISE EXCEPTION 'La conversión resultó en 0; revisa la tasa' USING ERRCODE = '22023';
    END IF;

    IF COALESCE(p_porcentaje_costo, 0) < 0 OR COALESCE(p_porcentaje_costo, 0) >= 100 THEN
        RAISE EXCEPTION 'El porcentaje de costo debe estar en [0, 100)' USING ERRCODE = '22023';
    END IF;
    v_comision := round(p_monto_origen * COALESCE(p_porcentaje_costo, 0) / 100, 2);
    v_total_origen := round(p_monto_origen + v_comision, 2);

    INSERT INTO public.fdi_dat_transferencia (
        id_tienda, idempotency_key,
        id_cuenta_origen, id_medio_pago_origen, moneda_origen,
        id_cuenta_destino, id_medio_pago_destino, moneda_destino,
        monto_destino, tasa, tasa_origen_a_destino, tasa_destino_a_origen,
        monto_base_origen, porcentaje_costo, monto_comision, monto_total_origen,
        id_transferencia_corregida, observacion, created_by
    ) VALUES (
        p_id_tienda, p_idempotency_key,
        p_id_cuenta_origen, p_id_medio_pago_origen, v_mo,
        p_id_cuenta_destino, p_id_medio_pago_destino, v_md,
        v_monto_destino,
        round(1.0 / v_tasa, 10),          -- `tasa` mantiene la semántica de la v1
        v_tasa,
        round(1.0 / v_tasa, 10),
        p_monto_origen, COALESCE(p_porcentaje_costo, 0), v_comision, v_total_origen,
        p_id_transferencia_corregida, p_observacion, auth.uid()
    ) RETURNING id INTO v_id;

    BEGIN
        -- Salida de la base
        PERFORM public._fdi_aplicar_movimiento(
            p_id_tienda, p_id_cuenta_origen, p_id_medio_pago_origen, v_mo,
            -p_monto_origen, 'transferencia_salida',
            p_id_transferencia := v_id,
            p_observacion := p_observacion,
            p_idempotency_key := p_idempotency_key);

        -- Comisión (movimiento propio, mismo documento)
        IF v_comision > 0 THEN
            PERFORM public._fdi_aplicar_movimiento(
                p_id_tienda, p_id_cuenta_origen, p_id_medio_pago_origen, v_mo,
                -v_comision, 'comision_transferencia',
                p_id_transferencia := v_id,
                p_observacion := 'Comisión ' || COALESCE(p_porcentaje_costo, 0)::text || '%',
                p_idempotency_key := p_idempotency_key);
        END IF;

        -- Entrada en destino
        PERFORM public._fdi_aplicar_movimiento(
            p_id_tienda, p_id_cuenta_destino, p_id_medio_pago_destino, v_md,
            v_monto_destino, 'transferencia_entrada',
            p_id_transferencia := v_id,
            p_observacion := p_observacion,
            p_idempotency_key := p_idempotency_key);
    EXCEPTION WHEN unique_violation THEN
        -- Reintento concurrente: el documento ya existe, no se vuelve a mover.
        RETURN jsonb_build_object('status', 'ok', 'duplicada', true);
    END;

    RETURN jsonb_build_object(
        'status', 'ok',
        'id_transferencia', v_id,
        'tasa_origen_a_destino', v_tasa,
        'monto_origen', p_monto_origen,
        'comision', v_comision,
        'total_origen', v_total_origen,
        'monto_destino', v_monto_destino,
        'tasa_referencia', v_ref);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_fdi_transferir_v2(
    bigint, bigint, smallint, text, bigint, smallint, text, numeric, numeric,
    numeric, bigint, text, uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_fdi_transferir_v2(
    bigint, bigint, smallint, text, bigint, smallint, text, numeric, numeric,
    numeric, bigint, text, uuid, boolean) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3) X11 · fn_fdi_ajuste con motivo por código y umbral
--    Se mantiene la firma de la 2a y se añade el código como último parámetro.
-- ---------------------------------------------------------------------------
-- Se elimina la firma de 7 args: con CREATE OR REPLACE quedaría como overload
-- y las llamadas del cliente seguirían resolviendo a la vieja.
DROP FUNCTION IF EXISTS public.fn_fdi_ajuste(
    bigint, bigint, smallint, text, numeric, text, uuid);

CREATE OR REPLACE FUNCTION public.fn_fdi_ajuste(
    p_id_tienda       bigint,
    p_id_cuenta       bigint,
    p_id_medio_pago   smallint,
    p_moneda          text,
    p_monto           numeric,
    p_motivo          text,
    p_idempotency_key uuid DEFAULT NULL,
    p_motivo_codigo   text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_codigos constant text[] := ARRAY['redondeo','error_captura','ajuste_cliente',
                                       'conciliacion','otro'];
    v_umbral  numeric;
BEGIN
    IF NOT public.fn_user_is_gerente_or_superadmin(p_id_tienda) THEN
        RAISE EXCEPTION 'Solo gerente o superadmin' USING ERRCODE = '42501';
    END IF;
    IF p_monto IS NULL OR p_monto <= 0 THEN
        RAISE EXCEPTION 'Los ajustes solo son positivos (monto > 0)' USING ERRCODE = 'P0002';
    END IF;
    IF p_motivo IS NULL OR btrim(p_motivo) = '' THEN
        RAISE EXCEPTION 'El motivo del ajuste es obligatorio' USING ERRCODE = 'P0002';
    END IF;
    IF p_motivo_codigo IS NOT NULL AND NOT (p_motivo_codigo = ANY (v_codigos)) THEN
        RAISE EXCEPTION 'Código de motivo inválido: %. Válidos: %', p_motivo_codigo, v_codigos
            USING ERRCODE = '22023';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.fdi_dat_cuenta
                    WHERE id = p_id_cuenta AND id_tienda = p_id_tienda) THEN
        RAISE EXCEPTION 'La cuenta no existe o no es de la tienda' USING ERRCODE = 'P0002';
    END IF;

    -- Umbral: por encima, solo el dueño.
    SELECT umbral_ajuste INTO v_umbral
    FROM public.fdi_dat_config WHERE id_tienda = p_id_tienda;

    IF v_umbral IS NOT NULL AND p_monto > v_umbral
       AND auth.uid() IS NOT NULL
       AND NOT COALESCE(public.fn_user_is_dueno(p_id_tienda), false) THEN
        RAISE EXCEPTION 'Un ajuste de % supera el umbral % (%). Solo el dueño puede aplicarlo.',
            p_monto, v_umbral, p_id_tienda
            USING ERRCODE = '42501';
    END IF;

    BEGIN
        PERFORM public._fdi_aplicar_movimiento(
            p_id_tienda, p_id_cuenta, p_id_medio_pago, p_moneda, p_monto, 'ajuste',
            p_observacion := p_motivo
                || CASE WHEN p_motivo_codigo IS NOT NULL THEN ' [' || p_motivo_codigo || ']' ELSE '' END
                || CASE WHEN p_idempotency_key IS NOT NULL
                        THEN ' · idem:' || p_idempotency_key::text ELSE '' END,
            p_idempotency_key := p_idempotency_key);
    EXCEPTION WHEN unique_violation THEN
        RETURN jsonb_build_object('status', 'ok', 'duplicada', true);
    END;

    RETURN jsonb_build_object('status', 'ok');
END;
$$;

-- ---------------------------------------------------------------------------
-- 4) Verificación
-- ---------------------------------------------------------------------------
DO $$
DECLARE v integer;
BEGIN
    SELECT count(*) INTO v FROM information_schema.columns
     WHERE table_schema='public' AND table_name='fdi_dat_transferencia'
       AND column_name IN ('tasa_origen_a_destino','tasa_destino_a_origen');
    IF v <> 2 THEN RAISE EXCEPTION 'Faltan las columnas de tasa explícita'; END IF;

    SELECT count(*) INTO v FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname='fn_fdi_transferir_v2';
    IF v <> 1 THEN RAISE EXCEPTION 'Falta fn_fdi_transferir_v2'; END IF;

    -- La v1 debe seguir viva y con 13 args.
    SELECT count(*) INTO v FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.proname='fn_fdi_transferir' AND p.pronargs=13;
    IF v <> 1 THEN RAISE EXCEPTION 'La v1 de transferir cambió: no debe tocarse'; END IF;

    SELECT count(*) INTO v FROM information_schema.columns
     WHERE table_schema='public' AND table_name='fdi_dat_config' AND column_name='umbral_ajuste';
    IF v <> 1 THEN RAISE EXCEPTION 'Falta fdi_dat_config.umbral_ajuste'; END IF;
END;
$$;

COMMIT;