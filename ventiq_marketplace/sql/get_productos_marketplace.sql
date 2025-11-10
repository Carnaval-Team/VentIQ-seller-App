-- =====================================================
-- Función RPC: get_productos_marketplace
-- Descripción: Obtiene productos para el marketplace con filtros opcionales
-- Autor: VentIQ Team
-- Fecha: 2025-11-10
-- =====================================================

CREATE OR REPLACE FUNCTION get_productos_marketplace(
    id_tienda_param bigint DEFAULT NULL,
    id_categoria_param bigint DEFAULT NULL,
    solo_disponibles_param boolean DEFAULT false,
    search_query_param text DEFAULT NULL,
    limit_param integer DEFAULT 50,
    offset_param integer DEFAULT 0
)
RETURNS TABLE (
    id_producto bigint,
    sku text,
    denominacion text,
    descripcion text,
    um text,
    es_refrigerado boolean,
    es_fragil boolean,
    es_vendible boolean,
    codigo_barras text,
    id_subcategoria bigint,
    subcategoria_nombre text,
    id_categoria bigint,
    categoria_nombre text,
    precio_venta numeric,
    imagen text,
    stock_disponible numeric,
    tiene_stock boolean,
    metadata jsonb
)
LANGUAGE plpgsql
AS $$
BEGIN  
    -- Devolver productos para marketplace con filtros opcionales
    RETURN QUERY
    SELECT 
        p.id::bigint AS id_producto,
        p.sku::text,
        p.denominacion::text,
        p.descripcion::text,
        p.um::text,
        p.es_refrigerado::boolean,
        p.es_fragil::boolean,
        p.es_vendible::boolean,
        p.codigo_barras::text,
        sc.id::bigint AS id_subcategoria,
        sc.denominacion::text AS subcategoria_nombre,
        c.id::bigint AS id_categoria,
        c.denominacion::text AS categoria_nombre,
        COALESCE(pv.precio_venta_cup, 0) AS precio_venta,
        p.imagen::text,
        -- Calcular stock disponible de TODOS los almacenes
        COALESCE(
            (SELECT SUM(ip.cantidad_final) 
             FROM app_dat_inventario_productos ip 
             WHERE ip.id_producto = p.id 
             AND ip.cantidad_final > 0
             -- Filtrar solo los registros más recientes por combinación única
             AND ip.id = (
                 SELECT MAX(ip2.id) 
                 FROM app_dat_inventario_productos ip2 
                 WHERE ip2.id_producto = ip.id_producto 
                 AND COALESCE(ip2.id_variante, 0) = COALESCE(ip.id_variante, 0)
                 AND COALESCE(ip2.id_opcion_variante, 0) = COALESCE(ip.id_opcion_variante, 0)
                 AND COALESCE(ip2.id_presentacion, 0) = COALESCE(ip.id_presentacion, 0)
                 AND COALESCE(ip2.id_ubicacion, 0) = COALESCE(ip.id_ubicacion, 0)
             )),
            0
        ) AS stock_disponible,
        -- Indicar si tiene stock disponible
        COALESCE(
            (SELECT CASE WHEN SUM(ip.cantidad_final) > 0 THEN true ELSE false END
             FROM app_dat_inventario_productos ip 
             WHERE ip.id_producto = p.id 
             AND ip.cantidad_final > 0
             -- Filtrar solo los registros más recientes por combinación única
             AND ip.id = (
                 SELECT MAX(ip2.id) 
                 FROM app_dat_inventario_productos ip2 
                 WHERE ip2.id_producto = ip.id_producto 
                 AND COALESCE(ip2.id_variante, 0) = COALESCE(ip.id_variante, 0)
                 AND COALESCE(ip2.id_opcion_variante, 0) = COALESCE(ip.id_opcion_variante, 0)
                 AND COALESCE(ip2.id_presentacion, 0) = COALESCE(ip.id_presentacion, 0)
                 AND COALESCE(ip2.id_ubicacion, 0) = COALESCE(ip.id_ubicacion, 0)
             )),
            false
        ) AS tiene_stock,
        -- ✅ Metadatos adicionales en formato JSON
        jsonb_build_object(
            'es_elaborado', p.es_elaborado,
            'es_servicio', p.es_servicio,
            'denominacion_tienda', t.denominacion,
            'id_tienda', t.id,
            'rating_promedio', COALESCE(
                (SELECT ROUND(AVG(pr.rating), 1)
                 FROM app_dat_producto_rating pr
                 WHERE pr.id_producto = p.id),
                0.0
            ),
            'total_ratings', COALESCE(
                (SELECT COUNT(*)
                 FROM app_dat_producto_rating pr
                 WHERE pr.id_producto = p.id),
                0
            ),
            'presentaciones', COALESCE(
                (SELECT jsonb_agg(
                    jsonb_build_object(
                        'id', pp.id,
                        'id_presentacion', pp.id_presentacion,
                        'denominacion', np.denominacion,
                        'descripcion', np.descripcion,
                        'sku_codigo', np.sku_codigo,
                        'cantidad', pp.cantidad,
                        'es_base', pp.es_base
                    ) ORDER BY pp.es_base DESC, np.denominacion
                )
                FROM app_dat_producto_presentacion pp
                JOIN app_nom_presentacion np ON pp.id_presentacion = np.id
                WHERE pp.id_producto = p.id),
                '[]'::jsonb
            )
        ) AS metadata
    FROM 
        app_dat_producto p
    JOIN 
        app_dat_tienda t ON p.id_tienda = t.id
    JOIN 
        app_dat_productos_subcategorias ps ON p.id = ps.id_producto
    JOIN 
        app_dat_subcategorias sc ON ps.id_sub_categoria = sc.id
    JOIN 
        app_dat_categoria c ON sc.idcategoria = c.id
    LEFT JOIN 
        app_dat_producto_ingredientes pri ON pri.id_ingrediente = p.id
    LEFT JOIN 
        app_dat_precio_venta pv ON p.id = pv.id_producto AND 
        (pv.id_variante IS NULL OR pv.id_variante = 0) AND
        (pv.fecha_hasta IS NULL OR pv.fecha_hasta >= CURRENT_DATE)
    WHERE 
        p.es_vendible = true AND
        pri.id IS NULL AND
        -- ✅ Filtro opcional por tienda
        (id_tienda_param IS NULL OR p.id_tienda = id_tienda_param) AND
        -- ✅ Filtro opcional por categoría
        (id_categoria_param IS NULL OR c.id = id_categoria_param) AND
        -- ✅ Filtro opcional de solo disponibles
        (NOT solo_disponibles_param OR EXISTS (
            SELECT 1 
            FROM app_dat_inventario_productos ip 
            WHERE ip.id_producto = p.id 
            AND ip.cantidad_final > 0
        )) AND
        -- ✅ Filtro de búsqueda flexible (búsqueda fonética en múltiples campos)
        (search_query_param IS NULL OR search_query_param = '' OR (
            -- Normalizar texto para búsqueda fonética (sin acentos, minúsculas)
            unaccent(LOWER(p.denominacion)) LIKE '%' || unaccent(LOWER(search_query_param)) || '%' OR
            unaccent(LOWER(p.descripcion)) LIKE '%' || unaccent(LOWER(search_query_param)) || '%' OR
            unaccent(LOWER(p.sku)) LIKE '%' || unaccent(LOWER(search_query_param)) || '%' OR
            unaccent(LOWER(p.codigo_barras)) LIKE '%' || unaccent(LOWER(search_query_param)) || '%' OR
            unaccent(LOWER(c.denominacion)) LIKE '%' || unaccent(LOWER(search_query_param)) || '%' OR
            unaccent(LOWER(sc.denominacion)) LIKE '%' || unaccent(LOWER(search_query_param)) || '%' OR
            unaccent(LOWER(t.denominacion)) LIKE '%' || unaccent(LOWER(search_query_param)) || '%'
        ))
    ORDER BY 
        p.denominacion
    LIMIT limit_param
    OFFSET offset_param;
