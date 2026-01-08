-- ============================================================================
-- MODIFICACIONES FINALES PARA DEVOLUCIONES EN CONSIGNACIÓN
-- ============================================================================
-- Este archivo contiene las modificaciones exactas para tu código actual
-- ============================================================================

-- ============================================================================
-- PARTE 1: Modificar crear_envio_consignacion
-- ============================================================================
-- Agregar estas variables al DECLARE (después de v_precio_costo_cup):

-- ⭐ AGREGAR AL DECLARE:
-- v_id_presentacion_original BIGINT;
-- v_id_variante_original BIGINT;
-- v_id_ubicacion_original BIGINT;

-- ============================================================================
-- PARTE 2: Modificar el loop de productos
-- ============================================================================
-- Reemplazar el loop FOR completo (línea ~110-135) con este código:

/*
  -- 6. Crear ENVÍO_PRODUCTOS para cada producto
  FOR v_producto IN SELECT jsonb_array_elements(p_productos)
  LOOP
    v_id_producto_original := (v_producto->>'id_producto')::BIGINT;
    v_id_inventario := (v_producto->>'id_inventario')::BIGINT;
    v_cantidad := (v_producto->>'cantidad')::NUMERIC;
    v_precio_costo_cup := (v_producto->>'precio_costo_cup')::NUMERIC;
    
    -- ⭐ OBTENER DATOS ORIGINALES DEL INVENTARIO
    SELECT 
      ip.id_presentacion,
      ip.id_variante,
      ip.id_ubicacion
    INTO 
      v_id_presentacion_original,
      v_id_variante_original,
      v_id_ubicacion_original
    FROM app_dat_inventario_productos ip
    WHERE ip.id = v_id_inventario;
    
    RAISE NOTICE 'Insertando producto: id_envio=%, id_inventario=%, id_producto=%, cantidad=%, presentacion=%, variante=%, ubicacion=%', 
      v_id_envio, v_id_inventario, v_id_producto_original, v_cantidad,
      v_id_presentacion_original, v_id_variante_original, v_id_ubicacion_original;
    
    -- Insertar producto del envío con datos originales
    INSERT INTO app_dat_consignacion_envio_producto (
      id_envio, 
      id_inventario, 
      id_producto, 
      cantidad_propuesta, 
      precio_costo_cup, 
      precio_costo_usd, 
      estado_producto, 
      created_at,
      -- ⭐ CAMPOS NUEVOS
      id_presentacion_original,
      id_variante_original,
      id_ubicacion_original,
      id_inventario_original
    ) VALUES (
      v_id_envio,
      v_id_inventario,
      v_id_producto_original,
      v_cantidad,
      v_precio_costo_cup,
      (v_producto->>'precio_costo_usd')::NUMERIC,
      1,
      CURRENT_TIMESTAMP,
      -- ⭐ VALORES ORIGINALES
      v_id_presentacion_original,
      v_id_variante_original,
      v_id_ubicacion_original,
      v_id_inventario
    );
    
    RAISE NOTICE 'Producto insertado exitosamente con datos originales';
  END LOOP;
*/

-- ============================================================================
-- FUNCIÓN COMPLETA MODIFICADA: crear_envio_consignacion
-- ============================================================================

CREATE OR REPLACE FUNCTION crear_envio_consignacion(
  p_id_contrato BIGINT,
  p_id_almacen_origen BIGINT,
  p_id_almacen_destino BIGINT,
  p_id_usuario UUID,
  p_productos JSONB,
  p_descripcion TEXT DEFAULT NULL,
  p_id_operacion_extraccion BIGINT DEFAULT NULL
) RETURNS TABLE (
  success BOOLEAN,
  id_envio BIGINT,
  numero_envio VARCHAR,
  id_operacion_extraccion BIGINT,
  id_operacion_recepcion BIGINT,
  mensaje VARCHAR
) AS $$
DECLARE
  v_id_contrato_consignacion BIGINT;
  v_id_operacion_extraccion BIGINT;
  v_id_operacion_recepcion BIGINT;
  v_numero_envio VARCHAR;
  v_id_envio BIGINT;
  v_id_tienda_origen BIGINT;
  v_id_tienda_destino BIGINT;
  v_producto JSONB;
  v_id_producto_original BIGINT;
  v_id_producto_destino BIGINT;
  v_cantidad NUMERIC;
  v_precio_costo_cup NUMERIC;
  v_id_inventario BIGINT;
  -- ⭐ NUEVAS VARIABLES PARA DATOS ORIGINALES
  v_id_presentacion_original BIGINT;
  v_id_variante_original BIGINT;
  v_id_ubicacion_original BIGINT;
