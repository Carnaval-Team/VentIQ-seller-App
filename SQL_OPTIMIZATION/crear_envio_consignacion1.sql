
DECLARE
  v_id_contrato_consignacion BIGINT;
  v_id_operacion_extraccion BIGINT;
  v_id_operacion_recepcion BIGINT;
  v_numero_envio VARCHAR;
  v_id_envio BIGINT;
  v_id_tienda_origen BIGINT;
  v_id_tienda_destino BIGINT;
  v_producto JSONB;
  v_id_producto_original BIGINT;
  v_id_producto_destino BIGINT;
  v_cantidad NUMERIC;
  v_precio_costo_cup NUMERIC;
  v_id_inventario BIGINT;
BEGIN
  -- 1. Obtener tiendas del contrato
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
  
  -- 2. Usar operación de EXTRACCIÓN existente o crear una nueva
  IF p_id_operacion_extraccion IS NOT NULL THEN
    -- Usar la operación de extracción existente
    v_id_operacion_extraccion := p_id_operacion_extraccion;
  ELSE
    -- Crear nueva operación de extracción si no existe
    INSERT INTO app_dat_operaciones (
      id_tienda, id_tipo_operacion, uuid, observaciones, created_at
    ) VALUES (
      v_id_tienda_origen, 7, p_id_usuario,
      COALESCE(p_descripcion, 'Extracción para consignación'), 
      CURRENT_TIMESTAMP
    ) RETURNING id INTO v_id_operacion_extraccion;
    
    IF v_id_operacion_extraccion IS NULL THEN
      RETURN QUERY SELECT 
        false::BOOLEAN, NULL::BIGINT, NULL::VARCHAR, NULL::BIGINT, NULL::BIGINT,
        'Error creando operación de extracción'::VARCHAR;
      RETURN;
    END IF;
  END IF;
  
  -- 3. La operación de RECEPCIÓN se crea después cuando se confirma la recepción
  -- No se crea aquí, solo se crea la operación de EXTRACCIÓN
  v_id_operacion_recepcion := NULL;
  
  -- 4. Generar número de envío
  v_numero_envio := 'ENV-' || TO_CHAR(CURRENT_TIMESTAMP, 'YYYYMMDD') || '-' || LPAD(nextval('app_dat_consignacion_envio_id_seq')::TEXT, 6, '0');
  
  -- 5. Crear ENVÍO de consignación PRIMERO
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
  
  IF v_id_envio IS NULL THEN
    RETURN QUERY SELECT 
      false::BOOLEAN, NULL::BIGINT, NULL::VARCHAR, NULL::BIGINT, NULL::BIGINT,
      'Error: INSERT en app_dat_consignacion_envio retornó NULL'::VARCHAR;
    RETURN;
  END IF;
  
  -- 6. Crear ENVÍO_PRODUCTOS para cada producto
  FOR v_producto IN SELECT jsonb_array_elements(p_productos)
  LOOP
    v_id_producto_original := (v_producto->>'id_producto')::BIGINT;
    v_id_inventario := (v_producto->>'id_inventario')::BIGINT;
    v_cantidad := (v_producto->>'cantidad')::NUMERIC;
    v_precio_costo_cup := (v_producto->>'precio_costo_cup')::NUMERIC;
    
    RAISE NOTICE 'Insertando producto: id_envio=%, id_inventario=%, id_producto=%, cantidad=%', 
      v_id_envio, v_id_inventario, v_id_producto_original, v_cantidad;
    
    -- Insertar producto del envío usando el producto original
    -- Guardar ambos precios: precio_costo_usd (configurado) y precio_costo_cup (configurado)
    INSERT INTO app_dat_consignacion_envio_producto (
      id_envio, id_inventario, id_producto, cantidad_propuesta, precio_costo_cup, precio_costo_usd, estado_producto, created_at
    ) VALUES (
      v_id_envio,
      v_id_inventario,
      v_id_producto_original,
      v_cantidad,
      v_precio_costo_cup,
      (v_producto->>'precio_costo_usd')::NUMERIC,
      1,
      CURRENT_TIMESTAMP
    );
    
    RAISE NOTICE 'Producto insertado exitosamente';
  END LOOP;
  
  -- Retornar resultado exitoso
  RETURN QUERY SELECT 
    true::BOOLEAN AS success,
    v_id_envio::BIGINT AS id_envio,
    v_numero_envio::VARCHAR AS numero_envio,
    v_id_operacion_extraccion::BIGINT AS id_operacion_extraccion,
    v_id_operacion_recepcion::BIGINT AS id_operacion_recepcion,
    'Envío creado exitosamente'::VARCHAR AS mensaje;

EXCEPTION WHEN OTHERS THEN
  RETURN QUERY SELECT 
    false::BOOLEAN AS success,
    NULL::BIGINT AS id_envio,
    NULL::VARCHAR AS numero_envio,
    NULL::BIGINT AS id_operacion_extraccion,
    NULL::BIGINT AS id_operacion_recepcion,
    ('Error: ' || SQLERRM)::VARCHAR AS mensaje;
END; y el codigo de fn_actualizar_precio_promedio es: 
