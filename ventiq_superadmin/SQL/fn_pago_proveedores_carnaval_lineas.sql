-- =============================================================================
-- fn_pago_proveedores_carnaval_lineas
--
-- Órdenes Carnaval CREADAS en el rango (Orders.created_at),
-- excluyendo canceladas/devueltas:
--   - Carnaval status Cancelado / Devuelto
--   - Inventtia estado actual 3 Devuelta, 4 Cancelada, 5 Anulada
-- =============================================================================

DROP FUNCTION IF EXISTS public.fn_pago_proveedores_carnaval_lineas(
  TIMESTAMPTZ, TIMESTAMPTZ, BIGINT
);
DROP FUNCTION IF EXISTS public.fn_pago_proveedores_carnaval_lineas(
  DATE, DATE, BIGINT
);

CREATE OR REPLACE FUNCTION public.fn_pago_proveedores_carnaval_lineas(
  p_fecha_desde  DATE,
  p_fecha_hasta  DATE,
  p_proveedor_id BIGINT DEFAULT NULL
)
RETURNS TABLE (
  order_id           BIGINT,
  proveedor          BIGINT,
  product_id         BIGINT,
  product_name       TEXT,
  product_image      TEXT,
  quantity           INTEGER,
  price              DOUBLE PRECISION,
  precio_usd         DOUBLE PRECISION,
  precio_euro        DOUBLE PRECISION,
  transferencia      BOOLEAN,
  fecha_creacion     DATE
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, carnavalapp
AS $$
  SELECT
    od.order_id::BIGINT,
    od.proveedor::BIGINT,
    od.product_id::BIGINT,
    COALESCE(p.name, 'Sin nombre')::TEXT,
    p.image::TEXT,
    COALESCE(od.quantity, 0)::INTEGER,
    COALESCE(od.price, 0)::DOUBLE PRECISION,
    COALESCE(od.precio_usd, 1)::DOUBLE PRECISION,
    COALESCE(od.precio_euro, 1)::DOUBLE PRECISION,
    COALESCE(od.transferencia, FALSE),
    o.created_at::DATE
  FROM carnavalapp."OrderDetails" od
  JOIN carnavalapp."Orders" o ON o.id = od.order_id
  LEFT JOIN carnavalapp."Productos" p ON p.id = od.product_id
  WHERE o.created_at >= p_fecha_desde
    AND o.created_at <= p_fecha_hasta
    AND o.status NOT IN ('Cancelado', 'Cancelada', 'Devuelto', 'Devuelta')
    AND (p_proveedor_id IS NULL OR od.proveedor = p_proveedor_id)
    AND NOT EXISTS (
      SELECT 1
      FROM public.app_dat_operaciones op
      JOIN public.app_dat_estado_operacion eo
        ON eo.id_operacion = op.id
       AND eo.estado IN (3, 4, 5)
       AND eo.id = (
         SELECT MAX(e2.id)
         FROM public.app_dat_estado_operacion e2
         WHERE e2.id_operacion = op.id
       )
      LEFT JOIN public.app_dat_tienda t ON t.id = op.id_tienda
      WHERE op.id_carnaval_order = o.id
        AND (
          t.id_tienda_carnaval IS NULL
          OR od.proveedor IS NULL
          OR t.id_tienda_carnaval = od.proveedor
        )
    );
$$;

COMMENT ON FUNCTION public.fn_pago_proveedores_carnaval_lineas(
  DATE, DATE, BIGINT
) IS
  'Líneas de pago a proveedores: órdenes Carnaval creadas en el rango, excluyendo canceladas y devueltas (Carnaval e Inventtia).';

GRANT EXECUTE ON FUNCTION public.fn_pago_proveedores_carnaval_lineas(
  DATE, DATE, BIGINT
) TO authenticated;

GRANT EXECUTE ON FUNCTION public.fn_pago_proveedores_carnaval_lineas(
  DATE, DATE, BIGINT
) TO service_role;
