-- ============================================================================
-- 03 · Lotes — ajuste+, stock por lote, alertas caducidad
-- ============================================================================
-- Plan: docs/PLAN_VENCIMIENTOS_LOTES.md  (Fases 1.3, 2, 3)
-- Prerrequisito: 01 + 02 en newa. NO aplicar en main hasta cerrar el proyecto.
-- ============================================================================

-- ============================================================================
-- A) Ajuste de inventario con lote (nuevos params opcionales)
-- ============================================================================
DROP FUNCTION IF EXISTS public.fn_insertar_ajuste_inventario2(
  BIGINT, BIGINT, BIGINT, NUMERIC, NUMERIC, TEXT, TEXT, UUID, BIGINT
);

CREATE OR REPLACE FUNCTION public.fn_insertar_ajuste_inventario2(
  p_id_producto        BIGINT,
  p_id_ubicacion       BIGINT,
  p_id_presentacion    BIGINT,
  p_cantidad_anterior  NUMERIC,
  p_cantidad_nueva     NUMERIC,
  p_motivo             TEXT,
  p_observaciones      TEXT,
  p_uuid_usuario       UUID,
  p_id_tipo_operacion  BIGINT,
  p_codigo_lote        TEXT DEFAULT NULL,
  p_fecha_vencimiento   DATE DEFAULT NULL,
  p_fecha_fabricacion  DATE DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_id_operacion    BIGINT;
  v_id_ajuste       BIGINT;
  v_id_control      BIGINT;
  v_id_lote         BIGINT;
  v_diferencia      NUMERIC;
  v_id_tienda       BIGINT;
  v_id_presentacion BIGINT := p_id_presentacion;
  v_saldo_real      NUMERIC;
  v_desfase         BOOLEAN := false;
  v_observaciones   TEXT;
  v_movimiento      JSONB;
  v_err_message     TEXT;
  v_es_por_lotes    BOOLEAN := false;
  v_lote_result     JSONB;
  v_codigo_lote     TEXT := NULLIF(TRIM(COALESCE(p_codigo_lote, '')), '');
BEGIN
  SELECT id_tienda, COALESCE(es_por_lotes, false)
  INTO v_id_tienda, v_es_por_lotes
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
    SELECT c.id_presentacion INTO v_id_presentacion
    FROM public.fn_presentaciones_producto(p_id_producto) c
    WHERE c.es_base LIMIT 1;
    IF v_id_presentacion IS NULL THEN
      RETURN jsonb_build_object(
        'status', 'error',
        'message', format('Producto %s sin presentacion', p_id_producto)
      );
    END IF;
  END IF;

  BEGIN
    PERFORM public.fn_validar_id_presentacion(p_id_producto, v_id_presentacion);
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err_message = MESSAGE_TEXT;
    RETURN jsonb_build_object('status', 'error', 'message', v_err_message);
  END;

  -- Saldo agregado (presentación); si es por lotes se recalcula por id_lote abajo
  SELECT COALESCE(SUM(s.saldo), 0) INTO v_saldo_real
  FROM public.fn_stock_saldos_presentacion(
         p_id_producto, NULL, p_id_ubicacion, true) s
  WHERE s.id_presentacion = v_id_presentacion;

  IF p_cantidad_anterior IS NOT NULL AND p_cantidad_anterior <> v_saldo_real THEN
    v_desfase := true;
  END IF;

  v_observaciones := COALESCE(p_observaciones, '');
  IF v_desfase THEN
    v_observaciones := v_observaciones || format(
      ' [saldo declarado %s, saldo real %s]', p_cantidad_anterior, v_saldo_real);
  END IF;

  INSERT INTO app_dat_operaciones (
    id_tipo_operacion, uuid, id_tienda, observaciones, created_at
  ) VALUES (
    p_id_tipo_operacion, p_uuid_usuario, v_id_tienda, v_observaciones, NOW()
  ) RETURNING id INTO v_id_operacion;

  INSERT INTO app_dat_estado_operacion (
    id_operacion, estado, uuid, created_at, comentario
  ) VALUES (
    v_id_operacion, 2, p_uuid_usuario, NOW(), 'Ajuste de inventario completado'
  );

  -- Resolver lote
  IF v_es_por_lotes THEN
    IF v_codigo_lote IS NOT NULL AND p_fecha_vencimiento IS NOT NULL THEN
      v_lote_result := public.fn_obtener_o_crear_lote(
        p_id_tienda := v_id_tienda,
        p_id_producto := p_id_producto,
        p_codigo := v_codigo_lote,
        p_fecha_vencimiento := p_fecha_vencimiento,
        p_fecha_fabricacion := p_fecha_fabricacion
      );
      IF COALESCE(v_lote_result->>'status','') <> 'success' THEN
        RETURN jsonb_build_object(
          'status', 'error',
          'message', COALESCE(v_lote_result->>'message', 'Error creando lote')
        );
      END IF;
      v_id_lote := (v_lote_result->>'id_lote')::BIGINT;
    ELSIF p_cantidad_nueva < v_saldo_real THEN
      -- FEFO automático en egreso si no mandan lote
      SELECT x.id_lote INTO v_id_lote
      FROM (
        SELECT DISTINCT ON (i.id_lote)
          i.id_lote, i.cantidad_final, l.fecha_vencimiento
        FROM app_dat_inventario_productos i
        JOIN app_dat_lote l ON l.id = i.id_lote
        WHERE i.id_producto = p_id_producto
          AND i.id_ubicacion IS NOT DISTINCT FROM p_id_ubicacion
          AND i.id_presentacion = v_id_presentacion
          AND i.id_lote IS NOT NULL
        ORDER BY i.id_lote, i.id DESC
      ) x
      WHERE x.cantidad_final > 0
      ORDER BY x.fecha_vencimiento ASC
      LIMIT 1;
    ELSE
      RETURN jsonb_build_object(
        'status', 'error',
        'message',
        'Producto por lotes: indique codigo_lote y fecha_vencimiento para el ajuste positivo'
      );
    END IF;

    IF v_id_lote IS NULL THEN
      RETURN jsonb_build_object(
        'status', 'error',
        'message', 'No se pudo resolver un lote para el ajuste'
      );
    END IF;

    -- Saldo del lote concreto
    SELECT COALESCE((
      SELECT i.cantidad_final FROM app_dat_inventario_productos i
      WHERE i.id_producto = p_id_producto
        AND i.id_ubicacion IS NOT DISTINCT FROM p_id_ubicacion
        AND i.id_presentacion = v_id_presentacion
        AND i.id_lote IS NOT DISTINCT FROM v_id_lote
      ORDER BY i.id DESC LIMIT 1
    ), 0) INTO v_saldo_real;
  END IF;

  v_diferencia := p_cantidad_nueva - v_saldo_real;

  IF v_diferencia <> 0 THEN
    INSERT INTO app_dat_control_productos (
      id_operacion, id_producto, id_ubicacion, id_presentacion, cantidad, created_at
    ) VALUES (
      v_id_operacion, p_id_producto, p_id_ubicacion, v_id_presentacion,
      ABS(v_diferencia), NOW()
    ) RETURNING id INTO v_id_control;
  END IF;

  INSERT INTO app_dat_ajuste_inventario (
    id_producto, id_variante, id_ubicacion,
    cantidad_anterior, cantidad_nueva, diferencia,
    id_control, id_operacion, uuid_usuario, created_at
  ) VALUES (
    p_id_producto, NULL, p_id_ubicacion,
    v_saldo_real, p_cantidad_nueva, v_diferencia,
    v_id_control, v_id_operacion, p_uuid_usuario, NOW()
  ) RETURNING id INTO v_id_ajuste;

  IF v_diferencia > 0 THEN
    v_movimiento := public.fn_ingresar_presentacion(
      p_id_producto := p_id_producto,
      p_id_ubicacion := p_id_ubicacion,
      p_id_presentacion := v_id_presentacion,
      p_cantidad := v_diferencia,
      p_origen_cambio := 3
    );
  ELSIF v_diferencia < 0 THEN
    v_movimiento := public.fn_descontar_con_rebalanceo(
      p_id_producto := p_id_producto,
      p_id_ubicacion := p_id_ubicacion,
      p_id_presentacion := v_id_presentacion,
      p_cantidad := -v_diferencia,
      p_origen_cambio := 3,
      p_id_operacion := v_id_operacion,
      p_uuid := p_uuid_usuario,
      p_motivo := COALESCE(NULLIF(TRIM(p_motivo), ''), 'ajuste')
    );
  ELSE
    v_movimiento := jsonb_build_object('status', 'success', 'sin_cambios', true);
  END IF;

  IF COALESCE(v_movimiento->>'status', '') <> 'success' THEN
    RAISE EXCEPTION '%', COALESCE(v_movimiento->>'message', 'No se pudo aplicar el ajuste')
      USING ERRCODE = 'P0001';
  END IF;

  IF v_id_control IS NOT NULL
     AND COALESCE(v_movimiento->>'sin_cambios', 'false') <> 'true' THEN
    UPDATE app_dat_inventario_productos i
    SET
      id_control = v_id_control,
      id_lote = COALESCE(v_id_lote, i.id_lote)
    WHERE i.id = (
      SELECT i2.id FROM app_dat_inventario_productos i2
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
      ORDER BY i2.id DESC LIMIT 1
    );
  END IF;

  RETURN jsonb_build_object(
    'status', 'success',
    'message', 'Ajuste de inventario registrado correctamente',
    'id_operacion', v_id_operacion,
    'id_ajuste', v_id_ajuste,
    'id_control', v_id_control,
    'id_lote', v_id_lote,
    'diferencia', v_diferencia,
    'id_presentacion', v_id_presentacion,
    'saldo_anterior', v_saldo_real,
    'saldo_nuevo', p_cantidad_nueva,
    'desfase', v_desfase
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'status', 'error',
    'message', 'Error al procesar ajuste: ' || SQLERRM,
    'error_detail', SQLSTATE
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_insertar_ajuste_inventario2(
  BIGINT, BIGINT, BIGINT, NUMERIC, NUMERIC, TEXT, TEXT, UUID, BIGINT, TEXT, DATE, DATE
) TO authenticated, service_role;


-- ============================================================================
-- B) Stock por lote en una ubicación (Fase 2)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_stock_lotes_en_ubicacion(
  p_id_ubicacion BIGINT
)
RETURNS TABLE (
  id_producto BIGINT,
  id_variante BIGINT,
  id_opcion_variante BIGINT,
  id_presentacion BIGINT,
  id_lote BIGINT,
  codigo_lote TEXT,
  fecha_vencimiento DATE,
  cantidad_final NUMERIC,
  dias_alert_caducidad NUMERIC,
  es_por_lotes BOOLEAN,
  estado_caducidad TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH latest AS (
    SELECT DISTINCT ON (
      i.id_producto,
      COALESCE(i.id_variante, 0),
      COALESCE(i.id_opcion_variante, 0),
      COALESCE(i.id_presentacion, 0),
      COALESCE(i.id_lote, 0)
    )
      i.id_producto,
      i.id_variante,
      i.id_opcion_variante,
      i.id_presentacion,
      i.id_lote,
      i.cantidad_final
    FROM app_dat_inventario_productos i
    WHERE i.id_ubicacion = p_id_ubicacion
      AND i.cantidad_final IS NOT NULL
    ORDER BY
      i.id_producto,
      COALESCE(i.id_variante, 0),
      COALESCE(i.id_opcion_variante, 0),
      COALESCE(i.id_presentacion, 0),
      COALESCE(i.id_lote, 0),
      i.id DESC
  )
  SELECT
    l.id_producto,
    l.id_variante,
    l.id_opcion_variante,
    l.id_presentacion,
    l.id_lote,
    lote.codigo::TEXT,
    lote.fecha_vencimiento,
    l.cantidad_final,
    p.dias_alert_caducidad,
    COALESCE(p.es_por_lotes, false),
    CASE
      WHEN lote.fecha_vencimiento IS NULL THEN 'sin_lote'
      WHEN lote.fecha_vencimiento < CURRENT_DATE THEN 'expired'
      WHEN p.dias_alert_caducidad IS NOT NULL
           AND p.dias_alert_caducidad > 0
           AND lote.fecha_vencimiento <= (CURRENT_DATE + (p.dias_alert_caducidad || ' days')::INTERVAL)
        THEN 'expiring'
      ELSE 'ok'
    END
  FROM latest l
  LEFT JOIN app_dat_lote lote ON lote.id = l.id_lote
  JOIN app_dat_producto p ON p.id = l.id_producto
  WHERE l.cantidad_final > 0
  ORDER BY lote.fecha_vencimiento ASC NULLS LAST, l.id_lote ASC NULLS LAST;
$$;

GRANT EXECUTE ON FUNCTION public.fn_stock_lotes_en_ubicacion(BIGINT)
  TO authenticated, service_role;


-- ============================================================================
-- C) Alertas de stock + caducidad (Fase 3)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.fn_analytics_stock_alerts(
  p_active_only boolean DEFAULT true,
  p_alert_types text[] DEFAULT NULL::text[],
  p_severities text[] DEFAULT NULL::text[],
  p_store_id integer DEFAULT NULL::integer
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_store_id INTEGER;
  result JSON;
BEGIN
  v_store_id := COALESCE(p_store_id, (
    SELECT id_tienda FROM app_dat_supervisor WHERE uuid = auth.uid() LIMIT 1
  ));
  IF v_store_id IS NULL THEN
    v_store_id := (
      SELECT id_tienda FROM auditor WHERE uuid = auth.uid() LIMIT 1
    );
  END IF;
  IF v_store_id IS NULL THEN
    v_store_id := (
      SELECT id_tienda FROM app_dat_gerente WHERE uuid = auth.uid() LIMIT 1
    );
  END IF;

  WITH latest_inventory AS (
    SELECT DISTINCT ON (ip.id_producto)
      ip.id_producto,
      COALESCE(ip.cantidad_final, ip.cantidad_inicial) AS current_stock
    FROM app_dat_inventario_productos ip
    INNER JOIN app_dat_producto p ON p.id = ip.id_producto
    WHERE p.id_tienda = v_store_id
      AND p.deleted_at IS NULL
      AND COALESCE(p.es_inventariable, true) = true
    ORDER BY ip.id_producto, ip.id DESC
  ),
  product_data AS (
    SELECT
      li.id_producto,
      p.denominacion AS product_name,
      p.sku,
      li.current_stock,
      (SELECT COUNT(DISTINCT ip2.id_ubicacion)
       FROM app_dat_inventario_productos ip2
       WHERE ip2.id_producto = li.id_producto
         AND COALESCE(ip2.cantidad_final, ip2.cantidad_inicial) > 0
      ) AS locations_count,
      COALESCE(
        (SELECT stock_min FROM app_dat_almacen_limites
         WHERE id_producto = li.id_producto LIMIT 1),
        5
      ) AS min_stock
    FROM latest_inventory li
    INNER JOIN app_dat_producto p ON p.id = li.id_producto
  ),
  stock_alerts AS (
    SELECT
      id_producto,
      product_name,
      sku,
      current_stock,
      locations_count,
      min_stock,
      CASE WHEN current_stock = 0 THEN 'critical' ELSE 'warning' END AS severity,
      CASE WHEN current_stock = 0 THEN 'out_of_stock' ELSE 'low_stock' END AS alert_type,
      CASE
        WHEN current_stock = 0 THEN 'Sin stock disponible'
        ELSE 'Stock bajo: ' || current_stock::text || ' unidades'
      END AS message,
      NULL::BIGINT AS id_lote,
      NULL::TEXT AS codigo_lote,
      NULL::DATE AS fecha_vencimiento
    FROM product_data
    WHERE current_stock <= min_stock
  ),
  latest_lote AS (
    SELECT DISTINCT ON (i.id_lote)
      i.id_producto,
      i.id_lote,
      i.cantidad_final,
      l.codigo,
      l.fecha_vencimiento,
      p.denominacion AS product_name,
      p.sku,
      p.dias_alert_caducidad
    FROM app_dat_inventario_productos i
    JOIN app_dat_lote l ON l.id = i.id_lote
    JOIN app_dat_producto p ON p.id = i.id_producto
    WHERE p.id_tienda = v_store_id
      AND p.deleted_at IS NULL
      AND i.id_lote IS NOT NULL
    ORDER BY i.id_lote, i.id DESC
  ),
  caducidad_alerts AS (
    SELECT
      id_producto,
      product_name,
      sku,
      cantidad_final AS current_stock,
      1 AS locations_count,
      0::NUMERIC AS min_stock,
      CASE
        WHEN fecha_vencimiento < CURRENT_DATE THEN 'critical'
        ELSE 'warning'
      END AS severity,
      CASE
        WHEN fecha_vencimiento < CURRENT_DATE THEN 'expired'
        ELSE 'expiring'
      END AS alert_type,
      CASE
        WHEN fecha_vencimiento < CURRENT_DATE THEN
          'Vencido (' || codigo || ') desde ' || fecha_vencimiento::text
        ELSE
          'Por vencer (' || codigo || ') el ' || fecha_vencimiento::text
      END AS message,
      id_lote,
      codigo AS codigo_lote,
      fecha_vencimiento
    FROM latest_lote
    WHERE cantidad_final > 0
      AND (
        fecha_vencimiento < CURRENT_DATE
        OR (
          dias_alert_caducidad IS NOT NULL
          AND dias_alert_caducidad > 0
          AND fecha_vencimiento <= (CURRENT_DATE + (dias_alert_caducidad || ' days')::INTERVAL)
        )
        -- Si no hay umbral, alertar 30 días por defecto
        OR (
          (dias_alert_caducidad IS NULL OR dias_alert_caducidad <= 0)
          AND fecha_vencimiento <= (CURRENT_DATE + INTERVAL '30 days')
          AND fecha_vencimiento >= CURRENT_DATE
        )
      )
  ),
  all_alerts AS (
    SELECT * FROM stock_alerts
    UNION ALL
    SELECT * FROM caducidad_alerts
  ),
  filtered AS (
    SELECT * FROM all_alerts a
    WHERE (p_alert_types IS NULL OR a.alert_type = ANY (p_alert_types))
      AND (p_severities IS NULL OR a.severity = ANY (p_severities))
      AND (NOT p_active_only OR a.severity IN ('critical', 'warning'))
  )
  SELECT json_agg(
    json_build_object(
      'productId', id_producto,
      'productName', product_name,
      'sku', sku,
      'currentStock', current_stock,
      'minStock', min_stock,
      'locationsWithStock', locations_count,
      'severity', severity,
      'alertType', alert_type,
      'message', message,
      'idLote', id_lote,
      'codigoLote', codigo_lote,
      'fechaVencimiento', fecha_vencimiento
    )
    ORDER BY
      CASE severity WHEN 'critical' THEN 1 WHEN 'warning' THEN 2 ELSE 3 END,
      current_stock ASC
  )
  INTO result
  FROM filtered;

  RETURN COALESCE(result, '[]'::json);
END;
$function$;
