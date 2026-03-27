DECLARE
    producto_data JSONB;
    inventario_data JSONB[];
    user_has_access boolean;
    almacenes_accesibles BIGINT[];
BEGIN
    -- -- Verificar que el usuario tenga acceso al producto (a través de la tienda)
    
    SELECT EXISTS (
        SELECT 1 FROM app_dat_producto p
        JOIN (
            -- Gerentes y supervisores de la tienda
            SELECT id_tienda FROM app_dat_gerente WHERE uuid = auth.uid()
            UNION
            SELECT id_tienda FROM app_dat_supervisor WHERE uuid = auth.uid()
            
            UNION
            
            -- Almaceneros de la tienda
            SELECT a.id_tienda FROM app_dat_almacenero al
            JOIN app_dat_almacen a ON al.id_almacen = a.id
            WHERE al.uuid = auth.uid()
            
            UNION
            
            -- Vendedores de la tienda
            SELECT tpv.id_tienda FROM app_dat_vendedor v
            JOIN app_dat_tpv tpv ON v.id_tpv = tpv.id
            WHERE v.uuid = auth.uid()
        ) AS usuarios_tienda ON p.id_tienda = usuarios_tienda.id_tienda
        WHERE p.id = id_producto_param
    ) INTO user_has_access;
    
    IF NOT user_has_access THEN
        RAISE EXCEPTION 'Acceso denegado: No tienes permisos para ver este producto';
    END IF;
    SELECT ARRAY(
        SELECT DISTINCT almacen_id FROM (
            SELECT tpv.id_almacen as almacen_id
            FROM app_dat_vendedor v
            JOIN app_dat_tpv tpv ON v.id_tpv = tpv.id
            WHERE v.uuid = auth.uid()
        ) AS almacenes_usuario
    ) INTO almacenes_accesibles;
    -- Obtener datos generales del producto
    SELECT jsonb_build_object(
        'id', p.id,
        'sku', p.sku,
        'denominacion', p.denominacion,
        'nombre_comercial', p.nombre_comercial,
        'descripcion', p.descripcion,
        'um', p.um,
        'es_refrigerado', p.es_refrigerado,
        'es_fragil', p.es_fragil,
        'es_peligroso', p.es_peligroso,
        'es_elaborado',p.es_elaborado,
        'codigo_barras', p.codigo_barras,
        'imagen', p.imagen,
        'categoria', jsonb_build_object(
            'id', c.id,
            'denominacion', c.denominacion,
            'sku_codigo', c.sku_codigo
        ),
        'precio_actual', COALESCE((
            SELECT precio_venta_cup 
            FROM app_dat_precio_venta 
            WHERE id_producto = p.id 
            --AND (id_variante IS NULL OR id_variante = 0)
            AND (fecha_hasta IS NULL OR fecha_hasta >= CURRENT_DATE)
            ORDER BY fecha_desde DESC LIMIT 1
        ), 0),
        'subcategorias', (
            SELECT jsonb_agg(jsonb_build_object(
                'id', sc.id,
                'denominacion', sc.denominacion,
                'sku_codigo', sc.sku_codigo
            ))
            FROM app_dat_productos_subcategorias ps
            JOIN app_dat_subcategorias sc ON ps.id_sub_categoria = sc.id
            WHERE ps.id_producto = p.id
        ),
        'presentaciones', (
            SELECT jsonb_agg(jsonb_build_object(
                'id', pp.id,
                'presentacion', np.denominacion,
                'es_fraccionable',np.es_fraccionable,
                'cantidad', pp.cantidad,
                'es_base', pp.es_base,
                'sku_codigo', np.sku_codigo
            ))
            FROM app_dat_producto_presentacion pp
            JOIN app_nom_presentacion np ON pp.id_presentacion = np.id
            WHERE pp.id_producto = p.id
        ),
        'multimedias', (
            SELECT jsonb_agg(media)
            FROM app_dat_producto_multimedias
            WHERE id_producto = p.id
        ),
        'etiquetas', (
            SELECT jsonb_agg(etiqueta)
            FROM app_dat_producto_etiquetas
            WHERE id_producto = p.id
        )
    ) INTO producto_data
    FROM app_dat_producto p
    JOIN app_dat_categoria c ON p.id_categoria = c.id
    WHERE p.id = id_producto_param;
    
    -- Obtener datos de inventario disponible (cantidad final > 0)
    SELECT array_agg(
        jsonb_build_object(
            'id_inventario', ip.id,
            'variante', CASE 
                WHEN v.id IS NOT NULL THEN jsonb_build_object(
                    'id', v.id,
                    'atributo', jsonb_build_object(
                        'id', a.id,
                        'denominacion', a.denominacion,
                        'label', a.label
                    ),
                    'opcion', jsonb_build_object(
                        'id', ao.id,
                        'valor', ao.valor,
                        'sku_codigo', ao.sku_codigo
                    )
                )
                ELSE NULL
            END,
            'presentacion', jsonb_build_object(
                'id', pp.id,
                'denominacion', np.denominacion,
                'es_fraccionable',np.es_fraccionable,
                'sku_codigo', np.sku_codigo,
                'cantidad', pp.cantidad
            ),
            'ubicacion', jsonb_build_object(
                'id', la.id,
                'denominacion', la.denominacion,
                'sku_codigo', la.sku_codigo,
                'almacen', jsonb_build_object(
                    'id', alm.id,
                    'denominacion', alm.denominacion
                )
            ),
            'cantidad_disponible', ip.cantidad_final,
            'reservado_carnaval', COALESCE(
                (SELECT SUM(cart.quantity)
                 FROM public.relation_products_carnaval rpc
                 JOIN carnavalapp."Carrito" cart ON cart.product_id = rpc.id_producto_carnaval
                 WHERE rpc.id_producto = ip.id_producto
                 AND rpc.id_ubicacion = ip.id_ubicacion
                ), 0),
            'ultima_actualizacion', ip.created_at,
            'proveedor', CASE 
                WHEN pr.id IS NOT NULL THEN jsonb_build_object(
                    'id', pr.id,
                    'denominacion', pr.denominacion,
                    'sku_codigo', pr.sku_codigo
                )
                ELSE NULL
            END
        )
    ) INTO inventario_data
    FROM app_dat_inventario_productos ip
    LEFT JOIN app_dat_variantes v ON ip.id_variante = v.id
    LEFT JOIN app_dat_atributos a ON v.id_atributo = a.id
    LEFT JOIN app_dat_atributo_opcion ao ON ip.id_opcion_variante = ao.id
    LEFT JOIN app_dat_producto_presentacion pp ON ip.id_presentacion = pp.id
    LEFT JOIN app_nom_presentacion np ON pp.id_presentacion = np.id
    LEFT JOIN app_dat_layout_almacen la ON ip.id_ubicacion = la.id
    LEFT JOIN app_dat_almacen alm ON la.id_almacen = alm.id
    LEFT JOIN app_dat_proveedor pr ON ip.id_proveedor = pr.id
    WHERE ip.id_producto = id_producto_param
    AND ip.cantidad_final > 0
    AND alm.id = ANY(almacenes_accesibles)
    AND ip.id = (
        SELECT MAX(id) 
        FROM app_dat_inventario_productos 
        WHERE id_producto = ip.id_producto 
        AND COALESCE(id_variante, 0) = COALESCE(ip.id_variante, 0)
        AND COALESCE(id_opcion_variante, 0) = COALESCE(ip.id_opcion_variante, 0)
        AND COALESCE(id_presentacion, 0) = COALESCE(ip.id_presentacion, 0)
        AND COALESCE(id_ubicacion, 0) = COALESCE(ip.id_ubicacion, 0)
    );
    
    -- Combinar ambos resultados en un solo JSON
    RETURN jsonb_build_object(
        'producto', producto_data,
        'inventario', inventario_data
    );
END;