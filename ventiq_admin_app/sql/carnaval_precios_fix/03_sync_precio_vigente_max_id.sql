-- =============================================================
-- CARNAVAL - Sync usa precio VIGENTE mas reciente por id
--
-- 03_sync_precio_vigente_max_id
--
-- Aplicar en: Supabase > SQL Editor
-- Idempotente: CREATE OR REPLACE (no toca tablas ni datos).
--
--
-- PROBLEMA
-- --------
-- 1) sync_price_to_carnaval usaba NEW.precio_venta_cup de la
--    fila que disparaba el trigger. Al cerrar duplicados
--    (solo fecha_hasta) sincronizaba el precio VIEJO de esa
--    fila y pisaba Carnaval.
--
-- 2) fn_update_carnaval_product_prices (trg_update_carnaval_
--    prices) tomaba ORDER BY created_at DESC sin filtrar
--    vigencia, distinto del criterio de keeper (MAX id).
--
-- REGLA NUEVA (ambos caminos)
-- ---------------------------
-- precio_base = precio_venta_cup de la fila vigente con
--               MAX(id) para el producto:
--   fecha_hasta IS NULL OR fecha_hasta >= CURRENT_DATE
-- ORDER BY id DESC
-- LIMIT 1
--
-- Ademas: sync IGNORA updates donde no cambian precios
-- (solo fecha_hasta / metadatos).
-- =============================================================


-- -------------------------------------------------------------
-- Precio base vigente (keeper = MAX id entre vigentes)
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_carnaval_precio_base_vigente(
    p_id_producto BIGINT
)
RETURNS NUMERIC
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
    SELECT pv.precio_venta_cup
      FROM public.app_dat_precio_venta pv
     WHERE pv.id_producto = p_id_producto
       AND (pv.fecha_hasta IS NULL OR pv.fecha_hasta >= CURRENT_DATE)
     ORDER BY pv.id DESC
     LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.fn_carnaval_precio_base_vigente(BIGINT)
    TO anon, authenticated, service_role;


-- -------------------------------------------------------------
-- Trigger por fila: app_dat_precio_venta -> Carnaval
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sync_price_to_carnaval()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_id_vendedor_app   BIGINT;
    v_id_tienda         BIGINT;
    v_base_price        NUMERIC;
    v_pct_efectivo      NUMERIC;
    v_pct_transferencia NUMERIC;
    v_precio_descuento  NUMERIC;
    v_precio_oficial    NUMERIC;
BEGIN
    IF TG_OP NOT IN ('INSERT', 'UPDATE') THEN
        RETURN NEW;
    END IF;

    -- Cerrar/reabrir fechas (u otros metadatos) NO debe
    -- reescribir Carnaval con el precio de esa fila.
    IF TG_OP = 'UPDATE'
       AND NEW.precio_venta_cup IS NOT DISTINCT FROM OLD.precio_venta_cup
       AND NEW.precio_venta_usd IS NOT DISTINCT FROM OLD.precio_venta_usd
       AND NEW.precio_descuento IS NOT DISTINCT FROM OLD.precio_descuento
    THEN
        RETURN NEW;
    END IF;

    SELECT p.id_vendedor_app, p.id_tienda
      INTO v_id_vendedor_app, v_id_tienda
      FROM public.app_dat_producto p
     WHERE p.id = NEW.id_producto;

    IF v_id_vendedor_app IS NULL THEN
        RETURN NEW;
    END IF;

    -- Siempre el vigente mas reciente por id (no NEW a ciegas).
    v_base_price := public.fn_carnaval_precio_base_vigente(NEW.id_producto);

    IF v_base_price IS NULL OR v_base_price <= 0 THEN
        RETURN NEW;
    END IF;

    SELECT o_pct_efectivo, o_pct_transferencia
      INTO v_pct_efectivo, v_pct_transferencia
      FROM public.fn_carnaval_porcientos_tienda(v_id_tienda);

    IF v_pct_efectivo IS NULL OR v_pct_transferencia IS NULL THEN
        RETURN NEW;
    END IF;

    v_precio_descuento := ROUND(v_base_price * (1 + v_pct_efectivo      / 100));
    v_precio_oficial   := ROUND(v_base_price * (1 + v_pct_transferencia / 100));

    UPDATE carnavalapp."Productos"
       SET price            = v_precio_oficial,
           precio_descuento = v_precio_descuento,
           updated_at       = NOW()
     WHERE id = v_id_vendedor_app
       AND COALESCE(proveedor, 0) <> 3;

    RETURN NEW;
