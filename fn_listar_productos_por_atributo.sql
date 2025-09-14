CREATE OR REPLACE FUNCTION fn_listar_productos_por_atributo(
    p_id_tienda BIGINT,
    p_id_variante BIGINT
)
RETURNS TABLE(
    id BIGINT,
    denominacion VARCHAR,
    descripcion VARCHAR,
    sku VARCHAR,
    codigo_barras VARCHAR,
    precio_venta NUMERIC,
    imagen TEXT,
    es_vendible BOOLEAN,
    created_at TIMESTAMP WITH TIME ZONE,
    id_categoria BIGINT,
    categoria_nombre VARCHAR,
    nombre_comercial VARCHAR,
    stock_disponible INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    result_count INTEGER;
    v_id_atributo BIGINT;
BEGIN
    -- Get the attribute ID from the variant
    SELECT v.id_atributo INTO v_id_atributo 
    FROM app_dat_variantes v 
    WHERE v.id = p_id_variante;
    
    -- Log input parameters for debugging
    RAISE NOTICE 'fn_listar_productos_por_atributo called with p_id_tienda: %, p_id_variante: %', p_id_tienda, p_id_variante;
    RAISE NOTICE 'Found id_atributo: % for variant: %', v_id_atributo, p_id_variante;
    
    -- Log count of products in store
    RAISE NOTICE 'Total products in store %: %', p_id_tienda, (SELECT COUNT(*) FROM app_dat_producto WHERE id_tienda = p_id_tienda);
    
    -- Log count of variants with this attribute
    RAISE NOTICE 'Variants with attribute %: %', v_id_atributo, (SELECT COUNT(*) FROM app_dat_variantes WHERE id_atributo = v_id_atributo);
    
    -- Log count of inventory records with variants of this attribute
    RAISE NOTICE 'Inventory records with variants of attribute %: %', v_id_atributo, 
        (SELECT COUNT(*) FROM app_dat_inventario_productos ip 
         INNER JOIN app_dat_variantes v ON ip.id_variante = v.id 
         WHERE v.id_atributo = v_id_atributo);
    
    RETURN QUERY
    SELECT DISTINCT
        p.id AS id,
        p.denominacion AS denominacion,
        p.descripcion AS descripcion,
        p.sku AS sku,
        p.codigo_barras AS codigo_barras,
        COALESCE(pv.precio_venta_cup, 0.0) AS precio_venta,
        p.imagen AS imagen,
        p.es_vendible AS es_vendible,
        p.created_at AS created_at,
        p.id_categoria AS id_categoria,
        COALESCE(c.denominacion, '') AS categoria_nombre,
        p.nombre_comercial AS nombre_comercial,
        COALESCE(
            (SELECT SUM(ip.cantidad_final) 
             FROM app_dat_inventario_productos ip 
             WHERE ip.id_producto = p.id), 0
        )::INTEGER AS stock_disponible
    FROM app_dat_producto p
    LEFT JOIN app_dat_categoria c ON p.id_categoria = c.id
    LEFT JOIN app_dat_precio_venta pv ON p.id = pv.id_producto 
        AND pv.fecha_desde <= CURRENT_DATE 
        AND (pv.fecha_hasta IS NULL OR pv.fecha_hasta >= CURRENT_DATE)
    WHERE p.id_tienda = p_id_tienda
    AND p.es_vendible = true
    AND EXISTS (
        -- Check if product uses any variant with this attribute through inventory
        SELECT 1 FROM app_dat_inventario_productos ip 
        INNER JOIN app_dat_variantes v ON ip.id_variante = v.id
        WHERE v.id_atributo = v_id_atributo
        AND ip.id_producto = p.id
        
        UNION
        
        -- Check if product uses any variant with this attribute through reception operations
        SELECT 1 FROM app_dat_recepcion_productos rp 
        INNER JOIN app_dat_variantes v ON rp.id_variante = v.id
        WHERE v.id_atributo = v_id_atributo
        AND rp.id_producto = p.id
        
        UNION
        
        -- Check if product uses any variant with this attribute through extraction operations
        SELECT 1 FROM app_dat_extraccion_productos ep 
        INNER JOIN app_dat_variantes v ON ep.id_variante = v.id
        WHERE v.id_atributo = v_id_atributo
        AND ep.id_producto = p.id
        
        UNION
        
        -- Check if product uses any variant with this attribute through control operations
        SELECT 1 FROM app_dat_control_productos cp 
        INNER JOIN app_dat_variantes v ON cp.id_variante = v.id
        WHERE v.id_atributo = v_id_atributo
        AND cp.id_producto = p.id
    )
    ORDER BY p.denominacion;
    
    -- Log result count
    GET DIAGNOSTICS result_count = ROW_COUNT;
    RAISE NOTICE 'Function returned % products', result_count;
END;
$$;
