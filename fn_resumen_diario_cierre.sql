CREATE OR REPLACE FUNCTION fn_resumen_diario_cierre(
    id_tpv_param BIGINT DEFAULT NULL,
    id_usuario_param UUID DEFAULT NULL
)
RETURNS TABLE (
    ventas_totales NUMERIC,
    efectivo_inicial NUMERIC,
    efectivo_real NUMERIC,
    efectivo_esperado NUMERIC,
    productos_vendidos INTEGER,
    ticket_promedio NUMERIC,
    porcentaje_efectivo NUMERIC,
    porcentaje_otros NUMERIC,
    operaciones_totales INTEGER,
    operaciones_por_hora NUMERIC,
    promedio_operaciones_por_hora NUMERIC,
    conciliacion_estado TEXT,
    efectivo_real_ajustado NUMERIC,
    diferencia_ajustada NUMERIC,
    turno_id BIGINT,
    fecha_apertura TIMESTAMPTZ,
    horas_transcurridas NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_uuid_usuario UUID;
    v_turno_abierto RECORD;
    v_ventas_totales NUMERIC := 0;
    v_efectivo_inicial NUMERIC := 0;
    v_efectivo_real NUMERIC := 0;
    v_efectivo_esperado NUMERIC := 0;
    v_productos_vendidos INTEGER := 0;
    v_ticket_promedio NUMERIC := 0;
    v_porcentaje_efectivo NUMERIC := 0;
    v_porcentaje_otros NUMERIC := 0;
    v_operaciones_totales INTEGER := 0;
    v_operaciones_por_hora NUMERIC := 0;
    v_promedio_operaciones_por_hora NUMERIC := 0;
    v_conciliacion_estado TEXT := 'Sin turno abierto';
    v_efectivo_real_ajustado NUMERIC := 0;
    v_diferencia_ajustada NUMERIC := 0;
    v_horas_transcurridas NUMERIC := 0;
    v_total_efectivo NUMERIC := 0;
    v_total_otros NUMERIC := 0;
    v_fecha_inicio TIMESTAMPTZ;
    v_fecha_fin TIMESTAMPTZ;
BEGIN
    -- Establecer contexto
    SET search_path = public;
    
    -- Obtener el usuario autenticado
    v_uuid_usuario := COALESCE(id_usuario_param, auth.uid());
    
    -- Establecer filtros de fecha diaria (00:00:00 a 23:59:59)
    v_fecha_inicio := DATE_TRUNC('day', NOW());
    v_fecha_fin := DATE_TRUNC('day', NOW()) + INTERVAL '1 day' - INTERVAL '1 second';
    
    -- Verificar permisos
    PERFORM check_user_has_access_to_any_tienda();
    
    -- Buscar el turno abierto del vendedor en el TPV especificado
    SELECT 
        ct.id,
        ct.fecha_apertura,
        ct.efectivo_inicial,
        ct.efectivo_esperado,
        ct.efectivo_real,
        ct.estado,
        EXTRACT(EPOCH FROM (NOW() - ct.fecha_apertura)) / 3600 AS horas_transcurridas
    INTO v_turno_abierto
    FROM app_dat_caja_turno ct
    JOIN app_dat_vendedor v ON ct.id_vendedor = v.id
    WHERE ct.id_tpv = id_tpv_param
      AND v.uuid = v_uuid_usuario
      AND ct.estado = 1 -- Abierto
    ORDER BY ct.fecha_apertura DESC
    LIMIT 1;
    
    -- Si no hay turno abierto, devolver valores por defecto
    IF NOT FOUND THEN
        RETURN QUERY SELECT 
            0::NUMERIC, 0::NUMERIC, 0::NUMERIC, 0::NUMERIC, 0::INTEGER,
            0::NUMERIC, 0::NUMERIC, 0::NUMERIC, 0::INTEGER, 0::NUMERIC,
            0::NUMERIC, 'Sin turno abierto'::TEXT, 0::NUMERIC, 0::NUMERIC,
            NULL::BIGINT, NULL::TIMESTAMPTZ, 0::NUMERIC;
        RETURN;
    END IF;
    
    -- Asignar valores del turno
    v_efectivo_inicial := COALESCE(v_turno_abierto.efectivo_inicial, 0);
    v_efectivo_esperado := COALESCE(v_turno_abierto.efectivo_esperado, 0);
    v_efectivo_real := COALESCE(v_turno_abierto.efectivo_real, 0);
    v_horas_transcurridas := COALESCE(v_turno_abierto.horas_transcurridas, 0);
    
    -- Calcular ventas totales y productos vendidos desde la apertura del turno
    SELECT 
        COALESCE(SUM(ep.importe), 0),
        COALESCE(SUM(ep.cantidad)::INTEGER, 0),
        COUNT(DISTINCT o.id)::INTEGER
    INTO 
        v_ventas_totales,
        v_productos_vendidos,
        v_operaciones_totales
    FROM app_dat_operaciones o
    JOIN app_dat_operacion_venta ov ON o.id = ov.id_operacion
    JOIN app_dat_extraccion_productos ep ON o.id = ep.id_operacion
    JOIN app_dat_estado_operacion eo ON o.id = eo.id_operacion
    WHERE ov.id_tpv = id_tpv_param
      AND o.uuid = v_uuid_usuario -- Filtro por usuario
      AND o.created_at >= GREATEST(v_turno_abierto.fecha_apertura, v_fecha_inicio)
      AND o.created_at <= v_fecha_fin -- Filtro diario hasta 23:59:59
      AND eo.estado IN (2) -- Solo operaciones completadas
      AND eo.id = (SELECT MAX(id) FROM app_dat_estado_operacion WHERE id_operacion = o.id);
    
    -- Calcular totales por medio de pago
    SELECT 
        COALESCE(SUM(CASE WHEN pv.id_medio_pago = 1 THEN pv.monto ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN pv.id_medio_pago != 1 THEN pv.monto ELSE 0 END), 0)
    INTO 
        v_total_efectivo,
        v_total_otros
    FROM app_dat_operaciones o
    JOIN app_dat_operacion_venta ov ON o.id = ov.id_operacion
    JOIN app_dat_pago_venta pv ON ov.id_operacion = pv.id_operacion_venta
    JOIN app_dat_estado_operacion eo ON o.id = eo.id_operacion
    WHERE ov.id_tpv = id_tpv_param
      AND o.uuid = v_uuid_usuario -- Filtro por usuario
      AND o.created_at >= GREATEST(v_turno_abierto.fecha_apertura, v_fecha_inicio)
      AND o.created_at <= v_fecha_fin -- Filtro diario hasta 23:59:59
      AND eo.estado IN (2) -- Solo operaciones completadas
      AND eo.id = (SELECT MAX(id) FROM app_dat_estado_operacion WHERE id_operacion = o.id);
    
    -- Calcular efectivo real basado en pagos en efectivo + efectivo inicial
    v_efectivo_real := v_efectivo_inicial + v_total_efectivo;
    
    -- Por ahora, efectivo esperado es igual al efectivo real
    v_efectivo_esperado := v_efectivo_real;
    
    -- Calcular porcentajes
    IF v_ventas_totales > 0 THEN
        v_porcentaje_efectivo := ROUND((v_total_efectivo / v_ventas_totales) * 100, 2);
        v_porcentaje_otros := ROUND((v_total_otros / v_ventas_totales) * 100, 2);
    END IF;
    
    -- Calcular ticket promedio
    IF v_operaciones_totales > 0 THEN
        v_ticket_promedio := ROUND(v_ventas_totales / v_operaciones_totales, 2);
    END IF;
    
    -- Calcular operaciones por hora
    IF v_horas_transcurridas > 0 THEN
        v_operaciones_por_hora := ROUND(v_operaciones_totales / v_horas_transcurridas, 2);
        v_promedio_operaciones_por_hora := v_operaciones_por_hora; -- Por ahora son iguales
    END IF;
    
    -- Determinar estado de conciliación
    CASE
        WHEN v_turno_abierto.estado = 1 THEN v_conciliacion_estado := 'Abierto';
        WHEN v_turno_abierto.diferencia IS NULL OR v_turno_abierto.diferencia = 0 THEN v_conciliacion_estado := 'Conciliado';
        WHEN ABS(COALESCE(v_turno_abierto.diferencia, 0)) <= 1.00 THEN v_conciliacion_estado := 'Casi exacto (≤ $1)';
        WHEN COALESCE(v_turno_abierto.diferencia, 0) > 0 THEN v_conciliacion_estado := 'Sobrante';
        ELSE v_conciliacion_estado := 'Falta';
    END CASE;
    
    -- Por ahora, valores ajustados son iguales a los reales
    v_efectivo_real_ajustado := v_efectivo_real;
    v_diferencia_ajustada := v_efectivo_real - v_efectivo_esperado;
    
    -- Devolver el resultado
    RETURN QUERY SELECT 
        v_ventas_totales,
        v_efectivo_inicial,
        v_efectivo_real,
        v_efectivo_esperado,
        v_productos_vendidos,
        v_ticket_promedio,
        v_porcentaje_efectivo,
        v_porcentaje_otros,
        v_operaciones_totales,
        v_operaciones_por_hora,
        v_promedio_operaciones_por_hora,
        v_conciliacion_estado,
        v_efectivo_real_ajustado,
        v_diferencia_ajustada,
        v_turno_abierto.id,
        v_turno_abierto.fecha_apertura,
        v_horas_transcurridas;
        
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error en fn_resumen_diario_cierre: %', SQLERRM;
END;
$$;

-- Comentarios sobre la función
COMMENT ON FUNCTION fn_resumen_diario_cierre IS 'Función para obtener el resumen diario completo para el cierre de turno';

-- Ejemplo de uso:
-- SELECT * FROM fn_resumen_diario_cierre(1, NULL);
