DECLARE
  v_id_operacion BIGINT;
  v_id_tipo_operacion BIGINT;
  v_producto_record JSONB;
  v_cantidad_total NUMERIC := 0;
  v_result JSONB;
  v_error_message TEXT;
  v_tienda_exists BOOLEAN;
  v_motivo_exists BOOLEAN;
BEGIN
  -- Validación de existencia de referencias
  SELECT EXISTS(SELECT 1 FROM app_dat_tienda WHERE id = p_id_tienda) 
  INTO v_tienda_exists;
  
  SELECT EXISTS(SELECT 1 FROM app_nom_motivo_extraccion WHERE id = p_id_motivo_operacion) 
  INTO v_motivo_exists;
  
  IF NOT v_tienda_exists THEN
    RAISE EXCEPTION 'La tienda con ID % no existe', p_id_tienda;
  END IF;
  
  IF NOT v_motivo_exists THEN
    RAISE EXCEPTION 'El motivo de extracción con ID % no existe', p_id_motivo_operacion;
  END IF;
  
  IF jsonb_array_length(p_productos) = 0 THEN
    RAISE EXCEPTION 'Debe incluir al menos un producto';
  END IF;

  -- Obtener ID del tipo de operación "Extracción" (asumiendo que existe)
  SELECT id INTO v_id_tipo_operacion 
  FROM app_nom_tipo_operacion 
  WHERE denominacion ILIKE '%extraccion%' OR denominacion ILIKE '%extracción%'
  LIMIT 1;
  
  IF v_id_tipo_operacion IS NULL THEN
    RAISE EXCEPTION 'No se encontró tipo de operación para extracción';
  END IF;

  -- 1. Insertar operación principal
  INSERT INTO app_dat_operaciones (
    id_tipo_operacion,
    uuid,
    id_tienda,
    observaciones,
    created_at
  ) VALUES (
    v_id_tipo_operacion,
    p_uuid,
    p_id_tienda,
    p_observaciones,
    NOW()
  ) RETURNING id INTO v_id_operacion;
  
  -- 2. Insertar detalles específicos de extracción
  INSERT INTO app_dat_operacion_extraccion (
    id_operacion,
    id_motivo_operacion,
    observaciones,
    autorizado_por,
    created_at
  ) VALUES (
    v_id_operacion,
    p_id_motivo_operacion,
    p_observaciones,
    p_autorizado_por,
    NOW()
  );
  
  -- 3. Insertar productos asociados (sin afectar inventario)
  FOR v_producto_record IN SELECT * FROM jsonb_array_elements(p_productos)
  LOOP
    -- Validación de datos mínimos del producto
    IF v_producto_record->>'id_producto' IS NULL OR v_producto_record->>'cantidad' IS NULL THEN
      RAISE EXCEPTION 'Cada producto debe tener id_producto y cantidad';
    END IF;
    
    -- Insertar en extracción_productos
    INSERT INTO app_dat_extraccion_productos (
      id_operacion,
      id_producto,
      id_variante,
      id_opcion_variante,
      id_ubicacion,
      id_presentacion,
      cantidad,
      precio_unitario,
      sku_producto,
      sku_ubicacion,
      created_at
    ) VALUES (
      v_id_operacion,
      (v_producto_record->>'id_producto')::BIGINT,
      NULLIF(v_producto_record->>'id_variante', '')::BIGINT,
      NULLIF(v_producto_record->>'id_opcion_variante', '')::BIGINT,
      NULLIF(v_producto_record->>'id_ubicacion', '')::BIGINT,
      NULLIF(v_producto_record->>'id_presentacion', '')::BIGINT,
      (v_producto_record->>'cantidad')::NUMERIC,
      NULLIF(v_producto_record->>'precio_unitario', '')::NUMERIC,
      v_producto_record->>'sku_producto',
      v_producto_record->>'sku_ubicacion',
      NOW()
    );
    
    -- Sumar al totalizador
    v_cantidad_total := v_cantidad_total + (v_producto_record->>'cantidad')::NUMERIC;
  END LOOP;
  
  -- 4. Insertar estado inicial
  INSERT INTO app_dat_estado_operacion (
    id_operacion,
    estado,
    uuid,
    created_at
  ) VALUES (
    v_id_operacion,
    p_estado_inicial, -- Usa el parámetro de estado
    p_uuid,
    NOW()
  );
  
  -- Construir respuesta
  v_result := jsonb_build_object(
    'status', 'success',
    'id_operacion', v_id_operacion,
    'total_productos', jsonb_array_length(p_productos),
    'cantidad_total', v_cantidad_total,
    'mensaje', 'Extracción registrada correctamente en estado pendiente'
  );
  
  RETURN v_result;
  
EXCEPTION
  WHEN OTHERS THEN
    v_result := jsonb_build_object(
      'status', 'error',
      'message', 'Error al registrar extracción: ' || SQLERRM,
      'sqlstate', SQLSTATE
    );
    RETURN v_result;
END;
