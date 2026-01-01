-- ============================================================================
-- FIX: Eliminar versiones antiguas y crear la nueva versión correcta
-- ============================================================================

-- 1. Eliminar la función antigua (si existe)
DROP FUNCTION IF EXISTS public.crear_envio_consignacion(
  p_id_contrato BIGINT,
  p_id_almacen_origen BIGINT,
  p_id_almacen_destino BIGINT,
  p_id_usuario UUID,
  p_productos JSONB,
  p_descripcion VARCHAR,
  p_id_operacion_extraccion BIGINT
) CASCADE;

DROP FUNCTION IF EXISTS public.crear_envio_consignacion(
  p_id_contrato BIGINT,
  p_id_almacen_origen BIGINT,
  p_id_almacen_destino BIGINT,
  p_id_usuario UUID,
  p_productos JSONB,
  p_descripcion TEXT,
  p_id_operacion_extraccion BIGINT
) CASCADE;

-- 2. Crear la nueva versión correcta
CREATE OR REPLACE FUNCTION public.crear_envio_consignacion(
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
  v_id_tienda_origen BIGINT;
  v_id_tienda_destino BIGINT;
  v_id_operacion_extraccion BIGINT;
  v_id_operacion_recepcion BIGINT;
  v_id_envio BIGINT;
  v_numero_envio VARCHAR;
  v_producto JSONB;
  v_id_producto_original BIGINT;
  v_id_producto_destino BIGINT;
  v_cantidad NUMERIC;
  v_precio_costo_usd NUMERIC;
  v_precio_costo_cup NUMERIC;
  v_tasa_cambio NUMERIC;
  v_id_inventario_origen BIGINT;
  v_duplicacion_result RECORD;
  v_contador INT := 0;
BEGIN
  -- 1. Validar contrato y obtener tiendas
  SELECT id, id_tienda_consignadora, id_tienda_consignataria
  INTO v_id_contrato_consignacion, v_id_tienda_origen, v_id_tienda_destino
  FROM app_dat_contrato_consignacion
  WHERE id = p_id_contrato;
  
  IF v_id_contrato_consignacion IS NULL THEN
    RETURN QUERY SELECT 
      false::BOOLEAN, NULL::BIGINT, NULL::VARCHAR, NULL::BIGINT, NULL::BIGINT,
      'Contrato de consignación no encontrado'::VARCHAR;
    RETURN;
  END IF;
  
  -- 2. Crear operación de EXTRACCIÓN en tienda consignadora
  -- IMPORTANTE: NO actualizar precio_costo aquí
  INSERT INTO app_dat_operaciones (
    id_tienda, id_tipo_operacion, uuid, observaciones, created_at
  ) VALUES (
    v_id_tienda_origen,
    (SELECT id FROM app_nom_tipo_operacion WHERE denominacion = 'Extracción'),
    p_id_usuario,
    'Extracción para consignación - Contrato: ' || v_id_contrato_consignacion,
    CURRENT_TIMESTAMP
  ) RETURNING id INTO v_id_operacion_extraccion;
  
  IF v_id_operacion_extraccion IS NULL THEN
    RETURN QUERY SELECT 
      false::BOOLEAN, NULL::BIGINT, NULL::VARCHAR, NULL::BIGINT, NULL::BIGINT,
      'Error creando operación de extracción'::VARCHAR;
    RETURN;
  END IF;
  
  -- 3. Crear operación de RECEPCIÓN en tienda consignataria
  INSERT INTO app_dat_operaciones (
    id_tienda, id_tipo_operacion, uuid, observaciones, created_at
  ) VALUES (
    v_id_tienda_destino,
    (SELECT id FROM app_nom_tipo_operacion WHERE denominacion = 'Recepción'),
    p_id_usuario,
    'Recepción para consignación - Contrato: ' || v_id_contrato_consignacion,
    CURRENT_TIMESTAMP
  ) RETURNING id INTO v_id_operacion_recepcion;
  
  IF v_id_operacion_recepcion IS NULL THEN
    RETURN QUERY SELECT 
      false::BOOLEAN, NULL::BIGINT, NULL::VARCHAR, NULL::BIGINT, NULL::BIGINT,
      'Error creando operación de recepción'::VARCHAR;
    RETURN;
  END IF;
  
  -- 4. OMITIR procesamiento de productos por ahora para crear el envío primero
  -- Los productos se procesarán después de crear el envío
  v_contador := jsonb_array_length(p_productos);
  
  -- 5. Generar número de envío único
  v_numero_envio := 'ENV-' || TO_CHAR(CURRENT_TIMESTAMP, 'YYYYMMDD') || '-' || LPAD(nextval('app_dat_consignacion_envio_id_seq')::TEXT, 6, '0');
  
  -- Validación: Verificar que tenemos todos los datos necesarios
  IF v_id_contrato_consignacion IS NULL THEN
    RETURN QUERY SELECT 
      false::BOOLEAN, NULL::BIGINT, NULL::VARCHAR, NULL::BIGINT, NULL::BIGINT,
      'Error: ID contrato es NULL'::VARCHAR;
    RETURN;
  END IF;
  
  IF v_id_operacion_extraccion IS NULL THEN
    RETURN QUERY SELECT 
      false::BOOLEAN, NULL::BIGINT, NULL::VARCHAR, NULL::BIGINT, NULL::BIGINT,
      'Error: ID operación extracción es NULL'::VARCHAR;
    RETURN;
  END IF;
  
  IF v_id_operacion_recepcion IS NULL THEN
    RETURN QUERY SELECT 
      false::BOOLEAN, NULL::BIGINT, NULL::VARCHAR, NULL::BIGINT, NULL::BIGINT,
      'Error: ID operación recepción es NULL'::VARCHAR;
    RETURN;
  END IF;
  
  IF v_numero_envio IS NULL OR v_numero_envio = '' THEN
    RETURN QUERY SELECT 
      false::BOOLEAN, NULL::BIGINT, NULL::VARCHAR, NULL::BIGINT, NULL::BIGINT,
      'Error: Número de envío no generado'::VARCHAR;
    RETURN;
  END IF;
  
  -- 6. Crear ENVÍO de consignación
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
      1,  -- ESTADO_PROPUESTO
      CURRENT_TIMESTAMP,
      p_id_almacen_origen,
      p_id_almacen_destino,
      p_id_usuario,
      1,  -- estado = 1 (activo)
      CURRENT_TIMESTAMP,
      CURRENT_TIMESTAMP
    ) RETURNING id INTO v_id_envio;
  EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT 
      false::BOOLEAN, NULL::BIGINT, NULL::VARCHAR, NULL::BIGINT, NULL::BIGINT,
      ('Error en INSERT envío: ' || SQLERRM)::VARCHAR;
    RETURN;
  END;
  
  IF v_id_envio IS NULL THEN
    RETURN QUERY SELECT 
      false::BOOLEAN, NULL::BIGINT, NULL::VARCHAR, NULL::BIGINT, NULL::BIGINT,
      'Error: INSERT en app_dat_consignacion_envio retornó NULL'::VARCHAR;
    RETURN;
  END IF;
  
  -- 7. Crear ENVÍO_PRODUCTOS para cada producto (usando producto original por ahora)
  FOR v_producto IN SELECT jsonb_array_elements(p_productos)
  LOOP
    v_id_producto_original := (v_producto->>'id_producto')::BIGINT;
    v_cantidad := (v_producto->>'cantidad')::NUMERIC;
    v_precio_costo_cup := (v_producto->>'precio_costo_cup')::NUMERIC;
    
    -- Por ahora usar el producto original, la duplicación se hará después
    INSERT INTO app_dat_consignacion_envio_producto (
      id_envio, id_producto, cantidad_propuesta, precio_costo_cup, estado_producto, created_at
    ) VALUES (
      v_id_envio,
      v_id_producto_original,  -- Usar producto original temporalmente
      v_cantidad,
      v_precio_costo_cup,
      1,  -- PRODUCTO_PROPUESTO
      CURRENT_TIMESTAMP
    );
  END LOOP;
  
  RETURN QUERY SELECT 
    true::BOOLEAN,
    v_id_envio::BIGINT,
    v_numero_envio::VARCHAR,
    v_id_operacion_extraccion::BIGINT,
    v_id_operacion_recepcion::BIGINT,
    format('Envío creado exitosamente. %s productos procesados', v_contador)::VARCHAR;

EXCEPTION WHEN OTHERS THEN
  RETURN QUERY SELECT 
    false::BOOLEAN, NULL::BIGINT, NULL::VARCHAR, NULL::BIGINT, NULL::BIGINT,
    ('Error: ' || SQLERRM)::VARCHAR;
END;
$$ LANGUAGE plpgsql;
