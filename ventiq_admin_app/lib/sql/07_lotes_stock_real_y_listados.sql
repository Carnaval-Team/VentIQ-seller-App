-- ============================================================================
-- 07 — Stock real = suma de lotes (operaciones de inventario)
-- ============================================================================
-- Requiere: 01 + 06 (fn_inventario_saldo_por_clave) en newa.
--
-- get_stock_real_by_location_presentation devolvía LIMIT 1 (último snapshot).
-- Con varios lotes eso muestra p.ej. 400 en lugar de 5000+400(+sin lote).
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'app_dat_inventario_productos'
      AND column_name = 'id_lote'
  ) THEN
    RAISE EXCEPTION
      'Falta id_lote. Aplica 01_lotes_vencimiento_schema.sql en newa primero.';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.get_stock_real_by_location_presentation(
    p_id_producto BIGINT,
    p_id_ubicacion BIGINT,
    p_id_presentacion BIGINT
)
RETURNS TABLE (
    cantidad_disponible NUMERIC,
    id_inventario BIGINT,
    created_at TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH latest_lote AS (
    SELECT DISTINCT ON (COALESCE(ip.id_lote, 0))
      ip.id,
      ip.id_lote,
      ip.cantidad_final,
      ip.created_at
    FROM app_dat_inventario_productos ip
    WHERE ip.id_producto = p_id_producto
      AND ip.id_ubicacion = p_id_ubicacion
      AND COALESCE(ip.id_presentacion, 0) = COALESCE(p_id_presentacion, 0)
      AND ip.cantidad_final IS NOT NULL
    ORDER BY COALESCE(ip.id_lote, 0), ip.id DESC
  )
  SELECT
    COALESCE(SUM(l.cantidad_final), 0)::NUMERIC,
    (ARRAY_AGG(l.id ORDER BY l.created_at DESC NULLS LAST, l.id DESC))[1]::BIGINT,
    MAX(l.created_at)
  FROM latest_lote l;
END;
$$;

COMMENT ON FUNCTION public.get_stock_real_by_location_presentation(BIGINT, BIGINT, BIGINT) IS
  'Stock disponible = SUM del último saldo por cada id_lote (incluye id_lote NULL).';

-- También incluir saldos sin id_lote en la lectura de lotes (para que
-- Stock muestre 5000 + 400 + 50 = mismo total que extracción).
CREATE OR REPLACE FUNCTION public.fn_stock_lotes_en_ubicacion(
  p_id_ubicacion BIGINT
)
RETURNS TABLE (
  id_producto BIGINT,
  id_variante BIGINT,
  id_opcion_variante BIGINT,
  id_presentacion BIGINT,
  id_lote BIGINT,
  codigo_lote TEXT,
  fecha_vencimiento DATE,
  cantidad_final NUMERIC,
  dias_alert_caducidad NUMERIC,
  es_por_lotes BOOLEAN,
  estado_caducidad TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH latest AS (
    SELECT DISTINCT ON (
      i.id_producto,
      COALESCE(i.id_variante, 0),
      COALESCE(i.id_opcion_variante, 0),
      COALESCE(i.id_presentacion, 0),
      COALESCE(i.id_lote, 0)
    )
      i.id_producto,
      i.id_variante,
      i.id_opcion_variante,
      i.id_presentacion,
      i.id_lote,
      i.cantidad_final
    FROM app_dat_inventario_productos i
    WHERE i.id_ubicacion = p_id_ubicacion
      AND i.cantidad_final IS NOT NULL
    ORDER BY
      i.id_producto,
      COALESCE(i.id_variante, 0),
      COALESCE(i.id_opcion_variante, 0),
      COALESCE(i.id_presentacion, 0),
      COALESCE(i.id_lote, 0),
      i.id DESC
  )
  SELECT
    l.id_producto,
    l.id_variante,
    l.id_opcion_variante,
    l.id_presentacion,
    l.id_lote,
    COALESCE(lote.codigo, CASE WHEN l.id_lote IS NULL THEN 'Sin lote' ELSE NULL END)::TEXT,
    lote.fecha_vencimiento,
    l.cantidad_final,
    p.dias_alert_caducidad,
    COALESCE(p.es_por_lotes, false),
    CASE
      WHEN l.id_lote IS NULL OR lote.fecha_vencimiento IS NULL THEN 'sin_lote'
      WHEN lote.fecha_vencimiento < CURRENT_DATE THEN 'expired'
      WHEN p.dias_alert_caducidad IS NOT NULL
           AND p.dias_alert_caducidad > 0
           AND lote.fecha_vencimiento <= (CURRENT_DATE + (p.dias_alert_caducidad || ' days')::INTERVAL)
        THEN 'expiring'
      ELSE 'ok'
    END
  FROM latest l
  LEFT JOIN app_dat_lote lote ON lote.id = l.id_lote
  JOIN app_dat_producto p ON p.id = l.id_producto
  WHERE l.cantidad_final > 0
  ORDER BY lote.fecha_vencimiento ASC NULLS LAST, l.id_lote ASC NULLS LAST;
$$;

GRANT EXECUTE ON FUNCTION public.fn_stock_lotes_en_ubicacion(BIGINT)
  TO authenticated, service_role;

-- ============================================================================
-- Listados grandes (aplicar cuando regeneres las funciones):
--   fn_listar_inventario_productos_paged2
--   fn_listar_inventario_productos_paged2_grouped2_optimiized
--
-- Mientras tanto la app admin corrige totales con
-- InventoryService.enrichMapsWithLoteSums / fn_inventario_saldo_por_clave.
-- ============================================================================
