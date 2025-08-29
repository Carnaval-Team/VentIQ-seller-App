CREATE OR REPLACE FUNCTION get_productos_completos_by_tienda_optimized(
    id_tienda_param INTEGER,
    id_categoria_param INTEGER DEFAULT NULL,
    solo_disponibles_param BOOLEAN DEFAULT FALSE
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    productos_result jsonb;
BEGIN
    -- Verificar que el usuario tenga acceso a la tienda
    PERFORM check_user_has_access_to_tienda(id_tienda_param);
    
    -- CTE para obtener el último inventario por producto/variante/presentación/ubicación
    WITH ultimo_inventario AS (
        SELECT DISTINCT ON (id_producto, COALESCE(id_variante, 0), COALESCE(id_opcion_variante, 0), 
                           COALESCE(id_presentacion, 0), COALESCE(id_ubicacion, 0))
            id_producto,
            id_variante,
            id_opcion_variante,
            id_presentacion,
            id_ubicacion,
            cantidad_final,
            id_proveedor,
            created_at,
            id as inventario_id
        FROM app_dat_inventario_productos
        WHERE cantidad_final > 0
        ORDER BY id_producto, COALESCE(id_variante, 0), COALESCE(id_opcion_variante, 0), 
                 COALESCE(id_presentacion, 0), COALESCE(id_ubicacion, 0), id DESC
    ),
    -- CTE para stock total por producto
    stock_productos AS (
        SELECT 
            id_producto,
            SUM(cantidad_final) as stock_total,
            COUNT(*) > 0 as tiene_stock
        FROM ultimo_inventario
        GROUP BY id_producto
    ),
    -- CTE para precios actuales
    precios_actuales AS (
        SELECT DISTINCT ON (id_producto)
            id_producto,
            precio_venta_cup
        FROM app_dat_precio_venta
        WHERE (id_variante IS NULL OR id_variante = 0)
        AND (fecha_hasta IS NULL OR fecha_hasta >= CURRENT_DATE)
        ORDER BY id_producto, fecha_desde DESC
    ),
    -- CTE para variantes configuradas en precios (solo las que tienen precio configurado)
    variantes_producto AS (
        SELECT 
            pv.id_producto,
            jsonb_agg(DISTINCT 
                jsonb_build_object(
                    'variante', CASE 
                        WHEN v.id IS NOT NULL THEN jsonb_build_object(
                            'id', v.id,
                            'atributo', jsonb_build_object(
                                'id', a.id,
                                'denominacion', a.denominacion,
                                'label', a.label
                            ),
                            'opciones', (
                                SELECT jsonb_agg(
                                    jsonb_build_object(
                                        'id', ao.id,
                                        'valor', ao.valor,
                                        'sku_codigo', ao.sku_codigo
                                    )
                                )
                                FROM app_dat_atributo_opcion ao
                                WHERE ao.id_atributo = a.id
                            )
                        )
                        ELSE NULL
                    END,
                    'presentaciones', (
                        SELECT jsonb_agg(
                            jsonb_build_object(
                                'id', pp2.id,
                                'denominacion', np2.denominacion,
                                'sku_codigo', np2.sku_codigo,
                                'cantidad', pp2.cantidad,
                                'es_base', pp2.es_base
                            )
                        )
                        FROM app_dat_producto_presentacion pp2
                        JOIN app_nom_presentacion np2 ON pp2.id_presentacion = np2.id
                        WHERE pp2.id_producto = pv.id_producto
                    )
                )
            ) as variantes_disponibles
        FROM app_dat_precio_venta pv
        JOIN app_dat_variantes v ON pv.id_variante = v.id
        JOIN app_dat_atributos a ON v.id_atributo = a.id
        WHERE pv.id_variante IS NOT NULL
        AND (pv.fecha_hasta IS NULL OR pv.fecha_hasta >= CURRENT_DATE)
        GROUP BY pv.id_producto
    ),
    -- CTE principal con todos los datos
    productos_completos AS (
        SELECT 
            p.id,
            p.sku,
            p.denominacion,
            p.nombre_comercial,
            p.descripcion,
            p.um,
            p.es_refrigerado,
            p.es_fragil,
            p.es_peligroso,
            p.es_vendible,
            p.codigo_barras,
            p.imagen,
            
            -- Categoría
            jsonb_build_object(
                'id', c.id,
                'denominacion', c.denominacion,
                'sku_codigo', c.sku_codigo
            ) as categoria,
            
            -- Precio
            COALESCE(pa.precio_venta_cup, 0) as precio_venta,
            
            -- Stock
            COALESCE(sp.stock_total, 0) as stock_disponible,
            COALESCE(sp.tiene_stock, false) as tiene_stock,
            
            -- Subcategorías (agregadas con LEFT JOIN)
            COALESCE(
                jsonb_agg(DISTINCT 
                    CASE WHEN sc.id IS NOT NULL THEN
                        jsonb_build_object(
                            'id', sc.id,
                            'denominacion', sc.denominacion,
                            'sku_codigo', sc.sku_codigo
                        )
                    END
                ) FILTER (WHERE sc.id IS NOT NULL), 
                '[]'::jsonb
            ) as subcategorias,
            
            -- Presentaciones (agregadas con LEFT JOIN)
            COALESCE(
                jsonb_agg(DISTINCT 
                    CASE WHEN pp.id IS NOT NULL THEN
                        jsonb_build_object(
                            'id', pp.id,
                            'presentacion', np.denominacion,
                            'cantidad', pp.cantidad,
                            'es_base', pp.es_base,
                            'sku_codigo', np.sku_codigo
                        )
                    END
                ) FILTER (WHERE pp.id IS NOT NULL),
                '[]'::jsonb
            ) as presentaciones,
            
            -- Multimedia (subconsulta optimizada)
            (SELECT COALESCE(jsonb_agg(media), '[]'::jsonb) 
             FROM app_dat_producto_multimedias 
             WHERE id_producto = p.id) as multimedias,
            
            -- Etiquetas (subconsulta optimizada)
            (SELECT COALESCE(jsonb_agg(etiqueta), '[]'::jsonb) 
             FROM app_dat_producto_etiquetas 
             WHERE id_producto = p.id) as etiquetas,
             
            -- Variantes disponibles (nuevo objeto)
            COALESCE(vp.variantes_disponibles, '[]'::jsonb) as variantes_disponibles
             
        FROM app_dat_producto p
        JOIN app_dat_categoria c ON p.id_categoria = c.id
        LEFT JOIN stock_productos sp ON p.id = sp.id_producto
        LEFT JOIN precios_actuales pa ON p.id = pa.id_producto
        LEFT JOIN app_dat_productos_subcategorias ps ON p.id = ps.id_producto
        LEFT JOIN app_dat_subcategorias sc ON ps.id_sub_categoria = sc.id
        LEFT JOIN app_dat_producto_presentacion pp ON p.id = pp.id_producto
        LEFT JOIN app_nom_presentacion np ON pp.id_presentacion = np.id
        LEFT JOIN variantes_producto vp ON p.id = vp.id_producto
        
        WHERE 
            p.id_tienda = id_tienda_param 
            AND p.es_vendible = true
            AND (id_categoria_param IS NULL OR c.id = id_categoria_param)
            AND (NOT solo_disponibles_param OR sp.tiene_stock = true)
            
        GROUP BY p.id, p.sku, p.denominacion, p.nombre_comercial, p.descripcion, 
                 p.um, p.es_refrigerado, p.es_fragil, p.es_peligroso, p.es_vendible,
                 p.codigo_barras, p.imagen, c.id, c.denominacion, c.sku_codigo,
                 pa.precio_venta_cup, sp.stock_total, sp.tiene_stock, vp.variantes_disponibles
        ORDER BY p.denominacion
    )
    -- Construir el resultado final
    SELECT jsonb_build_object(
        'tienda_id', id_tienda_param,
        'categoria_id', id_categoria_param,
        'solo_disponibles', solo_disponibles_param,
        'total_productos', COUNT(*),
        'productos', jsonb_agg(
            jsonb_build_object(
                'id', pc.id,
                'sku', pc.sku,
                'denominacion', pc.denominacion,
                'nombre_comercial', pc.nombre_comercial,
                'descripcion', pc.descripcion,
                'um', pc.um,
                'es_refrigerado', pc.es_refrigerado,
                'es_fragil', pc.es_fragil,
                'es_peligroso', pc.es_peligroso,
                'es_vendible', pc.es_vendible,
                'codigo_barras', pc.codigo_barras,
                'imagen', pc.imagen,
                'categoria', pc.categoria,
                'precio_venta', pc.precio_venta,
                'stock_disponible', pc.stock_disponible,
                'tiene_stock', pc.tiene_stock,
                'subcategorias', pc.subcategorias,
                'presentaciones', pc.presentaciones,
                'multimedias', pc.multimedias,
                'etiquetas', pc.etiquetas,
                'variantes_disponibles', pc.variantes_disponibles,
                'inventario', COALESCE((
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'id_inventario', ui.inventario_id,
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
                                WHEN pp2.id IS NOT NULL THEN jsonb_build_object(
                                    'id', pp2.id,
                                    'denominacion', np2.denominacion,
                                    'sku_codigo', np2.sku_codigo,
                                    'cantidad', pp2.cantidad
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
                            'cantidad_disponible', ui.cantidad_final,
                            'ultima_actualizacion', ui.created_at,
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
                    FROM ultimo_inventario ui
                    LEFT JOIN app_dat_variantes v ON ui.id_variante = v.id
                    LEFT JOIN app_dat_atributos a ON v.id_atributo = a.id
                    LEFT JOIN app_dat_atributo_opcion ao ON ui.id_opcion_variante = ao.id
                    LEFT JOIN app_dat_producto_presentacion pp2 ON ui.id_presentacion = pp2.id
                    LEFT JOIN app_nom_presentacion np2 ON pp2.id_presentacion = np2.id
                    LEFT JOIN app_dat_layout_almacen la ON ui.id_ubicacion = la.id
                    LEFT JOIN app_dat_almacen alm ON la.id_almacen = alm.id
                    LEFT JOIN app_dat_proveedor pr ON ui.id_proveedor = pr.id
                    WHERE ui.id_producto = pc.id
                ), '[]'::jsonb)
            )
        )
    ) INTO productos_result
    FROM productos_completos pc;
    
    RETURN productos_result;
END;
$$;
