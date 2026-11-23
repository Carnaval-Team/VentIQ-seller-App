-- ============================================================================
-- 06d_ajustes_por_financiar_rollback.sql — reversa de la fase 6d
--
-- REQUIERE: 06d_ajustes_por_financiar.sql aplicado.
--
-- Qué deshace:
--   1. `fn_fdi_compra_ajuste_financiar(bigint, jsonb, uuid)`
--   2. `fn_fdi_compra_ajuste_agregar(bigint, bigint, text, numeric, text, boolean, uuid)`
--   3. `fn_fdi_compra_recalcular` vuelve a su cuerpo anterior: recalcula
--      `total_financiado` siempre (sin el congelamiento tras `creada`).
--   4. Columnas e índices: `id_ajuste` en reserva, pago y costo;
--      `idempotency_key` en el ajuste y su índice único.
--
-- No toca los datos: los ajustes ya financiados conservan su estado; al
-- retirar `id_ajuste` de reserva/pago/costo se pierde la trazabilidad del
-- documento (los importes siguen).
--
-- Es transaccional.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) Retirar las RPC
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.fn_fdi_compra_ajuste_financiar(bigint, jsonb, uuid);
DROP FUNCTION IF EXISTS public.fn_fdi_compra_ajuste_agregar(bigint, bigint, text, numeric, text, boolean, uuid);

-- ---------------------------------------------------------------------------
-- 2) Devolver `fn_fdi_compra_recalcular` a su cuerpo anterior
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_fdi_compra_recalcular(p_id_compra bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_merc     numeric;
    v_aj_tot   numeric;
    v_aj_fin   numeric;
BEGIN
    SELECT COALESCE(sum(costo_linea), 0) INTO v_merc
    FROM public.fdi_dat_compra_linea WHERE id_compra = p_id_compra;

    SELECT COALESCE(sum(monto_capitalizado), 0),
           COALESCE(sum(monto_capitalizado) FILTER (WHERE origen_pago = 'fondo'), 0)
      INTO v_aj_tot, v_aj_fin
    FROM public.fdi_dat_compra_ajuste WHERE id_compra = p_id_compra;

    UPDATE public.fdi_dat_compra
       SET total_mercancia  = v_merc,
           total_ajustes    = v_aj_tot,
           total_financiado = v_merc + v_aj_fin,
           costo_aterrizado = v_merc + v_aj_tot,
           updated_at       = now()
     WHERE id = p_id_compra;
END;
$$;

-- ---------------------------------------------------------------------------
-- 3) Columnas e índices
-- ---------------------------------------------------------------------------
DROP INDEX IF EXISTS public.idx_fdi_reserva_ajuste;
DROP INDEX IF EXISTS public.idx_recepcion_producto_costo_ajuste;
DROP INDEX IF EXISTS public.idx_fdi_ajuste_idem;

ALTER TABLE public.fdi_dat_compra_reserva
    DROP COLUMN IF EXISTS id_ajuste;

ALTER TABLE public.fdi_dat_compra_pago
    DROP COLUMN IF EXISTS id_ajuste;

ALTER TABLE public.app_dat_recepcion_producto_costo
    DROP COLUMN IF EXISTS id_ajuste;

ALTER TABLE public.fdi_dat_compra_ajuste
    DROP COLUMN IF EXISTS idempotency_key;

-- ---------------------------------------------------------------------------
-- 4) Verificación final
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v integer;
BEGIN
    IF to_regprocedure('public.fn_fdi_compra_ajuste_financiar(bigint,jsonb,uuid)') IS NOT NULL THEN
        RAISE EXCEPTION 'Rollback 06d: fn_fdi_compra_ajuste_financiar sigue existiendo';
    END IF;
    IF to_regprocedure('public.fn_fdi_compra_ajuste_agregar(bigint,bigint,text,numeric,text,boolean,uuid)') IS NOT NULL THEN
        RAISE EXCEPTION 'Rollback 06d: fn_fdi_compra_ajuste_agregar sigue existiendo';
    END IF;

    SELECT count(*) INTO v FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'fdi_dat_compra_ajuste'
       AND column_name = 'idempotency_key';
    IF v <> 0 THEN
        RAISE EXCEPTION 'Rollback 06d: fdi_dat_compra_ajuste.idempotency_key sigue existiendo';
    END IF;

    SELECT count(*) INTO v FROM information_schema.columns
     WHERE table_schema = 'public'
       AND ((table_name = 'fdi_dat_compra_reserva' AND column_name = 'id_ajuste')
         OR (table_name = 'fdi_dat_compra_pago' AND column_name = 'id_ajuste')
         OR (table_name = 'app_dat_recepcion_producto_costo' AND column_name = 'id_ajuste'));
    IF v <> 0 THEN
        RAISE EXCEPTION 'Rollback 06d: quedan % columnas id_ajuste', v;
    END IF;

    SELECT count(*) INTO v FROM pg_proc p
     WHERE p.oid = 'public.fn_fdi_compra_recalcular(bigint)'::regprocedure
       AND position('v_estado' in p.prosrc) = 0;
    IF v <> 1 THEN
        RAISE EXCEPTION 'Rollback 06d: fn_fdi_compra_recalcular no volvió a su cuerpo anterior';
    END IF;

    RAISE NOTICE 'Rollback 06d aplicado: RPCs y columnas retiradas, recálculo restaurado.';
END;
$$;

COMMIT;