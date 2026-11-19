CREATE OR REPLACE FUNCTION public.fn_crear_moneda(p_codigo text, p_nombre text, p_simbolo text DEFAULT NULL::text, p_pais text DEFAULT NULL::text, p_decimales integer DEFAULT 2, p_orden integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_codigo text := upper(trim(p_codigo));
  v_nombre text := coalesce(nullif(trim(p_nombre), ''), upper(trim(p_codigo)));
  v_nuevo_id bigint;
BEGIN
  IF NOT public.fn_is_superadmin_full_access() THEN
    RAISE EXCEPTION 'Solo un superadministrador puede crear monedas';
  END IF;

  IF v_codigo !~ '^[A-Z]{3}$' THEN
    RAISE EXCEPTION 'El código debe ser ISO-4217 de 3 letras (recibido: %)', p_codigo;
  END IF;

  IF EXISTS (SELECT 1 FROM public.monedas WHERE codigo = v_codigo) THEN
    RAISE EXCEPTION 'La moneda % ya existe en el catálogo', v_codigo;
  END IF;

  INSERT INTO public.monedas (codigo, nombre, simbolo, pais, activo,
                              decimales, orden, es_base, es_sistema)
  VALUES (v_codigo, v_nombre, nullif(trim(p_simbolo),''), nullif(trim(p_pais),''),
          true, coalesce(p_decimales, 2)::smallint, coalesce(p_orden, 100)::smallint,
          false, false);

  -- Puente para las tasas por tienda. `tipos_moneda.id` no tiene DEFAULT.
  SELECT coalesce(max(id), 0) + 1 INTO v_nuevo_id FROM public.tipos_moneda;

  INSERT INTO public.tipos_moneda (id, denominacion, simbolo, nombre_corto,
                                   pais, activo, codigo)
  VALUES (v_nuevo_id, v_nombre, coalesce(nullif(trim(p_simbolo),''), ''),
          v_codigo, nullif(trim(p_pais),''), true, v_codigo);

  RETURN jsonb_build_object(
    'status', 'success',
    'codigo', v_codigo,
    'id_tipos_moneda', v_nuevo_id
  );
END;
$function$

