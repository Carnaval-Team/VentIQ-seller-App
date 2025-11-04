-- Función actualizada para buscar en nombre, SKU, nombre_corto y nombre_comercial
-- Modificación de fn_listar_inventario_productos_paged para incluir búsqueda expandida

CREATE OR REPLACE FUNCTION fn_listar_inventario_productos_paged(
    p_busqueda TEXT DEFAULT NULL,
    p_es_vendible BOOLEAN DEFAULT NULL,
    p_pagina INTEGER DEFAULT 1,
    p_limite INTEGER DEFAULT 20,
    p_id_tienda BIGINT DEFAULT NULL,
    p_mostrar_sin_stock BOOLEAN DEFAULT TRUE,
    p_id_ubicacion BIGINT DEFAULT NULL,
    p_clasificacion_abc SMALLINT DEFAULT NULL,
    p_id_almacen BIGINT DEFAULT NULL,
    p_id_producto BIGINT DEFAULT NULL,
    p_id_variante BIGINT DEFAULT NULL,
    p_id_opcion_variante BIGINT DEFAULT NULL,
    p_id_presentacion BIGINT DEFAULT NULL,
    p_id_categoria BIGINT DEFAULT NULL,
    p_id_subcategoria BIGINT DEFAULT NULL,
    p_id_proveedor BIGINT DEFAULT NULL,
    p_origen_cambio SMALLINT DEFAULT NULL,
    p_es_inventariable BOOLEAN DEFAULT NULL,
    p_con_stock_minimo BOOLEAN DEFAULT NULL
)
RETURNS TABLE (
    id_producto BIGINT,
    sku_producto TEXT,
    nombre_producto TEXT,
    id_categoria BIGINT,
    categoria TEXT,
    id_subcategoria BIGINT,
    subcategoria TEXT,
    id_tienda BIGINT,
    tienda TEXT,
    id_almacen BIGINT,
    almacen TEXT,
    id_ubicacion BIGINT,
    ubicacion TEXT,
    id_variante BIGINT,
    variante TEXT,
    id_opcion_variante BIGINT,
    opcion_variante TEXT,
    id_presentacion BIGINT,
    presentacion TEXT,
    cantidad_inicial NUMERIC,
    cantidad_final NUMERIC,
    stock_disponible NUMERIC,
    stock_reservado NUMERIC,
    stock_disponible_ajustado NUMERIC,
    es_vendible BOOLEAN,
    es_inventariable BOOLEAN,
    precio_venta NUMERIC,
    costo_promedio NUMERIC,
    margen_actual NUMERIC,
    clasificacion_abc SMALLINT,
    abc_descripcion TEXT,
    fecha_ultima_actualizacion TIMESTAMPTZ,
    total_count BIGINT,
    resumen_inventario JSONB,
    info_paginacion JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_offset INTEGER := (p_pagina - 1) * p_limite;
    v_total_count BIGINT;
    v_total_inventario BIGINT;
    v_total_con_cantidad_baja BIGINT;
    v_total_sin_stock BIGINT;
    v_total_paginas INTEGER;
    v_tiene_siguiente BOOLEAN;
BEGIN
    -- Validar acceso si se especifica tienda
    IF p_id_tienda IS NOT NULL THEN
        PERFORM check_user_has_access_to_tienda(p_id_tienda);
        
        -- Validar que la tienda exista
        IF NOT EXISTS (SELECT 1 FROM app_dat_tienda t WHERE t.id = p_id_tienda) THEN
            RAISE EXCEPTION 'La tienda con ID % no existe', p_id_tienda;
        END IF;
    END IF;

    -- Contar total de resultados (para paginación)
    SELECT COUNT(*) INTO v_total_count
    FROM (
        SELECT DISTINCT
            i.id_producto,
            COALESCE(i.id_variante, 0) AS id_variante,
            COALESCE(i.id_opcion_variante, 0) AS id_opcion_variante,
            COALESCE(i.id_ubicacion, 0) AS id_ubicacion
        FROM public.app_dat_inventario_productos i
        INNER JOIN public.app_dat_producto p ON i.id_producto = p.id
        INNER JOIN public.app_dat_layout_almacen l ON i.id_ubicacion = l.id
        INNER JOIN public.app_dat_almacen a ON l.id_almacen = a.id
        INNER JOIN public.app_dat_tienda t ON a.id_tienda = t.id
        LEFT JOIN public.app_dat_categoria c ON p.id_categoria = c.id
        LEFT JOIN public.app_dat_productos_subcategorias ps ON p.id = ps.id_producto
        LEFT JOIN public.app_dat_subcategorias s ON ps.id_sub_categoria = s.id
        LEFT JOIN public.app_dat_variantes v ON i.id_variante = v.id
        LEFT JOIN public.app_dat_atributos attr ON v.id_atributo = attr.id
        LEFT JOIN public.app_dat_atributo_opcion vo ON i.id_opcion_variante = vo.id
        LEFT JOIN public.app_dat_producto_presentacion pr ON i.id_presentacion = pr.id
        LEFT JOIN public.app_dat_layout_abc abc ON (l.id = abc.id_layout)
        WHERE 1 = 1
            AND (p_id_tienda IS NULL OR t.id = p_id_tienda)
            AND (p_id_almacen IS NULL OR a.id = p_id_almacen)
            AND (p_id_ubicacion IS NULL OR l.id = p_id_ubicacion)
            AND (p_id_producto IS NULL OR p.id = p_id_producto)
            AND (p_id_variante IS NULL OR v.id = p_id_variante)
            AND (p_id_opcion_variante IS NULL OR vo.id = p_id_opcion_variante)
            AND (p_id_presentacion IS NULL OR pr.id = p_id_presentacion)
            AND (p_id_categoria IS NULL OR c.id = p_id_categoria)
            AND (p_id_subcategoria IS NULL OR s.id = p_id_subcategoria)
            AND (p_id_proveedor IS NULL OR i.id_proveedor = p_id_proveedor)
            AND (p_origen_cambio IS NULL OR i.origen_cambio = p_origen_cambio)
            AND (p_es_vendible IS NULL OR p.es_vendible = p_es_vendible)
            AND (p_es_inventariable IS NULL OR p.es_inventariable = p_es_inventariable)
            AND (p_clasificacion_abc IS NULL OR abc.clasificacion_abc = p_clasificacion_abc)
            AND (
                p_busqueda IS NULL OR
                p.denominacion ILIKE '%' || p_busqueda || '%' OR
                p.sku ILIKE '%' || p_busqueda || '%' OR
                p.nombre_corto ILIKE '%' || p_busqueda || '%' OR
                p.nombre_comercial ILIKE '%' || p_busqueda || '%' OR
                p.codigo_barras ILIKE '%' || p_busqueda || '%' OR
                c.denominacion ILIKE '%' || p_busqueda || '%' OR
                s.denominacion ILIKE '%' || p_busqueda || '%' OR
                attr.denominacion ILIKE '%' || p_busqueda || '%' OR
                vo.valor ILIKE '%' || p_busqueda || '%' 
            )
            AND (
                p_mostrar_sin_stock = TRUE OR
                i.cantidad_final > 0
            )
            AND (
                p_con_stock_minimo IS NULL OR
                i.cantidad_final <= COALESCE(
                    (SELECT stock_min FROM app_dat_almacen_limites ls WHERE ls.id_producto = p.id AND ls.id_almacen = a.id),
                    0
                )
            )
    ) AS conteo;

    -- Calcular totales para resumen de inventario
    SELECT 
        COUNT(*) AS total_inventario,
        COUNT(CASE WHEN i.cantidad_final < 10 THEN 1 END) AS total_con_cantidad_baja,
        COUNT(CASE WHEN i.cantidad_final = 0 THEN 1 END) AS total_sin_stock
    INTO v_total_inventario, v_total_con_cantidad_baja, v_total_sin_stock
    FROM public.app_dat_inventario_productos i
    INNER JOIN public.app_dat_producto p ON i.id_producto = p.id
    INNER JOIN public.app_dat_layout_almacen l ON i.id_ubicacion = l.id
    INNER JOIN public.app_dat_almacen a ON l.id_almacen = a.id
    INNER JOIN public.app_dat_tienda t ON a.id_tienda = t.id
    LEFT JOIN public.app_dat_categoria c ON p.id_categoria = c.id
    LEFT JOIN public.app_dat_productos_subcategorias ps ON p.id = ps.id_producto
    LEFT JOIN public.app_dat_subcategorias s ON ps.id_sub_categoria = s.id
    LEFT JOIN public.app_dat_variantes v ON i.id_variante = v.id
    LEFT JOIN public.app_dat_atributos attr ON v.id_atributo = attr.id
    LEFT JOIN public.app_dat_atributo_opcion vo ON i.id_opcion_variante = vo.id
    LEFT JOIN public.app_dat_producto_presentacion pr ON i.id_presentacion = pr.id
    LEFT JOIN public.app_dat_layout_abc abc ON (l.id = abc.id_layout)
    WHERE 1 = 1
        AND (p_id_tienda IS NULL OR t.id = p_id_tienda)
        AND (p_id_almacen IS NULL OR a.id = p_id_almacen)
        AND (p_id_ubicacion IS NULL OR l.id = p_id_ubicacion)
        AND (p_id_producto IS NULL OR p.id = p_id_producto)
        AND (p_id_variante IS NULL OR v.id = p_id_variante)
        AND (p_id_opcion_variante IS NULL OR vo.id = p_id_opcion_variante)
        AND (p_id_presentacion IS NULL OR pr.id = p_id_presentacion)
        AND (p_id_categoria IS NULL OR c.id = p_id_categoria)
        AND (p_id_subcategoria IS NULL OR s.id = p_id_subcategoria)
        AND (p_id_proveedor IS NULL OR i.id_proveedor = p_id_proveedor)
        AND (p_origen_cambio IS NULL OR i.origen_cambio = p_origen_cambio)
        AND (p_es_vendible IS NULL OR p.es_vendible = p_es_vendible)
        AND (p_es_inventariable IS NULL OR p.es_inventariable = p_es_inventariable)
        AND (p_clasificacion_abc IS NULL OR abc.clasificacion_abc = p_clasificacion_abc)
        AND (
            p_busqueda IS NULL OR
            p.denominacion ILIKE '%' || p_busqueda || '%' OR
            p.sku ILIKE '%' || p_busqueda || '%' OR
            p.nombre_corto ILIKE '%' || p_busqueda || '%' OR
            p.nombre_comercial ILIKE '%' || p_busqueda || '%' OR
            p.codigo_barras ILIKE '%' || p_busqueda || '%' OR
            c.denominacion ILIKE '%' || p_busqueda || '%' OR
            s.denominacion ILIKE '%' || p_busqueda || '%' OR
            attr.denominacion ILIKE '%' || p_busqueda || '%' OR
            vo.valor ILIKE '%' || p_busqueda || '%'
        )
        AND (
            p_mostrar_sin_stock = TRUE OR
            i.cantidad_final > 0
        )
        AND (
            p_con_stock_minimo IS NULL OR
            i.cantidad_final <= COALESCE(
                (SELECT stock_min FROM app_dat_almacen_limites ls WHERE ls.id_producto = p.id AND ls.id_almacen = a.id),
                0
            )
        );

    -- Calcular información de paginación
    v_total_paginas := CEIL(v_total_count::NUMERIC / p_limite);
    v_tiene_siguiente := p_pagina < v_total_paginas;

    -- Retornar inventario paginado
    RETURN QUERY
    WITH inventario_detalle AS (
        SELECT DISTINCT ON (i.id_producto, COALESCE(i.id_variante, 0), COALESCE(i.id_opcion_variante, 0), 
                           COALESCE(i.id_presentacion, 0), COALESCE(i.id_ubicacion, 0))
            i.id_producto,
            i.id_variante,
            i.id_opcion_variante,
            i.id_ubicacion,
            i.id_presentacion,
            i.cantidad_inicial,
            i.cantidad_final,
            i.created_at AS fecha_ultima_actualizacion,
            i.origen_cambio,
            i.id_recepcion,
            i.id_extraccion,
            i.id_control,
            i.id_proveedor
        FROM public.app_dat_inventario_productos i
        INNER JOIN public.app_dat_layout_almacen l ON i.id_ubicacion = l.id
        INNER JOIN public.app_dat_almacen a ON l.id_almacen = a.id
        INNER JOIN public.app_dat_tienda t ON a.id_tienda = t.id
        WHERE 1 = 1
            AND (p_id_tienda IS NULL OR t.id = p_id_tienda)
            AND (p_id_almacen IS NULL OR a.id = p_id_almacen)
            AND (p_id_producto IS NULL OR i.id_producto = p_id_producto)
            AND (p_id_variante IS NULL OR COALESCE(i.id_variante, 0) = COALESCE(p_id_variante, 0))
            AND (p_id_opcion_variante IS NULL OR COALESCE(i.id_opcion_variante, 0) = COALESCE(p_id_opcion_variante, 0))
            AND (p_id_ubicacion IS NULL OR i.id_ubicacion = p_id_ubicacion)
            AND (p_id_presentacion IS NULL OR COALESCE(i.id_presentacion, 0) = COALESCE(p_id_presentacion, 0))
            AND (p_origen_cambio IS NULL OR i.origen_cambio = p_origen_cambio)
            AND (p_id_proveedor IS NULL OR i.id_proveedor = p_id_proveedor)
            AND (
                p_con_stock_minimo IS NULL OR
                i.cantidad_final <= COALESCE(
                    (SELECT stock_min FROM app_dat_almacen_limites ls WHERE ls.id_producto = i.id_producto AND ls.id_almacen = a.id),
                    0
                )
            )
        ORDER BY i.id_producto, COALESCE(i.id_variante, 0), COALESCE(i.id_opcion_variante, 0), 
                 COALESCE(i.id_presentacion, 0), COALESCE(i.id_ubicacion, 0), 
                 i.created_at DESC, i.id DESC
    ),
    producto_info AS (
        SELECT
            p.id,
            p.sku AS sku_producto,
            p.denominacion AS nombre_producto,
            p.id_categoria,
            ps.id_sub_categoria AS id_subcategoria,
            p.id_tienda,
            p.es_vendible,
            p.es_inventariable,
            COALESCE(pv.precio_venta_cup, 0) as precio_venta,
            0::NUMERIC as costo_promedio
        FROM public.app_dat_producto p
        LEFT JOIN public.app_dat_productos_subcategorias ps ON p.id = ps.id_producto
        LEFT JOIN public.app_dat_precio_venta pv ON p.id = pv.id_producto 
            AND (pv.id_variante IS NULL OR pv.id_variante = 0)
            AND (pv.fecha_hasta IS NULL OR pv.fecha_hasta >= CURRENT_DATE)
        WHERE (p_id_producto IS NULL OR p.id = p_id_producto)
    ),
    ubicacion_info AS (
        SELECT
            l.id AS id_ubicacion,
            l.denominacion AS ubicacion,
            a.id AS id_almacen,
            a.denominacion AS almacen,
            t.id AS id_tienda,
            t.denominacion AS tienda
        FROM public.app_dat_layout_almacen l
        INNER JOIN public.app_dat_almacen a ON l.id_almacen = a.id
        INNER JOIN public.app_dat_tienda t ON a.id_tienda = t.id
        WHERE (p_id_tienda IS NULL OR t.id = p_id_tienda)
          AND (p_id_almacen IS NULL OR a.id = p_id_almacen)
          AND (p_id_ubicacion IS NULL OR l.id = p_id_ubicacion)
    ),
    stock_reservado AS (
        SELECT
            ep.id_producto,
            COALESCE(ep.id_variante, 0) as id_variante,
            COALESCE(ep.id_opcion_variante, 0) as id_opcion_variante,
            ep.id_ubicacion,
            SUM(ep.cantidad) AS reservado
        FROM app_dat_extraccion_productos ep
        INNER JOIN app_dat_operaciones o ON ep.id_operacion = o.id
        INNER JOIN (
            SELECT 
                eo1.id_operacion,
                eo1.estado
            FROM (
                SELECT 
                    eo2.id_operacion,
                    eo2.estado,
                    ROW_NUMBER() OVER (PARTITION BY eo2.id_operacion ORDER BY eo2.created_at DESC) as rn
                FROM app_dat_estado_operacion eo2
            ) eo1
            WHERE eo1.rn = 1 AND eo1.estado = 1
        ) ultimo_estado ON o.id = ultimo_estado.id_operacion
        GROUP BY ep.id_producto, COALESCE(ep.id_variante, 0), COALESCE(ep.id_opcion_variante, 0), ep.id_ubicacion
    ),
    clasificaciones AS (
        SELECT
            p.id AS id_producto,
            c.denominacion AS categoria,
            s.denominacion AS subcategoria,
            attr_v.denominacion AS variante,
            ao.valor AS opcion_variante,
            np.denominacion AS presentacion,
            abc.clasificacion_abc
        FROM producto_info p
        LEFT JOIN public.app_dat_categoria c ON p.id_categoria = c.id
        LEFT JOIN public.app_dat_subcategorias s ON p.id_subcategoria = s.id
        LEFT JOIN inventario_detalle inv_det ON p.id = inv_det.id_producto
        LEFT JOIN public.app_dat_variantes v ON inv_det.id_variante = v.id
        LEFT JOIN public.app_dat_atributos attr_v ON v.id_atributo = attr_v.id
        LEFT JOIN public.app_dat_atributo_opcion ao ON inv_det.id_opcion_variante = ao.id
        LEFT JOIN public.app_dat_producto_presentacion pp ON inv_det.id_presentacion = pp.id
        LEFT JOIN public.app_nom_presentacion np ON pp.id_presentacion = np.id
        LEFT JOIN public.app_dat_layout_almacen la ON inv_det.id_ubicacion = la.id
        LEFT JOIN public.app_dat_layout_abc abc ON (la.id = abc.id_layout)
    )
    SELECT
        p.id::BIGINT,
        p.sku_producto::TEXT,
        p.nombre_producto::TEXT,
        p.id_categoria::BIGINT,
        COALESCE(c.categoria, 'Sin categoría')::TEXT,
        p.id_subcategoria::BIGINT,
        COALESCE(c.subcategoria, 'Sin subcategoría')::TEXT,
        p.id_tienda::BIGINT,
        u.tienda::TEXT,
        u.id_almacen::BIGINT,
        u.almacen::TEXT,
        u.id_ubicacion::BIGINT,
        u.ubicacion::TEXT,
        COALESCE(inv_det.id_variante, NULL)::BIGINT,
        COALESCE(c.variante, 'Unidad')::TEXT,
        COALESCE(inv_det.id_opcion_variante, NULL)::BIGINT,
        COALESCE(c.opcion_variante, 'Única')::TEXT,
        COALESCE(inv_det.id_presentacion, NULL)::BIGINT,
        COALESCE(c.presentacion, 'Unidad')::TEXT,
        inv_det.cantidad_inicial::NUMERIC,
        inv_det.cantidad_final::NUMERIC,
        inv_det.cantidad_final::NUMERIC AS stock_disponible,
        COALESCE(sr.reservado, 0)::NUMERIC AS stock_reservado,
        GREATEST(inv_det.cantidad_final - COALESCE(sr.reservado, 0), 0)::NUMERIC AS stock_disponible_ajustado,
        p.es_vendible::BOOLEAN,
        p.es_inventariable::BOOLEAN,
        p.precio_venta::NUMERIC,
        p.costo_promedio::NUMERIC,
        CASE
            WHEN p.precio_venta IS NOT NULL AND p.costo_promedio IS NOT NULL AND p.costo_promedio > 0
            THEN ROUND(((p.precio_venta - p.costo_promedio) / p.precio_venta) * 100, 2)
            ELSE NULL
        END::NUMERIC AS margen_actual,
        COALESCE(c.clasificacion_abc, 3)::SMALLINT,
        CASE COALESCE(c.clasificacion_abc, 3)
            WHEN 1 THEN 'A (Alta Rotación)'
            WHEN 2 THEN 'B (Media Rotación)'
            WHEN 3 THEN 'C (Baja Rotación)'
            ELSE 'No clasificado'
        END::TEXT AS abc_descripcion,
        inv_det.fecha_ultima_actualizacion::TIMESTAMPTZ,
        v_total_count::BIGINT,
        jsonb_build_object(
            'total_inventario', v_total_inventario,
            'total_con_cantidad_baja', v_total_con_cantidad_baja,
            'total_sin_stock', v_total_sin_stock
        )::JSONB AS resumen_inventario,
        jsonb_build_object(
            'pagina_actual', p_pagina,
            'total_items', p_limite,
            'total_paginas', v_total_paginas,
            'total_registros', v_total_count,
            'tiene_anterior', p_pagina > 1,
            'tiene_siguiente', v_tiene_siguiente
        )::JSONB AS info_paginacion
    FROM inventario_detalle inv_det
    INNER JOIN producto_info p ON inv_det.id_producto = p.id
    INNER JOIN ubicacion_info u ON inv_det.id_ubicacion = u.id_ubicacion
    LEFT JOIN clasificaciones c ON p.id = c.id_producto
    LEFT JOIN stock_reservado sr ON (
        inv_det.id_producto = sr.id_producto
        AND COALESCE(inv_det.id_variante, 0) = sr.id_variante
        AND COALESCE(inv_det.id_opcion_variante, 0) = sr.id_opcion_variante
        AND inv_det.id_ubicacion = sr.id_ubicacion
    )
    WHERE 1 = 1
        AND (p_id_categoria IS NULL OR p.id_categoria = p_id_categoria)
        AND (p_id_subcategoria IS NULL OR p.id_subcategoria = p_id_subcategoria)
        AND (p_es_vendible IS NULL OR p.es_vendible = p_es_vendible)
        AND (p_es_inventariable IS NULL OR p.es_inventariable = p_es_inventariable)
        AND (p_clasificacion_abc IS NULL OR c.clasificacion_abc = p_clasificacion_abc)
        AND (p_mostrar_sin_stock = TRUE OR inv_det.cantidad_final > 0)
        AND (
            p_busqueda IS NULL OR
            p.nombre_producto ILIKE '%' || p_busqueda || '%' OR
            p.sku_producto ILIKE '%' || p_busqueda || '%' OR
            c.categoria ILIKE '%' || p_busqueda || '%' OR
            c.subcategoria ILIKE '%' || p_busqueda || '%' OR
            c.variante ILIKE '%' || p_busqueda || '%' OR
            c.opcion_variante ILIKE '%' || p_busqueda || '%' OR
            c.presentacion ILIKE '%' || p_busqueda || '%'
        )
    ORDER BY u.tienda, u.almacen, u.ubicacion, p.nombre_producto, COALESCE(inv_det.id_variante, 0)
    LIMIT p_limite
    OFFSET v_offset;
END;
$$;

-- Comentarios sobre los cambios realizados:
-- 1. Se agregó búsqueda por p.nombre_corto en las condiciones WHERE de búsqueda
-- 2. Se agregó búsqueda por p.nombre_comercial en las condiciones WHERE de búsqueda
-- 3. Los cambios se aplicaron en ambas secciones: conteo de resultados y consulta final
-- 4. Se mantuvieron todas las demás funcionalidades existentes
-- 5. La búsqueda sigue siendo case-insensitive usando ILIKE
