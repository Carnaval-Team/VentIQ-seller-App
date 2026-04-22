-- ============================================================================
-- RPC Functions: Warehouse Valuation
-- ============================================================================
-- Provides inventory valuation (cost, sale, profit) in USD and CUP at three
-- levels:
--   1. fn_warehouses_valuation_summary  -> per tienda: totals + per-warehouse
--   2. fn_warehouse_valuation_zones     -> per almacen: totals + per-zone
--   3. fn_zone_valuation_products       -> per zona (layout): totals + per-product
--
-- Pricing source:
--   * precio_venta_cup  : latest row in app_dat_precio_venta for (producto, variante)
--   * precio_costo_usd  : latest app_dat_producto_presentacion.precio_promedio
--   * tasa_usd_cup      : tasa_cambio_extraoficial (by tienda) -> fallback tasas_conversion
--
-- Current stock source:
--   * app_dat_inventario_productos
--     Latest row per (id_producto, id_variante, id_opcion_variante,
--     id_presentacion, id_ubicacion) using ORDER BY id DESC (cantidad_final).
-- ============================================================================


-- ---------------------------------------------------------------------------
-- Helper: current rate USD -> CUP for a given tienda
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_get_usd_cup_rate(p_id_tienda BIGINT)
RETURNS NUMERIC
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(
        (
            SELECT tce.valor_cambio
            FROM tasa_cambio_extraoficial tce
            WHERE tce.id_tienda = p_id_tienda
              AND tce.activo = TRUE
              AND tce.id_moneda_origen = 2
              AND tce.id_moneda_destino = 1
              AND COALESCE(tce.usar_precio_toque, FALSE) = FALSE
              AND tce.valor_cambio IS NOT NULL
              AND tce.valor_cambio > 0
            ORDER BY tce.created_at DESC
            LIMIT 1
        ),
        (
            SELECT tc.tasa
            FROM tasas_conversion tc
            WHERE tc.moneda_origen = 'USD'
              AND tc.moneda_destino = 'CUP'
            ORDER BY tc.fecha_actualizacion DESC
            LIMIT 1
        ),
        1
    );
$$;


