DECLARE
    v_offset INTEGER := (p_pagina - 1) * p_limite;
BEGIN
    -- Validación de acceso
    IF p_id_tienda IS NOT NULL THEN
        PERFORM check_user_has_access_to_tienda(p_id_tienda);
        IF NOT EXISTS (SELECT 1 FROM app_dat_tienda t WHERE t.id = p_id_tienda) THEN
            RAISE EXCEPTION 'La tienda con ID % no existe', p_id_tienda;
        END IF;
    END IF;

    -- ============================================================
    -- Pipeline completo en una sola consulta con CTEs.
    -- - inv_last: último registro por combinación (DISTINCT ON) en lugar
    --   del subquery correlacionado MAX(ih.id).
    -- - inv_filtrado: filtros de inventario + resolución almacén/tienda/ABC.
    -- - base: filtros de producto/categoría/búsqueda.
    -- - psc/pa/sr/rc: agregaciones auxiliares restringidas a base.
    -- - enriched: totales y orden con window functions en una sola pasada.
    -- Mantiene la función STABLE (sin CREATE TEMP TABLE).
    -- ============================================================
    RETURN QUERY
    WITH inv_last AS (
        SELECT DISTINCT ON (
            ih.id_producto,
            COALESCE(ih.id_variante, 0),
            COALESCE(ih.id_opcion_variante, 0),
            COALESCE(ih.id_presentacion, 0),
            COALESCE(ih.id_ubicacion, 0)
        )
            ih.*
        FROM public.app_dat_inventario_productos ih
        WHERE (p_id_producto       IS NULL OR ih.id_producto       = p_id_producto)
          AND (p_id_variante       IS NULL OR COALESCE(ih.id_variante, 0)        = COALESCE(p_id_variante, 0))
          AND (p_id_opcion_variante IS NULL OR COALESCE(ih.id_opcion_variante, 0) = COALESCE(p_id_opcion_variante, 0))
          AND (p_id_presentacion   IS NULL OR COALESCE(ih.id_presentacion, 0)    = COALESCE(p_id_presentacion, 0))
          AND (p_id_ubicacion      IS NULL OR ih.id_ubicacion      = p_id_ubicacion)
          AND (p_id_proveedor      IS NULL OR ih.id_proveedor      = p_id_proveedor)
          AND (p_origen_cambio     IS NULL OR ih.origen_cambio     = p_origen_cambio)
        ORDER BY
            ih.id_producto,
            COALESCE(ih.id_variante, 0),
            COALESCE(ih.id_opcion_variante, 0),
            COALESCE(ih.id_presentacion, 0),
            COALESCE(ih.id_ubicacion, 0),
            ih.id DESC
    ),
    inv_filtrado AS (
        SELECT
            i.id,
            i.id_producto,
            i.id_variante,
            i.id_opcion_variante,
            i.id_ubicacion,
            i.id_presentacion,
            i.cantidad_inicial,
            i.cantidad_final,
            i.created_at,
            i.origen_cambio,
            i.id_recepcion,
            i.id_extraccion,
            i.id_control,
            i.id_proveedor,
            a.id           AS id_almacen,
            t.id           AS id_tienda,
            abc.clasificacion_abc
        FROM inv_last i
        INNER JOIN public.app_dat_layout_almacen l ON i.id_ubicacion = l.id
        INNER JOIN public.app_dat_almacen a       ON l.id_almacen   = a.id
        INNER JOIN public.app_dat_tienda t        ON a.id_tienda    = t.id
        LEFT  JOIN public.app_dat_layout_abc abc  ON l.id           = abc.id_layout
        WHERE (p_id_tienda  IS NULL OR t.id = p_id_tienda)
          AND (p_id_almacen IS NULL OR a.id = p_id_almacen)
          AND (p_clasificacion_abc IS NULL OR abc.clasificacion_abc = p_clasificacion_abc)
          AND (p_mostrar_sin_stock = TRUE OR i.cantidad_final > 0)
          AND (
                p_con_stock_minimo IS NULL OR
                i.cantidad_final <= COALESCE(
                    (SELECT ls.stock_min
                     FROM app_dat_almacen_limites ls
                     WHERE ls.id_producto = i.id_producto AND ls.id_almacen = a.id),
                    0
                )
          )
    ),
    base AS (
        SELECT
            inv.*,
            p.sku            AS sku_producto,
            p.denominacion   AS nombre_producto,
            p.nombre_comercial,
            p.denominacion_corta,
            p.descripcion,
            p.descripcion_corta,
            p.um,
            p.id_categoria,
            p.id_tienda      AS p_id_tienda,
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
            cat.denominacion AS categoria_denom,
            l.denominacion   AS ubicacion_denom,
            a.denominacion   AS almacen_denom,
            t.denominacion   AS tienda_denom,
            v.id_atributo,
            attr_v.denominacion AS atributo_denom,
            ao.valor          AS opcion_valor,
            np.denominacion   AS presentacion_denom
        FROM inv_filtrado inv
        INNER JOIN public.app_dat_producto p              ON inv.id_producto = p.id
        INNER JOIN public.app_dat_layout_almacen l        ON inv.id_ubicacion = l.id
        INNER JOIN public.app_dat_almacen a               ON inv.id_almacen   = a.id
        INNER JOIN public.app_dat_tienda t                ON inv.id_tienda    = t.id
        LEFT  JOIN public.app_dat_categoria cat           ON p.id_categoria   = cat.id
        LEFT  JOIN public.app_dat_variantes v             ON inv.id_variante  = v.id
        LEFT  JOIN public.app_dat_atributos attr_v        ON v.id_atributo    = attr_v.id
        LEFT  JOIN public.app_dat_atributo_opcion ao      ON inv.id_opcion_variante = ao.id
        LEFT  JOIN public.app_dat_producto_presentacion pp ON inv.id_presentacion   = pp.id
        LEFT  JOIN public.app_nom_presentacion np         ON pp.id_presentacion = np.id
        WHERE (p_id_categoria    IS NULL OR p.id_categoria    = p_id_categoria)
          AND (p_es_vendible     IS NULL OR p.es_vendible     = p_es_vendible)
          AND (p_es_inventariable IS NULL OR p.es_inventariable = p_es_inventariable)
          AND (p_id_subcategoria IS NULL OR EXISTS (
                  SELECT 1
                  FROM public.app_dat_productos_subcategorias ps
                  WHERE ps.id_producto = p.id
                    AND ps.id_sub_categoria = p_id_subcategoria
              ))
          AND (
                p_busqueda IS NULL OR
                p.denominacion       ILIKE '%' || p_busqueda || '%' OR
                p.sku                ILIKE '%' || p_busqueda || '%' OR
                p.codigo_barras      ILIKE '%' || p_busqueda || '%' OR
                p.nombre_comercial   ILIKE '%' || p_busqueda || '%' OR
                p.descripcion        ILIKE '%' || p_busqueda || '%' OR
                cat.denominacion     ILIKE '%' || p_busqueda || '%' OR
                attr_v.denominacion  ILIKE '%' || p_busqueda || '%' OR
                ao.valor             ILIKE '%' || p_busqueda || '%' OR
                np.denominacion      ILIKE '%' || p_busqueda || '%'
              )
    ),
    psc AS (
        SELECT DISTINCT ON (ps.id_producto)
            ps.id_producto,
            ps.id_sub_categoria AS id_subcategoria,
            s.denominacion      AS subcategoria
        FROM public.app_dat_productos_subcategorias ps
        LEFT JOIN public.app_dat_subcategorias s ON ps.id_sub_categoria = s.id
        WHERE ps.id_producto IN (SELECT base.id_producto FROM base)
        ORDER BY ps.id_producto, ps.id_sub_categoria
    ),
    pa AS (
        SELECT DISTINCT ON (pv.id_producto, COALESCE(pv.id_variante, 0))
            pv.id_producto,
            COALESCE(pv.id_variante, 0) AS id_variante,
            pv.precio_venta_cup
        FROM public.app_dat_precio_venta pv
        WHERE (pv.fecha_hasta IS NULL OR pv.fecha_hasta >= CURRENT_DATE)
          AND pv.id_producto IN (SELECT base.id_producto FROM base)
        ORDER BY pv.id_producto, COALESCE(pv.id_variante, 0), pv.fecha_desde DESC, pv.id DESC
    ),
    sr AS (
        SELECT
            ep.id_producto,
            COALESCE(ep.id_variante, 0)        AS id_variante,
            COALESCE(ep.id_opcion_variante, 0) AS id_opcion_variante,
            ep.id_ubicacion,
            SUM(ep.cantidad)                   AS reservado
        FROM app_dat_extraccion_productos ep
        INNER JOIN app_dat_operaciones o ON ep.id_operacion = o.id
        INNER JOIN LATERAL (
            SELECT eo.estado
            FROM app_dat_estado_operacion eo
            WHERE eo.id_operacion = o.id
            ORDER BY eo.created_at DESC
            LIMIT 1
        ) ult ON ult.estado = 1
        WHERE ep.id_producto IN (SELECT base.id_producto FROM base)
        GROUP BY ep.id_producto, COALESCE(ep.id_variante, 0),
                 COALESCE(ep.id_opcion_variante, 0), ep.id_ubicacion
    ),
    rc AS (
        SELECT
            rpc.id_producto,
            rpc.id_ubicacion,
            SUM(cart.quantity) AS reservado
        FROM public.relation_products_carnaval rpc
        JOIN carnavalapp."Carrito" cart ON cart.product_id = rpc.id_producto_carnaval
        WHERE rpc.id_producto IN (SELECT base.id_producto FROM base)
        GROUP BY rpc.id_producto, rpc.id_ubicacion
    ),
    enriched AS (
        SELECT
            b.*,
            psc.id_subcategoria,
            psc.subcategoria,
            pa.precio_venta_cup,
            COALESCE(sr.reservado, 0) AS stock_reservado_val,
            COALESCE(rc.reservado, 0) AS reservado_carnaval_val,
            COUNT(*) OVER ()                                              AS total_count,
            COUNT(*) FILTER (WHERE b.cantidad_final < 10) OVER ()         AS total_baja,
            COUNT(*) FILTER (WHERE b.cantidad_final = 0)  OVER ()         AS total_cero,
            ROW_NUMBER() OVER (
                ORDER BY b.tienda_denom, b.almacen_denom, b.ubicacion_denom,
                         b.nombre_producto, COALESCE(b.id_variante, 0)
            ) AS rn
        FROM base b
        LEFT JOIN psc ON b.id_producto = psc.id_producto
        LEFT JOIN pa  ON pa.id_producto = b.id_producto
                     AND pa.id_variante = COALESCE(b.id_variante, 0)
        LEFT JOIN sr  ON sr.id_producto = b.id_producto
                     AND sr.id_variante = COALESCE(b.id_variante, 0)
                     AND sr.id_opcion_variante = COALESCE(b.id_opcion_variante, 0)
                     AND sr.id_ubicacion = b.id_ubicacion
        LEFT JOIN rc  ON rc.id_producto = b.id_producto
                     AND rc.id_ubicacion = b.id_ubicacion
        WHERE (p_id_subcategoria IS NULL OR psc.id_subcategoria = p_id_subcategoria)
    )
    SELECT
        e.id_producto::BIGINT,
        e.sku_producto::TEXT,
        e.nombre_producto::TEXT,
        e.nombre_comercial::TEXT,
        e.denominacion_corta::TEXT,
        e.descripcion::TEXT,
        e.descripcion_corta::TEXT,
        e.um::TEXT,
        e.id_categoria::BIGINT,
        COALESCE(e.categoria_denom, 'Sin categoría')::TEXT,
        e.id_subcategoria::BIGINT,
        COALESCE(e.subcategoria, 'Sin subcategoría')::TEXT,
        e.p_id_tienda::BIGINT,
        e.tienda_denom::TEXT,
        e.id_almacen::BIGINT,
        e.almacen_denom::TEXT,
        e.id_ubicacion::BIGINT,
        e.ubicacion_denom::TEXT,
        e.id_variante::BIGINT,
        COALESCE(e.atributo_denom, 'Unidad')::TEXT,
        e.id_opcion_variante::BIGINT,
        COALESCE(e.opcion_valor, 'Única')::TEXT,
        e.id_presentacion::BIGINT,
        COALESCE(e.presentacion_denom, 'Unidad')::TEXT,
        e.cantidad_inicial::NUMERIC,
        e.cantidad_final::NUMERIC,
        e.cantidad_final::NUMERIC                                          AS stock_disponible,
        e.stock_reservado_val::NUMERIC                                     AS stock_reservado,
        GREATEST(e.cantidad_final - e.stock_reservado_val, 0)::NUMERIC     AS stock_disponible_ajustado,
        e.es_vendible::BOOLEAN,
        e.es_comprable::BOOLEAN,
        e.es_inventariable::BOOLEAN,
        e.es_por_lotes::BOOLEAN,
        e.dias_alert_caducidad::NUMERIC,
        e.es_refrigerado::BOOLEAN,
        e.es_fragil::BOOLEAN,
        e.es_peligroso::BOOLEAN,
        e.es_elaborado::BOOLEAN,
        e.es_servicio::BOOLEAN,
        e.imagen::TEXT,
        e.codigo_barras::TEXT,
        COALESCE(e.precio_venta_cup, 0)::NUMERIC                           AS precio_venta,
        0::NUMERIC                                                          AS costo_promedio,
        NULL::NUMERIC                                                       AS margen_actual,
        COALESCE(e.clasificacion_abc, 3)::SMALLINT,
        CASE COALESCE(e.clasificacion_abc, 3)
            WHEN 1 THEN 'A (Alta Rotación)'
            WHEN 2 THEN 'B (Media Rotación)'
            WHEN 3 THEN 'C (Baja Rotación)'
            ELSE 'No clasificado'
        END::TEXT AS abc_descripcion,
        e.created_at::TIMESTAMPTZ                                          AS fecha_ultima_actualizacion,
        e.total_count::BIGINT,
        jsonb_build_object(
            'total_inventario',        e.total_count,
            'total_con_cantidad_baja', e.total_baja,
            'total_sin_stock',         e.total_cero,
            'reservado_carnaval', jsonb_build_object(
                'id_producto',  e.id_producto,
                'id_ubicacion', e.id_ubicacion,
                'cantidad',     e.reservado_carnaval_val
            )
        )::JSONB AS resumen_inventario,
        jsonb_build_object(
            'pagina_actual',   p_pagina,
            'total_items',     p_limite,
            'total_paginas',   CEIL(e.total_count::NUMERIC / NULLIF(p_limite, 0))::INTEGER,
            'total_registros', e.total_count,
            'tiene_anterior',  p_pagina > 1,
            'tiene_siguiente', (p_pagina * p_limite) < e.total_count
        )::JSONB AS info_paginacion
    FROM enriched e
    WHERE e.rn > v_offset
      AND e.rn <= v_offset + p_limite
    ORDER BY e.rn;
END;
