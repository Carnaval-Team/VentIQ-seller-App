CREATE OR REPLACE FUNCTION fn_get_productos_recomendados_v2(
    id_usuario_param uuid,
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
DECLARE
    v_usuario uuid;
BEGIN
    v_usuario := auth.uid();

    IF v_usuario IS NULL THEN
        v_usuario := id_usuario_param;
    ELSIF id_usuario_param IS NOT NULL AND v_usuario <> id_usuario_param THEN
        RAISE EXCEPTION 'No autorizado';
    END IF;

    RETURN QUERY
    WITH subs_producto AS (
        SELECT sp.id_producto
        FROM app_dat_suscripcion_notificaciones_producto sp
        WHERE sp.id_usuario = v_usuario
          AND sp.activo = true
    ),
    subs_tienda AS (
        SELECT st.id_tienda
        FROM app_dat_suscripcion_notificaciones_tienda st
        WHERE st.id_usuario = v_usuario
          AND st.activo = true
    ),
    rating_agg AS (
        SELECT pr.id_producto,
               ROUND(AVG(pr.rating), 1) AS rating_promedio,
               COUNT(*) AS total_ratings
        FROM app_dat_producto_rating pr
        GROUP BY pr.id_producto
    )
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
        COALESCE(
            (SELECT SUM(ip.cantidad_final) 
             FROM app_dat_inventario_productos ip 
             WHERE ip.id_producto = p.id 
               AND ip.cantidad_final > 0
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
        COALESCE(
            (SELECT CASE WHEN SUM(ip.cantidad_final) > 0 THEN true ELSE false END
             FROM app_dat_inventario_productos ip 
             WHERE ip.id_producto = p.id 
               AND ip.cantidad_final > 0
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
        jsonb_build_object(
            'es_elaborado', p.es_elaborado,
            'es_servicio', p.es_servicio,
            'denominacion_tienda', t.denominacion,
            'id_tienda', t.id,
            'ubicacion', t.ubicacion,
            'direccion', t.direccion,
            'provincia', t.provincia,
            'municipio', t.municipio,
            'rating_promedio', COALESCE(ra.rating_promedio, 0.0),
            'total_ratings', COALESCE(ra.total_ratings, 0),
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
            ),
            'suscrito_producto', (sp.id_producto IS NOT NULL),
            'suscrito_tienda', (st.id_tienda IS NOT NULL)
        ) AS metadata
    FROM app_dat_producto p
    JOIN app_dat_tienda t ON p.id_tienda = t.id
    JOIN app_dat_productos_subcategorias ps ON p.id = ps.id_producto
    JOIN app_dat_subcategorias sc ON ps.id_sub_categoria = sc.id
    JOIN app_dat_categoria c ON sc.idcategoria = c.id
    LEFT JOIN app_dat_producto_ingredientes pri ON pri.id_ingrediente = p.id
    LEFT JOIN app_dat_precio_venta pv ON p.id = pv.id_producto AND 
        (pv.id_variante IS NULL OR pv.id_variante = 0) AND
        (pv.fecha_hasta IS NULL OR pv.fecha_hasta >= CURRENT_DATE)
    LEFT JOIN subs_producto sp ON sp.id_producto = p.id
    LEFT JOIN subs_tienda st ON st.id_tienda = p.id_tienda
    LEFT JOIN rating_agg ra ON ra.id_producto = p.id
    WHERE p.es_vendible = true
      AND pri.id IS NULL
      AND EXISTS (
          SELECT 1 
          FROM app_dat_inventario_productos ip 
          WHERE ip.id_producto = p.id 
            AND ip.cantidad_final > 0
      )
    ORDER BY 
        CASE
            WHEN sp.id_producto IS NOT NULL THEN 2
            WHEN st.id_tienda IS NOT NULL THEN 1
            ELSE 0
        END DESC,
        (
            (COALESCE(ra.rating_promedio, 0.0) * LN(COALESCE(ra.total_ratings, 0) + 1)) +
            (CASE WHEN stock_disponible > 50 THEN 1.0 ELSE 0.0 END)
        ) DESC,
        p.denominacion
    LIMIT limit_param
    OFFSET offset_param;
END;
$$;
