-- ============================================================================
-- FUNCIÓN: rechazar_producto_envio_consignacion (MEJORADO)
-- DESCRIPCIÓN: Rechaza un producto individual dentro de un envío de consignación.
--              - Elimina el producto de la operación de extracción
--              - Devuelve el stock si el envío está EN TRÁNSITO
--              - Cancela la operación de extracción si es el último producto
-- ============================================================================

CREATE OR REPLACE FUNCTION public.rechazar_producto_envio_consignacion(
  p_id_envio BIGINT,
  p_id_envio_producto BIGINT,
  p_id_usuario UUID,
  p_motivo_rechazo TEXT
)
RETURNS TABLE (
  success BOOLEAN,
  mensaje TEXT
) AS $$
DECLARE
  v_estado_envio INTEGER;
  v_cantidad_propuesta NUMERIC;
  v_id_inv_target BIGINT;
  v_id_operacion_extraccion BIGINT;
  v_id_extraccion_producto BIGINT;
  v_cantidad_extraccion NUMERIC;
BEGIN
  -- 1. Obtener datos del producto y del envío
  SELECT 
    ce.estado_envio,
    cep.cantidad_propuesta,
    COALESCE(cep.id_inventario_original, cep.id_inventario),
    ce.id_operacion_extraccion
  INTO 
    v_estado_envio,
    v_cantidad_propuesta,
    v_id_inv_target,
    v_id_operacion_extraccion
  FROM app_dat_consignacion_envio ce
  JOIN app_dat_consignacion_envio_producto cep ON ce.id = cep.id_envio
  WHERE ce.id = p_id_envio AND cep.id = p_id_envio_producto;

  IF v_estado_envio IS NULL THEN
    RETURN QUERY SELECT FALSE, 'Producto o envío no encontrado.'::TEXT;
    RETURN;
  END IF;

  -- 2. Validar estado del producto
  IF EXISTS (
    SELECT 1 FROM app_dat_consignacion_envio_producto 
    WHERE id = p_id_envio_producto AND estado_producto = 3 -- 3 = ACEPTADO
  ) THEN
    RETURN QUERY SELECT FALSE, 'No se puede rechazar un producto que ya ha sido ACEPTADO.'::TEXT;
    RETURN;
  END IF;

  -- 3. Si está en tránsito, devolver stock de este producto
  IF v_estado_envio = 3 THEN
    UPDATE app_dat_inventario_productos
    SET cantidad_final = cantidad_final + v_cantidad_propuesta,
        updated_at = NOW()
    WHERE id = v_id_inv_target;
  END IF;

  -- 4. Actualizar estado del producto en el envío
  UPDATE app_dat_consignacion_envio_producto
  SET 
    estado_producto = 2, -- 2 = RECHAZADO
    motivo_rechazo = p_motivo_rechazo,
    fecha_rechazo = NOW(),
    cantidad_rechazada = v_cantidad_propuesta,
    updated_at = NOW()
  WHERE id = p_id_envio_producto;

  -- 5. ⭐ NUEVO: Eliminar el producto de la operación de extracción
  IF v_id_operacion_extraccion IS NOT NULL THEN
    -- Obtener el ID del producto de extracción asociado
    SELECT ep.id, ep.cantidad
    INTO v_id_extraccion_producto, v_cantidad_extraccion
    FROM app_dat_extraccion_productos ep
    WHERE ep.id_operacion = v_id_operacion_extraccion
      AND ep.id_producto = (
        SELECT id_producto FROM app_dat_consignacion_envio_producto 
        WHERE id = p_id_envio_producto
      )
    LIMIT 1;

    -- Si existe, eliminarlo de la operación de extracción
    IF v_id_extraccion_producto IS NOT NULL THEN
      DELETE FROM app_dat_extraccion_productos
      WHERE id = v_id_extraccion_producto;
    END IF;
  END IF;

  -- 6. Registrar movimiento del producto
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
    3, -- 3 = MOVIMIENTO_RECHAZO
    v_estado_envio,
    v_estado_envio, -- El estado del envío no cambia por un rechazo individual
    'Producto rechazado individualmente: ' || p_motivo_rechazo,
    NOW()
  );

  -- 7. Verificar si todos los productos del envío están ahora procesados (ya no hay ninguno en estado 1 = PROPUESTO)
  IF NOT EXISTS (
    SELECT 1 FROM app_dat_consignacion_envio_producto
    WHERE id_envio = p_id_envio AND estado_producto = 1 -- 1 = PROPUESTO/PENDIENTE
  ) THEN
    -- Si no hay ninguno ACEPTADO (estado 3), procedemos al rechazo global del envío
    IF NOT EXISTS (
      SELECT 1 FROM app_dat_consignacion_envio_producto
      WHERE id_envio = p_id_envio AND estado_producto = 3 -- 3 = ACEPTADO
    ) THEN
      -- Actualizar el envío global a RECHAZADO (5)
      UPDATE app_dat_consignacion_envio
      SET 
        estado_envio = 5,
        fecha_rechazo = NOW(),
        id_usuario_rechazador = p_id_usuario,
        motivo_rechazo = 'Rechazado automáticamente al rechazar todos sus productos: ' || p_motivo_rechazo,
        updated_at = NOW()
      WHERE id = p_id_envio;

      -- Registrar movimiento del cierre global del envío
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
        3, -- MOVIMIENTO_RECHAZO
        v_estado_envio,
        5, -- RECHAZADO
        'Envío cerrado globalmente por rechazo de todos sus productos.',
        NOW()
      );

      -- Cancelar operaciones asociadas si existen y no están completadas
      -- Operación de extracción
      INSERT INTO app_dat_estado_operacion (id_operacion, estado, comentario, uuid)
      SELECT id_operacion_extraccion, 3, 'Cancelado: último producto del envío rechazado', p_id_usuario
      FROM app_dat_consignacion_envio
      WHERE id = p_id_envio 
        AND id_operacion_extraccion IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM app_dat_estado_operacion 
          WHERE id_operacion = id_operacion_extraccion AND estado = 2
        );

      -- Operación de recepción
      INSERT INTO app_dat_estado_operacion (id_operacion, estado, comentario, uuid)
      SELECT id_operacion_recepcion, 3, 'Cancelado: último producto del envío rechazado', p_id_usuario
      FROM app_dat_consignacion_envio
      WHERE id = p_id_envio 
        AND id_operacion_recepcion IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM app_dat_estado_operacion 
          WHERE id_operacion = id_operacion_recepcion AND estado = 2
        );
        
      RETURN QUERY SELECT TRUE, 'Producto rechazado. Como era el último, el envío se ha RECHAZADO globalmente.'::TEXT;
      RETURN;
    END IF;
  END IF;

  RETURN QUERY SELECT TRUE, 'Producto rechazado exitosamente y removido de la operación de extracción.'::TEXT;

EXCEPTION WHEN OTHERS THEN
  RETURN QUERY SELECT FALSE, 'Error en SQL: ' || SQLERRM;
END;
$$ LANGUAGE plpgsql;
