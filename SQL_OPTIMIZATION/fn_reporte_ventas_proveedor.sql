-- Función para reporte de ventas por proveedor
DROP FUNCTION IF EXISTS public.fn_reporte_ventas_proveedor(BIGINT, TIMESTAMP WITH TIME ZONE, TIMESTAMP WITH TIME ZONE);

CREATE OR REPLACE FUNCTION public.fn_reporte_ventas_proveedor(
    p_id_tienda BIGINT,
    p_fecha_desde TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    p_fecha_hasta TIMESTAMP WITH TIME ZONE DEFAULT NULL
)
RETURNS TABLE (
    id_proveedor BIGINT,
    nombre_proveedor VARCHAR,
    total_ventas NUMERIC,
    total_costo NUMERIC,
    total_ganancia NUMERIC,
    cantidad_productos NUMERIC,
    margen_porcentaje NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    WITH 
    -- 1. Unit Values (Logic provided by user)
    unit_values AS (
        SELECT 
            p.id AS id_producto,
            p.id_proveedor,
            COALESCE(pv.precio_venta_cup, 0) AS precio_venta_unitario,
            (COALESCE(rp.costo_real, rp.precio_unitario, 0) * COALESCE(tc.tasa, 1)) AS precio_costo_unitario,
            (COALESCE(pv.precio_venta_cup, 0) - (COALESCE(rp.costo_real, rp.precio_unitario, 0) * COALESCE(tc.tasa, 1))) AS ganancia_unitaria
        FROM 
            app_dat_producto p
        INNER JOIN (
            -- Obtener el costo más reciente de recepción
            SELECT DISTINCT ON (rp.id_producto, rp.id_variante)
                rp.id_producto,
                rp.id_variante,
                rp.precio_unitario,
                rp.costo_real
            FROM app_dat_recepcion_productos rp
            INNER JOIN app_dat_operaciones o ON rp.id_operacion = o.id
            WHERE 
                (p_fecha_desde IS NULL OR o.created_at >= p_fecha_desde)
                AND (p_fecha_hasta IS NULL OR o.created_at < p_fecha_hasta + INTERVAL '1 day')
            ORDER BY rp.id_producto, rp.id_variante, o.created_at DESC
        ) rp ON p.id = rp.id_producto
        LEFT JOIN (
            -- Obtener el precio de venta más reciente
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
            SELECT tasa
            FROM tasas_conversion 
            WHERE moneda_origen = 'USD' AND moneda_destino = 'CUP'
            ORDER BY fecha_actualizacion DESC
            LIMIT 1
        ) tc ON true
        WHERE 
            p.id_tienda = p_id_tienda
            AND (rp.costo_real IS NOT NULL OR rp.precio_unitario IS NOT NULL)
    ),
    -- 2. Sales Volume
    sales_volume AS (
        SELECT
            d.id_producto,
            SUM(d.cantidad) as cantidad_vendida
        FROM app_dat_extraccion_productos d
        INNER JOIN app_dat_operaciones o ON d.id_operacion = o.id
        INNER JOIN app_nom_tipo_operacion nto ON o.id_tipo_operacion = nto.id
        LEFT JOIN app_dat_operacion_venta ov ON o.id = ov.id_operacion
        WHERE o.id_tienda = p_id_tienda
          AND nto.denominacion = 'VENTA'
          AND ov.es_pagada = true
          AND (p_fecha_desde IS NULL OR o.created_at >= p_fecha_desde)
          AND (p_fecha_hasta IS NULL OR o.created_at < p_fecha_hasta + INTERVAL '1 day')
        GROUP BY d.id_producto
    )
    -- 3. Aggregate by Supplier
    SELECT
        prov.id AS id_proveedor,
        COALESCE(prov.denominacion, 'Sin Proveedor')::VARCHAR AS nombre_proveedor,
        COALESCE(SUM(uv.precio_venta_unitario * sv.cantidad_vendida), 0)::NUMERIC AS total_ventas,
        COALESCE(SUM(uv.precio_costo_unitario * sv.cantidad_vendida), 0)::NUMERIC AS total_costo,
        COALESCE(SUM(uv.ganancia_unitaria * sv.cantidad_vendida), 0)::NUMERIC AS total_ganancia,
        COALESCE(SUM(sv.cantidad_vendida), 0)::NUMERIC AS cantidad_productos,
        CASE 
            WHEN COALESCE(SUM(uv.precio_venta_unitario * sv.cantidad_vendida), 0) = 0 THEN 0
            ELSE (COALESCE(SUM(uv.ganancia_unitaria * sv.cantidad_vendida), 0) / COALESCE(SUM(uv.precio_venta_unitario * sv.cantidad_vendida), 0) * 100)::NUMERIC
        END AS margen_porcentaje
    FROM unit_values uv
    INNER JOIN sales_volume sv ON uv.id_producto = sv.id_producto
    LEFT JOIN app_dat_proveedor prov ON uv.id_proveedor = prov.id
    GROUP BY prov.id, prov.denominacion
    ORDER BY total_ventas DESC;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.fn_reporte_ventas_proveedor(BIGINT, TIMESTAMP WITH TIME ZONE, TIMESTAMP WITH TIME ZONE) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_reporte_ventas_proveedor(BIGINT, TIMESTAMP WITH TIME ZONE, TIMESTAMP WITH TIME ZONE) TO service_role;