-- ---------------------------------------------------------------------------
-- Core valuation row: for a given tienda, returns one row per
-- (almacen, layout/zona, producto, variante, presentacion) with
-- current stock and cost/sale/profit in USD & CUP.
-- ---------------------------------------------------------------------------
-- Implemented as a SQL function that can be re-used by the three public RPCs.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_inventory_valuation_rows(p_id_tienda BIGINT)
RETURNS TABLE (
    id_almacen          BIGINT,
    almacen_nombre      VARCHAR,
    id_layout           BIGINT,
    layout_nombre       VARCHAR,
    id_layout_padre     BIGINT,
    id_producto         BIGINT,
    producto_nombre     VARCHAR,
    sku                 VARCHAR,
    id_variante         BIGINT,
    id_opcion_variante  BIGINT,
    id_presentacion     BIGINT,
    cantidad            NUMERIC,
    precio_costo_usd    NUMERIC,
    precio_costo_cup    NUMERIC,
    precio_venta_cup    NUMERIC,
    precio_venta_usd    NUMERIC,
    tasa                NUMERIC,
    valor_costo_usd     NUMERIC,
    valor_costo_cup     NUMERIC,
    valor_venta_usd     NUMERIC,
    valor_venta_cup     NUMERIC,
    ganancia_usd        NUMERIC,
    ganancia_cup        NUMERIC
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_tasa NUMERIC;
BEGIN
    v_tasa := public.fn_get_usd_cup_rate(p_id_tienda);
    IF v_tasa IS NULL OR v_tasa <= 0 THEN
        v_tasa := 1;
    END IF;

    RETURN QUERY
    WITH latest_inv AS (
        -- Latest inventario row per (producto, variante, opcion, presentacion, ubicacion)
        SELECT DISTINCT ON (
            ip.id_producto,
            COALESCE(ip.id_variante, 0),
            COALESCE(ip.id_opcion_variante, 0),
            ip.id_presentacion,
            ip.id_ubicacion
        )
            ip.id_producto,
            ip.id_variante,
            ip.id_opcion_variante,
            ip.id_presentacion,
            ip.id_ubicacion,
            ip.cantidad_final
        FROM app_dat_inventario_productos ip
        WHERE ip.id_ubicacion IS NOT NULL
        ORDER BY
            ip.id_producto,
            COALESCE(ip.id_variante, 0),
            COALESCE(ip.id_opcion_variante, 0),
            ip.id_presentacion,
            ip.id_ubicacion,
            ip.id DESC
    ),
    latest_precio AS (
        SELECT DISTINCT ON (pv.id_producto, COALESCE(pv.id_variante, 0))
            pv.id_producto,
            pv.id_variante,
            pv.precio_venta_cup
        FROM app_dat_precio_venta pv
        ORDER BY pv.id_producto, COALESCE(pv.id_variante, 0), pv.created_at DESC
    ),
    latest_costo AS (
        SELECT DISTINCT ON (pp.id_producto, pp.id_presentacion)
            pp.id_producto,
            pp.id_presentacion,
            pp.precio_promedio
        FROM app_dat_producto_presentacion pp
        WHERE pp.precio_promedio IS NOT NULL AND pp.precio_promedio > 0
        ORDER BY pp.id_producto, pp.id_presentacion, pp.created_at DESC
    ),
    latest_costo_fallback AS (
        -- Fallback: any presentation (most recent) if the product's presentation has no price
        SELECT DISTINCT ON (pp.id_producto)
            pp.id_producto,
            pp.precio_promedio
        FROM app_dat_producto_presentacion pp
        WHERE pp.precio_promedio IS NOT NULL AND pp.precio_promedio > 0
        ORDER BY pp.id_producto, pp.created_at DESC
    )
    SELECT
        a.id                         AS id_almacen,
        a.denominacion               AS almacen_nombre,
        la.id                        AS id_layout,
        la.denominacion              AS layout_nombre,
        la.id_layout_padre           AS id_layout_padre,
        p.id                         AS id_producto,
        p.denominacion               AS producto_nombre,
        p.sku                        AS sku,
        li.id_variante               AS id_variante,
        li.id_opcion_variante        AS id_opcion_variante,
        li.id_presentacion           AS id_presentacion,
        COALESCE(li.cantidad_final, 0)                                   AS cantidad,
        COALESCE(lc.precio_promedio, lcf.precio_promedio, 0)::NUMERIC    AS precio_costo_usd,
        (COALESCE(lc.precio_promedio, lcf.precio_promedio, 0) * v_tasa)  AS precio_costo_cup,
        COALESCE(lp.precio_venta_cup, 0)                                 AS precio_venta_cup,
        (COALESCE(lp.precio_venta_cup, 0) / NULLIF(v_tasa, 0))           AS precio_venta_usd,
        v_tasa                                                           AS tasa,
        -- Valor de costo total (stock * costo)
        (COALESCE(li.cantidad_final, 0) * COALESCE(lc.precio_promedio, lcf.precio_promedio, 0))                  AS valor_costo_usd,
        (COALESCE(li.cantidad_final, 0) * COALESCE(lc.precio_promedio, lcf.precio_promedio, 0) * v_tasa)         AS valor_costo_cup,
        -- Valor de venta total (stock * precio venta)
        (COALESCE(li.cantidad_final, 0) * (COALESCE(lp.precio_venta_cup, 0) / NULLIF(v_tasa, 0)))                AS valor_venta_usd,
        (COALESCE(li.cantidad_final, 0) * COALESCE(lp.precio_venta_cup, 0))                                      AS valor_venta_cup,
        -- Ganancia (venta - costo) * stock
        (COALESCE(li.cantidad_final, 0) * ((COALESCE(lp.precio_venta_cup, 0) / NULLIF(v_tasa, 0)) - COALESCE(lc.precio_promedio, lcf.precio_promedio, 0)))        AS ganancia_usd,
        (COALESCE(li.cantidad_final, 0) * (COALESCE(lp.precio_venta_cup, 0) - (COALESCE(lc.precio_promedio, lcf.precio_promedio, 0) * v_tasa)))                    AS ganancia_cup
    FROM latest_inv li
    JOIN app_dat_layout_almacen la ON la.id = li.id_ubicacion AND la.deleted_at IS NULL
    JOIN app_dat_almacen a         ON a.id = la.id_almacen AND a.deleted_at IS NULL
    JOIN app_dat_producto p        ON p.id = li.id_producto
    LEFT JOIN latest_precio lp
           ON lp.id_producto = li.id_producto
          AND COALESCE(lp.id_variante, 0) = COALESCE(li.id_variante, 0)
    LEFT JOIN latest_costo lc
           ON lc.id_producto = li.id_producto
          AND lc.id_presentacion = li.id_presentacion
    LEFT JOIN latest_costo_fallback lcf
           ON lcf.id_producto = li.id_producto
    WHERE a.id_tienda = p_id_tienda
      AND COALESCE(li.cantidad_final, 0) > 0;
END;
$$;


-- ---------------------------------------------------------------------------
-- 1) Summary for the whole tienda: totals + breakdown per warehouse
-- ---------------------------------------------------------------------------
-- Returns JSON:
-- {
--   "tasa": number,
--   "totales": { valor_costo_usd, valor_costo_cup, valor_venta_usd,
--                valor_venta_cup, ganancia_usd, ganancia_cup, productos },
--   "almacenes": [
--      { id_almacen, nombre, total_productos, valor_costo_usd, valor_costo_cup,
--        valor_venta_usd, valor_venta_cup, ganancia_usd, ganancia_cup }
--   ]
-- }
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_warehouses_valuation_summary(p_id_tienda BIGINT)
RETURNS JSON
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_result JSON;
    v_tasa NUMERIC;
