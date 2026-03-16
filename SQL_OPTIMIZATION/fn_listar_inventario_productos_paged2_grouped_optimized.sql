CREATE OR REPLACE FUNCTION public.fn_listar_inventario_productos_paged2_grouped2_optimiized(
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
BEGIN
    -- Validar acceso si se especifica tienda
    IF p_id_tienda IS NOT NULL THEN
        PERFORM check_user_has_access_to_tienda(p_id_tienda);
        IF NOT EXISTS (SELECT 1 FROM app_dat_tienda t WHERE t.id = p_id_tienda) THEN
            RAISE EXCEPTION 'La tienda con ID % no existe', p_id_tienda;
        END IF;
    END IF;

    -- =====================================================================
    -- BASE FILTRADA: un único escaneo con todos los filtros aplicados.
    -- Reutilizada para count, resumen y datos principales.
    -- =====================================================================
    RETURN QUERY
    WITH base_filtrada AS (
        SELECT
            i.id_producto,
            i.id_variante,
            i.id_opcion_variante,
            i.id_ubicacion,
            i.id_presentacion,
            i.cantidad_inicial,
            i.cantidad_final,
            i.created_at,
            i.id_recepcion,
            i.id_proveedor,
            p.sku              AS sku_producto,
            p.denominacion     AS nombre_producto,
            p.nombre_comercial,
            p.denominacion_corta,
            p.descripcion,
            p.descripcion_corta,
            p.um,
            p.id_categoria,
            p.id_tienda        AS p_tienda_id,
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
            l.id               AS l_id,
            l.denominacion     AS ubicacion_nom,
            a.id               AS a_id,
            a.denominacion     AS almacen_nom,
            t.id               AS t_id,
            t.denominacion     AS tienda_nom,
            ps.id_sub_categoria,
            attr.denominacion  AS attr_den,
            vo.valor           AS vo_valor,
            pr.id              AS pr_id,
            abc.clasificacion_abc,
            lim.stock_min
        FROM public.app_dat_inventario_productos i
        INNER JOIN public.app_dat_producto p              ON i.id_producto  = p.id
        INNER JOIN public.app_dat_layout_almacen l        ON i.id_ubicacion = l.id
        INNER JOIN public.app_dat_almacen a               ON l.id_almacen   = a.id
        INNER JOIN public.app_dat_tienda t                ON a.id_tienda    = t.id
        LEFT JOIN  public.app_dat_categoria c_filt        ON p.id_categoria = c_filt.id
        LEFT JOIN  public.app_dat_productos_subcategorias ps ON p.id        = ps.id_producto
        LEFT JOIN  public.app_dat_subcategorias s          ON ps.id_sub_categoria = s.id
        LEFT JOIN  public.app_dat_variantes v              ON i.id_variante = v.id
        LEFT JOIN  public.app_dat_atributos attr           ON v.id_atributo = attr.id
        LEFT JOIN  public.app_dat_atributo_opcion vo       ON i.id_opcion_variante = vo.id
        LEFT JOIN  public.app_dat_producto_presentacion pr ON i.id_presentacion    = pr.id
        LEFT JOIN  public.app_dat_layout_abc abc           ON l.id = abc.id_layout
        LEFT JOIN  public.app_dat_almacen_limites lim      ON lim.id_producto = p.id AND lim.id_almacen = a.id
        WHERE
            (p_id_tienda          IS NULL OR t.id                   = p_id_tienda)
            AND (p_id_almacen     IS NULL OR a.id                   = p_id_almacen)
            AND (p_id_ubicacion   IS NULL OR l.id                   = p_id_ubicacion)
            AND (p_id_producto    IS NULL OR p.id                   = p_id_producto)
            AND (p_id_variante    IS NULL OR v.id                   = p_id_variante)
            AND (p_id_opcion_variante IS NULL OR vo.id              = p_id_opcion_variante)
            AND (p_id_presentacion    IS NULL OR pr.id              = p_id_presentacion)
            AND (p_id_categoria   IS NULL OR p.id_categoria         = p_id_categoria)
            AND (p_id_subcategoria IS NULL OR s.id                  = p_id_subcategoria)
            AND (p_id_proveedor   IS NULL OR i.id_proveedor         = p_id_proveedor)
            AND (p_origen_cambio  IS NULL OR i.origen_cambio        = p_origen_cambio)
            AND (p_es_vendible    IS NULL OR p.es_vendible          = p_es_vendible)
            AND (p_es_inventariable IS NULL OR p.es_inventariable   = p_es_inventariable)
            AND (p_clasificacion_abc IS NULL OR abc.clasificacion_abc = p_clasificacion_abc)
            AND (p_mostrar_sin_stock = TRUE OR i.cantidad_final > 0)
            AND (p_con_stock_minimo IS NULL OR i.cantidad_final <= COALESCE(lim.stock_min, 0))
            AND (
                p_busqueda IS NULL
                OR p.denominacion     ILIKE '%' || p_busqueda || '%'
                OR p.sku              ILIKE '%' || p_busqueda || '%'
                OR p.codigo_barras    ILIKE '%' || p_busqueda || '%'
                OR p.nombre_comercial ILIKE '%' || p_busqueda || '%'
                OR p.descripcion      ILIKE '%' || p_busqueda || '%'
                OR c_filt.denominacion ILIKE '%' || p_busqueda || '%'
                OR s.denominacion     ILIKE '%' || p_busqueda || '%'
                OR attr.denominacion  ILIKE '%' || p_busqueda || '%'
                OR vo.valor           ILIKE '%' || p_busqueda || '%'
            )
    ),
    -- ── Count + summary computed from the same base (no extra full scan) ──
    stats AS (
        SELECT
            COUNT(DISTINCT bf.id_producto)                                       AS total_count,
            COUNT(DISTINCT bf.id_producto)                                       AS total_inventario,
            COUNT(DISTINCT CASE WHEN ps.total_stock < 10 THEN bf.id_producto END) AS total_con_cantidad_baja,
            COUNT(DISTINCT CASE WHEN ps.total_stock = 0  THEN bf.id_producto END) AS total_sin_stock
        FROM base_filtrada bf
        JOIN (
            SELECT bf2.id_producto, SUM(bf2.cantidad_final) AS total_stock
            FROM base_filtrada bf2
            GROUP BY bf2.id_producto
        ) ps ON bf.id_producto = ps.id_producto
    ),
    -- ── Deduplicate per (product, variant, presentation, location) ────────
    inventario_detalle AS (
        SELECT DISTINCT ON (
            bf.id_producto,
            COALESCE(bf.id_variante, 0),
            COALESCE(bf.id_opcion_variante, 0),
            COALESCE(bf.id_presentacion, 0),
            bf.id_ubicacion
        )
            bf.id_producto,
            bf.id_variante,
            bf.id_opcion_variante,
            bf.id_ubicacion,
            bf.id_presentacion,
            bf.cantidad_inicial,
            bf.cantidad_final,
            bf.created_at        AS fecha_ultima_actualizacion,
            bf.sku_producto,
            bf.nombre_producto,
            bf.nombre_comercial,
            bf.denominacion_corta,
            bf.descripcion,
            bf.descripcion_corta,
            bf.um,
            bf.id_categoria,
            bf.p_tienda_id,
            bf.es_vendible,
            bf.es_comprable,
            bf.es_inventariable,
            bf.es_por_lotes,
            bf.dias_alert_caducidad,
            bf.es_refrigerado,
            bf.es_fragil,
            bf.es_peligroso,
            bf.es_elaborado,
            bf.es_servicio,
            bf.imagen,
            bf.codigo_barras,
            bf.l_id,
            bf.ubicacion_nom,
            bf.a_id,
            bf.almacen_nom,
            bf.t_id,
            bf.tienda_nom,
            bf.id_sub_categoria,
            bf.attr_den,
            bf.vo_valor,
            bf.pr_id,
            bf.clasificacion_abc
        FROM base_filtrada bf
        ORDER BY
            bf.id_producto,
            COALESCE(bf.id_variante, 0),
            COALESCE(bf.id_opcion_variante, 0),
            COALESCE(bf.id_presentacion, 0),
            bf.id_ubicacion,
            bf.created_at DESC,
            bf.id_recepcion DESC
    ),
    -- ── Price: most-recent active price per product ───────────────────────
    precio_info AS (
        SELECT DISTINCT ON (pv.id_producto)
            pv.id_producto,
            COALESCE(pv.precio_venta_cup, 0) AS precio_venta
        FROM public.app_dat_precio_venta pv
        WHERE (pv.id_variante IS NULL OR pv.id_variante = 0)
          AND (pv.fecha_hasta IS NULL OR pv.fecha_hasta >= CURRENT_DATE)
          AND (p_id_producto IS NULL OR pv.id_producto = p_id_producto::BIGINT)
        ORDER BY pv.id_producto, pv.created_at DESC
    ),
    -- ── Presentation name ─────────────────────────────────────────────────
    presentacion_nombre AS (
        SELECT pp.id AS id_pp, np.denominacion AS presentacion_nom
        FROM public.app_dat_producto_presentacion pp
        JOIN public.app_nom_presentacion np ON pp.id_presentacion = np.id
    ),
    -- ── Reserved stock: only pending operations (estado = 1) ─────────────
    stock_reservado AS (
        SELECT
            ep.id_producto,
            COALESCE(ep.id_variante, 0)        AS id_variante,
            COALESCE(ep.id_opcion_variante, 0) AS id_opcion_variante,
            ep.id_ubicacion,
            SUM(ep.cantidad)                   AS reservado
        FROM app_dat_extraccion_productos ep
        INNER JOIN app_dat_operaciones o ON ep.id_operacion = o.id
        INNER JOIN (
            SELECT DISTINCT ON (eo.id_operacion)
                eo.id_operacion,
                eo.estado
            FROM app_dat_estado_operacion eo
            ORDER BY eo.id_operacion, eo.created_at DESC
        ) ultimo_estado ON o.id = ultimo_estado.id_operacion AND ultimo_estado.estado = 1
        WHERE (p_id_producto IS NULL OR ep.id_producto = p_id_producto::BIGINT)
        GROUP BY ep.id_producto, COALESCE(ep.id_variante, 0), COALESCE(ep.id_opcion_variante, 0), ep.id_ubicacion
    ),
    -- ── Combine all detail data ───────────────────────────────────────────
    datos_completos AS (
        SELECT
            inv.id_producto                                              AS prod_id,
            inv.sku_producto,
            inv.nombre_producto,
            inv.nombre_comercial,
            inv.denominacion_corta,
            inv.descripcion,
            inv.descripcion_corta,
            inv.um,
            inv.id_categoria,
            COALESCE(cat.denominacion, 'Sin categoría')                  AS categoria,
            inv.id_sub_categoria,
            COALESCE(sub.denominacion, 'Sin subcategoría')               AS subcategoria,
            inv.p_tienda_id,
            inv.tienda_nom,
            inv.a_id,
            inv.almacen_nom,
            inv.l_id,
            inv.ubicacion_nom,
            inv.id_variante                                              AS variante_id,
            COALESCE(inv.attr_den, 'Unidad')                             AS variante,
            inv.id_opcion_variante                                       AS opcion_variante_id,
            COALESCE(inv.vo_valor, 'Única')                              AS opcion_variante,
            inv.id_presentacion                                          AS presentacion_id,
            COALESCE(pn.presentacion_nom, 'Unidad')                      AS presentacion,
            inv.cantidad_inicial,
            inv.cantidad_final,
            inv.cantidad_final                                           AS stock_disponible,
            COALESCE(sr.reservado, 0)                                    AS stock_reservado_val,
            GREATEST(inv.cantidad_final - COALESCE(sr.reservado, 0), 0) AS stock_disponible_ajustado_val,
            inv.es_vendible,
            inv.es_comprable,
            inv.es_inventariable,
            inv.es_por_lotes,
            inv.dias_alert_caducidad,
            inv.es_refrigerado,
            inv.es_fragil,
            inv.es_peligroso,
            inv.es_elaborado,
            inv.es_servicio,
            inv.imagen,
            inv.codigo_barras,
            COALESCE(pv.precio_venta, 0)                                 AS precio_venta,
            0::NUMERIC                                                   AS costo_promedio,
            COALESCE(inv.clasificacion_abc::INTEGER, 3)                  AS clasificacion_abc_val,
            inv.fecha_ultima_actualizacion
        FROM inventario_detalle inv
        LEFT JOIN public.app_dat_categoria cat     ON inv.id_categoria    = cat.id
        LEFT JOIN public.app_dat_subcategorias sub ON inv.id_sub_categoria = sub.id
        LEFT JOIN precio_info pv                   ON inv.id_producto     = pv.id_producto
        LEFT JOIN presentacion_nombre pn           ON inv.pr_id           = pn.id_pp
        LEFT JOIN stock_reservado sr ON (
            inv.id_producto                         = sr.id_producto
            AND COALESCE(inv.id_variante, 0)        = sr.id_variante
            AND COALESCE(inv.id_opcion_variante, 0) = sr.id_opcion_variante
            AND inv.id_ubicacion                    = sr.id_ubicacion
        )
        WHERE
            (p_id_categoria       IS NULL OR inv.id_categoria      = p_id_categoria)
            AND (p_id_subcategoria IS NULL OR inv.id_sub_categoria  = p_id_subcategoria)
            AND (p_es_vendible    IS NULL OR inv.es_vendible        = p_es_vendible)
            AND (p_es_inventariable IS NULL OR inv.es_inventariable = p_es_inventariable)
            AND (p_clasificacion_abc IS NULL OR inv.clasificacion_abc = p_clasificacion_abc)
            AND (p_mostrar_sin_stock = TRUE OR inv.cantidad_final   > 0)
    )
    -- ── Final grouped SELECT with stats injected inline ───────────────────
    SELECT
        d.prod_id::BIGINT                                    AS id_producto,
        MIN(d.sku_producto)::TEXT                            AS sku_producto,
        MIN(d.nombre_producto)::TEXT                         AS nombre_producto,
        MIN(d.nombre_comercial)::TEXT                        AS nombre_comercial,
        MIN(d.denominacion_corta)::TEXT                      AS denominacion_corta,
        MIN(d.descripcion)::TEXT                             AS descripcion,
        MIN(d.descripcion_corta)::TEXT                       AS descripcion_corta,
        MIN(d.um)::TEXT                                      AS um,
        MIN(d.id_categoria)::BIGINT                          AS id_categoria,
        MIN(d.categoria)::TEXT                               AS categoria,
        MIN(d.id_sub_categoria)::BIGINT                      AS id_subcategoria,
        MIN(d.subcategoria)::TEXT                            AS subcategoria,
        MIN(d.p_tienda_id)::BIGINT                           AS id_tienda,
        MIN(d.tienda_nom)::TEXT                              AS tienda,
        MIN(d.a_id)::BIGINT                                  AS id_almacen,
        MIN(d.almacen_nom)::TEXT                             AS almacen,
        MIN(d.l_id)::BIGINT                                  AS id_ubicacion,
        MIN(d.ubicacion_nom)::TEXT                           AS ubicacion,
        MIN(d.variante_id)::BIGINT                           AS id_variante,
        MIN(d.variante)::TEXT                                AS variante,
        MIN(d.opcion_variante_id)::BIGINT                    AS id_opcion_variante,
        MIN(d.opcion_variante)::TEXT                         AS opcion_variante,
        MIN(d.presentacion_id)::BIGINT                       AS id_presentacion,
        MIN(d.presentacion)::TEXT                            AS presentacion,
        SUM(d.cantidad_inicial)::NUMERIC                     AS cantidad_inicial,
        SUM(d.cantidad_final)::NUMERIC                       AS cantidad_final,
        SUM(d.stock_disponible)::NUMERIC                     AS stock_disponible,
        SUM(d.stock_reservado_val)::NUMERIC                  AS stock_reservado,
        SUM(d.stock_disponible_ajustado_val)::NUMERIC        AS stock_disponible_ajustado,
        BOOL_OR(d.es_vendible)::BOOLEAN                      AS es_vendible,
        BOOL_OR(d.es_comprable)::BOOLEAN                     AS es_comprable,
        BOOL_OR(d.es_inventariable)::BOOLEAN                 AS es_inventariable,
        BOOL_OR(d.es_por_lotes)::BOOLEAN                     AS es_por_lotes,
        MIN(d.dias_alert_caducidad)::NUMERIC                 AS dias_alert_caducidad,
        BOOL_OR(d.es_refrigerado)::BOOLEAN                   AS es_refrigerado,
        BOOL_OR(d.es_fragil)::BOOLEAN                        AS es_fragil,
        BOOL_OR(d.es_peligroso)::BOOLEAN                     AS es_peligroso,
        BOOL_OR(d.es_elaborado)::BOOLEAN                     AS es_elaborado,
        BOOL_OR(d.es_servicio)::BOOLEAN                      AS es_servicio,
        MIN(d.imagen)::TEXT                                  AS imagen,
        MIN(d.codigo_barras)::TEXT                           AS codigo_barras,
        MIN(d.precio_venta)::NUMERIC                         AS precio_venta,
        MIN(d.costo_promedio)::NUMERIC                       AS costo_promedio,
        CASE
            WHEN MIN(d.precio_venta) IS NOT NULL
             AND MIN(d.costo_promedio) IS NOT NULL
             AND MIN(d.costo_promedio) > 0
            THEN ROUND(((MIN(d.precio_venta) - MIN(d.costo_promedio)) / MIN(d.precio_venta)) * 100, 2)
            ELSE NULL
        END::NUMERIC                                         AS margen_actual,
        MIN(d.clasificacion_abc_val)::INTEGER                AS clasificacion_abc,
        MIN(CASE d.clasificacion_abc_val
                WHEN 1 THEN 'A (Alta Rotación)'
                WHEN 2 THEN 'B (Media Rotación)'
                WHEN 3 THEN 'C (Baja Rotación)'
                ELSE 'No clasificado'
            END)::TEXT                                       AS abc_descripcion,
        MAX(d.fecha_ultima_actualizacion)::TIMESTAMPTZ       AS fecha_ultima_actualizacion,
        (SELECT s.total_count    FROM stats s LIMIT 1)::BIGINT AS total_count,
        jsonb_build_object(
            'total_inventario',        (SELECT s.total_inventario        FROM stats s LIMIT 1),
            'total_con_cantidad_baja', (SELECT s.total_con_cantidad_baja FROM stats s LIMIT 1),
            'total_sin_stock',         (SELECT s.total_sin_stock         FROM stats s LIMIT 1)
        )::JSONB AS resumen_inventario,
        jsonb_build_object(
            'pagina_actual',   p_pagina,
            'total_items',     p_limite,
            'total_paginas',   1,
            'total_registros', (SELECT s.total_count FROM stats s LIMIT 1),
            'tiene_anterior',  false,
            'tiene_siguiente', false
        )::JSONB AS info_paginacion
    FROM datos_completos d
    GROUP BY d.prod_id
    ORDER BY MIN(d.tienda_nom), MIN(d.almacen_nom), MIN(d.ubicacion_nom), MIN(d.nombre_producto);
END;
$$;
