CREATE OR REPLACE FUNCTION public.fn_listar_inventario_productos_paged2_grouped2(
    p_pagina INTEGER DEFAULT 1,
    p_limite INTEGER DEFAULT 20,
    p_id_tienda INTEGER DEFAULT NULL,
    p_id_almacen INTEGER DEFAULT NULL,
    p_id_ubicacion INTEGER DEFAULT NULL,
    p_id_producto INTEGER DEFAULT NULL,
    p_id_variante INTEGER DEFAULT NULL,
    p_id_opcion_variante INTEGER DEFAULT NULL,
    p_id_presentacion INTEGER DEFAULT NULL,
    p_id_categoria INTEGER DEFAULT NULL,
    p_id_subcategoria INTEGER DEFAULT NULL,
    p_id_proveedor INTEGER DEFAULT NULL,
    p_origen_cambio SMALLINT DEFAULT NULL,
    p_es_vendible BOOLEAN DEFAULT NULL,
    p_es_inventariable BOOLEAN DEFAULT NULL,
    p_clasificacion_abc SMALLINT DEFAULT NULL,
    p_mostrar_sin_stock BOOLEAN DEFAULT TRUE,
    p_con_stock_minimo BOOLEAN DEFAULT NULL,
    p_busqueda TEXT DEFAULT NULL
)
RETURNS TABLE (
    id_producto BIGINT,
    sku_producto TEXT,
    nombre_producto TEXT,
    nombre_comercial TEXT,
    denominacion_corta TEXT,
    descripcion TEXT,
    descripcion_corta TEXT,
    um TEXT,
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
    es_comprable BOOLEAN,
    es_inventariable BOOLEAN,
    es_por_lotes BOOLEAN,
    dias_alert_caducidad NUMERIC,
    es_refrigerado BOOLEAN,
    es_fragil BOOLEAN,
    es_peligroso BOOLEAN,
    es_elaborado BOOLEAN,
    es_servicio BOOLEAN,
    imagen TEXT,
    codigo_barras TEXT,
    precio_venta NUMERIC,
    costo_promedio NUMERIC,
    margen_actual NUMERIC,
    clasificacion_abc INTEGER,
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
    v_total_count BIGINT;
    v_total_inventario BIGINT;
    v_total_con_cantidad_baja BIGINT;
    v_total_sin_stock BIGINT;
BEGIN
    -- Validar acceso si se especifica tienda
    IF p_id_tienda IS NOT NULL THEN
        PERFORM check_user_has_access_to_tienda(p_id_tienda);
        
        -- Validar que la tienda exista
        IF NOT EXISTS (SELECT 1 FROM app_dat_tienda t WHERE t.id = p_id_tienda) THEN
            RAISE EXCEPTION 'La tienda con ID % no existe', p_id_tienda;
        END IF;
    END IF;


    -- Contar total de productos ÚNICOS (agrupados por id_producto)
    SELECT COUNT(*) INTO v_total_count
    FROM (
        SELECT DISTINCT i.id_producto
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
                p.codigo_barras ILIKE '%' || p_busqueda || '%' OR
                p.nombre_comercial ILIKE '%' || p_busqueda || '%' OR
                p.descripcion ILIKE '%' || p_busqueda || '%' OR
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


    -- Calcular totales para resumen de inventario (agrupados por producto)
    SELECT 
        COUNT(*) AS total_inventario,
        COUNT(CASE WHEN total_stock < 10 THEN 1 END) AS total_con_cantidad_baja,
        COUNT(CASE WHEN total_stock = 0 THEN 1 END) AS total_sin_stock
    INTO v_total_inventario, v_total_con_cantidad_baja, v_total_sin_stock
    FROM (
        SELECT 
            i.id_producto,
            SUM(i.cantidad_final) AS total_stock
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
                p.codigo_barras ILIKE '%' || p_busqueda || '%' OR
                p.nombre_comercial ILIKE '%' || p_busqueda || '%' OR
                p.descripcion ILIKE '%' || p_busqueda || '%' OR
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
        GROUP BY i.id_producto
    ) AS resumen_agrupado;


    -- Retornar inventario AGRUPADO por id_producto
    -- Equivalente a _groupDuplicateProducts: suma stock_disponible, stock_reservado y stock_disponible_ajustado
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
            p.nombre_comercial,
            p.denominacion_corta,
            p.descripcion,
            p.descripcion_corta,
            p.um,
            p.id_categoria,
            ps.id_sub_categoria AS id_subcategoria,
            p.id_tienda,
            p.es_vendible,
            p.es_comprable,
            p.es_inventariable,
            p.es_por_lotes,
            p.dias_alert_caducidad,
            p.es_refrigerado,
            p.es_fragil,
            p.es_peligroso,
            p.es_elaborado,
            p.es_servicio,
            p.imagen,
            p.codigo_barras,
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
    ),
    -- Datos completos sin agrupar (misma lógica que la función original)
    datos_completos AS (
        SELECT
            p.id AS prod_id,
            p.sku_producto,
            p.nombre_producto,
            p.nombre_comercial,
            p.denominacion_corta,
            p.descripcion,
            p.descripcion_corta,
            p.um,
            p.id_categoria,
            COALESCE(c.categoria, 'Sin categoría') AS categoria,
            p.id_subcategoria,
            COALESCE(c.subcategoria, 'Sin subcategoría') AS subcategoria,
            p.id_tienda,
            u.tienda,
            u.id_almacen,
            u.almacen,
            u.id_ubicacion,
            u.ubicacion,
            inv_det.id_variante AS variante_id,
            COALESCE(c.variante, 'Unidad') AS variante,
            inv_det.id_opcion_variante AS opcion_variante_id,
            COALESCE(c.opcion_variante, 'Única') AS opcion_variante,
            inv_det.id_presentacion AS presentacion_id,
            COALESCE(c.presentacion, 'Unidad') AS presentacion,
            inv_det.cantidad_inicial,
            inv_det.cantidad_final,
            inv_det.cantidad_final AS stock_disponible,
            COALESCE(sr.reservado, 0) AS stock_reservado,
            GREATEST(inv_det.cantidad_final - COALESCE(sr.reservado, 0), 0) AS stock_disponible_ajustado,
            p.es_vendible,
            p.es_comprable,
            p.es_inventariable,
            p.es_por_lotes,
            p.dias_alert_caducidad,
            p.es_refrigerado,
            p.es_fragil,
            p.es_peligroso,
            p.es_elaborado,
            p.es_servicio,
            p.imagen,
            p.codigo_barras,
            p.precio_venta,
            p.costo_promedio,
            CASE
                WHEN p.precio_venta IS NOT NULL AND p.costo_promedio IS NOT NULL AND p.costo_promedio > 0
                THEN ROUND(((p.precio_venta - p.costo_promedio) / p.precio_venta) * 100, 2)
                ELSE NULL
            END AS margen_actual,
            COALESCE(c.clasificacion_abc::INTEGER, 3) AS clasificacion_abc_val,
            CASE COALESCE(c.clasificacion_abc, 3)
                WHEN 1 THEN 'A (Alta Rotación)'
                WHEN 2 THEN 'B (Media Rotación)'
                WHEN 3 THEN 'C (Baja Rotación)'
                ELSE 'No clasificado'
            END AS abc_descripcion,
            inv_det.fecha_ultima_actualizacion
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
                p.nombre_comercial ILIKE '%' || p_busqueda || '%' OR
                p.descripcion ILIKE '%' || p_busqueda || '%' OR
                c.categoria ILIKE '%' || p_busqueda || '%' OR
                c.subcategoria ILIKE '%' || p_busqueda || '%' OR
                c.variante ILIKE '%' || p_busqueda || '%' OR
                c.opcion_variante ILIKE '%' || p_busqueda || '%' OR
                c.presentacion ILIKE '%' || p_busqueda || '%'
            )
    )
    -- AGRUPACIÓN POR id_producto (equivalente a _groupDuplicateProducts)
    -- Suma stock_disponible, stock_reservado y stock_disponible_ajustado de todas las ubicaciones
    -- Toma el primer registro para los datos del producto (MIN/MAX para campos no agregables)
    SELECT
        d.prod_id::BIGINT AS id_producto,
        MIN(d.sku_producto)::TEXT AS sku_producto,
        MIN(d.nombre_producto)::TEXT AS nombre_producto,
        MIN(d.nombre_comercial)::TEXT AS nombre_comercial,
        MIN(d.denominacion_corta)::TEXT AS denominacion_corta,
        MIN(d.descripcion)::TEXT AS descripcion,
        MIN(d.descripcion_corta)::TEXT AS descripcion_corta,
        MIN(d.um)::TEXT AS um,
        MIN(d.id_categoria)::BIGINT AS id_categoria,
        MIN(d.categoria)::TEXT AS categoria,
        MIN(d.id_subcategoria)::BIGINT AS id_subcategoria,
        MIN(d.subcategoria)::TEXT AS subcategoria,
        MIN(d.id_tienda)::BIGINT AS id_tienda,
        MIN(d.tienda)::TEXT AS tienda,
        MIN(d.id_almacen)::BIGINT AS id_almacen,
        MIN(d.almacen)::TEXT AS almacen,
        MIN(d.id_ubicacion)::BIGINT AS id_ubicacion,
        MIN(d.ubicacion)::TEXT AS ubicacion,
        MIN(d.variante_id)::BIGINT AS id_variante,
        MIN(d.variante)::TEXT AS variante,
        MIN(d.opcion_variante_id)::BIGINT AS id_opcion_variante,
        MIN(d.opcion_variante)::TEXT AS opcion_variante,
        MIN(d.presentacion_id)::BIGINT AS id_presentacion,
        MIN(d.presentacion)::TEXT AS presentacion,
        SUM(d.cantidad_inicial)::NUMERIC AS cantidad_inicial,
        SUM(d.cantidad_final)::NUMERIC AS cantidad_final,
        SUM(d.stock_disponible)::NUMERIC AS stock_disponible,
        SUM(d.stock_reservado)::NUMERIC AS stock_reservado,
        SUM(d.stock_disponible_ajustado)::NUMERIC AS stock_disponible_ajustado,
        BOOL_OR(d.es_vendible)::BOOLEAN AS es_vendible,
        BOOL_OR(d.es_comprable)::BOOLEAN AS es_comprable,
        BOOL_OR(d.es_inventariable)::BOOLEAN AS es_inventariable,
        BOOL_OR(d.es_por_lotes)::BOOLEAN AS es_por_lotes,
        MIN(d.dias_alert_caducidad)::NUMERIC AS dias_alert_caducidad,
        BOOL_OR(d.es_refrigerado)::BOOLEAN AS es_refrigerado,
        BOOL_OR(d.es_fragil)::BOOLEAN AS es_fragil,
        BOOL_OR(d.es_peligroso)::BOOLEAN AS es_peligroso,
        BOOL_OR(d.es_elaborado)::BOOLEAN AS es_elaborado,
        BOOL_OR(d.es_servicio)::BOOLEAN AS es_servicio,
        MIN(d.imagen)::TEXT AS imagen,
        MIN(d.codigo_barras)::TEXT AS codigo_barras,
        MIN(d.precio_venta)::NUMERIC AS precio_venta,
        MIN(d.costo_promedio)::NUMERIC AS costo_promedio,
        MIN(d.margen_actual)::NUMERIC AS margen_actual,
        MIN(d.clasificacion_abc_val)::INTEGER AS clasificacion_abc,
        MIN(d.abc_descripcion)::TEXT AS abc_descripcion,
        MAX(d.fecha_ultima_actualizacion)::TIMESTAMPTZ AS fecha_ultima_actualizacion,
        v_total_count::BIGINT AS total_count,
        jsonb_build_object(
            'total_inventario', v_total_inventario,
            'total_con_cantidad_baja', v_total_con_cantidad_baja,
            'total_sin_stock', v_total_sin_stock
        )::JSONB AS resumen_inventario,
        jsonb_build_object(
            'pagina_actual', p_pagina,
            'total_items', p_limite,
            'total_paginas', 1,
            'total_registros', v_total_count,
            'tiene_anterior', false,
            'tiene_siguiente', false
        )::JSONB AS info_paginacion
    FROM datos_completos d
    GROUP BY d.prod_id
    ORDER BY MIN(d.tienda), MIN(d.almacen), MIN(d.ubicacion), MIN(d.nombre_producto);
END;
$$;
