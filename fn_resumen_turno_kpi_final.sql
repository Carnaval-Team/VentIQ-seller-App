CREATE OR REPLACE FUNCTION fn_resumen_turno_kpi_final(
    p_turno_id bigint DEFAULT NULL,
    p_vendedor_id bigint DEFAULT NULL,
    p_tpv_id bigint DEFAULT NULL,
    p_usuario_uuid uuid DEFAULT NULL
)
RETURNS TABLE(
    turno_id bigint,
    tpv varchar,
    vendedor varchar,
    fecha_apertura timestamp with time zone,
    fecha_cierre timestamp with time zone,
    duracion interval,
    estado_turno smallint,
    estado_descripcion varchar,
    
    -- Montos principales
    efectivo_inicial numeric,
    ventas_totales numeric,
    productos_vendidos numeric,
    operaciones_totales bigint,
    ticket_promedio numeric,
    
    -- Desglose de pagos por tipo
    ventas_efectivo numeric,
    ventas_transferencia numeric,
    porcentaje_efectivo numeric,
    porcentaje_transferencia numeric,
    
    -- Cálculos de caja
    efectivo_esperado numeric,
    efectivo_real numeric,
    diferencia_efectivo numeric,
    
    -- Egresos y ajustes
    total_egresos_parciales numeric,
    efectivo_real_ajustado numeric,
    diferencia_ajustada numeric,
    
    -- Estado de conciliación
    conciliacion_estado varchar,
    operaciones_por_hora numeric
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_uuid_vendedor UUID;
BEGIN
    -- Establecer contexto
    SET search_path = public;
    
    -- Obtener UUID del vendedor si se proporciona turno_id
    IF p_turno_id IS NOT NULL THEN
        SELECT v.uuid INTO v_uuid_vendedor
        FROM app_dat_caja_turno ct
        JOIN app_dat_vendedor v ON ct.id_vendedor = v.id
        WHERE ct.id = p_turno_id;
    END IF;

    RETURN QUERY
    SELECT
        ct.id AS turno_id,
        tpv.denominacion::VARCHAR AS tpv,
        (COALESCE(trab.nombres, '') || ' ' || COALESCE(trab.apellidos, ''))::VARCHAR AS vendedor,
        ct.fecha_apertura,
        ct.fecha_cierre,
        COALESCE(ct.fecha_cierre, NOW()) - ct.fecha_apertura AS duracion,
        ct.estado AS estado_turno,
        eo.denominacion::VARCHAR AS estado_descripcion,

        -- Montos principales
        ct.efectivo_inicial,
        COALESCE(vtas.ventas_totales, 0) AS ventas_totales,
        COALESCE(vtas.productos_vendidos, 0) AS productos_vendidos,
        COALESCE(stats.operaciones_totales, 0::BIGINT) AS operaciones_totales,
        CASE 
            WHEN COALESCE(vtas.operaciones_venta, 0) > 0 
            THEN ROUND(vtas.ventas_totales / vtas.operaciones_venta, 2)
            ELSE 0 
        END AS ticket_promedio,

        -- Desglose de pagos por tipo (usando tipo_pago)
        COALESCE(pagos.total_efectivo, 0) AS ventas_efectivo,
        COALESCE(pagos.total_transferencias, 0) AS ventas_transferencia,
        
        -- Porcentajes
        CASE 
            WHEN COALESCE(vtas.ventas_totales, 0) > 0 
            THEN ROUND(COALESCE(pagos.total_efectivo, 0) * 100.0 / vtas.ventas_totales, 2)
            ELSE 0 
        END AS porcentaje_efectivo,
        
        CASE 
            WHEN COALESCE(vtas.ventas_totales, 0) > 0 
            THEN ROUND(COALESCE(pagos.total_transferencias, 0) * 100.0 / vtas.ventas_totales, 2)
            ELSE 0 
        END AS porcentaje_transferencia,

        -- Cálculos de caja corregidos
        (ct.efectivo_inicial + COALESCE(pagos.total_efectivo, 0)) AS efectivo_esperado,
        (COALESCE(vtas.ventas_totales, 0) - COALESCE(pagos.total_transferencias, 0)) AS efectivo_real,
        ((COALESCE(vtas.ventas_totales, 0) - COALESCE(pagos.total_transferencias, 0)) - 
         (ct.efectivo_inicial + COALESCE(pagos.total_efectivo, 0))) AS diferencia_efectivo,

        -- Egresos y ajustes
        COALESCE(egresos.total_egresos, 0) AS total_egresos_parciales,
        ((COALESCE(vtas.ventas_totales, 0) - COALESCE(pagos.total_transferencias, 0)) - 
         COALESCE(egresos.total_egresos, 0)) AS efectivo_real_ajustado,
        (((COALESCE(vtas.ventas_totales, 0) - COALESCE(pagos.total_transferencias, 0)) - 
          COALESCE(egresos.total_egresos, 0)) - 
         (ct.efectivo_inicial + COALESCE(pagos.total_efectivo, 0))) AS diferencia_ajustada,

        -- Estado de conciliación
        CASE
            WHEN ct.estado = 1 THEN 'Abierto'::VARCHAR
            WHEN ct.diferencia IS NULL OR ct.diferencia = 0 THEN 'Conciliado'::VARCHAR
            WHEN ABS(COALESCE(ct.diferencia, 0)) <= 1.00 THEN 'Casi exacto (≤ $1)'::VARCHAR
            WHEN COALESCE(ct.diferencia, 0) > 0 THEN 'Sobrante'::VARCHAR
            ELSE 'Falta'::VARCHAR
        END AS conciliacion_estado,

        -- Operaciones por hora
        CASE 
            WHEN EXTRACT(EPOCH FROM (COALESCE(ct.fecha_cierre, NOW()) - ct.fecha_apertura)) > 0
            THEN ROUND(
                COALESCE(stats.operaciones_totales, 0) * 3600.0 / 
                EXTRACT(EPOCH FROM (COALESCE(ct.fecha_cierre, NOW()) - ct.fecha_apertura)), 
                2
            )
            ELSE 0 
        END AS operaciones_por_hora

    FROM app_dat_caja_turno ct
    JOIN app_dat_tpv tpv ON ct.id_tpv = tpv.id
    JOIN app_dat_vendedor ven ON ct.id_vendedor = ven.id
    JOIN app_dat_trabajadores trab ON ven.id_trabajador = trab.id
    JOIN app_nom_estado_operacion eo ON ct.estado = eo.id

    -- Estadísticas de ventas: SOLO operaciones completadas (estado = 2)
    LEFT JOIN LATERAL (
        SELECT
            SUM(ov.importe_total) AS ventas_totales,
            COUNT(DISTINCT ov.id_operacion) AS operaciones_venta,
            COALESCE(SUM(ep.cantidad), 0) AS productos_vendidos
        FROM app_dat_operacion_venta ov
        JOIN app_dat_operaciones o ON ov.id_operacion = o.id
        JOIN app_dat_estado_operacion eo_op ON eo_op.id_operacion = o.id
        LEFT JOIN app_dat_extraccion_productos ep ON o.id = ep.id_operacion
        WHERE ov.id_tpv = ct.id_tpv
          AND o.uuid = COALESCE(v_uuid_vendedor, ven.uuid)
          AND o.created_at >= ct.fecha_apertura
          AND (o.created_at <= ct.fecha_cierre OR ct.fecha_cierre IS NULL)
          AND o.id_tipo_operacion = (SELECT id FROM app_nom_tipo_operacion WHERE LOWER(denominacion) = 'venta')
          AND eo_op.estado = 2 -- SOLO operaciones completadas
          AND eo_op.id = (SELECT MAX(id) FROM app_dat_estado_operacion WHERE id_operacion = o.id)
    ) vtas ON true

    -- Resumen de pagos: usar tipo_pago para clasificar efectivo vs transferencia
    LEFT JOIN LATERAL (
        SELECT
            -- Efectivo: tipo_pago = 1
            COALESCE(SUM(CASE WHEN ov.tipo_pago = 1 THEN ov.importe_total ELSE 0 END), 0) AS total_efectivo,
            -- Transferencias: tipo_pago != 1 (2 u otros)
            COALESCE(SUM(CASE WHEN ov.tipo_pago != 1 THEN ov.importe_total ELSE 0 END), 0) AS total_transferencias,
            -- Total de pagos
            COALESCE(SUM(ov.importe_total), 0) AS total_pagos
        FROM app_dat_operacion_venta ov
        JOIN app_dat_operaciones o ON ov.id_operacion = o.id
        JOIN app_dat_estado_operacion eo_op ON eo_op.id_operacion = o.id
        WHERE ov.id_tpv = ct.id_tpv
          AND o.uuid = COALESCE(v_uuid_vendedor, ven.uuid)
          AND o.created_at >= ct.fecha_apertura
          AND (o.created_at <= COALESCE(ct.fecha_cierre, NOW()))
          AND o.id_tipo_operacion = (SELECT id FROM app_nom_tipo_operacion WHERE LOWER(denominacion) = 'venta')
          AND eo_op.estado = 2 -- SOLO operaciones completadas
          AND eo_op.id = (SELECT MAX(id) FROM app_dat_estado_operacion WHERE id_operacion = o.id)
    ) pagos ON true

    -- Estadísticas de operaciones (solo completadas)
    LEFT JOIN LATERAL (
        SELECT COUNT(*) AS operaciones_totales
        FROM app_dat_operaciones o
        JOIN app_dat_operacion_venta ov ON o.id = ov.id_operacion
        JOIN app_dat_estado_operacion eo_op ON eo_op.id_operacion = o.id
        WHERE ov.id_tpv = ct.id_tpv
          AND o.uuid = COALESCE(v_uuid_vendedor, ven.uuid)
          AND o.created_at >= ct.fecha_apertura
          AND (o.created_at <= ct.fecha_cierre OR ct.fecha_cierre IS NULL)
          AND o.id_tipo_operacion IN (
            SELECT id FROM app_nom_tipo_operacion 
            WHERE LOWER(denominacion) IN ('venta', 'devolución', 'ajuste')
          )
          AND eo_op.estado = 2 -- SOLO operaciones completadas
          AND eo_op.id = (SELECT MAX(id) FROM app_dat_estado_operacion WHERE id_operacion = o.id)
    ) stats ON true

    -- Egresos parciales del turno
    LEFT JOIN LATERAL (
        SELECT COALESCE(SUM(monto_entrega), 0) AS total_egresos
        FROM app_dat_entregas_parciales_caja 
        WHERE id_turno = ct.id
    ) egresos ON true

    WHERE (p_turno_id IS NULL OR ct.id = p_turno_id)
      AND (p_vendedor_id IS NULL OR ct.id_vendedor = p_vendedor_id)
      AND (p_tpv_id IS NULL OR ct.id_tpv = p_tpv_id)
      AND (p_usuario_uuid IS NULL OR ven.uuid = p_usuario_uuid);
END;
$$;

-- Comentarios sobre la función:
-- Esta función corrige todos los problemas identificados:
-- 1. Filtra SOLO operaciones completadas (estado = 2)
-- 2. Usa tipo_pago correctamente: 1=efectivo, 2+=transferencia
-- 3. Calcula efectivo real = ventas totales - transferencias
-- 4. Incluye todos los KPIs necesarios para el cierre de turno
-- 5. Maneja egresos parciales correctamente
-- 6. Proporciona cálculos precisos independientemente del número de ventas
