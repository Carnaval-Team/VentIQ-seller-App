-- ============================================================================
-- FUNCIÓN: fn_registrar_recepcion_con_inventario
-- Versión mejorada de fn_insertar_recepcion_completa_with_currency que además
-- registra el movimiento de inventario en app_dat_inventario_productos por
-- cada producto recibido.
--
-- Cambios respecto a la versión anterior:
--   1. Registra movimiento en app_dat_inventario_productos por cada producto
--      (cantidad_inicial = último saldo, cantidad_final = saldo + cantidad recibida)
--   2. Captura el id de cada app_dat_recepcion_productos para vincularlo al inventario
--   3. Validaciones retornan JSON de error en lugar de RAISE EXCEPTION
--   4. GET STACKED DIAGNOSTICS para capturar contexto completo en excepciones
--   5. SELECT id_tipo_operacion corregido (antes SELECT 1 → tipo siempre 1)
--   6. Campo 'etapa' en errores indica exactamente dónde falló
--   7. Campo 'id_operacion_parcial' informa si quedó registro huérfano
-- ============================================================================

DROP FUNCTION IF EXISTS public.fn_registrar_recepcion_con_inventario(
  TEXT, BIGINT, NUMERIC, INTEGER, TEXT, JSONB, TEXT, UUID, TEXT
);

