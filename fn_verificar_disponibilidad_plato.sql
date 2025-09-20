-- Función para verificar disponibilidad de platos elaborados
CREATE OR REPLACE FUNCTION fn_verificar_disponibilidad_plato(
  p_id_plato bigint,
  p_id_tienda bigint,
  p_cantidad integer DEFAULT 1
) RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_resultado jsonb := '{"disponible": true, "ingredientes_faltantes": [], "costo_total": 0}'::jsonb;
  v_ingrediente record;
  v_stock_disponible numeric;
  v_cantidad_necesaria numeric;
  v_cantidad_convertida numeric;
  v_faltantes jsonb := '[]'::jsonb;
  v_costo_total numeric := 0;
  v_precio_unitario numeric;
  v_unidad_inventario bigint;
BEGIN
  -- Verificar que el plato existe y está activo
  IF NOT EXISTS (
    SELECT 1 FROM app_rest_platos_elaborados 
    WHERE id = p_id_plato AND es_activo = true
  ) THEN
    RETURN jsonb_build_object(
      'disponible', false,
      'error', 'Plato no encontrado o inactivo'
    );
  END IF;
  
  -- Verificar cada ingrediente de la receta
  FOR v_ingrediente IN 
    SELECT r.id_producto_inventario, r.cantidad_requerida, r.um,
           p.denominacion as nombre_producto, p.sku,
           um_receta.id as id_unidad_receta,
           um_receta.denominacion as unidad_receta
    FROM app_rest_recetas r
    JOIN app_dat_producto p ON r.id_producto_inventario = p.id
    LEFT JOIN app_nom_unidades_medida um_receta ON um_receta.abreviatura = r.um
    WHERE r.id_plato = p_id_plato
    ORDER BY r.orden
  LOOP
    -- Calcular cantidad necesaria total
    v_cantidad_necesaria := v_ingrediente.cantidad_requerida * p_cantidad;
    
    -- Obtener unidad de inventario del producto (primera disponible)
    SELECT pu.id_unidad_medida INTO v_unidad_inventario
    FROM app_dat_producto_unidades pu
    WHERE pu.id_producto = v_ingrediente.id_producto_inventario
      AND pu.es_unidad_inventario = true
    LIMIT 1;
    
    -- Si no hay unidad específica, usar la unidad base del producto
    IF v_unidad_inventario IS NULL THEN
      SELECT um.id INTO v_unidad_inventario
      FROM app_nom_unidades_medida um
      WHERE um.abreviatura = (
        SELECT p.um FROM app_dat_producto p 
        WHERE p.id = v_ingrediente.id_producto_inventario
      )
      LIMIT 1;
    END IF;
    
    -- Convertir cantidad de receta a unidad de inventario si es necesario
    IF v_ingrediente.id_unidad_receta IS NOT NULL AND v_unidad_inventario IS NOT NULL 
       AND v_ingrediente.id_unidad_receta != v_unidad_inventario THEN
      
      SELECT fn_convertir_unidades(
        v_cantidad_necesaria,
        v_ingrediente.id_unidad_receta,
        v_unidad_inventario,
        v_ingrediente.id_producto_inventario
      ) INTO v_cantidad_convertida;
      
    ELSE
      v_cantidad_convertida := v_cantidad_necesaria;
    END IF;
    
    -- Obtener stock disponible actual
    SELECT COALESCE(SUM(
      CASE 
        WHEN i.cantidad_final IS NOT NULL THEN i.cantidad_final
        ELSE i.cantidad_inicial
      END
    ), 0) INTO v_stock_disponible
    FROM app_dat_inventario_productos i
    JOIN app_dat_layout_almacen l ON i.id_ubicacion = l.id
    JOIN app_dat_almacen a ON l.id_almacen = a.id
    WHERE i.id_producto = v_ingrediente.id_producto_inventario
      AND a.id_tienda = p_id_tienda
      AND (i.cantidad_final > 0 OR (i.cantidad_final IS NULL AND i.cantidad_inicial > 0));
    
    -- Obtener precio unitario más reciente para cálculo de costo
    SELECT COALESCE(precio_unitario, 0) INTO v_precio_unitario
    FROM app_dat_recepcion_productos
    WHERE id_producto = v_ingrediente.id_producto_inventario
    ORDER BY created_at DESC
    LIMIT 1;
    
    -- Calcular costo del ingrediente
    v_costo_total := v_costo_total + (v_cantidad_convertida * COALESCE(v_precio_unitario, 0));
    
    -- Verificar si hay suficiente stock
    IF v_stock_disponible < v_cantidad_convertida THEN
      v_resultado := jsonb_set(v_resultado, '{disponible}', 'false');
      v_faltantes := v_faltantes || jsonb_build_object(
        'producto_id', v_ingrediente.id_producto_inventario,
        'producto', v_ingrediente.nombre_producto,
        'sku', v_ingrediente.sku,
        'necesario', v_cantidad_necesaria,
        'unidad_receta', v_ingrediente.unidad_receta,
        'disponible', v_stock_disponible,
        'faltante', v_cantidad_convertida - v_stock_disponible,
        'costo_unitario', v_precio_unitario
      );
    END IF;
  END LOOP;
  
  -- Actualizar resultado final
  v_resultado := jsonb_set(v_resultado, '{ingredientes_faltantes}', v_faltantes);
  v_resultado := jsonb_set(v_resultado, '{costo_total}', to_jsonb(v_costo_total));
  v_resultado := jsonb_set(v_resultado, '{cantidad_solicitada}', to_jsonb(p_cantidad));
  
  -- Actualizar registro de disponibilidad si está disponible
  IF (v_resultado->>'disponible')::boolean = true THEN
    INSERT INTO app_rest_disponibilidad_platos (
      id_plato, id_tienda, fecha_revision, stock_disponible,
      ingredientes_suficientes, revisado_por, proxima_revision
    ) VALUES (
      p_id_plato, p_id_tienda, CURRENT_DATE, p_cantidad,
      true, '00000000-0000-0000-0000-000000000000'::uuid, 
      now() + interval '1 hour'
    )
    ON CONFLICT (id_plato, id_tienda, fecha_revision) 
    DO UPDATE SET
      stock_disponible = EXCLUDED.stock_disponible,
      ingredientes_suficientes = EXCLUDED.ingredientes_suficientes,
      proxima_revision = EXCLUDED.proxima_revision;
  ELSE
    -- Registrar no disponibilidad
    INSERT INTO app_rest_disponibilidad_platos (
      id_plato, id_tienda, fecha_revision, stock_disponible,
      ingredientes_suficientes, motivo_no_disponible, revisado_por
    ) VALUES (
      p_id_plato, p_id_tienda, CURRENT_DATE, 0,
      false, 'Ingredientes insuficientes', '00000000-0000-0000-0000-000000000000'::uuid
    )
    ON CONFLICT (id_plato, id_tienda, fecha_revision) 
    DO UPDATE SET
      ingredientes_suficientes = false,
      motivo_no_disponible = 'Ingredientes insuficientes';
  END IF;
  
  -- Log de la verificación
  INSERT INTO app_mkt_function_logs (
    function_name, parametros, resultado, fecha_acceso
  ) VALUES (
    'fn_verificar_disponibilidad_plato',
    jsonb_build_object(
      'id_plato', p_id_plato,
      'id_tienda', p_id_tienda,
      'cantidad', p_cantidad
    ),
    'Disponible: ' || (v_resultado->>'disponible') || ', Costo: ' || (v_resultado->>'costo_total'),
    now()
  );
  
  RETURN v_resultado;
  
EXCEPTION
  WHEN OTHERS THEN
    -- Log del error
    INSERT INTO app_mkt_function_logs (
      function_name, parametros, mensaje_error, fecha_acceso
    ) VALUES (
      'fn_verificar_disponibilidad_plato',
      jsonb_build_object(
        'id_plato', p_id_plato,
        'id_tienda', p_id_tienda,
        'cantidad', p_cantidad
      ),
      SQLERRM,
      now()
    );
    
    RETURN jsonb_build_object(
      'disponible', false,
      'error', SQLERRM
    );
END;
$$;
