DECLARE
    v_fecha_inicio_filtro timestamptz;
    v_fecha_fin_filtro timestamptz;
    v_id_tpv bigint;
BEGIN
    -- Si NO se pasan fechas, usamos el turno abierto del vendedor
    IF p_fecha_desde IS NULL AND p_fecha_hasta IS NULL AND p_uuid_usuario IS NOT NULL THEN
        -- Obtener el TPV del vendedor
        SELECT v.id_tpv
        INTO v_id_tpv
        FROM app_dat_vendedor v
        WHERE v.uuid = p_uuid_usuario;

        IF v_id_tpv IS NULL THEN
            -- El usuario no es vendedor
            RETURN;
        END IF;

        -- Obtener el turno abierto en ese TPV
        SELECT ct.fecha_apertura
        INTO v_fecha_inicio_filtro
        FROM app_dat_caja_turno ct
        WHERE ct.id_tpv = v_id_tpv
          AND ct.estado = 1  -- Abierto
          AND ct.id_vendedor IN (SELECT id FROM app_dat_vendedor WHERE uuid = p_uuid_usuario)
        ORDER BY ct.fecha_apertura DESC
        LIMIT 1;

        -- Si hay turno abierto, filtramos desde su apertura hasta ahora
        IF v_fecha_inicio_filtro IS NOT NULL THEN
            v_fecha_fin_filtro := NOW();
        ELSE
            -- No hay turno abierto → no devolver datos
            RETURN;
        END IF;
    ELSE
        -- Si se pasan fechas, usamos ese rango
        v_fecha_inicio_filtro := p_fecha_desde;
        v_fecha_fin_filtro := COALESCE(p_fecha_hasta, CURRENT_DATE) + INTERVAL '1 day' - INTERVAL '1 second';
    END IF;

    -- Aseguramos que el inicio tenga hora completa si es date
    IF v_fecha_inicio_filtro::date = v_fecha_inicio_filtro THEN
        v_fecha_inicio_filtro := v_fecha_inicio_filtro AT TIME ZONE 'UTC';
    END IF;

    RETURN QUERY
    SELECT 
        o.uuid AS uuid_usuario,
        t.nombres,
        t.apellidos,
        (t.nombres || ' ' || t.apellidos)::VARCHAR AS nombre_completo,
        COUNT(DISTINCT o.id) AS total_ventas,
        COALESCE(SUM(ep.cantidad), 0) AS total_productos_vendidos,
        -- Efectivo: usando la misma lógica que la segunda función
        COALESCE(SUM(CASE WHEN pv.id_medio_pago = 1 THEN pv.monto ELSE 0 END), 0) AS total_dinero_efectivo,
        -- No efectivo: todos los otros medios de pago
        COALESCE(SUM(CASE WHEN pv.id_medio_pago != 1 THEN pv.monto ELSE 0 END), 0) AS total_dinero_transferencia,
        COALESCE(SUM(pv.monto), 0) AS total_dinero_general,
        -- Usar el importe de extracción en lugar de operacion_venta para consistencia
        COALESCE(SUM(ep.importe), 0) AS total_importe_ventas,
        COUNT(DISTINCT ep.id_producto) AS productos_diferentes_vendidos,
        MIN(o.created_at) AS primera_venta,
        MAX(o.created_at) AS ultima_venta
    FROM 
        app_dat_operaciones o
        INNER JOIN app_dat_operacion_venta ov ON o.id = ov.id_operacion
        INNER JOIN app_dat_extraccion_productos ep ON o.id = ep.id_operacion
        INNER JOIN app_dat_estado_operacion eo ON o.id = eo.id_operacion
        INNER JOIN app_dat_vendedor v ON o.uuid = v.uuid
        INNER JOIN app_dat_trabajadores t ON v.id_trabajador = t.id
        LEFT JOIN app_dat_pago_venta pv ON ov.id_operacion = pv.id_operacion_venta
    WHERE 
        o.id_tipo_operacion = (SELECT id FROM app_nom_tipo_operacion WHERE LOWER(denominacion) = 'venta')
        -- Usar el estado más reciente de cada operación (como en la segunda función)
        AND eo.estado = 2  -- Solo operaciones completadas
        AND eo.id = (SELECT MAX(id) FROM app_dat_estado_operacion WHERE id_operacion = o.id)
        AND ov.es_pagada = true  -- Venta pagada
        AND o.uuid IS NOT NULL
        AND (p_uuid_usuario IS NULL OR o.uuid = p_uuid_usuario)
        -- Filtrar por TPV específico si tenemos uno (crítico para datos correctos)
        AND (v_id_tpv IS NULL OR ov.id_tpv = v_id_tpv)
        AND o.created_at >= v_fecha_inicio_filtro
        AND (v_fecha_fin_filtro IS NULL OR o.created_at <= v_fecha_fin_filtro)
        AND (p_id_tienda IS NULL OR o.id_tienda = p_id_tienda)
    GROUP BY 
        o.uuid, 
        t.nombres, 
        t.apellidos
    ORDER BY 
        total_dinero_general DESC, 
        total_ventas DESC;
END;
