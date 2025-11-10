-- =====================================================
-- FUNCIÓN RPC: Obtener tiendas destacadas del marketplace
-- =====================================================
-- Esta función obtiene las tiendas destacadas basándose en:
-- - Número de ventas en los últimos 30 días
-- - Monto total de ventas
-- - Ratings de usuarios
-- - Cantidad de productos activos
-- - Actividad reciente
-- - Score compuesto para ranking
-- =====================================================

CREATE OR REPLACE FUNCTION public.fn_get_tiendas_destacadas(
    p_limit INT DEFAULT 10
)
RETURNS TABLE (
    id_tienda BIGINT,
    nombre VARCHAR,
    descripcion VARCHAR,
    direccion VARCHAR,
    ubicacion VARCHAR,
    imagen_url TEXT,
    total_productos BIGINT,
    total_ventas BIGINT,
    monto_total_ventas NUMERIC,
    rating_promedio NUMERIC,
    total_ratings BIGINT,
    productos_activos BIGINT,
    ultima_venta TIMESTAMP WITH TIME ZONE,
    score_destacado NUMERIC
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    WITH ventas_tienda AS (
        -- Calcular ventas por tienda en los últimos 30 días
        SELECT 
            p.id_tienda,
            COUNT(DISTINCT op.id) as num_ventas,
            SUM(ov.importe_total) as monto_ventas,
            MAX(op.created_at) as ultima_venta_fecha
        FROM public.app_dat_operaciones op
        INNER JOIN public.app_dat_operacion_venta ov ON op.id = ov.id_operacion
        INNER JOIN public.app_dat_extraccion_productos ep ON op.id = ep.id_operacion
        INNER JOIN public.app_dat_producto p ON ep.id_producto = p.id
        WHERE op.created_at >= NOW() - INTERVAL '30 days'
        GROUP BY p.id_tienda
    ),
    productos_tienda AS (
        -- Contar productos por tienda
        SELECT 
            p.id_tienda,
            COUNT(*) as total_prods,
            COUNT(CASE WHEN p.deleted_at IS NULL AND p.es_vendible = true THEN 1 END) as prods_activos
        FROM public.app_dat_producto p
        GROUP BY p.id_tienda
    ),
    ratings_tienda AS (
        -- Calcular rating promedio por tienda
        SELECT 
            tr.id_tienda,
            ROUND(AVG(tr.rating)::numeric, 1) as rating_avg,
            COUNT(tr.id) as rating_count
        FROM public.app_dat_tienda_rating tr
        GROUP BY tr.id_tienda
    ),
    stock_tienda AS (
        -- Verificar que tenga stock disponible
        SELECT 
            p.id_tienda,
            SUM(ip.cantidad_final) as stock_total
        FROM public.app_dat_inventario_productos ip
        INNER JOIN public.app_dat_producto p ON ip.id_producto = p.id
        WHERE ip.cantidad_final > 0
        GROUP BY p.id_tienda
    )
    SELECT 
        t.id as id_tienda,
        t.denominacion as nombre,
        t.descripcion,
        t.direccion,
        t.ubicacion,
        t.imagen_url,
        COALESCE(pt.total_prods, 0) as total_productos,
        COALESCE(vt.num_ventas, 0) as total_ventas,
        COALESCE(vt.monto_ventas, 0) as monto_total_ventas,
        COALESCE(rt.rating_avg, 0.0) as rating_promedio,
        COALESCE(rt.rating_count, 0) as total_ratings,
        COALESCE(pt.prods_activos, 0) as productos_activos,
        vt.ultima_venta_fecha as ultima_venta,
        -- Score compuesto para ordenar tiendas destacadas
        -- Fórmula: (ventas * 0.4) + (rating * 10 * 0.3) + (productos * 0.2) + (actividad * 0.1)
        (
            (COALESCE(vt.num_ventas, 0) * 0.4) + -- 40% peso en ventas
            (COALESCE(rt.rating_avg, 0) * 10 * 0.3) + -- 30% peso en rating (normalizado a 50)
            (COALESCE(pt.prods_activos, 0) * 0.2) + -- 20% peso en productos activos
            (CASE WHEN vt.ultima_venta_fecha >= NOW() - INTERVAL '7 days' THEN 10 ELSE 0 END * 0.1) -- 10% peso en actividad reciente
        ) as score_destacado
    FROM public.app_dat_tienda t
    LEFT JOIN ventas_tienda vt ON t.id = vt.id_tienda
    LEFT JOIN productos_tienda pt ON t.id = pt.id_tienda
    LEFT JOIN ratings_tienda rt ON t.id = rt.id_tienda
    LEFT JOIN stock_tienda st ON t.id = st.id_tienda
    WHERE COALESCE(pt.prods_activos, 0) > 0 -- Solo tiendas con productos activos
        AND COALESCE(st.stock_total, 0) > 0 -- Solo tiendas con stock disponible
    ORDER BY 
        score_destacado DESC,
        COALESCE(vt.num_ventas, 0) DESC,
        COALESCE(rt.rating_avg, 0) DESC
    LIMIT p_limit;
END;
$$;

-- Comentarios
COMMENT ON FUNCTION public.fn_get_tiendas_destacadas IS 'Obtiene las tiendas destacadas del marketplace basado en ventas, ratings, productos activos y actividad reciente';

-- Ejemplos de uso:
-- SELECT * FROM fn_get_tiendas_destacadas(10); -- Top 10 tiendas destacadas
-- SELECT * FROM fn_get_tiendas_destacadas(5); -- Top 5 tiendas destacadas
-- SELECT * FROM fn_get_tiendas_destacadas(20); -- Top 20 tiendas destacadas
