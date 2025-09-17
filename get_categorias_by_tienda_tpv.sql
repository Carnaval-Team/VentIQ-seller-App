CREATE OR REPLACE FUNCTION get_categorias_by_tienda_tpv(
    p_tienda_id bigint,
    p_tpv_id bigint
)
RETURNS TABLE(
    id bigint, 
    nombre text, 
    descripcion text, 
    tienda_id bigint, 
    imagen text,
    total_productos bigint
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Verificar que el usuario tenga acceso a la tienda
    PERFORM check_user_has_access_to_tienda(p_tienda_id);
    
    -- Devolver categorías con conteo de productos filtrados por tienda y TPV
    RETURN QUERY
    SELECT 
        c.id,
        c.denominacion AS nombre,
        c.descripcion,
        ct.id_tienda AS tienda_id,
        c.image AS imagen,
        COUNT(DISTINCT p.id)::bigint AS total_productos
    FROM 
        public.app_dat_categoria c
    JOIN 
        public.app_dat_categoria_tienda ct ON c.id = ct.id_categoria
    JOIN 
        app_dat_subcategorias sc ON c.id = sc.idcategoria
    JOIN 
        app_dat_productos_subcategorias ps ON sc.id = ps.id_sub_categoria
    JOIN 
        app_dat_producto p ON ps.id_producto = p.id
    -- JOIN con TPV para filtrar solo productos del almacén asociado al TPV
    JOIN 
        app_dat_tpv tpv ON tpv.id = p_tpv_id AND tpv.id_tienda = p_tienda_id
    WHERE 
        ct.id_tienda = p_tienda_id
        AND p.id_tienda = p_tienda_id
        AND p.es_vendible = true
        -- Filtro TPV: solo productos que tienen inventario en el almacén del TPV
        AND EXISTS (
            SELECT 1 
            FROM app_dat_inventario_productos ip 
            JOIN app_dat_layout_almacen la ON ip.id_ubicacion = la.id
            WHERE ip.id_producto = p.id 
            AND la.id_almacen = tpv.id_almacen
            AND ip.cantidad_final > 0
        )
    GROUP BY 
        c.id, c.denominacion, c.descripcion, ct.id_tienda, c.image
    HAVING 
        COUNT(DISTINCT p.id) > 0  -- Solo categorías con productos disponibles
    ORDER BY 
        c.denominacion;
END;
$$;
