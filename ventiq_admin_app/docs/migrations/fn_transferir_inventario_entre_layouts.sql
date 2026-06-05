-- ============================================================================
-- Transferencia atómica entre layouts (origen → destino)
--
-- Ejecuta en UNA transacción:
--   1) Extracción (motivo 7) + movimiento de salida en origen
--   2) Recepción (motivo 2) + movimiento de entrada en destino
--   3) Registro en app_dat_operacion_transferencia
--   4) Opcional: marcar ambas operaciones como completadas (estado 2)
--
-- IMPORTANTE: transferencia interna — NO actualiza precio_promedio (costo).
-- La recepción usa precio_unitario = 0 y motivo = 2 (entrada por transferencia).
--
-- Si falla cualquier paso, se revierte todo (no queda extracción sin recepción).
--
-- Uso desde Flutter:
--   supabase.rpc('fn_transferir_inventario_entre_layouts', params: { ... })
--
-- Constantes alineadas con InventoryService.transferBetweenLayouts:
--   motivo extracción = 7, motivo recepción = 2
-- ============================================================================

-- ── Helper: convertir un ítem JSON a presentación base (misma lógica que Flutter) ─
CREATE OR REPLACE FUNCTION public.fn_producto_json_a_presentacion_base(p_item JSONB)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_id_producto        BIGINT;
  v_id_pp              BIGINT;  -- id fila app_dat_producto_presentacion
  v_cantidad           NUMERIC;
  v_id_base            BIGINT;
  v_cant_from          NUMERIC;
  v_cant_base          NUMERIC;
  v_cant_final         NUMERIC;
BEGIN
  IF p_item IS NULL OR p_item->>'id_producto' IS NULL THEN
    RETURN p_item;
  END IF;

  v_id_producto := (p_item->>'id_producto')::BIGINT;
  v_cantidad      := COALESCE((p_item->>'cantidad')::NUMERIC, 0);
  v_id_pp         := NULLIF(TRIM(p_item->>'id_presentacion'), '')::BIGINT;

  IF v_id_pp IS NULL THEN
    RETURN p_item;
  END IF;

  SELECT pp.id, pp.cantidad
  INTO v_id_base, v_cant_base
  FROM public.app_dat_producto_presentacion pp
  WHERE pp.id_producto = v_id_producto
    AND pp.es_base = TRUE
  ORDER BY pp.id
  LIMIT 1;

  IF v_id_base IS NULL THEN
    RETURN p_item;
  END IF;

  IF v_id_pp = v_id_base THEN
    RETURN p_item || jsonb_build_object('id_presentacion', v_id_base::TEXT);
  END IF;

  SELECT pp.cantidad
  INTO v_cant_from
  FROM public.app_dat_producto_presentacion pp
  WHERE pp.id = v_id_pp
  LIMIT 1;

  IF v_cant_from IS NULL OR v_cant_base IS NULL OR v_cant_base = 0 THEN
    RETURN p_item;
  END IF;

  v_cant_final := (v_cantidad * v_cant_from) / v_cant_base;

  RETURN p_item
    || jsonb_build_object(
         'id_presentacion', v_id_base::TEXT,
         'cantidad', v_cant_final
       );
END;
$$;

-- ── Helper: array de productos → presentación base ───────────────────────────
CREATE OR REPLACE FUNCTION public.fn_productos_json_a_presentacion_base(p_productos JSONB)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_item    JSONB;
  v_result  JSONB := '[]'::JSONB;
BEGIN
  IF p_productos IS NULL OR jsonb_array_length(p_productos) = 0 THEN
    RETURN '[]'::JSONB;
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_productos)
  LOOP
    v_result := v_result || jsonb_build_array(
      public.fn_producto_json_a_presentacion_base(v_item)
    );
  END LOOP;

  RETURN v_result;
END;
$$;

-- ── RPC principal ────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.fn_transferir_inventario_entre_layouts(
  BIGINT, BIGINT, JSONB, TEXT, TEXT, BIGINT, UUID, BOOLEAN, TEXT
);

