-- ============================================================================
-- FUNCIÓN: obtener_envios_consignacion_con_totales
-- DESCRIPCIÓN: Obtiene envíos de consignación con cálculo correcto de totales
-- ============================================================================

DROP FUNCTION IF EXISTS public.obtener_envios_consignacion_con_totales(
  BIGINT, INTEGER, BIGINT
) CASCADE;

CREATE OR REPLACE FUNCTION public.obtener_envios_consignacion_con_totales(
  p_id_contrato BIGINT DEFAULT NULL,
  p_estado_envio INTEGER DEFAULT NULL,
  p_id_tienda BIGINT DEFAULT NULL
)
RETURNS TABLE (
  id_envio BIGINT,
  numero_envio VARCHAR,
  estado_envio INTEGER,
  estado_envio_texto VARCHAR,
  id_contrato_consignacion BIGINT,
  id_tienda_consignadora BIGINT,
  id_tienda_consignataria BIGINT,
  id_almacen_origen BIGINT,
  id_almacen_destino BIGINT,
  tienda_consignadora VARCHAR,
  tienda_consignataria VARCHAR,
  almacen_origen VARCHAR,
  almacen_destino VARCHAR,
  porcentaje_comision NUMERIC,
  cantidad_productos BIGINT,
  cantidad_total_unidades NUMERIC,
  valor_total_costo NUMERIC,
  valor_total_venta NUMERIC,
  fecha_propuesta TIMESTAMP WITH TIME ZONE,
  fecha_configuracion TIMESTAMP WITH TIME ZONE,
  fecha_envio TIMESTAMP WITH TIME ZONE,
  fecha_aceptacion TIMESTAMP WITH TIME ZONE,
  fecha_rechazo TIMESTAMP WITH TIME ZONE,
  motivo_rechazo TEXT,
  productos JSONB,
  tipo_envio INTEGER
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    ce.id,
    ce.numero_envio,
    ce.estado_envio,
    CASE ce.estado_envio
      WHEN 1 THEN 'PROPUESTO'
      WHEN 2 THEN 'CONFIGURADO'
      WHEN 3 THEN 'EN TRÁNSITO'
      WHEN 4 THEN 'ACEPTADO'
      WHEN 5 THEN 'RECHAZADO'
      WHEN 6 THEN 'PARCIALMENTE ACEPTADO'
      ELSE 'DESCONOCIDO'
    END::VARCHAR,
    ce.id_contrato_consignacion,
    cc.id_tienda_consignadora,
    cc.id_tienda_consignataria,
    ce.id_almacen_origen,
    ce.id_almacen_destino,
    tc.denominacion::VARCHAR,
    td.denominacion::VARCHAR,
    COALESCE(ao.denominacion, '')::VARCHAR,
    COALESCE(ad.denominacion, '')::VARCHAR,
    cc.porcentaje_comision,
    COUNT(DISTINCT cep.id) FILTER (WHERE cep.estado_producto != 2)::BIGINT as cantidad_productos,
    COALESCE(SUM(cep.cantidad_propuesta) FILTER (WHERE cep.estado_producto != 2), 0)::NUMERIC as cantidad_total_unidades,
    COALESCE(SUM(cep.cantidad_propuesta * cep.precio_costo_usd) FILTER (WHERE cep.estado_producto != 2), 0)::NUMERIC as valor_total_costo,
    COALESCE(SUM(CASE WHEN cep.precio_venta_cup IS NOT NULL THEN cep.cantidad_propuesta * cep.precio_venta_cup ELSE 0 END) FILTER (WHERE cep.estado_producto != 2), 0)::NUMERIC as valor_total_venta,
    ce.fecha_propuesta,
    ce.fecha_configuracion,
    ce.fecha_envio,
    ce.fecha_aceptacion,
    ce.fecha_rechazo,
    ce.motivo_rechazo,
    COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id_envio_producto', cep.id,
          'id_producto', cep.id_producto,
          'id_inventario', cep.id_inventario,
          'cantidad_propuesta', cep.cantidad_propuesta,
          'cantidad_aceptada', cep.cantidad_aceptada,
          'cantidad_rechazada', cep.cantidad_rechazada,
          'precio_costo_cup', cep.precio_costo_cup,
          'precio_costo_usd', cep.precio_costo_usd,
          'precio_venta_cup', cep.precio_venta_cup,
          'estado_producto', cep.estado_producto
        )
      ) FILTER (WHERE cep.id IS NOT NULL),
      '[]'::JSONB
    )::JSONB,
    ce.tipo_envio
  FROM app_dat_consignacion_envio ce
  INNER JOIN app_dat_contrato_consignacion cc ON ce.id_contrato_consignacion = cc.id
  INNER JOIN app_dat_tienda tc ON cc.id_tienda_consignadora = tc.id
  INNER JOIN app_dat_tienda td ON cc.id_tienda_consignataria = td.id
  LEFT JOIN app_dat_almacen ao ON ce.id_almacen_origen = ao.id
  LEFT JOIN app_dat_almacen ad ON ce.id_almacen_destino = ad.id
  LEFT JOIN app_dat_consignacion_envio_producto cep ON ce.id = cep.id_envio
  WHERE 
    (p_id_contrato IS NULL OR ce.id_contrato_consignacion = p_id_contrato)
    AND (p_estado_envio IS NULL OR ce.estado_envio = p_estado_envio)
    AND (p_id_tienda IS NULL OR cc.id_tienda_consignadora = p_id_tienda OR cc.id_tienda_consignataria = p_id_tienda)
  GROUP BY 
    ce.id, ce.numero_envio, ce.estado_envio, ce.id_contrato_consignacion,
    cc.id_tienda_consignadora, cc.id_tienda_consignataria, cc.porcentaje_comision,
    ce.id_almacen_origen, ce.id_almacen_destino,
    tc.denominacion, td.denominacion, ao.denominacion, ad.denominacion,
    ce.fecha_propuesta, ce.fecha_configuracion, ce.fecha_envio,
    ce.fecha_aceptacion, ce.fecha_rechazo, ce.motivo_rechazo, ce.tipo_envio
  ORDER BY ce.created_at DESC;
END;
$$ LANGUAGE plpgsql;
