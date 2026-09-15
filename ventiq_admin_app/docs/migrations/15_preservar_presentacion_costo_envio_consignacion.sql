-- 15_preservar_presentacion_costo_envio_consignacion.sql
--
-- Conserva en el envío la presentación que eligió el usuario. El costo recibido
-- desde Flutter es el costo unitario de esa presentación, no el de una unidad
-- base y tampoco un precio de venta convertido.
--
-- No modifica envíos históricos.

CREATE OR REPLACE FUNCTION public.crear_envio_consignacion_v2(
  p_id_contrato BIGINT,
  p_id_almacen_origen BIGINT,
  p_id_almacen_destino BIGINT,
  p_id_usuario UUID,
  p_productos JSONB,
  p_descripcion TEXT DEFAULT NULL,
  p_id_operacion_extraccion BIGINT DEFAULT NULL
)
RETURNS TABLE (
  success BOOLEAN,
  id_envio BIGINT,
  numero_envio VARCHAR,
  id_operacion_extraccion BIGINT,
  id_operacion_recepcion BIGINT,
  mensaje VARCHAR
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
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
  v_cantidad NUMERIC;
  v_precio_costo_usd NUMERIC;
  v_precio_costo_cup NUMERIC;
  v_tasa_cambio NUMERIC;
  v_id_inventario BIGINT;
  v_id_presentacion_original BIGINT;
  v_id_variante_original BIGINT;
  v_id_ubicacion_original BIGINT;
BEGIN
  SELECT id, id_tienda_consignadora, id_tienda_consignataria
  INTO v_id_contrato_consignacion, v_id_tienda_origen, v_id_tienda_destino
  FROM app_dat_contrato_consignacion
  WHERE id = p_id_contrato;

  IF v_id_contrato_consignacion IS NULL THEN
    RETURN QUERY SELECT false::BOOLEAN, NULL::BIGINT, NULL::VARCHAR,
      NULL::BIGINT, NULL::BIGINT,
      'Contrato de consignación no encontrado'::VARCHAR;
    RETURN;
  END IF;

  PERFORM public.check_user_has_access_to_tienda(v_id_tienda_origen);

  IF p_id_operacion_extraccion IS NOT NULL THEN
    v_id_operacion_extraccion := p_id_operacion_extraccion;
  ELSE
    INSERT INTO app_dat_operaciones (
      id_tienda, id_tipo_operacion, uuid, observaciones, created_at
    ) VALUES (
      v_id_tienda_origen, 7, p_id_usuario,
      COALESCE(p_descripcion, 'Extracción para consignación'), CURRENT_TIMESTAMP
    ) RETURNING id INTO v_id_operacion_extraccion;

    IF v_id_operacion_extraccion IS NULL THEN
      RETURN QUERY SELECT false::BOOLEAN, NULL::BIGINT, NULL::VARCHAR,
        NULL::BIGINT, NULL::BIGINT,
        'Error creando operación de extracción'::VARCHAR;
      RETURN;
    END IF;

    INSERT INTO app_dat_estado_operacion (id_operacion, estado, comentario)
    VALUES (
      v_id_operacion_extraccion,
      1,
      'Operación de extracción creada para envío de consignación - Pendiente de completar'
    );
  END IF;

  v_id_operacion_recepcion := NULL;
  v_numero_envio := 'ENV-' || TO_CHAR(CURRENT_TIMESTAMP, 'YYYYMMDD') || '-'
    || LPAD(nextval('app_dat_consignacion_envio_id_seq')::TEXT, 6, '0');

  INSERT INTO app_dat_consignacion_envio (
    id_contrato_consignacion, id_operacion_extraccion, id_operacion_recepcion,
    numero_envio, estado_envio, fecha_propuesta, id_almacen_origen,
    id_almacen_destino, id_usuario_creador, estado, created_at, updated_at
  ) VALUES (
    v_id_contrato_consignacion, v_id_operacion_extraccion,
    v_id_operacion_recepcion, v_numero_envio, 1, CURRENT_TIMESTAMP,
    p_id_almacen_origen, p_id_almacen_destino, p_id_usuario, 1,
    CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
  ) RETURNING id INTO v_id_envio;

  FOR v_producto IN SELECT jsonb_array_elements(p_productos)
  LOOP
    v_id_producto_original := (v_producto->>'id_producto')::BIGINT;
    v_id_inventario := (v_producto->>'id_inventario')::BIGINT;
    v_cantidad := (v_producto->>'cantidad')::NUMERIC;
    v_precio_costo_usd := COALESCE((v_producto->>'precio_costo_usd')::NUMERIC, 0);
    v_precio_costo_cup := COALESCE(
      (v_producto->>'precio_costo_cup')::NUMERIC,
      v_precio_costo_usd * COALESCE((v_producto->>'tasa_cambio')::NUMERIC, 0)
    );
    v_tasa_cambio := COALESCE((v_producto->>'tasa_cambio')::NUMERIC, 0);

    IF v_precio_costo_usd <= 0 OR v_precio_costo_cup <= 0 THEN
      RAISE EXCEPTION
        'El producto % no tiene costo unitario válido para la presentación seleccionada',
        v_id_producto_original;
    END IF;

    SELECT ip.id_presentacion, ip.id_variante, ip.id_ubicacion
    INTO v_id_presentacion_original, v_id_variante_original, v_id_ubicacion_original
    FROM app_dat_inventario_productos ip
    WHERE ip.id = v_id_inventario;

    -- La presentación declarada por el flujo es la fuente de verdad. El
    -- inventario solo respalda líneas antiguas o clientes que no la envían.
    v_id_presentacion_original := COALESCE(
      (v_producto->>'id_presentacion')::BIGINT,
      v_id_presentacion_original
    );
    v_id_variante_original := COALESCE(
      (v_producto->>'id_variante')::BIGINT,
      v_id_variante_original
    );
    v_id_ubicacion_original := COALESCE(
      (v_producto->>'id_ubicacion')::BIGINT,
      v_id_ubicacion_original
    );

    INSERT INTO app_dat_consignacion_envio_producto (
      id_envio, id_inventario, id_producto, cantidad_propuesta,
      precio_costo_cup, precio_costo_usd, tasa_cambio, estado_producto,
      created_at, id_presentacion_original, id_variante_original,
      id_ubicacion_original, id_inventario_original
    ) VALUES (
      v_id_envio, v_id_inventario, v_id_producto_original, v_cantidad,
      v_precio_costo_cup, v_precio_costo_usd, v_tasa_cambio, 1,
      CURRENT_TIMESTAMP, v_id_presentacion_original, v_id_variante_original,
      v_id_ubicacion_original, v_id_inventario
    );
  END LOOP;

  RETURN QUERY SELECT true::BOOLEAN, v_id_envio::BIGINT, v_numero_envio::VARCHAR,
    v_id_operacion_extraccion::BIGINT, v_id_operacion_recepcion::BIGINT,
    'Envío creado exitosamente'::VARCHAR;
EXCEPTION WHEN OTHERS THEN
  RETURN QUERY SELECT false::BOOLEAN, NULL::BIGINT, NULL::VARCHAR,
    NULL::BIGINT, NULL::BIGINT, ('Error: ' || SQLERRM)::VARCHAR;
END;
$function$;
