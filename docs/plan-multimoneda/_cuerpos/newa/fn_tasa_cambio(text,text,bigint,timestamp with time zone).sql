CREATE OR REPLACE FUNCTION public.fn_tasa_cambio(p_moneda_origen text, p_moneda_destino text DEFAULT 'CUP'::text, p_id_tienda bigint DEFAULT NULL::bigint, p_fecha timestamp with time zone DEFAULT now())
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_origen  text := upper(trim(p_moneda_origen));
  v_destino text := upper(trim(coalesce(p_moneda_destino,'CUP')));
  v_id_origen  bigint;
  v_id_destino bigint;
  v_tasa    numeric;
BEGIN
  IF v_origen = v_destino THEN
    RETURN 1;
  END IF;

  SELECT id INTO v_id_origen  FROM public.tipos_moneda WHERE codigo = v_origen;
  SELECT id INTO v_id_destino FROM public.tipos_moneda WHERE codigo = v_destino;

  -- 1) Tasa por tienda
  IF v_id_origen IS NOT NULL AND v_id_destino IS NOT NULL AND p_id_tienda IS NOT NULL THEN
    SELECT valor_cambio INTO v_tasa
    FROM public.tasa_cambio_extraoficial
    WHERE id_tienda = p_id_tienda
      AND id_moneda_origen = v_id_origen
      AND id_moneda_destino = v_id_destino
      AND activo
      AND created_at <= p_fecha
    ORDER BY created_at DESC
    LIMIT 1;
    IF v_tasa IS NOT NULL AND v_tasa > 0 THEN
      RETURN v_tasa;
    END IF;
  END IF;

  -- 2) Tasa global manual
  SELECT tasa INTO v_tasa
  FROM public.tasas_conversion
  WHERE moneda_origen = v_origen
    AND moneda_destino = v_destino
    AND fecha_actualizacion <= p_fecha
  ORDER BY fecha_actualizacion DESC
  LIMIT 1;
  IF v_tasa IS NOT NULL AND v_tasa > 0 THEN
    RETURN v_tasa;
  END IF;

  -- 3) Tasa automática ("el toque")
  v_tasa := public.fn_tasa_automatica(v_origen, v_destino);
  IF v_tasa IS NOT NULL AND v_tasa > 0 THEN
    RETURN v_tasa;
  END IF;

  -- 4) Sin tasa
  RETURN NULL;
END;
$function$

