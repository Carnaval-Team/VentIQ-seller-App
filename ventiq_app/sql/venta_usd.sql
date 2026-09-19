ALTER TABLE public.app_dat_pago_venta
  ADD COLUMN IF NOT EXISTS moneda TEXT NOT NULL DEFAULT 'CUP',
  ADD COLUMN IF NOT EXISTS tasa_usd NUMERIC,
  ADD COLUMN IF NOT EXISTS monto_cup_equivalente NUMERIC;

ALTER TABLE public.app_dat_caja_turno
  ADD COLUMN IF NOT EXISTS efectivo_inicial_usd NUMERIC DEFAULT 0,
  ADD COLUMN IF NOT EXISTS efectivo_real_usd NUMERIC,
  ADD COLUMN IF NOT EXISTS diferencia_usd NUMERIC;

UPDATE public.app_dat_pago_venta
SET moneda = 'CUP',
    monto_cup_equivalente = monto
WHERE monto_cup_equivalente IS NULL;

ALTER TABLE public.app_dat_pago_venta
  DROP CONSTRAINT IF EXISTS app_dat_pago_venta_moneda_check;
ALTER TABLE public.app_dat_pago_venta
  ADD CONSTRAINT app_dat_pago_venta_moneda_check CHECK (moneda IN ('CUP', 'USD'));

CREATE OR REPLACE FUNCTION public.fn_registrar_pago_venta(
  p_id_operacion_venta BIGINT,
  p_pagos JSONB
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pago JSONB;
  v_importe_total NUMERIC;
  v_total_pagos_cup NUMERIC := 0;
  v_uuid_usuario UUID;
  v_id_medio_pago SMALLINT;
  v_moneda TEXT;
  v_tasa NUMERIC;
  v_monto NUMERIC;
  v_monto_cup NUMERIC;
BEGIN
  SELECT ov.importe_total, o.uuid
  INTO v_importe_total, v_uuid_usuario
  FROM public.app_dat_operacion_venta ov
  JOIN public.app_dat_operaciones o ON o.id = ov.id_operacion
  WHERE ov.id_operacion = p_id_operacion_venta;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Venta con id_operacion % no encontrada', p_id_operacion_venta;
  END IF;
  IF v_importe_total IS NULL THEN
    RAISE EXCEPTION 'La venta no tiene un importe_total definido';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.app_dat_vendedor WHERE uuid = v_uuid_usuario) THEN
    RAISE EXCEPTION 'El usuario que creó la venta no está registrado como vendedor';
  END IF;
  IF p_pagos IS NULL OR jsonb_typeof(p_pagos) <> 'array' THEN
    RETURN FALSE;
  END IF;

  FOR v_pago IN SELECT value FROM jsonb_array_elements(p_pagos)
  LOOP
    v_id_medio_pago := (v_pago->>'id_medio_pago')::SMALLINT;
    v_moneda := CASE WHEN UPPER(COALESCE(v_pago->>'moneda', 'CUP')) = 'USD' THEN 'USD' ELSE 'CUP' END;
    v_tasa := NULLIF(v_pago->>'tasa_usd', '')::NUMERIC;
    v_monto := COALESCE(NULLIF(v_pago->>'monto', '')::NUMERIC, 0);

    IF NOT EXISTS (
      SELECT 1 FROM public.app_nom_medio_pago
      WHERE id = v_id_medio_pago AND es_activo = TRUE
    ) THEN
      RAISE EXCEPTION 'Medio de pago con id % no existe o está inactivo', v_id_medio_pago;
    END IF;
    IF v_monto <= 0 THEN
      RAISE EXCEPTION 'El monto del pago debe ser mayor que cero';
    END IF;
    IF v_moneda = 'USD' AND COALESCE(v_tasa, 0) <= 0 THEN
      RAISE EXCEPTION 'La tasa USD debe ser mayor que cero';
    END IF;

    v_monto_cup := CASE WHEN v_moneda = 'USD' THEN v_monto * v_tasa ELSE v_monto END;
    v_total_pagos_cup := v_total_pagos_cup + v_monto_cup;

    INSERT INTO public.app_dat_pago_venta (
      id_operacion_venta, id_medio_pago, monto, referencia_pago,
      id_institucion_financiera, creado_por, tipo_pago,
      importe_sin_descuento, moneda, tasa_usd, monto_cup_equivalente
    ) VALUES (
      p_id_operacion_venta, v_id_medio_pago, v_monto,
      NULLIF(v_pago->>'referencia_pago', ''),
      NULLIF(v_pago->>'id_institucion_financiera', '')::BIGINT,
      v_uuid_usuario,
      COALESCE(NULLIF(v_pago->>'tipo_pago', '')::BIGINT, 1),
      NULLIF(v_pago->>'importe_sin_descuento', '')::NUMERIC,
      v_moneda,
      CASE WHEN v_moneda = 'USD' THEN v_tasa ELSE NULL END,
      v_monto_cup
    );
  END LOOP;

  IF v_total_pagos_cup >= v_importe_total THEN
    UPDATE public.app_dat_operacion_venta
    SET es_pagada = TRUE
    WHERE id_operacion = p_id_operacion_venta;
  END IF;

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_registrar_pago_venta(BIGINT, JSONB) TO authenticated;

