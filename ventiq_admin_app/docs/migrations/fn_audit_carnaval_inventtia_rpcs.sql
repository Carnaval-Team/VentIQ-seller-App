-- Auditoría Carnaval ↔ Inventtia
-- Dos RPCs: uno lee líneas Carnaval; otro lee extracciones Inventtia
-- vinculadas a esas órdenes.
--
-- Aplicar en Supabase SQL Editor (MCP está en solo lectura).
--
-- NOTA: la versión anterior de fn_audit_inventtia_carnaval_lines usaba
-- ILIKE '%...%' por cada order_id y hacía timeout sobre ~140k operaciones.
-- Esta versión usa:
--   1) id_carnaval_order = ANY(...)
--   2) igualdad exacta observaciones = 'Venta desde orden {id}'

-- Índices recomendados (idempotentes)
CREATE INDEX IF NOT EXISTS idx_operaciones_id_carnaval_order
  ON public.app_dat_operaciones (id_carnaval_order)
  WHERE id_carnaval_order IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_operaciones_obs_venta_carnaval
  ON public.app_dat_operaciones (observaciones)
  WHERE observaciones LIKE 'Venta desde orden %';

CREATE OR REPLACE FUNCTION public.fn_audit_carnaval_order_lines(
  p_proveedor_id bigint DEFAULT NULL,
  p_fecha_desde date DEFAULT NULL,
  p_fecha_hasta timestamptz DEFAULT NULL,
  p_status text DEFAULT NULL,
  p_exclude_cancelled boolean DEFAULT true
)
RETURNS TABLE (
  order_id bigint,
  order_status text,
  order_created_at date,
  carnaval_product_id bigint,
  product_name text,
  proveedor_id smallint,
  qty_carnaval numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, carnavalapp
AS $$
  SELECT
    o.id::bigint AS order_id,
    o.status::text AS order_status,
    o.created_at::date AS order_created_at,
    od.product_id::bigint AS carnaval_product_id,
    COALESCE(p.name, 'Producto #' || od.product_id::text)::text AS product_name,
    od.proveedor AS proveedor_id,
    SUM(COALESCE(od.quantity, 0)::numeric) AS qty_carnaval
  FROM carnavalapp."Orders" o
  JOIN carnavalapp."OrderDetails" od ON od.order_id = o.id
  LEFT JOIN carnavalapp."Productos" p ON p.id = od.product_id
  WHERE
    (p_exclude_cancelled IS DISTINCT FROM TRUE
      OR lower(COALESCE(o.status, '')) <> 'cancelado')
    AND (
      p_status IS NULL
      OR (
        p_status = 'Nuevo'
        AND o.status IN ('Nuevo', 'En Revision', 'Pendiente de Pago')
      )
      OR (p_status IS DISTINCT FROM 'Nuevo' AND o.status = p_status)
    )
    AND (p_fecha_desde IS NULL OR o.created_at::date >= p_fecha_desde)
    AND (p_fecha_hasta IS NULL OR o.created_at <= p_fecha_hasta)
    AND (
      p_proveedor_id IS NULL
      OR od.proveedor = p_proveedor_id
      OR (
        o.proveedores IS NOT NULL
        AND o.proveedores @> ARRAY[p_proveedor_id::smallint]
      )
    )
  GROUP BY
    o.id, o.status, o.created_at, od.product_id, p.name, od.proveedor
  ORDER BY o.id DESC, od.product_id;
$$;

COMMENT ON FUNCTION public.fn_audit_carnaval_order_lines IS
  'Auditoría: líneas agregadas de órdenes Carnaval (OrderDetails) para comparar vs Inventtia.';

CREATE OR REPLACE FUNCTION public.fn_audit_inventtia_carnaval_lines(
  p_order_ids bigint[],
  p_id_tienda bigint DEFAULT NULL
)
RETURNS TABLE (
  order_id bigint,
  carnaval_product_id bigint,
  inventtia_product_id bigint,
  product_name text,
  qty_inventtia numeric,
  operation_ids bigint[]
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_order_ids IS NULL OR cardinality(p_order_ids) = 0 THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH wanted AS (
    SELECT DISTINCT oid AS order_id
    FROM unnest(p_order_ids) AS oid
  ),
  -- 1) Match rápido por FK id_carnaval_order
  ops_by_fk AS (
    SELECT
      o.id AS operation_id,
      o.id_carnaval_order AS carnaval_order_id
    FROM public.app_dat_operaciones o
    WHERE o.id_carnaval_order = ANY (p_order_ids)
      AND (p_id_tienda IS NULL OR o.id_tienda = p_id_tienda)
  ),
  -- 2) Fallback exacto por observaciones (sin ILIKE)
  ops_by_obs AS (
    SELECT
      o.id AS operation_id,
      w.order_id AS carnaval_order_id
    FROM wanted w
    JOIN public.app_dat_operaciones o
      ON o.observaciones = ('Venta desde orden ' || w.order_id::text)
    WHERE (p_id_tienda IS NULL OR o.id_tienda = p_id_tienda)
      AND NOT EXISTS (
        SELECT 1
        FROM ops_by_fk f
        WHERE f.operation_id = o.id
      )
  ),
  ops AS (
    SELECT * FROM ops_by_fk
    UNION ALL
    SELECT * FROM ops_by_obs
  ),
  rpc_map AS (
    SELECT DISTINCT ON (r.id_producto)
      r.id_producto,
      r.id_producto_carnaval
    FROM public.relation_products_carnaval r
    WHERE r.id_producto IN (
      SELECT DISTINCT ep.id_producto
      FROM ops
      JOIN public.app_dat_extraccion_productos ep
        ON ep.id_operacion = ops.operation_id
    )
    ORDER BY r.id_producto, r.id
  ),
  mapped AS (
    SELECT
      ops.carnaval_order_id AS order_id,
      ops.operation_id,
      ep.id_producto AS inventtia_product_id,
      COALESCE(
        NULLIF(p.id_vendedor_app, 0),
        rpc.id_producto_carnaval
      ) AS carnaval_product_id,
      COALESCE(p.denominacion, 'Producto #' || ep.id_producto::text) AS product_name,
      COALESCE(ep.cantidad, 0)::numeric AS cantidad
    FROM ops
    JOIN public.app_dat_extraccion_productos ep
      ON ep.id_operacion = ops.operation_id
    LEFT JOIN public.app_dat_producto p
      ON p.id = ep.id_producto
    LEFT JOIN rpc_map rpc
      ON rpc.id_producto = ep.id_producto
  ),
  lines_agg AS (
    SELECT
      m.order_id::bigint AS order_id,
      m.carnaval_product_id::bigint AS carnaval_product_id,
      MIN(m.inventtia_product_id)::bigint AS inventtia_product_id,
      MIN(m.product_name)::text AS product_name,
      SUM(m.cantidad) AS qty_inventtia,
      array_agg(DISTINCT m.operation_id) AS operation_ids
    FROM mapped m
    GROUP BY m.order_id, m.carnaval_product_id
  ),
  ops_stub AS (
    SELECT
      ops.carnaval_order_id::bigint AS order_id,
      NULL::bigint AS carnaval_product_id,
      NULL::bigint AS inventtia_product_id,
      NULL::text AS product_name,
      0::numeric AS qty_inventtia,
      array_agg(DISTINCT ops.operation_id) AS operation_ids
    FROM ops
    WHERE NOT EXISTS (
      SELECT 1 FROM lines_agg la WHERE la.order_id = ops.carnaval_order_id
    )
    GROUP BY ops.carnaval_order_id
  )
  SELECT * FROM lines_agg
  UNION ALL
  SELECT * FROM ops_stub
  ORDER BY 1 DESC, 2 NULLS LAST;
END;
$$;

COMMENT ON FUNCTION public.fn_audit_inventtia_carnaval_lines IS
  'Auditoría: extracciones Inventtia para órdenes Carnaval. Match por id_carnaval_order o observaciones exactas (sin ILIKE).';

GRANT EXECUTE ON FUNCTION public.fn_audit_carnaval_order_lines(bigint, date, timestamptz, text, boolean)
  TO authenticated, service_role, anon;
GRANT EXECUTE ON FUNCTION public.fn_audit_inventtia_carnaval_lines(bigint[], bigint)
  TO authenticated, service_role, anon;
