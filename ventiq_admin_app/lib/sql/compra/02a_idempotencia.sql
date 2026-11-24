-- ============================================================================
-- 02a_idempotencia.sql — Fase 2: idempotencia real por columna (R5)
--
-- REQUIERE: 01_motor_dinero.sql aplicado.
--
-- Problema que cierra:
--   · `fn_fdi_ingreso_manual` comparaba `observacion = 'idem:<uuid>'`, pero el
--     movimiento se escribe como `motivo · fecha · idem:<uuid>` → la comprobación
--     NUNCA coincidía y el reintento duplicaba el ingreso.
--   · `fn_fdi_ajuste` y `fn_fdi_gasto` usaban `LIKE '%idem:<uuid>'`: funcionaba
--     en serie, pero dos reintentos concurrentes pasaban ambos por el EXISTS.
--
-- Solución: columna `idempotency_key uuid` + índice único parcial por `tipo`,
-- y las tres RPC pasan la clave al aplicador. El duplicado lo corta la base
-- (23505), no una consulta previa.
--
-- ROLLBACK: 02a_idempotencia_rollback.sql
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) Columna + backfill del histórico (13 movimientos con `idem:`)
-- ---------------------------------------------------------------------------
ALTER TABLE public.fdi_dat_movimiento
  ADD COLUMN IF NOT EXISTS idempotency_key uuid;

UPDATE public.fdi_dat_movimiento
   SET idempotency_key =
       substring(observacion from 'idem:([0-9a-fA-F-]{36})')::uuid
 WHERE idempotency_key IS NULL
   AND observacion ~ 'idem:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}';

-- Verificado antes de crear el índice: 0 pares (tipo, clave) repetidos.
CREATE UNIQUE INDEX IF NOT EXISTS idx_fdi_movimiento_idem
  ON public.fdi_dat_movimiento (tipo, idempotency_key)
  WHERE idempotency_key IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 2) Aplicador con la clave
--    Se elimina la firma de 10 args para que no queden dos overloads vivos:
--    si se dejara, cualquier llamada de 10 args seguiría usando la vieja.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public._fdi_aplicar_movimiento(
    bigint, bigint, smallint, text, numeric, character varying, bigint, bigint, bigint, text);

CREATE OR REPLACE FUNCTION public._fdi_aplicar_movimiento(
    p_id_tienda        bigint,
    p_id_cuenta        bigint,
    p_id_medio_pago    smallint,
    p_moneda           text,
    p_delta            numeric,
    p_tipo             character varying,
    p_id_liquidacion   bigint DEFAULT NULL,
    p_id_transferencia bigint DEFAULT NULL,
    p_id_inversion     bigint DEFAULT NULL,
    p_observacion      text   DEFAULT NULL,
    p_idempotency_key  uuid   DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_saldo_id     bigint;
    v_saldo_tienda bigint;
    v_saldo_previo numeric;
    v_saldo_nuevo  numeric;
    v_moneda       text := upper(btrim(coalesce(p_moneda, '')));
BEGIN
    IF v_moneda = '' THEN
        RAISE EXCEPTION 'La moneda es obligatoria' USING ERRCODE = '22023';
    END IF;
    IF p_delta IS NULL OR p_delta <> round(p_delta, 2) THEN
        RAISE EXCEPTION 'El monto debe tener como máximo dos decimales (recibido %)', p_delta
            USING ERRCODE = '22023';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.fdi_dat_cuenta c
        WHERE c.id = p_id_cuenta AND c.id_tienda = p_id_tienda
    ) THEN
        RAISE EXCEPTION 'La cuenta % no pertenece a la tienda %', p_id_cuenta, p_id_tienda
            USING ERRCODE = '42501';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM public.app_nom_medio_pago m WHERE m.id = p_id_medio_pago) THEN
        RAISE EXCEPTION 'El medio de pago % no existe', p_id_medio_pago USING ERRCODE = 'P0002';
    END IF;

    SELECT id, id_tienda, saldo
      INTO v_saldo_id, v_saldo_tienda, v_saldo_previo
    FROM public.fdi_dat_saldo
    WHERE id_cuenta = p_id_cuenta
      AND id_medio_pago = p_id_medio_pago
      AND moneda = v_moneda
    FOR UPDATE;

    IF v_saldo_id IS NULL THEN
        INSERT INTO public.fdi_dat_saldo
            (id_tienda, id_cuenta, id_medio_pago, moneda, saldo)
        VALUES (p_id_tienda, p_id_cuenta, p_id_medio_pago, v_moneda, 0)
        RETURNING id, saldo INTO v_saldo_id, v_saldo_previo;
    ELSIF v_saldo_tienda <> p_id_tienda THEN
        RAISE EXCEPTION 'El saldo de la cuenta % pertenece a otra tienda', p_id_cuenta
            USING ERRCODE = '42501';
    END IF;

    v_saldo_nuevo := round(v_saldo_previo + p_delta, 2);
    IF v_saldo_nuevo < 0 THEN
        RAISE EXCEPTION 'Saldo insuficiente en cuenta %, medio %, moneda %: disponible %, requerido %',
            p_id_cuenta, p_id_medio_pago, v_moneda, v_saldo_previo, -p_delta
            USING ERRCODE = 'P0002';
    END IF;

    UPDATE public.fdi_dat_saldo
    SET saldo = v_saldo_nuevo, updated_at = now()
    WHERE id = v_saldo_id;

    INSERT INTO public.fdi_dat_movimiento (
        id_tienda, id_cuenta, id_medio_pago, moneda, monto,
        saldo_anterior, saldo_nuevo, tipo,
        id_liquidacion, id_transferencia, id_inversion,
        observacion, created_by, idempotency_key
    ) VALUES (
        p_id_tienda, p_id_cuenta, p_id_medio_pago, v_moneda, round(p_delta, 2),
        v_saldo_previo, v_saldo_nuevo, p_tipo,
        p_id_liquidacion, p_id_transferencia, p_id_inversion,
        p_observacion, auth.uid(), p_idempotency_key
    );
