-- Fixed query without turno dependency
BEGIN
    -- Validar fechas por defecto
    IF p_fecha_desde IS NULL THEN
        p_fecha_desde := CURRENT_DATE - INTERVAL '30 days';
    END IF;
    
    IF p_fecha_hasta IS NULL THEN
        p_fecha_hasta := CURRENT_DATE;
    END IF;

    RETURN QUERY
    WITH ventas_vendedor AS (
        SELECT 
            -- Obtener UUID del usuario (para agrupar por usuario real)
            COALESCE(
                -- 1. UUID del usuario que creó la operación
                o.uuid,
                -- 2. UUID del vendedor por TPV
                (SELECT v.uuid 
                 FROM app_dat_vendedor v 
                 JOIN app_dat_tpv tpv ON v.id_tpv = tpv.id 
                 WHERE tpv.id = ov.id_tpv 
                 LIMIT 1),
                -- 3. UUID del vendedor por turno
                (SELECT v.uuid
                 FROM app_dat_caja_turno ct
                 JOIN app_dat_vendedor v ON ct.id_vendedor = v.id
                 WHERE ct.id = ov.id_turno_apertura
                 LIMIT 1)
            ) as usuario_uuid,
            
            -- ID del vendedor (para compatibilidad)
            COALESCE(
                -- 1. Por TPV asociado a la venta
                (SELECT v.id 
                 FROM app_dat_vendedor v 
                 JOIN app_dat_tpv tpv ON v.id_tpv = tpv.id 
                 WHERE tpv.id = ov.id_tpv 
                 LIMIT 1),
                -- 2. Por UUID del usuario que creó la operación
                (SELECT v.id
                 FROM app_dat_vendedor v
                 WHERE v.uuid = o.uuid
                 LIMIT 1),
                -- 3. Por turno si existe (fallback)
                (SELECT ct.id_vendedor
                 FROM app_dat_caja_turno ct
                 WHERE ct.id = ov.id_turno_apertura
                 LIMIT 1),
                -- 4. Por trabajador asociado al usuario
                (SELECT v.id
                 FROM app_dat_vendedor v
                 WHERE v.uuid = o.uuid
                 LIMIT 1)
            ) as vendedor_id,
            
            -- Nombre completo del usuario desde app_dat_trabajadores
            COALESCE(
                -- 1. Por UUID directo en trabajadores
                (SELECT (COALESCE(t.nombres, '') || ' ' || COALESCE(t.apellidos, ''))::VARCHAR
                 FROM app_dat_trabajadores t
                 WHERE t.uuid = o.uuid
                 LIMIT 1),
                -- 2. Por vendedor con TPV
                (SELECT (COALESCE(t.nombres, '') || ' ' || COALESCE(t.apellidos, ''))::VARCHAR
                 FROM app_dat_vendedor v 
                 JOIN app_dat_tpv tpv ON v.id_tpv = tpv.id 
                 JOIN app_dat_trabajadores t ON v.id_trabajador = t.id
                 WHERE tpv.id = ov.id_tpv 
                 LIMIT 1),
                -- 3. Por vendedor con turno
                (SELECT (COALESCE(t.nombres, '') || ' ' || COALESCE(t.apellidos, ''))::VARCHAR
                 FROM app_dat_caja_turno ct
                 JOIN app_dat_vendedor v ON ct.id_vendedor = v.id
                 JOIN app_dat_trabajadores t ON v.id_trabajador = t.id
                 WHERE ct.id = ov.id_turno_apertura
                 LIMIT 1),
                'Usuario desconocido'
            ) as nombre_vendedor,
            
            t.denominacion as tienda,
            ov.importe_total,
            o.created_at,
            
            -- Detalles de productos vendidos
            (SELECT SUM(ep.cantidad) 
             FROM app_dat_extraccion_productos ep 
             WHERE ep.id_operacion = o.id) as cantidad_productos,
            
            -- Información de pagos
            (SELECT SUM(pv.monto) 
             FROM app_dat_pago_venta pv 
             JOIN app_nom_medio_pago mp ON pv.id_medio_pago = mp.id 
             WHERE pv.id_operacion_venta = ov.id_operacion 
             AND mp.es_efectivo = true) as monto_efectivo,
            
            (SELECT SUM(pv.monto) 
             FROM app_dat_pago_venta pv 
             JOIN app_nom_medio_pago mp ON pv.id_medio_pago = mp.id 
             WHERE pv.id_operacion_venta = ov.id_operacion 
             AND mp.es_efectivo = false AND mp.es_digital = false) as monto_tarjeta,
            
            (SELECT SUM(pv.monto) 
             FROM app_dat_pago_venta pv 
             JOIN app_nom_medio_pago mp ON pv.id_medio_pago = mp.id 
             WHERE pv.id_operacion_venta = ov.id_operacion 
             AND mp.es_digital = true) as monto_digital

        FROM app_dat_operacion_venta ov
        JOIN app_dat_operaciones o ON ov.id_operacion = o.id
        JOIN app_dat_tienda t ON o.id_tienda = t.id
        -- REMOVED: JOIN app_dat_caja_turno ct ON ov.id_turno_apertura = ct.id
        -- REMOVED: JOIN app_dat_vendedor ven ON ct.id_vendedor = ven.id
        WHERE (p_vendedor_id IS NULL OR (
            -- Si se especifica un vendedor, buscar coincidencia
            CASE 
                WHEN ov.id_tpv IS NOT NULL THEN (
                    SELECT v.id 
                    FROM app_dat_vendedor v 
                    JOIN app_dat_tpv tpv ON v.id_tpv = tpv.id 
                    WHERE tpv.id = ov.id_tpv 
                    LIMIT 1
                ) = p_vendedor_id
                -- Si no hay TPV pero se busca un vendedor específico, verificar por UUID
                WHEN o.uuid IS NOT NULL THEN (
                    SELECT v.id
                    FROM app_dat_vendedor v
                    WHERE v.uuid = o.uuid
                    LIMIT 1
                ) = p_vendedor_id
                ELSE FALSE
            END
        ))
        AND (p_tienda_id IS NULL OR t.id = p_tienda_id)
        AND o.created_at::DATE BETWEEN p_fecha_desde AND p_fecha_hasta
        AND ov.es_pagada = true  -- Solo ventas pagadas
    ),
    dias_laborados AS (
        SELECT 
            vven.usuario_uuid,
            COUNT(DISTINCT created_at::DATE) as dias
        FROM ventas_vendedor as vven
        WHERE vven.usuario_uuid IS NOT NULL
        GROUP BY vven.usuario_uuid
    )
    SELECT 
        vv.usuario_uuid,
        vv.vendedor_id,
        vv.nombre_vendedor,
        vv.tienda,
        COUNT(*)::BIGINT as total_ventas,
        COALESCE(SUM(vv.importe_total), 0) as total_ingresos,
        CASE 
            WHEN COUNT(*) > 0 THEN SUM(vv.importe_total) / COUNT(*)
            ELSE 0 
        END as ticket_promedio,
        COALESCE(SUM(vv.cantidad_productos), 0) as productos_vendidos,
        COALESCE(SUM(vv.monto_efectivo), 0) as ventas_efectivo,
        COALESCE(SUM(vv.monto_tarjeta), 0) as ventas_tarjeta,
        COALESCE(SUM(vv.importe_total - COALESCE(vv.monto_efectivo, 0) - COALESCE(vv.monto_tarjeta, 0)), 0) as ventas_otros,
        p_fecha_desde,
        p_fecha_hasta,
        (COALESCE(dl.dias, 0))::integer as dias_laborados,
        CASE 
            WHEN COALESCE(dl.dias, 0) > 0 THEN SUM(vv.importe_total) / dl.dias
            ELSE 0 
        END as promedio_ventas_diario
    FROM ventas_vendedor vv
    LEFT JOIN dias_laborados dl ON vv.usuario_uuid = dl.usuario_uuid
    WHERE vv.usuario_uuid IS NOT NULL  -- Filtrar registros sin usuario válido
    GROUP BY vv.usuario_uuid, vv.vendedor_id, vv.nombre_vendedor, vv.tienda, dl.dias
    ORDER BY total_ingresos DESC;
END;
