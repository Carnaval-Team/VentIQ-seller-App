CREATE OR REPLACE FUNCTION public.fn_actualizar_moneda(p_codigo text, p_nombre text DEFAULT NULL::text, p_simbolo text DEFAULT NULL::text, p_pais text DEFAULT NULL::text, p_decimales integer DEFAULT NULL::integer, p_orden integer DEFAULT NULL::integer, p_activo boolean DEFAULT NULL::boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_codigo text := upper(trim(p_codigo));
  v_es_base boolean;
  v_pagos   bigint;
BEGIN
  IF NOT public.fn_is_superadmin_full_access() THEN
    RAISE EXCEPTION 'Solo un superadministrador puede modificar monedas';
  END IF;

  SELECT es_base INTO v_es_base FROM public.monedas WHERE codigo = v_codigo;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La moneda % no existe', v_codigo;
  END IF;

  IF p_activo IS FALSE THEN
    IF v_es_base THEN
      RAISE EXCEPTION 'No se puede desactivar la moneda base (%)', v_codigo;
    END IF;
    SELECT count(*) INTO v_pagos FROM public.app_dat_pago_venta WHERE moneda = v_codigo;
    IF v_pagos > 0 THEN
      RAISE EXCEPTION 'No se puede desactivar %: tiene % pagos registrados', v_codigo, v_pagos;
    END IF;
  END IF;

  UPDATE public.monedas SET
    nombre         = coalesce(nullif(trim(p_nombre),''), nombre),
    simbolo        = coalesce(nullif(trim(p_simbolo),''), simbolo),
    pais           = coalesce(nullif(trim(p_pais),''), pais),
    decimales      = coalesce(p_decimales, decimales)::smallint,
    orden          = coalesce(p_orden, orden)::smallint,
    activo         = coalesce(p_activo, activo),
    actualizado_en = now()
  WHERE codigo = v_codigo;

  UPDATE public.tipos_moneda SET
    denominacion = coalesce(nullif(trim(p_nombre),''), denominacion),
    activo       = coalesce(p_activo, activo),
    updated_at   = now()
  WHERE codigo = v_codigo;

  RETURN jsonb_build_object('status','success','codigo',v_codigo);
END;
$function$

