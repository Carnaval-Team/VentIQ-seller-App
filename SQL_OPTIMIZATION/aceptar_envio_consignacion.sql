-- ============================================================================
-- FUNCIÓN: aceptar_envio_consignacion
-- DESCRIPCIÓN: Acepta un envío de consignación
-- PASO 1: Duplica productos si es necesario
-- PASO 2: Crea operación de RECEPCIÓN
-- PASO 3: Inserta productos de recepción con presentación correcta
-- PASO 4: Actualiza envío a estado EN_TRANSITO
-- ============================================================================

DROP FUNCTION IF EXISTS public.aceptar_envio_consignacion(
  p_id_envio BIGINT,
  p_id_usuario UUID,
  p_precios_productos JSONB
) CASCADE;

CREATE OR REPLACE FUNCTION public.aceptar_envio_consignacion(
  p_id_envio BIGINT,
  p_id_usuario UUID,
  p_precios_productos JSONB
)
RETURNS TABLE (
  success BOOLEAN,
  id_operacion_extraccion BIGINT,
  id_operacion_recepcion BIGINT,
  mensaje TEXT
) AS $$
DECLARE
  v_id_contrato BIGINT;
  v_id_tienda_origen BIGINT;
  v_id_tienda_destino BIGINT;
  v_id_operacion_extraccion BIGINT;
  v_id_operacion_recepcion BIGINT;
  v_numero_envio VARCHAR;
  v_id_ubicacion BIGINT;
  v_producto RECORD;
  v_id_producto_destino BIGINT;
  v_id_presentacion_base BIGINT;
  v_duplicacion_result RECORD;