CREATE OR REPLACE FUNCTION public.fn_registrar_recepcion_con_inventario(
  p_entregado_por    TEXT,
  p_id_tienda        BIGINT,
  p_monto_total      NUMERIC  DEFAULT NULL,
  p_motivo           INTEGER  DEFAULT NULL,
  p_observaciones    TEXT     DEFAULT NULL,
  p_productos        JSONB    DEFAULT '[]'::JSONB,
  p_recibido_por     TEXT     DEFAULT NULL,
  p_uuid             UUID     DEFAULT NULL,
  p_moneda_factura   TEXT     DEFAULT 'USD'
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_id_operacion          BIGINT;
  v_id_tipo_operacion     BIGINT;
  v_producto_record       JSONB;
  v_cantidad_total        NUMERIC := 0;
  v_tienda_exists         BOOLEAN;
  v_moneda_factura        TEXT;
  -- Por producto
  v_id_recepcion_producto BIGINT;   -- id de app_dat_recepcion_productos
  v_id_producto           BIGINT;
  v_id_variante           BIGINT;
  v_id_opcion_variante    BIGINT;
  v_id_ubicacion          BIGINT;
  v_id_presentacion       BIGINT;
  v_id_proveedor          BIGINT;
  v_cantidad              NUMERIC;
  v_precio_unitario       NUMERIC;
  v_cantidad_inicial      NUMERIC;
  v_cantidad_final        NUMERIC;
  -- Captura de errores
  v_err_message           TEXT;
  v_err_detail            TEXT;
  v_err_hint              TEXT;
  v_err_context           TEXT;
BEGIN

  -- ── Validación: tienda existe ────────────────────────────────────────────
  SELECT EXISTS(SELECT 1 FROM app_dat_tienda WHERE id = p_id_tienda)
  INTO v_tienda_exists;

  IF NOT v_tienda_exists THEN
    RETURN jsonb_build_object(
      'status',   'error',
      'message',  format('La tienda con ID %s no existe', p_id_tienda),
      'sqlstate', 'V0001',
      'etapa',    'validacion_tienda'
    );
  END IF;

  -- ── Validación: al menos un producto ────────────────────────────────────
  IF p_productos IS NULL OR jsonb_array_length(p_productos) = 0 THEN
    RETURN jsonb_build_object(
      'status',   'error',
      'message',  'Debe incluir al menos un producto',
      'sqlstate', 'V0002',
      'etapa',    'validacion_productos'
    );
  END IF;

  -- ── Validación: moneda ───────────────────────────────────────────────────
  v_moneda_factura := COALESCE(NULLIF(TRIM(p_moneda_factura), ''), 'USD');

  IF v_moneda_factura NOT IN ('USD', 'EUR', 'CUP') THEN
    RETURN jsonb_build_object(
      'status',   'error',
      'message',  format('Moneda no válida: "%s". Use USD, EUR o CUP', v_moneda_factura),
      'sqlstate', 'V0003',
      'etapa',    'validacion_moneda'
    );
  END IF;

  -- ── Validación: motivo → tipo de operación ───────────────────────────────
  SELECT id_tipo_operacion
  INTO v_id_tipo_operacion
  FROM app_nom_motivo_recepcion
  WHERE id = p_motivo::BIGINT;

  IF v_id_tipo_operacion IS NULL THEN
    RETURN jsonb_build_object(
      'status',   'error',
      'message',  format('No se encontró tipo de operación para el motivo %s', p_motivo),
      'sqlstate', 'V0004',
      'etapa',    'validacion_motivo'
    );
  END IF;

  -- ── 1. Operación principal ───────────────────────────────────────────────
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

  -- ── 2. Detalles de recepción ─────────────────────────────────────────────
  INSERT INTO app_dat_operacion_recepcion (
    id_operacion,
    entregado_por,
    recibido_por,
    monto_total,
    observaciones,
    motivo,
    created_at,
    moneda_factura
  ) VALUES (
    v_id_operacion,
    p_entregado_por,
    p_recibido_por,
    p_monto_total,
    p_observaciones,
    p_motivo,
    NOW(),
    v_moneda_factura
  );

  -- ── 3. Productos + movimiento de inventario ──────────────────────────────
  FOR v_producto_record IN SELECT * FROM jsonb_array_elements(p_productos)
  LOOP

    -- Validar campos mínimos del producto
    IF v_producto_record->>'id_producto' IS NULL
    OR v_producto_record->>'cantidad'    IS NULL THEN
      RETURN jsonb_build_object(
        'status',               'error',
        'message',              'Cada producto debe tener id_producto y cantidad',
        'sqlstate',             'V0005',
        'etapa',                'validacion_producto_item',
        'producto_recibido',    v_producto_record,
        'id_operacion_parcial', v_id_operacion
      );
    END IF;

    -- Extraer campos del JSON a variables locales para reutilizar
    v_id_producto        := (v_producto_record->>'id_producto')::BIGINT;
    v_id_variante        := NULLIF(v_producto_record->>'id_variante',        '')::BIGINT;
    v_id_opcion_variante := NULLIF(v_producto_record->>'id_opcion_variante', '')::BIGINT;
    v_id_proveedor       := NULLIF(v_producto_record->>'id_proveedor',       '')::BIGINT;
    v_id_ubicacion       := NULLIF(v_producto_record->>'id_ubicacion',       '')::BIGINT;
    v_id_presentacion    := NULLIF(v_producto_record->>'id_presentacion',    '')::BIGINT;
    v_cantidad           := (v_producto_record->>'cantidad')::NUMERIC;
    v_precio_unitario    := NULLIF(v_producto_record->>'precio_unitario',    '')::NUMERIC;

    -- 3a. Insertar en app_dat_recepcion_productos y capturar su id
    INSERT INTO app_dat_recepcion_productos (
      id_operacion,
      id_producto,
      id_variante,
      id_opcion_variante,
      id_proveedor,
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
      v_id_proveedor,
      v_id_ubicacion,
      v_id_presentacion,
      v_cantidad,
      v_precio_unitario,
      v_producto_record->>'sku_producto',
      v_producto_record->>'sku_ubicacion',
      NOW()
    ) RETURNING id INTO v_id_recepcion_producto;

    -- 3b. Obtener saldo actual del inventario para este producto/presentación/ubicación
    --     Igual que fn_contabilizar_operacion: último cantidad_final DESC LIMIT 1
    SELECT COALESCE(
      (
        SELECT cantidad_final
        FROM app_dat_inventario_productos
        WHERE id_producto = v_id_producto
          AND (id_variante          IS NOT DISTINCT FROM v_id_variante)
          AND (id_opcion_variante   IS NOT DISTINCT FROM v_id_opcion_variante)
          AND (id_ubicacion         IS NOT DISTINCT FROM v_id_ubicacion)
          AND (id_presentacion      IS NOT DISTINCT FROM v_id_presentacion)
        ORDER BY created_at DESC
        LIMIT 1
      ), 0
    ) INTO v_cantidad_inicial;

    v_cantidad_final := v_cantidad_inicial + v_cantidad;

    -- 3c. Registrar movimiento de inventario (origen_cambio = 1 → recepción)
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
      origen_cambio,
      id_recepcion,
      id_proveedor,
      created_at
    ) VALUES (
      v_id_producto,
      v_id_variante,
      v_id_opcion_variante,
      v_id_ubicacion,
      v_id_presentacion,
      v_cantidad_inicial,
      v_cantidad_final,
      v_producto_record->>'sku_producto',
      v_producto_record->>'sku_ubicacion',
      1,                         -- 1 = recepción
      v_id_recepcion_producto,   -- FK al producto de esta recepción
      v_id_proveedor,
      NOW()
    );

    -- Acumular monto total
    v_cantidad_total := v_cantidad_total + (v_cantidad * COALESCE(v_precio_unitario, 0));

  END LOOP;

  -- ── 4. Estado inicial (1 = Pendiente) ───────────────────────────────────
  INSERT INTO app_dat_estado_operacion (
    id_operacion,
    estado,
    uuid,
    created_at
  ) VALUES (
    v_id_operacion,
    1,
    p_uuid,
    NOW()
  );

  -- ── 5. Actualizar monto total si no se proporcionó ───────────────────────
  IF p_monto_total IS NULL THEN
    UPDATE app_dat_operacion_recepcion
    SET monto_total = v_cantidad_total
    WHERE id_operacion = v_id_operacion;
  END IF;

  -- ── Respuesta exitosa ────────────────────────────────────────────────────
  RETURN jsonb_build_object(
    'status',           'success',
    'id_operacion',     v_id_operacion,
    'total_productos',  jsonb_array_length(p_productos),
    'monto_total',      COALESCE(p_monto_total, v_cantidad_total),
    'moneda_utilizada', v_moneda_factura,
    'mensaje',          'Recepción registrada correctamente con movimientos de inventario'
  );

EXCEPTION
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
      v_err_message = MESSAGE_TEXT,
      v_err_detail  = PG_EXCEPTION_DETAIL,
      v_err_hint    = PG_EXCEPTION_HINT,
      v_err_context = PG_EXCEPTION_CONTEXT;

    RETURN jsonb_build_object(
      'status',               'error',
      'message',              v_err_message,
      'detail',               COALESCE(v_err_detail,  ''),
      'hint',                 COALESCE(v_err_hint,    ''),
      'context',              COALESCE(v_err_context, ''),
      'sqlstate',             SQLSTATE,
      'etapa',                'excepcion_no_controlada',
      'id_operacion_parcial', v_id_operacion
    );
END;
$$;