END;
$$;

-- ---------------------------------------------------------------------------
-- 3) Las tres RPC: pasan la clave y atrapan el 23505
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_ingreso_manual(
    p_id_tienda       bigint,
    p_id_cuenta       bigint,
    p_id_medio_pago   smallint,
    p_moneda          text,
    p_monto           numeric,
    p_fecha           date DEFAULT CURRENT_DATE,
    p_motivo          text DEFAULT NULL,
    p_idempotency_key uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT public.fn_user_is_gerente_or_superadmin(p_id_tienda) THEN
        RAISE EXCEPTION 'Solo gerente o superadmin' USING ERRCODE = '42501';
    END IF;
    IF p_monto IS NULL OR p_monto <= 0 THEN
        RAISE EXCEPTION 'El monto debe ser mayor que 0' USING ERRCODE = 'P0002';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.fdi_dat_cuenta
                    WHERE id = p_id_cuenta AND id_tienda = p_id_tienda AND activo) THEN
        RAISE EXCEPTION 'La cuenta no existe o no es de la tienda' USING ERRCODE = 'P0002';
    END IF;

    BEGIN
        PERFORM public._fdi_aplicar_movimiento(
            p_id_tienda, p_id_cuenta, p_id_medio_pago, p_moneda, p_monto,
            'ingreso_manual',
            p_observacion := COALESCE(p_motivo, 'Ingreso manual')
                             || ' · ' || COALESCE(p_fecha::text, CURRENT_DATE::text)
                             || CASE WHEN p_idempotency_key IS NOT NULL
                                     THEN ' · idem:' || p_idempotency_key::text ELSE '' END,
            p_idempotency_key := p_idempotency_key);
    EXCEPTION WHEN unique_violation THEN
        RETURN jsonb_build_object('status', 'ok', 'duplicada', true);
    END;

    RETURN jsonb_build_object('status', 'ok');
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_fdi_ajuste(
    p_id_tienda       bigint,
    p_id_cuenta       bigint,
    p_id_medio_pago   smallint,
    p_moneda          text,
    p_monto           numeric,
    p_motivo          text,
    p_idempotency_key uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
    IF NOT EXISTS (SELECT 1 FROM public.fdi_dat_cuenta
                    WHERE id = p_id_cuenta AND id_tienda = p_id_tienda) THEN
        RAISE EXCEPTION 'La cuenta no existe o no es de la tienda' USING ERRCODE = 'P0002';
    END IF;

    BEGIN
        PERFORM public._fdi_aplicar_movimiento(
            p_id_tienda, p_id_cuenta, p_id_medio_pago, p_moneda, p_monto, 'ajuste',
            p_observacion := p_motivo
                || CASE WHEN p_idempotency_key IS NOT NULL
                        THEN ' · idem:' || p_idempotency_key::text ELSE '' END,
            p_idempotency_key := p_idempotency_key);
    EXCEPTION WHEN unique_violation THEN
        RETURN jsonb_build_object('status', 'ok', 'duplicada', true);
    END;

    RETURN jsonb_build_object('status', 'ok');
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_fdi_gasto(
    p_id_tienda       bigint,
    p_id_cuenta       bigint,
    p_id_medio_pago   smallint,
    p_moneda          text,
    p_monto           numeric,
    p_destino         text,
    p_motivo          text DEFAULT NULL,
    p_idempotency_key uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_destino text := btrim(COALESCE(p_destino, ''));
    v_motivo  text := NULLIF(btrim(COALESCE(p_motivo, '')), '');
    v_obs     text;
BEGIN
    IF NOT public.fn_user_is_gerente_or_superadmin(p_id_tienda) THEN
        RAISE EXCEPTION 'Solo gerente o superadmin' USING ERRCODE = '42501';
    END IF;
    IF p_monto IS NULL OR p_monto <= 0 THEN
        RAISE EXCEPTION 'El monto del gasto debe ser mayor que 0' USING ERRCODE = 'P0002';
    END IF;
    IF v_destino = '' THEN
        RAISE EXCEPTION 'Indica el destino del gasto' USING ERRCODE = 'P0002';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.fdi_dat_cuenta
                    WHERE id = p_id_cuenta AND id_tienda = p_id_tienda AND activo) THEN
        RAISE EXCEPTION 'La cuenta no existe, no es de la tienda o está inactiva'
            USING ERRCODE = 'P0002';
    END IF;

    v_obs := 'Destino: ' || v_destino
        || CASE WHEN v_motivo IS NOT NULL THEN ' · ' || v_motivo ELSE '' END
        || CASE WHEN p_idempotency_key IS NOT NULL
                THEN ' · idem:' || p_idempotency_key::text ELSE '' END;

    BEGIN
        PERFORM public._fdi_aplicar_movimiento(
            p_id_tienda, p_id_cuenta, p_id_medio_pago, p_moneda, -p_monto, 'gasto',
            p_observacion := v_obs,
            p_idempotency_key := p_idempotency_key);
    EXCEPTION WHEN unique_violation THEN
        RETURN jsonb_build_object('status', 'ok', 'duplicada', true);
    END;

    RETURN jsonb_build_object('status', 'ok');
END;
$$;

-- ---------------------------------------------------------------------------
-- 4) Verificación — si algo no cuadra, se revierte todo
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_col      integer;
    v_idx      integer;
    v_backfill integer;
    v_firmas   integer;
