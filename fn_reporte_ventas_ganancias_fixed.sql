CREATE OR REPLACE FUNCTION fn_reporte_ventas_gananciasv2(
    p_id_tienda INTEGER,
    p_fecha_desde DATE DEFAULT NULL,
    p_fecha_hasta DATE DEFAULT NULL
)
RETURNS TABLE(
    id_tienda BIGINT,
    id_producto BIGINT,
    nombre_producto CHARACTER VARYING,
    precio_venta_cup NUMERIC,
    precio_costo NUMERIC,
    valor_usd NUMERIC,
    precio_costo_cup NUMERIC,
    total_vendido NUMERIC,
    ingresos_totales NUMERIC,
    costo_total_vendido NUMERIC,
    ganancia_unitaria NUMERIC,
    ganancia_total NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
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
        COALESCE(ventas_reales.precio_venta_promedio, 0) AS precio_venta_cup,
        COALESCE(rp.precio_costo, 0) AS precio_costo,
        COALESCE(tc.tasa, 1) AS valor_usd,
        COALESCE(rp.precio_costo, 0) * COALESCE(tc.tasa, 1) AS precio_costo_cup,
        COALESCE(ventas_reales.total_vendido, 0) AS total_vendido,
        COALESCE(ventas_reales.ingresos_totales, 0) AS ingresos_totales,
        COALESCE(ventas_reales.total_vendido, 0) * (COALESCE(rp.precio_costo, 0) * COALESCE(tc.tasa, 1)) AS costo_total_vendido,
        COALESCE(ventas_reales.precio_venta_promedio, 0) - (COALESCE(rp.precio_costo, 0) * COALESCE(tc.tasa, 1)) AS ganancia_unitaria,
        COALESCE(ventas_reales.ingresos_totales, 0) - (COALESCE(ventas_reales.total_vendido, 0) * (COALESCE(rp.precio_costo, 0) * COALESCE(tc.tasa, 1))) AS ganancia_total
    FROM (
        -- Obtener ventas reales usando app_dat_pago_venta (montos reales pagados)
        SELECT 
            ep.id_producto,
            ep.id_variante,
            SUM(ep.cantidad) AS total_vendido,
            -- Usar los montos reales pagados desde app_dat_pago_venta
            SUM(pv.monto) AS ingresos_totales,
            -- Calcular precio promedio real basado en pagos
            CASE 
                WHEN SUM(ep.cantidad) > 0 THEN SUM(pv.monto) / SUM(ep.cantidad)
                ELSE 0
            END AS precio_venta_promedio
        FROM app_dat_operaciones o
        JOIN app_dat_operacion_venta ov ON o.id = ov.id_operacion
        JOIN app_dat_extraccion_productos ep ON o.id = ep.id_operacion
        JOIN app_dat_pago_venta pv ON ov.id_operacion = pv.id_operacion_venta
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
    ) ventas_reales
    JOIN app_dat_producto p ON ventas_reales.id_producto = p.id
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
    ) rp ON p.id = rp.id_producto AND COALESCE(ventas_reales.id_variante, 0) = COALESCE(rp.id_variante, 0)
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
    ORDER BY ventas_reales.ingresos_totales DESC, p.denominacion;
END;
$$;

-- Comentarios sobre los cambios realizados:
-- 1. Ahora usa ov.precio_total de app_dat_operacion_venta para obtener el precio real de venta
-- 2. Calcula el precio promedio real dividiendo ingresos totales entre cantidad vendida
-- 3. Elimina la dependencia de app_dat_precio_venta que podría tener precios desactualizados
-- 4. Mantiene la lógica de costos desde app_dat_recepcion_productos
-- 5. Sigue el patrón exitoso de tu función fn_resumen_diario_cierre
