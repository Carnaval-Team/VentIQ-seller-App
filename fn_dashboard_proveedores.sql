-- =====================================================
-- FUNCIÓN: fn_dashboard_proveedores
-- DESCRIPCIÓN: Dashboard específico de proveedores con KPIs y métricas
-- PARÁMETROS: p_id_tienda, p_periodo (días)
-- =====================================================

CREATE OR REPLACE FUNCTION fn_dashboard_proveedores(
    p_id_tienda BIGINT DEFAULT NULL,
    p_periodo INTEGER DEFAULT 30
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_fecha_desde DATE;
    v_fecha_hasta DATE;
    v_result JSON;
    v_total_proveedores INTEGER := 0;
    v_proveedores_activos INTEGER := 0;
    v_nuevos_proveedores INTEGER := 0;
    v_valor_compras_total DECIMAL(15,2) := 0.00;
    v_valor_compras_mes_anterior DECIMAL(15,2) := 0.00;
    v_crecimiento_compras DECIMAL(8,2) := 0.00;
    v_lead_time_promedio DECIMAL(8,2) := 0.00;
    v_performance_promedio DECIMAL(8,2) := 0.00;
    v_top_proveedores JSON;
    v_alertas JSON;
    v_distribucion_geografica JSON;
    v_productos_por_proveedor DECIMAL(8,2) := 0.00;
BEGIN
    -- Establecer período de análisis
    v_fecha_hasta := CURRENT_DATE;
    v_fecha_desde := CURRENT_DATE - INTERVAL '%s days' % p_periodo;

    -- KPIs básicos de proveedores
    SELECT COUNT(*)
    INTO v_total_proveedores
    FROM app_dat_proveedor p
    WHERE (p_id_tienda IS NULL OR p.id_tienda = p_id_tienda);

    -- Proveedores activos (con compras en el período)
    SELECT COUNT(DISTINCT rp.id_proveedor)
    INTO v_proveedores_activos
    FROM app_dat_operaciones o
    INNER JOIN app_dat_recepcion_productos rp ON rp.id_operacion = o.id
    WHERE o.created_at::DATE BETWEEN v_fecha_desde AND v_fecha_hasta
      AND o.id_estado_operacion = 3
      AND (p_id_tienda IS NULL OR o.id_tienda = p_id_tienda);

    -- Nuevos proveedores en el período
    SELECT COUNT(*)
    INTO v_nuevos_proveedores
    FROM app_dat_proveedor p
    WHERE p.created_at::DATE BETWEEN v_fecha_desde AND v_fecha_hasta
      AND (p_id_tienda IS NULL OR p.id_tienda = p_id_tienda);

    -- Valor total de compras en el período
    SELECT COALESCE(SUM(rp.costo_real * rp.cantidad), 0)
    INTO v_valor_compras_total
    FROM app_dat_operaciones o
    INNER JOIN app_dat_recepcion_productos rp ON rp.id_operacion = o.id
    WHERE o.created_at::DATE BETWEEN v_fecha_desde AND v_fecha_hasta
      AND o.id_estado_operacion = 3
      AND (p_id_tienda IS NULL OR o.id_tienda = p_id_tienda);

    -- Valor de compras del mes anterior para comparación
    SELECT COALESCE(SUM(rp.costo_real * rp.cantidad), 0)
    INTO v_valor_compras_mes_anterior
    FROM app_dat_operaciones o
    INNER JOIN app_dat_recepcion_productos rp ON rp.id_operacion = o.id
    WHERE o.created_at::DATE BETWEEN (v_fecha_desde - INTERVAL '%s days' % p_periodo) AND v_fecha_desde
      AND o.id_estado_operacion = 3
      AND (p_id_tienda IS NULL OR o.id_tienda = p_id_tienda);

    -- Calcular crecimiento
    IF v_valor_compras_mes_anterior > 0 THEN
        v_crecimiento_compras := ((v_valor_compras_total - v_valor_compras_mes_anterior) / v_valor_compras_mes_anterior) * 100;
    END IF;

    -- Lead time promedio de todos los proveedores activos
    SELECT COALESCE(AVG(p.lead_time), 0)
    INTO v_lead_time_promedio
    FROM app_dat_proveedor p
    WHERE EXISTS (
        SELECT 1 FROM app_dat_recepcion_productos rp 
        INNER JOIN app_dat_operaciones o ON o.id = rp.id_operacion
        WHERE rp.id_proveedor = p.id 
          AND o.created_at::DATE BETWEEN v_fecha_desde AND v_fecha_hasta
          AND o.id_estado_operacion = 3
    )
    AND (p_id_tienda IS NULL OR p.id_tienda = p_id_tienda);

    -- Promedio de productos por proveedor
    SELECT COALESCE(AVG(productos_count), 0)
    INTO v_productos_por_proveedor
    FROM (
        SELECT COUNT(DISTINCT rp.id_producto) as productos_count
        FROM app_dat_recepcion_productos rp
        INNER JOIN app_dat_operaciones o ON o.id = rp.id_operacion
        WHERE o.created_at::DATE BETWEEN v_fecha_desde AND v_fecha_hasta
          AND o.id_estado_operacion = 3
          AND (p_id_tienda IS NULL OR o.id_tienda = p_id_tienda)
        GROUP BY rp.id_proveedor
    ) proveedor_productos;

    -- Top 5 proveedores por valor de compras
    SELECT json_agg(
        json_build_object(
            'id_proveedor', rp.id_proveedor,
            'denominacion', p.denominacion,
            'valor_total', proveedor_stats.valor_total,
            'total_ordenes', proveedor_stats.total_ordenes,
            'productos_suministrados', proveedor_stats.productos_count,
            'performance_score', COALESCE(
                (proveedor_stats.ordenes_a_tiempo::DECIMAL / NULLIF(proveedor_stats.total_ordenes, 0)::DECIMAL) * 100, 
                0
            )
        ) ORDER BY proveedor_stats.valor_total DESC
    )
    INTO v_top_proveedores
    FROM (
        SELECT 
            rp.id_proveedor,
            SUM(rp.costo_real * rp.cantidad) as valor_total,
            COUNT(DISTINCT o.id) as total_ordenes,
            COUNT(DISTINCT rp.id_producto) as productos_count,
            COUNT(CASE WHEN EXTRACT(EPOCH FROM (
                SELECT created_at FROM app_dat_estados_operacion eo 
                WHERE eo.id_operacion = o.id AND eo.id_estado = 3 
                ORDER BY created_at DESC LIMIT 1
            ) - o.created_at) / 86400 <= COALESCE(p.lead_time, 7) THEN 1 END) as ordenes_a_tiempo
        FROM app_dat_operaciones o
        INNER JOIN app_dat_recepcion_productos rp ON rp.id_operacion = o.id
        INNER JOIN app_dat_proveedor p ON p.id = rp.id_proveedor
        WHERE o.created_at::DATE BETWEEN v_fecha_desde AND v_fecha_hasta
          AND o.id_estado_operacion = 3
          AND (p_id_tienda IS NULL OR o.id_tienda = p_id_tienda)
        GROUP BY rp.id_proveedor, p.lead_time
        ORDER BY valor_total DESC
        LIMIT 5
    ) proveedor_stats
    INNER JOIN app_dat_proveedor p ON p.id = proveedor_stats.id_proveedor;

    -- Distribución geográfica de proveedores
    SELECT json_agg(
        json_build_object(
            'ubicacion', COALESCE(ubicacion, 'Sin especificar'),
            'cantidad', ubicacion_count
        )
    )
    INTO v_distribucion_geografica
    FROM (
        SELECT 
            ubicacion,
            COUNT(*) as ubicacion_count
        FROM app_dat_proveedor
        WHERE (p_id_tienda IS NULL OR id_tienda = p_id_tienda)
        GROUP BY ubicacion
        ORDER BY ubicacion_count DESC
        LIMIT 10
    ) ubicaciones;

    -- Generar alertas automáticas
    SELECT json_agg(alerta)
    INTO v_alertas
    FROM (
        SELECT DISTINCT
            CASE 
                WHEN v_proveedores_activos < (v_total_proveedores * 0.3) THEN 
                    json_build_object(
                        'tipo', 'warning',
                        'mensaje', 'Solo ' || v_proveedores_activos || ' de ' || v_total_proveedores || ' proveedores están activos',
                        'accion', 'Revisar proveedores inactivos'
                    )
                WHEN v_crecimiento_compras < -20 THEN
                    json_build_object(
                        'tipo', 'danger',
                        'mensaje', 'Reducción significativa en compras: ' || ROUND(v_crecimiento_compras, 1) || '%',
                        'accion', 'Analizar causas de la reducción'
                    )
                WHEN v_lead_time_promedio > 14 THEN
                    json_build_object(
                        'tipo', 'warning',
                        'mensaje', 'Lead time promedio alto: ' || ROUND(v_lead_time_promedio, 1) || ' días',
                        'accion', 'Negociar mejores tiempos de entrega'
                    )
                WHEN v_nuevos_proveedores = 0 AND p_periodo >= 30 THEN
                    json_build_object(
                        'tipo', 'info',
                        'mensaje', 'No se han agregado nuevos proveedores en ' || p_periodo || ' días',
                        'accion', 'Considerar diversificar la base de proveedores'
                    )
                ELSE NULL
            END as alerta
    ) alertas_generadas
    WHERE alerta IS NOT NULL;

    -- Construir resultado final
    v_result := json_build_object(
        'periodo', json_build_object(
            'fecha_desde', v_fecha_desde,
            'fecha_hasta', v_fecha_hasta,
            'dias', p_periodo
        ),
        'kpis_principales', json_build_object(
            'total_proveedores', v_total_proveedores,
            'proveedores_activos', v_proveedores_activos,
            'nuevos_proveedores', v_nuevos_proveedores,
            'tasa_actividad', CASE WHEN v_total_proveedores > 0 THEN 
                ROUND((v_proveedores_activos::DECIMAL / v_total_proveedores::DECIMAL) * 100, 2) 
                ELSE 0 END
        ),
        'metricas_financieras', json_build_object(
            'valor_compras_total', v_valor_compras_total,
            'valor_compras_anterior', v_valor_compras_mes_anterior,
            'crecimiento_compras', ROUND(v_crecimiento_compras, 2),
            'valor_promedio_por_proveedor', CASE WHEN v_proveedores_activos > 0 THEN 
                ROUND(v_valor_compras_total / v_proveedores_activos, 2) 
                ELSE 0 END
        ),
        'metricas_operativas', json_build_object(
            'lead_time_promedio', ROUND(v_lead_time_promedio, 1),
            'productos_por_proveedor', ROUND(v_productos_por_proveedor, 1),
            'diversificacion_score', CASE WHEN v_total_proveedores > 0 THEN 
                LEAST(100, (v_proveedores_activos * 10)) 
                ELSE 0 END
        ),
        'top_proveedores', COALESCE(v_top_proveedores, '[]'::json),
        'distribucion_geografica', COALESCE(v_distribucion_geografica, '[]'::json),
        'alertas', COALESCE(v_alertas, '[]'::json),
        'generado_en', NOW()
    );

    RETURN v_result;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error generando dashboard de proveedores: %', SQLERRM;
END;
$$;