CREATE OR REPLACE FUNCTION public.registrar_apertura_turno_usd(
  p_efectivo_inicial NUMERIC,
  p_id_tpv BIGINT,
  p_id_vendedor BIGINT,
  p_usuario UUID,
  p_maneja_inventario BOOLEAN,
  p_productos JSONB,
  p_observaciones TEXT,
  p_efectivo_inicial_usd NUMERIC DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_operacion BIGINT;
BEGIN
  v_operacion := public.registrar_apertura_turno_v3(
    p_efectivo_inicial,
    p_id_tpv,
    p_id_vendedor,
    p_usuario,
    p_maneja_inventario,
    p_productos,
    p_observaciones
  );

  UPDATE public.app_dat_caja_turno
  SET efectivo_inicial_usd = COALESCE(p_efectivo_inicial_usd, 0)
  WHERE id_operacion_apertura = v_operacion;

  RETURN v_operacion;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_cerrar_turno_tpv_usd(
  p_id_tpv BIGINT,
  p_efectivo_real NUMERIC,
  p_usuario UUID,
  p_productos JSONB,
  p_observaciones TEXT,
  p_efectivo_real_usd NUMERIC DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result BOOLEAN;
  v_turno_id BIGINT;
  v_efectivo_esperado_usd NUMERIC;
BEGIN
  SELECT id INTO v_turno_id
  FROM public.app_dat_caja_turno
  WHERE id_tpv = p_id_tpv
    AND estado = 1
    AND creado_por = p_usuario
  ORDER BY fecha_apertura DESC
  LIMIT 1;

  SELECT COALESCE(SUM(pv.monto), 0) INTO v_efectivo_esperado_usd
  FROM public.app_dat_pago_venta pv
  JOIN public.app_dat_operacion_venta ov
    ON ov.id_operacion = pv.id_operacion_venta
  JOIN public.app_nom_medio_pago mp ON mp.id = pv.id_medio_pago
  WHERE pv.moneda = 'USD'
    AND mp.es_efectivo = TRUE
    AND ov.id_turno_apertura = v_turno_id;

  v_result := public.fn_cerrar_turno_tpv(
    p_id_tpv,
    p_efectivo_real,
    p_usuario,
    p_productos,
    p_observaciones
  );

  IF COALESCE(v_result, FALSE) AND v_turno_id IS NOT NULL THEN
    UPDATE public.app_dat_caja_turno
    SET efectivo_real_usd = p_efectivo_real_usd,
        diferencia_usd = CASE
          WHEN p_efectivo_real_usd IS NULL THEN NULL
          ELSE p_efectivo_real_usd -
            (COALESCE(efectivo_inicial_usd, 0) + v_efectivo_esperado_usd)
        END
    WHERE id = v_turno_id;
  END IF;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.registrar_apertura_turno_usd(NUMERIC, BIGINT, BIGINT, UUID, BOOLEAN, JSONB, TEXT, NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_cerrar_turno_tpv_usd(BIGINT, NUMERIC, UUID, JSONB, TEXT, NUMERIC) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_apertura_turno_offline_usd(
  p_client_uuid UUID,
  p_efectivo_inicial NUMERIC,
  p_id_tpv BIGINT,
  p_id_vendedor BIGINT,
  p_usuario UUID,
  p_maneja_inventario BOOLEAN DEFAULT FALSE,
  p_productos JSONB DEFAULT '[]'::JSONB,
  p_observaciones TEXT DEFAULT NULL,
  p_fecha_apertura TIMESTAMPTZ DEFAULT NULL,
  p_efectivo_inicial_usd NUMERIC DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSONB;
  v_turno_id BIGINT;
BEGIN
  v_result := public.fn_apertura_turno_offline(
    p_client_uuid, p_efectivo_inicial, p_id_tpv, p_id_vendedor, p_usuario,
    p_maneja_inventario, p_productos, p_observaciones, p_fecha_apertura
  );
  v_turno_id := NULLIF(v_result->>'id_turno', '')::BIGINT;
  IF v_turno_id IS NOT NULL THEN
    UPDATE public.app_dat_caja_turno
    SET efectivo_inicial_usd = COALESCE(p_efectivo_inicial_usd, 0)
    WHERE id = v_turno_id;
  END IF;
  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_cerrar_turno_offline_usd(
  p_client_uuid UUID,
  p_id_tpv BIGINT,
  p_efectivo_real NUMERIC,
  p_usuario UUID,
  p_productos JSONB DEFAULT '[]'::JSONB,
  p_observaciones TEXT DEFAULT NULL,
  p_fecha_cierre TIMESTAMPTZ DEFAULT NULL,
  p_efectivo_real_usd NUMERIC DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSONB;
  v_turno_id BIGINT;
  v_efectivo_esperado_usd NUMERIC := 0;
BEGIN
  SELECT id INTO v_turno_id
  FROM public.app_dat_caja_turno
  WHERE id_tpv = p_id_tpv AND estado = 1
  ORDER BY fecha_apertura DESC NULLS LAST
  LIMIT 1;

  SELECT COALESCE(SUM(pv.monto), 0) INTO v_efectivo_esperado_usd
  FROM public.app_dat_pago_venta pv
  JOIN public.app_dat_operacion_venta ov
    ON ov.id_operacion = pv.id_operacion_venta
  JOIN public.app_nom_medio_pago mp ON mp.id = pv.id_medio_pago
  WHERE pv.moneda = 'USD'
    AND mp.es_efectivo = TRUE
    AND ov.id_turno_apertura = v_turno_id;

  v_result := public.fn_cerrar_turno_offline(
    p_client_uuid, p_id_tpv, p_efectivo_real, p_usuario,
    p_productos, p_observaciones, p_fecha_cierre
  );

  IF v_turno_id IS NOT NULL AND (v_result->>'status') = 'success' THEN
    UPDATE public.app_dat_caja_turno
    SET efectivo_real_usd = p_efectivo_real_usd,
        diferencia_usd = CASE
          WHEN p_efectivo_real_usd IS NULL THEN NULL
          ELSE p_efectivo_real_usd -
            (COALESCE(efectivo_inicial_usd, 0) + v_efectivo_esperado_usd)
        END
    WHERE id = v_turno_id;
  END IF;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_apertura_turno_offline_usd(UUID, NUMERIC, BIGINT, BIGINT, UUID, BOOLEAN, JSONB, TEXT, TIMESTAMPTZ, NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_cerrar_turno_offline_usd(UUID, BIGINT, NUMERIC, UUID, JSONB, TEXT, TIMESTAMPTZ, NUMERIC) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_resumen_diario_cierre_v3(
  id_tpv_param BIGINT DEFAULT NULL,
  id_usuario_param UUID DEFAULT NULL
)
RETURNS TABLE(
  ventas_totales NUMERIC,
  efectivo_inicial NUMERIC,
  efectivo_real NUMERIC,
  efectivo_esperado NUMERIC,
  productos_vendidos NUMERIC,
  ticket_promedio NUMERIC,
  porcentaje_efectivo NUMERIC,
  porcentaje_otros NUMERIC,
  operaciones_totales INTEGER,
  operaciones_por_hora NUMERIC,
  promedio_operaciones_por_hora NUMERIC,
  conciliacion_estado TEXT,
  efectivo_real_ajustado NUMERIC,
  diferencia_ajustada NUMERIC,
  turno_id BIGINT,
  fecha_apertura TIMESTAMPTZ,
  horas_transcurridas NUMERIC,
  productos_vendidos_base NUMERIC,
  productos_vendidos_desglose TEXT,
  ventas_usd NUMERIC,
  efectivo_usd_esperado NUMERIC,
  digital_usd NUMERIC
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH base AS (
    SELECT *
    FROM public.fn_resumen_diario_cierre_v2(id_tpv_param, id_usuario_param)
  ),
  usd AS (
    SELECT
      b.turno_id,
      COALESCE(SUM(pv.monto) FILTER (WHERE pv.moneda = 'USD'), 0) AS ventas_usd,
      COALESCE(MAX(ct.efectivo_inicial_usd), 0) +
        COALESCE(SUM(pv.monto) FILTER (
          WHERE pv.moneda = 'USD' AND mp.es_efectivo = TRUE
        ), 0) AS efectivo_usd_esperado,
      COALESCE(SUM(pv.monto) FILTER (
        WHERE pv.moneda = 'USD' AND mp.es_efectivo = FALSE
      ), 0) AS digital_usd
    FROM base b
    LEFT JOIN public.app_dat_caja_turno ct ON ct.id = b.turno_id
    LEFT JOIN public.app_dat_operacion_venta ov
      ON ov.id_turno_apertura = b.turno_id
    LEFT JOIN public.app_dat_pago_venta pv
      ON pv.id_operacion_venta = ov.id_operacion
    LEFT JOIN public.app_nom_medio_pago mp ON mp.id = pv.id_medio_pago
    GROUP BY b.turno_id
  )
  SELECT
    b.ventas_totales, b.efectivo_inicial, b.efectivo_real,
    b.efectivo_esperado, b.productos_vendidos, b.ticket_promedio,
    b.porcentaje_efectivo, b.porcentaje_otros, b.operaciones_totales,
    b.operaciones_por_hora, b.promedio_operaciones_por_hora,
    b.conciliacion_estado, b.efectivo_real_ajustado,
    b.diferencia_ajustada, b.turno_id, b.fecha_apertura,
    b.horas_transcurridas, b.productos_vendidos_base,
    b.productos_vendidos_desglose,
    COALESCE(u.ventas_usd, 0), COALESCE(u.efectivo_usd_esperado, 0),
    COALESCE(u.digital_usd, 0)
  FROM base b
  LEFT JOIN usd u ON u.turno_id IS NOT DISTINCT FROM b.turno_id;
$$;

GRANT EXECUTE ON FUNCTION public.fn_resumen_diario_cierre_v3(BIGINT, UUID) TO authenticated;

DROP FUNCTION IF EXISTS public.get_sale_payments2(BIGINT);
CREATE FUNCTION public.get_sale_payments2(p_operacion_venta_id BIGINT)
RETURNS TABLE(
  payment_id BIGINT,
  monto NUMERIC,
  referencia_pago VARCHAR,
  fecha_pago TIMESTAMPTZ,
  institucion_financiera_id BIGINT,
  medio_pago_id SMALLINT,
  medio_pago_denominacion VARCHAR,
  medio_pago_descripcion TEXT,
  medio_pago_es_digital BOOLEAN,
  medio_pago_es_efectivo BOOLEAN,
  medio_pago_es_activo BOOLEAN,
  importe_sin_descuento NUMERIC,
  moneda TEXT,
  tasa_usd NUMERIC,
  monto_cup_equivalente NUMERIC
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    pv.id, pv.monto, pv.referencia_pago, pv.fecha_pago,
    pv.id_institucion_financiera, mp.id, mp.denominacion, mp.descripcion,
    mp.es_digital, mp.es_efectivo, mp.es_activo, pv.importe_sin_descuento,
    pv.moneda, pv.tasa_usd, pv.monto_cup_equivalente
  FROM public.app_dat_pago_venta pv
  JOIN public.app_nom_medio_pago mp ON mp.id = pv.id_medio_pago
  WHERE pv.id_operacion_venta = p_operacion_venta_id;
$$;

GRANT EXECUTE ON FUNCTION public.get_sale_payments2(BIGINT) TO authenticated;
