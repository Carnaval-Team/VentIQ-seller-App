-- RPCs: Productos Carnaval - Inventtia
--
-- Contiene:
-- 1) fn_carnaval_inventtia_kpis(p_id_tienda)
-- 2) fn_carnaval_inventtia_stock_page(p_id_tienda, p_limit, p_offset, p_search)
-- 3) fn_carnaval_inventtia_prices_page(p_id_tienda, p_limit, p_offset, p_search)
-- 4) fn_carnaval_update_product_stock(p_carnaval_product_id, p_new_stock)
-- 5) fn_carnaval_update_product_prices(p_carnaval_product_id, p_precio_descuento, p_price)
--
-- NOTAS:
-- - Usa "relation_products_carnaval" para decidir si el inventario debe filtrarse por (id_producto,id_ubicacion)
-- - Stock inventtia se toma de app_dat_inventario_productos.cantidad_final del registro mas reciente (created_at desc)
-- - Precio inventtia se toma de app_dat_precio_venta.precio_venta_cup del registro mas reciente (created_at desc)
-- - Precio carnaval se toma de carnavalapp."Productos".precio_descuento y carnavalapp."Productos".price
-- - Regla de precios OK/MAL:
--   * tienda 1 o 177: OK si diff% == 0
--   * resto: OK si diff% entre 5 y 6 (inclusive)

-- ============================================================
-- 1) KPI
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_carnaval_inventtia_kpis(
  p_id_tienda bigint
)
RETURNS TABLE (
  total_productos_sincronizados bigint,
  total_productos_precio_mal bigint,
  total_productos_stock_diferente bigint
)
LANGUAGE sql
STABLE
AS $$
WITH base AS (
  SELECT
    p.id AS id_producto,
    p.id_tienda,
    p.id_vendedor_app AS carnaval_product_id,
    p.denominacion,
    p.sku,
    rpc.id_ubicacion AS carnaval_id_ubicacion
  FROM public.app_dat_producto p
  LEFT JOIN public.relation_products_carnaval rpc
    ON rpc.id_producto = p.id
  WHERE p.id_tienda = p_id_tienda
    AND p.deleted_at IS NULL
), inv_stock AS (
  SELECT
    b.id_producto,
    (
      SELECT ip.cantidad_final
      FROM public.app_dat_inventario_productos ip
      WHERE ip.id_producto = b.id_producto
        AND (b.carnaval_id_ubicacion IS NULL OR ip.id_ubicacion = b.carnaval_id_ubicacion)
      ORDER BY ip.created_at DESC
      LIMIT 1
    ) AS stock_inventtia
  FROM base b
), inv_price AS (
  SELECT
    b.id_producto,
    (
      SELECT pv.precio_venta_cup
      FROM public.app_dat_precio_venta pv
      WHERE pv.id_producto = b.id_producto
      ORDER BY pv.created_at DESC
      LIMIT 1
    ) AS precio_inventtia
  FROM base b
), carnaval AS (
  SELECT
    b.id_producto,
    cp.id AS carnaval_product_id,
    cp.stock AS stock_carnaval,
    cp.precio_descuento AS precio_carnaval_descuento,
    cp.price AS precio_carnaval_price
  FROM base b
  LEFT JOIN carnavalapp."Productos" cp
    ON cp.id = b.carnaval_product_id
)
SELECT
  COUNT(*) FILTER (WHERE base.carnaval_product_id IS NOT NULL) AS total_productos_sincronizados,
  COUNT(*) FILTER (
    WHERE base.carnaval_product_id IS NOT NULL
      AND (
        CASE
          WHEN p_id_tienda IN (1, 177) THEN
            -- OK si diff% == 0
            COALESCE(
              CASE
                WHEN NULLIF(inv_price.precio_inventtia, 0) IS NULL THEN NULL
                ELSE ABS((carnaval.precio_carnaval_descuento - inv_price.precio_inventtia) / NULLIF(inv_price.precio_inventtia, 0)) * 100
              END,
              0
            ) <> 0
          ELSE
            -- OK si 5..6
            NOT (
              COALESCE(
                CASE
                  WHEN NULLIF(inv_price.precio_inventtia, 0) IS NULL THEN NULL
                  ELSE ABS((carnaval.precio_carnaval_descuento - inv_price.precio_inventtia) / NULLIF(inv_price.precio_inventtia, 0)) * 100
                END,
                0
              ) BETWEEN 5 AND 6
            )
        END
      )
  ) AS total_productos_precio_mal,
  COUNT(*) FILTER (
    WHERE base.carnaval_product_id IS NOT NULL
      AND COALESCE(inv_stock.stock_inventtia, 0) <> COALESCE(carnaval.stock_carnaval, 0)
  ) AS total_productos_stock_diferente
FROM base
LEFT JOIN inv_stock ON inv_stock.id_producto = base.id_producto
LEFT JOIN inv_price ON inv_price.id_producto = base.id_producto
LEFT JOIN carnaval ON carnaval.id_producto = base.id_producto;
$$;