CREATE OR REPLACE FUNCTION public.fn_transferir_inventario_entre_layouts(
  p_id_layout_origen       BIGINT,
  p_id_layout_destino      BIGINT,
  p_productos              JSONB,
  p_autorizado_por         TEXT,
  p_observaciones          TEXT    DEFAULT '',
  p_id_tienda              BIGINT  DEFAULT NULL,
  p_uuid                   UUID    DEFAULT NULL,
  p_completar_operaciones  BOOLEAN DEFAULT TRUE,
  p_moneda_factura         TEXT    DEFAULT 'USD'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  -- Motivos (alineados con ventiq_admin_app InventoryService)
  c_motivo_extraccion      CONSTANT BIGINT := 7;
  c_motivo_recepcion       CONSTANT INTEGER := 2;

  v_item                   JSONB;
  v_productos_base         JSONB;
  v_productos_extraccion   JSONB := '[]'::JSONB;
  v_productos_recepcion    JSONB := '[]'::JSONB;
  v_cantidad               NUMERIC;

  v_ext_result             JSONB;
  v_rec_result             JSONB;
  v_id_extraccion          BIGINT;
  v_id_recepcion           BIGINT;

  v_id_tipo_transferencia  BIGINT;
  v_id_operacion_padre     BIGINT;
  v_estado_actual          SMALLINT;
  v_op_a_completar         BIGINT;
BEGIN
  -- ── Validaciones ─────────────────────────────────────────────────────────
  IF p_id_layout_origen IS NULL OR p_id_layout_destino IS NULL THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'Debe indicar layout de origen y destino',
      'etapa', 'validacion_layouts'
    );
  END IF;

  IF p_id_layout_origen = p_id_layout_destino THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'El layout de origen y destino no pueden ser el mismo',
      'etapa', 'validacion_layouts'
    );
  END IF;

  IF p_productos IS NULL OR jsonb_array_length(p_productos) = 0 THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'Debe incluir al menos un producto',
      'etapa', 'validacion_productos'
    );
  END IF;

  IF p_id_tienda IS NULL THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'id_tienda es obligatorio',
      'etapa', 'validacion_tienda'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.app_dat_tienda WHERE id = p_id_tienda) THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', format('La tienda %s no existe', p_id_tienda),
      'etapa', 'validacion_tienda'
    );
  END IF;

  IF p_uuid IS NULL THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'uuid de usuario es obligatorio',
      'etapa', 'validacion_uuid'
    );
  END IF;

  -- ── Normalizar a presentación base ───────────────────────────────────────
  v_productos_base := public.fn_productos_json_a_presentacion_base(p_productos);

  FOR v_item IN SELECT value FROM jsonb_array_elements(v_productos_base)
  LOOP
    IF v_item->>'id_producto' IS NULL OR v_item->>'cantidad' IS NULL THEN
      RAISE EXCEPTION 'Cada producto debe tener id_producto y cantidad';
    END IF;

    v_cantidad := (v_item->>'cantidad')::NUMERIC;
    IF v_cantidad <= 0 THEN
      RAISE EXCEPTION 'La cantidad debe ser mayor que cero (producto %)', v_item->>'id_producto';
    END IF;

    -- Extracción: ubicación origen
    v_productos_extraccion := v_productos_extraccion || jsonb_build_array(
      v_item || jsonb_build_object(
        'id_ubicacion', p_id_layout_origen::TEXT,
        'precio_unitario', COALESCE(NULLIF(v_item->>'precio_unitario', '')::NUMERIC, 0)
      )
    );

    -- Recepción: ubicación destino, sin costo (no altera precio_promedio)
    v_productos_recepcion := v_productos_recepcion || jsonb_build_array(
      v_item || jsonb_build_object(
        'id_ubicacion', p_id_layout_destino::TEXT,
        'precio_unitario', 0,
        'id_motivo_operacion', c_motivo_recepcion::TEXT
      )
    );
  END LOOP;

  -- ── 1. Extracción (atómica con movimiento de inventario) ─────────────────
  v_ext_result := public.fn_crear_extraccion_con_movimiento(
    p_autorizado_por         => COALESCE(NULLIF(TRIM(p_autorizado_por), ''), 'Sistema'),
    p_estado_inicial         => 1::SMALLINT,
    p_id_motivo_operacion    => c_motivo_extraccion,
    p_id_tienda              => p_id_tienda,
    p_observaciones          => 'Extracción para transferencia: ' || COALESCE(p_observaciones, ''),
    p_productos              => v_productos_extraccion,
    p_uuid                   => p_uuid
  );

  IF COALESCE(v_ext_result->>'status', '') <> 'success' THEN
    RAISE EXCEPTION 'Error en extracción: %', COALESCE(v_ext_result->>'message', v_ext_result::TEXT);
  END IF;

  v_id_extraccion := (v_ext_result->>'id_operacion')::BIGINT;

  -- ── 2. Recepción (si falla, rollback de toda la función) ─────────────────
  v_rec_result := public.fn_registrar_recepcion_con_inventario(
    p_entregado_por    => COALESCE(NULLIF(TRIM(p_autorizado_por), ''), 'Sistema'),
    p_id_tienda        => p_id_tienda,
    p_monto_total      => 0,
    p_motivo           => c_motivo_recepcion,
    p_observaciones    => 'Transferencia: ' || COALESCE(p_observaciones, ''),
    p_productos        => v_productos_recepcion,
    p_recibido_por     => COALESCE(NULLIF(TRIM(p_autorizado_por), ''), 'Sistema'),
    p_uuid             => p_uuid,
    p_moneda_factura   => COALESCE(NULLIF(TRIM(p_moneda_factura), ''), 'USD')
  );

  IF COALESCE(v_rec_result->>'status', '') <> 'success' THEN
    RAISE EXCEPTION 'Error en recepción: %', COALESCE(v_rec_result->>'message', v_rec_result::TEXT);
  END IF;

  v_id_recepcion := (v_rec_result->>'id_operacion')::BIGINT;

  -- ── 3. Vínculo app_dat_operacion_transferencia ───────────────────────────
  SELECT id
  INTO v_id_tipo_transferencia
  FROM public.app_nom_tipo_operacion
  WHERE denominacion ILIKE '%transfer%'
  ORDER BY id
  LIMIT 1;

  IF v_id_tipo_transferencia IS NULL THEN
    SELECT o.id_tipo_operacion
    INTO v_id_tipo_transferencia
    FROM public.app_dat_operaciones o
    WHERE o.id = v_id_extraccion;
  END IF;

  INSERT INTO public.app_dat_operaciones (
    id_tipo_operacion,
    uuid,
    id_tienda,
    observaciones,
    created_at
  ) VALUES (
    v_id_tipo_transferencia,
    p_uuid,
    p_id_tienda,
    format(
      'Transferencia layout %s → %s (extracción %s, recepción %s)',
      p_id_layout_origen,
      p_id_layout_destino,
      v_id_extraccion,
      v_id_recepcion
    ),
    NOW()
  )
  RETURNING id INTO v_id_operacion_padre;

  INSERT INTO public.app_dat_operacion_transferencia (
    id_operacion,
    id_extraccion,
    id_recepcion,
    autorizado_por
  ) OVERRIDING SYSTEM VALUE
  VALUES (
    v_id_operacion_padre,
    v_id_extraccion,
    v_id_recepcion,
    NULLIF(TRIM(p_autorizado_por), '')
  );

  -- ── 4. Completar operaciones (estado 2), igual que la pantalla admin ───────
  IF p_completar_operaciones THEN
    FOREACH v_op_a_completar IN ARRAY ARRAY[v_id_extraccion, v_id_recepcion]
    LOOP
      SELECT eo.estado
      INTO v_estado_actual
      FROM public.app_dat_estado_operacion eo
      WHERE eo.id_operacion = v_op_a_completar
      ORDER BY eo.created_at DESC
      LIMIT 1;

      IF COALESCE(v_estado_actual, 0) <> 2 THEN
        INSERT INTO public.app_dat_estado_operacion (
          id_operacion,
          estado,
          uuid,
          created_at
        ) VALUES (
          v_op_a_completar,
          2,
          p_uuid,
          NOW()
        );
      END IF;
    END LOOP;
  END IF;

  RETURN jsonb_build_object(
    'status', 'success',
    'message', 'Transferencia entre layouts completada exitosamente',
    'id_extraccion', v_id_extraccion,
    'id_recepcion', v_id_recepcion,
    'id_operacion_transferencia', v_id_operacion_padre,
    'total_productos', jsonb_array_length(v_productos_base),
    'monto_total', 0,
    'estado', CASE WHEN p_completar_operaciones THEN 'completado' ELSE 'pendiente' END
  );

EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', SQLERRM,
      'sqlstate', SQLSTATE,
      'etapa', 'fn_transferir_inventario_entre_layouts',
      'id_extraccion_parcial', v_id_extraccion,
      'id_recepcion_parcial', v_id_recepcion
    );
END;
$$;

COMMENT ON FUNCTION public.fn_transferir_inventario_entre_layouts IS
  'Transferencia atómica: extracción en origen + recepción en destino + vínculo. Revierte todo si falla un paso.';

GRANT EXECUTE ON FUNCTION public.fn_producto_json_a_presentacion_base(JSONB) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_productos_json_a_presentacion_base(JSONB) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_transferir_inventario_entre_layouts(
  BIGINT, BIGINT, JSONB, TEXT, TEXT, BIGINT, UUID, BOOLEAN, TEXT
) TO authenticated, service_role;
