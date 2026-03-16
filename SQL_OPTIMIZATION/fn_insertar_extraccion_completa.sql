-- ============================================================================
-- FUNCIÓN: fn_crear_extraccion_con_movimiento
-- DESCRIPCIÓN: Crea una operación de extracción y registra inmediatamente
--              el movimiento de inventario en app_dat_inventario_productos,
--              reduciendo la cantidad disponible por cada producto extraído.
-- RENOMBRADA DESDE: fn_insertar_extraccion_completa
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_crear_extraccion_con_movimiento(
  p_autorizado_por      TEXT,
  p_estado_inicial      SMALLINT,
  p_id_motivo_operacion BIGINT,
  p_id_tienda           BIGINT,
  p_observaciones       TEXT,
  p_productos           JSONB,
  p_uuid                UUID
) RETURNS JSONB AS $$
DECLARE
  v_id_operacion        BIGINT;
  v_id_extraccion_prod  BIGINT;
  v_id_tipo_operacion   BIGINT;
  v_producto_record     JSONB;
  v_cantidad_total      NUMERIC := 0;
  v_result              JSONB;
  v_tienda_exists       BOOLEAN;
  v_motivo_exists       BOOLEAN;
  -- Variables para el movimiento de inventario
  v_id_producto         BIGINT;
  v_id_variante         BIGINT;
  v_id_opcion_variante  BIGINT;
  v_id_ubicacion        BIGINT;
  v_id_presentacion     BIGINT;
  v_cantidad            NUMERIC;
  v_precio_unitario     NUMERIC;
  v_sku_producto        TEXT;
  v_sku_ubicacion       TEXT;
  v_cantidad_inicial    NUMERIC;
  v_cantidad_final      NUMERIC;
