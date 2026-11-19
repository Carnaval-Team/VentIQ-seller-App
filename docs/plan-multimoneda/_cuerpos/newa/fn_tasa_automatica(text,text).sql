CREATE OR REPLACE FUNCTION public.fn_tasa_automatica(p_origen text, p_destino text DEFAULT 'CUP'::text)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v numeric;
BEGIN
  BEGIN
    v := flow.tasa_factor(upper(trim(p_origen)), upper(trim(p_destino)));
  EXCEPTION WHEN OTHERS THEN
    -- El esquema `flow` es opcional: sin él, la tasa automática no existe.
    RETURN NULL;
  END;

  RETURN NULLIF(v, 0);
END;
$function$