-- ============================================================
-- 2) Stock page
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_carnaval_inventtia_stock_page(
  p_id_tienda bigint,
  p_limit integer,
  p_offset integer,
  p_search text DEFAULT ''
)
RETURNS TABLE (
  total_count bigint,
  id_producto bigint,
  sku text,
  denominacion text,
  carnaval_product_id bigint,
  stock_inventtia numeric,
  stock_carnaval bigint,
  diff_stock numeric
)
LANGUAGE sql
STABLE
AS $$
WITH base AS (
  SELECT
    p.id AS id_producto,
    p.id_tienda,
    p.id_vendedor_app AS carnaval_product_id,
    p.denominacion,
    p.sku,
    rpc.id_ubicacion AS carnaval_id_ubicacion
  FROM public.app_dat_producto p
  LEFT JOIN public.relation_products_carnaval rpc
    ON rpc.id_producto = p.id
  WHERE p.id_tienda = p_id_tienda
    AND p.deleted_at IS NULL
    AND (
      p_search IS NULL
      OR p_search = ''
      OR p.denominacion ILIKE '%' || p_search || '%'
      OR COALESCE(p.sku, '') ILIKE '%' || p_search || '%'
    )
), enriched AS (
  SELECT
    b.*,
    (
      SELECT ip.cantidad_final
      FROM public.app_dat_inventario_productos ip
      WHERE ip.id_producto = b.id_producto
        AND (b.carnaval_id_ubicacion IS NULL OR ip.id_ubicacion = b.carnaval_id_ubicacion)
      ORDER BY ip.created_at DESC
      LIMIT 1
    ) AS stock_inventtia,
    cp.stock AS stock_carnaval
  FROM base b
  LEFT JOIN carnavalapp."Productos" cp
    ON cp.id = b.carnaval_product_id
)
SELECT
  (SELECT COUNT(*) FROM enriched) AS total_count,
  e.id_producto,
  e.sku,
  e.denominacion,
  e.carnaval_product_id,
  COALESCE(e.stock_inventtia, 0) AS stock_inventtia,
  COALESCE(e.stock_carnaval, 0) AS stock_carnaval,
  COALESCE(e.stock_inventtia, 0) - COALESCE(e.stock_carnaval, 0) AS diff_stock
FROM enriched e
ORDER BY e.denominacion
LIMIT p_limit
OFFSET p_offset;
$$;

-- ============================================================
-- 3) Prices page
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_carnaval_inventtia_prices_page(
  p_id_tienda bigint,
  p_limit integer,
  p_offset integer,
  p_search text DEFAULT ''
)
RETURNS TABLE (
  total_count bigint,
  id_producto bigint,
  sku text,
  denominacion text,
  carnaval_product_id bigint,
  precio_inventtia numeric,
  precio_carnaval_descuento numeric,
  precio_carnaval_price numeric,
  diff_percent_descuento numeric,
  diff_percent_price numeric,
  is_mal_precio boolean
)
LANGUAGE sql
STABLE
AS $$
WITH base AS (
  SELECT
    p.id AS id_producto,
    p.id_tienda,
    p.id_vendedor_app AS carnaval_product_id,
    p.denominacion,
    p.sku
  FROM public.app_dat_producto p
  WHERE p.id_tienda = p_id_tienda
    AND p.deleted_at IS NULL
    AND (
      p_search IS NULL
      OR p_search = ''
      OR p.denominacion ILIKE '%' || p_search || '%'
      OR COALESCE(p.sku, '') ILIKE '%' || p_search || '%'
    )
), enriched AS (
  SELECT
    b.*,
    (
      SELECT pv.precio_venta_cup
      FROM public.app_dat_precio_venta pv
      WHERE pv.id_producto = b.id_producto
      ORDER BY pv.created_at DESC
      LIMIT 1
    ) AS precio_inventtia,
    cp.precio_descuento AS precio_carnaval_descuento,
    cp.price AS precio_carnaval_price
  FROM base b
  LEFT JOIN carnavalapp."Productos" cp
    ON cp.id = b.carnaval_product_id
), calc AS (
  SELECT
    e.*,
    CASE
      WHEN NULLIF(e.precio_inventtia, 0) IS NULL THEN NULL
      ELSE ABS((e.precio_carnaval_descuento - e.precio_inventtia) / NULLIF(e.precio_inventtia, 0)) * 100
    END AS diff_percent_descuento,
    CASE
      WHEN NULLIF(e.precio_inventtia, 0) IS NULL THEN NULL
      ELSE ABS((e.precio_carnaval_price - e.precio_inventtia) / NULLIF(e.precio_inventtia, 0)) * 100
    END AS diff_percent_price
  FROM enriched e
)
SELECT
  (SELECT COUNT(*) FROM calc) AS total_count,
  c.id_producto,
  c.sku,
  c.denominacion,
  c.carnaval_product_id,
  COALESCE(c.precio_inventtia, 0) AS precio_inventtia,
  COALESCE(c.precio_carnaval_descuento, 0) AS precio_carnaval_descuento,
  COALESCE(c.precio_carnaval_price, 0) AS precio_carnaval_price,
  c.diff_percent_descuento,
  c.diff_percent_price,
  CASE
    WHEN c.carnaval_product_id IS NULL THEN true
    WHEN p_id_tienda IN (1, 177) THEN COALESCE(c.diff_percent_descuento, 0) <> 0
    ELSE NOT (COALESCE(c.diff_percent_descuento, 0) BETWEEN 5 AND 6)
  END AS is_mal_precio
FROM calc c
ORDER BY c.denominacion
LIMIT p_limit
OFFSET p_offset;
$$;

-- ============================================================
-- 4) Update stock (Carnaval)
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_carnaval_update_product_stock(
  p_carnaval_product_id bigint,
  p_new_stock bigint
)
RETURNS void
LANGUAGE sql
VOLATILE
AS $$
UPDATE carnavalapp."Productos"
SET stock = p_new_stock
WHERE id = p_carnaval_product_id;
$$;

-- ============================================================
-- 5) Update prices (Carnaval)
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_carnaval_update_product_prices(
  p_carnaval_product_id bigint,
  p_precio_descuento numeric,
  p_price numeric
)
RETURNS void
LANGUAGE sql
VOLATILE
AS $$
UPDATE carnavalapp."Productos"
SET precio_descuento = p_precio_descuento,
    price = p_price
WHERE id = p_carnaval_product_id;
$$;
