-- =====================================================
-- FUNCIÓN CORREGIDA: fn_resumen_turno_kpi
-- =====================================================
-- Versión que incluye turnos abiertos (estado = 1)

CREATE OR REPLACE FUNCTION fn_resumen_turno_kpi(
  p_id_tpv INTEGER DEFAULT NULL,
  p_id_vendedor INTEGER DEFAULT NULL,
  p_fecha_desde TIMESTAMP DEFAULT NULL,
  p_fecha_hasta TIMESTAMP DEFAULT NULL
)
RETURNS TABLE (
  turno_id INTEGER,
  tpv VARCHAR,
  vendedor VARCHAR,
  fecha_apertura TIMESTAMP,
  fecha_cierre TIMESTAMP,
  duracion INTERVAL,
  estado_turno INTEGER,
  ventas_totales NUMERIC,
  productos_vendidos BIGINT,
  ticket_promedio NUMERIC,
  efectivo_inicial NUMERIC,
  efectivo_esperado NUMERIC,
  efectivo_real NUMERIC,
  diferencia_efectivo NUMERIC,
  porcentaje_efectivo NUMERIC,
  porcentaje_otros NUMERIC,
  operaciones_totales BIGINT,
  operaciones_por_hora NUMERIC,
  conciliacion_estado VARCHAR
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT
    ct.id AS turno_id,
    tpv.denominacion AS tpv,
    'vendedor p'::varchar AS vendedor,
    ct.fecha_apertura,
    ct.fecha_cierre,
    ct.fecha_cierre - ct.fecha_apertura AS duracion,
    ct.estado AS estado_turno,
    
    -- KPIs de Venta
    COALESCE(vtas.ventas_totales, 0) AS ventas_totales,
    (COALESCE(vtas.productos_vendidos, 0))::bigint AS productos_vendidos,
    CASE 
      WHEN COALESCE(vtas.operaciones_venta, 0) > 0 
      THEN vtas.ventas_totales / vtas.operaciones_venta 
      ELSE 0 
    END AS ticket_promedio,

    -- KPIs de Pago
    ct.efectivo_inicial,
    COALESCE(pagos.efectivo_esperado, ct.efectivo_inicial) AS efectivo_esperado,
    COALESCE(ct.efectivo_real, 0) AS efectivo_real,
    COALESCE(ct.efectivo_real, 0) - COALESCE(pagos.efectivo_esperado, ct.efectivo_inicial) AS diferencia_efectivo,
    
    -- Porcentaje de ventas en efectivo
    CASE 
      WHEN COALESCE(vtas.ventas_totales, 0) > 0 
      THEN COALESCE(pagos.total_efectivo, 0) * 100.0 / vtas.ventas_totales 
      ELSE 0 
    END AS porcentaje_efectivo,
    
    CASE 
      WHEN COALESCE(vtas.ventas_totales, 0) > 0 
      THEN (vtas.ventas_totales - COALESCE(pagos.total_efectivo, 0)) * 100.0 / vtas.ventas_totales 
      ELSE 0 
    END AS porcentaje_otros,

    -- KPIs de Eficiencia
    COALESCE(stats.operaciones_totales, 0) AS operaciones_totales,
    CASE 
      WHEN EXTRACT(EPOCH FROM (ct.fecha_cierre - ct.fecha_apertura)) > 0
      THEN stats.operaciones_totales * 3600.0 / EXTRACT(EPOCH FROM (ct.fecha_cierre - ct.fecha_apertura))
      ELSE 0 
    END AS operaciones_por_hora,

    -- Estado de conciliación
    CASE
      WHEN ct.estado = 1 THEN 'Abierto'
      WHEN ct.diferencia IS NULL OR ct.diferencia = 0 THEN 'Conciliado'
      WHEN ABS(ct.diferencia) <= 1.00 THEN 'Casi exacto (≤ $1)'
      WHEN ct.diferencia > 0 THEN 'Sobrante'
      ELSE 'Falta'
    END AS conciliacion_estado

  FROM app_dat_caja_turno ct
  LEFT JOIN app_dat_tpv tpv ON ct.id_tpv = tpv.id  -- Cambié a LEFT JOIN
  LEFT JOIN app_dat_vendedor ven ON ct.id_vendedor = ven.id  -- Cambié a LEFT JOIN

  -- Estadísticas de ventas
  LEFT JOIN LATERAL (
    SELECT
      SUM(ov.importe_total) AS ventas_totales,
      COUNT(ov.id_operacion) AS operaciones_venta,
      (SUM(cp.cantidad))::bigint AS productos_vendidos
    FROM app_dat_operacion_venta ov
    JOIN app_dat_operaciones o ON ov.id_operacion = o.id
    LEFT JOIN app_dat_control_productos cp ON o.id = cp.id_operacion
    WHERE ov.id_tpv = ct.id_tpv
      AND o.created_at >= ct.fecha_apertura
      AND (o.created_at <= ct.fecha_cierre OR ct.fecha_cierre IS NULL)
      AND o.id_tipo_operacion = (SELECT id FROM app_nom_tipo_operacion WHERE denominacion = 'Venta')
  ) vtas ON true

  -- Resumen de pagos
  LEFT JOIN LATERAL (
    SELECT
      SUM(CASE WHEN mp.es_efectivo THEN pv.monto ELSE 0 END) AS total_efectivo,
      SUM(pv.monto) AS total_pagos,
      ct.efectivo_inicial + SUM(CASE WHEN mp.es_efectivo THEN pv.monto ELSE 0 END) AS efectivo_esperado
    FROM app_dat_pago_venta pv
    JOIN app_nom_medio_pago mp ON pv.id_medio_pago = mp.id
    JOIN app_dat_operacion_venta ov ON pv.id_operacion_venta = ov.id_operacion
    JOIN app_dat_operaciones o ON ov.id_operacion = o.id
    WHERE ov.id_tpv = ct.id_tpv
      AND o.created_at >= ct.fecha_apertura
      AND (o.created_at <= ct.fecha_cierre OR ct.fecha_cierre IS NULL)
  ) pagos ON true

  -- Estadísticas de operaciones
  LEFT JOIN LATERAL (
    SELECT COUNT(*) AS operaciones_totales
    FROM app_dat_operaciones o
    WHERE o.id_tienda = tpv.id_tienda
      AND o.created_at >= ct.fecha_apertura
      AND (o.created_at <= ct.fecha_cierre OR ct.fecha_cierre IS NULL)
  ) stats ON true

  -- Filtro: por TPV, vendedor y fecha
  WHERE (p_id_tpv IS NULL OR ct.id_tpv = p_id_tpv)
    AND (p_id_vendedor IS NULL OR ct.id_vendedor = p_id_vendedor)
    AND (p_fecha_desde IS NULL OR ct.fecha_apertura >= p_fecha_desde)
    AND (p_fecha_hasta IS NULL OR ct.fecha_apertura <= p_fecha_hasta)
    -- CAMBIO PRINCIPAL: Incluir turnos abiertos (estado = 1)
    AND ct.estado IN (1, 2, 3) -- Turnos abiertos, cerrados y en revisión
    AND ct.fecha_apertura IS NOT NULL

  ORDER BY ct.fecha_apertura DESC;
END;
$$;