END;
$$;

-- =====================================================
-- Comentarios de la función
-- =====================================================
COMMENT ON FUNCTION get_productos_marketplace(bigint, bigint, boolean, text, integer, integer) IS 
'Obtiene productos para el marketplace con filtros opcionales de tienda, categoría y búsqueda. 
Incluye búsqueda fonética en múltiples campos, información de stock total, rating promedio, 
presentaciones del producto, metadatos extendidos y paginación.';

-- =====================================================
-- Ejemplos de uso
-- =====================================================

-- Obtener todos los productos de todas las tiendas
-- SELECT * FROM get_productos_marketplace();

-- Obtener productos de una tienda específica
-- SELECT * FROM get_productos_marketplace(id_tienda_param := 1);

-- Obtener productos de una categoría específica
-- SELECT * FROM get_productos_marketplace(id_categoria_param := 5);

-- Obtener productos de una tienda y categoría específicas
-- SELECT * FROM get_productos_marketplace(id_tienda_param := 1, id_categoria_param := 5);

-- Obtener solo productos con stock disponible
-- SELECT * FROM get_productos_marketplace(solo_disponibles_param := true);

-- Obtener productos con stock de una categoría específica
-- SELECT * FROM get_productos_marketplace(id_categoria_param := 5, solo_disponibles_param := true);

-- Buscar productos por texto (búsqueda fonética)
-- SELECT * FROM get_productos_marketplace(search_query_param := 'cerveza');

-- Buscar productos sin acentos (encuentra "Piña" buscando "pina")
-- SELECT * FROM get_productos_marketplace(search_query_param := 'pina');

-- Buscar por SKU o código de barras
-- SELECT * FROM get_productos_marketplace(search_query_param := 'SKU-123');

-- Búsqueda combinada con categoría
-- SELECT * FROM get_productos_marketplace(id_categoria_param := 5, search_query_param := 'cristal');
