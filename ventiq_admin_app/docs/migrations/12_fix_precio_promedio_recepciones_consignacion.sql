BEGIN;

CREATE OR REPLACE FUNCTION public.fn_actualizar_precio_promedio_recepcion_v3(
  p_id_operacion BIGINT,
  p_productos JSONB
)
RETURNS TABLE (
  success BOOLEAN,
  mensaje TEXT,
  productos_actualizados INTEGER,
  tiempo_ms INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_inicio TIMESTAMPTZ := clock_timestamp();
  v_producto JSONB;
  v_id_presentacion BIGINT;
  v_precio_unitario NUMERIC;
  v_cantidad_recibida NUMERIC;
  v_precio_anterior NUMERIC;
  v_cantidad_anterior NUMERIC;
  v_precio_nuevo NUMERIC;
  v_actualizados INTEGER := 0;
  v_tiempo INTEGER;
BEGIN
  IF public.fn_es_operacion_sin_actualizar_precio_costo(p_id_operacion) THEN
    v_tiempo := (EXTRACT(EPOCH FROM (clock_timestamp() - v_inicio)) * 1000)::INTEGER;
    RETURN QUERY SELECT
      TRUE,
      'La operación es una transferencia, devolución u operación interna; no modifica el costo promedio'::TEXT,
      0,
      v_tiempo;
    RETURN;
  END IF;

  IF p_productos IS NULL OR jsonb_typeof(p_productos) <> 'array' OR jsonb_array_length(p_productos) = 0 THEN
    v_tiempo := (EXTRACT(EPOCH FROM (clock_timestamp() - v_inicio)) * 1000)::INTEGER;
    RETURN QUERY SELECT TRUE, 'No hay productos para procesar'::TEXT, 0, v_tiempo;
    RETURN;
  END IF;

  FOR v_producto IN SELECT value FROM jsonb_array_elements(p_productos)
  LOOP
    v_id_presentacion := NULLIF(v_producto->>'id_presentacion', '')::BIGINT;
    v_precio_unitario := NULLIF(v_producto->>'precio_unitario', '')::NUMERIC;
    v_cantidad_recibida := NULLIF(v_producto->>'cantidad', '')::NUMERIC;

    IF v_id_presentacion IS NULL OR
       v_precio_unitario IS NULL OR v_precio_unitario <= 0 OR
       v_cantidad_recibida IS NULL OR v_cantidad_recibida <= 0 THEN
      CONTINUE;
    END IF;

    SELECT COALESCE(pp.precio_promedio, 0)
    INTO v_precio_anterior
    FROM public.app_dat_producto_presentacion pp
    WHERE pp.id = v_id_presentacion
    FOR UPDATE;

    IF NOT FOUND THEN
      CONTINUE;
    END IF;

    SELECT COALESCE(ip.cantidad_inicial, 0)
    INTO v_cantidad_anterior
    FROM public.app_dat_inventario_productos ip
    WHERE ip.id_presentacion = v_id_presentacion
      AND ip.id_recepcion = p_id_operacion
    ORDER BY ip.created_at DESC, ip.id DESC
    LIMIT 1;

    v_cantidad_anterior := COALESCE(v_cantidad_anterior, 0);

    IF v_precio_anterior <= 0 OR v_cantidad_anterior <= 0 THEN
      v_precio_nuevo := v_precio_unitario;
    ELSE
      v_precio_nuevo :=
        ((v_precio_anterior * v_cantidad_anterior) +
         (v_precio_unitario * v_cantidad_recibida)) /
        (v_cantidad_anterior + v_cantidad_recibida);
    END IF;

    UPDATE public.app_dat_producto_presentacion
    SET precio_promedio = v_precio_nuevo
    WHERE id = v_id_presentacion;

    v_actualizados := v_actualizados + 1;
  END LOOP;

  v_tiempo := (EXTRACT(EPOCH FROM (clock_timestamp() - v_inicio)) * 1000)::INTEGER;

  BEGIN
    INSERT INTO public.app_dat_auditoria_precios (
      id_operacion,
      tipo_operacion,
      cantidad_productos,
      fecha_operacion,
      estado
    ) VALUES (
      p_id_operacion,
      'actualizar_precio_promedio',
      v_actualizados,
      CURRENT_TIMESTAMP,
      'exitosa'
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN QUERY SELECT
    TRUE,
    format('Se actualizaron %s precios promedio', v_actualizados)::TEXT,
    v_actualizados,
    v_tiempo;
EXCEPTION WHEN OTHERS THEN
  v_tiempo := (EXTRACT(EPOCH FROM (clock_timestamp() - v_inicio)) * 1000)::INTEGER;
  RETURN QUERY SELECT
    FALSE,
    format('Error en fn_actualizar_precio_promedio_recepcion_v3: %s', SQLERRM)::TEXT,
    0,
    v_tiempo;
END;
$$;

CREATE OR REPLACE FUNCTION public.configurar_precios_recepcion_consignacion_v2(
  p_id_operacion_recepcion BIGINT,
  p_id_tienda_destino BIGINT,
  p_precios_productos JSONB
)
RETURNS TABLE (
  success BOOLEAN,
  precios_configurados INTEGER,
  mensaje TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_producto RECORD;
  v_precio_venta_cup NUMERIC;
  v_precio_venta_usd NUMERIC;
  v_precio_costo_usd NUMERIC;
  v_es_devolucion BOOLEAN;
  v_count INTEGER := 0;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM public.app_dat_consignacion_envio ce
    WHERE ce.id_operacion_recepcion = p_id_operacion_recepcion
      AND ce.tipo_envio = 2
  ) INTO v_es_devolucion;

  FOR v_producto IN
    SELECT
      rp.id_producto,
      rp.id_presentacion,
      precio.value AS precio_data
    FROM public.app_dat_recepcion_productos rp
    JOIN LATERAL jsonb_array_elements(COALESCE(p_precios_productos, '[]'::JSONB)) precio(value)
      ON NULLIF(precio.value->>'id_producto', '')::BIGINT = rp.id_producto
    WHERE rp.id_operacion = p_id_operacion_recepcion
  LOOP
    v_precio_venta_cup := COALESCE(NULLIF(v_producto.precio_data->>'precio_venta_cup', '')::NUMERIC, 0);
    v_precio_venta_usd := NULLIF(v_producto.precio_data->>'precio_venta_usd', '')::NUMERIC;
    v_precio_costo_usd := COALESCE(NULLIF(v_producto.precio_data->>'precio_costo_usd', '')::NUMERIC, 0);

    UPDATE public.app_dat_recepcion_productos
    SET precio_unitario = v_precio_costo_usd
    WHERE id_operacion = p_id_operacion_recepcion
      AND id_producto = v_producto.id_producto
      AND id_presentacion IS NOT DISTINCT FROM v_producto.id_presentacion;

    IF NOT v_es_devolucion THEN
      UPDATE public.app_dat_precio_venta
      SET fecha_hasta = CURRENT_DATE - INTERVAL '1 day'
      WHERE id_producto = v_producto.id_producto
        AND fecha_hasta IS NULL;

      INSERT INTO public.app_dat_precio_venta (
        id_producto,
        precio_venta_cup,
        precio_venta_usd,
        fecha_desde,
        created_at
      ) VALUES (
        v_producto.id_producto,
        v_precio_venta_cup,
        v_precio_venta_usd,
        CURRENT_DATE,
        CURRENT_TIMESTAMP
      );
    END IF;

    v_count := v_count + 1;
  END LOOP;

  RETURN QUERY SELECT
    TRUE,
    v_count,
    CASE
      WHEN v_es_devolucion THEN 'Devolución configurada sin modificar precios ni costo promedio'
      ELSE 'Precios guardados; el costo promedio se actualizará una sola vez al completar la recepción'
    END::TEXT;
EXCEPTION WHEN OTHERS THEN
  RETURN QUERY SELECT FALSE, 0, ('Error: ' || SQLERRM)::TEXT;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_actualizar_precio_promedio_recepcion_v3(BIGINT, JSONB)
  TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.configurar_precios_recepcion_consignacion_v2(BIGINT, BIGINT, JSONB)
  TO authenticated, service_role;

COMMIT;
