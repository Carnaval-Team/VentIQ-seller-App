CREATE OR REPLACE FUNCTION public.fn_guardar_tasa_global(p_moneda_origen text, p_moneda_destino text, p_tasa numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_origen  text := upper(trim(p_moneda_origen));
  v_destino text := upper(trim(p_moneda_destino));
BEGIN
  IF NOT public.fn_is_superadmin_full_access() THEN
    RAISE EXCEPTION 'Solo un superadministrador puede modificar la tasa global';
  END IF;

  IF p_tasa IS NULL OR p_tasa <= 0 THEN
    RAISE EXCEPTION 'La tasa debe ser mayor que cero';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.monedas WHERE codigo = v_origen) THEN
    RAISE EXCEPTION 'La moneda origen % no existe', v_origen;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.monedas WHERE codigo = v_destino) THEN
    RAISE EXCEPTION 'La moneda destino % no existe', v_destino;
  END IF;

  INSERT INTO public.tasas_conversion (moneda_origen, moneda_destino, tasa, fecha_actualizacion)
  VALUES (v_origen, v_destino, p_tasa, now());

  RETURN jsonb_build_object('status','success','par', v_origen || '->' || v_destino);
END;
$function$

