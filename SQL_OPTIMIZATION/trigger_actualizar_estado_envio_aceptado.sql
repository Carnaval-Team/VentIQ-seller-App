-- ============================================================================
-- TRIGGER: Actualizar estado de envío a ACEPTADO al completar recepción
-- ============================================================================
-- Cuando se completa una operación de recepción asociada a un envío de
-- consignación o devolución, actualiza el estado del envío a ACEPTADO (4)
-- Si es devolución, resta el valor devuelto del monto_total del contrato
-- ============================================================================

-- Función que se ejecutará cuando se actualice el estado de una operación
CREATE OR REPLACE FUNCTION actualizar_estado_envio_aceptado()
RETURNS TRIGGER AS $$
DECLARE
  v_id_envio BIGINT;
  v_tipo_operacion INTEGER;
  v_estado_anterior INTEGER;
  v_tipo_envio INTEGER;
  v_id_contrato BIGINT;
  v_valor_devolucion NUMERIC := 0;
BEGIN
  -- Solo procesar si el estado cambió a COMPLETADA (2)
  IF NEW.estado = 2 AND (OLD.estado IS NULL OR OLD.estado != 2) THEN
    
    -- Obtener el tipo de operación
    SELECT id_tipo_operacion INTO v_tipo_operacion
    FROM app_dat_operaciones
    WHERE id = NEW.id_operacion;
    
    -- Solo procesar si es una operación de RECEPCIÓN (tipo 1)
    IF v_tipo_operacion = 1 THEN
      
      -- Buscar si esta operación está asociada a un envío de consignación
      SELECT id, estado_envio, tipo_envio, id_contrato_consignacion 
      INTO v_id_envio, v_estado_anterior, v_tipo_envio, v_id_contrato
      FROM app_dat_consignacion_envio
      WHERE id_operacion_recepcion = NEW.id_operacion;
      
      -- Si se encontró un envío asociado
      IF v_id_envio IS NOT NULL THEN
        
        -- Solo actualizar si el estado actual NO es ACEPTADO (4)
        -- Puede estar en PROPUESTO (1), CONFIGURADO (2) o EN TRÁNSITO (3)
        IF v_estado_anterior != 4 THEN
          
          -- Actualizar estado del envío a ACEPTADO
          UPDATE app_dat_consignacion_envio
          SET 
            estado_envio = 4,  -- ACEPTADO
            fecha_aceptacion = CURRENT_TIMESTAMP,
            updated_at = CURRENT_TIMESTAMP
          WHERE id = v_id_envio;
          
          RAISE NOTICE '✅ Envío % actualizado a ACEPTADO al completar operación de recepción %', 
            v_id_envio, NEW.id_operacion;
          
          -- ⭐ Si es una DEVOLUCIÓN (tipo_envio = 2), restar el valor del monto_total del contrato
          IF v_tipo_envio = 2 AND v_id_contrato IS NOT NULL THEN
            
            -- Calcular el valor total de los productos devueltos
            -- Suma: cantidad * precio_costo_usd de los productos del envío
            SELECT COALESCE(SUM(cep.cantidad_propuesta * cep.precio_costo_usd), 0)
            INTO v_valor_devolucion
            FROM app_dat_consignacion_envio_producto cep
            WHERE cep.id_envio = v_id_envio;
            
            -- Restar el valor de la devolución del monto_total del contrato
            UPDATE app_dat_contrato_consignacion
            SET 
              monto_total = GREATEST(0, monto_total - v_valor_devolucion),
              updated_at = CURRENT_TIMESTAMP
            WHERE id = v_id_contrato;
            
            RAISE NOTICE '💰 Devolución aceptada - Monto restado del contrato %: $% USD', 
              v_id_contrato, v_valor_devolucion;
            RAISE NOTICE '   ℹ️ El consignatario NO debe pagar este monto al consignador';
            
          END IF;
          
        ELSE
          RAISE NOTICE '⚠️ Envío % ya está en estado ACEPTADO (no se actualiza)', v_id_envio;
        END IF;
        
      END IF;
      
    END IF;
    
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Crear el trigger en la tabla app_dat_estado_operacion
DROP TRIGGER IF EXISTS trg_actualizar_estado_envio_aceptado ON app_dat_estado_operacion;

CREATE TRIGGER trg_actualizar_estado_envio_aceptado
  AFTER INSERT OR UPDATE OF estado ON app_dat_estado_operacion
  FOR EACH ROW
  EXECUTE FUNCTION actualizar_estado_envio_aceptado();

COMMENT ON FUNCTION actualizar_estado_envio_aceptado IS 
  'Actualiza automáticamente el estado de un envío de consignación a ACEPTADO (4) cuando se completa su operación de recepción asociada. Si es devolución, resta el valor devuelto del monto_total del contrato.';

COMMENT ON TRIGGER trg_actualizar_estado_envio_aceptado ON app_dat_estado_operacion IS 
  'Trigger que actualiza el estado del envío a ACEPTADO al completar la recepción. Si es devolución, ajusta el monto_total del contrato.';

-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '✅ Trigger creado: trg_actualizar_estado_envio_aceptado';
  RAISE NOTICE '';
  RAISE NOTICE '📋 FUNCIONAMIENTO:';
  RAISE NOTICE '1. Se detecta cuando una operación cambia a estado COMPLETADA (2)';
  RAISE NOTICE '2. Verifica que sea una operación de RECEPCIÓN (tipo 1)';
  RAISE NOTICE '3. Busca si está asociada a un envío de consignación';
  RAISE NOTICE '4. Si el envío NO está en estado ACEPTADO (4)';
  RAISE NOTICE '5. Actualiza el estado del envío a ACEPTADO (4)';
  RAISE NOTICE '6. ⭐ Si es DEVOLUCIÓN: resta valor devuelto del monto_total del contrato';
  RAISE NOTICE '';
  RAISE NOTICE '🎯 ESTADOS DE ENVÍO:';
  RAISE NOTICE '   1 = PROPUESTO';
  RAISE NOTICE '   2 = CONFIGURADO';
  RAISE NOTICE '   3 = EN TRÁNSITO';
  RAISE NOTICE '   4 = ACEPTADO ← Se actualiza automáticamente';
  RAISE NOTICE '';
  RAISE NOTICE '⚙️ APLICA A:';
  RAISE NOTICE '   ✅ Envíos de consignación (tipo_envio = 1)';
  RAISE NOTICE '   ✅ Devoluciones (tipo_envio = 2) → Ajusta monto_total del contrato';
  RAISE NOTICE '';
  RAISE NOTICE '💰 AJUSTE DE MONTO EN DEVOLUCIONES:';
  RAISE NOTICE '   - Calcula: SUM(cantidad * precio_costo_usd) de productos devueltos';
  RAISE NOTICE '   - Resta del monto_total del contrato';
  RAISE NOTICE '   - El consignatario NO debe pagar este monto al consignador';
  RAISE NOTICE '';
  RAISE NOTICE '🔗 TRABAJA EN CONJUNTO CON:';
  RAISE NOTICE '   ✅ trg_actualizar_estado_envio_en_transito (completar extracción → EN TRÁNSITO)';
  RAISE NOTICE '   ✅ trg_actualizar_estado_envio_aceptado (completar recepción → ACEPTADO)';
END $$;

-- ============================================================================
