-- Query para obtener totales de ventas, productos vendidos, dinero total 
-- y datos del trabajador agrupados por UUID del usuario que registró la venta
-- Incluye filtros por UUID, fecha desde/hasta y desglose por tipo de pago (efectivo/transferencia)
-- Basado en las tablas: app_dat_operaciones, app_dat_operacion_venta, 
-- app_dat_extraccion_productos, app_dat_vendedor, app_dat_trabajadores, app_dat_pago_venta

CREATE OR REPLACE FUNCTION fn_reporte_ventas_por_vendedor(
    p_uuid_usuario UUID DEFAULT NULL,
    p_fecha_desde DATE DEFAULT NULL,
    p_fecha_hasta DATE DEFAULT NULL,
    p_id_tienda BIGINT DEFAULT NULL
)
RETURNS TABLE (
    uuid_usuario UUID,
    nombres VARCHAR,
    apellidos VARCHAR,
    nombre_completo VARCHAR,
    total_ventas BIGINT,
    total_productos_vendidos NUMERIC,
    total_dinero_efectivo NUMERIC,
    total_dinero_transferencia NUMERIC,
    total_dinero_general NUMERIC,
    total_importe_ventas NUMERIC,
    productos_diferentes_vendidos BIGINT,
    primera_venta TIMESTAMP WITH TIME ZONE,
    ultima_venta TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        o.uuid as uuid_usuario,
        t.nombres,
        t.apellidos,
        CONCAT(t.nombres, ' ', t.apellidos) as nombre_completo,
        COUNT(DISTINCT o.id) as total_ventas,
        SUM(ep.cantidad) as total_productos_vendidos,
        COALESCE(SUM(CASE WHEN pv.id_medio_pago = 1 THEN pv.monto ELSE 0 END), 0) as total_dinero_efectivo,
        COALESCE(SUM(CASE WHEN pv.id_medio_pago != 1 THEN pv.monto ELSE 0 END), 0) as total_dinero_transferencia,
        COALESCE(SUM(pv.monto), 0) as total_dinero_general,
        SUM(ov.importe_total) as total_importe_ventas,
        COUNT(DISTINCT ep.id_producto) as productos_diferentes_vendidos,
        MIN(o.created_at) as primera_venta,
        MAX(o.created_at) as ultima_venta
    FROM 
        app_dat_operaciones o
        INNER JOIN app_dat_operacion_venta ov ON o.id = ov.id_operacion
        INNER JOIN app_dat_extraccion_productos ep ON o.id = ep.id_operacion
        INNER JOIN app_dat_estado_operacion eo ON o.id = eo.id_operacion
        INNER JOIN app_dat_vendedor v ON o.uuid = v.uuid
        INNER JOIN app_dat_trabajadores t ON v.id_trabajador = t.id
        LEFT JOIN app_dat_pago_venta pv ON ov.id_operacion = pv.id_operacion_venta
    WHERE 
        eo.estado = 2  -- Solo operaciones completadas/pagadas
        AND ov.es_pagada = true  -- Solo ventas pagadas
        AND o.uuid IS NOT NULL  -- Asegurar que hay UUID
        AND (p_uuid_usuario IS NULL OR o.uuid = p_uuid_usuario)  -- Filtro por UUID
        AND (p_fecha_desde IS NULL OR o.created_at >= p_fecha_desde)  -- Filtro fecha desde
        AND (p_fecha_hasta IS NULL OR o.created_at <= p_fecha_hasta + INTERVAL '1 day' - INTERVAL '1 second')  -- Filtro fecha hasta
        AND (p_id_tienda IS NULL OR o.id_tienda = p_id_tienda)  -- Filtro por tienda
    GROUP BY 
        o.uuid, 
        t.nombres, 
        t.apellidos
    ORDER BY 
        total_dinero_general DESC, 
        total_ventas DESC;
END;
$$;

-- Ejemplo de uso:
-- SELECT * FROM fn_reporte_ventas_por_vendedor(NULL, NULL, NULL, NULL);  -- Todos los vendedores, todas las fechas, todas las tiendas
-- SELECT * FROM fn_reporte_ventas_por_vendedor('uuid-especifico', '2024-01-01', '2024-12-31', 1);  -- Vendedor específico en rango de fechas y tienda específica
-- SELECT * FROM fn_reporte_ventas_por_vendedor(NULL, '2024-01-01', '2024-01-31', NULL);  -- Todos los vendedores en enero 2024, todas las tiendas
-- SELECT * FROM fn_reporte_ventas_por_vendedor(NULL, NULL, NULL, 1);  -- Todos los vendedores de la tienda 1, todas las fechas
