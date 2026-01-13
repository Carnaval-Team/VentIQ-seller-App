-- ✅ RPC: Obtiene TODOS los productos del envío con su estado_producto para mostrar información
CREATE OR REPLACE FUNCTION obtener_productos_envio2(p_id_envio INTEGER)
RETURNS TABLE (
  id BIGINT,
  id_producto BIGINT,
  id_inventario BIGINT,
  denominacion VARCHAR,
  sku VARCHAR,
  cantidad_propuesta NUMERIC,
  cantidad_aceptada NUMERIC,
  cantidad_rechazada NUMERIC,
  precio_costo_usd NUMERIC,
  precio_costo_cup NUMERIC,
  precio_venta_cup NUMERIC,
  tasa_cambio NUMERIC,
  estado_producto INTEGER,
  estado INTEGER,
  tipo_envio INTEGER
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    ep.id,
    ep.id_producto,
    ep.id_inventario,
    p.denominacion,
    p.sku,
    ep.cantidad_propuesta,
    COALESCE(ep.cantidad_aceptada, 0),
    COALESCE(ep.cantidad_rechazada, 0),
    ep.precio_costo_usd,
    ep.precio_costo_cup,
    ep.precio_venta_cup,
    ep.tasa_cambio,
    ep.estado_producto,  -- ✅ Retorna estado_producto (0=Pendiente, 1=Confirmado, 2=Rechazado)
    ep.estado,
    e.tipo_envio
  FROM app_dat_consignacion_envio_producto ep
  JOIN app_dat_producto p ON ep.id_producto = p.id
  JOIN app_dat_consignacion_envio e ON ep.id_envio = e.id
  WHERE ep.id_envio = p_id_envio
  ORDER BY ep.id;
END;
$$ LANGUAGE plpgsql;
