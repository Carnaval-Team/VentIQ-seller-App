CREATE OR REPLACE FUNCTION fn_registrar_venta(
  p_id_tpv BIGINT,
  p_uuid UUID,
  p_denominacion CHARACTER VARYING,
  p_codigo_promocion CHARACTER VARYING DEFAULT NULL,
  p_id_cliente BIGINT DEFAULT NULL,
  p_observaciones TEXT DEFAULT NULL,
  p_productos JSONB,
  p_estado_inicial SMALLINT DEFAULT 1
) RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_id_operacion BIGINT;
  v_id_tipo_operacion BIGINT;
  v_id_tienda BIGINT;
  v_producto JSONB;
  v_result JSONB;
  v_total_venta NUMERIC := 0;
  v_tpv_exists BOOLEAN;
  v_error_message TEXT;
  v_id_extraccion BIGINT;
BEGIN
  -- Validar que el TPV existe y obtener la tienda
  SELECT EXISTS(SELECT 1 FROM app_dat_tpv WHERE id = p_id_tpv), 
         (SELECT id_tienda FROM app_dat_tpv WHERE id = p_id_tpv)
  INTO v_tpv_exists, v_id_tienda;
  
  IF NOT v_tpv_exists THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'El punto de venta especificado no existe'
    );
  END IF;

  -- Obtener ID del tipo de operación "Venta"
  SELECT id INTO v_id_tipo_operacion 
  FROM app_nom_tipo_operacion 
  WHERE denominacion ILIKE '%venta%' LIMIT 1;
  
  IF v_id_tipo_operacion IS NULL THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'No se encontró tipo de operación para ventas'
    );
  END IF;

  -- Validar productos
  IF jsonb_array_length(p_productos) = 0 THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'Debe incluir al menos un producto'
    );
  END IF;

  -- Validar cliente si se proporciona (opcional)
  IF p_id_cliente IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM app_dat_clientes WHERE id = p_id_cliente) THEN
      RETURN jsonb_build_object(
        'status', 'error',
        'message', 'El cliente especificado no existe'
      );
    END IF;
  END IF;

  -- 1. Registrar operación principal
  INSERT INTO app_dat_operaciones (
    id_tipo_operacion,
    uuid,
    id_tienda,
    observaciones,
    created_at
  ) VALUES (
    v_id_tipo_operacion,
    p_uuid,
    v_id_tienda,
    p_observaciones,
    NOW()
  ) RETURNING id INTO v_id_operacion;
  
  -- 2. Registrar detalles específicos de venta (CON id_cliente)
  INSERT INTO app_dat_operacion_venta (
    id_operacion,
    id_tpv,
    denominacion,
    codigo_promocion,
    id_cliente,
    created_at
  ) VALUES (
    v_id_operacion,
    p_id_tpv,
    p_denominacion,
    p_codigo_promocion,
    p_id_cliente,
    NOW()
  );
  
  -- 3. Procesar cada producto vendido
  FOR v_producto IN SELECT * FROM jsonb_array_elements(p_productos)
  LOOP
    -- Validación de datos mínimos
    IF v_producto->>'id_producto' IS NULL OR 
       v_producto->>'cantidad' IS NULL OR
       v_producto->>'precio_unitario' IS NULL THEN
      RAISE EXCEPTION 'Cada producto debe tener id_producto, cantidad y precio_unitario';
    END IF;
    
    -- Registrar producto vendido Y CAPTURAR EL ID DE EXTRACCIÓN
    INSERT INTO app_dat_extraccion_productos (
      id_operacion,
      id_producto,
      id_variante,
      id_opcion_variante,
      id_ubicacion,
      id_presentacion,
      cantidad,
      precio_unitario,
      importe,
      importe_real,
      sku_producto,
      sku_ubicacion,
      created_at
    ) VALUES (
      v_id_operacion,
      (v_producto->>'id_producto')::BIGINT,
      NULLIF(v_producto->>'id_variante', '')::BIGINT,
      NULLIF(v_producto->>'id_opcion_variante', '')::BIGINT,
      NULLIF(v_producto->>'id_ubicacion', '')::BIGINT,
      NULLIF(v_producto->>'id_presentacion', '')::BIGINT,
      (v_producto->>'cantidad')::NUMERIC,
      (v_producto->>'precio_unitario')::NUMERIC,
      (v_producto->>'cantidad')::NUMERIC * (v_producto->>'precio_unitario')::NUMERIC,
      (v_producto->>'cantidad')::NUMERIC * COALESCE(NULLIF(v_producto->>'precio_real', '')::NUMERIC, (v_producto->>'precio_unitario')::NUMERIC),
      v_producto->>'sku_producto',
      v_producto->>'sku_ubicacion',
      NOW()
    ) RETURNING id INTO v_id_extraccion; -- ✅ CAPTURAR ID REAL DE EXTRACCIÓN
    
    -- Actualizar total de venta
    v_total_venta := v_total_venta + ((v_producto->>'cantidad')::NUMERIC * (v_producto->>'precio_unitario')::NUMERIC);
    
    -- Actualizar inventario usando el ID de extracción correcto
    INSERT INTO app_dat_inventario_productos (
      id_producto,
      id_variante,
      id_opcion_variante,
      id_ubicacion,
      id_presentacion,
      cantidad_inicial,
      cantidad_final,
      sku_producto,
      sku_ubicacion,
      origen_cambio,
      id_extraccion, -- ✅ Usar el ID de extracción real
      created_at
    )
    SELECT 
      (v_producto->>'id_producto')::BIGINT,
      NULLIF(v_producto->>'id_variante', '')::BIGINT,
      NULLIF(v_producto->>'id_opcion_variante', '')::BIGINT,
      NULLIF(v_producto->>'id_ubicacion', '')::BIGINT,
      NULLIF(v_producto->>'id_presentacion', '')::BIGINT,
      COALESCE(ip.cantidad_final, 0),
      COALESCE(ip.cantidad_final, 0) - (v_producto->>'cantidad')::NUMERIC,
      v_producto->>'sku_producto',
      v_producto->>'sku_ubicacion',
      3, -- Origen: Venta
      v_id_extraccion, -- ✅ ID de extracción correcto
      NOW()
    FROM (
      SELECT cantidad_final 
      FROM app_dat_inventario_productos 
      WHERE id_producto = (v_producto->>'id_producto')::BIGINT
        AND COALESCE(id_variante, 0) = COALESCE(NULLIF(v_producto->>'id_variante', '')::BIGINT, 0)
        AND COALESCE(id_ubicacion, 0) = COALESCE(NULLIF(v_producto->>'id_ubicacion', '')::BIGINT, 0)
      ORDER BY created_at DESC
      LIMIT 1
    ) ip;
    
  END LOOP;
  
  -- 4. Actualizar monto total en la venta
  UPDATE app_dat_operacion_venta
  SET importe_total = v_total_venta
  WHERE id_operacion = v_id_operacion;
  
  -- 5. Registrar estado inicial
  INSERT INTO app_dat_estado_operacion (
    id_operacion,
    estado,
    uuid,
    created_at
  ) VALUES (
    v_id_operacion,
    p_estado_inicial,
    p_uuid,
    NOW()
  );
  
  -- Construir respuesta
  v_result := jsonb_build_object(
    'status', 'success',
    'id_operacion', v_id_operacion,
    'total_venta', v_total_venta,
    'total_productos', jsonb_array_length(p_productos),
    'id_cliente', p_id_cliente,
    'mensaje', 'Venta registrada correctamente'
  );
  
  RETURN v_result;
  
EXCEPTION
  WHEN OTHERS THEN
    v_result := jsonb_build_object(
      'status', 'error',
      'message', 'Error al registrar venta: ' || SQLERRM,
      'sqlstate', SQLSTATE
    );
    RETURN v_result;
END;
$$;
