-- ============================================================================
-- CORRECCIÓN: crear_devolucion_consignacion
-- ============================================================================
-- Problema: No encuentra productos porque busca estado_producto = 3
-- Solución: Buscar productos en cualquier estado válido (no rechazados)
-- ============================================================================

-- ============================================================================
-- PASO 1: DIAGNÓSTICO - Ejecutar esto primero para ver qué está pasando
-- ============================================================================

-- Ver productos del contrato y sus estados
-- REEMPLAZAR [ID_CONTRATO] con el ID real
/*
SELECT 
  ce.id as id_envio,
  ce.numero_envio,
  ce.tipo_envio,
  ce.estado_envio,
  cep.id as id_envio_producto,
  cep.id_producto,
  cep.estado_producto,
  cep.id_presentacion_original,
  cep.id_variante_original,
  cep.id_ubicacion_original,
  cep.id_inventario_original,
  p.denominacion as nombre_producto
FROM app_dat_consignacion_envio ce
INNER JOIN app_dat_consignacion_envio_producto cep ON cep.id_envio = ce.id
INNER JOIN app_dat_producto p ON p.id = cep.id_producto
WHERE ce.id_contrato_consignacion = [ID_CONTRATO]
  AND ce.tipo_envio = 1  -- Solo envíos directos
ORDER BY ce.created_at DESC, cep.id;
*/

-- Ver si el producto 5255 existe en algún envío
/*
SELECT 
  ce.id as id_envio,
  ce.numero_envio,
  ce.tipo_envio,
  cep.id_producto,
  cep.estado_producto,
  cep.id_presentacion_original,
  cep.id_variante_original,
  cep.id_ubicacion_original
FROM app_dat_consignacion_envio ce
INNER JOIN app_dat_consignacion_envio_producto cep ON cep.id_envio = ce.id
WHERE cep.id_producto = 5255
  AND ce.tipo_envio = 1
ORDER BY ce.created_at DESC;
*/

