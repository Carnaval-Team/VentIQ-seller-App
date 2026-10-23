-- ============================================================================
-- 02 · Lotes / vencimientos — cablear recepción + contabilización
-- ============================================================================
-- Plan: docs/PLAN_VENCIMIENTOS_LOTES.md  (Fase 1)
-- Prerrequisito: 01_lotes_vencimiento_schema.sql aplicado en newa.
-- Aplicar SOLO en newa hasta cerrar el proyecto.
--
-- Cambios:
--   A) fn_registrar_recepcion_con_inventario
--      - Lee codigo_lote + fecha_vencimiento del jsonb de cada producto
--      - Si es_por_lotes → obligatorio; llama fn_obtener_o_crear_lote
--      - Guarda id_lote en app_dat_recepcion_productos
--   B) fn_contabilizar_linea_recepcion_inventario
--      - Copia id_lote al snapshot de inventario
--      - El saldo previo se lee particionado por id_lote
--        (IS NOT DISTINCT FROM) para no mezclar lotes
-- ============================================================================

-- ----------------------------------------------------------------------------
-- A) Registrar recepción (pendiente) con id_lote
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_registrar_recepcion_con_inventario(
  p_entregado_por text,
  p_id_tienda bigint,
  p_monto_total numeric DEFAULT NULL::numeric,
  p_motivo integer DEFAULT NULL::integer,
  p_observaciones text DEFAULT NULL::text,
  p_productos jsonb DEFAULT '[]'::jsonb,
  p_recibido_por text DEFAULT NULL::text,
  p_uuid uuid DEFAULT NULL::uuid,
  p_moneda_factura text DEFAULT 'USD'::text
)
RETURNS jsonb
LANGUAGE plpgsql
AS $function$
DECLARE
  v_id_operacion          BIGINT;
  v_id_tipo_operacion     BIGINT;
  v_producto_record       JSONB;
  v_cantidad_total        NUMERIC := 0;
  v_tienda_exists         BOOLEAN;
  v_moneda_factura        TEXT;
  v_id_recepcion_producto BIGINT;
  v_id_producto           BIGINT;
  v_id_variante           BIGINT;
  v_id_opcion_variante    BIGINT;
  v_id_ubicacion          BIGINT;
  v_id_presentacion       BIGINT;
  v_id_proveedor          BIGINT;
  v_cantidad              NUMERIC;
  v_precio_unitario       NUMERIC;
  v_codigo_lote           TEXT;
  v_fecha_vencimiento     DATE;
  v_fecha_fabricacion     DATE;
  v_es_por_lotes          BOOLEAN;
  v_id_lote               BIGINT;
  v_lote_result           JSONB;
  v_err_message           TEXT;
  v_err_detail            TEXT;
  v_err_hint              TEXT;
  v_err_context           TEXT;
