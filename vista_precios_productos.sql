CREATE OR REPLACE FUNCTION fn_vista_precios_productos(
    p_id_tienda INTEGER,
    p_fecha_desde DATE DEFAULT NULL,
    p_fecha_hasta DATE DEFAULT NULL
)
RETURNS TABLE (
    id_tienda bigint,
    id_producto bigint,
    nombre_producto varchar,
    precio_venta_cup NUMERIC,
    precio_costo NUMERIC,
    valor_usd NUMERIC,
    precio_costo_cup NUMERIC,
    ganancia NUMERIC
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.id_tienda,
        p.id AS id_producto,
        p.denominacion AS nombre_producto,
        COALESCE(pv.precio_venta_cup, 0) AS precio_venta_cup,
        COALESCE(rp.costo_real, rp.precio_unitario, 0) AS precio_costo,
        COALESCE(tc.tasa, 1) AS valor_usd,
        COALESCE(rp.costo_real, rp.precio_unitario, 0) * COALESCE(tc.tasa, 1) AS precio_costo_cup,
        COALESCE(pv.precio_venta_cup, 0) - (COALESCE(rp.costo_real, rp.precio_unitario, 0) * COALESCE(tc.tasa, 1)) AS ganancia
    FROM 
        app_dat_producto p
    INNER JOIN (
        -- Obtener el costo más reciente de recepción para cada producto
        SELECT DISTINCT ON (rp.id_producto, rp.id_variante)
            rp.id_producto,
            rp.id_variante,
            rp.precio_unitario,
            rp.costo_real
        FROM app_dat_recepcion_productos rp
        INNER JOIN app_dat_operaciones o ON rp.id_operacion = o.id
        WHERE 
            (p_fecha_desde IS NULL OR o.created_at >= p_fecha_desde)
            AND (p_fecha_hasta IS NULL OR o.created_at <= p_fecha_hasta)
        ORDER BY rp.id_producto, rp.id_variante, o.created_at DESC
    ) rp ON p.id = rp.id_producto
    LEFT JOIN (
        -- Obtener el precio de venta más reciente para cada producto
        SELECT DISTINCT ON (ven.id_producto, ven.id_variante) 
            ven.id_producto,
            ven.id_variante,
            ven.precio_venta_cup
        FROM app_dat_precio_venta ven
        WHERE (fecha_hasta IS NULL OR fecha_hasta >= CURRENT_DATE)
            AND fecha_desde <= CURRENT_DATE
        ORDER BY ven.id_producto, ven.id_variante, created_at DESC
    ) pv ON p.id = pv.id_producto AND COALESCE(pv.id_variante, 0) = COALESCE(rp.id_variante, 0)
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
        AND (rp.costo_real IS NOT NULL OR rp.precio_unitario IS NOT NULL)
    ORDER BY p.denominacion;
END;
$$;
