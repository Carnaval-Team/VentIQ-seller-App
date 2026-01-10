-- ============================================================================
-- CORRECCIÓN FINAL: aprobar_devolucion_consignacion
-- ============================================================================
-- PROBLEMA: app_dat_inventario_productos NO tiene columna id_tienda
-- SOLUCIÓN: Buscar por id_ubicacion que pertenece a la tienda
-- ============================================================================

CREATE OR REPLACE FUNCTION aprobar_devolucion_consignacion(
  p_id_envio BIGINT,
  p_id_almacen_recepcion BIGINT,
  p_id_usuario UUID
) RETURNS TABLE (
  success BOOLEAN,
  id_operacion_recepcion BIGINT,
  mensaje TEXT
) AS $$
DECLARE
  v_id_operacion_recepcion BIGINT;
  v_id_operacion_extraccion BIGINT;
  v_id_tienda_consignadora BIGINT;
  v_id_tienda_consignataria BIGINT;
  v_numero_envio VARCHAR;
  v_producto RECORD;
  v_id_zona_consignacion BIGINT;
  v_id_producto_duplicado BIGINT;
  v_id_producto_original BIGINT;
  v_cantidad_anterior NUMERIC;
BEGIN
  -- 1. Validar que el envío es de tipo devolución y está en estado PROPUESTO
  IF NOT EXISTS (
    SELECT 1 FROM app_dat_consignacion_envio
    WHERE id = p_id_envio 
      AND tipo_envio = 2 
      AND estado_envio = 1
  ) THEN
    RETURN QUERY SELECT FALSE, NULL::BIGINT, 
      'El envío no es una devolución válida o ya fue procesado'::TEXT;
    RETURN;
  END IF;

  -- 2. Obtener información del envío
  SELECT 
    ce.numero_envio, 
    cc.id_tienda_consignadora,
    cc.id_tienda_consignataria
  INTO v_numero_envio, v_id_tienda_consignadora, v_id_tienda_consignataria
  FROM app_dat_consignacion_envio ce
  INNER JOIN app_dat_contrato_consignacion cc ON cc.id = ce.id_contrato_consignacion
  WHERE ce.id = p_id_envio;

  -- 3. Obtener la operación de extracción creada al solicitar la devolución
  SELECT id_operacion_extraccion INTO v_id_operacion_extraccion
  FROM app_dat_consignacion_envio
  WHERE id = p_id_envio;

  -- 4. Completar la operación de extracción en consignatario
  IF v_id_operacion_extraccion IS NOT NULL THEN
    -- Para cada producto, registrar la extracción
    FOR v_producto IN 
      SELECT 
        cep.id_producto,
        cep.cantidad_propuesta,
        cep.id_presentacion_original,
        cep.id_variante_original,
        cep.id_ubicacion_original,
        cep.precio_costo_usd,
        cep.id_inventario
      FROM app_dat_consignacion_envio_producto cep
      WHERE cep.id_envio = p_id_envio
    LOOP
      -- ⭐ Obtener el producto DUPLICADO desde la tabla de duplicados
      -- El producto en cep.id_producto es el ORIGINAL, necesitamos el DUPLICADO para la extracción
      SELECT pcd.id_producto_duplicado
      INTO v_id_producto_duplicado
      FROM app_dat_producto_consignacion_duplicado pcd
      INNER JOIN app_dat_consignacion_envio ce ON ce.id_contrato_consignacion = pcd.id_contrato_consignacion
      WHERE pcd.id_producto_original = v_producto.id_producto
        AND ce.id = p_id_envio
      LIMIT 1;

      -- Si no se encuentra duplicado, usar el producto original
      v_id_producto_duplicado := COALESCE(v_id_producto_duplicado, v_producto.id_producto);

      RAISE NOTICE '📦 Extrayendo producto duplicado % (original: %) del consignatario', 
        v_id_producto_duplicado, v_producto.id_producto;

      -- Buscar la zona de consignación en la tienda consignataria
      SELECT id_zona INTO v_id_zona_consignacion
      FROM app_dat_consignacion_zona
      WHERE id_tienda_consignataria = v_id_tienda_consignataria
      LIMIT 1;

      -- Registrar extracción del producto DUPLICADO
      INSERT INTO app_dat_extraccion_productos (
        id_operacion,
        id_producto,
        id_presentacion,
        id_variante,
        id_ubicacion,
        cantidad,
        precio_unitario
      ) VALUES (
        v_id_operacion_extraccion,
        v_id_producto_duplicado,  -- ⭐ Usar producto DUPLICADO
        v_producto.id_presentacion_original,
        v_producto.id_variante_original,
        COALESCE(v_id_zona_consignacion, v_producto.id_ubicacion_original),
        v_producto.cantidad_propuesta,
        v_producto.precio_costo_usd
      );

      -- ⭐ Reducir inventario en la tienda consignataria
      -- Buscar por id_ubicacion que pertenece a la tienda consignataria
      UPDATE app_dat_inventario_productos
      SET cantidad_final = GREATEST(0, cantidad_final - v_producto.cantidad_propuesta)
      WHERE id_producto = v_id_producto_duplicado  -- ⭐ Producto DUPLICADO
        AND id_presentacion = v_producto.id_presentacion_original
        AND id_ubicacion IN (
          SELECT la.id 
          FROM app_dat_layout_almacen la
          INNER JOIN app_dat_almacen a ON a.id = la.id_almacen
          WHERE a.id_tienda = v_id_tienda_consignataria
        )
        AND COALESCE(id_variante, 0) = COALESCE(v_producto.id_variante_original, 0);

      RAISE NOTICE '✅ Inventario reducido en consignatario';
    END LOOP;

    -- Completar operación de extracción
    UPDATE app_dat_estado_operacion
    SET estado = 2, comentario = 'Extracción completada para devolución'
    WHERE id_operacion = v_id_operacion_extraccion;
  END IF;

  -- 5. Crear operación de RECEPCIÓN en tienda consignadora
  INSERT INTO app_dat_operaciones (
    id_tienda,
    id_tipo_operacion,
    uuid,
    observaciones,
    created_at
  ) VALUES (
    v_id_tienda_consignadora,
    1,  -- Tipo: Recepción
    p_id_usuario,
    'Recepción de devolución - ' || v_numero_envio,
    CURRENT_TIMESTAMP
  ) RETURNING id INTO v_id_operacion_recepcion;

  -- Actualizar envío con operación de recepción
  UPDATE app_dat_consignacion_envio
  SET id_operacion_recepcion = v_id_operacion_recepcion
  WHERE id = p_id_envio;

  -- 6. Para cada producto, restaurar al inventario ORIGINAL en consignador
  FOR v_producto IN 
    SELECT 
      cep.id_producto,
      cep.cantidad_propuesta,
      cep.id_presentacion_original,
      cep.id_variante_original,
      cep.id_ubicacion_original,
      cep.id_inventario_original,
      cep.precio_costo_usd
    FROM app_dat_consignacion_envio_producto cep
    WHERE cep.id_envio = p_id_envio
  LOOP
    RAISE NOTICE '📥 Recibiendo producto original % en consignador', v_producto.id_producto;

    -- ⭐ Registrar recepción del producto ORIGINAL
    INSERT INTO app_dat_recepcion_productos (
      id_operacion,
      id_producto,
      id_presentacion,
      id_variante,
      id_ubicacion,
      cantidad,
      precio_unitario
    ) VALUES (
      v_id_operacion_recepcion,
      v_producto.id_producto,  -- ⭐ Producto ORIGINAL
      v_producto.id_presentacion_original,
      v_producto.id_variante_original,
      v_producto.id_ubicacion_original,
      v_producto.cantidad_propuesta,
      v_producto.precio_costo_usd
    );

    -- ⭐ Registrar movimiento de inventario en la ubicación ORIGINAL del consignador
    -- app_dat_inventario_productos es una tabla de HISTORIAL, cada fila es un movimiento
    -- Obtener la cantidad final del último registro para calcular la nueva cantidad
    SELECT cantidad_final INTO v_cantidad_anterior
    FROM app_dat_inventario_productos
    WHERE id_producto = v_producto.id_producto
      AND id_presentacion = v_producto.id_presentacion_original
      AND id_ubicacion = v_producto.id_ubicacion_original
      AND COALESCE(id_variante, 0) = COALESCE(v_producto.id_variante_original, 0)
    ORDER BY created_at DESC
    LIMIT 1;
    
    -- Si no hay registro anterior, la cantidad anterior es 0
    v_cantidad_anterior := COALESCE(v_cantidad_anterior, 0);

    -- Insertar nuevo registro de movimiento de inventario
    INSERT INTO app_dat_inventario_productos (
      id_producto,
      id_presentacion,
      id_variante,
      id_ubicacion,
      cantidad_inicial,
      cantidad_final,
      origen_cambio,
      id_recepcion,
      created_at
    ) VALUES (
      v_producto.id_producto,
      v_producto.id_presentacion_original,
      v_producto.id_variante_original,
      v_producto.id_ubicacion_original,
      v_cantidad_anterior,  -- Cantidad antes del movimiento
      v_cantidad_anterior + v_producto.cantidad_propuesta,  -- Cantidad después del movimiento
      1,  -- Origen: Recepción
      v_id_operacion_recepcion,
      CURRENT_TIMESTAMP
    );

    RAISE NOTICE '✅ Inventario restaurado en consignador: % → %', 
      v_cantidad_anterior, v_cantidad_anterior + v_producto.cantidad_propuesta;
  END LOOP;

  -- 7. Actualizar estado del envío
  UPDATE app_dat_consignacion_envio
  SET 
    estado_envio = 4,  -- ESTADO_ACEPTADO
    fecha_aceptacion = NOW(),
    id_almacen_destino = p_id_almacen_recepcion
  WHERE id = p_id_envio;

  -- 8. Completar operación de recepción
  INSERT INTO app_dat_estado_operacion (id_operacion, estado, comentario)
  VALUES (v_id_operacion_recepcion, 2, 'Devolución recibida y productos restaurados');

  -- 9. Registrar movimiento
  INSERT INTO app_dat_consignacion_envio_movimiento (
    id_envio,
    tipo_movimiento,
    id_usuario,
    estado_anterior,
    estado_nuevo,
    descripcion
  ) VALUES (
    p_id_envio,
    4,  -- MOVIMIENTO_ACEPTACION
    p_id_usuario,
    1,  -- ESTADO_PROPUESTO
    4,  -- ESTADO_ACEPTADO
    'Devolución aprobada y recibida por consignador'
  );

  RETURN QUERY SELECT TRUE, v_id_operacion_recepcion, 
    'Devolución aprobada exitosamente. Productos restaurados a ubicación original.'::TEXT;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION aprobar_devolucion_consignacion IS 
  'Aprueba una devolución, completa la extracción del producto DUPLICADO en consignatario y crea recepción del producto ORIGINAL en consignador restaurando a su ubicación original. NO actualiza precio promedio.';

-- ============================================================================
-- MENSAJE DE CONFIRMACIÓN
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '✅ Función aprobar_devolucion_consignacion corregida';
  RAISE NOTICE '';
  RAISE NOTICE '📋 FLUJO CORRECTO:';
  RAISE NOTICE '1. Extrae producto DUPLICADO del consignatario';
  RAISE NOTICE '2. Reduce inventario en ubicaciones del consignatario';
  RAISE NOTICE '3. Recibe producto ORIGINAL en consignador';
  RAISE NOTICE '4. Restaura inventario en ubicación ORIGINAL';
  RAISE NOTICE '5. NO actualiza precio promedio (fn_actualizar_precio_promedio_recepcion_v2 lo detecta)';
  RAISE NOTICE '';
  RAISE NOTICE '✅ LISTO PARA USAR';
END $$;
