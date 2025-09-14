BEGIN
    -- Establecer contexto
    SET search_path = public;
    
    -- Verificar permisos
    PERFORM check_user_has_access_to_tienda(p_id_tienda);
    
    RETURN QUERY
    SELECT 
        p.id_tienda,
        p.id AS id_producto,
        p.denominacion AS nombre_producto,
        COALESCE(pv.precio_venta_cup, ep_avg.precio_promedio, 0) AS precio_venta_cup,
        COALESCE(rp.precio_costo, 0) AS precio_costo,
        COALESCE(tc.tasa, 1) AS valor_usd,
        COALESCE(rp.precio_costo, 0) * COALESCE(tc.tasa, 1) AS precio_costo_cup,
        COALESCE(ventas.total_vendido, 0) AS total_vendido,
        COALESCE(ventas.ingresos_totales, 0) AS ingresos_totales,
        COALESCE(ventas.total_vendido, 0) * (COALESCE(rp.precio_costo, 0) * COALESCE(tc.tasa, 1)) AS costo_total_vendido,
        COALESCE(pv.precio_venta_cup, ep_avg.precio_promedio, 0) - (COALESCE(rp.precio_costo, 0) * COALESCE(tc.tasa, 1)) AS ganancia_unitaria,
        COALESCE(ventas.ingresos_totales, 0) - (COALESCE(ventas.total_vendido, 0) * (COALESCE(rp.precio_costo, 0) * COALESCE(tc.tasa, 1))) AS ganancia_total
    FROM (
        -- USAR LA MISMA LÓGICA EXITOSA: Obtener ventas por producto
        SELECT 
            ep.id_producto,
            ep.id_variante,
            SUM(ep.cantidad) AS total_vendido,
            SUM(ep.importe) AS ingresos_totales,
            AVG(ep.precio_unitario) AS precio_promedio
        FROM app_dat_operaciones o
        JOIN app_dat_operacion_venta ov ON o.id = ov.id_operacion
        JOIN app_dat_extraccion_productos ep ON o.id = ep.id_operacion
        JOIN app_dat_estado_operacion eo ON o.id = eo.id_operacion
        WHERE o.id_tienda = p_id_tienda
          AND eo.estado = 2 -- Solo operaciones completadas
          AND eo.id = (SELECT MAX(id) FROM app_dat_estado_operacion WHERE id_operacion = o.id)
          AND ov.es_pagada = true -- Solo ventas pagadas
          AND o.id_tipo_operacion = (SELECT id FROM app_nom_tipo_operacion WHERE LOWER(denominacion) = 'venta')
          AND (p_fecha_desde IS NULL OR o.created_at::DATE >= p_fecha_desde)
          AND (p_fecha_hasta IS NULL OR o.created_at::DATE <= p_fecha_hasta)
        GROUP BY ep.id_producto, ep.id_variante
        HAVING SUM(ep.cantidad) > 0
    ) ventas
    JOIN app_dat_producto p ON ventas.id_producto = p.id
    LEFT JOIN (
        -- Precio promedio de ventas como respaldo
        SELECT 
            ep.id_producto,
            ep.id_variante,
            AVG(ep.precio_unitario) AS precio_promedio
        FROM app_dat_operaciones o
        JOIN app_dat_operacion_venta ov ON o.id = ov.id_operacion
        JOIN app_dat_extraccion_productos ep ON o.id = ep.id_operacion
        JOIN app_dat_estado_operacion eo ON o.id = eo.id_operacion
        WHERE o.id_tienda = p_id_tienda
          AND eo.estado = 2
          AND eo.id = (SELECT MAX(id) FROM app_dat_estado_operacion WHERE id_operacion = o.id)
        GROUP BY ep.id_producto, ep.id_variante
    ) ep_avg ON p.id = ep_avg.id_producto AND COALESCE(ventas.id_variante, 0) = COALESCE(ep_avg.id_variante, 0)
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
    ) pv ON p.id = pv.id_producto AND COALESCE(ventas.id_variante, 0) = COALESCE(pv.id_variante, 0)
    LEFT JOIN (
        -- Obtener el costo más reciente de recepción para cada producto
        SELECT DISTINCT ON (rp.id_producto, COALESCE(rp.id_variante, 0))
            rp.id_producto,
            rp.id_variante,
            COALESCE(rp.costo_real, rp.precio_unitario, 0) AS precio_costo
        FROM app_dat_recepcion_productos rp
        INNER JOIN app_dat_operaciones o ON rp.id_operacion = o.id
        WHERE o.id_tienda = p_id_tienda
        ORDER BY rp.id_producto, COALESCE(rp.id_variante, 0), o.created_at DESC
    ) rp ON p.id = rp.id_producto AND COALESCE(ventas.id_variante, 0) = COALESCE(rp.id_variante, 0)
    LEFT JOIN (
        -- Obtener la tasa de cambio USD más reciente
        SELECT 
            tasa
        FROM tasas_conversion 
        WHERE moneda_origen = 'USD' AND moneda_destino = 'CUP'
        ORDER BY fecha_actualizacion DESC
        LIMIT 1
    ) tc ON true
    WHERE p.id_tienda = p_id_tienda
    ORDER BY ventas.ingresos_totales DESC, p.denominacion;
END;
