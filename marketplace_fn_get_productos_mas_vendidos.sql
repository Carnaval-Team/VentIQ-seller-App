-- =====================================================
-- FUNCIÓN RPC: Obtener productos más vendidos del marketplace
-- =====================================================
-- Esta función obtiene los productos más vendidos basándose en:
-- - Ventas de los últimos 30 días
-- - Stock disponible
-- - Ratings de usuarios
-- - Información completa de producto, tienda y categoría
-- =====================================================

CREATE OR REPLACE FUNCTION public.fn_get_productos_mas_vendidos(
    p_limit INT DEFAULT 10,
    p_id_categoria BIGINT DEFAULT NULL
)
RETURNS TABLE (
    id_producto BIGINT,
    nombre VARCHAR,
    descripcion VARCHAR,
    imagen TEXT,
    precio_venta NUMERIC,
    precio_oferta NUMERIC,
    tiene_oferta BOOLEAN,
    porcentaje_descuento NUMERIC,
    categoria_nombre VARCHAR,
    subcategoria_nombre VARCHAR,
    id_tienda BIGINT,
    tienda_nombre VARCHAR,
    tienda_ubicacion VARCHAR,
    total_vendido BIGINT,
    rating_promedio NUMERIC,
    total_ratings BIGINT,
    stock_disponible BIGINT
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    WITH ventas_productos AS (
        -- Calcular total vendido por producto en los últimos 30 días
        SELECT 
            ep.id_producto,
            SUM(ep.cantidad) as cantidad_vendida
        FROM public.app_dat_extraccion_productos ep
        INNER JOIN public.app_dat_operaciones op ON ep.id_operacion = op.id
        INNER JOIN public.app_dat_operacion_venta ov ON op.id = ov.id_operacion
        WHERE op.created_at >= NOW() - INTERVAL '30 days'
        GROUP BY ep.id_producto
    ),
    ratings_productos AS (
        -- Calcular rating promedio por producto
        SELECT 
            pr.id_producto,
            ROUND(AVG(pr.rating)::numeric, 1) as rating_avg,
            COUNT(pr.id) as rating_count
        FROM public.app_dat_producto_rating pr
        GROUP BY pr.id_producto
    ),
    stock_productos AS (
        -- Calcular stock disponible por producto
        SELECT 
            ip.id_producto,
            SUM(ip.cantidad_final) as stock_total
        FROM public.app_dat_inventario_productos ip
        WHERE ip.cantidad_final > 0
        GROUP BY ip.id_producto
    ),
    precios_productos AS (
        -- Obtener precios de venta de productos
        SELECT DISTINCT ON (pv.id_producto)
            pv.id_producto,
            pv.precio_venta,
            pv.precio_oferta,
            pv.tiene_oferta
        FROM public.app_dat_precio_venta as pv
        WHERE precio_venta IS NOT NULL
        ORDER BY id_producto, created_at DESC
    )
    SELECT 
        p.id as id_producto,
        p.denominacion as nombre,
        p.descripcion,
        p.imagen,
        COALESCE(pv.precio_venta, 0) as precio_venta,
        pv.precio_oferta,
        COALESCE(pv.tiene_oferta, false) as tiene_oferta,
        CASE 
            WHEN pv.tiene_oferta AND pv.precio_oferta IS NOT NULL AND pv.precio_venta > 0 
            THEN ROUND(((pv.precio_venta - pv.precio_oferta) / pv.precio_venta * 100)::numeric, 0)
            ELSE 0
        END as porcentaje_descuento,
        cat.denominacion as categoria_nombre,
        sub.denominacion as subcategoria_nombre,
        t.id as id_tienda,
        t.denominacion as tienda_nombre,
        t.ubicacion as tienda_ubicacion,
        COALESCE(vp.cantidad_vendida, 0) as total_vendido,
        COALESCE(rp.rating_avg, 0.0) as rating_promedio,
        COALESCE(rp.rating_count, 0) as total_ratings,
        COALESCE(sp.stock_total, 0) as stock_disponible
    FROM public.app_dat_producto p
    INNER JOIN public.app_dat_tienda t ON p.id_tienda = t.id
    LEFT JOIN precios_productos pv ON p.id = pv.id_producto
    LEFT JOIN public.app_dat_productos_subcategorias psc ON p.id = psc.id_producto
    LEFT JOIN public.app_dat_subcategorias sub ON psc.id_sub_categoria = sub.id
    LEFT JOIN public.app_dat_categoria cat ON p.id_categoria = cat.id
    LEFT JOIN ventas_productos vp ON p.id = vp.id_producto
    LEFT JOIN ratings_productos rp ON p.id = rp.id_producto
    LEFT JOIN stock_productos sp ON p.id = sp.id_producto
    WHERE p.deleted_at IS NULL
        AND p.es_vendible = true
        AND COALESCE(sp.stock_total, 0) > 0 -- Solo productos con stock
        AND (p_id_categoria IS NULL OR cat.id = p_id_categoria)
    ORDER BY 
        COALESCE(vp.cantidad_vendida, 0) DESC,
        COALESCE(rp.rating_avg, 0) DESC,
        p.created_at DESC
    LIMIT p_limit;
END;
$$;

-- Comentarios
COMMENT ON FUNCTION public.fn_get_productos_mas_vendidos IS 'Obtiene los productos más vendidos del marketplace con información completa de ventas, ratings y stock';

-- Ejemplos de uso:
-- SELECT * FROM fn_get_productos_mas_vendidos(10, NULL); -- Top 10 de todas las categorías
-- SELECT * FROM fn_get_productos_mas_vendidos(5, 1); -- Top 5 de la categoría 1
-- SELECT * FROM fn_get_productos_mas_vendidos(20, NULL); -- Top 20 general
