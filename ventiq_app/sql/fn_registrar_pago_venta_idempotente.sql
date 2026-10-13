-- ============================================================================
-- fn_registrar_pago_venta_v2 (versión idempotente)
-- ----------------------------------------------------------------------------
-- Nueva función (no modifica fn_registrar_pago_venta, que queda intacta para
-- las apps desplegadas con versiones anteriores):
--   1) Antes de insertar, elimina los pagos previos de la operación que NO
--      estén ya ligados a una liquidación de Cuentas por Cobrar.
--   2) Inserta el desglose recibido.
--   3) Recalcula es_pagada.
--
-- Esto cierra el hueco de _pagosYaRegistrados: si una llamada anterior insertó
-- parcialmente las filas, la siguiente llamada las reescribe completamente en
-- lugar de duplicarlas.
--
-- APLICAR MANUALMENTE en Supabase SQL Editor.
-- Requiere que las columnas moneda/tasa_usd/monto_cup_equivalente ya existan
-- (ver venta_usd.sql).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_registrar_pago_venta_v2(
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

  -- Idempotencia: borrar pagos previos que aún no estén liquidados.
  -- Los pagos con id_liquidacion ya pertenecen a un recibo de CxC y no deben
  -- tocarse.
  DELETE FROM public.app_dat_pago_venta
  WHERE id_operacion_venta = p_id_operacion_venta
    AND id_liquidacion IS NULL;

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

GRANT EXECUTE ON FUNCTION public.fn_registrar_pago_venta_v2(BIGINT, JSONB) TO authenticated;

NOTIFY pgrst, 'reload schema';
