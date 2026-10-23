-- ============================================================================
-- 09 · Asignar lote + fecha a stock sin lote (legacy)
-- ============================================================================
-- Productos es_por_lotes con saldo en id_lote NULL: gerente/supervisor
-- reclasifican (egreso NULL + ingreso al lote) sin cambiar el stock total.
-- Prerrequisito: 01–08 en newa. NO aplicar en main hasta cerrar el proyecto.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_asignar_lote_a_stock_sin_lote(
  p_id_producto        bigint,
  p_id_ubicacion       bigint,
  p_id_presentacion    bigint,
  p_codigo_lote        text,
  p_fecha_vencimiento  date,
  p_fecha_fabricacion  date DEFAULT NULL,
  p_id_variante        bigint DEFAULT NULL,
  p_id_opcion_variante bigint DEFAULT NULL,
  p_cantidad           numeric DEFAULT NULL,
  p_observaciones      text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid                uuid := auth.uid();
  v_id_tienda          bigint;
  v_es_por_lotes       boolean := false;
  v_saldo_sin_lote     numeric := 0;
  v_saldo_lote         numeric := 0;
  v_qty                numeric;
  v_codigo             text := NULLIF(trim(COALESCE(p_codigo_lote, '')), '');
  v_lote_result        jsonb;
  v_id_lote            bigint;
  v_id_operacion       bigint;
  v_id_control         bigint;
  v_id_tipo_operacion  bigint;
  v_obs                text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'Usuario no autenticado');
  END IF;

  IF p_id_producto IS NULL OR p_id_ubicacion IS NULL OR p_id_presentacion IS NULL THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'id_producto, id_ubicacion e id_presentacion son obligatorios'
    );
  END IF;

  IF v_codigo IS NULL THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'codigo de lote vacío');
  END IF;

  IF p_fecha_vencimiento IS NULL THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'fecha_vencimiento es obligatoria');
  END IF;

  SELECT p.id_tienda, COALESCE(p.es_por_lotes, false)
  INTO v_id_tienda, v_es_por_lotes
  FROM app_dat_producto p
  WHERE p.id = p_id_producto
    AND p.deleted_at IS NULL;

  IF v_id_tienda IS NULL THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', format('Producto %s no encontrado', p_id_producto)
    );
  END IF;

  IF NOT v_es_por_lotes THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'El producto no está marcado como por lotes'
    );
  END IF;

  -- Solo gerente o supervisor de esa tienda
  IF NOT EXISTS (
        SELECT 1 FROM app_dat_gerente g
        WHERE g.uuid = v_uid AND g.id_tienda = v_id_tienda
      )
     AND NOT EXISTS (
        SELECT 1 FROM app_dat_supervisor s
        WHERE s.uuid = v_uid AND s.id_tienda = v_id_tienda
      ) THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'Solo gerente o supervisor pueden asignar lote a stock sin etiquetar'
    );
  END IF;

  BEGIN
    PERFORM public.fn_validar_id_presentacion(p_id_producto, p_id_presentacion);
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('status', 'error', 'message', SQLERRM);
  END;

  -- Saldo vigente del bucket sin lote
  SELECT COALESCE((
    SELECT i.cantidad_final
    FROM app_dat_inventario_productos i
    WHERE i.id_producto = p_id_producto
      AND i.id_ubicacion IS NOT DISTINCT FROM p_id_ubicacion
      AND i.id_presentacion IS NOT DISTINCT FROM p_id_presentacion
      AND i.id_variante IS NOT DISTINCT FROM p_id_variante
      AND i.id_opcion_variante IS NOT DISTINCT FROM p_id_opcion_variante
      AND i.id_lote IS NULL
    ORDER BY i.id DESC
    LIMIT 1
  ), 0) INTO v_saldo_sin_lote;

  IF v_saldo_sin_lote <= 0 THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'No hay stock sin lote en esta ubicación/presentación'
    );
  END IF;

  v_qty := COALESCE(p_cantidad, v_saldo_sin_lote);
  IF v_qty <= 0 THEN
    RETURN jsonb_build_object('status', 'error', 'message', 'La cantidad a asignar debe ser > 0');
  END IF;
  IF v_qty > v_saldo_sin_lote THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', format(
        'Cantidad %s supera el saldo sin lote (%s)',
        v_qty, v_saldo_sin_lote
      )
    );
  END IF;

  v_lote_result := public.fn_obtener_o_crear_lote(
    p_id_tienda := v_id_tienda,
    p_id_producto := p_id_producto,
    p_codigo := v_codigo,
    p_fecha_vencimiento := p_fecha_vencimiento,
    p_fecha_fabricacion := p_fecha_fabricacion,
    p_observaciones := p_observaciones
  );

  IF COALESCE(v_lote_result->>'status', '') <> 'success' THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', COALESCE(v_lote_result->>'message', 'Error creando/obteniendo lote')
    );
  END IF;

  v_id_lote := (v_lote_result->>'id_lote')::bigint;

  -- Saldo vigente del lote destino
  SELECT COALESCE((
    SELECT i.cantidad_final
    FROM app_dat_inventario_productos i
    WHERE i.id_producto = p_id_producto
      AND i.id_ubicacion IS NOT DISTINCT FROM p_id_ubicacion
      AND i.id_presentacion IS NOT DISTINCT FROM p_id_presentacion
      AND i.id_variante IS NOT DISTINCT FROM p_id_variante
      AND i.id_opcion_variante IS NOT DISTINCT FROM p_id_opcion_variante
      AND i.id_lote IS NOT DISTINCT FROM v_id_lote
    ORDER BY i.id DESC
    LIMIT 1
  ), 0) INTO v_saldo_lote;

  SELECT id INTO v_id_tipo_operacion
  FROM app_nom_tipo_operacion
  WHERE denominacion ILIKE 'Control Físico'
  LIMIT 1;

  IF v_id_tipo_operacion IS NULL THEN
    SELECT id INTO v_id_tipo_operacion
    FROM app_nom_tipo_operacion
    WHERE denominacion ILIKE 'Ajuste%'
    ORDER BY id
    LIMIT 1;
  END IF;

  IF v_id_tipo_operacion IS NULL THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'No se encontró tipo de operación para la asignación de lote'
    );
  END IF;

  v_obs := COALESCE(NULLIF(trim(COALESCE(p_observaciones, '')), ''), '')
    || format(
      ' [asignar lote "%s" a %s uds sin lote → id_lote=%s]',
      v_codigo, v_qty, v_id_lote
    );

  INSERT INTO app_dat_operaciones (
    id_tipo_operacion, uuid, id_tienda, observaciones, created_at
  ) VALUES (
    v_id_tipo_operacion, v_uid, v_id_tienda, v_obs, NOW()
  ) RETURNING id INTO v_id_operacion;

  INSERT INTO app_dat_estado_operacion (
    id_operacion, estado, uuid, created_at, comentario
  ) VALUES (
    v_id_operacion, 2, v_uid, NOW(), 'Asignación de lote a stock sin etiquetar'
  );

  INSERT INTO app_dat_control_productos (
    id_operacion, id_producto, id_ubicacion, id_presentacion, cantidad, created_at
  ) VALUES (
    v_id_operacion, p_id_producto, p_id_ubicacion, p_id_presentacion, v_qty, NOW()
  ) RETURNING id INTO v_id_control;

  -- 1) Cero (o reduce) el bucket sin lote
  INSERT INTO app_dat_inventario_productos (
    id_producto, id_variante, id_opcion_variante, id_ubicacion,
    id_presentacion, cantidad_inicial, cantidad_final,
    origen_cambio, id_control, id_lote, created_at
  ) VALUES (
    p_id_producto, p_id_variante, p_id_opcion_variante, p_id_ubicacion,
    p_id_presentacion, v_saldo_sin_lote, v_saldo_sin_lote - v_qty,
    3, v_id_control, NULL, NOW()
  );

  -- 2) Credita el lote destino
  INSERT INTO app_dat_inventario_productos (
    id_producto, id_variante, id_opcion_variante, id_ubicacion,
    id_presentacion, cantidad_inicial, cantidad_final,
    origen_cambio, id_control, id_lote, created_at
  ) VALUES (
    p_id_producto, p_id_variante, p_id_opcion_variante, p_id_ubicacion,
    p_id_presentacion, v_saldo_lote, v_saldo_lote + v_qty,
    3, v_id_control, v_id_lote, NOW()
  );

  RETURN jsonb_build_object(
    'status', 'success',
    'message', 'Lote asignado al stock sin etiquetar',
    'id_operacion', v_id_operacion,
    'id_lote', v_id_lote,
    'codigo', v_lote_result->>'codigo',
    'fecha_vencimiento', p_fecha_vencimiento,
    'cantidad_movida', v_qty,
    'saldo_sin_lote_nuevo', v_saldo_sin_lote - v_qty,
    'saldo_lote_nuevo', v_saldo_lote + v_qty
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'status', 'error',
    'message', 'Error en fn_asignar_lote_a_stock_sin_lote: ' || SQLERRM,
    'error_detail', SQLSTATE
  );
END;
$$;

COMMENT ON FUNCTION public.fn_asignar_lote_a_stock_sin_lote(
  bigint, bigint, bigint, text, date, date, bigint, bigint, numeric, text
) IS
  'Reclasifica stock id_lote NULL → lote (código+fecha). Solo gerente/supervisor. '
  'Neto cero: egreso del bucket sin lote + ingreso al lote destino.';

GRANT EXECUTE ON FUNCTION public.fn_asignar_lote_a_stock_sin_lote(
  bigint, bigint, bigint, text, date, date, bigint, bigint, numeric, text
) TO authenticated, service_role;
