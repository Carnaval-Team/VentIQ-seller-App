-- ============================================================================
-- FUNCIÓN: cancelar_envio_consignacion
-- DESCRIPCIÓN: Cancela un envío de consignación. 
--              Se usa generalmente por el emisor antes de que sea aceptado.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.cancelar_envio_consignacion(
  p_id_envio BIGINT,
  p_id_usuario UUID,
  p_motivo TEXT DEFAULT NULL
)
RETURNS TABLE (
  success BOOLEAN,
  mensaje TEXT
) AS $$
DECLARE
  v_estado_actual INTEGER;
BEGIN
  -- 1. Obtener estado actual
  SELECT estado_envio INTO v_estado_actual
  FROM app_dat_consignacion_envio
  WHERE id = p_id_envio;

  IF NOT FOUND THEN
    RETURN QUERY SELECT FALSE, 'Envío no encontrado.'::TEXT;
    RETURN;
  END IF;

  -- 2. Validar que no haya sido aceptado
  IF v_estado_actual = 4 THEN
    RETURN QUERY SELECT FALSE, 'No se puede cancelar un envío que ya ha sido ACEPTADO.'::TEXT;
    RETURN;
  END IF;

  -- 3. Si por error se cancela algo en tránsito, manejamos la devolución de stock
  IF v_estado_actual = 3 THEN
    -- Reutilizamos la lógica de retorno de stock
    UPDATE app_dat_inventario_productos ip
    SET cantidad_final = ip.cantidad_final + cep.cantidad_propuesta,
        updated_at = NOW()
    FROM app_dat_consignacion_envio_producto cep
    WHERE cep.id_envio = p_id_envio 
      AND ip.id = COALESCE(cep.id_inventario_original, cep.id_inventario);
  END IF;

  -- 3.b Cancelar operaciones si no están completadas
  INSERT INTO app_dat_estado_operacion (id_operacion, estado, comentario, uuid)
  SELECT id_operacion_extraccion, 3, 'Operación cancelada por anulación de envío', p_id_usuario
  FROM app_dat_consignacion_envio 
  WHERE id = p_id_envio AND id_operacion_extraccion IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM app_dat_estado_operacion WHERE id_operacion = id_operacion_extraccion AND estado = 2);

  INSERT INTO app_dat_estado_operacion (id_operacion, estado, comentario, uuid)
  SELECT id_operacion_recepcion, 3, 'Operación cancelada por anulación de envío', p_id_usuario
  FROM app_dat_consignacion_envio 
  WHERE id = p_id_envio AND id_operacion_recepcion IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM app_dat_estado_operacion WHERE id_operacion = id_operacion_recepcion AND estado = 2);

  -- 4. Actualizar estado del envío 
  -- (Usamos estado 5 para RECHAZADO/CANCELADO según el estándar del proyecto)
  UPDATE app_dat_consignacion_envio
  SET 
    estado_envio = 5,
    motivo_rechazo = COALESCE(p_motivo, 'Cancelado por el usuario'),
    fecha_rechazo = NOW(),
    id_usuario_rechazador = p_id_usuario,
    updated_at = NOW()
  WHERE id = p_id_envio;

  -- 5. Registrar en el historial
  INSERT INTO app_dat_consignacion_envio_movimiento (
    id_envio,
    id_usuario,
    tipo_movimiento,
    descripcion,
    created_at
  ) VALUES (
    p_id_envio,
    p_id_usuario,
    3, -- MOVIMIENTO_RECHAZO/CANCELACION
    'Envío cancelado: ' || COALESCE(p_motivo, 'Sin motivo especificado'),
    NOW()
  );

  RETURN QUERY SELECT TRUE, 'Envío cancelado exitosamente.'::TEXT;

EXCEPTION WHEN OTHERS THEN
  RETURN QUERY SELECT FALSE, 'Error en SQL: ' || SQLERRM;
END;
$$ LANGUAGE plpgsql;
