-- ============================================================================
-- 05a_compra_recepcion_rollback.sql — reversa de la fase 5a
--
-- REQUIERE: 03a_compra_esquema.sql aplicado (la tabla
--           `fdi_dat_compra_recepcion` viene de ahí, no de 05a). Si además se
--           revierte 03a, este script va PRIMERO.
-- ORDEN respecto a 05c: si también se revierte 05c, este script va DESPUÉS
--           (05c restaura RPC que este rollback no toca, y aquí se dropea
--           `fn_fdi_compra_vincular_recepcion`, que 05c no recrea).
--
-- Qué deshace, exactamente lo que añadió 05a:
--   · DROP de `fn_fdi_compra_recepcion_pendiente(bigint)` y
--     `fn_fdi_compra_vincular_recepcion(bigint,bigint,jsonb,boolean,numeric,numeric,numeric,text)`.
--   · Quita las 5 columnas del cargo de importadora de
--     `fdi_dat_compra_recepcion` y `fecha_operacion` de
--     `app_dat_operacion_recepcion`.
--   · Vacía `fdi_dat_compra_recepcion_linea` y `fdi_dat_compra_recepcion`,
--     porque esas filas sólo las podía crear la RPC que aquí desaparece.
--
-- GUARDIA: si hay filas de recepción, ABORTA. Para forzar el borrado:
--     select set_config('ventiq.forzar_rollback_compra', 'on', false);
--   y volver a lanzar el script en la MISMA sesión.
--
-- NO recalcula `fdi_dat_compra.estado`: las compras que la RPC dejó en
-- 'entrega_parcial'/'completada' se quedan como están (sin RPC que las
-- rederive, inventarse la transición sería peor). El estado anterior de cada
-- una está en `fdi_hist_estado_compra.estado_anterior`; el script avisa por
-- NOTICE cuántas quedan afectadas para que se revisen a mano.
--
-- No toca `fdi_dat_compra` ni `fdi_dat_compra_linea` (son de 03a). Es
-- transaccional: o sale todo o no sale nada.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) Guardia de datos
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_rc      bigint := 0;
    v_rl      bigint := 0;
    v_forzar  text   := current_setting('ventiq.forzar_rollback_compra', true);
BEGIN
    IF to_regclass('public.fdi_dat_compra_recepcion') IS NOT NULL THEN
        EXECUTE 'select count(*) from public.fdi_dat_compra_recepcion' INTO v_rc;
    END IF;
    IF to_regclass('public.fdi_dat_compra_recepcion_linea') IS NOT NULL THEN
        EXECUTE 'select count(*) from public.fdi_dat_compra_recepcion_linea' INTO v_rl;
    END IF;

    IF (v_rc > 0 OR v_rl > 0) AND coalesce(v_forzar, '') <> 'on' THEN
        RAISE EXCEPTION
            'Rollback 05a abortado: hay % vínculo(s) y % línea(s) de recepción que se perderían. '
            'Si es intencionado: select set_config(''ventiq.forzar_rollback_compra'', ''on'', false); '
            'y relance el script en la misma sesión.', v_rc, v_rl
            USING ERRCODE = '22023';
    END IF;

    RAISE NOTICE 'Rollback 05a: se borrarán % vínculo(s) y % línea(s) de recepción', v_rc, v_rl;
END;
$$;

-- ---------------------------------------------------------------------------
-- 2) Fuera las filas de recepción (primero las líneas, que son hijas)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_compras bigint;
BEGIN
    IF to_regclass('public.fdi_dat_compra_recepcion_linea') IS NOT NULL THEN
        DELETE FROM public.fdi_dat_compra_recepcion_linea;
    END IF;
    IF to_regclass('public.fdi_dat_compra_recepcion') IS NOT NULL THEN
        DELETE FROM public.fdi_dat_compra_recepcion;
    END IF;

    SELECT count(*) INTO v_compras
      FROM public.fdi_dat_compra
     WHERE estado IN ('entrega_parcial', 'completada');
    IF v_compras > 0 THEN
        RAISE NOTICE
            'Rollback 05a: % compra(s) siguen en entrega_parcial/completada sin recepciones. '
            'Revise fdi_hist_estado_compra.estado_anterior y corríjalas a mano.', v_compras;
    END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 3) Fuera las RPC (las GRANT/REVOKE se van con ellas)
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.fn_fdi_compra_vincular_recepcion(bigint, bigint, jsonb, boolean, numeric, numeric, numeric, text);
DROP FUNCTION IF EXISTS public.fn_fdi_compra_recepcion_pendiente(bigint);

-- ---------------------------------------------------------------------------
-- 4) Fuera las columnas
-- ---------------------------------------------------------------------------
ALTER TABLE public.fdi_dat_compra_recepcion
    DROP COLUMN IF EXISTS pct_importadora,
    DROP COLUMN IF EXISTS base_importadora,
    DROP COLUMN IF EXISTS monto_importadora,
    DROP COLUMN IF EXISTS reembolso_importadora,
    DROP COLUMN IF EXISTS origen_pago;

ALTER TABLE public.app_dat_operacion_recepcion
    DROP COLUMN IF EXISTS fecha_operacion;

-- ---------------------------------------------------------------------------
-- 5) Verificación: o quedó limpio, o se deshace todo
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_cols integer;
    v_fecha integer;
    v_rpcs integer;
    v_base integer;
BEGIN
    SELECT count(*) INTO v_cols
      FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'fdi_dat_compra_recepcion'
       AND column_name IN ('pct_importadora','base_importadora','monto_importadora',
                           'reembolso_importadora','origen_pago');
    IF v_cols <> 0 THEN
        RAISE EXCEPTION 'Quedaron % de 5 columnas de importadora', v_cols;
    END IF;

    SELECT count(*) INTO v_fecha
      FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'app_dat_operacion_recepcion'
       AND column_name = 'fecha_operacion';
    IF v_fecha <> 0 THEN
        RAISE EXCEPTION 'Quedó fecha_operacion';
    END IF;

    SELECT count(*) INTO v_rpcs
      FROM (VALUES
          ('public.fn_fdi_compra_recepcion_pendiente(bigint)'),
          ('public.fn_fdi_compra_vincular_recepcion(bigint,bigint,jsonb,boolean,numeric,numeric,numeric,text)')
      ) x(firma)
     WHERE to_regprocedure(x.firma) IS NOT NULL;
    IF v_rpcs <> 0 THEN
        RAISE EXCEPTION 'Quedaron % de 2 RPC de recepción; revisa las firmas', v_rpcs;
    END IF;

    -- La tabla es de 03a: este rollback NO debe llevársela.
    SELECT count(*) INTO v_base
      FROM (VALUES ('id_compra'), ('id_operacion'), ('id_tienda'), ('monto_valorizado'))
           x(col)
     WHERE EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema = 'public'
                      AND table_name = 'fdi_dat_compra_recepcion'
                      AND column_name = x.col);
    IF v_base <> 4 THEN
        RAISE EXCEPTION 'Se esperaban las 4 columnas base de 03a intactas y hay %', v_base;
    END IF;
END;
$$;

COMMIT;