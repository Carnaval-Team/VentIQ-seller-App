-- ============================================================================
-- CORRECCIÓN FINAL V2: aprobar_devolucion_consignacion
-- ============================================================================
-- ESTRATEGIA CORRECTA:
-- 1. Completar operación de EXTRACCIÓN en consignatario (reduce inventario)
-- 2. Crear operación de RECEPCIÓN en consignador (PENDIENTE, no completada)
-- 3. Vincular operación de recepción al envío
-- 4. El inventario en consignador se actualizará cuando se COMPLETE la recepción
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
  v_productos_extraccion JSONB := '[]'::JSONB;
  v_producto_json JSONB;
  v_extraccion_result JSONB;
  -- Variables para datos del inventario del producto duplicado
  v_id_presentacion_original BIGINT;
  v_id_variante_original BIGINT;
  v_id_ubicacion_original BIGINT;
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

  -- 4. Preparar productos para extracción (productos DUPLICADOS del consignatario)
  -- ⭐ IMPORTANTE: Usar los datos del inventario DUPLICADO en la zona de consignación
  FOR v_producto IN 
    SELECT 
      cep.id_producto,
      cep.cantidad_propuesta,
      cep.precio_costo_usd
    FROM app_dat_consignacion_envio_producto cep
    WHERE cep.id_envio = p_id_envio
  LOOP
    -- ⭐ Obtener el producto DUPLICADO desde la tabla de duplicados
    SELECT pcd.id_producto_duplicado
    INTO v_id_producto_duplicado
    FROM app_dat_producto_consignacion_duplicado pcd
    INNER JOIN app_dat_consignacion_envio ce ON ce.id_contrato_consignacion = pcd.id_contrato_consignacion
    WHERE pcd.id_producto_original = v_producto.id_producto
      AND ce.id = p_id_envio
    LIMIT 1;

    -- Si no se encuentra duplicado, usar el producto original
    v_id_producto_duplicado := COALESCE(v_id_producto_duplicado, v_producto.id_producto);

    -- ⭐ Buscar la zona de consignación en la tienda consignataria
    -- La zona tiene id_zona (ubicación en layout_almacen)
    SELECT id_zona INTO v_id_zona_consignacion
    FROM app_dat_consignacion_zona
    WHERE id_tienda_consignataria = v_id_tienda_consignataria
    LIMIT 1;

    -- ⭐ CRÍTICO: Obtener los datos del INVENTARIO del producto DUPLICADO en la zona de consignación
    -- Buscar el registro más reciente del producto duplicado en la zona de consignación
    SELECT 
      ip.id_presentacion,
      ip.id_variante,
      ip.id_ubicacion
    INTO 
      v_id_presentacion_original,
      v_id_variante_original,
      v_id_ubicacion_original
    FROM app_dat_inventario_productos ip
    WHERE ip.id_producto = v_id_producto_duplicado
      AND ip.id_ubicacion = v_id_zona_consignacion
    ORDER BY ip.created_at DESC
    LIMIT 1;
    
    -- Si no se encuentra en la zona de consignación, buscar en cualquier ubicación de la tienda
    IF v_id_ubicacion_original IS NULL THEN
      SELECT 
        ip.id_presentacion,
        ip.id_variante,
        ip.id_ubicacion
      INTO 
        v_id_presentacion_original,
        v_id_variante_original,
        v_id_ubicacion_original
      FROM app_dat_inventario_productos ip
      INNER JOIN app_dat_layout_almacen la ON la.id = ip.id_ubicacion
      INNER JOIN app_dat_almacen a ON a.id = la.id_almacen
      WHERE ip.id_producto = v_id_producto_duplicado
        AND a.id_tienda = v_id_tienda_consignataria
      ORDER BY ip.created_at DESC
      LIMIT 1;
    END IF;

    RAISE NOTICE '📦 Preparando extracción de producto duplicado % (original: %), presentación: %, variante: %, ubicación: %', 
      v_id_producto_duplicado, v_producto.id_producto, 
      v_id_presentacion_original, v_id_variante_original, v_id_ubicacion_original;

    -- ⭐ Construir JSON con datos del producto DUPLICADO del inventario del consignatario
    v_producto_json := jsonb_build_object(
      'id_producto', v_id_producto_duplicado,
      'cantidad', v_producto.cantidad_propuesta,
      'id_presentacion', v_id_presentacion_original,
      'id_ubicacion', v_id_ubicacion_original,
      'id_variante', v_id_variante_original,
      'precio_unitario', v_producto.precio_costo_usd
    );

    v_productos_extraccion := v_productos_extraccion || v_producto_json;
  END LOOP;

  -- 5. Crear operación de extracción usando fn_crear_extraccion_con_movimiento
  -- Aplica el movimiento de inventario inmediatamente al crear la extracción
  -- Parámetros: p_autorizado_por (text), p_estado_inicial (smallint), p_id_motivo_operacion (bigint), 
  --             p_id_tienda (bigint), p_observaciones (text), p_productos (jsonb), p_uuid (uuid)
  SELECT fn_crear_extraccion_con_movimiento(
    'Sistema'::TEXT,  -- p_autorizado_por
    1::SMALLINT,  -- p_estado_inicial (1 = Pendiente)
    21::BIGINT,  -- p_id_motivo_operacion (Consignación)
    v_id_tienda_consignataria,  -- p_id_tienda
    ('Extracción para devolución - ' || v_numero_envio)::TEXT,  -- p_observaciones
    v_productos_extraccion,  -- p_productos
    p_id_usuario  -- p_uuid
  ) INTO v_extraccion_result;

  IF (v_extraccion_result->>'status')::TEXT != 'success' THEN
    RAISE EXCEPTION 'Error creando extracción: %', v_extraccion_result->>'message';
  END IF;

  v_id_operacion_extraccion := (v_extraccion_result->>'id_operacion')::BIGINT;
  
  RAISE NOTICE '✅ Operación de extracción COMPLETADA (con movimiento de inventario) creada: %', v_id_operacion_extraccion;

  -- 6. Vincular operación de extracción al envío
  UPDATE app_dat_consignacion_envio
  SET id_operacion_extraccion = v_id_operacion_extraccion
  WHERE id = p_id_envio;

  -- 7. Crear operación de RECEPCIÓN en tienda consignadora (PENDIENTE)
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

  -- Registrar estado inicial de la operación de recepción (PENDIENTE)
  INSERT INTO app_dat_estado_operacion (id_operacion, estado, comentario)
  VALUES (v_id_operacion_recepcion, 1, 'Operación de recepción creada para devolución - Pendiente de completar');

  -- 6. Vincular operación de recepción al envío y actualizar estado a CONFIGURADO
  -- Los triggers se encargarán de cambiar a EN TRÁNSITO (3) y ACEPTADO (4) automáticamente
  UPDATE app_dat_consignacion_envio
  SET 
    id_operacion_recepcion = v_id_operacion_recepcion,
    estado_envio = 2,  -- CONFIGURADO (devolución aprobada, operaciones pendientes)
    fecha_configuracion = NOW(),
    id_almacen_destino = p_id_almacen_recepcion
  WHERE id = p_id_envio;

  -- 8. Registrar productos de recepción (PENDIENTE) - Se completarán cuando el consignador complete la recepción
  FOR v_producto IN 
    SELECT 
      cep.id_producto,
      cep.cantidad_propuesta,
      cep.id_presentacion_original,
      cep.id_variante_original,
      cep.id_ubicacion_original,
      cep.precio_costo_usd
    FROM app_dat_consignacion_envio_producto cep
    WHERE cep.id_envio = p_id_envio
  LOOP
    RAISE NOTICE '📥 Registrando producto original % para recepción pendiente', v_producto.id_producto;

    -- ⭐ Registrar productos de recepción (PENDIENTE, no actualiza inventario aún)
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
  END LOOP;

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
    2,  -- ESTADO_CONFIGURADO
    'Devolución aprobada - Operaciones de extracción y recepción creadas (pendientes de completar)'
  );

  RETURN QUERY SELECT TRUE, v_id_operacion_recepcion, 
    'Devolución aprobada exitosamente. Operaciones de extracción y recepción creadas en estado PENDIENTE. El consignatario debe completar la extracción y el consignador debe completar la recepción.'::TEXT;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION aprobar_devolucion_consignacion IS 
  'Aprueba una devolución: crea operación de extracción COMPLETADA (con movimiento de inventario inmediato) del producto DUPLICADO en consignatario usando fn_crear_extraccion_con_movimiento, y operación de recepción PENDIENTE del producto ORIGINAL en consignador. El consignador debe completar la recepción desde su pantalla de operaciones.';

-- ============================================================================
-- MENSAJE DE CONFIRMACIÓN
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '✅ Función aprobar_devolucion_consignacion corregida V3 (usa fn_crear_extraccion_con_movimiento)';
  RAISE NOTICE '';
  RAISE NOTICE '📋 FLUJO CORRECTO:';
  RAISE NOTICE '1. Crea operación de extracción COMPLETADA (inventario reducido inmediatamente) del producto DUPLICADO en consignatario';
  RAISE NOTICE '2. Registra productos de extracción (sin actualizar inventario aún)';
  RAISE NOTICE '3. Crea operación de recepción PENDIENTE en consignador';
  RAISE NOTICE '4. Registra productos de recepción (sin actualizar inventario aún)';
  RAISE NOTICE '5. Vincula ambas operaciones al envío';
  RAISE NOTICE '6. El inventario del consignatario ya fue reducido al crear la extracción (fn_crear_extraccion_con_movimiento)';
  RAISE NOTICE '7. El consignador debe COMPLETAR la recepción para aumentar inventario';
  RAISE NOTICE '';
  RAISE NOTICE '✅ LISTO PARA USAR';
END $$;
