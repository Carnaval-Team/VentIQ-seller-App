BEGIN;

DO $$
BEGIN
  IF to_regprocedure('public.fn_registrar_recepcion_con_inventario(text,bigint,numeric,integer,text,jsonb,text,uuid,text,bigint,numeric,boolean)') IS NULL
     OR to_regprocedure('public.fn_fdi_crear_inversion(bigint,character varying,text,text,text,jsonb,uuid)') IS NULL THEN
    RAISE EXCEPTION 'Faltan las RPC del esquema FDI o el parche de recepción; revise sus migraciones antes de continuar';
  END IF;
END;
$$;

ALTER TABLE public.app_dat_operacion_recepcion
  ADD COLUMN IF NOT EXISTS fdi_idempotency_key uuid,
  ADD COLUMN IF NOT EXISTS fdi_solicitud jsonb;
CREATE UNIQUE INDEX IF NOT EXISTS idx_recepcion_fdi_idempotency
  ON public.app_dat_operacion_recepcion(fdi_idempotency_key)
  WHERE fdi_idempotency_key IS NOT NULL;

CREATE OR REPLACE FUNCTION public.fn_fdi_registrar_recepcion(
  p_recepcion jsonb,
  p_fuentes jsonb,
  p_idempotency_key uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_tienda bigint := (p_recepcion->>'p_id_tienda')::bigint;
  v_total numeric := (p_recepcion->>'p_monto_total')::numeric;
  v_moneda text := p_recepcion->>'p_moneda_factura';
  v_solicitud jsonb := jsonb_build_object('recepcion', p_recepcion, 'fuentes', p_fuentes);
  v_previa record;
  v_fuente jsonb;
  v_producto jsonb;
  v_saldo numeric;
  v_monto numeric;
  v_tasa numeric;
  v_cubierto numeric := 0;
  v_inversion bigint;
  v_operacion bigint;
  v_result jsonb;
  v_vinculo jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT COALESCE(public.fn_user_is_gerente_or_superadmin(v_tienda), false)
     OR (p_recepcion->>'p_uuid')::uuid IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Solo gerente o superadmin de la tienda' USING ERRCODE = '42501';
  END IF;
  IF p_idempotency_key IS NULL OR v_total IS NULL OR NOT (v_total > 0 AND v_total < 'Infinity'::numeric)
     OR v_total <> round(v_total, 2) OR v_moneda NOT IN ('USD', 'CUP', 'EUR') OR v_moneda IS NULL
     OR p_recepcion->>'p_id_inversion' IS NOT NULL THEN
    RAISE EXCEPTION 'Solicitud de financiación inválida' USING ERRCODE = '22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('fdi-recepcion:' || p_idempotency_key::text, 0));
  SELECT r.id_operacion, r.fdi_solicitud, o.id_tienda, ir.id_inversion
    INTO v_previa
    FROM public.app_dat_operacion_recepcion r
    JOIN public.app_dat_operaciones o ON o.id = r.id_operacion
    LEFT JOIN public.fdi_dat_inversion_recepcion ir ON ir.id_operacion = r.id_operacion
    WHERE r.fdi_idempotency_key = p_idempotency_key;
  IF FOUND THEN
    IF v_previa.id_tienda <> v_tienda OR v_previa.fdi_solicitud IS DISTINCT FROM v_solicitud THEN
      RAISE EXCEPTION 'La clave ya corresponde a otra recepción; revise la operación guardada' USING ERRCODE = '22023';
    END IF;
    RETURN jsonb_build_object('status', 'success', 'id_operacion', v_previa.id_operacion,
      'id_inversion', v_previa.id_inversion, 'duplicada', true);
  END IF;
  IF jsonb_typeof(p_fuentes) IS DISTINCT FROM 'array' OR jsonb_array_length(p_fuentes) = 0 THEN
    RAISE EXCEPTION 'Seleccione fuentes del fondo' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_fuentes) f
    GROUP BY f->>'id_cuenta', f->>'id_medio_pago', f->>'moneda' HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION 'Fuente del fondo repetida' USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(p_recepcion->'p_productos') IS DISTINCT FROM 'array'
     OR jsonb_array_length(p_recepcion->'p_productos') = 0 THEN
    RAISE EXCEPTION 'Debe incluir productos' USING ERRCODE = '22023';
  END IF;
  FOR v_producto IN SELECT * FROM jsonb_array_elements(p_recepcion->'p_productos') LOOP
    IF NOT EXISTS (
      SELECT 1 FROM public.app_dat_layout_almacen l
      JOIN public.app_dat_almacen a ON a.id = l.id_almacen
      WHERE l.id = (v_producto->>'id_ubicacion')::bigint AND a.id_tienda = v_tienda
    ) THEN
      RAISE EXCEPTION 'Ubicación ajena a la tienda' USING ERRCODE = '42501';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.app_dat_producto p
                   WHERE p.id = (v_producto->>'id_producto')::bigint AND p.id_tienda = v_tienda)
       OR NOT COALESCE((v_producto->>'cantidad')::numeric > 0
                      AND (v_producto->>'cantidad')::numeric < 'Infinity'::numeric, false)
       OR NOT COALESCE((v_producto->>'precio_unitario')::numeric >= 0
                      AND (v_producto->>'precio_unitario')::numeric < 'Infinity'::numeric, false) THEN
      RAISE EXCEPTION 'Producto de recepción inválido' USING ERRCODE = '22023';
    END IF;
  END LOOP;
  FOR v_fuente IN SELECT * FROM jsonb_array_elements(p_fuentes)
    ORDER BY (value->>'id_cuenta')::bigint, (value->>'id_medio_pago')::smallint, value->>'moneda'
  LOOP
    v_monto := (v_fuente->>'monto')::numeric;
    v_tasa := (v_fuente->>'tasa_a_ref')::numeric;
    IF v_monto IS NULL OR NOT (v_monto > 0 AND v_monto < 'Infinity'::numeric)
       OR v_monto <> round(v_monto, 2) OR v_tasa IS NULL OR NOT (v_tasa > 0 AND v_tasa < 'Infinity'::numeric)
       OR ((v_fuente->>'moneda') = v_moneda AND v_tasa <> 1) THEN
      RAISE EXCEPTION 'Monto o tasa de fuente inválidos' USING ERRCODE = '22023';
    END IF;
    SELECT s.saldo INTO v_saldo FROM public.fdi_dat_saldo s
      JOIN public.fdi_dat_cuenta c ON c.id = s.id_cuenta
      JOIN public.fdi_dat_concepto co ON co.id = c.id_concepto
      JOIN public.app_nom_medio_pago mp ON mp.id = s.id_medio_pago
      WHERE s.id_tienda = v_tienda AND c.id_tienda = v_tienda AND co.id_tienda = v_tienda
        AND c.activo AND co.activo AND mp.es_activo
        AND s.id_cuenta = (v_fuente->>'id_cuenta')::bigint
        AND s.id_medio_pago = (v_fuente->>'id_medio_pago')::smallint
        AND s.moneda = v_fuente->>'moneda'
      FOR UPDATE OF s;
    IF NOT FOUND OR v_saldo < v_monto THEN
      RAISE EXCEPTION 'Saldo insuficiente o fuente inactiva; actualice los saldos del fondo' USING ERRCODE = 'P0002';
    END IF;
    v_cubierto := v_cubierto + round(v_monto * v_tasa, 2);
  END LOOP;
  IF v_cubierto <> v_total THEN
    RAISE EXCEPTION 'Las fuentes deben cubrir exactamente el monto de recepción' USING ERRCODE = '22023';
  END IF;
  v_result := public.fn_fdi_crear_inversion(
    v_tienda, ('Recepción ' || p_idempotency_key::text)::varchar,
    NULL::text, 'Financiación directa de recepción', v_moneda, p_fuentes, p_idempotency_key);
  IF v_result->>'status' IS DISTINCT FROM 'ok' OR COALESCE((v_result->>'duplicada')::boolean, false) THEN
    RAISE EXCEPTION 'No se pudo crear la financiación de recepción';
  END IF;
  v_inversion := (v_result->>'id_inversion')::bigint;
  UPDATE public.fdi_dat_inversion_fuente SET monto_ref = round(monto * tasa_a_ref, 2)
    WHERE id_inversion = v_inversion;
  UPDATE public.fdi_dat_inversion SET monto_total_ref = v_total WHERE id = v_inversion;
  v_result := public.fn_registrar_recepcion_con_inventario(
    p_entregado_por := p_recepcion->>'p_entregado_por',
    p_id_tienda := v_tienda,
    p_monto_total := v_total,
    p_motivo := (p_recepcion->>'p_motivo')::integer,
    p_observaciones := p_recepcion->>'p_observaciones',
    p_productos := p_recepcion->'p_productos',
    p_recibido_por := p_recepcion->>'p_recibido_por',
    p_uuid := auth.uid(),
    p_moneda_factura := v_moneda,
    p_id_inversion := NULL::bigint,
    p_tasa_inversion := NULL::numeric,
    p_confirmar_exceso_inversion := false);
  IF v_result->>'status' IS DISTINCT FROM 'success' OR v_result->>'id_operacion' IS NULL THEN
    RAISE EXCEPTION 'No se registró la recepción: %', COALESCE(v_result->>'message', v_result::text);
  END IF;
  v_operacion := (v_result->>'id_operacion')::bigint;
  v_vinculo := public.fn_fdi_vincular_recepcion(v_operacion, v_inversion, v_total, v_moneda, 1::numeric, false);
  IF v_vinculo->>'status' IS DISTINCT FROM 'ok' THEN
    RAISE EXCEPTION 'No se vinculó la recepción: %', v_vinculo;
  END IF;
  UPDATE public.app_dat_operacion_recepcion
    SET fdi_idempotency_key = p_idempotency_key, fdi_solicitud = v_solicitud
    WHERE id_operacion = v_operacion;
  UPDATE public.fdi_dat_inversion SET identificador = 'Recepción ' || v_operacion::text WHERE id = v_inversion;
  RETURN v_result || jsonb_build_object('id_inversion', v_inversion, 'financiada_fondo', true);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_fdi_registrar_recepcion(jsonb, jsonb, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_fdi_registrar_recepcion(jsonb, jsonb, uuid) TO authenticated;

COMMIT;
