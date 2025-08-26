CREATE OR REPLACE FUNCTION get_productos_completos_by_tienda(
    id_tienda_param bigint,
    id_categoria_param bigint DEFAULT NULL,
    solo_disponibles_param boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    productos_result jsonb[];
    producto_item jsonb;
    inventario_data jsonb[];
BEGIN
    -- Verificar que el usuario tenga acceso a la tienda
    PERFORM check_user_has_access_to_tienda(id_tienda_param);
    
    -- Construir array de productos con detalles completos
    SELECT array_agg(
        jsonb_build_object(
            -- Información básica del producto
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
            'codigo_barras', p.codigo_barras,
            'imagen', p.imagen,
            
            -- Información de categoría
            'categoria', jsonb_build_object(
                'id', c.id,
                'denominacion', c.denominacion,
                'sku_codigo', c.sku_codigo
            ),
            
            -- Precio actual
            'precio_venta', COALESCE((
                SELECT precio_venta_cup 
                FROM app_dat_precio_venta 
                WHERE id_producto = p.id 
                AND (id_variante IS NULL OR id_variante = 0)
                AND (fecha_hasta IS NULL OR fecha_hasta >= CURRENT_DATE)
                ORDER BY fecha_desde DESC LIMIT 1
            ), 0),
            
            -- Subcategorías
            'subcategorias', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                    'id', sc.id,
                    'denominacion', sc.denominacion,
                    'sku_codigo', sc.sku_codigo
                ))
                FROM app_dat_productos_subcategorias ps
                JOIN app_dat_subcategorias sc ON ps.id_sub_categoria = sc.id
                WHERE ps.id_producto = p.id
            ), '[]'::jsonb),
            
            -- Presentaciones
            'presentaciones', COALESCE((
                SELECT jsonb_agg(jsonb_build_object(
                    'id', pp.id,
                    'presentacion', np.denominacion,
                    'cantidad', pp.cantidad,
                    'es_base', pp.es_base,
                    'sku_codigo', np.sku_codigo
                ))
                FROM app_dat_producto_presentacion pp
                JOIN app_nom_presentacion np ON pp.id_presentacion = np.id
                WHERE pp.id_producto = p.id
            ), '[]'::jsonb),
            
            -- Multimedia
            'multimedias', COALESCE((
                SELECT jsonb_agg(media)
                FROM app_dat_producto_multimedias
                WHERE id_producto = p.id
            ), '[]'::jsonb),
            
            -- Etiquetas
            'etiquetas', COALESCE((
                SELECT jsonb_agg(etiqueta)
                FROM app_dat_producto_etiquetas
                WHERE id_producto = p.id
            ), '[]'::jsonb),
            
            -- Stock disponible total
            'stock_disponible', COALESCE(
                (SELECT SUM(ip.cantidad_final) 
                 FROM app_dat_inventario_productos ip 
                 WHERE ip.id_producto = p.id 
                 AND ip.cantidad_final > 0
                 AND ip.id = (
                     SELECT MAX(id) 
                     FROM app_dat_inventario_productos 
                     WHERE id_producto = ip.id_producto 
                     AND COALESCE(id_variante, 0) = COALESCE(ip.id_variante, 0)
                     AND COALESCE(id_opcion_variante, 0) = COALESCE(ip.id_opcion_variante, 0)
                     AND COALESCE(id_presentacion, 0) = COALESCE(ip.id_presentacion, 0)
                     AND COALESCE(id_ubicacion, 0) = COALESCE(ip.id_ubicacion, 0)
                 )),
                0
            ),
            
            -- Indicador de stock disponible
            'tiene_stock', EXISTS (
                SELECT 1 
                FROM app_dat_inventario_productos ip 
                WHERE ip.id_producto = p.id 
                AND ip.cantidad_final > 0
                AND ip.id = (
                    SELECT MAX(id) 
                    FROM app_dat_inventario_productos 
                    WHERE id_producto = ip.id_producto 
                    AND COALESCE(id_variante, 0) = COALESCE(ip.id_variante, 0)
                    AND COALESCE(id_opcion_variante, 0) = COALESCE(ip.id_opcion_variante, 0)
                    AND COALESCE(id_presentacion, 0) = COALESCE(ip.id_presentacion, 0)
                    AND COALESCE(id_ubicacion, 0) = COALESCE(ip.id_ubicacion, 0)
                )
            ),
            
            -- Inventario detallado por variantes/presentaciones/ubicaciones
            'inventario', COALESCE((
                SELECT jsonb_agg(
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
                        'presentacion', CASE
                            WHEN pp.id IS NOT NULL THEN jsonb_build_object(
                                'id', pp.id,
                                'denominacion', np.denominacion,
                                'sku_codigo', np.sku_codigo,
                                'cantidad', pp.cantidad
                            )
                            ELSE NULL
                        END,
                        'ubicacion', CASE
                            WHEN la.id IS NOT NULL THEN jsonb_build_object(
                                'id', la.id,
                                'denominacion', la.denominacion,
                                'sku_codigo', la.sku_codigo,
                                'almacen', jsonb_build_object(
                                    'id', alm.id,
                                    'denominacion', alm.denominacion
                                )
                            )
                            ELSE NULL
                        END,
                        'cantidad_disponible', ip.cantidad_final,
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
                )
                FROM app_dat_inventario_productos ip
                LEFT JOIN app_dat_variantes v ON ip.id_variante = v.id
                LEFT JOIN app_dat_atributos a ON v.id_atributo = a.id
                LEFT JOIN app_dat_atributo_opcion ao ON ip.id_opcion_variante = ao.id
                LEFT JOIN app_dat_producto_presentacion pp ON ip.id_presentacion = pp.id
                LEFT JOIN app_nom_presentacion np ON pp.id_presentacion = np.id
                LEFT JOIN app_dat_layout_almacen la ON ip.id_ubicacion = la.id
                LEFT JOIN app_dat_almacen alm ON la.id_almacen = alm.id
                LEFT JOIN app_dat_proveedor pr ON ip.id_proveedor = pr.id
                WHERE ip.id_producto = p.id
                AND ip.cantidad_final > 0
                AND ip.id = (
                    SELECT MAX(id) 
                    FROM app_dat_inventario_productos 
                    WHERE id_producto = ip.id_producto 
                    AND COALESCE(id_variante, 0) = COALESCE(ip.id_variante, 0)
                    AND COALESCE(id_opcion_variante, 0) = COALESCE(ip.id_opcion_variante, 0)
                    AND COALESCE(id_presentacion, 0) = COALESCE(ip.id_presentacion, 0)
                    AND COALESCE(id_ubicacion, 0) = COALESCE(ip.id_ubicacion, 0)
                )
            ), '[]'::jsonb)
        )
        ORDER BY p.denominacion
    ) INTO productos_result
    FROM 
        app_dat_producto p
    JOIN 
        app_dat_categoria c ON p.id_categoria = c.id
    WHERE 
        p.id_tienda = id_tienda_param AND
        p.es_vendible = true AND
        (id_categoria_param IS NULL OR c.id = id_categoria_param) AND
        -- Filtro de productos disponibles si se solicita
        (NOT solo_disponibles_param OR EXISTS (
            SELECT 1 
            FROM app_dat_inventario_productos ip 
            WHERE ip.id_producto = p.id 
            AND ip.cantidad_final > 0
            AND ip.id = (
                SELECT MAX(id) 
                FROM app_dat_inventario_productos 
                WHERE id_producto = ip.id_producto 
                AND COALESCE(id_variante, 0) = COALESCE(ip.id_variante, 0)
                AND COALESCE(id_opcion_variante, 0) = COALESCE(ip.id_opcion_variante, 0)
                AND COALESCE(id_presentacion, 0) = COALESCE(ip.id_presentacion, 0)
                AND COALESCE(id_ubicacion, 0) = COALESCE(ip.id_ubicacion, 0)
            )
        ));
    
    -- Retornar resultado estructurado
    RETURN jsonb_build_object(
        'tienda_id', id_tienda_param,
        'categoria_id', id_categoria_param,
        'solo_disponibles', solo_disponibles_param,
        'total_productos', COALESCE(array_length(productos_result, 1), 0),
        'productos', COALESCE(to_jsonb(productos_result), '[]'::jsonb)
    );
END;
$$;
