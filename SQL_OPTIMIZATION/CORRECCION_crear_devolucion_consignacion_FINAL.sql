-- ============================================================================
-- CORRECCIÓN FINAL: crear_devolucion_consignacion
-- ============================================================================
-- PROBLEMA: Los productos en consignación se duplican y la relación está en
-- app_dat_producto_consignacion_duplicado
-- 
-- SOLUCIÓN: 
-- 1. El producto que se quiere devolver es el DUPLICADO (en tienda consignataria)
-- 2. Buscar en app_dat_producto_consignacion_duplicado para obtener el producto ORIGINAL
-- 3. Usar producto ORIGINAL para buscar en el envío inicial
-- 4. Copiar datos originales del envío inicial a la devolución
-- ============================================================================

CREATE OR REPLACE FUNCTION crear_devolucion_consignacion(
  p_id_contrato BIGINT,
  p_id_almacen_origen BIGINT,
  p_id_usuario UUID,
  p_productos JSONB,
  p_descripcion TEXT DEFAULT NULL
) RETURNS TABLE (
  id_envio BIGINT,
  numero_envio VARCHAR,
  id_operacion_extraccion BIGINT
) AS $$
DECLARE
  v_id_envio BIGINT;
  v_numero_envio VARCHAR;
  v_id_operacion_extraccion BIGINT;
  v_producto JSONB;
  v_id_tienda_consignadora BIGINT;
  v_id_tienda_consignataria BIGINT;
  v_id_almacen_destino BIGINT;
  v_id_producto_duplicado BIGINT;  -- Producto en tienda consignataria (el que se devuelve)
  v_id_producto_original BIGINT;   -- Producto en tienda consignadora (el original)
  v_cantidad NUMERIC;
  v_id_inventario BIGINT;
  v_rows_inserted INT;
