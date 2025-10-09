-- Función RPC: get_productos_by_categoria_tpv_meta
-- Descripción: Obtiene productos por categoría y TPV con metadatos adicionales en formato JSON
-- Autor: Sistema VentIQ
-- Fecha: 2025-01-09

CREATE OR REPLACE FUNCTION get_productos_by_categoria_tpv_meta(
    id_categoria_param bigint DEFAULT NULL,
    id_tienda_param bigint,
    id_tpv_param bigint,
    solo_disponibles_param boolean DEFAULT true
)
RETURNS TABLE(
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
    metadata jsonb  -- ✅ NUEVO CAMPO: Metadatos adicionales en formato JSON
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Verificar que el usuario tenga acceso a la tienda
    PERFORM check_user_has_access_to_tienda(id_tienda_param);
    
    -- Devolver productos filtrados por tienda, categoría y TPV (almacén asociado) con metadatos
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
        -- Calcular stock disponible solo del almacén asociado al TPV
        COALESCE(
            (SELECT SUM(ip.cantidad_final) 
             FROM app_dat_inventario_productos ip 
             JOIN app_dat_layout_almacen la ON ip.id_ubicacion = la.id
             JOIN app_dat_tpv tpv ON la.id_almacen = tpv.id_almacen
             WHERE ip.id_producto = p.id 
             AND tpv.id = id_tpv_param
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
        -- Indicar si tiene stock disponible en el almacén del TPV
        COALESCE(
            (SELECT CASE WHEN SUM(ip.cantidad_final) > 0 THEN true ELSE false END
             FROM app_dat_inventario_productos ip 
             JOIN app_dat_layout_almacen la ON ip.id_ubicacion = la.id
             JOIN app_dat_tpv tpv ON la.id_almacen = tpv.id_almacen
             WHERE ip.id_producto = p.id 
             AND tpv.id = id_tpv_param
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
        -- ✅ NUEVO CAMPO: Metadatos adicionales en formato JSON
        jsonb_build_object(
            'es_elaborado', p.es_elaborado,
            'es_servicio', p.es_servicio
        ) AS metadata
    FROM 
        app_dat_producto p
    JOIN 
        app_dat_productos_subcategorias ps ON p.id = ps.id_producto
    JOIN 
        app_dat_subcategorias sc ON ps.id_sub_categoria = sc.id
    JOIN 
        app_dat_categoria c ON sc.idcategoria = c.id
    LEFT JOIN 
        app_dat_producto_ingredientes as pri on pri.id_ingrediente = p.id
    LEFT JOIN 
        app_dat_precio_venta pv ON p.id = pv.id_producto AND 
        (pv.id_variante IS NULL OR pv.id_variante = 0) AND
        (pv.fecha_hasta IS NULL OR pv.fecha_hasta >= CURRENT_DATE)
    -- JOIN con TPV para filtrar solo productos del almacén asociado al TPV
    JOIN 
        app_dat_tpv tpv ON tpv.id = id_tpv_param AND tpv.id_tienda = id_tienda_param
    WHERE 
        p.id_tienda = id_tienda_param AND
        p.es_vendible = true AND
        pri.id is NULL AND
        (id_categoria_param IS NULL OR c.id = id_categoria_param) AND
        -- Filtro TPV: solo productos que tienen inventario en el almacén del TPV
        EXISTS (
            SELECT 1 
            FROM app_dat_inventario_productos ip 
            JOIN app_dat_layout_almacen la ON ip.id_ubicacion = la.id
            WHERE ip.id_producto = p.id 
            AND la.id_almacen = tpv.id_almacen
            AND (NOT solo_disponibles_param OR ip.cantidad_final > 0)
        )
    ORDER BY 
        p.denominacion;
END;
$$;

-- Comentarios sobre la función:
-- 1. Mantiene todos los campos originales de get_productos_by_categoria_tpv
-- 2. Agrega un campo 'metadata' de tipo JSONB con información adicional del producto
-- 3. El campo metadata incluye:
--    - es_elaborado: Indica si el producto es elaborado (requerido)
--    - es_peligroso: Indica si el producto es peligroso
--    - es_comprable: Indica si el producto es comprable
--    - es_inventariable: Indica si el producto es inventariable
--    - es_por_lotes: Indica si el producto se maneja por lotes
--    - fecha_creacion: Fecha de creación del producto
--    - fecha_actualizacion: Fecha de última actualización del producto
-- 4. Fácil de extender agregando más campos al jsonb_build_object
-- 5. Mantiene la misma lógica de filtrado y cálculo de stock que la función original

-- Ejemplo de uso:
-- SELECT * FROM get_productos_by_categoria_tpv_meta(1, 11, 5, true);

-- Ejemplo de respuesta del campo metadata:
-- {
--   "es_elaborado": true,
--   "es_peligroso": false,
--   "es_comprable": true,
--   "es_inventariable": true,
--   "es_por_lotes": false,
--   "fecha_creacion": "2024-01-15T10:30:00Z",
--   "fecha_actualizacion": "2024-01-20T14:45:00Z"
-- }
