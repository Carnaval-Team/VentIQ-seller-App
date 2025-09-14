CREATE OR REPLACE FUNCTION fn_reporte_ventas_ganancias_simple(
    p_id_tienda INTEGER,
    p_fecha_desde DATE DEFAULT NULL,
    p_fecha_hasta DATE DEFAULT NULL
)
RETURNS TABLE (
    id_tienda INTEGER,
    id_producto INTEGER,
    nombre_producto TEXT,
    precio_venta_cup NUMERIC,
    precio_costo NUMERIC,
    valor_usd NUMERIC,
    precio_costo_cup NUMERIC,
    total_vendido NUMERIC,
    ingreso_total NUMERIC,
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
    WITH ventas_productos AS (
        -- Obtener ventas por producto usando la misma lógica exitosa
        SELECT 
            ep.id_producto,
            ep.id_variante,
            SUM(ep.cantidad) AS total_vendido,
            SUM(ep.importe) AS ingreso_total,
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
    ),
    precios_productos AS (
        -- Obtener precios de venta actuales
        SELECT DISTINCT ON (pv.id_producto, COALESCE(pv.id_variante, 0))
            pv.id_producto,
            pv.id_variante,
            pv.precio_venta_cup
        FROM app_dat_precio_venta pv
        WHERE (pv.fecha_hasta IS NULL OR pv.fecha_hasta >= CURRENT_DATE)
          AND pv.fecha_desde <= CURRENT_DATE
        ORDER BY pv.id_producto, COALESCE(pv.id_variante, 0), pv.created_at DESC
    ),
    costos_productos AS (
        -- Obtener costos más recientes de recepción
        SELECT DISTINCT ON (rp.id_producto, COALESCE(rp.id_variante, 0))
            rp.id_producto,
            rp.id_variante,
            COALESCE(rp.costo_real, rp.precio_unitario, 0) AS precio_costo
        FROM app_dat_recepcion_productos rp
        INNER JOIN app_dat_operaciones o ON rp.id_operacion = o.id
        WHERE o.id_tienda = p_id_tienda
        ORDER BY rp.id_producto, COALESCE(rp.id_variante, 0), o.created_at DESC
    ),
    tasa_cambio AS (
        -- Obtener tasa de cambio USD más reciente
        SELECT COALESCE(tasa, 1) AS valor_usd
        FROM tasas_conversion 
        WHERE moneda_origen = 'USD' AND moneda_destino = 'CUP'
        ORDER BY fecha_actualizacion DESC
        LIMIT 1
    )
    SELECT 
        p.id_tienda,
        p.id AS id_producto,
        p.denominacion AS nombre_producto,
        COALESCE(pp.precio_venta_cup, vp.precio_promedio, 0) AS precio_venta_cup,
        COALESCE(cp.precio_costo, 0) AS precio_costo,
        COALESCE(tc.valor_usd, 1) AS valor_usd,
        COALESCE(cp.precio_costo, 0) * COALESCE(tc.valor_usd, 1) AS precio_costo_cup,
        vp.total_vendido,
        vp.ingreso_total,
        vp.total_vendido * (COALESCE(cp.precio_costo, 0) * COALESCE(tc.valor_usd, 1)) AS costo_total_vendido,
        COALESCE(pp.precio_venta_cup, vp.precio_promedio, 0) - (COALESCE(cp.precio_costo, 0) * COALESCE(tc.valor_usd, 1)) AS ganancia_unitaria,
        vp.ingreso_total - (vp.total_vendido * (COALESCE(cp.precio_costo, 0) * COALESCE(tc.valor_usd, 1))) AS ganancia_total
    FROM ventas_productos vp
    JOIN app_dat_producto p ON vp.id_producto = p.id
    LEFT JOIN precios_productos pp ON p.id = pp.id_producto AND COALESCE(vp.id_variante, 0) = COALESCE(pp.id_variante, 0)
    LEFT JOIN costos_productos cp ON p.id = cp.id_producto AND COALESCE(vp.id_variante, 0) = COALESCE(cp.id_variante, 0)
    CROSS JOIN tasa_cambio tc
    WHERE p.id_tienda = p_id_tienda
    ORDER BY vp.ingreso_total DESC, p.denominacion;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error en fn_reporte_ventas_ganancias_simple: %', SQLERRM;
END;
$$;
