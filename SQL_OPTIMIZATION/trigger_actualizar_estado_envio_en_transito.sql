-- ============================================================================
-- TRIGGER: Actualizar estado de envío a EN TRÁNSITO al completar extracción
-- ============================================================================
-- Cuando se completa una operación de extracción asociada a un envío de
-- consignación o devolución, actualiza el estado del envío a EN TRÁNSITO (3)
-- ============================================================================

-- Función que se ejecutará cuando se actualice el estado de una operación
CREATE OR REPLACE FUNCTION actualizar_estado_envio_en_transito()
RETURNS TRIGGER AS $$
DECLARE
  v_id_envio BIGINT;
  v_tipo_operacion INTEGER;
  v_estado_anterior INTEGER;
BEGIN
  -- Solo procesar si el estado cambió a COMPLETADA (2)
  IF NEW.estado = 2 AND (OLD.estado IS NULL OR OLD.estado != 2) THEN
    
    -- Obtener el tipo de operación
    SELECT id_tipo_operacion INTO v_tipo_operacion
    FROM app_dat_operaciones
    WHERE id = NEW.id_operacion;
    
    -- Solo procesar si es una operación de EXTRACCIÓN (tipo 7)
    IF v_tipo_operacion = 7 THEN
      
      -- Buscar si esta operación está asociada a un envío de consignación
      SELECT id, estado_envio INTO v_id_envio, v_estado_anterior
      FROM app_dat_consignacion_envio
      WHERE id_operacion_extraccion = NEW.id_operacion;
      
      -- Si se encontró un envío asociado
      IF v_id_envio IS NOT NULL THEN
        
        -- Solo actualizar si el estado actual es PROPUESTO (1) o CONFIGURADO (2)
        -- No actualizar si ya está EN TRÁNSITO (3) o ACEPTADO (4)
        IF v_estado_anterior IN (1, 2) THEN
          
          -- Actualizar estado del envío a EN TRÁNSITO
          UPDATE app_dat_consignacion_envio
          SET 
            estado_envio = 3,  -- EN TRÁNSITO
            fecha_envio = CURRENT_TIMESTAMP,
            updated_at = CURRENT_TIMESTAMP
          WHERE id = v_id_envio;
          
          RAISE NOTICE '✅ Envío % actualizado a EN TRÁNSITO al completar operación de extracción %', 
            v_id_envio, NEW.id_operacion;
        ELSE
          RAISE NOTICE '⚠️ Envío % ya está en estado % (no se actualiza)', 
            v_id_envio, v_estado_anterior;
        END IF;
        
      END IF;
      
    END IF;
    
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Crear el trigger en la tabla app_dat_estado_operacion
DROP TRIGGER IF EXISTS trg_actualizar_estado_envio_en_transito ON app_dat_estado_operacion;

CREATE TRIGGER trg_actualizar_estado_envio_en_transito
  AFTER INSERT OR UPDATE OF estado ON app_dat_estado_operacion
  FOR EACH ROW
  EXECUTE FUNCTION actualizar_estado_envio_en_transito();

COMMENT ON FUNCTION actualizar_estado_envio_en_transito IS 
  'Actualiza automáticamente el estado de un envío de consignación a EN TRÁNSITO (3) cuando se completa su operación de extracción asociada';

COMMENT ON TRIGGER trg_actualizar_estado_envio_en_transito ON app_dat_estado_operacion IS 
  'Trigger que actualiza el estado del envío a EN TRÁNSITO al completar la extracción';

-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '✅ Trigger creado: trg_actualizar_estado_envio_en_transito';
  RAISE NOTICE '';
  RAISE NOTICE '📋 FUNCIONAMIENTO:';
  RAISE NOTICE '1. Se detecta cuando una operación cambia a estado COMPLETADA (2)';
  RAISE NOTICE '2. Verifica que sea una operación de EXTRACCIÓN (tipo 7)';
  RAISE NOTICE '3. Busca si está asociada a un envío de consignación';
  RAISE NOTICE '4. Si el envío está en estado PROPUESTO (1) o CONFIGURADO (2)';
  RAISE NOTICE '5. Actualiza el estado del envío a EN TRÁNSITO (3)';
  RAISE NOTICE '';
  RAISE NOTICE '🎯 ESTADOS DE ENVÍO:';
  RAISE NOTICE '   1 = PROPUESTO';
  RAISE NOTICE '   2 = CONFIGURADO';
  RAISE NOTICE '   3 = EN TRÁNSITO ← Se actualiza automáticamente';
  RAISE NOTICE '   4 = ACEPTADO';
  RAISE NOTICE '';
  RAISE NOTICE '⚙️ APLICA A:';
  RAISE NOTICE '   ✅ Envíos de consignación (tipo_envio = 1)';
  RAISE NOTICE '   ✅ Devoluciones (tipo_envio = 2)';
END $$;

-- ============================================================================
