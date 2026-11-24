-- ============================================================================
-- 01_motor_dinero_rollback.sql — reversa de la fase 1
--
-- Restaura los CUERPOS ORIGINALES de las 4 funciones que la migración reemplazó
-- (capturados de `newa` con pg_get_functiondef el 2026-11-20, antes de aplicarla),
-- revierte los CHECK y devuelve las columnas a numeric sin escala.
--
-- NO es reversible a ciegas: si ya existen inversiones 'anulado' o movimientos
-- 'devolucion_inversion', aborta. Esas filas habría que resolverlas primero.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 0) Guardia: no revertir si los valores nuevos ya se usaron
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM public.fdi_dat_inversion WHERE estado = 'anulado') THEN
        RAISE EXCEPTION 'Hay inversiones en estado anulado: resuélvelas antes de revertir';
    END IF;
    IF EXISTS (SELECT 1 FROM public.fdi_dat_movimiento WHERE tipo = 'devolucion_inversion') THEN
        RAISE EXCEPTION 'Hay movimientos devolucion_inversion: no se puede revertir el CHECK';
    END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 1) Quitar objetos nuevos
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.fn_fdi_inversion_anular(bigint, text);
DROP FUNCTION IF EXISTS public.fn_fdi_conciliacion(bigint);

-- ---------------------------------------------------------------------------
-- 2) CHECK originales
-- ---------------------------------------------------------------------------
ALTER TABLE public.fdi_dat_inversion
  DROP CONSTRAINT IF EXISTS fdi_dat_inversion_estado_check;
ALTER TABLE public.fdi_dat_inversion
  ADD CONSTRAINT fdi_dat_inversion_estado_check
  CHECK (estado IN ('pendiente', 'parcial', 'completado'));

ALTER TABLE public.fdi_dat_movimiento
  DROP CONSTRAINT IF EXISTS fdi_dat_movimiento_tipo_check;
ALTER TABLE public.fdi_dat_movimiento
  ADD CONSTRAINT fdi_dat_movimiento_tipo_check
  CHECK (tipo IN ('liquidacion', 'transferencia_salida', 'transferencia_entrada',
                  'comision_transferencia', 'extraccion_inversion', 'ingreso_manual',
                  'ajuste', 'ajuste_correccion', 'gasto'));

-- ---------------------------------------------------------------------------
-- 3) Cuerpos originales
-- ---------------------------------------------------------------------------
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
    p_observacion      text   DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_saldo_id     bigint;
    v_saldo_previo numeric;
    v_saldo_nuevo  numeric;
