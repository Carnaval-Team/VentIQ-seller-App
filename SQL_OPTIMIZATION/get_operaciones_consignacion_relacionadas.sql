-- ============================================================================
-- FUNCIÓN: get_operaciones_consignacion_relacionadas
-- DESCRIPCIÓN: Obtiene las operaciones de extracción y recepción relacionadas
--              a un envío de consignación
-- PARÁMETROS:
--   p_id_operacion_recepcion: ID de la operación de recepción
-- RETORNA:
--   id: bigint - ID del envío (o NULL si viene de producto_consignacion)
--   id_operacion_recepcion: bigint - ID de la operación de recepción
--   id_operacion_extraccion: bigint - ID de la operación de extracción
--   estado_recepcion: integer - Estado de la recepción (1=PENDIENTE, 2=COMPLETADA)
--   estado_extraccion: integer - Estado de la extracción (1=PENDIENTE, 2=COMPLETADA)
--   productos_pendientes: bigint - Cantidad de productos pendientes
-- ============================================================================

DROP FUNCTION IF EXISTS public.get_operaciones_consignacion_relacionadas(BIGINT) CASCADE;

CREATE OR REPLACE FUNCTION public.get_operaciones_consignacion_relacionadas(
  p_id_operacion_recepcion BIGINT
)
RETURNS TABLE (
  id BIGINT,
  id_operacion_recepcion BIGINT,
  id_operacion_extraccion BIGINT,
  estado_recepcion INTEGER,
  estado_extraccion INTEGER,
  productos_pendientes BIGINT
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    e.id,
    e.id_operacion_recepcion,
    e.id_operacion_extraccion,
    COALESCE((SELECT eo.estado FROM app_dat_estado_operacion eo WHERE eo.id_operacion = e.id_operacion_recepcion ORDER BY eo.created_at DESC LIMIT 1), 1),
    COALESCE((SELECT eo.estado FROM app_dat_estado_operacion eo WHERE eo.id_operacion = e.id_operacion_extraccion ORDER BY eo.created_at DESC LIMIT 1), 1),
    (SELECT COUNT(*) FROM app_dat_consignacion_envio_producto ep WHERE ep.id_envio = e.id AND ep.estado = 1)
  FROM app_dat_consignacion_envio e
  WHERE e.id_operacion_recepcion = p_id_operacion_recepcion
  
  UNION
  
  -- Fallback para productos vinculados directamente si no hay registro en app_dat_consignacion_envio
  SELECT 
    NULL::BIGINT,
    pc.id_operacion_recepcion,
    pc.id_operacion_extraccion,
    COALESCE((SELECT eo.estado FROM app_dat_estado_operacion eo WHERE eo.id_operacion = pc.id_operacion_recepcion ORDER BY eo.created_at DESC LIMIT 1), 1),
    COALESCE((SELECT eo.estado FROM app_dat_estado_operacion eo WHERE eo.id_operacion = pc.id_operacion_extraccion ORDER BY eo.created_at DESC LIMIT 1), 1),
    COUNT(*)::BIGINT
  FROM app_dat_producto_consignacion pc
  WHERE pc.id_operacion_recepcion = p_id_operacion_recepcion
  AND NOT EXISTS (SELECT 1 FROM app_dat_consignacion_envio env WHERE env.id_operacion_recepcion = p_id_operacion_recepcion)
  GROUP BY pc.id_operacion_recepcion, pc.id_operacion_extraccion;
END;
$$ LANGUAGE plpgsql;
