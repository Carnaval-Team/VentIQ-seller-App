CREATE OR REPLACE FUNCTION fn_listar_operaciones_producto_recepcion(
    p_id_tienda BIGINT,
    p_id_tipo_operacion BIGINT,
    p_fecha_desde DATE DEFAULT NULL,
    p_limite INTEGER DEFAULT 5,
    p_pagina INTEGER DEFAULT 1,
    p_id_operacion BIGINT DEFAULT NULL,
    p_busqueda TEXT DEFAULT NULL
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
SET search_path = public
AS $$
DECLARE
    v_offset INTEGER := (p_pagina - 1) * p_limite;
    v_total_count BIGINT;
BEGIN
    -- Validar que el usuario tenga acceso a la tienda
    IF NOT EXISTS (
        SELECT 1 FROM (
            SELECT g.id_tienda FROM app_dat_gerente g WHERE g.uuid = auth.uid()
            UNION
            SELECT s.id_tienda FROM app_dat_supervisor s WHERE s.uuid = auth.uid()
            UNION
            SELECT a.id_tienda FROM app_dat_almacenero al 
            JOIN app_dat_almacen a ON al.id_almacen = a.id 
            WHERE al.uuid = auth.uid()
            UNION
            SELECT tpv.id_tienda FROM app_dat_vendedor v 
            JOIN app_dat_tpv tpv ON v.id_tpv = tpv.id 
            WHERE v.uuid = auth.uid()
        ) accesos
        WHERE accesos.id_tienda = p_id_tienda
    ) THEN
        RAISE EXCEPTION 'No tiene acceso a la tienda especificada';
    END IF;

    -- Contar total de operaciones para paginación
    SELECT COUNT(*) INTO v_total_count
    FROM app_dat_operaciones o
    INNER JOIN app_nom_tipo_operacion top ON o.id_tipo_operacion = top.id
    INNER JOIN app_dat_tienda t ON o.id_tienda = t.id
    INNER JOIN (
        SELECT e1.id_operacion, e1.estado
        FROM app_dat_estado_operacion e1
        WHERE e1.created_at = (
            SELECT MAX(e2.created_at)
            FROM app_dat_estado_operacion e2
            WHERE e2.id_operacion = e1.id_operacion
        )
    ) e ON o.id = e.id_operacion
    INNER JOIN app_nom_estado_operacion neo ON e.estado = neo.id
    WHERE o.id_tienda = p_id_tienda
        AND o.id_tipo_operacion = p_id_tipo_operacion
        AND (p_fecha_desde IS NULL OR o.created_at::DATE >= p_fecha_desde)
        AND (p_id_operacion IS NULL OR o.id = p_id_operacion)
        AND (
            p_busqueda IS NULL OR
            top.denominacion ILIKE '%' || p_busqueda || '%' OR
            t.denominacion ILIKE '%' || p_busqueda || '%' OR
            o.observaciones ILIKE '%' || p_busqueda || '%' OR
            o.id::TEXT ILIKE '%' || p_busqueda || '%'
        );

    -- Retornar operaciones paginadas
    RETURN QUERY
    SELECT
        o.id::BIGINT,
        top.denominacion::TEXT as tipo_operacion_nombre,
        o.id_tienda::BIGINT,
        t.denominacion::TEXT as tienda_nombre,
        NULL::BIGINT as id_tpv,
        NULL::TEXT as tpv_nombre,
        o.uuid::UUID,
        COALESCE(
            (SELECT tr.nombres || ' ' || tr.apellidos FROM app_dat_trabajadores tr WHERE tr.uuid = o.uuid),
            'Sistema'
        )::TEXT as usuario_email,
        e.estado::SMALLINT,
        neo.denominacion::TEXT as estado_nombre,
        o.created_at::TIMESTAMPTZ,
        COALESCE(
            (SELECT SUM(rp.importe) FROM app_dat_recepcion_productos rp WHERE rp.id_operacion = o.id),
            0
        )::NUMERIC as total,
        COALESCE(
            (SELECT COUNT(*) FROM app_dat_recepcion_productos rp WHERE rp.id_operacion = o.id),
            0
        )::INTEGER as cantidad_items,
        o.observaciones::TEXT,
        jsonb_build_object(
            'detalles_especificos', jsonb_build_object(
                'entregado_por', orp.entregado_por,
                'recibido_por', orp.recibido_por,
                'monto_total', orp.monto_total
            ),
            'items', (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'id_producto', rp.id_producto,
                        'producto_nombre', COALESCE(p.denominacion, 'Producto no encontrado'),
                        'cantidad', rp.cantidad,
                        'precio_unitario', rp.precio_unitario,
                        'importe', rp.importe
                    )
                )
                FROM app_dat_recepcion_productos rp
                LEFT JOIN app_dat_producto p ON rp.id_producto = p.id
                WHERE rp.id_operacion = o.id
                LIMIT 10
            )
        ) as detalles,
        v_total_count::BIGINT
    FROM app_dat_operaciones o
    INNER JOIN app_nom_tipo_operacion top ON o.id_tipo_operacion = top.id
    INNER JOIN app_dat_tienda t ON o.id_tienda = t.id
    INNER JOIN (
        SELECT e1.id_operacion, e1.estado
        FROM app_dat_estado_operacion e1
        WHERE e1.created_at = (
            SELECT MAX(e2.created_at)
            FROM app_dat_estado_operacion e2
            WHERE e2.id_operacion = e1.id_operacion
        )
    ) e ON o.id = e.id_operacion
    INNER JOIN app_nom_estado_operacion neo ON e.estado = neo.id
    LEFT JOIN app_dat_operacion_recepcion orp ON o.id = orp.id_operacion
    WHERE o.id_tienda = p_id_tienda
        AND o.id_tipo_operacion = p_id_tipo_operacion
        AND (p_fecha_desde IS NULL OR o.created_at::DATE >= p_fecha_desde)
        AND (p_id_operacion IS NULL OR o.id = p_id_operacion)
        AND (
            p_busqueda IS NULL OR
            top.denominacion ILIKE '%' || p_busqueda || '%' OR
            t.denominacion ILIKE '%' || p_busqueda || '%' OR
            o.observaciones ILIKE '%' || p_busqueda || '%' OR
            o.id::TEXT ILIKE '%' || p_busqueda || '%'
        )
    ORDER BY o.created_at DESC
    LIMIT p_limite
    OFFSET v_offset;
END;
$$;
