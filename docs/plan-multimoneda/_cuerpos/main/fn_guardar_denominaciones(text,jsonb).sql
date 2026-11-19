CREATE OR REPLACE FUNCTION public.fn_guardar_denominaciones(p_codigo text, p_denominaciones jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_codigo text := upper(trim(p_codigo));
  v_item   jsonb;
  v_valor  numeric;
  v_activo boolean;
  v_n       int := 0;
BEGIN
  IF NOT public.fn_is_superadmin_full_access() THEN
    RAISE EXCEPTION 'Solo un superadministrador puede modificar denominaciones';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.monedas WHERE codigo = v_codigo) THEN
    RAISE EXCEPTION 'La moneda % no existe', v_codigo;
  END IF;

  IF p_denominaciones IS NULL OR jsonb_typeof(p_denominaciones) <> 'array' THEN
    RAISE EXCEPTION 'p_denominaciones debe ser un array JSON';
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_denominaciones)
  LOOP
    v_valor  := (v_item->>'denominacion')::numeric;
    v_activo := coalesce((v_item->>'active')::boolean, true);

    IF v_valor IS NULL OR v_valor <= 0 THEN
      RAISE EXCEPTION 'Denominación inválida: %', v_item->>'denominacion';
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.app_dat_denominaciones_moneda
      WHERE codigo_moneda = v_codigo AND denominacion = v_valor
    ) THEN
      UPDATE public.app_dat_denominaciones_moneda
      SET active = v_activo, updated_at = now()
      WHERE codigo_moneda = v_codigo AND denominacion = v_valor;
    ELSE
      INSERT INTO public.app_dat_denominaciones_moneda
        (codigo_moneda, denominacion, active)
      VALUES (v_codigo, v_valor, v_activo);
    END IF;
    v_n := v_n + 1;
  END LOOP;

  RETURN jsonb_build_object('status','success','codigo',v_codigo,'denominaciones',v_n);
END;
$function$