BEGIN
  -- 1. Obtener tiendas del contrato
  SELECT id_tienda_consignadora, id_tienda_consignataria
  INTO v_id_tienda_consignadora, v_id_tienda_consignataria
  FROM app_dat_contrato_consignacion
  WHERE id = p_id_contrato;

  IF v_id_tienda_consignadora IS NULL THEN
    RAISE EXCEPTION 'Contrato no encontrado: %', p_id_contrato;
  END IF;

  -- 2. Obtener almacén destino (primer almacén del consignador)
  SELECT id INTO v_id_almacen_destino
  FROM app_dat_almacen
  WHERE id_tienda = v_id_tienda_consignadora
  LIMIT 1;

  IF v_id_almacen_destino IS NULL THEN
    RAISE EXCEPTION 'No se encontró almacén para la tienda consignadora';
  END IF;

  -- 3. Generar número de envío
  v_numero_envio := 'DEV-' || p_id_contrato || '-' || 
                    TO_CHAR(NOW(), 'YYYYMMDD-HH24MISS');

  -- 4. Crear envío de devolución (tipo_envio = 2)
  INSERT INTO app_dat_consignacion_envio (
    id_contrato_consignacion,
    numero_envio,
    tipo_envio,
    estado_envio,
    id_almacen_origen,
    id_almacen_destino,
    descripcion,
    fecha_propuesta,
    id_usuario_creador,
    estado,
    created_at,
    updated_at
  ) VALUES (
    p_id_contrato,
    v_numero_envio,
    2,  -- TIPO_ENVIO_DEVOLUCION
    1,  -- ESTADO_PROPUESTO
    p_id_almacen_origen,
    v_id_almacen_destino,
    COALESCE(p_descripcion, 'Devolución de productos en consignación'),
    NOW(),
    p_id_usuario,
    1,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
  ) RETURNING id INTO v_id_envio;

  -- ⭐ NO CREAR OPERACIÓN DE EXTRACCIÓN AQUÍ
  -- La operación de extracción se creará cuando se APRUEBE la devolución
  -- en la función aprobar_devolucion_consignacion usando fn_insertar_extraccion_completa2
  v_id_operacion_extraccion := NULL;

  -- 5. Insertar productos en el envío
  FOR v_producto IN SELECT * FROM jsonb_array_elements(p_productos)
  LOOP
    v_id_producto_duplicado := (v_producto->>'id_producto')::BIGINT;  -- Producto duplicado (consignatario)
    v_id_inventario := (v_producto->>'id_inventario')::BIGINT;
    v_cantidad := (v_producto->>'cantidad')::NUMERIC;

    RAISE NOTICE '🔍 Procesando devolución de producto duplicado: %', v_id_producto_duplicado;

    -- ⭐ PASO CRÍTICO: Obtener el producto ORIGINAL desde la tabla de duplicados
    SELECT pcd.id_producto_original
    INTO v_id_producto_original
    FROM app_dat_producto_consignacion_duplicado pcd
    WHERE pcd.id_producto_duplicado = v_id_producto_duplicado
      AND pcd.id_contrato_consignacion = p_id_contrato
    LIMIT 1;

    IF v_id_producto_original IS NULL THEN
      RAISE EXCEPTION 'No se encontró el producto original para el producto duplicado %. Verifica que el producto fue duplicado correctamente en la tabla app_dat_producto_consignacion_duplicado', v_id_producto_duplicado;
    END IF;

    RAISE NOTICE '✅ Producto original encontrado: % (duplicado: %)', v_id_producto_original, v_id_producto_duplicado;

    -- ⭐ Buscar en el envío ORIGINAL usando el producto ORIGINAL
    -- y copiar TODOS los datos (precios, datos originales, etc.)
    INSERT INTO app_dat_consignacion_envio_producto (
      id_envio,
      id_producto,
      id_inventario,
      cantidad_propuesta,
      precio_costo_usd,
      precio_costo_cup,
      tasa_cambio,
      estado_producto,
      id_presentacion_original,
      id_variante_original,
      id_ubicacion_original,
      id_inventario_original,
      created_at
    )
    SELECT
      v_id_envio,
      cep.id_producto,  -- ⭐ Usar producto ORIGINAL del envío inicial
      v_id_inventario,  -- Inventario del producto duplicado (actual)
      v_cantidad,
      cep.precio_costo_usd,
      cep.precio_costo_cup,
      cep.tasa_cambio,
      1,  -- ESTADO_PROPUESTO para la devolución
      -- ⭐ COPIAR datos originales del envío inicial
      cep.id_presentacion_original,
      cep.id_variante_original,
      cep.id_ubicacion_original,
      cep.id_inventario_original,
      CURRENT_TIMESTAMP
    FROM app_dat_consignacion_envio_producto cep
    INNER JOIN app_dat_consignacion_envio ce ON ce.id = cep.id_envio
    WHERE ce.id_contrato_consignacion = p_id_contrato
      AND ce.tipo_envio = 1  -- Solo del envío original (no de otras devoluciones)
      AND cep.id_producto = v_id_producto_original  -- ⭐ Buscar por producto ORIGINAL
      AND cep.estado_producto != 4  -- Excluir solo rechazados
    ORDER BY cep.created_at DESC
    LIMIT 1;

    GET DIAGNOSTICS v_rows_inserted = ROW_COUNT;

    -- Verificar que se insertó el producto
    IF v_rows_inserted = 0 THEN
      RAISE EXCEPTION 'No se encontró información del producto original % (duplicado: %) en el envío inicial. Verifica que: 1) El producto fue enviado en consignación, 2) El producto no fue rechazado, 3) Los datos originales existen en app_dat_consignacion_envio_producto', 
        v_id_producto_original, v_id_producto_duplicado;
    END IF;

    RAISE NOTICE '✅ Producto % insertado correctamente en devolución con datos originales', v_id_producto_original;
  END LOOP;

  -- 7. Registrar movimiento
  INSERT INTO app_dat_consignacion_envio_movimiento (
    id_envio,
    tipo_movimiento,
    id_usuario,
    estado_anterior,
    estado_nuevo,
    descripcion
  ) VALUES (
    v_id_envio,
    1,  -- MOVIMIENTO_CREACION
    p_id_usuario,
    NULL,  -- No hay estado anterior (es creación)
    1,  -- ESTADO_PROPUESTO
    'Devolución creada por consignatario'
  );

  RETURN QUERY SELECT v_id_envio, v_numero_envio, v_id_operacion_extraccion;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION crear_devolucion_consignacion IS 
  'Crea una solicitud de devolución de productos en consignación. Usa app_dat_producto_consignacion_duplicado para obtener el producto original y copiar los datos del envío inicial.';

-- ============================================================================
-- MENSAJE DE CONFIRMACIÓN
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '✅ Función crear_devolucion_consignacion corregida';
  RAISE NOTICE '';
  RAISE NOTICE '📋 FLUJO CORRECTO:';
  RAISE NOTICE '1. Recibe producto DUPLICADO (el que está en consignatario)';
  RAISE NOTICE '2. Busca en app_dat_producto_consignacion_duplicado para obtener producto ORIGINAL';
  RAISE NOTICE '3. Busca en envío inicial usando producto ORIGINAL';
  RAISE NOTICE '4. Copia TODOS los datos (precios, presentación, ubicación, etc.)';
  RAISE NOTICE '5. Crea operación de extracción con producto duplicado';
  RAISE NOTICE '';
  RAISE NOTICE '✅ LISTO PARA USAR';
END $$;
