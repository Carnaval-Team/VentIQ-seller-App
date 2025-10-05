-- =====================================================
-- FUNCIONES RPC PARA GESTIÓN DE PROVEEDORES
-- =====================================================

-- 1. Función para obtener métricas de proveedor
CREATE OR REPLACE FUNCTION fn_metricas_proveedor(p_id_proveedor BIGINT)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result jsonb;
    v_total_recepciones integer := 0;
    v_valor_total_compras numeric := 0;
    v_valor_promedio_orden numeric := 0;
    v_productos_unicos integer := 0;
    v_ultima_recepcion timestamp with time zone;
    v_lead_time_promedio numeric;
BEGIN
    -- Obtener métricas de recepciones
    SELECT 
        COUNT(*) as total,
        COALESCE(SUM(rp.cantidad * rp.costo_unitario), 0) as valor_total,
        MAX(o.created_at) as ultima_fecha
    INTO v_total_recepciones, v_valor_total_compras, v_ultima_recepcion
    FROM app_dat_recepcion_productos rp
    INNER JOIN app_dat_operaciones o ON rp.id_operacion = o.id
    WHERE rp.id_proveedor = p_id_proveedor;
    
    -- Calcular valor promedio por orden
    IF v_total_recepciones > 0 THEN
        v_valor_promedio_orden := v_valor_total_compras / v_total_recepciones;
    END IF;
    
    -- Obtener productos únicos suministrados
    SELECT COUNT(DISTINCT rp.id_producto)
    INTO v_productos_unicos
    FROM app_dat_recepcion_productos rp
    WHERE rp.id_proveedor = p_id_proveedor;
    
    -- Obtener lead time del proveedor
    SELECT lead_time
    INTO v_lead_time_promedio
    FROM app_dat_proveedor
    WHERE id = p_id_proveedor;
    
    -- Construir respuesta
    SELECT jsonb_build_object(
        'id_proveedor', p_id_proveedor,
        'total_recepciones', v_total_recepciones,
        'valor_total_compras', ROUND(v_valor_total_compras, 2),
        'valor_promedio_orden', ROUND(v_valor_promedio_orden, 2),
        'productos_unicos', v_productos_unicos,
        'ultima_recepcion', v_ultima_recepcion,
        'lead_time_promedio', v_lead_time_promedio,
        'performance_score', CASE 
            WHEN v_total_recepciones >= 10 THEN 'Excelente'
            WHEN v_total_recepciones >= 5 THEN 'Bueno'
            WHEN v_total_recepciones > 0 THEN 'Regular'
            ELSE 'Sin datos'
        END
    ) INTO v_result;
    
    RETURN v_result;
END;
$$;