BEGIN
  -- 1. Obtener datos del envío
  SELECT 
    ce.id_contrato_consignacion,
    cc.id_tienda_consignadora,
    cc.id_tienda_consignataria,
    ce.id_operacion_extraccion,
    ce.numero_envio
  INTO v_id_contrato, v_id_tienda_origen, v_id_tienda_destino, v_id_operacion_extraccion, v_numero_envio
  FROM app_dat_consignacion_envio ce
  INNER JOIN app_dat_contrato_consignacion cc ON ce.id_contrato_consignacion = cc.id
  WHERE ce.id = p_id_envio;
  
  IF v_id_contrato IS NULL THEN
    RETURN QUERY SELECT 
      false::BOOLEAN, NULL::BIGINT, NULL::BIGINT,
      'Envío de consignación no encontrado'::TEXT;
    RETURN;
  END IF;
  
  -- 1b. Obtener id_ubicacion (zona de consignación) del contrato
  SELECT cz.id_zona
  INTO v_id_ubicacion
  FROM app_dat_consignacion_zona cz
  WHERE cz.id_contrato = v_id_contrato
  LIMIT 1;
  
  -- Si no hay zona, usar la primera ubicación del almacén destino como fallback
  IF v_id_ubicacion IS NULL THEN
    SELECT dla.id
    INTO v_id_ubicacion
    FROM app_dat_layout_almacen dla
    INNER JOIN app_dat_almacen a ON dla.id_almacen = a.id
    WHERE a.id_tienda = v_id_tienda_destino
    LIMIT 1;
  END IF;
  
  -- Validar que se encontró una ubicación válida
  IF v_id_ubicacion IS NULL THEN
    RETURN QUERY SELECT 
      false::BOOLEAN, v_id_operacion_extraccion::BIGINT, NULL::BIGINT,
      'Error: No se encontró ubicación de destino para la tienda consignataria'::TEXT;
    RETURN;
  END IF;
  
  -- 2. Crear operación de RECEPCIÓN
  INSERT INTO app_dat_operaciones (
    id_tienda,
    id_tipo_operacion,
    uuid,
    observaciones,
    created_at
  ) VALUES (
    v_id_tienda_destino,
    1, -- RECEPCION
    p_id_usuario,
    'Recepción de envío de consignación ' || v_numero_envio,
    CURRENT_TIMESTAMP
  ) RETURNING id INTO v_id_operacion_recepcion;
  
  IF v_id_operacion_recepcion IS NULL THEN
    RETURN QUERY SELECT 
      false::BOOLEAN, v_id_operacion_extraccion::BIGINT, NULL::BIGINT,
      'Error creando operación de recepción'::TEXT;
    RETURN;
  END IF;
  
  -- 3. Guardar estado inicial de la operación de recepción
  INSERT INTO app_dat_estado_operacion (
    id_operacion,
    estado,
    comentario
  ) VALUES (
    v_id_operacion_recepcion,
    1, -- PENDIENTE
    'Operación de recepción en consignación creada'
  );
  
  -- 3b. Registrar la operación de recepción en app_dat_operacion_recepcion
  INSERT INTO app_dat_operacion_recepcion (
    id_operacion,
    recibido_por,
    motivo,
    observaciones
  ) VALUES (
    v_id_operacion_recepcion,
    'Sistema',
    1,
    'Recepción de envío de consignación ' || v_numero_envio
  );
  
  -- 4. Procesar cada producto: duplicar si es necesario y crear registro de recepción
  FOR v_producto IN 
    SELECT 
      cep.id, 
      cep.id_producto, 
      cep.cantidad_propuesta,
      COALESCE((precio_data->>'precio_venta_cup')::NUMERIC, cep.precio_venta_cup) AS precio_venta_cup,
      COALESCE((precio_data->>'precio_costo_usd')::NUMERIC, 0) AS precio_costo_usd
    FROM app_dat_consignacion_envio_producto cep
    LEFT JOIN LATERAL jsonb_array_elements(p_precios_productos) AS precio_data 
      ON (precio_data->>'id_producto')::BIGINT = cep.id_producto
    WHERE cep.id_envio = p_id_envio
  LOOP
    -- 4a. Duplicar producto si es necesario (busca por SKU, reutiliza si existe)
    SELECT * FROM duplicar_producto_si_necesario(
      v_producto.id_producto,
      v_id_tienda_destino,
      v_id_contrato::INT,
      v_id_tienda_origen::INT,
      p_id_usuario
    ) INTO v_duplicacion_result;
    
    IF v_duplicacion_result.success THEN
      v_id_producto_destino := v_duplicacion_result.id_producto_resultado;
    ELSE
      -- Si falla la duplicación, usar el producto original
      v_id_producto_destino := v_producto.id_producto;
    END IF;
    
    -- 4b. Obtener presentación base del producto duplicado/reutilizado
    SELECT pp.id
    INTO v_id_presentacion_base
    FROM app_dat_producto_presentacion pp
    WHERE pp.id_producto = v_id_producto_destino
      AND pp.es_base = true
    LIMIT 1;
    
    -- 4c. Actualizar precio_venta en tienda consignataria para el producto duplicado
    -- Primero cerrar el precio anterior (si existe)
    UPDATE app_dat_precio_venta
    SET fecha_hasta = CURRENT_DATE - INTERVAL '1 day'
    WHERE id_producto = v_id_producto_destino
      AND fecha_hasta IS NULL;
    
    -- Luego insertar el nuevo precio
    INSERT INTO app_dat_precio_venta (
      id_producto,
      precio_venta_cup,
      fecha_desde,
      created_at
    ) VALUES (
      v_id_producto_destino,
      v_producto.precio_venta_cup,
      CURRENT_DATE,
      CURRENT_TIMESTAMP
    );
    
    -- 4d. Crear registro de recepción con presentación correcta y precio_unitario en USD
    INSERT INTO app_dat_recepcion_productos (
      id_operacion,
      id_producto,
      id_presentacion,
      id_ubicacion,
      cantidad,
      precio_unitario,
      created_at
    ) VALUES (
      v_id_operacion_recepcion,
      v_id_producto_destino,
      v_id_presentacion_base,
      v_id_ubicacion,
      v_producto.cantidad_propuesta,
      v_producto.precio_costo_usd,
      CURRENT_TIMESTAMP
    );
  END LOOP;
  
  -- 5. Actualizar envío: asignar operación de recepción y cambiar estado a EN_TRANSITO (estado 3)
  UPDATE app_dat_consignacion_envio
  SET 
    id_operacion_recepcion = v_id_operacion_recepcion,
    estado_envio = 3, -- EN_TRANSITO
    fecha_envio = CURRENT_TIMESTAMP,
    id_usuario_aceptador = p_id_usuario,
    updated_at = CURRENT_TIMESTAMP
  WHERE id = p_id_envio;
  
  -- 6. Retornar resultado exitoso
  RETURN QUERY SELECT 
    true::BOOLEAN AS success,
    v_id_operacion_extraccion::BIGINT AS id_operacion_extraccion,
    v_id_operacion_recepcion::BIGINT AS id_operacion_recepcion,
    'Envío aceptado exitosamente'::TEXT AS mensaje;

EXCEPTION WHEN OTHERS THEN
  RETURN QUERY SELECT 
    false::BOOLEAN AS success,
    NULL::BIGINT AS id_operacion_extraccion,
    NULL::BIGINT AS id_operacion_recepcion,
    ('Error: ' || SQLERRM)::TEXT AS mensaje;
END;
$$ LANGUAGE plpgsql;
