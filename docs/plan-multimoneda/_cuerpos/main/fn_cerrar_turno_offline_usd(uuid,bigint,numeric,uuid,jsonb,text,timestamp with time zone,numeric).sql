CREATE OR REPLACE FUNCTION public.fn_cerrar_turno_offline_usd(p_client_uuid uuid, p_id_tpv bigint, p_efectivo_real numeric, p_usuario uuid, p_productos jsonb DEFAULT '[]'::jsonb, p_observaciones text DEFAULT NULL::text, p_fecha_cierre timestamp with time zone DEFAULT NULL::timestamp with time zone, p_efectivo_real_usd numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$

