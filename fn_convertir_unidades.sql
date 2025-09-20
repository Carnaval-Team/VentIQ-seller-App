-- Función para convertir unidades de medida con soporte para productos específicos
CREATE OR REPLACE FUNCTION fn_convertir_unidades(
  p_cantidad numeric,
  p_id_unidad_origen bigint,
  p_id_unidad_destino bigint,
  p_id_producto bigint DEFAULT NULL
) RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
  v_factor_conversion numeric;
  v_factor_producto_origen numeric := 1.0;
  v_factor_producto_destino numeric := 1.0;
  v_cantidad_convertida numeric;
  v_tipo_unidad_origen smallint;
  v_tipo_unidad_destino smallint;
BEGIN
  -- Verificar que las unidades sean del mismo tipo
  SELECT u1.tipo_unidad, u2.tipo_unidad 
  INTO v_tipo_unidad_origen, v_tipo_unidad_destino
  FROM app_nom_unidades_medida u1, app_nom_unidades_medida u2
  WHERE u1.id = p_id_unidad_origen AND u2.id = p_id_unidad_destino;
  
  -- Si las unidades son iguales, retornar la misma cantidad
  IF p_id_unidad_origen = p_id_unidad_destino THEN
    RETURN p_cantidad;
  END IF;
  
  -- Verificar que sean del mismo tipo (peso, volumen, etc.)
  IF v_tipo_unidad_origen != v_tipo_unidad_destino THEN
    RAISE EXCEPTION 'No se puede convertir entre diferentes tipos de unidades: % -> %', 
      v_tipo_unidad_origen, v_tipo_unidad_destino;
  END IF;
  
  -- Buscar factor de conversión directo
  SELECT factor_conversion INTO v_factor_conversion
  FROM app_nom_conversiones_unidades
  WHERE id_unidad_origen = p_id_unidad_origen 
    AND id_unidad_destino = p_id_unidad_destino;
  
  -- Si no existe conversión directa, buscar conversión inversa
  IF v_factor_conversion IS NULL THEN
    SELECT 1.0/factor_conversion INTO v_factor_conversion
    FROM app_nom_conversiones_unidades
    WHERE id_unidad_origen = p_id_unidad_destino 
      AND id_unidad_destino = p_id_unidad_origen;
  END IF;
  
  -- Si aún no hay conversión, usar factores base
  IF v_factor_conversion IS NULL THEN
    DECLARE
      v_factor_base_origen numeric;
      v_factor_base_destino numeric;
    BEGIN
      SELECT factor_base INTO v_factor_base_origen
      FROM app_nom_unidades_medida WHERE id = p_id_unidad_origen;
      
      SELECT factor_base INTO v_factor_base_destino
      FROM app_nom_unidades_medida WHERE id = p_id_unidad_destino;
      
      IF v_factor_base_origen IS NOT NULL AND v_factor_base_destino IS NOT NULL THEN
        v_factor_conversion := v_factor_base_origen / v_factor_base_destino;
      ELSE
        RAISE EXCEPTION 'No se encontró conversión entre las unidades % y %', 
          p_id_unidad_origen, p_id_unidad_destino;
      END IF;
    END;
  END IF;
  
  -- Si hay producto específico, aplicar factores del producto
  IF p_id_producto IS NOT NULL THEN
    -- Factor para unidad origen
    SELECT COALESCE(factor_producto, 1.0) INTO v_factor_producto_origen
    FROM app_dat_producto_unidades
    WHERE id_producto = p_id_producto 
      AND id_unidad_medida = p_id_unidad_origen;
    
    -- Factor para unidad destino
    SELECT COALESCE(factor_producto, 1.0) INTO v_factor_producto_destino
    FROM app_dat_producto_unidades
    WHERE id_producto = p_id_producto 
      AND id_unidad_medida = p_id_unidad_destino;
  END IF;
  
  -- Calcular conversión final
  v_cantidad_convertida := p_cantidad * v_factor_conversion * v_factor_producto_origen / v_factor_producto_destino;
  
  -- Log de la conversión para auditoría
  INSERT INTO app_mkt_function_logs (
    function_name, parametros, resultado, fecha_acceso
  ) VALUES (
    'fn_convertir_unidades',
    jsonb_build_object(
      'cantidad', p_cantidad,
      'unidad_origen', p_id_unidad_origen,
      'unidad_destino', p_id_unidad_destino,
      'producto', p_id_producto,
      'factor_conversion', v_factor_conversion
    ),
    'SUCCESS: ' || v_cantidad_convertida::text,
    now()
  );
  
  RETURN v_cantidad_convertida;
  
EXCEPTION
  WHEN OTHERS THEN
    -- Log del error
    INSERT INTO app_mkt_function_logs (
      function_name, parametros, mensaje_error, fecha_acceso
    ) VALUES (
      'fn_convertir_unidades',
      jsonb_build_object(
        'cantidad', p_cantidad,
        'unidad_origen', p_id_unidad_origen,
        'unidad_destino', p_id_unidad_destino,
        'producto', p_id_producto
      ),
      SQLERRM,
      now()
    );
    RAISE;
END;
$$;
