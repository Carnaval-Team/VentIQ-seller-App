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

        IF NOT EXISTS (SELECT 1 FROM app_dat_tienda t WHERE t.id = p_id_tienda) THEN
            RAISE EXCEPTION 'La tienda con ID % no existe', p_id_tienda;
        END IF;
    END IF;


    -- ============================================================
    -- Contar total de resultados (para paginación)
    -- Usa únicamente el último registro histórico por combinación
    -- (producto, variante, opcion_variante, presentacion, ubicacion)
    -- ============================================================
    SELECT COUNT(*) INTO v_total_count
    FROM (
        SELECT DISTINCT
            i.id_producto,
            COALESCE(i.id_variante, 0)        AS id_variante,
            COALESCE(i.id_opcion_variante, 0) AS id_opcion_variante,
            COALESCE(i.id_ubicacion, 0)       AS id_ubicacion,
            COALESCE(i.id_presentacion, 0)    AS id_presentacion
        FROM public.app_dat_inventario_productos i
        INNER JOIN public.app_dat_producto p ON i.id_producto = p.id
        INNER JOIN public.app_dat_layout_almacen l ON i.id_ubicacion = l.id
        INNER JOIN public.app_dat_almacen a ON l.id_almacen = a.id
        INNER JOIN public.app_dat_tienda t ON a.id_tienda = t.id
        LEFT JOIN public.app_dat_categoria c ON p.id_categoria = c.id
        LEFT JOIN public.app_dat_variantes v ON i.id_variante = v.id
        LEFT JOIN public.app_dat_atributos attr ON v.id_atributo = attr.id
        LEFT JOIN public.app_dat_atributo_opcion vo ON i.id_opcion_variante = vo.id
        LEFT JOIN public.app_dat_producto_presentacion pr ON i.id_presentacion = pr.id
        LEFT JOIN public.app_dat_layout_abc abc ON l.id = abc.id_layout
        WHERE 1 = 1
            AND i.id = (
                SELECT MAX(ih.id)
                FROM public.app_dat_inventario_productos ih
                WHERE ih.id_producto = i.id_producto
                  AND COALESCE(ih.id_variante, 0)        = COALESCE(i.id_variante, 0)
                  AND COALESCE(ih.id_opcion_variante, 0) = COALESCE(i.id_opcion_variante, 0)
                  AND COALESCE(ih.id_presentacion, 0)    = COALESCE(i.id_presentacion, 0)
                  AND COALESCE(ih.id_ubicacion, 0)       = COALESCE(i.id_ubicacion, 0)
            )
            AND (p_id_tienda IS NULL OR t.id = p_id_tienda)
            AND (p_id_almacen IS NULL OR a.id = p_id_almacen)
            AND (p_id_ubicacion IS NULL OR l.id = p_id_ubicacion)
            AND (p_id_producto IS NULL OR p.id = p_id_producto)
            AND (p_id_variante IS NULL OR v.id = p_id_variante)
            AND (p_id_opcion_variante IS NULL OR vo.id = p_id_opcion_variante)
            AND (p_id_presentacion IS NULL OR pr.id = p_id_presentacion)
            AND (p_id_categoria IS NULL OR p.id_categoria = p_id_categoria)
            AND (p_id_subcategoria IS NULL OR EXISTS (
                    SELECT 1 FROM public.app_dat_productos_subcategorias ps
                    WHERE ps.id_producto = p.id AND ps.id_sub_categoria = p_id_subcategoria
                ))
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
                    (SELECT ls.stock_min FROM app_dat_almacen_limites ls WHERE ls.id_producto = p.id AND ls.id_almacen = a.id),
                    0
                )
            )
    ) AS conteo;


    -- ============================================================
    -- Totales para resumen (mismo criterio: último registro)
    -- ============================================================
    SELECT
        COUNT(*) AS total_inventario,
        COUNT(CASE WHEN i.cantidad_final < 10 THEN 1 END) AS total_con_cantidad_baja,
        COUNT(CASE WHEN i.cantidad_final = 0 THEN 1 END)  AS total_sin_stock
    INTO v_total_inventario, v_total_con_cantidad_baja, v_total_sin_stock
    FROM public.app_dat_inventario_productos i
    INNER JOIN public.app_dat_producto p ON i.id_producto = p.id
    INNER JOIN public.app_dat_layout_almacen l ON i.id_ubicacion = l.id
    INNER JOIN public.app_dat_almacen a ON l.id_almacen = a.id
    INNER JOIN public.app_dat_tienda t ON a.id_tienda = t.id
    LEFT JOIN public.app_dat_categoria c ON p.id_categoria = c.id
    LEFT JOIN public.app_dat_variantes v ON i.id_variante = v.id
    LEFT JOIN public.app_dat_atributos attr ON v.id_atributo = attr.id
    LEFT JOIN public.app_dat_atributo_opcion vo ON i.id_opcion_variante = vo.id
    LEFT JOIN public.app_dat_producto_presentacion pr ON i.id_presentacion = pr.id
    LEFT JOIN public.app_dat_layout_abc abc ON l.id = abc.id_layout
    WHERE 1 = 1
        AND i.id = (
            SELECT MAX(ih.id)
            FROM public.app_dat_inventario_productos ih
            WHERE ih.id_producto = i.id_producto
              AND COALESCE(ih.id_variante, 0)        = COALESCE(i.id_variante, 0)
              AND COALESCE(ih.id_opcion_variante, 0) = COALESCE(i.id_opcion_variante, 0)
              AND COALESCE(ih.id_presentacion, 0)    = COALESCE(i.id_presentacion, 0)
              AND COALESCE(ih.id_ubicacion, 0)       = COALESCE(i.id_ubicacion, 0)
        )
        AND (p_id_tienda IS NULL OR t.id = p_id_tienda)
        AND (p_id_almacen IS NULL OR a.id = p_id_almacen)
        AND (p_id_ubicacion IS NULL OR l.id = p_id_ubicacion)
        AND (p_id_producto IS NULL OR p.id = p_id_producto)
        AND (p_id_variante IS NULL OR v.id = p_id_variante)
        AND (p_id_opcion_variante IS NULL OR vo.id = p_id_opcion_variante)
        AND (p_id_presentacion IS NULL OR pr.id = p_id_presentacion)
        AND (p_id_categoria IS NULL OR p.id_categoria = p_id_categoria)
        AND (p_id_subcategoria IS NULL OR EXISTS (
                SELECT 1 FROM public.app_dat_productos_subcategorias ps
                WHERE ps.id_producto = p.id AND ps.id_sub_categoria = p_id_subcategoria
            ))
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
                (SELECT ls.stock_min FROM app_dat_almacen_limites ls WHERE ls.id_producto = p.id AND ls.id_almacen = a.id),
                0
            )
        );


    -- ============================================================
    -- Retornar inventario paginado
    -- ============================================================
    RETURN QUERY
    WITH inventario_detalle AS (
        -- Último registro por combinación: filtra por MAX(id) correlacionado
        SELECT
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
        WHERE i.id = (
                SELECT MAX(ih.id)
                FROM public.app_dat_inventario_productos ih
                WHERE ih.id_producto = i.id_producto
                  AND COALESCE(ih.id_variante, 0)        = COALESCE(i.id_variante, 0)
                  AND COALESCE(ih.id_opcion_variante, 0) = COALESCE(i.id_opcion_variante, 0)
                  AND COALESCE(ih.id_presentacion, 0)    = COALESCE(i.id_presentacion, 0)
                  AND COALESCE(ih.id_ubicacion, 0)       = COALESCE(i.id_ubicacion, 0)
            )
            AND (p_id_tienda IS NULL OR t.id = p_id_tienda)
            AND (p_id_almacen IS NULL OR a.id = p_id_almacen)
            AND (p_id_ubicacion IS NULL OR i.id_ubicacion = p_id_ubicacion)
            AND (p_id_producto IS NULL OR i.id_producto = p_id_producto)
            AND (p_id_variante IS NULL OR COALESCE(i.id_variante, 0) = COALESCE(p_id_variante, 0))
            AND (p_id_opcion_variante IS NULL OR COALESCE(i.id_opcion_variante, 0) = COALESCE(p_id_opcion_variante, 0))
            AND (p_id_presentacion IS NULL OR COALESCE(i.id_presentacion, 0) = COALESCE(p_id_presentacion, 0))
            AND (p_origen_cambio IS NULL OR i.origen_cambio = p_origen_cambio)
            AND (p_id_proveedor IS NULL OR i.id_proveedor = p_id_proveedor)
            AND (
                p_con_stock_minimo IS NULL OR
                i.cantidad_final <= COALESCE(
                    (SELECT ls.stock_min FROM app_dat_almacen_limites ls WHERE ls.id_producto = i.id_producto AND ls.id_almacen = a.id),
                    0
                )
            )
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
            p.codigo_barras
        FROM public.app_dat_producto p
        WHERE (p_id_producto IS NULL OR p.id = p_id_producto)
    ),
    -- Primera subcategoría del producto (evita duplicación por multi-subcategoría)
    producto_subcategoria AS (
        SELECT DISTINCT ON (ps.id_producto)
            ps.id_producto,
            ps.id_sub_categoria AS id_subcategoria,
            s.denominacion AS subcategoria
        FROM public.app_dat_productos_subcategorias ps
        LEFT JOIN public.app_dat_subcategorias s ON ps.id_sub_categoria = s.id
        ORDER BY ps.id_producto, ps.id_sub_categoria
    ),
    -- Precio vigente más reciente por (producto, variante)
    precio_actual AS (
        SELECT DISTINCT ON (pv.id_producto, COALESCE(pv.id_variante, 0))
            pv.id_producto,
            COALESCE(pv.id_variante, 0) AS id_variante,
            pv.precio_venta_cup
        FROM public.app_dat_precio_venta pv
        WHERE (pv.fecha_hasta IS NULL OR pv.fecha_hasta >= CURRENT_DATE)
        ORDER BY pv.id_producto, COALESCE(pv.id_variante, 0), pv.fecha_desde DESC, pv.id DESC
    ),
    ubicacion_info AS (
        SELECT
            l.id AS id_ubicacion,
            l.denominacion AS ubicacion,
            a.id AS id_almacen,
            a.denominacion AS almacen,
            t.id AS id_tienda,
            t.denominacion AS tienda,
            abc.clasificacion_abc
        FROM public.app_dat_layout_almacen l
        INNER JOIN public.app_dat_almacen a ON l.id_almacen = a.id
        INNER JOIN public.app_dat_tienda t ON a.id_tienda = t.id
        LEFT JOIN public.app_dat_layout_abc abc ON l.id = abc.id_layout
        WHERE (p_id_tienda IS NULL OR t.id = p_id_tienda)
          AND (p_id_almacen IS NULL OR a.id = p_id_almacen)
          AND (p_id_ubicacion IS NULL OR l.id = p_id_ubicacion)
    ),
    stock_reservado AS (
        SELECT
            ep.id_producto,
            COALESCE(ep.id_variante, 0) AS id_variante,
            COALESCE(ep.id_opcion_variante, 0) AS id_opcion_variante,
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
    reservado_carnaval AS (
        SELECT
            rpc.id_producto,
            rpc.id_ubicacion,
            SUM(cart.quantity) AS reservado
        FROM public.relation_products_carnaval rpc
        JOIN carnavalapp."Carrito" cart ON cart.product_id = rpc.id_producto_carnaval
        GROUP BY rpc.id_producto, rpc.id_ubicacion
    )
    SELECT
        p.id::BIGINT,
        p.sku_producto::TEXT,
        p.nombre_producto::TEXT,
        p.nombre_comercial::TEXT,
        p.denominacion_corta::TEXT,
        p.descripcion::TEXT,
        p.descripcion_corta::TEXT,
        p.um::TEXT,
        p.id_categoria::BIGINT,
        COALESCE(cat.denominacion, 'Sin categoría')::TEXT,
        psc.id_subcategoria::BIGINT,
        COALESCE(psc.subcategoria, 'Sin subcategoría')::TEXT,
        p.id_tienda::BIGINT,
        u.tienda::TEXT,
        u.id_almacen::BIGINT,
        u.almacen::TEXT,
        u.id_ubicacion::BIGINT,
        u.ubicacion::TEXT,
        inv_det.id_variante::BIGINT,
        COALESCE(attr_v.denominacion, 'Unidad')::TEXT,
        inv_det.id_opcion_variante::BIGINT,
        COALESCE(ao.valor, 'Única')::TEXT,
        inv_det.id_presentacion::BIGINT,
        COALESCE(np.denominacion, 'Unidad')::TEXT,
        inv_det.cantidad_inicial::NUMERIC,
        inv_det.cantidad_final::NUMERIC,
        inv_det.cantidad_final::NUMERIC AS stock_disponible,
        COALESCE(sr.reservado, 0)::NUMERIC AS stock_reservado,
        GREATEST(inv_det.cantidad_final - COALESCE(sr.reservado, 0), 0)::NUMERIC AS stock_disponible_ajustado,
        p.es_vendible::BOOLEAN,
        p.es_comprable::BOOLEAN,
        p.es_inventariable::BOOLEAN,
        p.es_por_lotes::BOOLEAN,
        p.dias_alert_caducidad::NUMERIC,
        p.es_refrigerado::BOOLEAN,
        p.es_fragil::BOOLEAN,
        p.es_peligroso::BOOLEAN,
        p.es_elaborado::BOOLEAN,
        p.es_servicio::BOOLEAN,
        p.imagen::TEXT,
        p.codigo_barras::TEXT,
        COALESCE(pa.precio_venta_cup, 0)::NUMERIC AS precio_venta,
        0::NUMERIC AS costo_promedio,
        NULL::NUMERIC AS margen_actual,
        COALESCE(u.clasificacion_abc, 3)::SMALLINT,
        CASE COALESCE(u.clasificacion_abc, 3)
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
            'total_sin_stock', v_total_sin_stock,
            'reservado_carnaval', jsonb_build_object(
                'id_producto', inv_det.id_producto,
                'id_ubicacion', inv_det.id_ubicacion,
                'cantidad', COALESCE(rc.reservado, 0)
            )
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
    LEFT JOIN public.app_dat_categoria cat ON p.id_categoria = cat.id
    LEFT JOIN producto_subcategoria psc ON p.id = psc.id_producto
    LEFT JOIN public.app_dat_variantes v ON inv_det.id_variante = v.id
    LEFT JOIN public.app_dat_atributos attr_v ON v.id_atributo = attr_v.id
    LEFT JOIN public.app_dat_atributo_opcion ao ON inv_det.id_opcion_variante = ao.id
    LEFT JOIN public.app_dat_producto_presentacion pp ON inv_det.id_presentacion = pp.id
    LEFT JOIN public.app_nom_presentacion np ON pp.id_presentacion = np.id
    LEFT JOIN precio_actual pa
           ON pa.id_producto = p.id
          AND pa.id_variante = COALESCE(inv_det.id_variante, 0)
    LEFT JOIN stock_reservado sr ON (
        inv_det.id_producto = sr.id_producto
        AND COALESCE(inv_det.id_variante, 0) = sr.id_variante
        AND COALESCE(inv_det.id_opcion_variante, 0) = sr.id_opcion_variante
        AND inv_det.id_ubicacion = sr.id_ubicacion
    )
    LEFT JOIN reservado_carnaval rc ON (
        inv_det.id_producto = rc.id_producto
        AND inv_det.id_ubicacion = rc.id_ubicacion
    )
    WHERE 1 = 1
        AND (p_id_categoria IS NULL OR p.id_categoria = p_id_categoria)
        AND (p_id_subcategoria IS NULL OR psc.id_subcategoria = p_id_subcategoria)
        AND (p_es_vendible IS NULL OR p.es_vendible = p_es_vendible)
        AND (p_es_inventariable IS NULL OR p.es_inventariable = p_es_inventariable)
        AND (p_clasificacion_abc IS NULL OR u.clasificacion_abc = p_clasificacion_abc)
        AND (p_mostrar_sin_stock = TRUE OR inv_det.cantidad_final > 0)
        AND (
            p_busqueda IS NULL OR
            p.nombre_producto ILIKE '%' || p_busqueda || '%' OR
            p.sku_producto ILIKE '%' || p_busqueda || '%' OR
            p.nombre_comercial ILIKE '%' || p_busqueda || '%' OR
            p.descripcion ILIKE '%' || p_busqueda || '%' OR
            cat.denominacion ILIKE '%' || p_busqueda || '%' OR
            psc.subcategoria ILIKE '%' || p_busqueda || '%' OR
            attr_v.denominacion ILIKE '%' || p_busqueda || '%' OR
            ao.valor ILIKE '%' || p_busqueda || '%' OR
            np.denominacion ILIKE '%' || p_busqueda || '%'
        )
    ORDER BY u.tienda, u.almacen, u.ubicacion, p.nombre_producto, COALESCE(inv_det.id_variante, 0);
    -- LIMIT p_limite
    -- OFFSET v_offset;
END;