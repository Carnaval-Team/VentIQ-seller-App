-- ============================================================================
-- FUNCIÓN: obtener_productos_envio
-- DESCRIPCIÓN: Obtiene los productos de un envío de consignación con detalles
-- ============================================================================

DROP FUNCTION IF EXISTS public.obtener_productos_envio(INTEGER) CASCADE;

CREATE OR REPLACE FUNCTION public.obtener_productos_envio(
  p_id_envio INTEGER
)
RETURNS TABLE (
  id BIGINT,
  id_envio BIGINT,
  id_producto BIGINT,
  id_inventario BIGINT,
  cantidad_propuesta NUMERIC,
  cantidad_aceptada NUMERIC,
  cantidad_rechazada NUMERIC,
  precio_costo_cup NUMERIC,
  precio_costo_usd NUMERIC,
  precio_venta_cup NUMERIC,
  estado_producto INTEGER,
  producto_denominacion VARCHAR,
  producto_sku VARCHAR,
  producto_id_tienda BIGINT,
  created_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    cep.id,
    cep.id_envio,
    cep.id_producto,
    cep.id_inventario,
    cep.cantidad_propuesta,
    cep.cantidad_aceptada,
    cep.cantidad_rechazada,
    cep.precio_costo_cup,
    cep.precio_costo_usd,
    cep.precio_venta_cup,
    cep.estado_producto,
    p.denominacion,
    p.sku,
    p.id_tienda,
    cep.created_at
  FROM app_dat_consignacion_envio_producto cep
  INNER JOIN app_dat_producto p ON cep.id_producto = p.id
  WHERE cep.id_envio = p_id_envio
  ORDER BY cep.id ASC;
END;
$$ LANGUAGE plpgsql;