BEGIN
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

  IF p_productos IS NULL OR jsonb_array_length(p_productos) = 0 THEN
    RETURN jsonb_build_object(
      'status',   'error',
      'message',  'Debe incluir al menos un producto',
      'sqlstate', 'V0002',
      'etapa',    'validacion_productos'
    );
  END IF;

  v_moneda_factura := COALESCE(NULLIF(TRIM(p_moneda_factura), ''), 'USD');
  IF v_moneda_factura NOT IN ('USD', 'EUR', 'CUP') THEN
    RETURN jsonb_build_object(
      'status',   'error',
      'message',  format('Moneda no válida: "%s". Use USD, EUR o CUP', v_moneda_factura),
      'sqlstate', 'V0003',
      'etapa',    'validacion_moneda'
    );
  END IF;

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

  INSERT INTO app_dat_operaciones (
    id_tipo_operacion, uuid, id_tienda, observaciones, created_at
  ) VALUES (
    v_id_tipo_operacion, p_uuid, p_id_tienda, p_observaciones, NOW()
  ) RETURNING id INTO v_id_operacion;

  INSERT INTO app_dat_operacion_recepcion (
    id_operacion, entregado_por, recibido_por, monto_total,
    observaciones, motivo, created_at, moneda_factura
  ) VALUES (
    v_id_operacion, p_entregado_por, p_recibido_por, p_monto_total,
    p_observaciones, p_motivo, NOW(), v_moneda_factura
  );

  FOR v_producto_record IN SELECT * FROM jsonb_array_elements(p_productos)
  LOOP
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

    v_id_producto        := (v_producto_record->>'id_producto')::BIGINT;
    v_id_variante        := NULLIF(v_producto_record->>'id_variante',        '')::BIGINT;
    v_id_opcion_variante := NULLIF(v_producto_record->>'id_opcion_variante', '')::BIGINT;
    v_id_proveedor       := NULLIF(v_producto_record->>'id_proveedor',       '')::BIGINT;
    v_id_ubicacion       := NULLIF(v_producto_record->>'id_ubicacion',       '')::BIGINT;
    v_id_presentacion    := NULLIF(v_producto_record->>'id_presentacion',    '')::BIGINT;
    v_cantidad           := (v_producto_record->>'cantidad')::NUMERIC;
    v_precio_unitario    := NULLIF(v_producto_record->>'precio_unitario',    '')::NUMERIC;

    -- Lote (aliases: codigo_lote | lote | nro_lote)
    v_codigo_lote := NULLIF(TRIM(COALESCE(
      v_producto_record->>'codigo_lote',
      v_producto_record->>'lote',
      v_producto_record->>'nro_lote',
      ''
    )), '');
    v_fecha_vencimiento := NULLIF(COALESCE(
      v_producto_record->>'fecha_vencimiento',
      v_producto_record->>'fecha_vencimiento_lote',
      ''
    ), '')::DATE;
    v_fecha_fabricacion := NULLIF(COALESCE(
      v_producto_record->>'fecha_fabricacion',
      ''
    ), '')::DATE;

    SELECT COALESCE(p.es_por_lotes, false)
      INTO v_es_por_lotes
      FROM app_dat_producto p
     WHERE p.id = v_id_producto;

    v_id_lote := NULL;

    IF COALESCE(v_es_por_lotes, false) THEN
      IF v_codigo_lote IS NULL OR v_fecha_vencimiento IS NULL THEN
        RETURN jsonb_build_object(
          'status',               'error',
          'message',              format(
            'El producto %s es por lotes: codigo_lote y fecha_vencimiento son obligatorios',
            v_id_producto
          ),
          'sqlstate',             'V0006',
          'etapa',                'validacion_lote',
          'producto_recibido',    v_producto_record,
          'id_operacion_parcial', v_id_operacion
        );
      END IF;

      v_lote_result := public.fn_obtener_o_crear_lote(
        p_id_tienda         := p_id_tienda,
        p_id_producto       := v_id_producto,
        p_codigo            := v_codigo_lote,
        p_fecha_vencimiento := v_fecha_vencimiento,
        p_fecha_fabricacion := v_fecha_fabricacion,
        p_observaciones     := NULL
      );

      IF COALESCE(v_lote_result->>'status', '') <> 'success' THEN
        RETURN jsonb_build_object(
          'status',               'error',
          'message',              COALESCE(
            v_lote_result->>'message',
            'No se pudo obtener/crear el lote'
          ),
          'sqlstate',             'V0007',
          'etapa',                'crear_lote',
          'lote_result',          v_lote_result,
          'producto_recibido',    v_producto_record,
          'id_operacion_parcial', v_id_operacion
        );
      END IF;

      v_id_lote := (v_lote_result->>'id_lote')::BIGINT;
    END IF;

    INSERT INTO app_dat_recepcion_productos (
      id_operacion, id_producto, id_variante, id_opcion_variante,
      id_proveedor, id_ubicacion, id_presentacion, cantidad,
      precio_unitario, sku_producto, sku_ubicacion, id_lote, created_at
    ) VALUES (
      v_id_operacion, v_id_producto, v_id_variante, v_id_opcion_variante,
      v_id_proveedor, v_id_ubicacion, v_id_presentacion, v_cantidad,
      v_precio_unitario,
      v_producto_record->>'sku_producto',
      v_producto_record->>'sku_ubicacion',
      v_id_lote,
      NOW()
    ) RETURNING id INTO v_id_recepcion_producto;

    v_cantidad_total := v_cantidad_total + (v_cantidad * COALESCE(v_precio_unitario, 0));
  END LOOP;

  INSERT INTO app_dat_estado_operacion (id_operacion, estado, uuid, created_at)
  VALUES (v_id_operacion, 1, p_uuid, NOW());

  IF p_monto_total IS NULL THEN
    UPDATE app_dat_operacion_recepcion
    SET monto_total = v_cantidad_total
    WHERE id_operacion = v_id_operacion;
  END IF;

  RETURN jsonb_build_object(
    'status',           'success',
    'id_operacion',     v_id_operacion,
    'total_productos',  jsonb_array_length(p_productos),
    'monto_total',      COALESCE(p_monto_total, v_cantidad_total),
    'moneda_utilizada', v_moneda_factura,
    'mensaje',          'Recepción pendiente registrada. El inventario se aplicará al completar.'
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
      'id_operacion_parcial', v_id_operacion
    );
END;
$function$;


