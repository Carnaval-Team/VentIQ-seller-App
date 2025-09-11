CREATE OR REPLACE FUNCTION fn_listar_productos_promocion(
    p_id_promocion BIGINT
)
RETURNS TABLE (
    id VARCHAR,
    name VARCHAR,
    description VARCHAR,
    categoryId VARCHAR,
    categoryName VARCHAR,
    brand VARCHAR,
    sku VARCHAR,
    barcode VARCHAR,
    basePrice NUMERIC,
    imageUrl TEXT,
    isActive BOOLEAN,
    createdAt TIMESTAMP WITH TIME ZONE,
    updatedAt TIMESTAMP WITH TIME ZONE,
    stockDisponible INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    SET search_path = public;
    
    -- Validar que la promoción existe
    IF NOT EXISTS (SELECT 1 FROM app_mkt_promociones WHERE app_mkt_promociones.id = p_id_promocion) THEN
        RAISE EXCEPTION 'Promoción con ID % no encontrada', p_id_promocion;
    END IF;
    
    -- Retornar productos específicos de la promoción con precios reales
    RETURN QUERY
    SELECT DISTINCT
        p.id::VARCHAR as id,
        COALESCE(p.denominacion, '')::VARCHAR as name,
        COALESCE(p.descripcion, '')::VARCHAR as description,
        COALESCE(p.id_categoria::VARCHAR, '') as categoryId,
        COALESCE(c.denominacion, '')::VARCHAR as categoryName,
        COALESCE(p.nombre_comercial, '')::VARCHAR as brand,
        COALESCE(p.sku, '')::VARCHAR as sku,
        COALESCE(p.codigo_barras, '')::VARCHAR as barcode,
        COALESCE(pv.precio_venta_cup, 0.0)::NUMERIC as basePrice,
        COALESCE(p.imagen, '')::TEXT as imageUrl,
        COALESCE(p.es_vendible, true) as isActive,
        COALESCE(p.created_at, NOW()) as createdAt,
        COALESCE(p.created_at, NOW()) as updatedAt,
        COALESCE(0, 0) as stockDisponible
    FROM app_mkt_promocion_productos pp
    INNER JOIN app_dat_producto p ON (
        (pp.id_producto IS NOT NULL AND pp.id_producto = p.id) OR
        (pp.id_categoria IS NOT NULL AND pp.id_categoria = p.id_categoria) OR
        (pp.id_subcategoria IS NOT NULL AND pp.id_subcategoria IN (
            SELECT psc.id_sub_categoria 
            FROM app_dat_productos_subcategorias psc 
            WHERE psc.id_producto = p.id
        ))
    )
    LEFT JOIN app_dat_categoria c ON p.id_categoria = c.id
    LEFT JOIN app_dat_precio_venta pv ON pv.id_producto = p.id 
        AND pv.id_variante IS NULL 
        AND pv.fecha_desde <= CURRENT_DATE 
        AND (pv.fecha_hasta IS NULL OR pv.fecha_hasta >= CURRENT_DATE)
    WHERE pp.id_promocion = p_id_promocion;
      
END;
$$;
