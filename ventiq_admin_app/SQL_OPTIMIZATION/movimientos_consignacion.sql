-- ============================================================================
-- FUNCIÓN RPC: Obtener Operaciones de Venta de Productos en Consignación
-- ============================================================================
-- ENFOQUE 2: Consulta desde la ZONA de consignación
-- 
-- Devuelve las operaciones de venta completadas de los productos que están
-- en la zona específica del contrato de consignación. No modifica operaciones
-- existentes, solo consulta desde la zona.
-- 
-- LÓGICA:
-- 1. Obtiene el contrato y su almacén destino
-- 2. Busca la zona de consignación en ese almacén
-- 3. Obtiene todos los productos en esa zona (app_dat_inventario_productos)
-- 4. Busca operaciones de EXTRACCIÓN con motivos de venta (11-20)
-- 5. Retorna operaciones reales (fuente de verdad única)
--
-- NOTA: Las ventas se registran en app_dat_operacion_extraccion con
--       id_motivo_operacion entre 11 y 20 (motivos de venta)
--
-- Parámetros:
--   p_id_contrato: ID del contrato de consignación
--   p_fecha_desde: Fecha inicial (opcional)
--   p_fecha_hasta: Fecha final (opcional)
--
-- Retorna: Operaciones de venta con información del producto, almacén y zona
-- ============================================================================

CREATE OR REPLACE FUNCTION get_movimientos_consignacion(
  p_id_contrato BIGINT,
  p_fecha_desde TIMESTAMP WITH TIME ZONE DEFAULT NULL,
  p_fecha_hasta TIMESTAMP WITH TIME ZONE DEFAULT NULL
)
RETURNS TABLE (
  id_operacion BIGINT,
  id_producto BIGINT,
  denominacion_producto VARCHAR,
  sku_producto VARCHAR,
  cantidad_vendida NUMERIC,
  importe_total NUMERIC,
  fecha_venta TIMESTAMP WITH TIME ZONE,
  motivo_extraccion VARCHAR,
  id_motivo_extraccion BIGINT,
  id_almacen BIGINT,
  denominacion_almacen VARCHAR,
  id_zona BIGINT,
  denominacion_zona VARCHAR,
  sku_codigo_zona VARCHAR
) AS $$
BEGIN
  RETURN QUERY
  SELECT DISTINCT ON (op.id, p.id, ep.id)
    op.id,
    p.id,
    p.denominacion,
    p.sku,
    ep.cantidad::NUMERIC,
    COALESCE(ep.importe_real, 0)::NUMERIC,
    op.created_at,
    'Venta'::VARCHAR,
    0::BIGINT,
    a.id,
    a.denominacion,
    la.id,
    la.denominacion,
    la.sku_codigo
  FROM app_dat_contrato_consignacion cc
  -- Obtener almacén
  INNER JOIN app_dat_almacen a ON a.id = cc.id_almacen_destino
  -- Obtener zona de consignación del almacén destino (FILTRO OBLIGATORIO)
  INNER JOIN app_dat_layout_almacen la ON la.id_almacen = cc.id_almacen_destino
  -- Obtener operaciones de venta en tienda consignataria
  INNER JOIN app_dat_operaciones op ON op.id_tienda = cc.id_tienda_consignataria
  INNER JOIN app_dat_operacion_venta ov ON op.id = ov.id_operacion
  -- Obtener detalles de productos en la operación
  INNER JOIN app_dat_extraccion_productos ep ON ep.id_operacion = op.id
  INNER JOIN app_dat_producto p ON ep.id_producto = p.id
  -- Verificar que el producto está en la zona de consignación
  INNER JOIN app_dat_inventario_productos ip ON ip.id_ubicacion = la.id AND ip.id_producto = ep.id_producto
  -- Filtrar solo operaciones COMPLETADAS (estado = 2)
  INNER JOIN app_dat_estado_operacion eo ON eo.id_operacion = op.id
  WHERE cc.id = p_id_contrato
    AND eo.estado = 2  -- 2 = Completada
    AND (p_fecha_desde IS NULL OR ep.created_at >= p_fecha_desde)
    AND (p_fecha_hasta IS NULL OR ep.created_at <= p_fecha_hasta + INTERVAL '23 hours 59 minutes 59 seconds')
  ORDER BY op.id, p.id, ep.id, op.created_at DESC;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- FUNCIÓN RPC: Obtener Estadísticas de Ventas del Contrato
-- ============================================================================
-- Devuelve un resumen consolidado de las operaciones de venta del contrato
-- basado en operaciones de extracción con motivos de venta (11-20)
--
-- Parámetros:
--   p_id_contrato: ID del contrato de consignación
--   p_fecha_desde: Fecha inicial (opcional)
--   p_fecha_hasta: Fecha final (opcional)
--
-- Retorna: Estadísticas consolidadas con información del almacén y zona
-- ============================================================================

