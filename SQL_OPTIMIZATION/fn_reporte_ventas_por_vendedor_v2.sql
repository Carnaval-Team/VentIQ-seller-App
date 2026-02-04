CREATE OR REPLACE FUNCTION fn_reporte_ventas_por_vendedor_v2(
    p_uuid_usuario uuid DEFAULT NULL,
    p_fecha_desde date DEFAULT NULL,
    p_fecha_hasta date DEFAULT NULL,
    p_id_tienda bigint DEFAULT NULL
)
RETURNS TABLE (
    uuid_usuario uuid,
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
) AS $$
DECLARE
    v_fecha_inicio_filtro timestamptz;
    v_fecha_fin_filtro timestamptz;
    v_id_tpv bigint;
BEGIN
    -- Si NO se pasan fechas, usamos TODOS los turnos (abiertos y cerrados) del vendedor
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

        -- Obtener TODOS los turnos (abiertos y cerrados) del vendedor en ese TPV
        -- Tomar desde el más antiguo hasta el más reciente
        SELECT MIN(ct.fecha_apertura), MAX(COALESCE(ct.fecha_cierre, NOW()))
        INTO v_fecha_inicio_filtro, v_fecha_fin_filtro
        FROM app_dat_caja_turno ct
        WHERE ct.id_tpv = v_id_tpv
          AND ct.id_vendedor IN (SELECT id FROM app_dat_vendedor WHERE uuid = p_uuid_usuario);

        -- Si hay al menos un turno, filtramos desde el más antiguo hasta el más reciente
        IF v_fecha_inicio_filtro IS NULL THEN
            -- No hay turnos → no devolver datos
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
    
    -- Agregamos los productos por operación para evitar duplicación
    COALESCE(SUM(productos_por_operacion.total_productos), 0) AS total_productos_vendidos,
    
    -- Agregamos los pagos por operación para evitar duplicación
    COALESCE(SUM(pagos_por_operacion.total_efectivo), 0) AS total_dinero_efectivo,
    COALESCE(SUM(pagos_por_operacion.total_transferencia), 0) AS total_dinero_transferencia,
    COALESCE(SUM(pagos_por_operacion.total_general), 0) AS total_dinero_general,
    
    -- Agregamos los importes por operación para evitar duplicación
    COALESCE(SUM(productos_por_operacion.total_importe), 0) AS total_importe_ventas,
    (COALESCE(SUM(productos_por_operacion.productos_diferentes), 0))::bigint AS productos_diferentes_vendidos,
    
    MIN(o.created_at) AS primera_venta,
    MAX(o.created_at) AS ultima_venta
FROM app_dat_operaciones o
INNER JOIN app_dat_operacion_venta ov ON o.id = ov.id_operacion
INNER JOIN app_dat_estado_operacion eo ON o.id = eo.id_operacion
INNER JOIN app_dat_vendedor v ON o.uuid = v.uuid
INNER JOIN app_dat_trabajadores t ON v.id_trabajador = t.id

-- Subquery para agregar productos por operación
LEFT JOIN (
    SELECT 
        ep.id_operacion,
        SUM(ep.cantidad) AS total_productos,
        SUM(ep.importe) AS total_importe,
        COUNT(DISTINCT ep.id_producto) AS productos_diferentes
    FROM app_dat_extraccion_productos ep
    GROUP BY ep.id_operacion
) productos_por_operacion ON o.id = productos_por_operacion.id_operacion

-- Subquery para agregar pagos por operación
LEFT JOIN (
    SELECT 
        pv.id_operacion_venta,
        SUM(CASE WHEN pv.id_medio_pago = 1 THEN pv.monto ELSE 0 END) AS total_efectivo,
        SUM(CASE WHEN pv.id_medio_pago != 1 THEN pv.monto ELSE 0 END) AS total_transferencia,
        SUM(pv.monto) AS total_general
    FROM app_dat_pago_venta pv
    GROUP BY pv.id_operacion_venta
) pagos_por_operacion ON ov.id_operacion = pagos_por_operacion.id_operacion_venta

WHERE o.id_tipo_operacion = (SELECT id FROM app_nom_tipo_operacion WHERE LOWER(denominacion) = 'venta')
  AND eo.estado = 2 -- Solo operaciones completadas
  AND eo.id = (SELECT MAX(id) FROM app_dat_estado_operacion WHERE id_operacion = o.id)
  AND ov.es_pagada = true -- Venta pagada
  AND o.uuid IS NOT NULL
  AND (p_uuid_usuario IS NULL OR o.uuid = p_uuid_usuario)
  AND (v_id_tpv IS NULL OR ov.id_tpv = v_id_tpv)
  AND o.created_at >= v_fecha_inicio_filtro
  AND (v_fecha_fin_filtro IS NULL OR o.created_at <= v_fecha_fin_filtro)
  AND (p_id_tienda IS NULL OR o.id_tienda = p_id_tienda)
GROUP BY o.uuid, t.nombres, t.apellidos
ORDER BY total_dinero_general DESC, total_ventas DESC;
END;
$$ LANGUAGE plpgsql;
