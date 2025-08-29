CREATE OR REPLACE FUNCTION fn_listar_operaciones_inventario_re(
    p_id_tienda BIGINT DEFAULT NULL,
    p_id_tpv BIGINT DEFAULT NULL,
    p_id_tipo_operacion BIGINT DEFAULT NULL,
    p_estados SMALLINT[] DEFAULT NULL,
    p_fecha_desde DATE DEFAULT NULL,
    p_fecha_hasta DATE DEFAULT NULL,
    p_uuid_usuario_operador UUID DEFAULT NULL,
    p_busqueda TEXT DEFAULT NULL,
    p_limite INTEGER DEFAULT 20,
    p_pagina INTEGER DEFAULT 1
)
RETURNS TABLE (
    id BIGINT,
    tipo_operacion_nombre TEXT,
    id_tienda BIGINT,
    tienda_nombre TEXT,
    id_tpv BIGINT,
    tpv_nombre TEXT,
    uuid UUID,
    usuario_email TEXT,
    estado SMALLINT,
    estado_nombre TEXT,
    created_at TIMESTAMPTZ,
    total NUMERIC,
    cantidad_items INTEGER,
    observaciones TEXT,
    detalles JSONB,
    total_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_offset INTEGER := (p_pagina - 1) * p_limite;
    v_total_count BIGINT;
BEGIN
    -- ✅ Validar que el usuario tenga acceso a al menos una tienda
    PERFORM check_user_has_access_to_any_tienda();

    -- ✅ Contar total de operaciones (para paginación)
    SELECT COUNT(*) INTO v_total_count
    FROM (
        SELECT o.id
        FROM public.app_dat_operaciones o
        INNER JOIN public.app_nom_tipo_operacion top ON o.id_tipo_operacion = top.id
        INNER JOIN public.app_dat_tienda t ON o.id_tienda = t.id
        -- Último estado de la operación
        INNER JOIN (
            SELECT e1.id_operacion, e1.estado
            FROM public.app_dat_estado_operacion e1
            WHERE e1.created_at = (
                SELECT MAX(e2.created_at)
                FROM app_dat_estado_operacion e2
                WHERE e2.id_operacion = e1.id_operacion
            )
        ) e ON o.id = e.id_operacion
        -- ✅ Ahora podemos hacer JOIN seguro con el catálogo de estados
        INNER JOIN public.app_nom_estado_operacion neo ON e.estado = neo.id
        -- Datos específicos por tipo de operación
        LEFT JOIN public.app_dat_operacion_venta ov ON o.id = ov.id_operacion
        LEFT JOIN public.app_dat_operacion_recepcion orp ON o.id = orp.id_operacion
        LEFT JOIN public.app_dat_operacion_extraccion oe ON o.id = oe.id_operacion
        LEFT JOIN public.app_dat_operacion_transferencia ot ON o.id = ot.id_operacion
        WHERE 1 = 1
            AND (p_id_tienda IS NULL OR o.id_tienda = p_id_tienda)
            AND (p_id_tpv IS NULL OR EXISTS (
                SELECT 1 FROM app_dat_operacion_venta ov2 WHERE ov2.id_operacion = o.id AND ov2.id_tpv = p_id_tpv
            ))
            AND (p_id_tipo_operacion IS NULL OR o.id_tipo_operacion = p_id_tipo_operacion)
            AND (p_estados IS NULL OR e.estado = ANY(p_estados))
            AND (p_fecha_desde IS NULL OR o.created_at::DATE >= p_fecha_desde)
            AND (p_fecha_hasta IS NULL OR o.created_at::DATE <= p_fecha_hasta)
            AND (p_uuid_usuario_operador IS NULL OR o.uuid = p_uuid_usuario_operador)
            AND (
                p_busqueda IS NULL OR
                top.denominacion ILIKE '%' || p_busqueda || '%' OR
                t.denominacion ILIKE '%' || p_busqueda || '%' OR
                o.observaciones ILIKE '%' || p_busqueda || '%'
            )
            -- Validar acceso del usuario a la tienda
            AND EXISTS (
                SELECT 1 FROM (
                    SELECT g.id_tienda FROM app_dat_gerente g WHERE g.uuid = auth.uid()
                    UNION
                    SELECT s.id_tienda FROM app_dat_supervisor s WHERE s.uuid = auth.uid()
                    UNION
                    SELECT a.id_tienda FROM app_dat_almacenero al JOIN app_dat_almacen a ON al.id_almacen = a.id WHERE al.uuid = auth.uid()
                    UNION
                    SELECT tpv.id_tienda FROM app_dat_vendedor v JOIN app_dat_tpv tpv ON v.id_tpv = tpv.id WHERE v.uuid = auth.uid()
                ) accesos
                WHERE accesos.id_tienda = o.id_tienda
            )
    ) AS conteo;

    -- ✅ Retornar operaciones paginadas
    RETURN QUERY
    WITH operaciones_filtradas AS (
        SELECT
            o.id,
            o.created_at,
            o.id_tipo_operacion,
            top.denominacion AS tipo_operacion_nombre,
            o.id_tienda,
            t.denominacion AS tienda_nombre,
            o.uuid,
            'Sistema' AS usuario_email,
            e.estado,
            neo.denominacion AS estado_nombre, -- ✅ Usamos el nombre desde el catálogo
            o.observaciones,
            -- Datos específicos por tipo de operación
            CASE
                WHEN o.id_tipo_operacion = (SELECT top_sub.id FROM app_nom_tipo_operacion top_sub WHERE top_sub.denominacion = 'Venta') THEN
                    (SELECT jsonb_build_object(
                        'id_tpv', tpv.id,
                        'tpv_nombre', tpv.denominacion,
                        'total', ov.monto_total,
                        'cantidad_items', COUNT(ep.id)
                    )
                    FROM app_dat_operacion_venta ov
                    JOIN app_dat_tpv tpv ON ov.id_tpv = tpv.id
                    LEFT JOIN app_dat_extraccion_productos ep ON ov.id_operacion = ep.id_operacion
                    WHERE ov.id_operacion = o.id
                    GROUP BY tpv.id, tpv.denominacion, ov.monto_total)
                WHEN o.id_tipo_operacion = (SELECT top_sub.id FROM app_nom_tipo_operacion top_sub WHERE top_sub.denominacion ILIKE '%recepcion%') THEN
                    (SELECT jsonb_build_object(
                        'entregado_por', orp.entregado_por,
                        'recibido_por', orp.recibido_por,
                        'monto_total', orp.monto_total,
                        'cantidad_items', COUNT(rp.id)
                    )
                    FROM app_dat_operacion_recepcion orp
                    LEFT JOIN app_dat_recepcion_productos rp ON orp.id_operacion = rp.id_operacion
                    WHERE orp.id_operacion = o.id
                    GROUP BY orp.entregado_por, orp.recibido_por, orp.monto_total)
                WHEN o.id_tipo_operacion = (SELECT top_sub.id FROM app_nom_tipo_operacion top_sub WHERE top_sub.denominacion ILIKE '%extraccion%') THEN
                    (SELECT jsonb_build_object(
                        'motivo', oe.id_motivo_operacion,
                        'observaciones', oe.observaciones,
                        'cantidad_items', COUNT(ep.id)
                    )
                    FROM app_dat_operacion_extraccion oe
                    LEFT JOIN app_dat_extraccion_productos ep ON oe.id_operacion = ep.id_operacion
                    WHERE oe.id_operacion = o.id
                    GROUP BY oe.id_motivo_operacion, oe.observaciones)
                WHEN o.id_tipo_operacion = (SELECT top_sub.id FROM app_nom_tipo_operacion top_sub WHERE top_sub.denominacion ILIKE '%transferencia%') THEN
                    (SELECT jsonb_build_object(
                        'autorizado_por', ot.autorizado_por,
                        'id_recepcion', ot.id_recepcion,
                        'id_extraccion', ot.id_extraccion,
                        'cantidad_items', COUNT(ep.id)
                    )
                    FROM app_dat_operacion_transferencia ot
                    LEFT JOIN app_dat_extraccion_productos ep ON ot.id_extraccion = ep.id_operacion
                    WHERE ot.id_operacion = o.id
                    GROUP BY ot.autorizado_por, ot.id_recepcion, ot.id_extraccion)
                ELSE
                    '{}'::jsonb
            END AS datos_especificos,
            -- Contar items (productos)
            (
                SELECT COUNT(*)
                FROM (
                    SELECT 1 FROM app_dat_extraccion_productos exy WHERE exy.id_operacion = o.id
                    UNION ALL
                    SELECT 1 FROM app_dat_recepcion_productos rxy WHERE rxy.id_operacion = o.id
                    UNION ALL
                    SELECT 1 FROM app_dat_inventario_productos invp WHERE invp.id_control = o.id
                ) AS items
            ) AS cantidad_items,
            -- Total de la operación (si aplica)
            (
                SELECT COALESCE(SUM(exp.importe), 0)
                FROM app_dat_extraccion_productos exp
                WHERE exp.id_operacion = o.id
            ) AS total_venta,
            (
                SELECT COALESCE(SUM(recp.importe), 0)
                FROM app_dat_recepcion_productos recp
                WHERE recp.id_operacion = o.id
            ) AS total_recepcion
        FROM public.app_dat_operaciones o
        INNER JOIN public.app_nom_tipo_operacion top ON o.id_tipo_operacion = top.id
        INNER JOIN public.app_dat_tienda t ON o.id_tienda = t.id
        -- Último estado
        INNER JOIN (
            SELECT e1.id_operacion, e1.estado
            FROM public.app_dat_estado_operacion e1
            WHERE e1.created_at = (
                SELECT MAX(e2.created_at)
                FROM app_dat_estado_operacion e2
                WHERE e2.id_operacion = e1.id_operacion
            )
        ) e ON o.id = e.id_operacion
        -- ✅ JOIN con catálogo de estados
        INNER JOIN public.app_nom_estado_operacion neo ON e.estado = neo.id
        WHERE 1 = 1
            AND (p_id_tienda IS NULL OR o.id_tienda = p_id_tienda)
            AND (p_id_tpv IS NULL OR EXISTS (
                SELECT 1 FROM app_dat_operacion_venta ov2 WHERE ov2.id_operacion = o.id AND ov2.id_tpv = p_id_tpv
            ))
            AND (p_id_tipo_operacion IS NULL OR o.id_tipo_operacion = p_id_tipo_operacion)
            AND (p_estados IS NULL OR e.estado = ANY(p_estados))
            AND (p_fecha_desde IS NULL OR o.created_at::DATE >= p_fecha_desde)
            AND (p_fecha_hasta IS NULL OR o.created_at::DATE <= p_fecha_hasta)
            AND (p_uuid_usuario_operador IS NULL OR o.uuid = p_uuid_usuario_operador)
            AND (
                p_busqueda IS NULL OR
                top.denominacion ILIKE '%' || p_busqueda || '%' OR
                t.denominacion ILIKE '%' || p_busqueda || '%' OR
                o.observaciones ILIKE '%' || p_busqueda || '%'
            )
            -- Validar acceso
            AND EXISTS (
                SELECT 1 FROM (
                    SELECT g.id_tienda FROM app_dat_gerente g WHERE g.uuid = auth.uid()
                    UNION
                    SELECT s.id_tienda FROM app_dat_supervisor s WHERE s.uuid = auth.uid()
                    UNION
                    SELECT a.id_tienda FROM app_dat_almacenero al JOIN app_dat_almacen a ON al.id_almacen = a.id WHERE al.uuid = auth.uid()
                    UNION
                    SELECT tpv.id_tienda FROM app_dat_vendedor v JOIN app_dat_tpv tpv ON v.id_tpv = tpv.id WHERE v.uuid = auth.uid()
                ) accesos
                WHERE accesos.id_tienda = o.id_tienda
            )
    )
    SELECT
        o.id::BIGINT,
        o.tipo_operacion_nombre::TEXT,
        o.id_tienda::BIGINT,
        o.tienda_nombre::TEXT,
        COALESCE((o.datos_especificos->>'id_tpv')::BIGINT, NULL)::BIGINT,
        COALESCE((o.datos_especificos->>'tpv_nombre')::TEXT, NULL)::TEXT,
        o.uuid::UUID,
        COALESCE(
            (SELECT t.nombres || ' ' || t.apellidos FROM app_dat_trabajadores t WHERE t.uuid = o.uuid),
            o.usuario_email
        )::TEXT,
        o.estado::SMALLINT,
        o.estado_nombre::TEXT,
        o.created_at::TIMESTAMPTZ,
        COALESCE(o.total_venta, o.total_recepcion, 0)::NUMERIC,
        o.cantidad_items::INTEGER,
        o.observaciones::TEXT,
        jsonb_build_object(
            'detalles_especificos', o.datos_especificos,
            'items', (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'id_producto', COALESCE(ep.id_producto, rp.id_producto),
                        'producto_nombre', COALESCE(p.denominacion, 'Producto no encontrado'),
                        'cantidad', COALESCE(ep.cantidad, rp.cantidad),
                        'precio_unitario', COALESCE(ep.precio_unitario, rp.precio_unitario),
                        'importe', COALESCE(ep.importe, rp.importe),
                        'presentacion', np.denominacion,
                        'variante', v.denominacion,
                        'opcion_variante', vo.denominacion
                    )
                )
                FROM (
                    SELECT 'extraccion' as tipo, ext.id_producto, ext.id_variante, ext.id_opcion_variante, ext.id_presentacion, ext.cantidad, ext.precio_unitario, ext.importe 
                    FROM app_dat_extraccion_productos ext WHERE ext.id_operacion = o.id
                    UNION ALL
                    SELECT 'recepcion', rep.id_producto, rep.id_variante, rep.id_opcion_variante, rep.id_presentacion, rep.cantidad, rep.precio_unitario, rep.importe 
                    FROM app_dat_recepcion_productos rep WHERE rep.id_operacion = o.id
                ) AS items(tipo, id_producto, id_variante, id_opcion_variante, id_presentacion, cantidad, precio_unitario, importe)
                LEFT JOIN app_dat_extraccion_productos ep ON items.tipo = 'extraccion' AND ep.id_operacion = o.id AND ep.id_producto = items.id_producto
                LEFT JOIN app_dat_recepcion_productos rp ON items.tipo = 'recepcion' AND rp.id_operacion = o.id AND rp.id_producto = items.id_producto
                LEFT JOIN app_dat_producto p ON items.id_producto = p.id
                LEFT JOIN app_dat_producto_presentacion np ON items.id_presentacion = np.id
                LEFT JOIN app_dat_variantes v ON items.id_variante = v.id
                LEFT JOIN app_dat_atributo_opcion vo ON items.id_opcion_variante = vo.id
                LIMIT 100 -- Evitar sobrecarga
            )
        ) AS detalles,
        v_total_count::BIGINT
    FROM operaciones_filtradas o
    ORDER BY o.created_at DESC
    LIMIT p_limite
    OFFSET v_offset;
END;
$$;
