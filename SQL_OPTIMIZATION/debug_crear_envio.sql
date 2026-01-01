-- ============================================================================
-- DEBUG: Versión con logging extensivo para identificar el problema
-- ============================================================================

DROP FUNCTION IF EXISTS public.debug_crear_envio_consignacion(
  p_id_contrato BIGINT,
  p_id_almacen_origen BIGINT,
  p_id_almacen_destino BIGINT,
  p_id_usuario UUID,
  p_productos JSONB,
  p_descripcion VARCHAR,
  p_id_operacion_extraccion BIGINT
) CASCADE;

CREATE OR REPLACE FUNCTION public.debug_crear_envio_consignacion(
  p_id_contrato BIGINT,
  p_id_almacen_origen BIGINT,
  p_id_almacen_destino BIGINT,
  p_id_usuario UUID,
  p_productos JSONB,
  p_descripcion VARCHAR DEFAULT NULL,
  p_id_operacion_extraccion BIGINT DEFAULT NULL
)
RETURNS TABLE (
  success BOOLEAN,
  id_envio BIGINT,
  numero_envio VARCHAR,
  id_operacion_extraccion BIGINT,
  id_operacion_recepcion BIGINT,
  mensaje VARCHAR
) AS $$
DECLARE
  v_id_contrato_consignacion BIGINT;
  v_id_operacion_extraccion BIGINT;
  v_id_operacion_recepcion BIGINT;
  v_numero_envio VARCHAR;
  v_id_envio BIGINT;
  v_id_tienda_origen BIGINT;
  v_id_tienda_destino BIGINT;
