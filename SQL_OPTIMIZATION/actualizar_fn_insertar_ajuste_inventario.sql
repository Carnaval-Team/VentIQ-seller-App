-- ============================================================================
-- ACTUALIZAR: Función fn_insertar_ajuste_inventario para guardar id_operacion
-- ============================================================================
-- Este script reemplaza la función existente con la versión que guarda id_operacion
-- ============================================================================

-- PASO 1: Eliminar la función antigua (si existe)
DROP FUNCTION IF EXISTS fn_insertar_ajuste_inventario2(
  BIGINT, BIGINT, BIGINT, NUMERIC, NUMERIC, TEXT, TEXT, UUID, BIGINT
) CASCADE;

-- PASO 2: Crear la función actualizada
CREATE OR REPLACE FUNCTION fn_insertar_ajuste_inventario2(
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
  v_producto_nombre TEXT;
  v_ubicacion_nombre TEXT;
  v_presentacion_nombre TEXT;
  v_id_tienda BIGINT;
  v_result JSONB;
BEGIN
  -- Calcular diferencia
  v_diferencia := p_cantidad_nueva - p_cantidad_anterior;

  -- Obtener información descriptiva
  SELECT p.denominacion, p.id_tienda 
  INTO v_producto_nombre, v_id_tienda
  FROM app_dat_producto p 
  WHERE p.id = p_id_producto;

  SELECT la.denominacion 
  INTO v_ubicacion_nombre
  FROM app_dat_layout_almacen la 
  WHERE la.id = p_id_ubicacion;

  SELECT pp.cantidad::TEXT || ' ' || np.denominacion
  INTO v_presentacion_nombre
  FROM app_dat_producto_presentacion pp
  JOIN app_nom_presentacion np ON pp.id_presentacion = np.id
  WHERE pp.id = p_id_presentacion;

  -- Validar parámetros
  IF p_id_producto IS NULL OR p_id_ubicacion IS NULL OR p_id_presentacion IS NULL THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'Parámetros requeridos faltantes'
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

  -- PASO 2: Crear estado inicial (Pendiente = 1)
  INSERT INTO app_dat_estado_operacion (
    id_operacion,
    estado,
    uuid,
    created_at,
    comentario
  ) VALUES (
    v_id_operacion,
    1,
    p_uuid_usuario,
    NOW(),
    'Ajuste de inventario creado - Estado inicial'
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

  -- PASO 4: Insertar en tabla de inventario
  INSERT INTO app_dat_inventario_productos (
    id_producto,
    id_variante,
    id_opcion_variante,
    id_ubicacion,
    id_presentacion,
    cantidad_inicial,
    cantidad_final,
    origen_cambio,
    id_operacion,
    uuid_usuario,
    created_at
  ) VALUES (
    p_id_producto,
    NULL,
    NULL,
    p_id_ubicacion,
    p_id_presentacion,
    p_cantidad_anterior,
    p_cantidad_nueva,
    3, -- origen_cambio: 3 = Ajuste
    v_id_operacion,
    p_uuid_usuario,
    NOW()
  );

  -- Construir respuesta exitosa
  v_result := jsonb_build_object(
    'status', 'success',
    'message', 'Ajuste de inventario registrado correctamente',
    'id_operacion', v_id_operacion,
    'id_ajuste', v_id_ajuste,
    'diferencia', v_diferencia,
    'producto', v_producto_nombre,
    'ubicacion', v_ubicacion_nombre,
    'presentacion', v_presentacion_nombre
  );

  RETURN v_result;

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'status', 'error',
    'message', 'Error al procesar ajuste: ' || SQLERRM,
    'error_detail', SQLSTATE
  );
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================
-- Después de ejecutar este script, verifica que la función existe:
-- SELECT * FROM information_schema.routines 
-- WHERE routine_name = 'fn_insertar_ajuste_inventario';
--
-- Los nuevos ajustes deberían tener id_operacion poblado:
-- SELECT id, id_operacion, id_producto, created_at 
-- FROM app_dat_ajuste_inventario 
-- WHERE id_operacion IS NOT NULL
-- ORDER BY created_at DESC LIMIT 5;
-- ============================================================================
