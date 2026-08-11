-- =============================================================================
-- RPCs de desglose de stock real (en_pedidos / entregando) según Carnaval
-- Reemplazan las múltiples consultas client-side de InventoryService.
--
-- Lógica (igual que la app):
--   - Solo ventas pendientes (último estado_operacion = 1)
--   - Orden Carnaval status "Entregando" → entregando (NO vuelve a almacén)
--   - Completado/Cancelado → se ignora
--   - Resto (Procesando, sin orden, etc.) → en_pedidos (sigue en almacén)
--
-- El cliente calcula: en_almacen = cantidad_final_base + en_pedidos
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_stock_breakdown_by_products(
  p_product_ids bigint[],
  p_id_almacen bigint DEFAULT NULL
)
RETURNS TABLE (
  id_producto bigint,
  en_pedidos numeric,
  entregando numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, carnavalapp
AS $function$
DECLARE
  v_tipo_venta_id bigint;
BEGIN
  IF p_product_ids IS NULL OR cardinality(p_product_ids) = 0 THEN
    RETURN;
  END IF;

  SELECT t.id
  INTO v_tipo_venta_id
  FROM public.app_nom_tipo_operacion t
  WHERE lower(trim(t.denominacion)) = 'venta'
  LIMIT 1;

  RETURN QUERY
  WITH ubicaciones_filtro AS (
    SELECT l.id
    FROM public.app_dat_layout_almacen l
    WHERE p_id_almacen IS NULL OR l.id_almacen = p_id_almacen
  ),
  extracciones AS (
    SELECT
      ep.id_operacion,
      ep.id_producto,
      ep.id_ubicacion,
      ABS(COALESCE(ep.cantidad, 0))::numeric AS cantidad
    FROM public.app_dat_extraccion_productos ep
    WHERE ep.id_producto = ANY (p_product_ids)
      AND (
        p_id_almacen IS NULL
        OR ep.id_ubicacion IN (SELECT uf.id FROM ubicaciones_filtro uf)
      )
  ),
  ultimo_estado AS (
    SELECT DISTINCT ON (eo.id_operacion)
      eo.id_operacion,
      eo.estado
    FROM public.app_dat_estado_operacion eo
    WHERE eo.id_operacion IN (SELECT DISTINCT e.id_operacion FROM extracciones e)
    ORDER BY eo.id_operacion, eo.id DESC
  ),
  pending AS (
    SELECT
      e.id_producto,
      e.id_ubicacion,
      e.cantidad,
      o.id_carnaval_order,
      o.observaciones
    FROM extracciones e
    INNER JOIN ultimo_estado ue
      ON ue.id_operacion = e.id_operacion
     AND ue.estado = 1
    INNER JOIN public.app_dat_operaciones o
      ON o.id = e.id_operacion
    WHERE v_tipo_venta_id IS NULL
       OR o.id_tipo_operacion = v_tipo_venta_id
  ),
  with_order AS (
    SELECT
      p.id_producto,
      p.id_ubicacion,
      p.cantidad,
      COALESCE(
        p.id_carnaval_order,
        NULLIF(
          (regexp_match(COALESCE(p.observaciones, ''), 'Venta desde orden\s+(\d+)', 'i'))[1],
          ''
        )::bigint
      ) AS order_id
    FROM pending p
  ),
  with_status AS (
    SELECT
      w.id_producto,
      w.id_ubicacion,
      w.cantidad,
      lower(trim(COALESCE(ord.status, ''))) AS order_status
    FROM with_order w
    LEFT JOIN carnavalapp."Orders" ord ON ord.id = w.order_id
  ),
  classified AS (
    SELECT
      ws.id_producto,
      ws.cantidad,
      CASE
        WHEN ws.order_status = 'entregando'
          OR ws.order_status LIKE '%entregando%' THEN 'entregando'
        WHEN ws.order_status IN ('completado', 'completada', 'cancelado', 'cancelada')
          THEN 'terminal'
        ELSE 'en_pedidos'
      END AS bucket
    FROM with_status ws
  )
  SELECT
    c.id_producto,
    COALESCE(SUM(c.cantidad) FILTER (WHERE c.bucket = 'en_pedidos'), 0)::numeric AS en_pedidos,
    COALESCE(SUM(c.cantidad) FILTER (WHERE c.bucket = 'entregando'), 0)::numeric AS entregando
  FROM classified c
  WHERE c.bucket <> 'terminal'
  GROUP BY c.id_producto;
END;
$function$;


CREATE OR REPLACE FUNCTION public.fn_stock_breakdown_by_locations(
  p_product_ids bigint[],
  p_ubicacion_ids bigint[]
)
RETURNS TABLE (
  id_producto bigint,
  id_ubicacion bigint,
  en_pedidos numeric,
  entregando numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, carnavalapp
AS $function$
DECLARE
  v_tipo_venta_id bigint;
BEGIN
  IF p_product_ids IS NULL OR cardinality(p_product_ids) = 0 THEN
    RETURN;
  END IF;
  IF p_ubicacion_ids IS NULL OR cardinality(p_ubicacion_ids) = 0 THEN
    RETURN;
  END IF;

  SELECT t.id
  INTO v_tipo_venta_id
  FROM public.app_nom_tipo_operacion t
  WHERE lower(trim(t.denominacion)) = 'venta'
  LIMIT 1;

  RETURN QUERY
  WITH extracciones AS (
    SELECT
      ep.id_operacion,
      ep.id_producto,
      ep.id_ubicacion,
      ABS(COALESCE(ep.cantidad, 0))::numeric AS cantidad
    FROM public.app_dat_extraccion_productos ep
    WHERE ep.id_producto = ANY (p_product_ids)
      AND ep.id_ubicacion = ANY (p_ubicacion_ids)
  ),
  ultimo_estado AS (
    SELECT DISTINCT ON (eo.id_operacion)
      eo.id_operacion,
      eo.estado
    FROM public.app_dat_estado_operacion eo
    WHERE eo.id_operacion IN (SELECT DISTINCT e.id_operacion FROM extracciones e)
    ORDER BY eo.id_operacion, eo.id DESC
  ),
  pending AS (
    SELECT
      e.id_producto,
      e.id_ubicacion,
      e.cantidad,
      o.id_carnaval_order,
      o.observaciones
    FROM extracciones e
    INNER JOIN ultimo_estado ue
      ON ue.id_operacion = e.id_operacion
     AND ue.estado = 1
    INNER JOIN public.app_dat_operaciones o
      ON o.id = e.id_operacion
    WHERE v_tipo_venta_id IS NULL
       OR o.id_tipo_operacion = v_tipo_venta_id
  ),
  with_order AS (
    SELECT
      p.id_producto,
      p.id_ubicacion,
      p.cantidad,
      COALESCE(
        p.id_carnaval_order,
        NULLIF(
          (regexp_match(COALESCE(p.observaciones, ''), 'Venta desde orden\s+(\d+)', 'i'))[1],
          ''
        )::bigint
      ) AS order_id
    FROM pending p
  ),
  with_status AS (
    SELECT
      w.id_producto,
      w.id_ubicacion,
      w.cantidad,
      lower(trim(COALESCE(ord.status, ''))) AS order_status
    FROM with_order w
    LEFT JOIN carnavalapp."Orders" ord ON ord.id = w.order_id
  ),
  classified AS (
    SELECT
      ws.id_producto,
      ws.id_ubicacion,
      ws.cantidad,
      CASE
        WHEN ws.order_status = 'entregando'
          OR ws.order_status LIKE '%entregando%' THEN 'entregando'
        WHEN ws.order_status IN ('completado', 'completada', 'cancelado', 'cancelada')
          THEN 'terminal'
        ELSE 'en_pedidos'
      END AS bucket
    FROM with_status ws
  )
  SELECT
    c.id_producto,
    c.id_ubicacion,
    COALESCE(SUM(c.cantidad) FILTER (WHERE c.bucket = 'en_pedidos'), 0)::numeric AS en_pedidos,
    COALESCE(SUM(c.cantidad) FILTER (WHERE c.bucket = 'entregando'), 0)::numeric AS entregando
  FROM classified c
  WHERE c.bucket <> 'terminal'
  GROUP BY c.id_producto, c.id_ubicacion;
END;
$function$;


GRANT EXECUTE ON FUNCTION public.fn_stock_breakdown_by_products(bigint[], bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_stock_breakdown_by_products(bigint[], bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_stock_breakdown_by_locations(bigint[], bigint[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_stock_breakdown_by_locations(bigint[], bigint[]) TO service_role;

COMMENT ON FUNCTION public.fn_stock_breakdown_by_products(bigint[], bigint) IS
  'Desglose en_pedidos/entregando por producto según status Carnaval. Una sola llamada.';
COMMENT ON FUNCTION public.fn_stock_breakdown_by_locations(bigint[], bigint[]) IS
  'Desglose en_pedidos/entregando por producto+ubicación según status Carnaval. Una sola llamada.';
