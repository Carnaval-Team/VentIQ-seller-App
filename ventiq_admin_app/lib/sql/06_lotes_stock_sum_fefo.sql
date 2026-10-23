-- ============================================================================
-- 06 — Stock agregado por lotes + ORDER BY FEFO
-- ============================================================================
-- Problema:
--   1) fn_stock_lotes_en_ubicacion no ordenaba por fecha_vencimiento (FEFO).
--   2) Listados / resumen tomaban DISTINCT/ROW_NUMBER sin id_lote → un solo
--      snapshot (último movimiento) en lugar de SUM de saldos por lote.
--
-- Aplicar SOLO en newa (SQL Editor → proyecto newa).
-- Requiere 01_lotes_vencimiento_schema.sql (columna id_lote).
-- NO aplicar en main hasta el pase final (01→06).
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'app_dat_inventario_productos'
      AND column_name = 'id_lote'
  ) THEN
    RAISE EXCEPTION
      'Falta columna id_lote en app_dat_inventario_productos. '
      'Estas en el proyecto equivocado (main?) o falta aplicar '
      '01_lotes_vencimiento_schema.sql antes de 06.';
  END IF;
END $$;

-- A) Lectura de lotes ordenada FEFO
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
    lote.codigo::TEXT,
    lote.fecha_vencimiento,
    l.cantidad_final,
    p.dias_alert_caducidad,
    COALESCE(p.es_por_lotes, false),
    CASE
      WHEN lote.fecha_vencimiento IS NULL THEN 'sin_lote'
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


-- B) Helper: último saldo por lote, luego agregado sin lote
--    (reutilizable por listados / reporting)
CREATE OR REPLACE FUNCTION public.fn_inventario_saldo_por_clave(
  p_id_ubicacion BIGINT DEFAULT NULL,
  p_id_producto BIGINT DEFAULT NULL
)
RETURNS TABLE (
  id_producto BIGINT,
  id_variante BIGINT,
  id_opcion_variante BIGINT,
  id_presentacion BIGINT,
  id_ubicacion BIGINT,
  cantidad_inicial NUMERIC,
  cantidad_final NUMERIC,
  created_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH latest_lote AS (
    SELECT DISTINCT ON (
      i.id_producto,
      COALESCE(i.id_variante, 0),
      COALESCE(i.id_opcion_variante, 0),
      COALESCE(i.id_presentacion, 0),
      COALESCE(i.id_ubicacion, 0),
      COALESCE(i.id_lote, 0)
    )
      i.id_producto,
      i.id_variante,
      i.id_opcion_variante,
      i.id_presentacion,
      i.id_ubicacion,
      i.cantidad_inicial,
      i.cantidad_final,
      i.created_at
    FROM app_dat_inventario_productos i
    WHERE i.cantidad_final IS NOT NULL
      AND (p_id_ubicacion IS NULL OR i.id_ubicacion = p_id_ubicacion)
      AND (p_id_producto IS NULL OR i.id_producto = p_id_producto)
    ORDER BY
      i.id_producto,
      COALESCE(i.id_variante, 0),
      COALESCE(i.id_opcion_variante, 0),
      COALESCE(i.id_presentacion, 0),
      COALESCE(i.id_ubicacion, 0),
      COALESCE(i.id_lote, 0),
      i.id DESC
  )
  SELECT
    l.id_producto,
    l.id_variante,
    l.id_opcion_variante,
    l.id_presentacion,
    l.id_ubicacion,
    SUM(l.cantidad_inicial)::NUMERIC,
    SUM(l.cantidad_final)::NUMERIC,
    MAX(l.created_at)
  FROM latest_lote l
  GROUP BY
    l.id_producto,
    l.id_variante,
    l.id_opcion_variante,
    l.id_presentacion,
    l.id_ubicacion;
$$;

GRANT EXECUTE ON FUNCTION public.fn_inventario_saldo_por_clave(BIGINT, BIGINT)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.fn_inventario_saldo_por_clave IS
  'Último saldo por (producto, variante, presentación, ubicación, lote) y SUM entre lotes. FEFO no aplica aquí: solo agrega cantidad.';


-- C) Resumen por usuario: último saldo POR LOTE (luego SUM en CTE resumen)
--    Reaplicar también el archivo
--    fn_inventario_resumen_por_usuario_almacen2_include_auditor.sql
--    (PARTITION BY ahora incluye COALESCE(id_lote, 0)).
--
-- D) fn_listar_inventario_productos_paged2
--    El CTE inv_last debe ser: DISTINCT ON (... id_lote) → luego GROUP BY
--    sumando cantidad_*. Mientras no se reemplace la función completa en
--    SQL Editor, la app admin corrige cantidades en cliente con
--    fn_stock_lotes_en_ubicacion + suma FEFO.
