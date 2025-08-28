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
            neo.denominacion AS estado_nombre,
            o.observaciones,
            -- Datos específicos por tipo de operación
            CASE
                WHEN o.id_tipo_operacion = (SELECT top_sub.id FROM app_nom_tipo_operacion top_sub WHERE top_sub.denominacion = 'Venta') THEN
                    (SELECT jsonb_build_object(
                        'id_tpv', tpv.id,
                        'tpv_nombre', tpv.denominacion,
                        'total', ov_inner.importe_total,
                        'cantidad_items', COUNT(ep_inner.id)
                    )
                    FROM app_dat_operacion_venta ov_inner
                    JOIN app_dat_tpv tpv ON ov_inner.id_tpv = tpv.id
                    LEFT JOIN app_dat_extraccion_productos ep_inner ON ov_inner.id_operacion = ep_inner.id_operacion
                    WHERE ov_inner.id_operacion = o.id
                    GROUP BY tpv.id, tpv.denominacion, ov_inner.importe_total)
                WHEN o.id_tipo_operacion = (SELECT top_sub.id FROM app_nom_tipo_operacion top_sub WHERE top_sub.denominacion ILIKE '%recepcion%') THEN
                    (SELECT jsonb_build_object(
                        'entregado_por', orp_inner.entregado_por,
                        'recibido_por', orp_inner.recibido_por,
                        'monto_total', orp_inner.monto_total,
                        'cantidad_items', COUNT(rp_inner.id)
                    )
                    FROM app_dat_operacion_recepcion orp_inner
                    LEFT JOIN app_dat_recepcion_productos rp_inner ON orp_inner.id_operacion = rp_inner.id_operacion
                    WHERE orp_inner.id_operacion = o.id
                    GROUP BY orp_inner.entregado_por, orp_inner.recibido_por, orp_inner.monto_total)
                WHEN o.id_tipo_operacion = (SELECT top_sub.id FROM app_nom_tipo_operacion top_sub WHERE top_sub.denominacion ILIKE '%extraccion%') THEN
                    (SELECT jsonb_build_object(
                        'motivo', oe_inner.id_motivo_operacion,
                        'observaciones', oe_inner.observaciones,
                        'cantidad_items', COUNT(ep_inner.id)
                    )
                    FROM app_dat_operacion_extraccion oe_inner
                    LEFT JOIN app_dat_extraccion_productos ep_inner ON oe_inner.id_operacion = ep_inner.id_operacion
                    WHERE oe_inner.id_operacion = o.id
                    GROUP BY oe_inner.id_motivo_operacion, oe_inner.observaciones)
                WHEN o.id_tipo_operacion = (SELECT top_sub.id FROM app_nom_tipo_operacion top_sub WHERE top_sub.denominacion ILIKE '%transferencia%') THEN
                    (SELECT jsonb_build_object(
                        'autorizado_por', ot_inner.autorizado_por,
                        'id_recepcion', ot_inner.id_recepcion,
                        'id_extraccion', ot_inner.id_extraccion,
                        'cantidad_items', COUNT(ep_inner.id)
                    )
                    FROM app_dat_operacion_transferencia ot_inner
                    LEFT JOIN app_dat_extraccion_productos ep_inner ON ot_inner.id_extraccion = ep_inner.id_operacion
                    WHERE ot_inner.id_operacion = o.id
                    GROUP BY ot_inner.autorizado_por, ot_inner.id_recepcion, ot_inner.id_extraccion)
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
                SELECT COALESCE(SUM(recp.precio_unitario * recp.cantidad), 0)
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
            (SELECT tr.nombres || ' ' || tr.apellidos 
             FROM app_dat_trabajadores tr 
             WHERE tr.id = (
                 SELECT v.id_trabajador FROM app_dat_vendedor v WHERE v.uuid = o.uuid
                 UNION
                 SELECT s.id_trabajador FROM app_dat_supervisor s WHERE s.uuid = o.uuid
                 UNION
                 SELECT g.id_trabajador FROM app_dat_gerente g WHERE g.uuid = o.uuid
                 UNION
                 SELECT al.id_trabajador FROM app_dat_almacenero al WHERE al.uuid = o.uuid
                 LIMIT 1
             )),
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
                        'id_producto', items.id_producto,
                        'producto_nombre', COALESCE(p.denominacion, 'Producto no encontrado'),
                        'cantidad', items.cantidad,
                        'precio_unitario', items.precio_unitario,
                        'importe', COALESCE(items.importe, items.precio_unitario * items.cantidad),
                        'presentacion', np.denominacion,
                        'variante', attr.denominacion,
                        'opcion_variante', ao.valor
                    )
                )
                FROM (
                    SELECT ext.id_producto, ext.id_variante, ext.id_opcion_variante, ext.id_presentacion, ext.cantidad, ext.precio_unitario, ext.importe 
                    FROM app_dat_extraccion_productos ext WHERE ext.id_operacion = o.id
                    UNION ALL
                    SELECT rep.id_producto, rep.id_variante, rep.id_opcion_variante, rep.id_presentacion, rep.cantidad, rep.precio_unitario, NULL as importe
                    FROM app_dat_recepcion_productos rep WHERE rep.id_operacion = o.id
                ) AS items
                LEFT JOIN app_dat_producto p ON items.id_producto = p.id
                LEFT JOIN app_dat_producto_presentacion pp ON items.id_presentacion = pp.id
                LEFT JOIN app_nom_presentacion np ON pp.id_presentacion = np.id
                LEFT JOIN app_dat_variantes v ON items.id_variante = v.id
                LEFT JOIN app_dat_atributos attr ON v.id_atributo = attr.id
                LEFT JOIN app_dat_atributo_opcion ao ON items.id_opcion_variante = ao.id
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
