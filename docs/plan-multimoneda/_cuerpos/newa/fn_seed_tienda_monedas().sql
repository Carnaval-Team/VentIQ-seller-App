CREATE OR REPLACE FUNCTION public.fn_seed_tienda_monedas()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO public.app_dat_tienda_moneda (id_tienda, moneda, activo, orden)
  SELECT NEW.id, m.codigo, true,
         CASE m.codigo WHEN 'CUP' THEN 10 WHEN 'USD' THEN 20 ELSE 100 END
  FROM public.monedas m
  WHERE m.codigo IN ('CUP', 'USD')
  ON CONFLICT DO NOTHING;
  RETURN NEW;
END;
$function$