BEGIN
  -- 1. Obtener tiendas del contrato
  SELECT id, id_tienda_consignadora, id_tienda_consignataria
  INTO v_id_contrato_consignacion, v_id_tienda_origen, v_id_tienda_destino
  FROM app_dat_contrato_consignacion
  WHERE id = p_id_contrato;
  
  IF v_id_contrato_consignacion IS NULL THEN
    RETURN QUERY SELECT 
      false::BOOLEAN, NULL::BIGINT, NULL::VARCHAR, NULL::BIGINT, NULL::BIGINT,
      'Contrato de consignación no encontrado'::VARCHAR;
    RETURN;
  END IF;
  
  -- 2. Usar operación de EXTRACCIÓN existente o crear una nueva
  IF p_id_operacion_extraccion IS NOT NULL THEN
    v_id_operacion_extraccion := p_id_operacion_extraccion;
  ELSE
    INSERT INTO app_dat_operaciones (
      id_tienda, id_tipo_operacion, uuid, observaciones, created_at
    ) VALUES (
      v_id_tienda_origen, 7, p_id_usuario,
      COALESCE(p_descripcion, 'Extracción para consignación'), 
      CURRENT_TIMESTAMP
    ) RETURNING id INTO v_id_operacion_extraccion;
    
    IF v_id_operacion_extraccion IS NULL THEN
      RETURN QUERY SELECT 
        false::BOOLEAN, NULL::BIGINT, NULL::VARCHAR, NULL::BIGINT, NULL::BIGINT,
        'Error creando operación de extracción'::VARCHAR;
      RETURN;
    END IF;
  END IF;
  
  -- 3. La operación de RECEPCIÓN se crea después cuando se confirma la recepción
  v_id_operacion_recepcion := NULL;
  
  -- 4. Generar número de envío
  v_numero_envio := 'ENV-' || TO_CHAR(CURRENT_TIMESTAMP, 'YYYYMMDD') || '-' || LPAD(nextval('app_dat_consignacion_envio_id_seq')::TEXT, 6, '0');
  
  -- 5. Crear ENVÍO de consignación
  INSERT INTO app_dat_consignacion_envio (
    id_contrato_consignacion,
    id_operacion_extraccion,
    id_operacion_recepcion,
    numero_envio,
    estado_envio,
    fecha_propuesta,
    id_almacen_origen,
    id_almacen_destino,
    id_usuario_creador,
    estado,
    created_at,
    updated_at
  ) VALUES (
    v_id_contrato_consignacion,
    v_id_operacion_extraccion,
    v_id_operacion_recepcion,
    v_numero_envio,
    1,
    CURRENT_TIMESTAMP,
    p_id_almacen_origen,
    p_id_almacen_destino,
    p_id_usuario,
    1,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
  ) RETURNING id INTO v_id_envio;
  
  IF v_id_envio IS NULL THEN
    RETURN QUERY SELECT 
      false::BOOLEAN, NULL::BIGINT, NULL::VARCHAR, NULL::BIGINT, NULL::BIGINT,
      'Error: INSERT en app_dat_consignacion_envio retornó NULL'::VARCHAR;
    RETURN;
  END IF;
  
  -- 6. Crear ENVÍO_PRODUCTOS para cada producto
  FOR v_producto IN SELECT jsonb_array_elements(p_productos)
  LOOP
    v_id_producto_original := (v_producto->>'id_producto')::BIGINT;
    v_id_inventario := (v_producto->>'id_inventario')::BIGINT;
    v_cantidad := (v_producto->>'cantidad')::NUMERIC;
    v_precio_costo_cup := (v_producto->>'precio_costo_cup')::NUMERIC;
    
    -- ⭐ OBTENER DATOS ORIGINALES DEL INVENTARIO
    SELECT 
      ip.id_presentacion,
      ip.id_variante,
      ip.id_ubicacion
    INTO 
      v_id_presentacion_original,
      v_id_variante_original,
      v_id_ubicacion_original
    FROM app_dat_inventario_productos ip
    WHERE ip.id = v_id_inventario;
    
    RAISE NOTICE 'Insertando producto: id_envio=%, id_inventario=%, id_producto=%, cantidad=%, presentacion=%, variante=%, ubicacion=%', 
      v_id_envio, v_id_inventario, v_id_producto_original, v_cantidad,
      v_id_presentacion_original, v_id_variante_original, v_id_ubicacion_original;
    
    -- Insertar producto del envío con datos originales
    INSERT INTO app_dat_consignacion_envio_producto (
      id_envio, 
      id_inventario, 
      id_producto, 
      cantidad_propuesta, 
      precio_costo_cup, 
      precio_costo_usd, 
      estado_producto, 
      created_at,
      -- ⭐ CAMPOS NUEVOS
      id_presentacion_original,
      id_variante_original,
      id_ubicacion_original,
      id_inventario_original
    ) VALUES (
      v_id_envio,
      v_id_inventario,
      v_id_producto_original,
      v_cantidad,
      v_precio_costo_cup,
      (v_producto->>'precio_costo_usd')::NUMERIC,
      1,
      CURRENT_TIMESTAMP,
      -- ⭐ VALORES ORIGINALES
      v_id_presentacion_original,
      v_id_variante_original,
      v_id_ubicacion_original,
      v_id_inventario
    );
    
    RAISE NOTICE 'Producto insertado exitosamente con datos originales';
  END LOOP;
  
  -- Retornar resultado exitoso
  RETURN QUERY SELECT 
    true::BOOLEAN AS success,
    v_id_envio::BIGINT AS id_envio,
    v_numero_envio::VARCHAR AS numero_envio,
    v_id_operacion_extraccion::BIGINT AS id_operacion_extraccion,
    v_id_operacion_recepcion::BIGINT AS id_operacion_recepcion,
    'Envío creado exitosamente'::VARCHAR AS mensaje;

