-- ============================================================================
-- FUNCIÓN CORREGIDA: fn_insertar_ajuste_inventario2
-- ============================================================================
-- Solo guarda id_operacion en app_dat_ajuste_inventario
-- NO intenta guardar en app_dat_inventario_productos
-- ============================================================================

DROP FUNCTION IF EXISTS public.fn_insertar_ajuste_inventario2(
  BIGINT, BIGINT, BIGINT, NUMERIC, NUMERIC, TEXT, TEXT, UUID, BIGINT
) CASCADE;

CREATE OR REPLACE FUNCTION public.fn_insertar_ajuste_inventario2(
  p_id_producto BIGINT,
  p_id_ubicacion BIGINT,
  p_id_presentacion BIGINT,
  p_cantidad_anterior NUMERIC,
  p_cantidad_nueva NUMERIC,
  p_motivo TEXT,
  p_observaciones TEXT,
  p_uuid_usuario UUID,
  p_id_tipo_operacion BIGINT
) RETURNS JSONB AS $$
DECLARE
  v_id_operacion BIGINT;
  v_id_ajuste BIGINT;
  v_diferencia NUMERIC;
  v_id_tienda BIGINT;
BEGIN
  -- Calcular diferencia
  v_diferencia := p_cantidad_nueva - p_cantidad_anterior;

  -- Obtener id_tienda del producto
  SELECT id_tienda 
  INTO v_id_tienda
  FROM app_dat_producto 
  WHERE id = p_id_producto;

  -- Validar parámetros
  IF p_id_producto IS NULL OR p_id_ubicacion IS NULL THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'Parámetros requeridos faltantes: id_producto, id_ubicacion'
    );
  END IF;

  IF p_cantidad_nueva < 0 THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'La cantidad nueva no puede ser negativa'
    );
  END IF;

  -- PASO 1: Crear la operación principal
  INSERT INTO app_dat_operaciones (
    id_tipo_operacion,
    uuid,
    id_tienda,
    observaciones,
    created_at
  ) VALUES (
    p_id_tipo_operacion,
    p_uuid_usuario,
    v_id_tienda,
    p_observaciones,
    NOW()
  ) RETURNING id INTO v_id_operacion;

  -- PASO 2: Crear estado inicial (Completada = 2)
  INSERT INTO app_dat_estado_operacion (
    id_operacion,
    estado,
    uuid,
    created_at,
    comentario
  ) VALUES (
    v_id_operacion,
    2,
    p_uuid_usuario,
    NOW(),
    'Ajuste de inventario completado'
  );

  -- PASO 3: Insertar en tabla de ajuste CON id_operacion
  INSERT INTO app_dat_ajuste_inventario (
    id_producto,
    id_variante,
    id_ubicacion,
    cantidad_anterior,
    cantidad_nueva,
    diferencia,
    id_operacion,
    uuid_usuario,
    created_at
  ) VALUES (
    p_id_producto,
    NULL,
    p_id_ubicacion,
    p_cantidad_anterior,
    p_cantidad_nueva,
    v_diferencia,
    v_id_operacion,
    p_uuid_usuario,
    NOW()
  ) RETURNING id INTO v_id_ajuste;

  -- PASO 4: Insertar en tabla de inventario (SIN id_operacion, SIN uuid_usuario)
  INSERT INTO app_dat_inventario_productos (
    id_producto,
    id_variante,
    id_opcion_variante,
    id_ubicacion,
    id_presentacion,
    cantidad_inicial,
    cantidad_final,
    origen_cambio,
    created_at
  ) VALUES (
    p_id_producto,
    NULL,
    NULL,
    p_id_ubicacion,
    p_id_presentacion,
    p_cantidad_anterior,
    p_cantidad_nueva,
    3,
    NOW()
  );

  -- Retornar éxito
  RETURN jsonb_build_object(
    'status', 'success',
    'message', 'Ajuste de inventario registrado correctamente',
    'id_operacion', v_id_operacion,
    'id_ajuste', v_id_ajuste,
    'diferencia', v_diferencia
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'status', 'error',
    'message', 'Error al procesar ajuste: ' || SQLERRM,
    'error_detail', SQLSTATE
  );
END;
$$ LANGUAGE plpgsql;

-- Verificar que la función se creó
SELECT 
  routine_name,
  routine_type,
  routine_schema
FROM information_schema.routines
WHERE routine_name = 'fn_insertar_ajuste_inventario2'
  AND routine_schema = 'public';
