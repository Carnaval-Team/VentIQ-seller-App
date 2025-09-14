BEGIN
    -- Debug: Verificar que existen productos en la tienda
    RAISE NOTICE 'Total productos en tienda %: %', p_id_tienda, (SELECT COUNT(*) FROM app_dat_producto WHERE id_tienda = p_id_tienda);
    
    -- Debug: Verificar que existen operaciones de venta
    RAISE NOTICE 'Total operaciones de venta: %', (
        SELECT COUNT(*) 
        FROM app_dat_operaciones o
        INNER JOIN app_dat_operacion_venta ov ON o.id = ov.id_operacion
        WHERE o.id_tienda = p_id_tienda
        AND o.id_tipo_operacion = (SELECT id FROM app_nom_tipo_operacion WHERE LOWER(denominacion) = 'venta')
    );
    
    -- Debug: Verificar operaciones completadas
    RAISE NOTICE 'Operaciones completadas: %', (
        SELECT COUNT(*) 
        FROM app_dat_operaciones o
        INNER JOIN app_dat_operacion_venta ov ON o.id = ov.id_operacion
        INNER JOIN app_dat_estado_operacion eo ON o.id = eo.id_operacion
        WHERE o.id_tienda = p_id_tienda
        AND o.id_tipo_operacion = (SELECT id FROM app_nom_tipo_operacion WHERE LOWER(denominacion) = 'venta')
        AND eo.estado = 2
        AND eo.id = (SELECT MAX(id) FROM app_dat_estado_operacion WHERE id_operacion = o.id)
    );
    
    -- Debug: Verificar extracciones de productos
    RAISE NOTICE 'Extracciones de productos: %', (
        SELECT COUNT(*) 
        FROM app_dat_extraccion_productos ep
        INNER JOIN app_dat_operaciones o ON ep.id_operacion = o.id
        INNER JOIN app_dat_operacion_venta ov ON o.id = ov.id_operacion
        INNER JOIN app_dat_estado_operacion eo ON o.id = eo.id_operacion
        WHERE o.id_tienda = p_id_tienda
        AND o.id_tipo_operacion = (SELECT id FROM app_nom_tipo_operacion WHERE LOWER(denominacion) = 'venta')
        AND eo.estado = 2
        AND eo.id = (SELECT MAX(id) FROM app_dat_estado_operacion WHERE id_operacion = o.id)
        AND ov.es_pagada = true
    );

    RETURN QUERY
    SELECT 
        p.id_tienda,
        p.id AS id_producto,
        p.denominacion AS nombre_producto,
        COALESCE(pv.precio_venta_cup, 0) AS precio_venta_cup,
        COALESCE(rp.costo_real, rp.precio_unitario, 0) AS precio_costo,
        COALESCE(tc.tasa, 1) AS valor_usd,
        COALESCE(rp.costo_real, rp.precio_unitario, 0) * COALESCE(tc.tasa, 1) AS precio_costo_cup,
        COALESCE(ventas.total_vendido, 0) AS total_vendido,
        COALESCE(ventas.ingresos_totales, 0) AS ingresos_totales,
        COALESCE(ventas.total_vendido, 0) * (COALESCE(rp.costo_real, rp.precio_unitario, 0) * COALESCE(tc.tasa, 1)) AS costo_total_vendido,
        COALESCE(pv.precio_venta_cup, 0) - (COALESCE(rp.costo_real, rp.precio_unitario, 0) * COALESCE(tc.tasa, 1)) AS ganancia_unitaria,
        COALESCE(ventas.ingresos_totales, 0) - (COALESCE(ventas.total_vendido, 0) * (COALESCE(rp.costo_real, rp.precio_unitario, 0) * COALESCE(tc.tasa, 1))) AS ganancia_total
    FROM 
        app_dat_producto p
    -- CAMBIO: Hacer LEFT JOIN en lugar de INNER JOIN para ver todos los productos
    LEFT JOIN (
        -- Obtener el costo más reciente de recepción para cada producto
        SELECT DISTINCT ON (rp.id_producto, COALESCE(rp.id_variante, 0))
            rp.id_producto,
            rp.id_variante,
            rp.precio_unitario,
            rp.costo_real
        FROM app_dat_recepcion_productos rp
        INNER JOIN app_dat_operaciones o ON rp.id_operacion = o.id
        WHERE 
            (p_fecha_desde IS NULL OR o.created_at >= p_fecha_desde)
            AND (p_fecha_hasta IS NULL OR o.created_at <= p_fecha_hasta)
        ORDER BY rp.id_producto, COALESCE(rp.id_variante, 0), o.created_at DESC
    ) rp ON p.id = rp.id_producto
    LEFT JOIN (
        -- Obtener el precio de venta más reciente para cada producto
        SELECT DISTINCT ON (ven.id_producto, COALESCE(ven.id_variante, 0)) 
            ven.id_producto,
            ven.id_variante,
            ven.precio_venta_cup
        FROM app_dat_precio_venta ven
        WHERE (fecha_hasta IS NULL OR fecha_hasta >= CURRENT_DATE)
            AND fecha_desde <= CURRENT_DATE
        ORDER BY ven.id_producto, COALESCE(ven.id_variante, 0), created_at DESC
    ) pv ON p.id = pv.id_producto AND COALESCE(pv.id_variante, 0) = COALESCE(rp.id_variante, 0)
    LEFT JOIN (
        -- Obtener totales de ventas por producto
        SELECT 
            ep.id_producto,
            COALESCE(ep.id_variante, 0) as id_variante,
            SUM(ep.cantidad) AS total_vendido,
            SUM(ep.importe) AS ingresos_totales
        FROM app_dat_extraccion_productos ep
        INNER JOIN app_dat_operaciones o ON ep.id_operacion = o.id
        INNER JOIN app_dat_operacion_venta ov ON o.id = ov.id_operacion
        INNER JOIN app_dat_estado_operacion eo ON o.id = eo.id_operacion
        WHERE 
            eo.estado = 2  -- Solo operaciones completadas
            AND eo.id = (SELECT MAX(id) FROM app_dat_estado_operacion WHERE id_operacion = o.id)
            AND ov.es_pagada = true  -- Solo ventas pagadas
            AND o.id_tienda = p_id_tienda
            AND o.id_tipo_operacion = (SELECT id FROM app_nom_tipo_operacion WHERE LOWER(denominacion) = 'venta')
            AND (p_fecha_desde IS NULL OR o.created_at >= p_fecha_desde)
            AND (p_fecha_hasta IS NULL OR o.created_at <= p_fecha_hasta)
        GROUP BY ep.id_producto, COALESCE(ep.id_variante, 0)
    ) ventas ON p.id = ventas.id_producto AND COALESCE(rp.id_variante, 0) = ventas.id_variante
    LEFT JOIN (
        -- Obtener la tasa de cambio USD más reciente
        SELECT 
            tasa
        FROM tasas_conversion 
        WHERE moneda_origen = 'USD' AND moneda_destino = 'CUP'
        ORDER BY fecha_actualizacion DESC
        LIMIT 1
    ) tc ON true
    WHERE 
        p.id_tienda = p_id_tienda
        -- CAMBIO: Mostrar todos los productos, no solo los que tienen costo
        -- AND (rp.costo_real IS NOT NULL OR rp.precio_unitario IS NOT NULL)
        -- CAMBIO: Mostrar todos los productos, no solo los que tienen ventas
        -- AND ventas.total_vendido > 0
    ORDER BY COALESCE(ventas.ingresos_totales, 0) DESC, p.denominacion;
END;
