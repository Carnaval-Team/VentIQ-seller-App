CREATE OR REPLACE FUNCTION public.fn_guardar_monedas_tienda(p_id_tienda bigint, p_monedas jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_item    jsonb;
  v_codigo  text;
  v_activo  boolean;
  v_orden   integer;
  v_n       int := 0;
  v_codigos text[] := '{}';
BEGIN
  IF NOT public.fn_user_can_access_tienda(p_id_tienda) THEN
    RAISE EXCEPTION 'No tienes acceso a la tienda %', p_id_tienda;
  END IF;

  IF p_monedas IS NULL OR jsonb_typeof(p_monedas) <> 'array' THEN
    RAISE EXCEPTION 'p_monedas debe ser un array JSON';
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_monedas)
  LOOP
    v_codigo := upper(trim(v_item->>'moneda'));
    v_activo := coalesce((v_item->>'activo')::boolean, true);
    v_orden  := coalesce((v_item->>'orden')::integer, 100);

    IF NOT EXISTS (
      SELECT 1 FROM public.monedas WHERE codigo = v_codigo AND activo
    ) THEN
      RAISE EXCEPTION 'La moneda % no existe o está inactiva en el catálogo', v_codigo;
    END IF;

    INSERT INTO public.app_dat_tienda_moneda
      (id_tienda, moneda, activo, orden, updated_at)
    VALUES
      (p_id_tienda, v_codigo, v_activo, v_orden::smallint, now())
    ON CONFLICT (id_tienda, moneda) DO UPDATE
      SET activo     = excluded.activo,
          orden      = excluded.orden,
          updated_at = now();

    v_codigos := v_codigos || v_codigo;
    v_n := v_n + 1;
  END LOOP;

  -- La tienda siempre debe aceptar CUP: es la moneda base contable.
  IF NOT ('CUP' = ANY (v_codigos)) THEN
    RAISE EXCEPTION 'La tienda debe aceptar CUP (moneda base)';
  END IF;

  UPDATE public.app_dat_tienda_moneda
  SET activo = false, updated_at = now()
  WHERE id_tienda = p_id_tienda
    AND NOT (moneda = ANY (v_codigos))
    AND activo;

  RETURN jsonb_build_object(
    'status', 'success',
    'id_tienda', p_id_tienda,
    'monedas', v_n
  );
END;
$function$

