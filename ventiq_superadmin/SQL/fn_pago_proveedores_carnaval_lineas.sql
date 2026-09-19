-- =============================================================================
-- fn_pago_proveedores_carnaval_lineas
--
-- Órdenes Carnaval CREADAS en el rango (Orders.created_at),
-- excluyendo canceladas/devueltas:
--   - Carnaval status Cancelado / Devuelto
--   - Inventtia estado actual 3 Devuelta, 4 Cancelada, 5 Anulada
--
-- price / precio_usd: precios de tienda Inventtia (app_dat_precio_venta),
-- NO el precio cobrado en Carnaval. Así el listado de órdenes suma igual
-- que el resumen a pagar al proveedor.
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
    COALESCE(pv.precio_venta_cup, 0)::DOUBLE PRECISION AS price,
    COALESCE(pv.precio_venta_usd, 0)::DOUBLE PRECISION AS precio_usd,
    COALESCE(od.precio_euro, 0)::DOUBLE PRECISION,
    COALESCE(od.transferencia, FALSE),
    o.created_at::DATE
  FROM carnavalapp."OrderDetails" od
  JOIN carnavalapp."Orders" o ON o.id = od.order_id
  LEFT JOIN carnavalapp."Productos" p ON p.id = od.product_id
  LEFT JOIN public.app_dat_producto ap
    ON ap.id_vendedor_app = od.product_id
  LEFT JOIN LATERAL (
    SELECT pv2.precio_venta_cup, pv2.precio_venta_usd
    FROM public.app_dat_precio_venta pv2
    WHERE pv2.id_producto = ap.id
    ORDER BY pv2.created_at DESC NULLS LAST, pv2.id DESC
    LIMIT 1
  ) pv ON TRUE
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
  'Líneas de pago a proveedores con precios Inventtia (precio_venta_cup), excluyendo canceladas/devueltas.';

GRANT EXECUTE ON FUNCTION public.fn_pago_proveedores_carnaval_lineas(
  DATE, DATE, BIGINT
) TO authenticated;

GRANT EXECUTE ON FUNCTION public.fn_pago_proveedores_carnaval_lineas(
  DATE, DATE, BIGINT
) TO service_role;