BEGIN
    v_tasa := public.fn_get_usd_cup_rate(p_id_tienda);

    WITH rows AS (
        SELECT * FROM public.fn_inventory_valuation_rows(p_id_tienda)
    ),
    per_almacen AS (
        SELECT
            r.id_almacen,
            r.almacen_nombre,
            COUNT(DISTINCT r.id_producto)                      AS total_productos,
            COALESCE(SUM(r.valor_costo_usd), 0)                AS valor_costo_usd,
            COALESCE(SUM(r.valor_costo_cup), 0)                AS valor_costo_cup,
            COALESCE(SUM(r.valor_venta_usd), 0)                AS valor_venta_usd,
            COALESCE(SUM(r.valor_venta_cup), 0)                AS valor_venta_cup,
            COALESCE(SUM(r.ganancia_usd), 0)                   AS ganancia_usd,
            COALESCE(SUM(r.ganancia_cup), 0)                   AS ganancia_cup
        FROM rows r
        GROUP BY r.id_almacen, r.almacen_nombre
    ),
    all_warehouses AS (
        -- Include warehouses with no stock so the UI shows them with zeros
        SELECT a.id AS id_almacen, a.denominacion AS almacen_nombre
        FROM app_dat_almacen a
        WHERE a.id_tienda = p_id_tienda
          AND a.deleted_at IS NULL
    ),
    merged AS (
        SELECT
            w.id_almacen,
            w.almacen_nombre,
            COALESCE(pa.total_productos, 0)   AS total_productos,
            COALESCE(pa.valor_costo_usd, 0)   AS valor_costo_usd,
            COALESCE(pa.valor_costo_cup, 0)   AS valor_costo_cup,
            COALESCE(pa.valor_venta_usd, 0)   AS valor_venta_usd,
            COALESCE(pa.valor_venta_cup, 0)   AS valor_venta_cup,
            COALESCE(pa.ganancia_usd, 0)      AS ganancia_usd,
            COALESCE(pa.ganancia_cup, 0)      AS ganancia_cup
        FROM all_warehouses w
        LEFT JOIN per_almacen pa ON pa.id_almacen = w.id_almacen
    )
    SELECT json_build_object(
        'tasa', v_tasa,
        'totales', json_build_object(
            'valor_costo_usd', COALESCE(SUM(valor_costo_usd), 0),
            'valor_costo_cup', COALESCE(SUM(valor_costo_cup), 0),
            'valor_venta_usd', COALESCE(SUM(valor_venta_usd), 0),
            'valor_venta_cup', COALESCE(SUM(valor_venta_cup), 0),
            'ganancia_usd',    COALESCE(SUM(ganancia_usd), 0),
            'ganancia_cup',    COALESCE(SUM(ganancia_cup), 0),
            'productos',       COALESCE(SUM(total_productos), 0)
        ),
        'almacenes', COALESCE(
            (
                SELECT json_agg(
                    json_build_object(
                        'id_almacen',       m.id_almacen,
                        'nombre',           m.almacen_nombre,
                        'total_productos',  m.total_productos,
                        'valor_costo_usd',  m.valor_costo_usd,
                        'valor_costo_cup',  m.valor_costo_cup,
                        'valor_venta_usd',  m.valor_venta_usd,
                        'valor_venta_cup',  m.valor_venta_cup,
                        'ganancia_usd',     m.ganancia_usd,
                        'ganancia_cup',     m.ganancia_cup
                    )
                    ORDER BY m.almacen_nombre
                )
                FROM merged m
            ),
            '[]'::json
        )
    )
    INTO v_result
    FROM merged;

    RETURN v_result;