-- ============================================================================
-- PASO 2: FUNCIÓN CORREGIDA
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
  v_id_producto BIGINT;
  v_cantidad NUMERIC;
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
    id_usuario_creador
  ) VALUES (
    p_id_contrato,
    v_numero_envio,
    2,  -- TIPO_ENVIO_DEVOLUCION
    1,  -- ESTADO_PROPUESTO
    p_id_almacen_origen,
    v_id_almacen_destino,
    COALESCE(p_descripcion, 'Devolución de productos en consignación'),
    NOW(),
    p_id_usuario
  ) RETURNING id INTO v_id_envio;

  -- 5. Crear operación de extracción (PENDIENTE) en tienda consignataria
  INSERT INTO app_dat_operaciones (
    id_tienda,
    id_tipo_operacion,
    uuid,
    observaciones,
    created_at
  ) VALUES (
    v_id_tienda_consignataria,
    7,  -- Tipo: Extracción de consignación
    p_id_usuario,
    'Extracción por devolución - ' || v_numero_envio,
    CURRENT_TIMESTAMP
  ) RETURNING id INTO v_id_operacion_extraccion;

  -- Actualizar envío con operación de extracción
  UPDATE app_dat_consignacion_envio
  SET id_operacion_extraccion = v_id_operacion_extraccion
  WHERE id = v_id_envio;

  -- Registrar estado inicial de la operación
  INSERT INTO app_dat_estado_operacion (id_operacion, estado, comentario)
  VALUES (v_id_operacion_extraccion, 1, 'Operación de extracción creada para devolución');

  -- 6. Insertar productos en el envío
  FOR v_producto IN SELECT * FROM jsonb_array_elements(p_productos)
  LOOP
    v_id_producto := (v_producto->>'id_producto')::BIGINT;
    v_cantidad := (v_producto->>'cantidad')::NUMERIC;

    RAISE NOTICE 'Procesando producto % para devolución', v_id_producto;

    -- ⭐ CORRECCIÓN: Buscar en cualquier estado válido, no solo estado = 3
    -- También verificar que los datos originales no sean NULL
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
      cep.id_producto,
      (v_producto->>'id_inventario')::BIGINT,
      v_cantidad,
      cep.precio_costo_usd,
      cep.precio_costo_cup,
      cep.tasa_cambio,
      1,  -- ESTADO_PROPUESTO para la devolución
      -- ⭐ COPIAR datos originales del envío inicial
      -- Si son NULL, intentar obtenerlos del inventario actual
      COALESCE(cep.id_presentacion_original, (
        SELECT id_presentacion 
        FROM app_dat_inventario_productos 
        WHERE id = (v_producto->>'id_inventario')::BIGINT
      )),
      COALESCE(cep.id_variante_original, (
        SELECT id_variante 
        FROM app_dat_inventario_productos 
        WHERE id = (v_producto->>'id_inventario')::BIGINT
      )),
      COALESCE(cep.id_ubicacion_original, (
        SELECT id_ubicacion 
        FROM app_dat_inventario_productos 
        WHERE id = (v_producto->>'id_inventario')::BIGINT
      )),
      COALESCE(cep.id_inventario_original, (v_producto->>'id_inventario')::BIGINT),
      CURRENT_TIMESTAMP
    FROM app_dat_consignacion_envio_producto cep
    INNER JOIN app_dat_consignacion_envio ce ON ce.id = cep.id_envio
    WHERE ce.id_contrato_consignacion = p_id_contrato
      AND ce.tipo_envio = 1  -- Solo del envío original (no de otras devoluciones)
      AND cep.id_producto = v_id_producto
      AND cep.estado_producto != 4  -- ⭐ CAMBIO: Excluir solo rechazados (4), aceptar todos los demás
    ORDER BY cep.created_at DESC
    LIMIT 1;

    GET DIAGNOSTICS v_rows_inserted = ROW_COUNT;

    -- Verificar que se insertó el producto
    IF v_rows_inserted = 0 THEN
      RAISE EXCEPTION 'No se encontró información del producto % en el envío original. Verifica que: 1) El producto fue enviado en consignación, 2) El producto no fue rechazado, 3) Los datos originales existen', v_id_producto;
    END IF;

    RAISE NOTICE 'Producto % insertado correctamente en devolución', v_id_producto;
  END LOOP;

  -- 7. Registrar movimiento
  INSERT INTO app_dat_consignacion_envio_movimiento (
    id_envio,
    tipo_movimiento,
    id_usuario,
    descripcion
  ) VALUES (
    v_id_envio,
    1,  -- MOVIMIENTO_CREACION
    p_id_usuario,
    'Devolución creada por consignatario'
  );

  RETURN QUERY SELECT v_id_envio, v_numero_envio, v_id_operacion_extraccion;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION crear_devolucion_consignacion IS 
  'Crea una solicitud de devolución de productos en consignación, copiando los datos originales del envío inicial. Acepta productos en cualquier estado excepto rechazados.';

-- ============================================================================
-- MENSAJE DE CONFIRMACIÓN
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '✅ Función crear_devolucion_consignacion corregida';
  RAISE NOTICE '';
  RAISE NOTICE '📋 CAMBIOS REALIZADOS:';
  RAISE NOTICE '1. Busca productos con estado_producto != 4 (cualquiera excepto rechazados)';
  RAISE NOTICE '2. Si datos originales son NULL, los obtiene del inventario actual';
  RAISE NOTICE '3. Mensaje de error más descriptivo';
  RAISE NOTICE '4. Logs de depuración mejorados';
  RAISE NOTICE '';
  RAISE NOTICE '🔍 PARA DIAGNOSTICAR:';
  RAISE NOTICE 'Ejecuta las queries comentadas al inicio del archivo';
  RAISE NOTICE 'para ver el estado real de los productos en tu BD';
END $$;