EXCEPTION WHEN OTHERS THEN
  RETURN QUERY SELECT 
    false::BOOLEAN AS success,
    NULL::BIGINT AS id_envio,
    NULL::VARCHAR AS numero_envio,
    NULL::BIGINT AS id_operacion_extraccion,
    NULL::BIGINT AS id_operacion_recepcion,
    ('Error: ' || SQLERRM)::VARCHAR AS mensaje;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- PARTE 3: Modificar fn_actualizar_precio_promedio_recepcion_v2
-- ============================================================================
-- Tu función NO recibe p_id_operacion, recibe p_productos directamente
-- Por lo tanto, necesitamos una estrategia diferente
-- ============================================================================

-- OPCIÓN 1: Agregar p_id_operacion como parámetro (RECOMENDADO)
CREATE OR REPLACE FUNCTION fn_actualizar_precio_promedio_recepcion_v2(
  p_id_operacion BIGINT,  -- ⭐ AGREGAR ESTE PARÁMETRO
  p_productos JSONB
) RETURNS TABLE (
  success BOOLEAN,
  mensaje TEXT,
  productos_actualizados INT,
  tiempo_ms INT
) AS $$
DECLARE
  v_contador INT := 0;
  v_rows_updated INT := 0;
  v_rows_inserted INT := 0;
  v_start_time TIMESTAMP;
  v_tiempo_ms INT;
  v_es_devolucion BOOLEAN;  -- ⭐ NUEVA VARIABLE
BEGIN
  v_start_time := CLOCK_TIMESTAMP();
  
  -- ⭐ VERIFICAR SI ES DEVOLUCIÓN
  SELECT EXISTS (
    SELECT 1 
    FROM app_dat_consignacion_envio
    WHERE id_operacion_recepcion = p_id_operacion
      AND tipo_envio = 2  -- Devolución
  ) INTO v_es_devolucion;

  -- ⭐ SI ES DEVOLUCIÓN, NO ACTUALIZAR PRECIO PROMEDIO
  IF v_es_devolucion THEN
    v_tiempo_ms := EXTRACT(EPOCH FROM (CLOCK_TIMESTAMP() - v_start_time))::INT * 1000;
    RAISE NOTICE 'Operación % es devolución - precio promedio NO se actualiza', p_id_operacion;
    
    RETURN QUERY SELECT 
      true::BOOLEAN,
      'Operación de devolución - precio promedio no actualizado'::TEXT,
      0::INT,
      v_tiempo_ms::INT;
    RETURN;
  END IF;
  
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
  productos_a_actualizar AS (
    SELECT
      id,
      precio_promedio_nuevo
    FROM productos_con_anterior
    WHERE NOT es_nuevo AND precio_promedio_nuevo IS NOT NULL
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
  
  v_contador := v_rows_updated + v_rows_inserted;
  v_tiempo_ms := EXTRACT(EPOCH FROM (CLOCK_TIMESTAMP() - v_start_time))::INT * 1000;

  -- =====================================================
  -- REGISTRAR AUDITORÍA
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
$$ LANGUAGE plpgsql;

-- ============================================================================
-- MENSAJE DE CONFIRMACIÓN
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '✅ MODIFICACIONES COMPLETADAS';
  RAISE NOTICE '';
  RAISE NOTICE '1. ✅ crear_envio_consignacion - Guarda datos originales';
  RAISE NOTICE '2. ✅ fn_actualizar_precio_promedio_recepcion_v2 - Ignora devoluciones';
  RAISE NOTICE '';
  RAISE NOTICE '⚠️ IMPORTANTE: Verificar que las llamadas a fn_actualizar_precio_promedio_recepcion_v2';
  RAISE NOTICE '   ahora incluyan p_id_operacion como primer parámetro';
  RAISE NOTICE '';
  RAISE NOTICE '📝 PRÓXIMO PASO: Modificar código Dart';
END $$;