END;
$$;


-- ---------------------------------------------------------------------------
-- 2) Per-warehouse: totals + breakdown per zone (layout)
-- ---------------------------------------------------------------------------
-- Returns JSON:
-- {
--   "tasa": ...,
--   "almacen": { id, nombre },
--   "totales": { valor_costo_usd, ..., productos },
--   "zonas": [
--     { id_layout, nombre, id_layout_padre, total_productos, valor_costo_usd,
--       valor_costo_cup, valor_venta_usd, valor_venta_cup,
--       ganancia_usd, ganancia_cup }
--   ]
-- }
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_warehouse_valuation_zones(
    p_id_tienda  BIGINT,
    p_id_almacen BIGINT
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_result JSON;
    v_tasa   NUMERIC;
BEGIN
    v_tasa := public.fn_get_usd_cup_rate(p_id_tienda);

    WITH rows AS (
        SELECT *
        FROM public.fn_inventory_valuation_rows(p_id_tienda)
        WHERE id_almacen = p_id_almacen
    ),
    per_zone AS (
        SELECT
            r.id_layout,
            r.layout_nombre,
            r.id_layout_padre,
            COUNT(DISTINCT r.id_producto)                       AS total_productos,
            COALESCE(SUM(r.valor_costo_usd), 0)                 AS valor_costo_usd,
            COALESCE(SUM(r.valor_costo_cup), 0)                 AS valor_costo_cup,
            COALESCE(SUM(r.valor_venta_usd), 0)                 AS valor_venta_usd,
            COALESCE(SUM(r.valor_venta_cup), 0)                 AS valor_venta_cup,
            COALESCE(SUM(r.ganancia_usd), 0)                    AS ganancia_usd,
            COALESCE(SUM(r.ganancia_cup), 0)                    AS ganancia_cup
        FROM rows r
        GROUP BY r.id_layout, r.layout_nombre, r.id_layout_padre
    ),
    all_zones AS (
        SELECT la.id AS id_layout,
               la.denominacion AS layout_nombre,
               la.id_layout_padre
        FROM app_dat_layout_almacen la
        WHERE la.id_almacen = p_id_almacen
          AND la.deleted_at IS NULL
    ),
    merged AS (
        SELECT
            z.id_layout,
            z.layout_nombre,
            z.id_layout_padre,
            COALESCE(pz.total_productos, 0) AS total_productos,
            COALESCE(pz.valor_costo_usd, 0) AS valor_costo_usd,
            COALESCE(pz.valor_costo_cup, 0) AS valor_costo_cup,
            COALESCE(pz.valor_venta_usd, 0) AS valor_venta_usd,
            COALESCE(pz.valor_venta_cup, 0) AS valor_venta_cup,
            COALESCE(pz.ganancia_usd, 0)    AS ganancia_usd,
            COALESCE(pz.ganancia_cup, 0)    AS ganancia_cup
        FROM all_zones z
        LEFT JOIN per_zone pz ON pz.id_layout = z.id_layout
    )
    SELECT json_build_object(
        'tasa', v_tasa,
        'almacen', (
            SELECT json_build_object('id', a.id, 'nombre', a.denominacion)
            FROM app_dat_almacen a
            WHERE a.id = p_id_almacen
        ),
        'totales', json_build_object(
            'valor_costo_usd', COALESCE(SUM(valor_costo_usd), 0),
            'valor_costo_cup', COALESCE(SUM(valor_costo_cup), 0),
            'valor_venta_usd', COALESCE(SUM(valor_venta_usd), 0),
            'valor_venta_cup', COALESCE(SUM(valor_venta_cup), 0),
            'ganancia_usd',    COALESCE(SUM(ganancia_usd), 0),
            'ganancia_cup',    COALESCE(SUM(ganancia_cup), 0),
            'productos',       COALESCE(SUM(total_productos), 0)
        ),
        'zonas', COALESCE(
            (
                SELECT json_agg(
                    json_build_object(
                        'id_layout',        m.id_layout,
                        'nombre',           m.layout_nombre,
                        'id_layout_padre',  m.id_layout_padre,
                        'total_productos',  m.total_productos,
                        'valor_costo_usd',  m.valor_costo_usd,
                        'valor_costo_cup',  m.valor_costo_cup,
                        'valor_venta_usd',  m.valor_venta_usd,
                        'valor_venta_cup',  m.valor_venta_cup,
                        'ganancia_usd',     m.ganancia_usd,
                        'ganancia_cup',     m.ganancia_cup
                    )
                    ORDER BY m.layout_nombre
                )
                FROM merged m
            ),
            '[]'::json
        )
    )
    INTO v_result
    FROM merged;

    RETURN v_result;
END;
$$;


-- ---------------------------------------------------------------------------
-- 3) Per-zone: totals + breakdown per product
-- ---------------------------------------------------------------------------
-- Returns JSON:
-- {
--   "tasa": ...,
--   "zona": { id_layout, nombre, id_almacen, almacen_nombre },
--   "totales": { ... },
--   "productos": [
--     { id_producto, nombre, sku, cantidad, precio_costo_usd,
--       precio_costo_cup, precio_venta_usd, precio_venta_cup,
--       valor_costo_usd, valor_costo_cup, valor_venta_usd, valor_venta_cup,
--       ganancia_usd, ganancia_cup }
--   ]
-- }
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_zone_valuation_products(
    p_id_tienda BIGINT,
    p_id_layout BIGINT
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_result JSON;
    v_tasa   NUMERIC;
BEGIN
    v_tasa := public.fn_get_usd_cup_rate(p_id_tienda);

    WITH rows AS (
        SELECT *
        FROM public.fn_inventory_valuation_rows(p_id_tienda)
        WHERE id_layout = p_id_layout
    ),
    per_product AS (
        -- Aggregate possible multiple variantes/presentaciones of the same producto
        SELECT
            r.id_producto,
            MAX(r.producto_nombre)       AS nombre,
            MAX(r.sku)                   AS sku,
            SUM(r.cantidad)              AS cantidad,
            -- Use weighted averages for unit prices when multiple rows exist
            CASE WHEN SUM(r.cantidad) > 0
                 THEN SUM(r.valor_costo_usd) / NULLIF(SUM(r.cantidad), 0)
                 ELSE MAX(r.precio_costo_usd)
            END AS precio_costo_usd,
            CASE WHEN SUM(r.cantidad) > 0
                 THEN SUM(r.valor_costo_cup) / NULLIF(SUM(r.cantidad), 0)
                 ELSE MAX(r.precio_costo_cup)
            END AS precio_costo_cup,
            CASE WHEN SUM(r.cantidad) > 0
                 THEN SUM(r.valor_venta_usd) / NULLIF(SUM(r.cantidad), 0)
                 ELSE MAX(r.precio_venta_usd)
            END AS precio_venta_usd,
            CASE WHEN SUM(r.cantidad) > 0
                 THEN SUM(r.valor_venta_cup) / NULLIF(SUM(r.cantidad), 0)
                 ELSE MAX(r.precio_venta_cup)
            END AS precio_venta_cup,
            SUM(r.valor_costo_usd)       AS valor_costo_usd,
            SUM(r.valor_costo_cup)       AS valor_costo_cup,
            SUM(r.valor_venta_usd)       AS valor_venta_usd,
            SUM(r.valor_venta_cup)       AS valor_venta_cup,
            SUM(r.ganancia_usd)          AS ganancia_usd,
            SUM(r.ganancia_cup)          AS ganancia_cup
        FROM rows r
        GROUP BY r.id_producto
    )
    SELECT json_build_object(
        'tasa', v_tasa,
        'zona', (
            SELECT json_build_object(
                'id_layout',       la.id,
                'nombre',          la.denominacion,
                'id_almacen',      la.id_almacen,
                'almacen_nombre',  a.denominacion
            )
            FROM app_dat_layout_almacen la
            JOIN app_dat_almacen a ON a.id = la.id_almacen
            WHERE la.id = p_id_layout
        ),
        'totales', json_build_object(
            'valor_costo_usd', COALESCE(SUM(valor_costo_usd), 0),
            'valor_costo_cup', COALESCE(SUM(valor_costo_cup), 0),
            'valor_venta_usd', COALESCE(SUM(valor_venta_usd), 0),
            'valor_venta_cup', COALESCE(SUM(valor_venta_cup), 0),
            'ganancia_usd',    COALESCE(SUM(ganancia_usd), 0),
            'ganancia_cup',    COALESCE(SUM(ganancia_cup), 0),
            'productos',       COALESCE(COUNT(*), 0)
        ),
        'productos', COALESCE(
            (
                SELECT json_agg(
                    json_build_object(
                        'id_producto',       pp.id_producto,
                        'nombre',            pp.nombre,
                        'sku',               pp.sku,
                        'cantidad',          pp.cantidad,
                        'precio_costo_usd',  pp.precio_costo_usd,
                        'precio_costo_cup',  pp.precio_costo_cup,
                        'precio_venta_usd',  pp.precio_venta_usd,
                        'precio_venta_cup',  pp.precio_venta_cup,
                        'valor_costo_usd',   pp.valor_costo_usd,
                        'valor_costo_cup',   pp.valor_costo_cup,
                        'valor_venta_usd',   pp.valor_venta_usd,
                        'valor_venta_cup',   pp.valor_venta_cup,
                        'ganancia_usd',      pp.ganancia_usd,
                        'ganancia_cup',      pp.ganancia_cup
                    )
                    ORDER BY pp.nombre
                )
                FROM per_product pp
            ),
            '[]'::json
        )
    )
    INTO v_result
    FROM per_product;

    RETURN v_result;
END;
$$;


-- ---------------------------------------------------------------------------
-- Grants (Supabase typically exposes functions to the `anon` and `authenticated` roles)
-- ---------------------------------------------------------------------------
GRANT EXECUTE ON FUNCTION public.fn_get_usd_cup_rate(BIGINT)                            TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_inventory_valuation_rows(BIGINT)                    TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_warehouses_valuation_summary(BIGINT)                TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_warehouse_valuation_zones(BIGINT, BIGINT)           TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.fn_zone_valuation_products(BIGINT, BIGINT)             TO anon, authenticated;