-- ----------------------------------------------------------------------------
-- B) Contabilizar línea → inventario con id_lote y saldo por lote
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_contabilizar_linea_recepcion_inventario(
  p_id_recepcion_producto bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_rp RECORD;
  v_stock_actual numeric;
  v_id_movimiento bigint;
  v_id_presentacion bigint;
BEGIN
  SELECT
    rp.id,
    rp.id_operacion,
    rp.id_producto,
    rp.id_variante,
    rp.id_opcion_variante,
    rp.id_ubicacion,
    rp.id_presentacion,
    rp.cantidad,
    rp.sku_producto,
    rp.sku_ubicacion,
    rp.id_proveedor,
    rp.id_lote,
    p.denominacion AS producto_nombre
  INTO v_rp
  FROM app_dat_recepcion_productos rp
  LEFT JOIN app_dat_producto p ON p.id = rp.id_producto
  WHERE rp.id = p_id_recepcion_producto;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'estado', 'ERROR',
      'id_recepcion_producto', p_id_recepcion_producto,
      'mensaje', 'Línea de recepción no encontrada'
    );
  END IF;

  IF EXISTS (
    SELECT 1
    FROM app_dat_inventario_productos inv
    WHERE inv.id_recepcion = p_id_recepcion_producto
  ) THEN
    RETURN jsonb_build_object(
      'estado', 'OMITIDO',
      'id_recepcion_producto', p_id_recepcion_producto,
      'id_producto', v_rp.id_producto,
      'producto_nombre', v_rp.producto_nombre,
      'mensaje', 'Ya contabilizado en inventario'
    );
  END IF;

  IF v_rp.id_producto IS NULL THEN
    RETURN jsonb_build_object(
      'estado', 'ERROR',
      'id_recepcion_producto', p_id_recepcion_producto,
      'mensaje', 'La línea no tiene producto asociado (id_producto nulo)'
    );
  END IF;

  IF v_rp.id_ubicacion IS NULL THEN
    RETURN jsonb_build_object(
      'estado', 'ERROR',
      'id_recepcion_producto', p_id_recepcion_producto,
      'id_producto', v_rp.id_producto,
      'producto_nombre', v_rp.producto_nombre,
      'mensaje', 'La línea no tiene ubicación asignada'
    );
  END IF;

  v_id_presentacion := v_rp.id_presentacion;

  IF v_id_presentacion IS NULL THEN
    SELECT pp.id
    INTO v_id_presentacion
    FROM app_dat_producto_presentacion pp
    WHERE pp.id_producto = v_rp.id_producto
      AND pp.es_base = true
    LIMIT 1;

    IF v_id_presentacion IS NULL THEN
      SELECT pp.id
      INTO v_id_presentacion
      FROM app_dat_producto_presentacion pp
      WHERE pp.id_producto = v_rp.id_producto
      LIMIT 1;
    END IF;

    IF v_id_presentacion IS NOT NULL THEN
      UPDATE app_dat_recepcion_productos
      SET id_presentacion = v_id_presentacion
      WHERE id = p_id_recepcion_producto;
    ELSE
      RETURN jsonb_build_object(
        'estado', 'ERROR',
        'id_recepcion_producto', p_id_recepcion_producto,
        'id_producto', v_rp.id_producto,
        'producto_nombre', v_rp.producto_nombre,
        'mensaje', 'El producto no tiene presentaciones en catálogo'
      );
    END IF;
  END IF;

  -- Saldo previo de ESA presentación/ubicación/LOTE (null = sin lote, como antes)
  SELECT COALESCE((
    SELECT ip.cantidad_final::numeric
    FROM app_dat_inventario_productos ip
    WHERE ip.id_producto = v_rp.id_producto
      AND (ip.id_variante IS NOT DISTINCT FROM v_rp.id_variante)
      AND (ip.id_opcion_variante IS NOT DISTINCT FROM v_rp.id_opcion_variante)
      AND (ip.id_presentacion IS NOT DISTINCT FROM v_id_presentacion)
      AND (ip.id_ubicacion IS NOT DISTINCT FROM v_rp.id_ubicacion)
      AND (ip.id_lote IS NOT DISTINCT FROM v_rp.id_lote)
      AND (ip.id_recepcion IS DISTINCT FROM p_id_recepcion_producto)
    ORDER BY ip.id DESC
    LIMIT 1
  ), 0) INTO v_stock_actual;

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
    id_lote,
    created_at
  ) VALUES (
    v_rp.id_producto,
    v_rp.id_variante,
    v_rp.id_opcion_variante,
    v_rp.id_ubicacion,
    v_id_presentacion,
    v_stock_actual,
    v_stock_actual + v_rp.cantidad::numeric,
    v_rp.sku_producto,
    v_rp.sku_ubicacion,
    1,
    p_id_recepcion_producto,
    v_rp.id_proveedor,
    v_rp.id_lote,
    NOW()
  )
  RETURNING id INTO v_id_movimiento;

  RETURN jsonb_build_object(
    'estado', 'OK',
    'id_recepcion_producto', p_id_recepcion_producto,
    'id_producto', v_rp.id_producto,
    'producto_nombre', v_rp.producto_nombre,
    'cantidad_recepcion', v_rp.cantidad,
    'cantidad_inicial', v_stock_actual,
    'cantidad_final', v_stock_actual + v_rp.cantidad::numeric,
    'id_movimiento', v_id_movimiento,
    'id_lote', v_rp.id_lote,
    'mensaje', 'Movimiento de inventario registrado'
  );
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'estado', 'ERROR',
      'id_recepcion_producto', p_id_recepcion_producto,
      'id_producto', v_rp.id_producto,
      'producto_nombre', v_rp.producto_nombre,
      'mensaje', SQLERRM
    );
END;
$function$;
