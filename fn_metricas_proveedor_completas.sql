-- =====================================================
-- FUNCIÓN: fn_metricas_proveedor_completas
-- DESCRIPCIÓN: Obtiene métricas detalladas de un proveedor específico
-- PARÁMETROS: p_id_proveedor, p_fecha_desde, p_fecha_hasta
-- =====================================================

CREATE OR REPLACE FUNCTION fn_metricas_proveedor_completas(
    p_id_proveedor BIGINT,
    p_fecha_desde DATE DEFAULT NULL,
    p_fecha_hasta DATE DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_fecha_desde DATE;
    v_fecha_hasta DATE;
    v_result JSON;
    v_total_ordenes INTEGER := 0;
    v_valor_total DECIMAL(15,2) := 0.00;
    v_valor_promedio DECIMAL(15,2) := 0.00;
    v_lead_time_promedio DECIMAL(8,2) := 0.00;
    v_lead_time_real DECIMAL(8,2) := 0.00;
    v_performance_score DECIMAL(5,2) := 0.00;
    v_ultima_compra DATE;
    v_productos_suministrados INTEGER := 0;
    v_ordenes_a_tiempo INTEGER := 0;
    v_ordenes_tarde INTEGER := 0;
    v_calidad_score DECIMAL(5,2) := 100.00;
BEGIN
    -- Establecer fechas por defecto si no se proporcionan
    v_fecha_desde := COALESCE(p_fecha_desde, CURRENT_DATE - INTERVAL '90 days');
    v_fecha_hasta := COALESCE(p_fecha_hasta, CURRENT_DATE);

    -- Validar que el proveedor existe
    IF NOT EXISTS (SELECT 1 FROM app_dat_proveedor WHERE id = p_id_proveedor) THEN
        RAISE EXCEPTION 'Proveedor con ID % no encontrado', p_id_proveedor;
    END IF;

    -- Métricas básicas de órdenes
    SELECT 
        COUNT(DISTINCT o.id),
        COALESCE(SUM(rp.costo_real * rp.cantidad), 0),
        COALESCE(AVG(rp.costo_real * rp.cantidad), 0),
        MAX(o.created_at)::DATE
    INTO 
        v_total_ordenes,
        v_valor_total,
        v_valor_promedio,
        v_ultima_compra
    FROM app_dat_operaciones o
    INNER JOIN app_dat_recepcion_productos rp ON rp.id_operacion = o.id
    WHERE rp.id_proveedor = p_id_proveedor
      AND o.created_at::DATE BETWEEN v_fecha_desde AND v_fecha_hasta
      AND o.id_estado_operacion = 3; -- Solo operaciones ejecutadas

    -- Productos únicos suministrados
    SELECT COUNT(DISTINCT rp.id_producto)
    INTO v_productos_suministrados
    FROM app_dat_operaciones o
    INNER JOIN app_dat_recepcion_productos rp ON rp.id_operacion = o.id
    WHERE rp.id_proveedor = p_id_proveedor
      AND o.created_at::DATE BETWEEN v_fecha_desde AND v_fecha_hasta
      AND o.id_estado_operacion = 3;

    -- Lead time prometido vs real (usando datos del proveedor)
    SELECT COALESCE(AVG(lead_time), 0)
    INTO v_lead_time_promedio
    FROM app_dat_proveedor
    WHERE id = p_id_proveedor;

    -- Lead time real calculado (días entre creación y ejecución)
    SELECT COALESCE(AVG(
        EXTRACT(EPOCH FROM (
            SELECT created_at FROM app_dat_estados_operacion eo 
            WHERE eo.id_operacion = o.id AND eo.id_estado = 3 
            ORDER BY created_at DESC LIMIT 1
        ) - o.created_at) / 86400
    ), 0)
    INTO v_lead_time_real
    FROM app_dat_operaciones o
    INNER JOIN app_dat_recepcion_productos rp ON rp.id_operacion = o.id
    WHERE rp.id_proveedor = p_id_proveedor
      AND o.created_at::DATE BETWEEN v_fecha_desde AND v_fecha_hasta
      AND o.id_estado_operacion = 3;

    -- Análisis de puntualidad
    SELECT 
        COUNT(CASE WHEN lead_time_real <= v_lead_time_promedio THEN 1 END),
        COUNT(CASE WHEN lead_time_real > v_lead_time_promedio THEN 1 END)
    INTO v_ordenes_a_tiempo, v_ordenes_tarde
    FROM (
        SELECT EXTRACT(EPOCH FROM (
            SELECT created_at FROM app_dat_estados_operacion eo 
            WHERE eo.id_operacion = o.id AND eo.id_estado = 3 
            ORDER BY created_at DESC LIMIT 1
        ) - o.created_at) / 86400 as lead_time_real
        FROM app_dat_operaciones o
        INNER JOIN app_dat_recepcion_productos rp ON rp.id_operacion = o.id
        WHERE rp.id_proveedor = p_id_proveedor
          AND o.created_at::DATE BETWEEN v_fecha_desde AND v_fecha_hasta
          AND o.id_estado_operacion = 3
    ) lead_times;

    -- Calcular performance score
    IF v_total_ordenes > 0 THEN
        v_performance_score := (v_ordenes_a_tiempo::DECIMAL / v_total_ordenes::DECIMAL) * 100;
    END IF;

    -- Construir resultado JSON
    v_result := json_build_object(
        'id_proveedor', p_id_proveedor,
        'periodo', json_build_object(
            'fecha_desde', v_fecha_desde,
            'fecha_hasta', v_fecha_hasta
        ),
        'metricas_basicas', json_build_object(
            'total_ordenes', v_total_ordenes,
            'valor_total', v_valor_total,
            'valor_promedio', v_valor_promedio,
            'productos_suministrados', v_productos_suministrados,
            'ultima_compra', v_ultima_compra
        ),
        'metricas_performance', json_build_object(
            'lead_time_prometido', v_lead_time_promedio,
            'lead_time_real', v_lead_time_real,
            'ordenes_a_tiempo', v_ordenes_a_tiempo,
            'ordenes_tarde', v_ordenes_tarde,
            'performance_score', v_performance_score,
            'calidad_score', v_calidad_score
        ),
        'tendencias', json_build_object(
            'crecimiento_mensual', 0.0, -- Se puede calcular con datos históricos
            'variacion_precios', 0.0,   -- Se puede calcular comparando precios
            'estabilidad_suministro', v_performance_score
        ),
        'alertas', json_build_array(
            CASE 
                WHEN v_performance_score < 70 THEN 'Performance bajo: ' || v_performance_score || '%'
                WHEN v_lead_time_real > v_lead_time_promedio * 1.5 THEN 'Lead time excesivo'
                WHEN v_ultima_compra < CURRENT_DATE - INTERVAL '30 days' THEN 'Sin compras recientes'
                ELSE NULL
            END
        ),
        'generado_en', NOW()
    );

    RETURN v_result;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error calculando métricas del proveedor: %', SQLERRM;
END;
$$;
