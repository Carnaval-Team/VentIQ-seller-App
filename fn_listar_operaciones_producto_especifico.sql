CREATE OR REPLACE FUNCTION fn_listar_operaciones_producto_especifico(
    p_id_producto BIGINT,
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
    uuid UUID,
    usuario_email TEXT,
    estado SMALLINT,
    estado_nombre TEXT,
    created_at TIMESTAMPTZ,
    cantidad_producto NUMERIC,
    precio_unitario NUMERIC,
    importe_producto NUMERIC,
    proveedor TEXT,
    documento TEXT,
    observaciones TEXT,
    total_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_offset INTEGER := (p_pagina - 1) * p_limite;
    v_total_count BIGINT;
    v_id_tienda BIGINT;
BEGIN
    -- Obtener la tienda del producto y validar acceso del usuario
    SELECT p.id_tienda INTO v_id_tienda
    FROM app_dat_producto p
    WHERE p.id = p_id_producto;
    
    IF v_id_tienda IS NULL THEN
        RAISE EXCEPTION 'Producto no encontrado';
    END IF;

    -- Validar que el usuario tenga acceso a la tienda del producto
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
        WHERE accesos.id_tienda = v_id_tienda
    ) THEN
        RAISE EXCEPTION 'No tiene acceso a la tienda del producto especificado';
    END IF;

    -- Contar total de operaciones para paginación
    SELECT COUNT(*) INTO v_total_count
    FROM app_dat_operaciones o
    INNER JOIN app_nom_tipo_operacion top ON o.id_tipo_operacion = top.id
    INNER JOIN app_dat_recepcion_productos rp ON o.id = rp.id_operacion
    INNER JOIN (
        SELECT e1.id_operacion, e1.estado
        FROM app_dat_estado_operacion e1
        WHERE e1.created_at = (
            SELECT MAX(e2.created_at)
            FROM app_dat_estado_operacion e2
            WHERE e2.id_operacion = e1.id_operacion
        )
    ) e ON o.id = e.id_operacion
    WHERE rp.id_producto = p_id_producto
        AND top.denominacion ILIKE '%recepcion%'
        AND (p_id_operacion IS NULL OR o.id = p_id_operacion)
        AND (
            p_busqueda IS NULL OR
            top.denominacion ILIKE '%' || p_busqueda || '%' OR
            o.observaciones ILIKE '%' || p_busqueda || '%' OR
            o.id::TEXT ILIKE '%' || p_busqueda || '%'
        );

    -- Retornar operaciones paginadas filtradas por producto
    RETURN QUERY
    SELECT
        o.id::BIGINT,
        top.denominacion::TEXT as tipo_operacion_nombre,
        o.id_tienda::BIGINT,
        t.denominacion::TEXT as tienda_nombre,
        o.uuid::UUID,
        COALESCE(
            (SELECT tr.nombres || ' ' || tr.apellidos FROM app_dat_trabajadores tr WHERE tr.uuid = o.uuid),
            'Sistema'
        )::TEXT as usuario_email,
        e.estado::SMALLINT,
        neo.denominacion::TEXT as estado_nombre,
        o.created_at::TIMESTAMPTZ,
        rp.cantidad::NUMERIC as cantidad_producto,
        rp.precio_unitario::NUMERIC,
        (rp.cantidad * rp.precio_unitario)::NUMERIC as importe_producto,
        COALESCE(orp.entregado_por, 'No especificado')::TEXT as proveedor,
        ('OP-' || o.id::TEXT)::TEXT as documento,
        o.observaciones::TEXT,
        v_total_count::BIGINT
    FROM app_dat_operaciones o
    INNER JOIN app_nom_tipo_operacion top ON o.id_tipo_operacion = top.id
    INNER JOIN app_dat_tienda t ON o.id_tienda = t.id
    INNER JOIN app_dat_recepcion_productos rp ON o.id = rp.id_operacion
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
    WHERE rp.id_producto = p_id_producto
        AND top.denominacion ILIKE '%recepcion%'
        AND (p_id_operacion IS NULL OR o.id = p_id_operacion)
        AND (
            p_busqueda IS NULL OR
            top.denominacion ILIKE '%' || p_busqueda || '%' OR
            o.observaciones ILIKE '%' || p_busqueda || '%' OR
            o.id::TEXT ILIKE '%' || p_busqueda || '%'
        )
    ORDER BY o.created_at DESC
    LIMIT p_limite
    OFFSET v_offset;
END;
$$;
