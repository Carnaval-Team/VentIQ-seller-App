CREATE OR REPLACE FUNCTION public.fn_tasas_refrescar(p_forzar boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_r  jsonb;
  v_id bigint;
BEGIN
  IF NOT public.fn_is_superadmin_full_access() THEN
    RAISE EXCEPTION 'Solo un superadministrador puede refrescar las tasas';
  END IF;

  BEGIN
    v_r := flow.tasas_refrescar(p_forzar);
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'disponible', false,
      'error', 'El esquema flow no está disponible en este entorno.'
    );
  END;

  IF coalesce(v_r->>'estado','') = 'vigente' THEN
    RETURN public.fn_tasa_automatica_estado();
  END IF;

  v_id := nullif(v_r->>'request_id','')::bigint;

  RETURN jsonb_build_object(
    'disponible', true,
    'ok', true,
    'estado', 'solicitado',
    'request_id', v_id,
    'mensaje', 'Tasa solicitada al proveedor. Se recoge en unos segundos.'
  );
END;
$function$

