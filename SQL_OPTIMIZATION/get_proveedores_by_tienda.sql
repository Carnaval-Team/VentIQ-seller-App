-- =====================================================
-- RPC: get_proveedores_by_tienda
-- Obtiene lista de proveedores únicos de una tienda
-- =====================================================
DROP FUNCTION IF EXISTS get_proveedores_by_tienda;
CREATE OR REPLACE FUNCTION get_proveedores_by_tienda2(p_id_tienda INTEGER)
RETURNS TABLE (
    id BIGINT,
    denominacion TEXT,
    sku_codigo TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT
        pr.id,
        pr.denominacion,
        pr.sku_codigo
    FROM app_dat_proveedor pr
    WHERE pr.idtienda = p_id_tienda
        AND pr.id IS NOT NULL
        AND pr.estado = 1
    ORDER BY pr.denominacion ASC;
END;
$$ LANGUAGE plpgsql STABLE;

-- =====================================================
-- Comentarios
-- =====================================================
COMMENT ON FUNCTION get_proveedores_by_tienda2(INTEGER) IS 
'Obtiene lista de proveedores únicos que tienen inventario en una tienda específica.
Parámetros:
  - p_id_tienda: ID de la tienda
Retorna: Lista de proveedores con id, denominacion y sku_codigo';
