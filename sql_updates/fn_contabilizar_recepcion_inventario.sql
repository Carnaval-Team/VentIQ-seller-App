-- ============================================================================
-- Contabilización de inventario para recepciones (línea a línea, idempotente)
-- ============================================================================
-- Usado al COMPLETAR (todas las líneas) y al REPARAR (solo faltantes).
-- Cada línea se procesa de forma independiente: si una falla, se registra el
-- error y se continúa con las demás.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_contabilizar_linea_recepcion_inventario(
  p_id_recepcion_producto bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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

  SELECT COALESCE((
    SELECT ip.cantidad_final::numeric
    FROM app_dat_inventario_productos ip
    WHERE ip.id_producto = v_rp.id_producto
      AND (ip.id_variante IS NOT DISTINCT FROM v_rp.id_variante)
      AND (ip.id_opcion_variante IS NOT DISTINCT FROM v_rp.id_opcion_variante)
      AND (ip.id_presentacion IS NOT DISTINCT FROM v_id_presentacion)
      AND (ip.id_ubicacion IS NOT DISTINCT FROM v_rp.id_ubicacion)
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
$$;


CREATE OR REPLACE FUNCTION public.fn_contabilizar_recepcion_inventario(
  p_id_operacion bigint,
  p_solo_faltantes boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_linea RECORD;
  v_result jsonb;
  v_detalle jsonb := '[]'::jsonb;
  v_total int := 0;
  v_exitosas int := 0;
  v_omitidas int := 0;
  v_fallidas int := 0;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM app_dat_operacion_recepcion orp
    WHERE orp.id_operacion = p_id_operacion
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'La operación no es una recepción',
      'id_operacion', p_id_operacion
    );
  END IF;

  FOR v_linea IN
    SELECT rp.id AS id_recepcion_producto
    FROM app_dat_recepcion_productos rp
    WHERE rp.id_operacion = p_id_operacion
    ORDER BY rp.id
  LOOP
    IF p_solo_faltantes AND EXISTS (
      SELECT 1
      FROM app_dat_inventario_productos inv
      WHERE inv.id_recepcion = v_linea.id_recepcion_producto
    ) THEN
      v_total := v_total + 1;
      v_omitidas := v_omitidas + 1;
      v_result := jsonb_build_object(
        'estado', 'OMITIDO',
        'id_recepcion_producto', v_linea.id_recepcion_producto,
        'mensaje', 'Ya contabilizado en inventario'
      );
      v_detalle := v_detalle || jsonb_build_array(v_result);
      CONTINUE;
    END IF;

    v_total := v_total + 1;
    v_result := fn_contabilizar_linea_recepcion_inventario(
      v_linea.id_recepcion_producto
    );

    CASE v_result->>'estado'
      WHEN 'OK' THEN v_exitosas := v_exitosas + 1;
      WHEN 'OMITIDO' THEN v_omitidas := v_omitidas + 1;
      ELSE v_fallidas := v_fallidas + 1;
    END CASE;

    v_detalle := v_detalle || jsonb_build_array(v_result);
  END LOOP;

  RETURN jsonb_build_object(
    'success', v_fallidas = 0,
    'id_operacion', p_id_operacion,
    'solo_faltantes', p_solo_faltantes,
    'total_lineas', v_total,
    'exitosas', v_exitosas,
    'omitidas', v_omitidas,
    'fallidas', v_fallidas,
    'message',
      CASE
        WHEN v_fallidas = 0 AND v_exitosas = 0 AND v_omitidas = v_total
          THEN 'Todas las líneas ya estaban contabilizadas'
        WHEN v_fallidas = 0
          THEN format(
            'Contabilización completada: %s nuevas, %s omitidas',
            v_exitosas,
            v_omitidas
          )
        ELSE format(
          'Contabilización con errores: %s exitosas, %s fallidas, %s omitidas',
          v_exitosas,
          v_fallidas,
          v_omitidas
        )
      END,
    'detalle', v_detalle
  );
END;
$$;


-- Alias explícito para reparación desde auditoría
CREATE OR REPLACE FUNCTION public.fn_reparar_recepcion_inventario_faltante(
  p_id_operacion bigint
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT fn_contabilizar_recepcion_inventario(p_id_operacion, true);
$$;

GRANT EXECUTE ON FUNCTION public.fn_contabilizar_linea_recepcion_inventario(bigint)
  TO PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_contabilizar_recepcion_inventario(bigint, boolean)
  TO PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_reparar_recepcion_inventario_faltante(bigint)
  TO PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.fn_contabilizar_recepcion_inventario(bigint, boolean) IS
  'Contabiliza líneas de recepción en inventario. p_solo_faltantes=true solo procesa las que no tienen kardex.';
COMMENT ON FUNCTION public.fn_reparar_recepcion_inventario_faltante(bigint) IS
  'Repara movimientos faltantes de una recepción completada. Continúa aunque alguna línea falle.';
