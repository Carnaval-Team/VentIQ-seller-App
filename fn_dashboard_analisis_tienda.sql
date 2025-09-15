CREATE OR REPLACE FUNCTION fn_dashboard_analisis_tienda(
    p_id_tienda BIGINT,
    p_periodo TEXT DEFAULT '1 mes'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_fecha_inicio TIMESTAMPTZ;
    v_fecha_fin TIMESTAMPTZ;
    v_fecha_inicio_anterior TIMESTAMPTZ;
    v_fecha_fin_anterior TIMESTAMPTZ;
    v_resultado JSONB;
    v_ventas_totales NUMERIC := 0;
    v_ventas_totales_anterior NUMERIC := 0;
    v_total_productos BIGINT := 0;
    v_productos_sin_stock BIGINT := 0;
    v_total_ordenes BIGINT := 0;
    v_total_gastos NUMERIC := 0;
    v_tendencias_venta JSONB;
    v_total_prod_categoria JSONB;
    v_estado_inventario JSONB;
BEGIN
    -- Establecer contexto
    SET search_path = public;
    
    -- Verificar permisos
    PERFORM check_user_has_access_to_any_tienda();
    
    -- Calcular fechas según el periodo con horas específicas
    v_fecha_fin := DATE_TRUNC('day', NOW()) + INTERVAL '23 hours 59 minutes 59 seconds';
    
    v_fecha_inicio := CASE 
        WHEN p_periodo = '5 años' THEN DATE_TRUNC('day', v_fecha_fin - INTERVAL '5 years')
        WHEN p_periodo = '3 años' THEN DATE_TRUNC('day', v_fecha_fin - INTERVAL '3 years')
        WHEN p_periodo = '1 año' THEN DATE_TRUNC('day', v_fecha_fin - INTERVAL '1 year')
        WHEN p_periodo = '6 meses' THEN DATE_TRUNC('day', v_fecha_fin - INTERVAL '6 months')
        WHEN p_periodo = '3 meses' THEN DATE_TRUNC('day', v_fecha_fin - INTERVAL '3 months')
        WHEN p_periodo = '1 mes' THEN DATE_TRUNC('day', v_fecha_fin - INTERVAL '1 month')
        WHEN p_periodo = 'Semana' THEN DATE_TRUNC('day', v_fecha_fin - INTERVAL '1 week')
        WHEN p_periodo = 'Día' THEN DATE_TRUNC('day', v_fecha_fin)
        ELSE DATE_TRUNC('day', v_fecha_fin - INTERVAL '1 month')  -- Valor por defecto
    END;

    -- Para período "Día", ajustar fecha_fin al final del día actual
    IF p_periodo = 'Día' THEN
        v_fecha_fin := DATE_TRUNC('day', NOW()) + INTERVAL '23 hours 59 minutes 59 seconds';
    END IF;

    -- Calcular fechas del período anterior para comparación
    v_fecha_fin_anterior := v_fecha_inicio - INTERVAL '1 second';
    v_fecha_inicio_anterior := v_fecha_inicio - (v_fecha_fin - v_fecha_inicio);

    -- Ventas Totales del período actual (todos los usuarios de la tienda)
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
      AND o.created_at BETWEEN v_fecha_inicio AND v_fecha_fin
      AND eo.estado IN (2) -- Solo operaciones completadas
      AND eo.id = (SELECT MAX(id) FROM app_dat_estado_operacion WHERE id_operacion = o.id);

    -- Ventas Totales del período anterior
    SELECT COALESCE(SUM(ep.importe), 0)
    INTO v_ventas_totales_anterior
    FROM app_dat_operaciones o
    JOIN app_dat_operacion_venta ov ON o.id = ov.id_operacion
    JOIN app_dat_extraccion_productos ep ON o.id = ep.id_operacion
    JOIN app_dat_estado_operacion eo ON o.id = eo.id_operacion
    WHERE o.id_tienda = p_id_tienda 
      AND o.created_at BETWEEN v_fecha_inicio_anterior AND v_fecha_fin_anterior
      AND eo.estado IN (2) -- Solo operaciones completadas
      AND eo.id = (SELECT MAX(id) FROM app_dat_estado_operacion WHERE id_operacion = o.id);

    -- Total de Productos e Inventario
    SELECT 
        COUNT(DISTINCT p.id),
        COUNT(DISTINCT p.id) FILTER (WHERE COALESCE(i.cantidad_final, 0) <= 0)
    INTO 
        v_total_productos, 
        v_productos_sin_stock
    FROM app_dat_producto p
    LEFT JOIN app_dat_inventario_productos i ON p.id = i.id_producto
    WHERE p.id_tienda = p_id_tienda;

    -- Total de Gastos (usando tabla de gastos si existe, sino usar egresos)
    BEGIN
        SELECT COALESCE(SUM(monto), 0)
        INTO v_total_gastos
        FROM app_cont_gastos
        WHERE id_tienda = p_id_tienda 
          AND fecha BETWEEN v_fecha_inicio AND v_fecha_fin;
    EXCEPTION
        WHEN OTHERS THEN
            -- Si no existe la tabla de gastos, usar egresos
            SELECT COALESCE(SUM(monto_entrega), 0)
            INTO v_total_gastos
            FROM app_dat_entrega_efectivo
            WHERE id_tienda = p_id_tienda 
              AND fecha_entrega BETWEEN v_fecha_inicio AND v_fecha_fin;
    END;

    -- Tendencias de Venta (basado en operaciones reales)
    WITH ventas_agrupadas AS (
        SELECT 
            CASE 
                WHEN p_periodo IN ('5 años', '3 años', '1 año') THEN 
                    TO_CHAR(o.created_at, 'YYYY-MM')
                WHEN p_periodo IN ('6 meses', '3 meses', '1 mes') THEN 
                    TO_CHAR(o.created_at, 'YYYY-MM-DD')
                WHEN p_periodo = 'Semana' THEN 
                    TO_CHAR(o.created_at, 'YYYY-MM-DD')
                WHEN p_periodo = 'Día' THEN 
                    TO_CHAR(o.created_at, 'YYYY-MM-DD HH24')
            END AS x_axis,
            COALESCE(SUM(ep.importe), 0) AS total_ventas
        FROM app_dat_operaciones o
        JOIN app_dat_operacion_venta ov ON o.id = ov.id_operacion
        JOIN app_dat_extraccion_productos ep ON o.id = ep.id_operacion
        JOIN app_dat_estado_operacion eo ON o.id = eo.id_operacion
        WHERE o.id_tienda = p_id_tienda 
          AND o.created_at BETWEEN v_fecha_inicio AND v_fecha_fin
          AND eo.estado IN (2) -- Solo operaciones completadas
          AND eo.id = (SELECT MAX(id) FROM app_dat_estado_operacion WHERE id_operacion = o.id)
        GROUP BY x_axis
        ORDER BY x_axis
    )
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'x_axis', x_axis,
            'value', total_ventas
        )
    ), '[]'::jsonb)
    INTO v_tendencias_venta
    FROM ventas_agrupadas;

    -- Total de Productos por Categoría
    WITH productos_por_categoria AS (
        SELECT 
            COALESCE(c.denominacion, 'Sin Categoría') AS name,
            COUNT(DISTINCT p.id) AS total_product
        FROM app_dat_producto p
        LEFT JOIN app_dat_categoria c ON p.id_categoria = c.id
        WHERE p.id_tienda = p_id_tienda
        GROUP BY c.denominacion
        HAVING COUNT(DISTINCT p.id) > 0
    )
    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'name', name,
            'total_product', total_product
        )
    ), '[]'::jsonb)
    INTO v_total_prod_categoria
    FROM productos_por_categoria;

    -- Estado de Inventario
    WITH estado_inventario AS (
        SELECT 
            COUNT(DISTINCT p.id) FILTER (WHERE COALESCE(i.cantidad_final, 0) = 0) AS productos_sin_stock,
            COUNT(DISTINCT p.id) FILTER (WHERE COALESCE(i.cantidad_final, 0) > 0 AND COALESCE(i.cantidad_final, 0) <= 10) AS stock_bajo,
            COUNT(DISTINCT p.id) FILTER (WHERE COALESCE(i.cantidad_final, 0) > 10) AS stock_ok
        FROM app_dat_producto p
        LEFT JOIN app_dat_inventario_productos i ON p.id = i.id_producto
        WHERE p.id_tienda = p_id_tienda
    )
    SELECT jsonb_build_object(
        'productos_sin_stock', COALESCE(productos_sin_stock, 0),
        'stock_bajo', COALESCE(stock_bajo, 0),
        'stock_ok', COALESCE(stock_ok, 0)
    )
    INTO v_estado_inventario
    FROM estado_inventario;

    -- Construir resultado final con la misma estructura que obtener_analisis_tienda
    v_resultado := jsonb_build_object(
        'ventas_totales', COALESCE(v_ventas_totales, 0),
        'ventas_totales_anterior', COALESCE(v_ventas_totales_anterior, 0),
        'total_de_productos', COALESCE(v_total_productos, 0),
        'total_productos_no_stock', COALESCE(v_productos_sin_stock, 0),
        'total_ordenes', COALESCE(v_total_ordenes, 0),
        'total_gastos', COALESCE(v_total_gastos, 0),
        'tendencias_de_venta', COALESCE(v_tendencias_venta, '[]'::jsonb),
        'total_prod_categoria', COALESCE(v_total_prod_categoria, '[]'::jsonb),
        'estado_inventario', COALESCE(v_estado_inventario, '{}'::jsonb)
    );

    RETURN v_resultado;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error en fn_dashboard_analisis_tienda: %', SQLERRM;
END;
$$;