CREATE OR REPLACE FUNCTION get_estadisticas_ventas_consignacion(
  p_id_contrato BIGINT,
  p_fecha_desde TIMESTAMP WITH TIME ZONE DEFAULT NULL,
  p_fecha_hasta TIMESTAMP WITH TIME ZONE DEFAULT NULL
)
RETURNS TABLE (
  total_enviado NUMERIC,
  total_vendido NUMERIC,
  total_devuelto NUMERIC,
  total_pendiente NUMERIC,
  total_operaciones BIGINT,
  total_monto_ventas NUMERIC,
  promedio_venta NUMERIC,
  ultima_venta TIMESTAMP WITH TIME ZONE,
  primera_venta TIMESTAMP WITH TIME ZONE,
  id_almacen BIGINT,
  denominacion_almacen VARCHAR,
  id_zona BIGINT,
  denominacion_zona VARCHAR,
  sku_codigo_zona VARCHAR
) AS $$
BEGIN
  RETURN QUERY
  WITH movimientos_deduplicados AS (
    -- Obtener movimientos sin duplicados (mismo que get_movimientos_consignacion)
    SELECT DISTINCT ON (op.id, p.id, ep.id)
      op.id as op_id,
      p.id as p_id,
      ep.cantidad,
      ep.importe_real,
      op.created_at,
      a.id as a_id,
      a.denominacion as a_denominacion,
      la.id as la_id,
      la.denominacion as la_denominacion,
      la.sku_codigo
    FROM app_dat_contrato_consignacion cc
    -- Obtener almacén
    INNER JOIN app_dat_almacen a ON a.id = cc.id_almacen_destino
    -- Obtener zona de consignación del almacén destino (FILTRO OBLIGATORIO)
    INNER JOIN app_dat_layout_almacen la ON la.id_almacen = cc.id_almacen_destino
    -- Obtener operaciones de venta en tienda consignataria
    INNER JOIN app_dat_operaciones op ON op.id_tienda = cc.id_tienda_consignataria
    INNER JOIN app_dat_operacion_venta ov ON op.id = ov.id_operacion
    -- Obtener detalles de productos en la operación
    INNER JOIN app_dat_extraccion_productos ep ON ep.id_operacion = op.id
    INNER JOIN app_dat_producto p ON ep.id_producto = p.id
    -- Verificar que el producto está en la zona de consignación
    INNER JOIN app_dat_inventario_productos ip ON ip.id_ubicacion = la.id AND ip.id_producto = ep.id_producto
    -- Filtrar solo operaciones COMPLETADAS (estado = 2)
    INNER JOIN app_dat_estado_operacion eo ON eo.id_operacion = op.id
    WHERE cc.id = p_id_contrato
      AND eo.estado = 2  -- 2 = Completada
      AND (p_fecha_desde IS NULL OR ep.created_at >= p_fecha_desde)
      AND (p_fecha_hasta IS NULL OR ep.created_at <= p_fecha_hasta + INTERVAL '23 hours 59 minutes 59 seconds')
    ORDER BY op.id, p.id, ep.id, op.created_at DESC
  ),
  ventas_consolidadas AS (
    SELECT
      COALESCE(SUM(cantidad), 0)::NUMERIC as total_vendido_calc,
      COALESCE(SUM(importe_real), 0)::NUMERIC as total_monto_calc,
      COUNT(DISTINCT op_id)::BIGINT as total_ops,
      MAX(created_at) as ultima_venta_calc,
      MIN(created_at) as primera_venta_calc,
      a_id as id_almacen_calc,
      a_denominacion as denominacion_almacen_calc,
      la_id as id_zona_calc,
      la_denominacion as denominacion_zona_calc,
      sku_codigo as sku_codigo_zona_calc
    FROM movimientos_deduplicados
    GROUP BY a_id, a_denominacion, la_id, la_denominacion, sku_codigo
  ),
  productos_consignacion AS (
    SELECT
      COALESCE(SUM(pc.cantidad_enviada), 0)::NUMERIC as total_enviado_calc,
      COALESCE(SUM(pc.cantidad_devuelta), 0)::NUMERIC as total_devuelto_calc
    FROM app_dat_producto_consignacion pc
    WHERE pc.id_contrato = p_id_contrato
  )
  SELECT
    pc.total_enviado_calc,
    vc.total_vendido_calc,
    pc.total_devuelto_calc,
    (pc.total_enviado_calc - vc.total_vendido_calc - pc.total_devuelto_calc)::NUMERIC,
    vc.total_ops,
    vc.total_monto_calc,
    CASE 
      WHEN vc.total_ops > 0 
      THEN vc.total_monto_calc / vc.total_ops
      ELSE 0
    END::NUMERIC,
    vc.ultima_venta_calc,
    vc.primera_venta_calc,
    vc.id_almacen_calc,
    vc.denominacion_almacen_calc,
    vc.id_zona_calc,
    vc.denominacion_zona_calc,
    vc.sku_codigo_zona_calc
  FROM productos_consignacion pc
  CROSS JOIN ventas_consolidadas vc;
END;
$$ LANGUAGE plpgsql;
