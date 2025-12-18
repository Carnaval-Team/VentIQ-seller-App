CREATE OR REPLACE FUNCTION get_productos_by_categoria_tpv_meta(
    id_categoria_param BIGINT,
    id_tienda_param BIGINT,
    id_tpv_param BIGINT,
    solo_disponibles_param BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
    id_producto BIGINT,
    sku TEXT,
    denominacion TEXT,
    descripcion TEXT,
    um TEXT,
    es_refrigerado BOOLEAN,
    es_fragil BOOLEAN,
    es_vendible BOOLEAN,
    codigo_barras TEXT,
    id_subcategoria BIGINT,
    subcategoria_nombre TEXT,
    id_categoria BIGINT,
    categoria_nombre TEXT,
    precio_venta NUMERIC,
    imagen TEXT,
    stock_disponible NUMERIC,
    tiene_stock BOOLEAN,
    metadata JSONB
) 
LANGUAGE plpgsql
AS $$
DECLARE
    tiene_suscripcion_activa BOOLEAN := FALSE;
    primer_producto RECORD;
    primera_subcategoria RECORD;
    primera_categoria RECORD;
BEGIN
    -- Verificar que el usuario tenga acceso a la tienda
    PERFORM check_user_has_access_to_tienda(id_tienda_param);
    
    -- Verificar si la tienda tiene suscripción activa
    SELECT EXISTS(
        SELECT 1 
        FROM app_suscripciones 
        WHERE id_tienda = id_tienda_param 
        AND estado = 1 
        AND (fecha_fin IS NULL OR fecha_fin > NOW())
        ORDER BY created_at DESC 
        LIMIT 1
    ) INTO tiene_suscripcion_activa;
    
    -- Si no tiene suscripción activa, devolver producto de contacto
    IF NOT tiene_suscripcion_activa THEN
        -- Obtener el primer producto de la tienda para usar sus atributos
        SELECT p.id, p.sku, p.um, p.es_refrigerado, p.es_fragil, p.es_vendible, 
               p.codigo_barras, p.imagen, p.es_elaborado, p.es_servicio
        INTO primer_producto
        FROM app_dat_producto p
        WHERE p.id_tienda = id_tienda_param
        LIMIT 1;
        
        -- Obtener la primera subcategoría de la categoría solicitada
        SELECT sc.id, sc.denominacion
        INTO primera_subcategoria
        FROM app_dat_subcategorias sc
        WHERE sc.idcategoria = id_categoria_param
        LIMIT 1;
        
        -- Obtener información de la categoría
        SELECT c.id, c.denominacion
        INTO primera_categoria
        FROM app_dat_categoria c
        WHERE c.id = id_categoria_param;
        
        -- Si no hay datos, usar valores por defecto
        IF primer_producto IS NULL THEN
            primer_producto.id := 999999;
            primer_producto.sku := 'CONTACT-ADMIN';
            primer_producto.um := 'Unidad';
            primer_producto.es_refrigerado := FALSE;
            primer_producto.es_fragil := FALSE;
            primer_producto.es_vendible := FALSE;
            primer_producto.codigo_barras := '';
            primer_producto.imagen := '';
            primer_producto.es_elaborado := FALSE;
            primer_producto.es_servicio := TRUE;
        END IF;
        
        IF primera_subcategoria IS NULL THEN
            primera_subcategoria.id := 999999;
            primera_subcategoria.denominacion := 'Administración';
        END IF;
        
        IF primera_categoria IS NULL THEN
            primera_categoria.id := COALESCE(id_categoria_param, 999999);
            primera_categoria.denominacion := 'Administración';
        END IF;
        
        -- Retornar producto de contacto
        RETURN QUERY
        SELECT 
            primer_producto.id::bigint AS id_producto,
            COALESCE(primer_producto.sku, 'CONTACT-ADMIN')::text AS sku,
            'CONTACTAR VIA WHATSAPP AL 53765120 O supportinvenntia@gmail.com'::text AS denominacion,
            'escribir a supportinventtia@gmail.com o via whatsapp al 53765120'::text AS descripcion,
            COALESCE(primer_producto.um, 'Unidad')::text AS um,
            COALESCE(primer_producto.es_refrigerado, FALSE)::boolean AS es_refrigerado,
            COALESCE(primer_producto.es_fragil, FALSE)::boolean AS es_fragil,
            FALSE::boolean AS es_vendible, -- Siempre false para el producto de contacto
            COALESCE(primer_producto.codigo_barras, '')::text AS codigo_barras,
            primera_subcategoria.id::bigint AS id_subcategoria,
            primera_subcategoria.denominacion::text AS subcategoria_nombre,
            primera_categoria.id::bigint AS id_categoria,
            primera_categoria.denominacion::text AS categoria_nombre,
            0::numeric AS precio_venta,
            COALESCE(primer_producto.imagen, '')::text AS imagen,
            0::numeric AS stock_disponible,
            FALSE::boolean AS tiene_stock,
            jsonb_build_object(
                'es_elaborado', COALESCE(primer_producto.es_elaborado, FALSE),
                'es_servicio', COALESCE(primer_producto.es_servicio, TRUE)
            ) AS metadata;
        
        RETURN;
    END IF;
    
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
    -- Cambio principal aquí: LEFT JOIN LATERAL para obtener el precio más reciente
    LEFT JOIN LATERAL (
        SELECT precio_venta_cup
        FROM app_dat_precio_venta pv_inner
        WHERE pv_inner.id_producto = p.id 
        AND (pv_inner.id_variante IS NULL OR pv_inner.id_variante = 0)
        AND (pv_inner.fecha_hasta IS NULL OR pv_inner.fecha_hasta >= CURRENT_DATE)
        ORDER BY pv_inner.created_at DESC
        LIMIT 1
    ) pv ON TRUE
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