BEGIN
  -- LOG 1: Inicio
  RAISE NOTICE 'DEBUG 1: Iniciando función con contrato=%', p_id_contrato;
  
  -- Obtener ID del contrato
  v_id_contrato_consignacion := p_id_contrato;
  RAISE NOTICE 'DEBUG 2: ID contrato obtenido=%', v_id_contrato_consignacion;
  
  -- Obtener tiendas del contrato
  SELECT id_tienda_consignadora, id_tienda_consignataria
  INTO v_id_tienda_origen, v_id_tienda_destino
  FROM app_dat_contrato_consignacion
  WHERE id = v_id_contrato_consignacion;
  
  RAISE NOTICE 'DEBUG 3: Tiendas obtenidas: origen=%, destino=%', v_id_tienda_origen, v_id_tienda_destino;
  
  -- Usar operación de extracción existente o crear nueva
  IF p_id_operacion_extraccion IS NOT NULL THEN
    v_id_operacion_extraccion := p_id_operacion_extraccion;
    RAISE NOTICE 'DEBUG 4: Usando operación extracción existente=%', v_id_operacion_extraccion;
  ELSE
    RAISE NOTICE 'DEBUG 4: Creando nueva operación de extracción';
    -- app_dat_operaciones: id, id_tipo_operacion, uuid, id_tienda, observaciones, created_at
    INSERT INTO app_dat_operaciones (
      id_tienda, id_tipo_operacion, uuid, observaciones, created_at
    ) VALUES (
      v_id_tienda_origen, 7, p_id_usuario,
      COALESCE(p_descripcion, 'Extracción para consignación'), 
      CURRENT_TIMESTAMP
    ) RETURNING id INTO v_id_operacion_extraccion;
    RAISE NOTICE 'DEBUG 4b: Operación extracción creada=%', v_id_operacion_extraccion;
  END IF;
  
  -- Crear operación de recepción
  RAISE NOTICE 'DEBUG 5: Creando operación de recepción';
  -- app_dat_operaciones: id, id_tipo_operacion, uuid, id_tienda, observaciones, created_at
  INSERT INTO app_dat_operaciones (
    id_tienda, id_tipo_operacion, uuid, observaciones, created_at
  ) VALUES (
    v_id_tienda_destino, 1, p_id_usuario,
    COALESCE(p_descripcion, 'Recepción de consignación'),
    CURRENT_TIMESTAMP
  ) RETURNING id INTO v_id_operacion_recepcion;
  
  RAISE NOTICE 'DEBUG 6: Operación recepción creada=%', v_id_operacion_recepcion;
  
  -- Generar número de envío
  v_numero_envio := 'ENV-' || TO_CHAR(CURRENT_TIMESTAMP, 'YYYYMMDD') || '-' || LPAD(nextval('app_dat_consignacion_envio_id_seq')::TEXT, 6, '0');
  RAISE NOTICE 'DEBUG 7: Número de envío generado=%', v_numero_envio;
  
  -- Validaciones
  IF v_id_contrato_consignacion IS NULL THEN
    RAISE NOTICE 'DEBUG ERROR: ID contrato es NULL';
    RETURN QUERY SELECT false::BOOLEAN, NULL::BIGINT, NULL::VARCHAR, NULL::BIGINT, NULL::BIGINT, 'Error: ID contrato es NULL'::VARCHAR;
    RETURN;
  END IF;
  
  IF v_id_operacion_extraccion IS NULL THEN
    RAISE NOTICE 'DEBUG ERROR: ID operación extracción es NULL';
    RETURN QUERY SELECT false::BOOLEAN, NULL::BIGINT, NULL::VARCHAR, NULL::BIGINT, NULL::BIGINT, 'Error: ID operación extracción es NULL'::VARCHAR;
    RETURN;
  END IF;
  
  IF v_id_operacion_recepcion IS NULL THEN
    RAISE NOTICE 'DEBUG ERROR: ID operación recepción es NULL';
    RETURN QUERY SELECT false::BOOLEAN, NULL::BIGINT, NULL::VARCHAR, NULL::BIGINT, NULL::BIGINT, 'Error: ID operación recepción es NULL'::VARCHAR;
    RETURN;
  END IF;
  
  IF v_numero_envio IS NULL OR v_numero_envio = '' THEN
    RAISE NOTICE 'DEBUG ERROR: Número de envío no generado';
    RETURN QUERY SELECT false::BOOLEAN, NULL::BIGINT, NULL::VARCHAR, NULL::BIGINT, NULL::BIGINT, 'Error: Número de envío no generado'::VARCHAR;
    RETURN;
  END IF;
  
  -- Crear envío
  RAISE NOTICE 'DEBUG 8: Creando envío en app_dat_consignacion_envio';
  BEGIN
    INSERT INTO app_dat_consignacion_envio (
      id_contrato_consignacion,
      id_operacion_extraccion,
      id_operacion_recepcion,
      numero_envio,
      estado_envio,
      fecha_propuesta,
      id_almacen_origen,
      id_almacen_destino,
      id_usuario_creador,
      estado,
      created_at,
      updated_at
    ) VALUES (
      v_id_contrato_consignacion,
      v_id_operacion_extraccion,
      v_id_operacion_recepcion,
      v_numero_envio,
      1,
      CURRENT_TIMESTAMP,
      p_id_almacen_origen,
      p_id_almacen_destino,
      p_id_usuario,
      1,
      CURRENT_TIMESTAMP,
      CURRENT_TIMESTAMP
    ) RETURNING id INTO v_id_envio;
    
    RAISE NOTICE 'DEBUG 9: Envío creado con ID=%', v_id_envio;
    
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'DEBUG ERROR en INSERT envío: %', SQLERRM;
    RETURN QUERY SELECT false::BOOLEAN, NULL::BIGINT, NULL::VARCHAR, NULL::BIGINT, NULL::BIGINT, ('Error en INSERT envío: ' || SQLERRM)::VARCHAR;
    RETURN;
  END;
  
  IF v_id_envio IS NULL THEN
    RAISE NOTICE 'DEBUG ERROR: INSERT retornó NULL';
    RETURN QUERY SELECT false::BOOLEAN, NULL::BIGINT, NULL::VARCHAR, NULL::BIGINT, NULL::BIGINT, 'Error: INSERT en app_dat_consignacion_envio retornó NULL'::VARCHAR;
    RETURN;
  END IF;
  
  -- Crear productos del envío (simplificado)
  RAISE NOTICE 'DEBUG 10: Creando productos del envío';
  DECLARE
    v_producto JSONB;
    v_id_producto BIGINT;
    v_cantidad NUMERIC;
    v_precio_costo_cup NUMERIC;
  BEGIN
    FOR v_producto IN SELECT jsonb_array_elements(p_productos)
    LOOP
      v_id_producto := (v_producto->>'id_producto')::BIGINT;
      v_cantidad := (v_producto->>'cantidad')::NUMERIC;
      v_precio_costo_cup := (v_producto->>'precio_costo_cup')::NUMERIC;
      
      RAISE NOTICE 'DEBUG 10a: Insertando producto=%, cantidad=%, precio=%', v_id_producto, v_cantidad, v_precio_costo_cup;
      
      INSERT INTO app_dat_consignacion_envio_producto (
        id_envio, id_producto, cantidad_propuesta, precio_costo_cup, estado_producto, created_at
      ) VALUES (
        v_id_envio,
        v_id_producto,
        v_cantidad,
        v_precio_costo_cup,
        1,
        CURRENT_TIMESTAMP
      );
    END LOOP;
    
    RAISE NOTICE 'DEBUG 11: Productos insertados correctamente';
    
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'DEBUG ERROR en productos: %', SQLERRM;
  END;
  
  -- Retornar resultado exitoso
  RAISE NOTICE 'DEBUG 12: Retornando resultado exitoso';
  RETURN QUERY SELECT 
    true::BOOLEAN,
    v_id_envio::BIGINT,
    v_numero_envio::VARCHAR,
    v_id_operacion_extraccion::BIGINT,
    v_id_operacion_recepcion::BIGINT,
    'Envío creado exitosamente'::VARCHAR;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'DEBUG ERROR GENERAL: %', SQLERRM;
  RETURN QUERY SELECT 
    false::BOOLEAN, NULL::BIGINT, NULL::VARCHAR, NULL::BIGINT, NULL::BIGINT,
    ('Error general: ' || SQLERRM)::VARCHAR;
END;
$$ LANGUAGE plpgsql;

-- Para ver los logs en Supabase, ejecutar:
-- SELECT * FROM debug_crear_envio_consignacion(25, 1, 1, 'uuid-aqui', '[{"id_producto": 4475, "cantidad": 500, "precio_costo_cup": 456.75}]'::jsonb, null, 38609);
