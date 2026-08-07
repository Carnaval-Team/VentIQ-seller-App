-- ============================================================================
-- Transferencia entre layouts: personas entrega / transporta / recibe
--
-- Extracción:
--   entregado_por = quien entrega en origen
--   recibido_por   = quien transporta
--   autorizado_por = quien entrega (compat)
--
-- Recepción:
--   entregado_por = quien transporta
--   recibido_por   = quien recibe en destino
-- ============================================================================

ALTER TABLE public.app_dat_operacion_extraccion
  ADD COLUMN IF NOT EXISTS entregado_por VARCHAR,
  ADD COLUMN IF NOT EXISTS recibido_por VARCHAR;

DROP FUNCTION IF EXISTS public.fn_transferir_inventario_entre_layouts(
  BIGINT, BIGINT, JSONB, TEXT, TEXT, BIGINT, UUID, BOOLEAN, TEXT
);

DROP FUNCTION IF EXISTS public.fn_transferir_inventario_entre_layouts(
  BIGINT, BIGINT, JSONB, TEXT, TEXT, BIGINT, UUID, BOOLEAN, TEXT, TEXT, TEXT, TEXT
);

CREATE OR REPLACE FUNCTION public.fn_transferir_inventario_entre_layouts(
  p_id_layout_origen       BIGINT,
  p_id_layout_destino      BIGINT,
  p_productos              JSONB,
  p_autorizado_por         TEXT,
  p_observaciones          TEXT    DEFAULT '',
  p_id_tienda              BIGINT  DEFAULT NULL,
  p_uuid                   UUID    DEFAULT NULL,
  p_completar_operaciones  BOOLEAN DEFAULT FALSE,
  p_moneda_factura         TEXT    DEFAULT 'USD',
  p_entregado_por          TEXT    DEFAULT NULL,
  p_transportado_por       TEXT    DEFAULT NULL,
  p_recibido_por           TEXT    DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
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

  v_entregado              TEXT;
  v_transporta             TEXT;
  v_recibe                 TEXT;
BEGIN
  v_entregado := COALESCE(
    NULLIF(TRIM(p_entregado_por), ''),
    NULLIF(TRIM(p_autorizado_por), ''),
    'Sistema'
  );
  v_transporta := COALESCE(
    NULLIF(TRIM(p_transportado_por), ''),
    v_entregado
  );
  v_recibe := COALESCE(
    NULLIF(TRIM(p_recibido_por), ''),
    v_transporta
  );

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

    v_productos_extraccion := v_productos_extraccion || jsonb_build_array(
      v_item || jsonb_build_object(
        'id_ubicacion', p_id_layout_origen::TEXT,
        'precio_unitario', COALESCE(NULLIF(v_item->>'precio_unitario', '')::NUMERIC, 0)
      )
    );

    v_productos_recepcion := v_productos_recepcion || jsonb_build_array(
      v_item || jsonb_build_object(
        'id_ubicacion', p_id_layout_destino::TEXT,
        'precio_unitario', 0,
        'id_motivo_operacion', c_motivo_recepcion::TEXT
      )
    );
  END LOOP;

  -- 1. Extracción
  v_ext_result := public.fn_crear_extraccion_con_movimiento(
    p_autorizado_por         => v_entregado,
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

  -- Salida de transferencia: tipo 7 (no el 18 genérico de extracción)
  UPDATE public.app_dat_operaciones
  SET id_tipo_operacion = 7
  WHERE id = v_id_extraccion;

  -- Personas en extracción: entrega = origen, recibe = transporta
  UPDATE public.app_dat_operacion_extraccion
  SET autorizado_por = v_entregado,
      entregado_por  = v_entregado,
      recibido_por    = v_transporta
  WHERE id_operacion = v_id_extraccion;

  -- 2. Recepción: entrega = transporta, recibe = destino
  v_rec_result := public.fn_registrar_recepcion_con_inventario(
    p_entregado_por    => v_transporta,
    p_id_tienda        => p_id_tienda,
    p_monto_total      => 0,
    p_motivo           => c_motivo_recepcion,
    p_observaciones    => 'Transferencia: ' || COALESCE(p_observaciones, ''),
    p_productos        => v_productos_recepcion,
    p_recibido_por     => v_recibe,
    p_uuid             => p_uuid,
    p_moneda_factura   => COALESCE(NULLIF(TRIM(p_moneda_factura), ''), 'USD')
  );

  IF COALESCE(v_rec_result->>'status', '') <> 'success' THEN
    RAISE EXCEPTION 'Error en recepción: %', COALESCE(v_rec_result->>'message', v_rec_result::TEXT);
  END IF;

  v_id_recepcion := (v_rec_result->>'id_operacion')::BIGINT;

  -- Entrada de transferencia: tipo 8 (refuerzo por si el motivo no lo resolvió)
  UPDATE public.app_dat_operaciones
  SET id_tipo_operacion = 8
  WHERE id = v_id_recepcion;

  -- 3. Vínculo transferencia (padre = Transferencia de productos = 19)
  SELECT id
  INTO v_id_tipo_transferencia
  FROM public.app_nom_tipo_operacion
  WHERE id = 19
     OR denominacion ILIKE '%transferencia de productos%'
  ORDER BY CASE WHEN id = 19 THEN 0 ELSE 1 END, id
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
      'Transferencia layout %s → %s (extracción %s, recepción %s). Entrega: %s | Transporta: %s | Recibe: %s',
      p_id_layout_origen,
      p_id_layout_destino,
      v_id_extraccion,
      v_id_recepcion,
      v_entregado,
      v_transporta,
      v_recibe
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
    v_entregado
  );

  -- Estado pendiente del padre (la UI lista la transferencia como una sola op)
  INSERT INTO public.app_dat_estado_operacion (
    id_operacion,
    estado,
    uuid,
    created_at
  ) VALUES (
    v_id_operacion_padre,
    1,
    p_uuid,
    NOW()
  );

  -- 4. Completar operaciones
  IF p_completar_operaciones THEN
    FOREACH v_op_a_completar IN ARRAY ARRAY[v_id_extraccion, v_id_recepcion, v_id_operacion_padre]
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
    'message', CASE
      WHEN p_completar_operaciones THEN 'Transferencia entre layouts completada exitosamente'
      ELSE 'Transferencia registrada en pendiente (extracción y recepción)'
    END,
    'id_extraccion', v_id_extraccion,
    'id_recepcion', v_id_recepcion,
    'id_operacion_transferencia', v_id_operacion_padre,
    'total_productos', jsonb_array_length(v_productos_base),
    'monto_total', 0,
    'entregado_por', v_entregado,
    'transportado_por', v_transporta,
    'recibido_por', v_recibe,
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
  'Transferencia atómica entre layouts. Personas: p_entregado_por (origen), p_transportado_por, p_recibido_por (destino). Extracción: entregado=origen, recibido=transporta. Recepción: entregado=transporta, recibido=destino.';

GRANT EXECUTE ON FUNCTION public.fn_transferir_inventario_entre_layouts(
  BIGINT, BIGINT, JSONB, TEXT, TEXT, BIGINT, UUID, BOOLEAN, TEXT, TEXT, TEXT, TEXT
) TO authenticated;

GRANT EXECUTE ON FUNCTION public.fn_transferir_inventario_entre_layouts(
  BIGINT, BIGINT, JSONB, TEXT, TEXT, BIGINT, UUID, BOOLEAN, TEXT, TEXT, TEXT, TEXT
) TO anon;
