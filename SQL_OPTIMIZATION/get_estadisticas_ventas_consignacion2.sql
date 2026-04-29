
BEGIN
  RETURN QUERY
  WITH zona_contrato AS (
    -- Obtener la zona de consignación del contrato
    SELECT 
      cc.id_layout_destino as id_zona,
      la.denominacion::TEXT as denominacion_zona,
      la.sku_codigo::TEXT as sku_codigo_zona,
      la.id_almacen as id_almacen,
      a.denominacion::TEXT as denominacion_almacen
    FROM app_dat_contrato_consignacion cc
    LEFT JOIN app_dat_layout_almacen la ON la.id = cc.id_layout_destino
    LEFT JOIN app_dat_almacen a ON a.id = la.id_almacen
    WHERE cc.id = p_id_contrato
  ),
  movimientos_ventas AS (
    -- Obtener movimientos de venta de la zona de consignación
    SELECT DISTINCT ON (op.id, ep.id)
      op.id as op_id,
      ep.cantidad,
      ep.id_producto,
      op.created_at
    FROM app_dat_contrato_consignacion cc
    INNER JOIN zona_contrato zc ON true
    -- Operaciones de venta en tienda consignataria
    INNER JOIN app_dat_operaciones op ON op.id_tienda = cc.id_tienda_consignataria
    INNER JOIN app_dat_operacion_venta ov ON op.id = ov.id_operacion
    -- Productos extraídos
    INNER JOIN app_dat_extraccion_productos ep ON ep.id_operacion = op.id
    -- Verificar que la extracción fue de la zona de consignación
    INNER JOIN app_dat_inventario_productos ip 
      ON ip.id_extraccion = ep.id 
      AND ip.id_ubicacion = zc.id_zona
    -- Estado completado
    INNER JOIN app_dat_estado_operacion eo ON eo.id_operacion = op.id
    WHERE cc.id = p_id_contrato
      AND eo.estado = 2  -- 2 = Completada
      AND zc.id_zona IS NOT NULL  -- Asegurar que existe la zona
      AND (p_fecha_desde IS NULL OR op.created_at >= p_fecha_desde)
      AND (p_fecha_hasta IS NULL OR op.created_at <= p_fecha_hasta + INTERVAL '23 hours 59 minutes 59 seconds')
    ORDER BY op.id, ep.id, op.created_at DESC
  ),
  -- Obtener precio_costo_usd más reciente por producto del contrato
  precio_costo_producto AS (
    SELECT DISTINCT ON (cep.id_producto)
      cep.id_producto,
      cep.precio_costo_usd
    FROM app_dat_consignacion_envio_producto cep
    INNER JOIN app_dat_consignacion_envio ce 
      ON ce.id = cep.id_envio
      AND ce.id_contrato_consignacion = p_id_contrato
    WHERE cep.precio_costo_usd IS NOT NULL
      AND cep.precio_costo_usd > 0
    ORDER BY cep.id_producto, cep.created_at DESC
  ),
  ventas_consolidadas AS (
    -- Calcular monto usando precio_costo_usd del envío de consignación
    SELECT
      COALESCE(SUM(mv.cantidad), 0)::NUMERIC as total_vendido_calc,
      COALESCE(SUM(mv.cantidad * COALESCE(pcp.precio_costo_usd, 0)), 0)::NUMERIC as total_monto_calc,
      COUNT(DISTINCT mv.op_id)::BIGINT as total_ops,
      MAX(mv.created_at) as ultima_venta_calc,
      MIN(mv.created_at) as primera_venta_calc
    FROM movimientos_ventas mv
    LEFT JOIN precio_costo_producto pcp 
      ON pcp.id_producto = mv.id_producto
  ),
  productos_consignacion AS (
    SELECT
      COALESCE(SUM(pc.cantidad_enviada), 0)::NUMERIC as total_enviado_calc,
      COALESCE(SUM(pc.cantidad_devuelta), 0)::NUMERIC as total_devuelto_calc
    FROM app_dat_producto_consignacion pc
    WHERE pc.id_contrato = p_id_contrato
      AND pc.estado = 1  -- Solo productos activos
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
      THEN (vc.total_monto_calc / vc.total_ops)::NUMERIC
      ELSE 0::NUMERIC
    END,
    vc.ultima_venta_calc,
    vc.primera_venta_calc,
    zc.id_almacen,
    zc.denominacion_almacen,
    zc.id_zona,
    zc.denominacion_zona,
    zc.sku_codigo_zona
  FROM productos_consignacion pc
  CROSS JOIN ventas_consolidadas vc
  CROSS JOIN zona_contrato zc;
END;
