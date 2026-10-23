-- ============================================================================
-- FUNCION: fn_insertar_ajuste_inventario2
-- Ajuste de UNA presentacion: lee saldo real, crea operacion + estado +
-- control_productos + ajuste_inventario, aplica ledger via helpers y enlaza
-- id_control en el snapshot para que export/kardex no lo dejen como SIN_OP.
--
-- Fuente: presentaciones_inventario/08_ajuste_por_presentacion.sql
-- Aplicar en SQL Editor. Idempotente (CREATE OR REPLACE). Firma sin cambios.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_insertar_ajuste_inventario2(
  p_id_producto        BIGINT,
  p_id_ubicacion       BIGINT,
  p_id_presentacion    BIGINT,
  p_cantidad_anterior  NUMERIC,
  p_cantidad_nueva     NUMERIC,
  p_motivo             TEXT,
  p_observaciones      TEXT,
  p_uuid_usuario       UUID,
  p_id_tipo_operacion  BIGINT
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_id_operacion    BIGINT;
  v_id_ajuste       BIGINT;
  v_id_control      BIGINT;
  v_diferencia      NUMERIC;
  v_id_tienda       BIGINT;
  v_id_presentacion BIGINT := p_id_presentacion;
  v_saldo_real      NUMERIC;
  v_desfase         BOOLEAN := false;
  v_observaciones   TEXT;
  v_movimiento      JSONB;
  v_err_message     TEXT;
BEGIN
  SELECT id_tienda
  INTO v_id_tienda
  FROM app_dat_producto
  WHERE id = p_id_producto;

  IF p_id_producto IS NULL OR p_id_ubicacion IS NULL THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'Parámetros requeridos faltantes: id_producto, id_ubicacion'
    );
  END IF;

  IF p_cantidad_nueva IS NULL OR p_cantidad_nueva < 0 THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'La cantidad nueva no puede ser negativa'
    );
  END IF;

  IF v_id_presentacion IS NULL THEN
    SELECT c.id_presentacion
    INTO v_id_presentacion
    FROM public.fn_presentaciones_producto(p_id_producto) c
    WHERE c.es_base
    LIMIT 1;

    IF v_id_presentacion IS NULL THEN
      RETURN jsonb_build_object(
        'status',  'error',
        'message', format(
          'El producto %s no tiene ninguna presentacion configurada en app_dat_producto_presentacion',
          p_id_producto)
      );
    END IF;
  END IF;

  BEGIN
    PERFORM public.fn_validar_id_presentacion(p_id_producto, v_id_presentacion);
  EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_err_message = MESSAGE_TEXT;
      RETURN jsonb_build_object(
        'status',          'error',
        'message',         v_err_message,
        'id_presentacion', v_id_presentacion
      );
  END;

  SELECT COALESCE(SUM(s.saldo), 0)
  INTO v_saldo_real
  FROM public.fn_stock_saldos_presentacion(
         p_id_producto, NULL, p_id_ubicacion, true) s
  WHERE s.id_presentacion = v_id_presentacion;

  v_diferencia := p_cantidad_nueva - v_saldo_real;

  IF p_cantidad_anterior IS NOT NULL AND p_cantidad_anterior <> v_saldo_real THEN
    v_desfase := true;
  END IF;

  v_observaciones := COALESCE(p_observaciones, '');
  IF v_desfase THEN
    v_observaciones := v_observaciones || format(
      ' [saldo declarado %s, saldo real %s]', p_cantidad_anterior, v_saldo_real);
  END IF;

  INSERT INTO app_dat_operaciones (
    id_tipo_operacion,
    uuid,
    id_tienda,
    observaciones,
    created_at
  ) VALUES (
    p_id_tipo_operacion,
    p_uuid_usuario,
    v_id_tienda,
    v_observaciones,
    NOW()
  ) RETURNING id INTO v_id_operacion;

  INSERT INTO app_dat_estado_operacion (
    id_operacion,
    estado,
    uuid,
    created_at,
    comentario
  ) VALUES (
    v_id_operacion,
    2,
    p_uuid_usuario,
    NOW(),
    'Ajuste de inventario completado'
  );

  -- control_productos: enlace canónico operación ↔ ledger (evita SIN_OP).
  IF v_diferencia <> 0 THEN
    INSERT INTO app_dat_control_productos (
      id_operacion,
      id_producto,
      id_ubicacion,
      id_presentacion,
      cantidad,
      created_at
    ) VALUES (
      v_id_operacion,
      p_id_producto,
      p_id_ubicacion,
      v_id_presentacion,
      ABS(v_diferencia),
      NOW()
    ) RETURNING id INTO v_id_control;
  END IF;

  INSERT INTO app_dat_ajuste_inventario (
    id_producto,
    id_variante,
    id_ubicacion,
    cantidad_anterior,
    cantidad_nueva,
    diferencia,
    id_control,
    id_operacion,
    uuid_usuario,
    created_at
  ) VALUES (
    p_id_producto,
    NULL,
    p_id_ubicacion,
    v_saldo_real,
    p_cantidad_nueva,
    v_diferencia,
    v_id_control,
    v_id_operacion,
    p_uuid_usuario,
    NOW()
  ) RETURNING id INTO v_id_ajuste;

  IF v_diferencia > 0 THEN
    v_movimiento := public.fn_ingresar_presentacion(
      p_id_producto     := p_id_producto,
      p_id_ubicacion    := p_id_ubicacion,
      p_id_presentacion := v_id_presentacion,
      p_cantidad        := v_diferencia,
      p_origen_cambio   := 3
    );

  ELSIF v_diferencia < 0 THEN
    v_movimiento := public.fn_descontar_con_rebalanceo(
      p_id_producto     := p_id_producto,
      p_id_ubicacion    := p_id_ubicacion,
      p_id_presentacion := v_id_presentacion,
      p_cantidad        := -v_diferencia,
      p_origen_cambio   := 3,
      p_id_operacion    := v_id_operacion,
      p_uuid            := p_uuid_usuario,
      p_motivo          := COALESCE(NULLIF(TRIM(p_motivo), ''), 'ajuste')
    );

  ELSE
    v_movimiento := jsonb_build_object('status', 'success', 'sin_cambios', true);
  END IF;

  IF COALESCE(v_movimiento->>'status', '') <> 'success' THEN
    RAISE EXCEPTION '%', COALESCE(
      v_movimiento->>'message',
      'No se pudo aplicar el ajuste al inventario')
      USING ERRCODE = 'P0001';
  END IF;

  -- Helpers aún no aceptan p_id_control; enlazar la fila recién escrita.
  IF v_id_control IS NOT NULL
     AND COALESCE(v_movimiento->>'sin_cambios', 'false') <> 'true' THEN
    UPDATE app_dat_inventario_productos i
    SET id_control = v_id_control
    WHERE i.id = (
      SELECT i2.id
      FROM app_dat_inventario_productos i2
      WHERE i2.id_producto = p_id_producto
        AND i2.id_ubicacion IS NOT DISTINCT FROM p_id_ubicacion
        AND i2.id_presentacion = v_id_presentacion
        AND i2.origen_cambio = 3
        AND i2.id_control IS NULL
        AND i2.id_extraccion IS NULL
        AND i2.id_recepcion IS NULL
        AND COALESCE(i2.id_conversion, 0) = 0
        AND i2.created_at >= (
          SELECT o.created_at FROM app_dat_operaciones o WHERE o.id = v_id_operacion
        )
      ORDER BY i2.id DESC
      LIMIT 1
    );
  END IF;

  RETURN jsonb_build_object(
    'status',          'success',
    'message',         'Ajuste de inventario registrado correctamente',
    'id_operacion',    v_id_operacion,
    'id_ajuste',       v_id_ajuste,
    'id_control',      v_id_control,
    'diferencia',      v_diferencia,
    'id_presentacion', v_id_presentacion,
    'saldo_anterior',  v_saldo_real,
    'saldo_nuevo',     p_cantidad_nueva,
    'saldo_declarado', p_cantidad_anterior,
    'desfase',         v_desfase,
    'conversiones',    COALESCE(v_movimiento->'conversiones', '[]'::JSONB)
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'status', 'error',
    'message', 'Error al procesar ajuste: ' || SQLERRM,
    'error_detail', SQLSTATE
  );
END;
$$;

COMMENT ON FUNCTION public.fn_insertar_ajuste_inventario2(
  BIGINT, BIGINT, BIGINT, NUMERIC, NUMERIC, TEXT, TEXT, UUID, BIGINT) IS
  'Ajusta el inventario de UNA presentacion en una ubicacion. Lee el saldo '
  'previo real, valida id_presentacion, aplica la diferencia con helpers, y '
  'crea app_dat_control_productos + enlaza id_control en ajuste y ledger.';