BEGIN
    SELECT count(*) INTO v_col
    FROM information_schema.columns
    WHERE table_schema='public' AND table_name='fdi_dat_movimiento'
      AND column_name='idempotency_key';
    IF v_col <> 1 THEN
        RAISE EXCEPTION 'Falta la columna idempotency_key';
    END IF;

    SELECT count(*) INTO v_idx
    FROM pg_indexes
    WHERE schemaname='public' AND indexname='idx_fdi_movimiento_idem';
    IF v_idx <> 1 THEN
        RAISE EXCEPTION 'Falta el índice único de idempotencia';
    END IF;

    -- El backfill debe haber recogido todas las claves del histórico.
    SELECT count(*) INTO v_backfill
    FROM public.fdi_dat_movimiento
    WHERE observacion ~ 'idem:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
      AND idempotency_key IS NULL;
    IF v_backfill > 0 THEN
        RAISE EXCEPTION 'Quedaron % movimientos con idem: sin columna', v_backfill;
    END IF;

    -- No debe quedar el overload viejo de 10 args.
    SELECT count(*) INTO v_firmas
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname='public' AND p.proname='_fdi_aplicar_movimiento';
    IF v_firmas <> 1 THEN
        RAISE EXCEPTION 'Quedaron % firmas de _fdi_aplicar_movimiento (debe ser 1)', v_firmas;
    END IF;
END;
$$;

COMMIT;