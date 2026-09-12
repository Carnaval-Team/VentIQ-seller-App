-- ============================================================================
-- 14_crear_envio_consignacion_v2.sql
-- RPC: public.crear_envio_consignacion_v2(
--        p_id_contrato, p_id_almacen_origen, p_id_almacen_destino,
--        p_id_usuario, p_productos,
--        p_descripcion DEFAULT NULL, p_id_operacion_extraccion DEFAULT NULL)
--
-- PROPÓSITO:
--   Crea un envío de consignación con la MISMA lógica que
--   public.crear_envio_consignacion, PERO además persiste:
--     * tasa_cambio : la tasa vigente al momento de la creación (viene del JSON)
--   manteniendo precio_costo_usd / precio_costo_cup como el COSTO REAL que
--   ya manda el Dart (precio_promedio de la presentación, no el precio de venta).
--
-- CAMBIOS vs. la función original (NO se modifica esa — contrato vivo en prod):
--   + INSERT a app_dat_consignacion_envio_producto incluye la columna
--     tasa_cambio (tomada de v_producto->>'tasa_cambio').
--   + SECURITY DEFINER + SET search_path = public (convención del repo).
--   + PERFORM public.check_user_has_access_to_tienda(id_tienda_consignadora):
--     el usuario que crea el envío debe tener acceso a la tienda origen.
--   + Idempotente: CREATE OR REPLACE.
--
-- NOTAS:
--   * No se toca crear_envio_consignacion (los envíos ya creados no se tocan).
--   * El Dart migrará a llamar a crear_envio_consignacion_v2 (paso aparte).
--   * La excepción de acceso se captura en el handler WHEN OTHERS y se
--     devuelve como success=false con el mensaje (misma semántica que la original).
-- ============================================================================

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
  v_id_producto_destino BIGINT;
  v_cantidad NUMERIC;
  v_precio_costo_cup NUMERIC;
  v_tasa_cambio NUMERIC;          -- ⭐ NUEVO
  v_id_inventario BIGINT;
  -- Datos originales (para devoluciones)
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

  -- ⭐ SEGURIDAD: el usuario debe tener acceso a la tienda consignadora (origen)
  PERFORM public.check_user_has_access_to_tienda(v_id_tienda_origen);

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

    INSERT INTO app_dat_estado_operacion (id_operacion, estado, comentario)
    VALUES (v_id_operacion_extraccion, 1,
            'Operación de extracción creada para envío de consignación - Pendiente de completar');
  END IF;

  -- 3. La operación de RECEPCIÓN se crea después al confirmar la recepción
  v_id_operacion_recepcion := NULL;

  -- 4. Generar número de envío
  v_numero_envio := 'ENV-' || TO_CHAR(CURRENT_TIMESTAMP, 'YYYYMMDD')
                   || '-' || LPAD(nextval('app_dat_consignacion_envio_id_seq')::TEXT, 6, '0');

  -- 5. Crear ENVÍO de consignación PRIMERO
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
    v_id_inventario        := (v_producto->>'id_inventario')::BIGINT;
    v_cantidad             := (v_producto->>'cantidad')::NUMERIC;
    v_precio_costo_cup     := (v_producto->>'precio_costo_cup')::NUMERIC;
    v_tasa_cambio          := (v_producto->>'tasa_cambio')::NUMERIC;   -- ⭐ NUEVO

    -- Obtener datos originales del inventario
    SELECT ip.id_presentacion, ip.id_variante, ip.id_ubicacion
    INTO v_id_presentacion_original, v_id_variante_original, v_id_ubicacion_original
    FROM app_dat_inventario_productos ip
    WHERE ip.id = v_id_inventario;

    RAISE NOTICE
      'Insertando producto: id_envio=%, id_inventario=%, id_producto=%, cantidad=%, presentacion=%, variante=%, ubicacion=%, tasa=%',
      v_id_envio, v_id_inventario, v_id_producto_original, v_cantidad,
      v_id_presentacion_original, v_id_variante_original, v_id_ubicacion_original,
      v_tasa_cambio;

    -- Insertar producto del envío.
    -- precio_costo_usd / precio_costo_cup = COSTO REAL (ya lo manda el Dart).
    -- ⭐ tasa_cambio persistida para poder recalcular USD si la columna quedó
    --    truncada (numeric(20,2)) o nula.
    INSERT INTO app_dat_consignacion_envio_producto (
      id_envio,
      id_inventario,
      id_producto,
      cantidad_propuesta,
      precio_costo_cup,
      precio_costo_usd,
      tasa_cambio,                       -- ⭐ NUEVO
      estado_producto,
      created_at,
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
      v_tasa_cambio,                     -- ⭐ NUEVO
      1,
      CURRENT_TIMESTAMP,
      v_id_presentacion_original,
      v_id_variante_original,
      v_id_ubicacion_original,
      v_id_inventario
    );

    -- Los productos de la extracción se registran cuando el usuario
    -- COMPLETE manualmente la operación de extracción.
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
$function$;

-- ============================================================================
-- VERIFICACIONES (ejecutar después de aplicar)
-- ============================================================================

-- V1) La función existe, es SECURITY DEFINER y tiene search_path=public
-- SELECT p.proname, p.prosecdef, p.proconfig
-- FROM pg_proc p
-- JOIN pg_namespace n ON n.oid = p.pronamespace
-- WHERE n.nspname = 'public'
--   AND p.proname = 'crear_envio_consignacion_v2';

-- V2) El cuerpo incluye la columna tasa_cambio en el INSERT
-- SELECT (pg_get_functiondef(oid) LIKE '%tasa_cambio%') AS tiene_tasa,
--        (pg_get_functiondef(oid) LIKE '%check_user_has_access_to_tienda%') AS tiene_check
-- FROM pg_proc WHERE proname = 'crear_envio_consignacion_v2';

-- V3) La función original NO fue tocada (sigue sin tasa_cambio en el INSERT)
-- SELECT (pg_get_functiondef(oid) LIKE '%tasa_cambio%') AS original_tiene_tasa
-- FROM pg_proc WHERE proname = 'crear_envio_consignacion';
