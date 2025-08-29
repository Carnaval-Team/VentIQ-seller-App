DECLARE
  v_id_operacion BIGINT;
  v_id_tipo_operacion BIGINT;
  v_producto_record JSONB;
  v_cantidad_total NUMERIC := 0;
  v_result JSONB;
  v_error_message TEXT;
  v_tienda_exists BOOLEAN;
BEGIN
  -- Validación de existencia de referencias
  SELECT EXISTS(SELECT 1 FROM app_dat_tienda WHERE id = p_id_tienda) 
  INTO v_tienda_exists;
  
  IF NOT v_tienda_exists THEN
    RAISE EXCEPTION 'La tienda con ID % no existe', p_id_tienda;
  END IF;
  
  IF jsonb_array_length(p_productos) = 0 THEN
    RAISE EXCEPTION 'Debe incluir al menos un producto';
  END IF;

  -- Obtener ID del tipo de operación "Recepción" (asumiendo que existe)
  SELECT id INTO v_id_tipo_operacion 
  FROM app_nom_tipo_operacion 
  WHERE denominacion ILIKE '%recepcion%' 
  LIMIT 1;
  
  IF v_id_tipo_operacion IS NULL THEN
    RAISE EXCEPTION 'No se encontró tipo de operación para recepción';
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
  
  -- 2. Insertar detalles específicos de recepción
  INSERT INTO app_dat_operacion_recepcion (
    id_operacion,
    entregado_por,
    recibido_por,
    monto_total,
    observaciones,
    motivo,
    created_at
  ) VALUES (
    v_id_operacion,
    p_entregado_por,
    p_recibido_por,
    p_monto_total,
    p_observaciones,
    p_motivo,
    NOW()
  );
  
  -- 3. Insertar productos asociados
  FOR v_producto_record IN SELECT * FROM jsonb_array_elements(p_productos)
  LOOP
    -- Validación de datos mínimos del producto
    IF v_producto_record->>'id_producto' IS NULL OR v_producto_record->>'cantidad' IS NULL THEN
      RAISE EXCEPTION 'Cada producto debe tener id_producto y cantidad';
    END IF;
    
    -- Insertar en recepción_productos
    INSERT INTO app_dat_recepcion_productos (
      id_operacion,
      id_producto,
      id_variante,
      id_opcion_variante,
      id_proveedor,
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
      NULLIF(v_producto_record->>'id_proveedor', '')::BIGINT,
      NULLIF(v_producto_record->>'id_ubicacion', '')::BIGINT,
      NULLIF(v_producto_record->>'id_presentacion', '')::BIGINT,
      (v_producto_record->>'cantidad')::NUMERIC,
      NULLIF(v_producto_record->>'precio_unitario', '')::NUMERIC,
      v_producto_record->>'sku_producto',
      v_producto_record->>'sku_ubicacion',
      NOW()
    );
    
    -- Sumar al totalizador
    v_cantidad_total := v_cantidad_total + 
      ((v_producto_record->>'cantidad')::NUMERIC * 
       COALESCE(NULLIF(v_producto_record->>'precio_unitario', '')::NUMERIC, 0));
  END LOOP;
  
  -- 4. Insertar estado inicial (1 = Pendiente)
  INSERT INTO app_dat_estado_operacion (
    id_operacion,
    estado,
    uuid,
    created_at
  ) VALUES (
    v_id_operacion,
    1, -- Estado pendiente
    p_uuid,
    NOW()
  );
  
  -- 5. Actualizar monto total si no se proporcionó
  IF p_monto_total IS NULL THEN
    UPDATE app_dat_operacion_recepcion
    SET monto_total = v_cantidad_total
    WHERE id_operacion = v_id_operacion;
  END IF;
  
  -- Construir respuesta
  v_result := jsonb_build_object(
    'status', 'success',
    'id_operacion', v_id_operacion,
    'total_productos', jsonb_array_length(p_productos),
    'monto_total', COALESCE(p_monto_total, v_cantidad_total),
    'mensaje', 'Recepción registrada correctamente en estado pendiente'
  );
  
  RETURN v_result;
  
EXCEPTION
  WHEN OTHERS THEN
    -- Supabase maneja el rollback automáticamente en caso de error
    v_result := jsonb_build_object(
      'status', 'error',
      'message', 'Error al registrar recepción: ' || SQLERRM,
      'sqlstate', SQLSTATE
    );
    RETURN v_result;
END;
