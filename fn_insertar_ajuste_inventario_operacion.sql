CREATE OR REPLACE FUNCTION fn_insertar_ajuste_inventario(
  p_id_producto BIGINT,
  p_id_ubicacion BIGINT,
  p_id_presentacion BIGINT,
  p_cantidad_anterior NUMERIC,
  p_cantidad_nueva NUMERIC,
  p_motivo TEXT,
  p_observaciones TEXT,
  p_uuid_usuario UUID,
  p_id_tipo_operacion BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
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
  -- Log inicio del procedimiento
  RAISE NOTICE '🔄 INICIO: Procesando ajuste de inventario como operación';
  RAISE NOTICE '📦 Producto ID: %, Ubicación ID: %, Presentación ID: %', p_id_producto, p_id_ubicacion, p_id_presentacion;
  RAISE NOTICE '📊 Cantidad anterior: % → Cantidad nueva: %', p_cantidad_anterior, p_cantidad_nueva;
  RAISE NOTICE '📝 Motivo: %, Usuario: %', p_motivo, p_uuid_usuario;
  RAISE NOTICE '🏷️ Tipo de operación ID: %', p_id_tipo_operacion;

  -- Validar parámetros de entrada
  IF p_id_producto IS NULL OR p_id_ubicacion IS NULL OR p_id_presentacion IS NULL THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'Parámetros requeridos faltantes: id_producto, id_ubicacion, id_presentacion'
    );
  END IF;

  IF p_cantidad_anterior IS NULL OR p_cantidad_nueva IS NULL THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'Las cantidades anterior y nueva son requeridas'
    );
  END IF;

  IF p_cantidad_nueva < 0 THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'La cantidad nueva no puede ser negativa'
    );
  END IF;

  IF p_id_tipo_operacion IS NULL THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'El ID del tipo de operación es requerido'
    );
  END IF;

  -- Calcular diferencia
  v_diferencia := p_cantidad_nueva - p_cantidad_anterior;
  RAISE NOTICE '📈 Diferencia calculada: %', v_diferencia;

  -- Obtener información descriptiva para logs
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

  RAISE NOTICE '🏷️ Producto: %, Ubicación: %, Presentación: %', 
    COALESCE(v_producto_nombre, 'Desconocido'),
    COALESCE(v_ubicacion_nombre, 'Desconocida'),
    COALESCE(v_presentacion_nombre, 'Desconocida');

  -- Validar que el tipo de operación existe
  IF NOT EXISTS (SELECT 1 FROM app_nom_tipo_operacion WHERE id = p_id_tipo_operacion) THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'El tipo de operación especificado no existe: ' || p_id_tipo_operacion
    );
  END IF;

  RAISE NOTICE '📋 Usando tipo de operación ID: %', p_id_tipo_operacion;

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

  RAISE NOTICE '✅ PASO 1: Operación creada con ID: %', v_id_operacion;

  -- PASO 2: Crear estado inicial de la operación (Pendiente = 1)
  INSERT INTO app_dat_estado_operacion (
    id_operacion,
    estado,
    uuid,
    created_at,
    comentario
  ) VALUES (
    v_id_operacion,
    1, -- Estado: Pendiente
    p_uuid_usuario,
    NOW(),
    'Ajuste de inventario creado - Estado inicial'
  );

  RAISE NOTICE '✅ PASO 2: Estado inicial creado (Pendiente)';

  -- PASO 3: Insertar en tabla de ajuste
  INSERT INTO app_dat_ajuste_inventario (
    id_producto,
    id_variante,
    id_ubicacion,
    cantidad_anterior,
    cantidad_nueva,
    diferencia,
    uuid_usuario,
    created_at
  ) VALUES (
    p_id_producto,
    NULL, -- Sin variante por simplicidad
    p_id_ubicacion,
    p_cantidad_anterior,
    p_cantidad_nueva,
    v_diferencia,
    p_uuid_usuario,
    NOW()
  ) RETURNING id INTO v_id_ajuste;

  RAISE NOTICE '✅ PASO 3: Ajuste registrado en tabla con ID: %', v_id_ajuste;

  -- PASO 4: Insertar en tabla de inventario
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
  SELECT 
    p_id_producto,
    NULL,
    NULL,
    p_id_ubicacion,
    p_id_presentacion,
    p_cantidad_anterior,
    p_cantidad_nueva,
    p.sku,
    la.sku_codigo,
    3, -- Origen cambio: Ajuste
    NULL,
    NULL,
    NOW()
  FROM app_dat_producto p
  LEFT JOIN app_dat_layout_almacen la ON la.id = p_id_ubicacion
  WHERE p.id = p_id_producto;

  RAISE NOTICE '✅ PASO 4: Inventario actualizado';

  -- PASO 5: Cambiar estado a Ejecutado (2)
  INSERT INTO app_dat_estado_operacion (
    id_operacion,
    estado,
    uuid,
    created_at,
    comentario
  ) VALUES (
    v_id_operacion,
    2, -- Estado: Ejecutado
    p_uuid_usuario,
    NOW(),
    'Ajuste de inventario ejecutado correctamente'
  );

  RAISE NOTICE '✅ PASO 5: Estado cambiado a Ejecutado (2)';

  -- Construir respuesta exitosa
  v_result := jsonb_build_object(
    'status', 'success',
    'data', jsonb_build_object(
      'id_operacion', v_id_operacion,
      'id_ajuste', v_id_ajuste,
      'diferencia', v_diferencia,
      'cantidad_anterior', p_cantidad_anterior,
      'cantidad_nueva', p_cantidad_nueva,
      'producto', v_producto_nombre,
      'ubicacion', v_ubicacion_nombre,
      'presentacion', v_presentacion_nombre
    ),
    'message', 'Ajuste de inventario procesado exitosamente'
  );

  RAISE NOTICE '🎉 ÉXITO: Ajuste completado con flujo correcto';
  RAISE NOTICE '📊 ID Operación: %, ID Ajuste: %, Diferencia: %', v_id_operacion, v_id_ajuste, v_diferencia;

  RETURN v_result;

EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE '❌ ERROR en ajuste de inventario: % - %', SQLSTATE, SQLERRM;
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'Error al procesar ajuste de inventario: ' || SQLERRM,
      'sqlstate', SQLSTATE
    );
END;
$$;
