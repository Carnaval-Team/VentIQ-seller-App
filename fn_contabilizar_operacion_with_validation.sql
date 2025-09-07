CREATE OR REPLACE FUNCTION fn_contabilizar_operacion(
  p_id_operacion BIGINT,
  p_comentario TEXT,
  p_uuid UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_tipo_operacion RECORD;
  v_operacion RECORD;
  v_productos RECORD;
  v_result JSONB;
  v_afecta_inventario BOOLEAN;
  v_factor_inventario INTEGER;
  v_estado_actual INTEGER;
  v_cantidad_inicial NUMERIC;
  v_cantidad_final NUMERIC;
  v_insufficient_stock TEXT := '';
BEGIN
  -- Verificar existencia de la operación y obtener su tipo
  SELECT o.id, o.id_tipo_operacion, top.denominacion, top.accion 
  INTO v_operacion
  FROM app_dat_operaciones o
  JOIN app_nom_tipo_operacion top ON o.id_tipo_operacion = top.id
  WHERE o.id = p_id_operacion;
  
  IF v_operacion.id IS NULL THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'Operación no encontrada'
    );
  END IF;
  
  -- Verificar estado actual
  SELECT estado INTO v_estado_actual
  FROM app_dat_estado_operacion
  WHERE id_operacion = p_id_operacion
  ORDER BY created_at DESC
  LIMIT 1;
  
  IF v_estado_actual = 2 THEN -- 2 = Contabilizado
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'La operación ya está contabilizada'
    );
  END IF;
  
  -- Determinar si afecta inventario y el factor (suma/resta)
  v_afecta_inventario := TRUE;
  CASE v_operacion.accion
    WHEN 'entrada' THEN v_factor_inventario := 1;
    WHEN 'salida' THEN v_factor_inventario := -1;
    WHEN 'transferencia' THEN v_factor_inventario := 0;
    ELSE v_afecta_inventario := FALSE;
  END CASE;
  
  -- Para extracciones, validar stock disponible ANTES de procesar
  IF v_afecta_inventario AND v_factor_inventario = -1 THEN
    FOR v_productos IN 
      SELECT 
        ep.id_producto,
        ep.id_variante,
        ep.id_opcion_variante,
        ep.id_ubicacion,
        ep.id_presentacion,
        ep.cantidad,
        ep.sku_producto,
        ep.sku_ubicacion,
        p.denominacion as producto_nombre
      FROM app_dat_extraccion_productos ep
      JOIN app_dat_producto p ON ep.id_producto = p.id
      WHERE ep.id_operacion = p_id_operacion
    LOOP
      -- Obtener cantidad actual disponible
      SELECT COALESCE(cantidad_final, 0) INTO v_cantidad_inicial
      FROM app_dat_inventario_productos 
      WHERE id_producto = v_productos.id_producto
        AND COALESCE(id_variante, 0) = COALESCE(v_productos.id_variante, 0)
        AND COALESCE(id_opcion_variante, 0) = COALESCE(v_productos.id_opcion_variante, 0)
        AND id_ubicacion = v_productos.id_ubicacion
        AND COALESCE(id_presentacion, 0) = COALESCE(v_productos.id_presentacion, 0)
      ORDER BY created_at DESC
      LIMIT 1;
      
      IF v_cantidad_inicial IS NULL THEN
        v_cantidad_inicial := 0;
      END IF;
      
      -- Calcular cantidad final después de la extracción
      v_cantidad_final := v_cantidad_inicial - v_productos.cantidad;
      
      -- Validar que no resulte en stock negativo
      IF v_cantidad_final < 0 THEN
        v_insufficient_stock := v_insufficient_stock || 
          CASE WHEN v_insufficient_stock != '' THEN ', ' ELSE '' END ||
          v_productos.producto_nombre || ' (disponible: ' || v_cantidad_inicial || ', solicitado: ' || v_productos.cantidad || ')';
      END IF;
    END LOOP;
    
    -- Si hay productos con stock insuficiente, retornar error
    IF v_insufficient_stock != '' THEN
      RETURN jsonb_build_object(
        'status', 'error',
        'message', 'Stock insuficiente para: ' || v_insufficient_stock,
        'error_type', 'insufficient_stock'
      );
    END IF;
  END IF;
  
  -- Actualizar estado de la operación a "Contabilizado" (2)
  INSERT INTO app_dat_estado_operacion (
    id_operacion,
    estado,
    uuid,
    created_at,
    comentario
  ) VALUES (
    p_id_operacion,
    2, -- Código para "Contabilizado"
    p_uuid,
    NOW(),
    p_comentario
  );
  
  -- Actualizar inventario si corresponde
  IF v_afecta_inventario AND v_factor_inventario != 0 THEN
    FOR v_productos IN 
      SELECT 
        rp.id_producto,
        rp.id_variante,
        rp.id_opcion_variante,
        rp.id_ubicacion,
        rp.id_presentacion,
        rp.cantidad,
        rp.sku_producto,
        rp.sku_ubicacion
      FROM app_dat_recepcion_productos rp
      WHERE rp.id_operacion = p_id_operacion
      
      UNION ALL
      
      SELECT 
        ep.id_producto,
        ep.id_variante,
        ep.id_opcion_variante,
        ep.id_ubicacion,
        ep.id_presentacion,
        ep.cantidad,
        ep.sku_producto,
        ep.sku_ubicacion
      FROM app_dat_extraccion_productos ep
      WHERE ep.id_operacion = p_id_operacion
    LOOP
      -- Obtener cantidad inicial
      SELECT COALESCE(cantidad_final, 0) INTO v_cantidad_inicial
      FROM app_dat_inventario_productos 
      WHERE id_producto = v_productos.id_producto
        AND COALESCE(id_variante, 0) = COALESCE(v_productos.id_variante, 0)
        AND COALESCE(id_opcion_variante, 0) = COALESCE(v_productos.id_opcion_variante, 0)
        AND id_ubicacion = v_productos.id_ubicacion
        AND COALESCE(id_presentacion, 0) = COALESCE(v_productos.id_presentacion, 0)
      ORDER BY created_at DESC
      LIMIT 1;
      
      IF v_cantidad_inicial IS NULL THEN
        v_cantidad_inicial := 0;
      END IF;
      
      -- Calcular cantidad final
      v_cantidad_final := v_cantidad_inicial + (v_productos.cantidad * v_factor_inventario);
      
      -- Insertar registro de inventario
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
        id_recepcion,
        id_extraccion,
        created_at
      )
      VALUES (
        v_productos.id_producto,
        v_productos.id_variante,
        v_productos.id_opcion_variante,
        v_productos.id_ubicacion,
        v_productos.id_presentacion,
        v_cantidad_inicial,
        v_cantidad_final,
        v_productos.sku_producto,
        v_productos.sku_ubicacion,
        2, -- Origen cambio: Contabilización
        CASE WHEN v_factor_inventario > 0 THEN p_id_operacion ELSE NULL END,
        CASE WHEN v_factor_inventario < 0 THEN p_id_operacion ELSE NULL END,
        NOW()
      );
    END LOOP;
  END IF;
  
  -- Construir respuesta exitosa
  v_result := jsonb_build_object(
    'status', 'success',
    'id_operacion', p_id_operacion,
    'tipo_operacion', v_operacion.denominacion,
    'productos_afectados', (
      SELECT COUNT(*) 
      FROM (
        SELECT 1 FROM app_dat_recepcion_productos WHERE id_operacion = p_id_operacion
        UNION ALL
        SELECT 1 FROM app_dat_extraccion_productos WHERE id_operacion = p_id_operacion
      ) t
    ),
    'mensaje', 'Operación contabilizada correctamente'
  );
  
  RETURN v_result;
  
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'Error al contabilizar operación: ' || SQLERRM,
      'sqlstate', SQLSTATE
    );
END;
$$;
