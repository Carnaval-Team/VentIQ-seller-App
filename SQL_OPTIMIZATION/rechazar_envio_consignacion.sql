-- ============================================================================
-- FUNCIÓN: rechazar_envio_consignacion
-- DESCRIPCIÓN: Rechaza un envío de consignación en cualquier etapa previa a la aceptación completa.
--              Si el envío ya estaba EN TRÁNSITO (estado 3), devuelve automáticamente el stock
--              a la ubicación original en la tienda consignadora.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.rechazar_envio_consignacion(
  p_id_envio BIGINT,
  p_id_usuario UUID,
  p_motivo_rechazo TEXT
)
RETURNS TABLE (
  success BOOLEAN,
  mensaje TEXT
) AS $$
DECLARE
  v_estado_actual INTEGER;
  v_id_contrato BIGINT;
  v_producto RECORD;
BEGIN
  -- 1. Obtener estado actual y datos del envío
  SELECT estado_envio, id_contrato_consignacion
  INTO v_estado_actual, v_id_contrato
  FROM app_dat_consignacion_envio
  WHERE id = p_id_envio;

  IF v_id_contrato IS NULL THEN
    RETURN QUERY SELECT FALSE, 'El envío no existe.'::TEXT;
    RETURN;
  END IF;

  -- 2. Validar si el envío ya fue aceptado o rechazado anteriormente
  IF v_estado_actual = 4 THEN
    RETURN QUERY SELECT FALSE, 'No se puede rechazar un envío que ya ha sido ACEPTADO.'::TEXT;
    RETURN;
  END IF;

  IF v_estado_actual = 5 THEN
    RETURN QUERY SELECT FALSE, 'El envío ya se encuentra RECHAZADO.'::TEXT;
    RETURN;
  END IF;

  -- 3. Si el envío está EN TRÁNSITO (estado 3), debemos devolver el stock
  --    Porque el estado 3 implica que la extracción ya fue completada y el stock rebajado.
  IF v_estado_actual = 3 THEN
    FOR v_producto IN 
      SELECT 
        id_producto,
        COALESCE(id_inventario_original, id_inventario) as id_inv_target,
        cantidad_propuesta
      FROM app_dat_consignacion_envio_producto
      WHERE id_envio = p_id_envio
    LOOP
      -- Devolver el stock al inventario original
      UPDATE app_dat_inventario_productos
      SET cantidad_final = cantidad_final + v_producto.cantidad_propuesta,
          updated_at = NOW()
      WHERE id = v_producto.id_inv_target;
    END LOOP;
  END IF;

  -- 3.b Cancelar operaciones asociadas si no están completadas
  -- Operación de extracción
  INSERT INTO app_dat_estado_operacion (id_operacion, estado, comentario, uuid)
  SELECT id_operacion_extraccion, 3, 'Operación cancelada por rechazo de envío global', p_id_usuario
  FROM app_dat_consignacion_envio
  WHERE id = p_id_envio 
    AND id_operacion_extraccion IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM app_dat_estado_operacion 
      WHERE id_operacion = id_operacion_extraccion AND estado = 2
    );

  -- Operación de recepción
  INSERT INTO app_dat_estado_operacion (id_operacion, estado, comentario, uuid)
  SELECT id_operacion_recepcion, 3, 'Operación cancelada por rechazo de envío global', p_id_usuario
  FROM app_dat_consignacion_envio
  WHERE id = p_id_envio 
    AND id_operacion_recepcion IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM app_dat_estado_operacion 
      WHERE id_operacion = id_operacion_recepcion AND estado = 2
    );

  -- 4. Actualizar el estado del envío a RECHAZADO (5)
  UPDATE app_dat_consignacion_envio
  SET 
    estado_envio = 5,
    fecha_rechazo = NOW(),
    motivo_rechazo = p_motivo_rechazo,
    id_usuario_rechazador = p_id_usuario,
    updated_at = NOW()
  WHERE id = p_id_envio;

  -- 5. Actualizar el estado de todos los productos del envío
  UPDATE app_dat_consignacion_envio_producto
  SET 
    estado_producto = 2, -- Suponiendo 2 = RECHAZADO para productos
    fecha_rechazo = NOW(),
    motivo_rechazo = p_motivo_rechazo,
    cantidad_rechazada = cantidad_propuesta,
    updated_at = NOW()
  WHERE id_envio = p_id_envio;

  -- 6. Registrar movimiento en el historial para auditoría
  INSERT INTO app_dat_consignacion_envio_movimiento (
    id_envio,
    id_usuario,
    tipo_movimiento,
    estado_anterior,
    estado_nuevo,
    descripcion,
    created_at
  ) VALUES (
    p_id_envio,
    p_id_usuario,
    3, -- 3 = MOVIMIENTO_RECHAZO (siguiendo el estándar de la tabla)
    v_estado_actual,
    5, -- 5 = RECHAZADO
    'Envío rechazado globalmente: ' || p_motivo_rechazo,
    NOW()
  );

  RETURN QUERY SELECT TRUE, 'Envío rechazado exitosamente e inventario actualizado.'::TEXT;

EXCEPTION WHEN OTHERS THEN
  RETURN QUERY SELECT FALSE, 'Error en SQL: ' || SQLERRM;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION public.rechazar_envio_consignacion IS 'Rechaza un envío de consignación y devuelve el stock si estaba en tránsito.';