BEGIN
    SELECT id, saldo INTO v_saldo_id, v_saldo_previo
    FROM public.fdi_dat_saldo
    WHERE id_cuenta = p_id_cuenta
      AND id_medio_pago = p_id_medio_pago
      AND moneda = p_moneda
    FOR UPDATE;

    IF v_saldo_id IS NULL THEN
        INSERT INTO public.fdi_dat_saldo
            (id_tienda, id_cuenta, id_medio_pago, moneda, saldo)
        VALUES (p_id_tienda, p_id_cuenta, p_id_medio_pago, p_moneda, 0)
        RETURNING id, saldo INTO v_saldo_id, v_saldo_previo;
    END IF;

    v_saldo_nuevo := v_saldo_previo + p_delta;
    IF v_saldo_nuevo < 0 THEN
        RAISE EXCEPTION 'Saldo insuficiente en cuenta %, medio %, moneda %: disponible %, requerido %',
            p_id_cuenta, p_id_medio_pago, p_moneda, v_saldo_previo, -p_delta
            USING ERRCODE = 'P0002';
    END IF;

    UPDATE public.fdi_dat_saldo
    SET saldo = v_saldo_nuevo, updated_at = now()
    WHERE id = v_saldo_id;

    INSERT INTO public.fdi_dat_movimiento (
        id_tienda, id_cuenta, id_medio_pago, moneda, monto,
        saldo_anterior, saldo_nuevo, tipo,
        id_liquidacion, id_transferencia, id_inversion,
        observacion, created_by
    ) VALUES (
        p_id_tienda, p_id_cuenta, p_id_medio_pago, p_moneda, p_delta,
        v_saldo_previo, v_saldo_nuevo, p_tipo,
        p_id_liquidacion, p_id_transferencia, p_id_inversion,
        p_observacion, auth.uid()
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_fdi_vincular_recepcion(
    p_id_operacion     bigint,
    p_id_inversion     bigint,
    p_monto            numeric,
    p_moneda           text,
    p_tasa_a_ref       numeric DEFAULT 1,
    p_confirmar_exceso boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_inv      record;
    v_op_tienda bigint;
    v_monto_ref numeric;
BEGIN
    SELECT * INTO v_inv FROM public.fdi_dat_inversion WHERE id = p_id_inversion;
    IF v_inv.id IS NULL THEN
        RAISE EXCEPTION 'Inversión % no encontrada', p_id_inversion USING ERRCODE = 'P0002';
    END IF;

    SELECT id_tienda INTO v_op_tienda FROM public.app_dat_operaciones WHERE id = p_id_operacion;
    IF v_op_tienda IS NULL OR v_op_tienda <> v_inv.id_tienda THEN
        RAISE EXCEPTION 'La recepción % no pertenece a la tienda de la inversión',
            p_id_operacion USING ERRCODE = 'P0002';
    END IF;
    IF p_monto IS NULL OR p_monto <= 0 THEN
        RAISE EXCEPTION 'El monto de la recepción debe ser > 0' USING ERRCODE = 'P0002';
    END IF;

    IF p_moneda = v_inv.moneda_referencia THEN
        p_tasa_a_ref := 1;
    END IF;
    IF p_tasa_a_ref IS NULL OR p_tasa_a_ref <= 0 THEN
        RAISE EXCEPTION 'La tasa a la moneda de referencia debe ser > 0' USING ERRCODE = 'P0002';
    END IF;
    v_monto_ref := p_monto * p_tasa_a_ref;

    IF v_inv.monto_recibido_ref + v_monto_ref > v_inv.monto_total_ref
       AND NOT p_confirmar_exceso THEN
        RETURN jsonb_build_object(
            'status', 'requires_confirmation',
            'code', 'exceso_recepcion',
            'monto_total_ref', v_inv.monto_total_ref,
            'monto_recibido_ref', v_inv.monto_recibido_ref,
            'monto_nuevo_ref', v_monto_ref);
    END IF;

    INSERT INTO public.fdi_dat_inversion_recepcion (
        id_inversion, id_operacion, monto_recepcion, moneda_recepcion,
        tasa_a_ref, monto_ref, confirmada_con_exceso, created_by
    ) VALUES (
        p_id_inversion, p_id_operacion, p_monto, p_moneda,
        p_tasa_a_ref, v_monto_ref,
        v_inv.monto_recibido_ref + v_monto_ref > v_inv.monto_total_ref,
        auth.uid()
    );

    PERFORM public.fn_fdi_recalcular_inversion(p_id_inversion);

    RETURN jsonb_build_object('status', 'ok', 'monto_ref', v_monto_ref);
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_fdi_repartir_ganancia() RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_tienda    bigint;
    v_igual     boolean;
    v_total     numeric;
    v_n         integer;
    v_asignado  numeric := 0;
    v_monto     numeric;
    v_pct       numeric;
    v_i         record;
    v_ultimo    bigint;
BEGIN
    SELECT id_tienda, repartir_igual INTO STRICT v_tienda, v_igual
    FROM public.fdi_dat_liquidacion WHERE id = NEW.id_liquidacion;
    IF NOT COALESCE(public.fn_user_is_dueno(v_tienda), false) THEN
        RAISE EXCEPTION 'Solo el dueño puede liquidar ganancias' USING ERRCODE = '42501';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended('fdi_inversores:' || v_tienda, 0));
    SELECT sum(porcentaje), max(id), count(*) INTO v_total, v_ultimo, v_n
    FROM public.fdi_dat_inversor WHERE id_tienda = v_tienda AND activo;
    IF v_n IS NULL OR v_n = 0 THEN
        RAISE EXCEPTION 'No hay inversores activos para repartir la ganancia';
    END IF;
    IF NOT v_igual AND v_total IS DISTINCT FROM 100::numeric THEN
        RAISE EXCEPTION 'La participación de los inversores activos debe sumar 100%%';
    END IF;
    IF NEW.monto_ganancia_retirada = 0 THEN RETURN NEW; END IF;
    IF NEW.monto_ganancia_retirada <> round(NEW.monto_ganancia_retirada, 2) THEN
        RAISE EXCEPTION 'La ganancia retirada debe tener como máximo dos decimales';
    END IF;
    FOR v_i IN SELECT * FROM public.fdi_dat_inversor WHERE id_tienda = v_tienda AND activo ORDER BY id LOOP
        v_pct := CASE WHEN v_igual THEN 100.0 / v_n ELSE v_i.porcentaje END;
        v_monto := CASE WHEN NOT v_igual AND v_i.id = v_ultimo
                        THEN NEW.monto_ganancia_retirada - v_asignado
                        ELSE trunc(NEW.monto_ganancia_retirada * v_pct / 100, 2) END;
        INSERT INTO public.fdi_dat_inversor_reparto(id_tienda, id_inversor, id_detalle, nombre_snapshot, porcentaje_snapshot, moneda, monto)
        VALUES (v_tienda, v_i.id, NEW.id, v_i.nombre, v_pct, NEW.moneda, v_monto);
        v_asignado := v_asignado + v_monto;
    END LOOP;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_fdi_recalcular_inversion(p_id_inversion bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_inv      record;
    v_recibido numeric;
    v_nuevo    varchar;
BEGIN
    SELECT * INTO v_inv FROM public.fdi_dat_inversion WHERE id = p_id_inversion FOR UPDATE;
    IF v_inv.id IS NULL THEN
        RETURN;
    END IF;

    SELECT COALESCE(sum(monto_ref), 0) INTO v_recibido
    FROM public.fdi_dat_inversion_recepcion WHERE id_inversion = p_id_inversion;

    v_nuevo := CASE
        WHEN v_recibido <= 0 THEN 'pendiente'
        WHEN v_recibido < v_inv.monto_total_ref THEN 'parcial'
        ELSE 'completado' END;

    IF v_nuevo <> v_inv.estado THEN
        INSERT INTO public.fdi_hist_estado_inversion (
            id_inversion, estado_anterior, estado_nuevo, origen, motivo, created_by
        ) VALUES (
            p_id_inversion, v_inv.estado, v_nuevo, 'automatico',
            'Recalculo por recepciones', auth.uid());
    END IF;

    UPDATE public.fdi_dat_inversion
    SET monto_recibido_ref = v_recibido,
        estado             = v_nuevo,
        estado_manual      = false,
        requiere_revision  = CASE WHEN v_recibido >= v_inv.monto_total_ref
                                  THEN false ELSE requiere_revision END,
        motivo_revision    = CASE WHEN v_recibido >= v_inv.monto_total_ref
                                  THEN NULL ELSE motivo_revision END,
        monto_faltante_ref = CASE WHEN v_recibido >= v_inv.monto_total_ref
                                  THEN NULL ELSE monto_faltante_ref END,
        updated_at         = now()
    WHERE id = p_id_inversion;
END;
$$;

-- ---------------------------------------------------------------------------
-- 4) Volver a numeric sin escala (lossless: los valores ya son de 2 decimales)
-- ---------------------------------------------------------------------------
ALTER TABLE public.fdi_dat_saldo
  ALTER COLUMN saldo TYPE numeric;

ALTER TABLE public.fdi_dat_movimiento
  ALTER COLUMN monto          TYPE numeric,
  ALTER COLUMN saldo_anterior TYPE numeric,
  ALTER COLUMN saldo_nuevo    TYPE numeric;

COMMIT;