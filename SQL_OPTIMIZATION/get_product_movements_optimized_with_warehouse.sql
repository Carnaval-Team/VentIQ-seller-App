CREATE OR REPLACE FUNCTION public.get_product_movements_optimized_with_warehouse(
  p_id_producto BIGINT,
  p_fecha_desde DATE DEFAULT NULL,
  p_fecha_hasta DATE DEFAULT NULL,
  p_tipo_operacion_id BIGINT DEFAULT NULL,
  p_id_almacen BIGINT DEFAULT NULL,
  p_offset INTEGER DEFAULT 0,
  p_limit INTEGER DEFAULT 20
)
RETURNS TABLE (
  id BIGINT,
  id_operacion BIGINT,
  tipo_movimiento VARCHAR,
  tipo_operacion_id BIGINT,
  tipo_operacion VARCHAR,
  cantidad NUMERIC,
  precio_unitario NUMERIC,
  costo_real NUMERIC,
  importe_real NUMERIC,
  fecha TIMESTAMP WITH TIME ZONE,
  usuario_uuid UUID,
  ubicacion_id BIGINT,
  ubicacion_nombre VARCHAR,
  almacen_id BIGINT,
  almacen_nombre VARCHAR,
  proveedor_id BIGINT,
  proveedor_nombre VARCHAR,
  observaciones VARCHAR,
  cantidad_inicial NUMERIC,
  cantidad_final NUMERIC,
  estado_operacion SMALLINT,
  estado_operacion_nombre VARCHAR,
  total_count BIGINT
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    COALESCE(rp.id, ep.id, cp.id)::BIGINT,
    op.id::BIGINT,
    CASE 
      WHEN inv.id_recepcion IS NOT NULL THEN 'Recepción'::VARCHAR
      WHEN inv.id_extraccion IS NOT NULL THEN 'Extracción'::VARCHAR
      WHEN inv.id_control IS NOT NULL THEN 'Control'::VARCHAR
      ELSE 'Desconocido'::VARCHAR
    END,
    op.id_tipo_operacion::BIGINT,
    nto.denominacion::VARCHAR,
    COALESCE(rp.cantidad, ep.cantidad, cp.cantidad)::NUMERIC,
    COALESCE(rp.precio_unitario, ep.precio_unitario)::NUMERIC,
    rp.costo_real::NUMERIC,
    ep.importe_real::NUMERIC,
    COALESCE(rp.created_at, ep.created_at, cp.created_at)::TIMESTAMP WITH TIME ZONE,
    op.uuid::UUID,
    COALESCE(rp.id_ubicacion, ep.id_ubicacion, cp.id_ubicacion)::BIGINT,
    la.denominacion::VARCHAR,
    la.id_almacen::BIGINT,
    alm.denominacion::VARCHAR,
    COALESCE(rp.id_proveedor, inv.id_proveedor)::BIGINT,
    prov.denominacion::VARCHAR,
    op.observaciones::VARCHAR,
    inv.cantidad_inicial::NUMERIC,
    inv.cantidad_final::NUMERIC,
    eo.estado::SMALLINT,
    CASE 
      WHEN eo.estado = 1 THEN 'Pendiente'::VARCHAR
      WHEN eo.estado = 2 THEN 'Completada'::VARCHAR
      WHEN eo.estado = 3 THEN 'Devuelta'::VARCHAR
      WHEN eo.estado = 4 THEN 'Cancelada'::VARCHAR
      ELSE 'Desconocido'::VARCHAR
    END,
    COUNT(*) OVER ()::BIGINT
  FROM app_dat_inventario_productos inv
  INNER JOIN app_dat_operaciones op ON (
    (inv.id_recepcion IS NOT NULL AND EXISTS (
      SELECT 1 FROM app_dat_recepcion_productos rp 
      WHERE rp.id = inv.id_recepcion AND rp.id_operacion = op.id
    ))
    OR (inv.id_extraccion IS NOT NULL AND EXISTS (
      SELECT 1 FROM app_dat_extraccion_productos ep 
      WHERE ep.id = inv.id_extraccion AND ep.id_operacion = op.id
    ))
    OR (inv.id_control IS NOT NULL AND EXISTS (
      SELECT 1 FROM app_dat_control_productos cp 
      WHERE cp.id = inv.id_control AND cp.id_operacion = op.id
    ))
  )
  INNER JOIN app_nom_tipo_operacion nto ON op.id_tipo_operacion = nto.id
  LEFT JOIN app_dat_recepcion_productos rp ON inv.id_recepcion = rp.id
  LEFT JOIN app_dat_extraccion_productos ep ON inv.id_extraccion = ep.id
  LEFT JOIN app_dat_control_productos cp ON inv.id_control = cp.id
  LEFT JOIN app_dat_layout_almacen la ON COALESCE(rp.id_ubicacion, ep.id_ubicacion, cp.id_ubicacion) = la.id
  LEFT JOIN app_dat_almacen alm ON la.id_almacen = alm.id
  LEFT JOIN app_dat_proveedor prov ON COALESCE(rp.id_proveedor, inv.id_proveedor) = prov.id
  LEFT JOIN LATERAL (
    SELECT estado
    FROM app_dat_estado_operacion
    WHERE app_dat_estado_operacion.id_operacion = op.id
    ORDER BY created_at DESC
    LIMIT 1
  ) eo ON TRUE
  WHERE inv.id_producto = p_id_producto
    AND (p_fecha_desde IS NULL OR inv.created_at::DATE >= p_fecha_desde)
    AND (p_fecha_hasta IS NULL OR inv.created_at::DATE <= p_fecha_hasta)
    AND (p_tipo_operacion_id IS NULL OR op.id_tipo_operacion = p_tipo_operacion_id)
    AND (p_id_almacen IS NULL OR la.id_almacen = p_id_almacen)
  ORDER BY COALESCE(rp.created_at, ep.created_at, cp.created_at) DESC
  LIMIT p_limit
  OFFSET p_offset;
END;
$$ LANGUAGE plpgsql;