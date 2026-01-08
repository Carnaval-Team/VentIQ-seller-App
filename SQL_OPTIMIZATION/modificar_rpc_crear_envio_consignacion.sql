-- ============================================================================
-- PASO 2: Modificar RPC crear_envio_consignacion
-- ============================================================================
-- Este script modifica el RPC existente para guardar los datos originales
-- del producto (presentación, variante, ubicación, inventario)
-- ============================================================================

CREATE OR REPLACE FUNCTION crear_envio_consignacion(
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
  v_id_inventario BIGINT;
  v_cantidad NUMERIC;
  v_precio_costo_usd NUMERIC;
  v_precio_costo_cup NUMERIC;
  v_precio_venta NUMERIC;
  v_tasa_cambio NUMERIC;
  -- ⭐ NUEVAS VARIABLES PARA DATOS ORIGINALES
  v_id_presentacion_original BIGINT;
  v_id_variante_original BIGINT;
  v_id_ubicacion_original BIGINT;
  v_id_inventario_original BIGINT;
BEGIN
  -- 1. Obtener tiendas del contrato
  SELECT id_tienda_consignadora, id_tienda_consignataria
  INTO v_id_tienda_consignadora, v_id_tienda_consignataria
  FROM app_dat_contrato_consignacion
  WHERE id = p_id_contrato;

  -- 2. Obtener almacén destino (primer almacén del consignatario)
  SELECT id INTO v_id_almacen_destino
  FROM app_dat_almacen
  WHERE id_tienda = v_id_tienda_consignataria
  LIMIT 1;

  -- 3. Generar número de envío
  v_numero_envio := 'ENV-' || p_id_contrato || '-' || 
                    TO_CHAR(NOW(), 'YYYYMMDD-HH24MISS');

  -- 4. Crear envío (tipo_envio = 1 para envío directo)
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
    1,  -- TIPO_ENVIO_DIRECTO
    1,  -- ESTADO_PROPUESTO
    p_id_almacen_origen,
    v_id_almacen_destino,
    COALESCE(p_descripcion, 'Envío de productos en consignación'),
    NOW(),
    p_id_usuario
  ) RETURNING id INTO v_id_envio;

  -- 5. Crear operación de extracción (PENDIENTE)
  INSERT INTO app_dat_operaciones (
    id_tienda,
    id_tipo_operacion,
    observaciones
  ) VALUES (
    v_id_tienda_consignadora,
    7,  -- Tipo: Extracción de consignación
    'Extracción por envío - ' || v_numero_envio
  ) RETURNING id INTO v_id_operacion_extraccion;

  -- Actualizar envío con id de operación
  UPDATE app_dat_consignacion_envio
  SET id_operacion_extraccion = v_id_operacion_extraccion
  WHERE id = v_id_envio;

  -- 6. Insertar productos en el envío
  FOR v_producto IN SELECT * FROM jsonb_array_elements(p_productos)
  LOOP
    -- Extraer datos del producto
    v_id_producto := (v_producto->>'id_producto')::BIGINT;
    v_id_inventario := (v_producto->>'id_inventario')::BIGINT;
    v_cantidad := (v_producto->>'cantidad')::NUMERIC;
    v_precio_costo_usd := (v_producto->>'precio_costo_usd')::NUMERIC;
    v_precio_costo_cup := COALESCE((v_producto->>'precio_venta')::NUMERIC, (v_producto->>'precio_costo_cup')::NUMERIC);
    v_precio_venta := COALESCE((v_producto->>'precio_venta')::NUMERIC, 0);
    v_tasa_cambio := COALESCE((v_producto->>'tasa_cambio')::NUMERIC, 440.0);

    -- ⭐ OBTENER DATOS ORIGINALES DEL INVENTARIO
    SELECT 
      ip.id_presentacion,
      ip.id_variante,
      ip.id_ubicacion,
      ip.id
    INTO 
      v_id_presentacion_original,
      v_id_variante_original,
      v_id_ubicacion_original,
      v_id_inventario_original
    FROM app_dat_inventario_productos ip
    WHERE ip.id = v_id_inventario;

    -- Insertar producto con datos originales
    INSERT INTO app_dat_consignacion_envio_producto (
      id_envio,
      id_producto,
      id_inventario,
      cantidad_propuesta,
      precio_costo_usd,
      precio_costo_cup,
      tasa_cambio,
      estado_producto,
      -- ⭐ CAMPOS NUEVOS: DATOS ORIGINALES
      id_presentacion_original,
      id_variante_original,
      id_ubicacion_original,
      id_inventario_original
    ) VALUES (
      v_id_envio,
      v_id_producto,
      v_id_inventario,
      v_cantidad,
      v_precio_costo_usd,
      v_precio_costo_cup,
      v_tasa_cambio,
      1,  -- ESTADO_PROPUESTO
      -- ⭐ VALORES DE DATOS ORIGINALES
      v_id_presentacion_original,
      v_id_variante_original,
      v_id_ubicacion_original,
      v_id_inventario_original
    );
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
    'Envío creado por consignador'
  );

  RETURN QUERY SELECT v_id_envio, v_numero_envio, v_id_operacion_extraccion;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION crear_envio_consignacion IS 
  'Crea un envío de consignación guardando los datos originales del producto (presentación, variante, ubicación)';

-- ============================================================================
-- MENSAJE DE CONFIRMACIÓN
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '✅ RPC crear_envio_consignacion modificado correctamente';
  RAISE NOTICE '📋 Ahora guarda 4 campos adicionales:';
  RAISE NOTICE '   - id_presentacion_original';
  RAISE NOTICE '   - id_variante_original';
  RAISE NOTICE '   - id_ubicacion_original';
  RAISE NOTICE '   - id_inventario_original';
  RAISE NOTICE '';
  RAISE NOTICE '📝 PRÓXIMO PASO: Modificar función de precio promedio';
END $$;