END;
$$;


-- -------------------------------------------------------------
-- Recalculo masivo al cambiar el piso global
-- (trg_update_carnaval_prices sobre precio_global_productos_carnaval)
--
-- Al cambiar porciento_efectivo / porciento_transferencia
-- recalcula TODOS los productos ligados (no proveedor 3),
-- con porciento = GREATEST(tienda, nuevo_global) y base
-- vigente MAX(id).
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_update_carnaval_product_prices()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_actualizados INTEGER := 0;
BEGIN
    WITH productos AS (
        SELECT p.id_vendedor_app,
               public.fn_carnaval_precio_base_vigente(p.id) AS precio_base,
               GREATEST(COALESCE(pg.precio_venta_carnaval,
                                 NEW.porciento_efectivo),
                        NEW.porciento_efectivo)  AS pct_efectivo,
               GREATEST(COALESCE(pg.precio_venta_carnaval_transferencia,
                                 NEW.porciento_transferencia),
                        NEW.porciento_transferencia) AS pct_transferencia
        FROM public.app_dat_producto p
        LEFT JOIN public.app_dat_precio_general_tienda pg
               ON pg.id_tienda = p.id_tienda
        WHERE p.id_vendedor_app IS NOT NULL
          AND p.deleted_at IS NULL
    )
    UPDATE carnavalapp."Productos" cp
       SET price            = ROUND(pr.precio_base * (1 + pr.pct_transferencia / 100)),
           precio_descuento = ROUND(pr.precio_base * (1 + pr.pct_efectivo      / 100)),
           updated_at       = NOW()
      FROM productos pr
     WHERE cp.id = pr.id_vendedor_app
       AND pr.precio_base IS NOT NULL
       AND pr.precio_base > 0
       AND COALESCE(cp.proveedor, 0) <> 3;

    GET DIAGNOSTICS v_actualizados = ROW_COUNT;
    RAISE NOTICE '[piso_global] Productos recalculados: %.', v_actualizados;

    -- updated_at del global no se auto-actualiza en UPDATE;
    -- solo tocamos esa columna para no re-disparar este trigger
    -- (esta definido como UPDATE OF porciento_*).
    UPDATE public.precio_global_productos_carnaval
       SET updated_at = NOW()
     WHERE id = NEW.id;

    RETURN NEW;
END;
$$;


-- Asegura el trigger: dispara al cambiar cualquiera de los
-- dos porcientos globales. Un touch con el mismo valor
-- (SET porciento_efectivo = porciento_efectivo) tambien
-- dispara y fuerza el recalculo de TODOS los ligados.
DROP TRIGGER IF EXISTS trg_update_carnaval_prices
    ON public.precio_global_productos_carnaval;

CREATE TRIGGER trg_update_carnaval_prices
    AFTER UPDATE OF porciento_efectivo, porciento_transferencia
    ON public.precio_global_productos_carnaval
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_update_carnaval_product_prices();


-- =============================================================
-- VERIFICACION
-- =============================================================

-- 1) Helper: 7345 debe devolver 625 (vigente MAX id)
SELECT public.fn_carnaval_precio_base_vigente(7345) AS base_7345_esperada_625;

-- 2) Trigger global apunta a la funcion
SELECT t.tgname, pg_get_triggerdef(t.oid) AS def
FROM pg_trigger t
WHERE t.tgrelid = 'public.precio_global_productos_carnaval'::regclass
  AND NOT t.tgisinternal;

-- 3) Forzar recalculo global (descomentar para sanear Carnaval):
-- UPDATE public.precio_global_productos_carnaval
--    SET porciento_efectivo      = porciento_efectivo,
--        porciento_transferencia = porciento_transferencia
--  WHERE id = 1;
--
-- Luego comprobar 7345:
-- SELECT cp.price, cp.precio_descuento, cp.updated_at
-- FROM carnavalapp."Productos" cp
-- WHERE cp.id = 1839;
-- -- esperado: 681 / 681
