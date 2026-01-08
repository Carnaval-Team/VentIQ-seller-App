DECLARE
  v_contador INT := 0;
  v_rows_updated INT := 0;
  v_rows_inserted INT := 0;
  v_start_time TIMESTAMP;
  v_tiempo_ms INT;
BEGIN
  v_start_time := CLOCK_TIMESTAMP();
  
  -- Validar entrada
  IF p_productos IS NULL OR jsonb_array_length(p_productos) = 0 THEN
    RETURN QUERY SELECT 
      true::BOOLEAN,
      'No hay productos para procesar'::TEXT,
      0::INT,
      0::INT;
    RETURN;
  END IF;

  -- =====================================================
  -- PROCESAR PRODUCTOS USANDO CTE (SIN TABLA TEMPORAL)
  -- =====================================================
  WITH productos_entrada AS (
    -- Extraer y validar datos de entrada
    SELECT
      (elem->>'id_presentacion')::BIGINT AS id_presentacion,
      (elem->>'precio_unitario')::NUMERIC AS precio_unitario,
      (elem->>'cantidad')::NUMERIC AS cantidad
    FROM jsonb_array_elements(p_productos) AS elem
    WHERE 
      (elem->>'id_presentacion') IS NOT NULL
      AND (elem->>'precio_unitario') IS NOT NULL
      AND (elem->>'cantidad') IS NOT NULL
      AND (elem->>'id_presentacion')::NUMERIC > 0
      AND (elem->>'cantidad')::NUMERIC > 0
  ),
  productos_con_anterior AS (
    -- Unir con datos anteriores
    -- IMPORTANTE: Obtener cantidad REAL del último inventario, no de app_dat_producto_presentacion
    SELECT
      pe.id_presentacion,
      pe.precio_unitario,
      pe.cantidad,
      app.id,
      app.precio_promedio,
      -- Obtener la cantidad REAL del último inventario para esta presentación
      COALESCE(
        (SELECT cantidad 
         FROM app_dat_inventario_productos 
         WHERE id_presentacion = pe.id_presentacion 
         ORDER BY created_at DESC 
         LIMIT 1),
        0
      ) AS cantidad_anterior,
      CASE
        -- Si no existe registro anterior, usar precio nuevo
        WHEN app.id IS NULL THEN pe.precio_unitario
        
        -- Manejar división por cero
        WHEN (COALESCE((SELECT cantidad 
                        FROM app_dat_inventario_productos 
                        WHERE id_presentacion = pe.id_presentacion 
                        ORDER BY created_at DESC 
                        LIMIT 1), 0) + pe.cantidad) = 0 
          THEN pe.precio_unitario
        
        -- Calcular promedio ponderado CON CANTIDAD REAL
        ELSE (
          (COALESCE(app.precio_promedio, 0) * 
           COALESCE((SELECT cantidad 
                     FROM app_dat_inventario_productos 
                     WHERE id_presentacion = pe.id_presentacion 
                     ORDER BY created_at DESC 
                     LIMIT 1), 0) + 
           pe.precio_unitario * pe.cantidad) / 
          (COALESCE((SELECT cantidad 
                     FROM app_dat_inventario_productos 
                     WHERE id_presentacion = pe.id_presentacion 
                     ORDER BY created_at DESC 
                     LIMIT 1), 0) + pe.cantidad)
        )
      END AS precio_promedio_nuevo,
      (app.id IS NULL) AS es_nuevo
    FROM productos_entrada pe
    LEFT JOIN app_dat_producto_presentacion app ON pe.id_presentacion = app.id
  ),
  productos_a_actualizar AS (
    -- Seleccionar solo los que existen (no son nuevos)
    SELECT
      id,
      precio_promedio_nuevo
    FROM productos_con_anterior
    WHERE NOT es_nuevo AND precio_promedio_nuevo IS NOT NULL
  ),
  productos_a_insertar AS (
    -- Seleccionar solo los nuevos
    SELECT
      NULL::BIGINT AS id_producto,
      id_presentacion,
      precio_promedio_nuevo,
      cantidad,
      FALSE AS es_base
    FROM productos_con_anterior
    WHERE es_nuevo
  )
  -- =====================================================
  -- ACTUALIZAR REGISTROS EXISTENTES
  -- =====================================================
  UPDATE app_dat_producto_presentacion app
  SET precio_promedio = pau.precio_promedio_nuevo
  FROM productos_a_actualizar pau
  WHERE app.id = pau.id;

  GET DIAGNOSTICS v_rows_updated = ROW_COUNT;

  -- =====================================================
  -- INSERTAR NUEVOS REGISTROS
  -- =====================================================
  WITH productos_entrada AS (
    SELECT
      (elem->>'id_presentacion')::BIGINT AS id_presentacion,
      (elem->>'precio_unitario')::NUMERIC AS precio_unitario,
      (elem->>'cantidad')::NUMERIC AS cantidad
    FROM jsonb_array_elements(p_productos) AS elem
    WHERE 
      (elem->>'id_presentacion') IS NOT NULL
      AND (elem->>'precio_unitario') IS NOT NULL
      AND (elem->>'cantidad') IS NOT NULL
      AND (elem->>'id_presentacion')::NUMERIC > 0
      AND (elem->>'cantidad')::NUMERIC > 0
  ),
  productos_con_anterior AS (
    SELECT
      pe.id_presentacion,
      pe.precio_unitario,
      pe.cantidad,
      app.id,
      app.precio_promedio,
      COALESCE(
        (SELECT cantidad 
         FROM app_dat_inventario_productos 
         WHERE id_presentacion = pe.id_presentacion 
         ORDER BY created_at DESC 
         LIMIT 1),
        0
      ) AS cantidad_anterior,
      CASE
        WHEN app.id IS NULL THEN pe.precio_unitario
        WHEN (COALESCE((SELECT cantidad 
                        FROM app_dat_inventario_productos 
                        WHERE id_presentacion = pe.id_presentacion 
                        ORDER BY created_at DESC 
                        LIMIT 1), 0) + pe.cantidad) = 0 
          THEN pe.precio_unitario
        ELSE (
          (COALESCE(app.precio_promedio, 0) * 
           COALESCE((SELECT cantidad 
                     FROM app_dat_inventario_productos 
                     WHERE id_presentacion = pe.id_presentacion 
                     ORDER BY created_at DESC 
                     LIMIT 1), 0) + 
           pe.precio_unitario * pe.cantidad) / 
          (COALESCE((SELECT cantidad 
                     FROM app_dat_inventario_productos 
                     WHERE id_presentacion = pe.id_presentacion 
                     ORDER BY created_at DESC 
                     LIMIT 1), 0) + pe.cantidad)
        )
      END AS precio_promedio_nuevo,
      (app.id IS NULL) AS es_nuevo
    FROM productos_entrada pe
    LEFT JOIN app_dat_producto_presentacion app ON pe.id_presentacion = app.id
  ),
  productos_a_insertar AS (
    SELECT
      NULL::BIGINT AS id_producto,
      id_presentacion,
      precio_promedio_nuevo,
      cantidad,
      FALSE AS es_base
    FROM productos_con_anterior
    WHERE es_nuevo
  )
  INSERT INTO app_dat_producto_presentacion (
    id_producto,
    id_presentacion,
    precio_promedio,
    cantidad,
    es_base,
    created_at
  )
  SELECT
    id_producto,
    id_presentacion,
    precio_promedio_nuevo,
    cantidad,
    es_base,
    CURRENT_TIMESTAMP
  FROM productos_a_insertar
  ON CONFLICT (id) DO UPDATE SET
    precio_promedio = EXCLUDED.precio_promedio;

  GET DIAGNOSTICS v_rows_inserted = ROW_COUNT;
  
  -- Sumar totales
  v_contador := v_rows_updated + v_rows_inserted;
  v_tiempo_ms := EXTRACT(EPOCH FROM (CLOCK_TIMESTAMP() - v_start_time))::INT * 1000;

  -- =====================================================
  -- REGISTRAR AUDITORÍA (Opcional)
  -- =====================================================
  BEGIN
    INSERT INTO app_dat_auditoria_precios (
      id_operacion,
      tipo_operacion,
      cantidad_productos,
      fecha_operacion,
      estado
    ) VALUES (
      p_id_operacion,
      'actualizar_precio_promedio',
      v_contador,
      CURRENT_TIMESTAMP,
      'exitosa'
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  -- Retornar resultado exitoso
  RETURN QUERY SELECT 
    true::BOOLEAN,
    format('Se actualizaron %s precios promedio en %sms', v_contador, v_tiempo_ms)::TEXT,
    v_contador::INT,
    v_tiempo_ms::INT;

EXCEPTION WHEN OTHERS THEN
  v_tiempo_ms := EXTRACT(EPOCH FROM (CLOCK_TIMESTAMP() - v_start_time))::INT * 1000;
  
  RETURN QUERY SELECT 
    false::BOOLEAN,
    format('Error en fn_actualizar_precio_promedio_recepcion_v2: %s (tiempo: %sms)', SQLERRM, v_tiempo_ms)::TEXT,
    0::INT,
    v_tiempo_ms::INT;
END;

