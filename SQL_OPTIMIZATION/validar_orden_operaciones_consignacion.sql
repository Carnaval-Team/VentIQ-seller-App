-- ============================================================================
-- FUNCIÓN: validar_orden_operaciones_consignacion
-- DESCRIPCIÓN: Valida que la operación de extracción esté completada antes de 
--              permitir completar la operación de recepción en consignación
-- PARÁMETROS:
--   p_id_operacion_recepcion: ID de la operación de recepción a validar
-- RETORNA:
--   valido: boolean - true si la extracción está completada
--   mensaje: text - Mensaje descriptivo
--   id_operacion_extraccion: bigint - ID de la operación de extracción relacionada
--   estado_extraccion: integer - Estado de la operación de extracción (1=PENDIENTE, 2=COMPLETADA)
-- ============================================================================

DROP FUNCTION IF EXISTS public.validar_orden_operaciones_consignacion(BIGINT) CASCADE;

CREATE OR REPLACE FUNCTION public.validar_orden_operaciones_consignacion(
  p_id_operacion_recepcion BIGINT
)
RETURNS TABLE (
  valido BOOLEAN,
  mensaje TEXT,
  id_operacion_extraccion BIGINT,
  estado_extraccion INTEGER
) AS $$
DECLARE
  v_rel RECORD;
BEGIN
  -- Obtener información de las operaciones relacionadas
  SELECT * FROM get_operaciones_consignacion_relacionadas(p_id_operacion_recepcion) INTO v_rel;
  
  -- Si no hay operaciones relacionadas, se considera válido (no es consignación o no tiene trazabilidad)
  IF v_rel.id_operacion_extraccion IS NULL THEN
    RETURN QUERY SELECT TRUE, 'No se requiere validación de orden (no es una transacción vinculada)'::TEXT, NULL::BIGINT, NULL::INT;
    RETURN;
  END IF;
  
  -- Verificar estado de la extracción (Estado 2 = COMPLETADA)
  IF v_rel.estado_extraccion = 2 THEN
    RETURN QUERY SELECT TRUE, 'Validación exitosa: La operación de extracción está completada.'::TEXT, v_rel.id_operacion_extraccion, v_rel.estado_extraccion;
  ELSE
    RETURN QUERY SELECT 
      FALSE, 
      'La operación de extracción #' || v_rel.id_operacion_extraccion || ' debe estar COMPLETADA antes de recibir los productos.'::TEXT, 
      v_rel.id_operacion_extraccion, 
      v_rel.estado_extraccion;
  END IF;
END;
$$ LANGUAGE plpgsql;