-- 2. Función para obtener top proveedores
CREATE OR REPLACE FUNCTION fn_top_proveedores(
    p_fecha_desde timestamp with time zone DEFAULT NULL,
    p_fecha_hasta timestamp with time zone DEFAULT NULL,
    p_limite integer DEFAULT 10
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result jsonb;
BEGIN
    WITH proveedor_stats AS (
        SELECT 
            p.id,
            p.denominacion,
            p.sku_codigo,
            p.ubicacion,
            COUNT(rp.id) as total_recepciones,
            COALESCE(SUM(rp.cantidad * rp.costo_unitario), 0) as valor_total,
            COUNT(DISTINCT rp.id_producto) as productos_unicos,
            MAX(o.created_at) as ultima_recepcion
        FROM app_dat_proveedor p
        LEFT JOIN app_dat_recepcion_productos rp ON p.id = rp.id_proveedor
        LEFT JOIN app_dat_operaciones o ON rp.id_operacion = o.id
        WHERE (p_fecha_desde IS NULL OR o.created_at >= p_fecha_desde)
          AND (p_fecha_hasta IS NULL OR o.created_at <= p_fecha_hasta)
        GROUP BY p.id, p.denominacion, p.sku_codigo, p.ubicacion
        HAVING COUNT(rp.id) > 0
        ORDER BY valor_total DESC, total_recepciones DESC
        LIMIT p_limite
    )
    SELECT jsonb_agg(
        jsonb_build_object(
            'id', ps.id,
            'denominacion', ps.denominacion,
            'sku_codigo', ps.sku_codigo,
            'ubicacion', ps.ubicacion,
            'total_recepciones', ps.total_recepciones,
            'valor_total', ROUND(ps.valor_total, 2),
            'productos_unicos', ps.productos_unicos,
            'ultima_recepcion', ps.ultima_recepcion,
            'valor_promedio_orden', CASE 
                WHEN ps.total_recepciones > 0 
                THEN ROUND(ps.valor_total / ps.total_recepciones, 2)
                ELSE 0
            END
        )
    )
    INTO v_result
    FROM proveedor_stats ps;
    
    RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

-- 3. Función para dashboard de proveedores
CREATE OR REPLACE FUNCTION fn_dashboard_proveedores(p_id_tienda BIGINT DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result jsonb;
    v_total_proveedores integer := 0;
    v_proveedores_activos integer := 0;
    v_lead_time_promedio numeric := 0;
    v_valor_total_mes numeric := 0;
BEGIN
    -- Total de proveedores
    SELECT COUNT(*) INTO v_total_proveedores FROM app_dat_proveedor;
    
    -- Proveedores activos (con recepciones en los últimos 90 días)
    SELECT COUNT(DISTINCT rp.id_proveedor)
    INTO v_proveedores_activos
    FROM app_dat_recepcion_productos rp
    INNER JOIN app_dat_operaciones o ON rp.id_operacion = o.id
    WHERE o.created_at >= (CURRENT_DATE - INTERVAL '90 days')
      AND (p_id_tienda IS NULL OR o.id_tienda = p_id_tienda);
    
    -- Lead time promedio
    SELECT AVG(lead_time)
    INTO v_lead_time_promedio
    FROM app_dat_proveedor
    WHERE lead_time IS NOT NULL;
    
    -- Valor total de compras del mes actual
    SELECT COALESCE(SUM(rp.cantidad * rp.costo_unitario), 0)
    INTO v_valor_total_mes
    FROM app_dat_recepcion_productos rp
    INNER JOIN app_dat_operaciones o ON rp.id_operacion = o.id
    WHERE DATE_TRUNC('month', o.created_at) = DATE_TRUNC('month', CURRENT_DATE)
      AND (p_id_tienda IS NULL OR o.id_tienda = p_id_tienda);
    
    -- Construir respuesta
    SELECT jsonb_build_object(
        'total_proveedores', v_total_proveedores,
        'proveedores_activos', v_proveedores_activos,
        'lead_time_promedio', ROUND(COALESCE(v_lead_time_promedio, 0), 1),
        'valor_compras_mes', ROUND(v_valor_total_mes, 2),
        'porcentaje_activos', CASE 
            WHEN v_total_proveedores > 0 
            THEN ROUND((v_proveedores_activos::numeric / v_total_proveedores) * 100, 1)
            ELSE 0
        END
    ) INTO v_result;
    
    RETURN v_result;
END;
$$;

-- 4. Función para validar eliminación de proveedor
CREATE OR REPLACE FUNCTION fn_validar_eliminacion_proveedor(p_id_proveedor BIGINT)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_recepciones_count integer := 0;
    v_inventario_count integer := 0;
BEGIN
    -- Verificar recepciones asociadas
    SELECT COUNT(*) INTO v_recepciones_count
    FROM app_dat_recepcion_productos
    WHERE id_proveedor = p_id_proveedor;
    
    -- Verificar inventario asociado
    SELECT COUNT(*) INTO v_inventario_count
    FROM app_dat_inventario_productos
    WHERE id_proveedor = p_id_proveedor;
    
    RETURN jsonb_build_object(
        'puede_eliminar', (v_recepciones_count = 0 AND v_inventario_count = 0),
        'recepciones_asociadas', v_recepciones_count,
        'inventario_asociado', v_inventario_count,
        'mensaje', CASE 
            WHEN v_recepciones_count > 0 OR v_inventario_count > 0 
            THEN 'No se puede eliminar el proveedor porque tiene registros asociados'
            ELSE 'El proveedor puede ser eliminado'
        END
    );
END;
$$;

-- 5. Función para buscar proveedores
CREATE OR REPLACE FUNCTION fn_buscar_proveedores(
    p_termino_busqueda text,
    p_limite integer DEFAULT 50
)
RETURNS TABLE (
    id bigint,
    denominacion character varying,
    direccion character varying,
    ubicacion character varying,
    sku_codigo character varying,
    lead_time integer,
    created_at timestamp with time zone,
    total_recepciones bigint,
    valor_total_compras numeric,
    ultima_recepcion timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.id,
        p.denominacion,
        p.direccion,
        p.ubicacion,
        p.sku_codigo,
        p.lead_time,
        p.created_at,
        COUNT(rp.id) as total_recepciones,
        COALESCE(SUM(rp.cantidad * rp.costo_unitario), 0) as valor_total_compras,
        MAX(o.created_at) as ultima_recepcion
    FROM app_dat_proveedor p
    LEFT JOIN app_dat_recepcion_productos rp ON p.id = rp.id_proveedor
    LEFT JOIN app_dat_operaciones o ON rp.id_operacion = o.id
    WHERE (p_termino_busqueda IS NULL OR p_termino_busqueda = '' OR
           p.denominacion ILIKE '%' || p_termino_busqueda || '%' OR
           p.sku_codigo ILIKE '%' || p_termino_busqueda || '%' OR
           p.ubicacion ILIKE '%' || p_termino_busqueda || '%')
    GROUP BY p.id, p.denominacion, p.direccion, p.ubicacion, p.sku_codigo, p.lead_time, p.created_at
    ORDER BY p.denominacion
    LIMIT p_limite;
END;
$$;

-- =====================================================
-- PERMISOS Y COMENTARIOS
-- =====================================================

-- Agregar comentarios a las funciones
COMMENT ON FUNCTION fn_metricas_proveedor(BIGINT) IS 'Obtiene métricas detalladas de un proveedor específico';
COMMENT ON FUNCTION fn_top_proveedores(timestamp with time zone, timestamp with time zone, integer) IS 'Obtiene los top proveedores por valor de compras en un período';
COMMENT ON FUNCTION fn_dashboard_proveedores(BIGINT) IS 'Obtiene métricas generales de proveedores para dashboard';
COMMENT ON FUNCTION fn_validar_eliminacion_proveedor(BIGINT) IS 'Valida si un proveedor puede ser eliminado';
COMMENT ON FUNCTION fn_buscar_proveedores(text, integer) IS 'Busca proveedores por término de búsqueda con métricas';