BEGIN
  -- ── Validaciones ──────────────────────────────────────────────────────────
  SELECT EXISTS(SELECT 1 FROM app_dat_tienda WHERE id = p_id_tienda)
  INTO v_tienda_exists;

  SELECT EXISTS(SELECT 1 FROM app_nom_motivo_extraccion WHERE id = p_id_motivo_operacion)
  INTO v_motivo_exists;

  IF NOT v_tienda_exists THEN
    RAISE EXCEPTION 'La tienda con ID % no existe', p_id_tienda;
  END IF;

  IF NOT v_motivo_exists THEN
    RAISE EXCEPTION 'El motivo de extracción con ID % no existe', p_id_motivo_operacion;
  END IF;

  IF jsonb_array_length(p_productos) = 0 THEN
    RAISE EXCEPTION 'Debe incluir al menos un producto';
  END IF;

  -- ── Obtener tipo de operación Extracción ───────────────────────────────────
  SELECT id INTO v_id_tipo_operacion
  FROM app_nom_tipo_operacion
  WHERE denominacion ILIKE '%extraccion%' OR denominacion ILIKE '%extracción%'
  LIMIT 1;

  IF v_id_tipo_operacion IS NULL THEN
    RAISE EXCEPTION 'No se encontró tipo de operación para extracción';
  END IF;

  -- ── 1. Operación principal ─────────────────────────────────────────────────
  INSERT INTO app_dat_operaciones (
    id_tipo_operacion,
    uuid,
    id_tienda,
    observaciones,
    created_at
  ) VALUES (
    v_id_tipo_operacion,
    p_uuid,
    p_id_tienda,
    p_observaciones,
    NOW()
  ) RETURNING id INTO v_id_operacion;

  -- ── 2. Detalle de extracción ───────────────────────────────────────────────
  INSERT INTO app_dat_operacion_extraccion (
    id_operacion,
    id_motivo_operacion,
    observaciones,
    autorizado_por,
    created_at
  ) VALUES (
    v_id_operacion,
    p_id_motivo_operacion,
    p_observaciones,
    p_autorizado_por,
    NOW()
  );

  -- ── 3. Productos + movimiento de inventario inmediato ─────────────────────
  FOR v_producto_record IN SELECT * FROM jsonb_array_elements(p_productos)
  LOOP
    IF v_producto_record->>'id_producto' IS NULL OR v_producto_record->>'cantidad' IS NULL THEN
      RAISE EXCEPTION 'Cada producto debe tener id_producto y cantidad';
    END IF;

    -- Extraer campos del JSON
    v_id_producto        := (v_producto_record->>'id_producto')::BIGINT;
    v_id_variante        := NULLIF(v_producto_record->>'id_variante', '')::BIGINT;
    v_id_opcion_variante := NULLIF(v_producto_record->>'id_opcion_variante', '')::BIGINT;
    v_id_ubicacion       := NULLIF(v_producto_record->>'id_ubicacion', '')::BIGINT;
    v_id_presentacion    := NULLIF(v_producto_record->>'id_presentacion', '')::BIGINT;
    v_cantidad           := (v_producto_record->>'cantidad')::NUMERIC;
    v_precio_unitario    := NULLIF(v_producto_record->>'precio_unitario', '')::NUMERIC;
    v_sku_producto       := v_producto_record->>'sku_producto';
    v_sku_ubicacion      := v_producto_record->>'sku_ubicacion';

    -- 3a. Registrar producto en la extracción
    INSERT INTO app_dat_extraccion_productos (
      id_operacion,
      id_producto,
      id_variante,
      id_opcion_variante,
      id_ubicacion,
      id_presentacion,
      cantidad,
      precio_unitario,
      sku_producto,
      sku_ubicacion,
      created_at
    ) VALUES (
      v_id_operacion,
      v_id_producto,
      v_id_variante,
      v_id_opcion_variante,
      v_id_ubicacion,
      v_id_presentacion,
      v_cantidad,
      v_precio_unitario,
      v_sku_producto,
      v_sku_ubicacion,
      NOW()
    ) RETURNING id INTO v_id_extraccion_prod;

    -- 3b. Obtener saldo actual del inventario para este producto/ubicación
    SELECT COALESCE(cantidad_final, 0)
    INTO v_cantidad_inicial
    FROM app_dat_inventario_productos
    WHERE id_producto = v_id_producto
      AND (id_variante           IS NOT DISTINCT FROM v_id_variante)
      AND (id_opcion_variante    IS NOT DISTINCT FROM v_id_opcion_variante)
      AND (id_ubicacion          IS NOT DISTINCT FROM v_id_ubicacion)
      AND (id_presentacion       IS NOT DISTINCT FROM v_id_presentacion)
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_cantidad_inicial IS NULL THEN
      v_cantidad_inicial := 0;
    END IF;

    -- 3c. Calcular nuevo saldo (extracción = resta)
    v_cantidad_final := v_cantidad_inicial - v_cantidad;

    -- 3d. Insertar movimiento en app_dat_inventario_productos
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
      origen_cambio,   -- 2 = extracción
      id_extraccion,
      created_at
    ) VALUES (
      v_id_producto,
      v_id_variante,
      v_id_opcion_variante,
      v_id_ubicacion,
      v_id_presentacion,
      v_cantidad_inicial,
      v_cantidad_final,
      v_sku_producto,
      v_sku_ubicacion,
      2,
      v_id_extraccion_prod,
      NOW()
    );

    -- Acumular total
    v_cantidad_total := v_cantidad_total + v_cantidad;
  END LOOP;

  -- ── 4. Estado inicial de la operación ─────────────────────────────────────
  INSERT INTO app_dat_estado_operacion (
    id_operacion,
    estado,
    uuid,
    created_at
  ) VALUES (
    v_id_operacion,
    p_estado_inicial,
    p_uuid,
    NOW()
  );

  -- ── Respuesta exitosa ──────────────────────────────────────────────────────
  v_result := jsonb_build_object(
    'status',          'success',
    'id_operacion',    v_id_operacion,
    'total_productos', jsonb_array_length(p_productos),
    'cantidad_total',  v_cantidad_total,
    'mensaje',         'Extracción registrada y movimientos de inventario aplicados'
  );

  RETURN v_result;

EXCEPTION
  WHEN OTHERS THEN
    v_result := jsonb_build_object(
      'status',    'error',
      'message',   'Error al registrar extracción: ' || SQLERRM,
      'sqlstate',  SQLSTATE
    );
    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- MENSAJE DE CONFIRMACIÓN
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '✅ Función fn_crear_extraccion_con_movimiento creada exitosamente';
  RAISE NOTICE '';
  RAISE NOTICE '📋 PARÁMETROS:';
  RAISE NOTICE '  1. p_autorizado_por      (TEXT)';
  RAISE NOTICE '  2. p_estado_inicial      (SMALLINT) - 1=Pendiente, 2=Completada';
  RAISE NOTICE '  3. p_id_motivo_operacion (BIGINT)';
  RAISE NOTICE '  4. p_id_tienda           (BIGINT)';
  RAISE NOTICE '  5. p_observaciones       (TEXT)';
  RAISE NOTICE '  6. p_productos           (JSONB)';
  RAISE NOTICE '  7. p_uuid                (UUID)';
  RAISE NOTICE '';
  RAISE NOTICE '🆕 CAMBIOS vs fn_insertar_extraccion_completa:';
  RAISE NOTICE '  - Registra movimiento en app_dat_inventario_productos por cada producto';
  RAISE NOTICE '  - Reduce cantidad_final inmediatamente al crear la extracción';
  RAISE NOTICE '  - origen_cambio = 2 (extracción), id_extraccion vinculado';
  RAISE NOTICE '';
  RAISE NOTICE '✅ LISTO PARA USAR';
END $$;