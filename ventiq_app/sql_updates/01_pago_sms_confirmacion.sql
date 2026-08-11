-- ============================================================================
-- Confirmación de pago por SMS (PAGOxMOVIL)
-- ============================================================================
-- Guarda el SMS de confirmación del banco, ya parseado, en la operación de
-- venta a la que corresponde.
--
-- Notas de diseño:
--
-- 1. NO se reutiliza `es_pagada`: esa columna ya está en TRUE en el 100% de
--    las filas (la setea fn_registrar_venta), así que no distingue una venta
--    confirmada por SMS de una que no. La señal de "pago confirmado por SMS"
--    es `pago_sms_json IS NOT NULL`.
--
-- 2. La confirmación es INFORMATIVA: una venta puede cerrarse sin SMS. La
--    columna es nullable y no hay constraint que obligue a llenarla.
--
-- 3. El `nro_transaccion_banco` es el identificador único del pago. El índice
--    unique parcial impide que un mismo SMS se use para confirmar dos ventas
--    distintas (colisión real cuando hay dos ventas del mismo monto en la
--    misma ventana de tiempo).
--
-- Aplicar manualmente en Supabase.
-- ============================================================================

-- 1) Columna con el SMS parseado -------------------------------------------
ALTER TABLE app_dat_operacion_venta
  ADD COLUMN IF NOT EXISTS pago_sms_json jsonb;

COMMENT ON COLUMN app_dat_operacion_venta.pago_sms_json IS
  'SMS de confirmación de PAGOxMOVIL parseado a JSON. NULL = pago no '
  'confirmado por SMS (informativo, no bloquea la venta). Claves: banco, '
  'fecha, entidad, nro_transaccion, nro_transaccion_banco, monto, moneda, '
  'raw_message, received_at, matched_at.';

-- 2) Unicidad del pago bancario -------------------------------------------
-- Un `nro_transaccion_banco` no puede confirmar dos operaciones.
CREATE UNIQUE INDEX IF NOT EXISTS uq_operacion_venta_sms_tx_banco
  ON app_dat_operacion_venta ((pago_sms_json ->> 'nro_transaccion_banco'))
  WHERE pago_sms_json IS NOT NULL;

-- 3) Índice para listar ventas confirmadas/no confirmadas ------------------
CREATE INDEX IF NOT EXISTS idx_operacion_venta_sms_confirmado
  ON app_dat_operacion_venta (id_tpv, created_at DESC)
  WHERE pago_sms_json IS NOT NULL;

-- ============================================================================
-- 4) RPC de conciliación
-- ============================================================================
-- Adjunta el SMS a una operación de venta. Se hace por RPC en lugar de un
-- UPDATE directo desde el cliente para que la validación de monto y la
-- detección de SMS ya usado vivan en un solo lugar.
--
-- Devuelve jsonb:
--   { "status": "success",   "id_operacion": N }
--   { "status": "duplicate", "id_operacion": N }  -- SMS ya usado en otra venta
--   { "status": "mismatch",  "esperado": X, "recibido": Y }
--   { "status": "not_found" }
-- ============================================================================
CREATE OR REPLACE FUNCTION fn_confirmar_pago_sms(
  p_id_operacion bigint,
  p_sms_json     jsonb,
  p_tolerancia   numeric DEFAULT 0.01
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tx_banco   text;
  v_monto_sms  numeric;
  v_total      numeric;
  v_existente  bigint;
BEGIN
  v_tx_banco  := p_sms_json ->> 'nro_transaccion_banco';
  v_monto_sms := (p_sms_json ->> 'monto')::numeric;

  IF v_tx_banco IS NULL OR v_tx_banco = '' THEN
    RETURN jsonb_build_object(
      'status', 'error',
      'message', 'nro_transaccion_banco requerido'
    );
  END IF;

  -- ¿Este SMS ya confirmó alguna venta?
  SELECT id_operacion INTO v_existente
    FROM app_dat_operacion_venta
   WHERE pago_sms_json ->> 'nro_transaccion_banco' = v_tx_banco
   LIMIT 1;

  IF v_existente IS NOT NULL THEN
    RETURN jsonb_build_object(
      'status', 'duplicate',
      'id_operacion', v_existente
    );
  END IF;

  -- Total de la venta. Se prefiere el precio con descuento (lo que el
  -- cliente realmente paga) y se cae a importe_total.
  SELECT COALESCE(precio_con_descuento_total, importe_total)
    INTO v_total
    FROM app_dat_operacion_venta
   WHERE id_operacion = p_id_operacion;

  IF v_total IS NULL THEN
    RETURN jsonb_build_object('status', 'not_found');
  END IF;

  IF ABS(v_total - v_monto_sms) > p_tolerancia THEN
    RETURN jsonb_build_object(
      'status', 'mismatch',
      'esperado', v_total,
      'recibido', v_monto_sms
    );
  END IF;

  UPDATE app_dat_operacion_venta
     SET pago_sms_json = p_sms_json
                         || jsonb_build_object('matched_at', now())
   WHERE id_operacion = p_id_operacion;

  RETURN jsonb_build_object(
    'status', 'success',
    'id_operacion', p_id_operacion
  );

EXCEPTION
  -- Carrera: otra transacción insertó el mismo tx_banco entre el SELECT y el
  -- UPDATE. El índice unique lo bloquea; lo reportamos como duplicado.
  WHEN unique_violation THEN
    RETURN jsonb_build_object('status', 'duplicate');
END;
$$;

COMMENT ON FUNCTION fn_confirmar_pago_sms IS
  'Adjunta un SMS de PAGOxMOVIL parseado a una operación de venta, validando '
  'que el monto coincida y que el SMS no se haya usado antes.';

GRANT EXECUTE ON FUNCTION fn_confirmar_pago_sms(bigint, jsonb, numeric)
  TO authenticated;
