CREATE OR REPLACE FUNCTION obtener_analisis_tienda(
    p_id_tienda INTEGER,
    p_periodo TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_uuid_usuario UUID;
    v_fecha_inicio TIMESTAMP;
    v_fecha_fin TIMESTAMP;
    v_resultado JSONB;
    v_ventas_totales NUMERIC;
    v_ventas_totales_anterior NUMERIC;
    v_total_productos BIGINT;
    v_productos_sin_stock BIGINT;
    v_total_ordenes BIGINT;
    v_total_gastos NUMERIC;
    v_tendencias_venta JSONB;
    v_total_prod_categoria JSONB;
    v_estado_inventario JSONB;
BEGIN
    -- Establecer contexto
    SET search_path = public;
    
    -- Obtener el usuario autenticado
    v_uuid_usuario := auth.uid();
    
    -- Verificar permisos
    PERFORM check_user_has_access_to_tienda(p_id_tienda);
    
    -- Calcular fechas según el periodo (usando timezone local)
    v_fecha_fin := NOW() AT TIME ZONE 'America/Havana';
    v_fecha_inicio := CASE 
        WHEN p_periodo = '5 años' THEN v_fecha_fin - INTERVAL '5 years'
        WHEN p_periodo = '3 años' THEN v_fecha_fin - INTERVAL '3 years'
        WHEN p_periodo = '1 año' THEN v_fecha_fin - INTERVAL '1 year'
        WHEN p_periodo = '6 meses' THEN v_fecha_fin - INTERVAL '6 months'
        WHEN p_periodo = '3 meses' THEN v_fecha_fin - INTERVAL '3 months'
        WHEN p_periodo = '1 mes' THEN v_fecha_fin - INTERVAL '1 month'
        WHEN p_periodo = 'Semana' THEN v_fecha_fin - INTERVAL '1 week'
        WHEN p_periodo = 'Día' THEN DATE_TRUNC('day', v_fecha_fin)
        ELSE v_fecha_fin - INTERVAL '1 month'  -- Valor por defecto
    END;

    -- Para período "Día", ajustar fecha_fin al final del día
    IF p_periodo = 'Día' THEN
        v_fecha_fin := DATE_TRUNC('day', v_fecha_fin) + INTERVAL '1 day' - INTERVAL '1 second';
    END IF;

    -- Ventas Totales (siguiendo el patrón de fn_resumen_diario_cierre)
    SELECT 
        COALESCE(SUM(ep.importe), 0),
        COUNT(DISTINCT o.id)
    INTO 
        v_ventas_totales, 
        v_total_ordenes
    FROM app_dat_operaciones o
    JOIN app_dat_operacion_venta ov ON o.id = ov.id_operacion
    JOIN app_dat_extraccion_productos ep ON o.id = ep.id_operacion
    JOIN app_dat_estado_operacion eo ON o.id = eo.id_operacion
    WHERE o.id_tienda = p_id_tienda 
      AND o.uuid = v_uuid_usuario -- Filtro por usuario como en la función correcta
      AND (o.created_at AT TIME ZONE 'America/Havana') BETWEEN v_fecha_inicio AND v_fecha_fin
      AND eo.estado IN (2) -- Solo operaciones completadas
      AND eo.id = (SELECT MAX(id) FROM app_dat_estado_operacion WHERE id_operacion = o.id);

    -- Ventas Totales del Periodo Anterior
    SELECT COALESCE(SUM(ep.importe), 0)
    INTO v_ventas_totales_anterior
    FROM app_dat_operaciones o
    JOIN app_dat_operacion_venta ov ON o.id = ov.id_operacion
    JOIN app_dat_extraccion_productos ep ON o.id = ep.id_operacion
    JOIN app_dat_estado_operacion eo ON o.id = eo.id_operacion
    WHERE o.id_tienda = p_id_tienda 
      AND o.uuid = v_uuid_usuario -- Filtro por usuario
      AND (o.created_at AT TIME ZONE 'America/Havana') BETWEEN (v_fecha_inicio - (v_fecha_fin - v_fecha_inicio)) AND v_fecha_inicio
      AND eo.estado IN (2) -- Solo operaciones completadas
      AND eo.id = (SELECT MAX(id) FROM app_dat_estado_operacion WHERE id_operacion = o.id);

    -- Total de Productos
    SELECT 
        COUNT(DISTINCT p.id),
        COUNT(DISTINCT p.id) FILTER (WHERE i.cantidad_final <= 0)
    INTO 
        v_total_productos, 
        v_productos_sin_stock
    FROM app_dat_producto p
    LEFT JOIN app_dat_inventario_productos i ON p.id = i.id_producto
    WHERE p.id_tienda = p_id_tienda;

    -- Total de Gastos (con timezone)
    SELECT COALESCE(SUM(monto), 0)
    INTO v_total_gastos
    FROM app_cont_gastos
    WHERE id_tienda = p_id_tienda 
      AND (fecha AT TIME ZONE 'America/Havana') BETWEEN v_fecha_inicio AND v_fecha_fin;

    -- Tendencias de Venta (con timezone y filtros correctos)
    WITH ventas_agrupadas AS (
        SELECT 
            CASE 
                WHEN p_periodo IN ('5 años', '3 años', '1 año') THEN 
                    TO_CHAR(o.created_at AT TIME ZONE 'America/Havana', 'YYYY-MM')
                WHEN p_periodo IN ('6 meses', '3 meses', '1 mes') THEN 
                    TO_CHAR(o.created_at AT TIME ZONE 'America/Havana', 'YYYY-MM-DD')
                WHEN p_periodo = 'Semana' THEN 
                    TO_CHAR(o.created_at AT TIME ZONE 'America/Havana', 'YYYY-MM-DD')
                WHEN p_periodo = 'Día' THEN 
                    TO_CHAR(o.created_at AT TIME ZONE 'America/Havana', 'YYYY-MM-DD HH24')
            END AS x_axis,
            COALESCE(SUM(ep.importe), 0) AS total_ventas
        FROM app_dat_operaciones o
        JOIN app_dat_operacion_venta ov ON o.id = ov.id_operacion
        JOIN app_dat_extraccion_productos ep ON o.id = ep.id_operacion
        JOIN app_dat_estado_operacion eo ON o.id = eo.id_operacion
        WHERE o.id_tienda = p_id_tienda 
          AND o.uuid = v_uuid_usuario -- Filtro por usuario
          AND (o.created_at AT TIME ZONE 'America/Havana') BETWEEN v_fecha_inicio AND v_fecha_fin
          AND eo.estado IN (2) -- Solo operaciones completadas
          AND eo.id = (SELECT MAX(id) FROM app_dat_estado_operacion WHERE id_operacion = o.id)
        GROUP BY x_axis
        ORDER BY x_axis
    )
    SELECT json_agg(
        json_build_object(
            'x_axis', x_axis,
            'value', total_ventas
        )
    )
    INTO v_tendencias_venta
    FROM ventas_agrupadas;

    -- Total de Productos por Categoría
    WITH productos_por_categoria AS (
        SELECT 
            c.denominacion AS name,
            COUNT(DISTINCT p.id) AS total_product
        FROM app_dat_producto p
        JOIN app_dat_categoria c ON p.id_categoria = c.id
        WHERE p.id_tienda = p_id_tienda
        GROUP BY c.denominacion
    )
    SELECT json_agg(
        json_build_object(
            'name', name,
            'total_product', total_product
        )
    )
    INTO v_total_prod_categoria
    FROM productos_por_categoria;

    -- Estado de Inventario
    WITH estado_inventario AS (
        SELECT 
            COUNT(DISTINCT p.id) FILTER (WHERE i.cantidad_final = 0) AS productos_sin_stock,
            COUNT(DISTINCT p.id) FILTER (WHERE i.cantidad_final > 0 AND i.cantidad_final <= 10) AS stock_bajo,
            COUNT(DISTINCT p.id) FILTER (WHERE i.cantidad_final > 10) AS stock_ok
        FROM app_dat_producto p
        LEFT JOIN app_dat_inventario_productos i ON p.id = i.id_producto
        WHERE p.id_tienda = p_id_tienda
    )
    SELECT json_build_object(
        'productos_sin_stock', productos_sin_stock,
        'stock_bajo', stock_bajo,
        'stock_ok', stock_ok
    )
    INTO v_estado_inventario
    FROM estado_inventario;

    -- Construir resultado final
    v_resultado := json_build_object(
        'ventas_totales', v_ventas_totales,
        'ventas_totales_anterior', v_ventas_totales_anterior,
        'total_de_productos', v_total_productos,
        'total_productos_no_stock', v_productos_sin_stock,
        'total_ordenes', v_total_ordenes,
        'total_gastos', v_total_gastos,
        'tendencias_de_venta', v_tendencias_venta,
        'total_prod_categoria', v_total_prod_categoria,
        'estado_inventario', v_estado_inventario
    );

    RETURN v_resultado;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error en obtener_analisis_tienda: %', SQLERRM;
END;
$$;
