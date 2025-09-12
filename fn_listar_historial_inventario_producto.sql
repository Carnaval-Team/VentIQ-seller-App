CREATE OR REPLACE FUNCTION fn_listar_historial_inventario_producto(
    p_id_producto BIGINT,
    p_dias INTEGER DEFAULT 30
)
RETURNS TABLE (
    id BIGINT,
    tipo_operacion TEXT,
    fecha TIMESTAMPTZ,
    cantidad NUMERIC,
    stock_inicial NUMERIC,
    stock_final NUMERIC,
    cantidad_anterior NUMERIC,
    cantidad_nueva NUMERIC,
    precio_unitario NUMERIC,
    importe NUMERIC,
    usuario TEXT,
    documento TEXT,
    observaciones TEXT,
    proveedor TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id_tienda BIGINT;
    v_fecha_limite TIMESTAMPTZ;
BEGIN
    -- Calcular fecha límite
    v_fecha_limite := NOW() - INTERVAL '1 day' * p_dias;
    
    -- Obtener la tienda del producto y validar acceso del usuario
    SELECT p.id_tienda INTO v_id_tienda
    FROM app_dat_producto p
    WHERE p.id = p_id_producto;
    
    IF v_id_tienda IS NULL THEN
        RAISE EXCEPTION 'Producto no encontrado';
    END IF;

    -- Validar que el usuario tenga acceso a la tienda del producto
    IF NOT EXISTS (
        SELECT 1 FROM (
            SELECT g.id_tienda FROM app_dat_gerente g WHERE g.uuid = auth.uid()
            UNION
            SELECT s.id_tienda FROM app_dat_supervisor s WHERE s.uuid = auth.uid()
            UNION
            SELECT a.id_tienda FROM app_dat_almacenero al 
            JOIN app_dat_almacen a ON al.id_almacen = a.id 
            WHERE al.uuid = auth.uid()
            UNION
            SELECT tpv.id_tienda FROM app_dat_vendedor v 
            JOIN app_dat_tpv tpv ON v.id_tpv = tpv.id 
            WHERE v.uuid = auth.uid()
        ) accesos
        WHERE accesos.id_tienda = v_id_tienda
    ) THEN
        RAISE EXCEPTION 'No tiene acceso a la tienda del producto especificado';
    END IF;

    -- Retornar todas las operaciones de inventario del producto en los últimos días
    RETURN QUERY
    WITH operaciones_producto AS (
        -- Operaciones de recepción (entrada de stock)
        SELECT 
            o.id,
            'Recepción' as tipo_operacion,
            o.created_at as fecha,
            rp.cantidad,
            rp.precio_unitario,
            (rp.cantidad * rp.precio_unitario) as importe,
            'Sistema' as usuario, 
            ('REC-' || o.id::TEXT) as documento,
            COALESCE(o.observaciones, '') as observaciones,
            COALESCE(orp.entregado_por, 'No especificado') as proveedor
        FROM app_dat_operaciones o
        INNER JOIN app_nom_tipo_operacion top ON o.id_tipo_operacion = top.id
        INNER JOIN app_dat_recepcion_productos rp ON o.id = rp.id_operacion
        LEFT JOIN app_dat_operacion_recepcion orp ON o.id = orp.id_operacion
        WHERE rp.id_producto = p_id_producto
            AND top.denominacion ILIKE '%recepcion%'
            AND o.created_at >= v_fecha_limite
            AND o.id_tienda = v_id_tienda
        
        UNION ALL
        
        -- Operaciones de extracción (salida de stock)
        SELECT 
            o.id,
            CASE 
                WHEN top.denominacion ILIKE '%venta%' THEN 'Venta'
                WHEN top.denominacion ILIKE '%extraccion%' THEN 'Extracción'
                ELSE 'Salida'
            END as tipo_operacion,
            o.created_at as fecha,
            -ep.cantidad as cantidad, 
            ep.precio_unitario,
            (ep.cantidad * ep.precio_unitario) as importe,
            'Sistema' as usuario, 
            CASE 
                WHEN top.denominacion ILIKE '%venta%' THEN 'VEN-' || o.id::TEXT
                ELSE 'EXT-' || o.id::TEXT
            END as documento,
            COALESCE(o.observaciones, '') as observaciones,
            CASE 
                WHEN top.denominacion ILIKE '%venta%' THEN 'Cliente'
                ELSE 'Interno'
            END as proveedor
        FROM app_dat_operaciones o
        INNER JOIN app_nom_tipo_operacion top ON o.id_tipo_operacion = top.id
        INNER JOIN app_dat_extraccion_productos ep ON o.id = ep.id_operacion
        WHERE ep.id_producto = p_id_producto
            AND o.created_at >= v_fecha_limite
            AND o.id_tienda = v_id_tienda
    ),
    operaciones_con_stock AS (
        SELECT 
            op.*,
            -- Calcular stock acumulado usando window function con cantidades con signo correcto
            SUM(CASE 
                WHEN op.tipo_operacion = 'Recepción' THEN op.cantidad 
                ELSE -op.cantidad 
            END) OVER (ORDER BY op.fecha, op.id ROWS UNBOUNDED PRECEDING) as stock_acumulado,
            -- Stock inicial es el stock antes de esta operación
            COALESCE(SUM(CASE 
                WHEN op.tipo_operacion = 'Recepción' THEN op.cantidad 
                ELSE -op.cantidad 
            END) OVER (ORDER BY op.fecha, op.id ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) as stock_inicial
        FROM operaciones_producto op
    )
    SELECT 
        ops.id::BIGINT,
        ops.tipo_operacion::TEXT,
        ops.fecha::TIMESTAMPTZ,
        ops.cantidad::NUMERIC as cantidad,
        ops.stock_inicial::NUMERIC,
        ops.stock_acumulado::NUMERIC as stock_final,
        0::NUMERIC as cantidad_anterior,
        ops.cantidad::NUMERIC as cantidad_nueva,
        ops.precio_unitario::NUMERIC,
        ops.importe::NUMERIC,
        ops.usuario::TEXT,
        ops.documento::TEXT,
        ops.observaciones::TEXT,
        ops.proveedor::TEXT
    FROM operaciones_con_stock ops
    ORDER BY ops.fecha DESC;
END;
$$;

CREATE OR REPLACE FUNCTION fn_listar_historial_inventario_producto_v2(
    p_id_producto BIGINT,
    p_dias INTEGER DEFAULT 30
)
RETURNS TABLE (
    id BIGINT,
    tipo_operacion TEXT,
    fecha TIMESTAMPTZ,
    cantidad NUMERIC,
    stock_inicial NUMERIC,
    stock_final NUMERIC,
    precio_unitario NUMERIC,
    importe NUMERIC,
    usuario TEXT,
    documento TEXT,
    observaciones TEXT,
    proveedor TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_id_tienda BIGINT;
    v_fecha_limite TIMESTAMPTZ;
BEGIN
    -- Calcular fecha límite
    v_fecha_limite := NOW() - INTERVAL '1 day' * p_dias;
    
    -- Obtener la tienda del producto y validar acceso del usuario
    SELECT p.id_tienda INTO v_id_tienda
    FROM app_dat_producto p
    WHERE p.id = p_id_producto;
    
    IF v_id_tienda IS NULL THEN
        RAISE EXCEPTION 'Producto no encontrado';
    END IF;

    -- Validar que el usuario tenga acceso a la tienda del producto
    IF NOT EXISTS (
        SELECT 1 FROM (
            SELECT g.id_tienda FROM app_dat_gerente g WHERE g.uuid = auth.uid()
            UNION
            SELECT s.id_tienda FROM app_dat_supervisor s WHERE s.uuid = auth.uid()
            UNION
            SELECT a.id_tienda FROM app_dat_almacenero al 
            JOIN app_dat_almacen a ON al.id_almacen = a.id 
            WHERE al.uuid = auth.uid()
            UNION
            SELECT tpv.id_tienda FROM app_dat_vendedor v 
            JOIN app_dat_tpv tpv ON v.id_tpv = tpv.id 
            WHERE v.uuid = auth.uid()
        ) accesos
        WHERE accesos.id_tienda = v_id_tienda
    ) THEN
        RAISE EXCEPTION 'No tiene acceso a la tienda del producto especificado';
    END IF;

    -- Retornar todas las operaciones de inventario del producto en los últimos días
    RETURN QUERY
    WITH operaciones_producto AS (
        -- Operaciones de recepción (entrada de stock)
        SELECT 
            o.id,
            'Recepción' as tipo_operacion,
            o.created_at as fecha,
            rp.cantidad,
            rp.precio_unitario,
            (rp.cantidad * rp.precio_unitario) as importe,
            'Sistema' as usuario, 
            ('REC-' || o.id::TEXT) as documento,
            COALESCE(o.observaciones, '') as observaciones,
            COALESCE(orp.entregado_por, 'No especificado') as proveedor
        FROM app_dat_operaciones o
        INNER JOIN app_nom_tipo_operacion top ON o.id_tipo_operacion = top.id
        INNER JOIN app_dat_recepcion_productos rp ON o.id = rp.id_operacion
        LEFT JOIN app_dat_operacion_recepcion orp ON o.id = orp.id_operacion
        WHERE rp.id_producto = p_id_producto
            AND top.denominacion ILIKE '%recepcion%'
            AND o.created_at >= v_fecha_limite
            AND o.id_tienda = v_id_tienda
        
        UNION ALL
        
        -- Operaciones de extracción (salida de stock)
        SELECT 
            o.id,
            CASE 
                WHEN top.denominacion ILIKE '%venta%' THEN 'Venta'
                WHEN top.denominacion ILIKE '%extraccion%' THEN 'Extracción'
                ELSE 'Salida'
            END as tipo_operacion,
            o.created_at as fecha,
            -ep.cantidad as cantidad, 
            ep.precio_unitario,
            (ep.cantidad * ep.precio_unitario) as importe,
            'Sistema' as usuario, 
            CASE 
                WHEN top.denominacion ILIKE '%venta%' THEN 'VEN-' || o.id::TEXT
                ELSE 'EXT-' || o.id::TEXT
            END as documento,
            COALESCE(o.observaciones, '') as observaciones,
            CASE 
                WHEN top.denominacion ILIKE '%venta%' THEN 'Cliente'
                ELSE 'Interno'
            END as proveedor
        FROM app_dat_operaciones o
        INNER JOIN app_nom_tipo_operacion top ON o.id_tipo_operacion = top.id
        INNER JOIN app_dat_extraccion_productos ep ON o.id = ep.id_operacion
        WHERE ep.id_producto = p_id_producto
            AND o.created_at >= v_fecha_limite
            AND o.id_tienda = v_id_tienda
    ),
    operaciones_con_stock AS (
        SELECT 
            op.*,
            -- Calcular stock acumulado usando window function con cantidades con signo correcto
            SUM(CASE 
                WHEN op.tipo_operacion = 'Recepción' THEN op.cantidad 
                ELSE -op.cantidad 
            END) OVER (ORDER BY op.fecha, op.id ROWS UNBOUNDED PRECEDING) as stock_acumulado,
            -- Stock inicial es el stock antes de esta operación
            COALESCE(SUM(CASE 
                WHEN op.tipo_operacion = 'Recepción' THEN op.cantidad 
                ELSE -op.cantidad 
            END) OVER (ORDER BY op.fecha, op.id ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) as stock_inicial
        FROM operaciones_producto op
    )
    SELECT 
        ops.id::BIGINT,
        ops.tipo_operacion::TEXT,
        ops.fecha::TIMESTAMPTZ,
        ops.cantidad::NUMERIC,
        ops.stock_inicial::NUMERIC,
        ops.stock_acumulado::NUMERIC as stock_final,
        ops.precio_unitario::NUMERIC,
        ops.importe::NUMERIC,
        ops.usuario::TEXT,
        ops.documento::TEXT,
        ops.observaciones::TEXT,
        ops.proveedor::TEXT
    FROM operaciones_con_stock ops
    ORDER BY ops.fecha DESC;
END;
$$;

-- Función para detectar inconsistencias en el histórico de stock
CREATE OR REPLACE FUNCTION fn_detectar_inconsistencias_stock(
    p_id_producto BIGINT,
    p_dias INTEGER DEFAULT 30
)
RETURNS TABLE (
    operacion_id BIGINT,
    operacion_numero INTEGER,
    tipo_operacion TEXT,
    fecha TIMESTAMPTZ,
    cantidad NUMERIC,
    stock_inicial_actual NUMERIC,
    stock_final_anterior NUMERIC,
    diferencia NUMERIC,
    documento TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    WITH operaciones_ordenadas AS (
        SELECT 
            ops.id,
            ops.tipo_operacion,
            ops.fecha,
            ops.cantidad,
            ops.stock_inicial,
            ops.stock_final,
            ops.documento,
            ROW_NUMBER() OVER (ORDER BY ops.fecha, ops.id) as operacion_numero,
            LAG(ops.stock_final) OVER (ORDER BY ops.fecha, ops.id) as stock_final_anterior
        FROM fn_listar_historial_inventario_producto_v2(p_id_producto, p_dias) ops
    )
    SELECT 
        ord.id::BIGINT,
        ord.operacion_numero::INTEGER,
        ord.tipo_operacion::TEXT,
        ord.fecha::TIMESTAMPTZ,
        ord.cantidad::NUMERIC,
        ord.stock_inicial::NUMERIC,
        COALESCE(ord.stock_final_anterior, 0)::NUMERIC,
        (ord.stock_inicial - COALESCE(ord.stock_final_anterior, 0))::NUMERIC as diferencia,
        ord.documento::TEXT
    FROM operaciones_ordenadas ord
    WHERE ord.operacion_numero > 1  -- Excluir la primera operación
      AND ord.stock_inicial != COALESCE(ord.stock_final_anterior, 0)  -- Solo inconsistencias
    ORDER BY ord.fecha, ord.id;
END;
$$;
