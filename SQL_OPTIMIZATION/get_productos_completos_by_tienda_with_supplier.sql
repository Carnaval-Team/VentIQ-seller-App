
DECLARE
    productos_result jsonb;
    tiene_suscripcion_activa BOOLEAN := FALSE;
    primer_producto RECORD;
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
        SELECT id, sku, id_categoria, um, es_refrigerado, es_fragil, es_peligroso, 
               es_vendible, es_servicio, codigo_barras, imagen
        INTO primer_producto
        FROM app_dat_producto 
        WHERE id_tienda = id_tienda_param 
        LIMIT 1;
        
        -- Si no hay productos, usar valores por defecto
        IF primer_producto IS NULL THEN
            primer_producto.id := 999999;
            primer_producto.sku := 'CONTACT-ADMIN';
            primer_producto.id_categoria := 1;
            primer_producto.um := 'Unidad';
            primer_producto.es_refrigerado := FALSE;
            primer_producto.es_fragil := FALSE;
            primer_producto.es_peligroso := FALSE;
            primer_producto.es_vendible := FALSE;
            primer_producto.es_servicio := TRUE;
            primer_producto.codigo_barras := '';
            primer_producto.imagen := '';
        END IF;
        
        -- Retornar producto de contacto con estructura completa
        RETURN jsonb_build_object(
            'tienda_id', id_tienda_param,
            'categoria_id', id_categoria_param,
            'solo_disponibles', solo_disponibles_param,
            'proveedor_id', id_proveedor_param,
            'total_productos', 1,
            'productos', jsonb_build_array(
                jsonb_build_object(
                    'id', primer_producto.id,
                    'sku', COALESCE(primer_producto.sku, 'CONTACT-ADMIN'),
                    'denominacion', 'CONTACTAR A ADMINISTRACION',
                    'nombre_comercial', 'Contacto Administración',
                    'descripcion', 'escribir a supportinventtia@gmail.com o via whatsapp al 53765120',
                    'um', COALESCE(primer_producto.um, 'Unidad'),
                    'es_refrigerado', COALESCE(primer_producto.es_refrigerado, FALSE),
                    'es_fragil', COALESCE(primer_producto.es_fragil, FALSE),
                    'es_peligroso', COALESCE(primer_producto.es_peligroso, FALSE),
                    'es_vendible', FALSE,
                    'es_elaborado', FALSE,
                    'es_servicio', COALESCE(primer_producto.es_servicio, TRUE),
                    'codigo_barras', COALESCE(primer_producto.codigo_barras, ''),
                    'imagen', COALESCE(primer_producto.imagen, ''),
                    'categoria', jsonb_build_object(
                        'id', primer_producto.id_categoria,
                        'denominacion', 'Administración',
                        'sku_codigo', 'ADMIN'
                    ),
                    'precio_venta', 0,
                    'stock_disponible', 0,
                    'tiene_stock', FALSE,
                    'subcategorias', '[]'::jsonb,
                    'presentaciones', '[]'::jsonb,
                    'multimedias', '[]'::jsonb,
                    'etiquetas', '[]'::jsonb,
                    'variantes_disponibles', '[]'::jsonb,
                    'inventario', '[]'::jsonb
                )
            )
        );
    END IF;
    
    -- CTE para stock total por producto
    WITH proveedores_productos AS (
        -- Obtener todos los productos únicos de un proveedor
        SELECT DISTINCT id_producto
        FROM app_dat_inventario_productos
        WHERE id_proveedor = id_proveedor_param
    ),
    stock_productos AS (
        SELECT 
            i.id_producto,
            ROUND(SUM(i.cantidad_final))::integer as stock_total,
            COUNT(*) > 0 as tiene_stock
        FROM app_dat_inventario_productos i
        WHERE (id_proveedor_param IS NULL OR i.id_proveedor = id_proveedor_param)
        GROUP BY i.id_producto
    ),
    precios_actuales AS (
        SELECT DISTINCT ON (id_producto)
            id_producto,
            precio_venta_cup
        FROM app_dat_precio_venta
        WHERE (id_variante IS NULL OR id_variante = 0)
        AND (fecha_hasta IS NULL OR fecha_hasta >= CURRENT_DATE)
        ORDER BY id_producto, fecha_desde DESC
    )
    SELECT jsonb_build_object(
        'tienda_id', id_tienda_param,
        'categoria_id', id_categoria_param,
        'solo_disponibles', solo_disponibles_param,
        'proveedor_id', id_proveedor_param,
        'total_productos', COUNT(*),
        'productos', jsonb_agg(
            jsonb_build_object(
                'id', p.id,
                'sku', p.sku,
                'denominacion', p.denominacion,
                'nombre_comercial', p.nombre_comercial,
                'descripcion', p.descripcion,
                'um', p.um,
                'es_refrigerado', p.es_refrigerado,
                'es_fragil', p.es_fragil,
                'es_peligroso', p.es_peligroso,
                'es_vendible', p.es_vendible,
                'es_elaborado', p.es_elaborado,
                'es_servicio', p.es_servicio,
                'codigo_barras', p.codigo_barras,
                'imagen', p.imagen,
                'categoria', jsonb_build_object(
                    'id', c.id,
                    'denominacion', c.denominacion,
                    'sku_codigo', c.sku_codigo
                ),
                'precio_venta', COALESCE(pa.precio_venta_cup, 0),
                'stock_disponible', COALESCE(sp.stock_total, 0),
                'tiene_stock', COALESCE(sp.tiene_stock, false),
                'subcategorias', '[]'::jsonb,
                'presentaciones', '[]'::jsonb,
                'multimedias', '[]'::jsonb,
                'etiquetas', '[]'::jsonb,
                'variantes_disponibles', '[]'::jsonb,
                'inventario', '[]'::jsonb
            )
        )
    ) INTO productos_result
    FROM app_dat_producto p
    JOIN app_dat_categoria c ON p.id_categoria = c.id
    LEFT JOIN stock_productos sp ON p.id = sp.id_producto
    LEFT JOIN precios_actuales pa ON p.id = pa.id_producto
    WHERE 
        p.id_tienda = id_tienda_param 
        AND p.es_vendible = true
        AND (id_categoria_param IS NULL OR c.id = id_categoria_param)
        AND (NOT solo_disponibles_param OR sp.tiene_stock = true)
        AND (
            id_proveedor_param IS NULL 
            OR p.id IN (SELECT id_producto FROM proveedores_productos)
        )
    GROUP BY p.id, p.sku, p.denominacion, p.nombre_comercial, p.descripcion, 
             p.um, p.es_refrigerado, p.es_fragil, p.es_peligroso, p.es_vendible, p.es_servicio,
             p.codigo_barras, p.imagen, c.id, c.denominacion, c.sku_codigo,
             pa.precio_venta_cup, sp.stock_total, sp.tiene_stock, p.es_elaborado
    ORDER BY p.denominacion;
    
    RETURN productos_result;
END;
