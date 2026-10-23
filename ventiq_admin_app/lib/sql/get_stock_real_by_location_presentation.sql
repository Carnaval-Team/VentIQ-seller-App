-- =====================================================
-- RPC: GET_STOCK_REAL_BY_LOCATION_PRESENTATION
-- =====================================================
-- Obtiene la cantidad real disponible de un producto en una ubicación específica
-- filtrando por id_producto, id_ubicacion e id_presentacion
-- Retorna la cantidad_final del último registro en app_dat_inventario_productos
-- =====================================================

CREATE OR REPLACE FUNCTION get_stock_real_by_location_presentation(
    p_id_producto BIGINT,
    p_id_ubicacion BIGINT,
    p_id_presentacion BIGINT
)
RETURNS TABLE (
    cantidad_disponible NUMERIC,
    id_inventario BIGINT,
    created_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    -- Suma el último saldo de cada lote (incluye id_lote NULL).
    RETURN QUERY
    WITH latest_lote AS (
      SELECT DISTINCT ON (COALESCE(ip.id_lote, 0))
        ip.id,
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
$$ LANGUAGE plpgsql STABLE;

-- =====================================================
-- COMENTARIOS
-- =====================================================
-- Esta función obtiene la cantidad real disponible de un producto
-- en una ubicación específica y presentación específica.
--
-- Parámetros:
--   p_id_producto: ID del producto
--   p_id_ubicacion: ID de la ubicación (zona del almacén)
--   p_id_presentacion: ID de la presentación del producto
--
-- Retorna:
--   cantidad_disponible: La cantidad_final del último registro (stock actual)
--   id_inventario: ID del registro de inventario
--   created_at: Fecha de creación del registro
--
-- Ejemplo de uso:
--   SELECT * FROM get_stock_real_by_location_presentation(123, 456, 789);
--
-- Notas:
--   - Retorna el ÚLTIMO registro (más reciente) para esa combinación
--   - Si no existe registro, retorna cantidad_disponible = 0
--   - Usa STABLE para permitir optimizaciones de query planner
-- =====================================================
