BEGIN;

-- BORRADOR M01 columnas de app_dat_tienda. NO EJECUTAR.
-- Requiere la policy m01_tienda_actualizar del script 10.
-- El authenticated solo actualiza el perfil. Validación, prueba, catálogo
-- exclusivo y el vínculo Carnaval quedan en funciones de superadmin.
-- No crea columnas.

SET LOCAL app.m01_r0e_tienda_columnas_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r0e_tienda_columnas_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador columnas de tienda: NO EJECUTAR sin revision del conjunto M01 en newa';
    END IF;
    IF to_regprocedure('public.fn_is_superadmin_full_access()') IS NULL THEN
        RAISE EXCEPTION 'Falta fn_is_superadmin_full_access';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_policy
        WHERE polrelid = 'public.app_dat_tienda'::regclass
          AND polname = 'm01_tienda_actualizar'
    ) THEN
        RAISE EXCEPTION 'Falta la policy del script 10';
    END IF;
    IF to_regprocedure('public.fn_m01_vincular_tienda_carnaval(bigint,bigint)') IS NOT NULL
       OR to_regprocedure('public.fn_m01_desvincular_tienda_carnaval(bigint)') IS NOT NULL
       OR to_regprocedure('public.fn_m01_validar_tienda_catalogo(bigint,boolean)') IS NOT NULL
       OR to_regprocedure('public.fn_m01_marcar_tienda_prueba(bigint,boolean)') IS NOT NULL THEN
        RAISE EXCEPTION 'Una funcion de columnas de tienda ya existe';
    END IF;
END;
$preflight$;

REVOKE UPDATE ON TABLE public.app_dat_tienda FROM PUBLIC, anon, authenticated;
GRANT UPDATE (
    denominacion, direccion, ubicacion, imagen_url, phone,
    pais, estado, nombre_pais, nombre_estado, latitude, longitude,
    mostrar_en_catalogo, layout_catalogo, dias_trabajo,
    hora_apertura, hora_cierre, provincia
) ON TABLE public.app_dat_tienda TO authenticated;

CREATE FUNCTION public.fn_m01_vincular_tienda_carnaval(
    p_id_tienda bigint,
    p_id_carnaval bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
    IF auth.uid() IS NULL OR p_id_tienda IS NULL OR p_id_carnaval IS NULL
       OR public.fn_is_superadmin_full_access() IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    UPDATE public.app_dat_tienda
       SET admin_carnaval = true, id_tienda_carnaval = p_id_carnaval
     WHERE id = p_id_tienda
       AND (admin_carnaval IS DISTINCT FROM true
            OR id_tienda_carnaval IS DISTINCT FROM p_id_carnaval);
    IF NOT FOUND AND NOT EXISTS (
        SELECT 1 FROM public.app_dat_tienda WHERE id = p_id_tienda
    ) THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE FUNCTION public.fn_m01_desvincular_tienda_carnaval(p_id_tienda bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
    IF auth.uid() IS NULL OR p_id_tienda IS NULL
       OR public.fn_is_superadmin_full_access() IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    UPDATE public.app_dat_tienda
       SET admin_carnaval = false, id_tienda_carnaval = NULL
     WHERE id = p_id_tienda
       AND (admin_carnaval IS DISTINCT FROM false OR id_tienda_carnaval IS NOT NULL);
    IF NOT FOUND AND NOT EXISTS (
        SELECT 1 FROM public.app_dat_tienda WHERE id = p_id_tienda
    ) THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE FUNCTION public.fn_m01_validar_tienda_catalogo(
    p_id_tienda bigint,
    p_validada boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
    IF auth.uid() IS NULL OR p_id_tienda IS NULL OR p_validada IS NULL
       OR public.fn_is_superadmin_full_access() IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    UPDATE public.app_dat_tienda
       SET validada = p_validada
     WHERE id = p_id_tienda AND validada IS DISTINCT FROM p_validada;
    IF NOT FOUND AND NOT EXISTS (
        SELECT 1 FROM public.app_dat_tienda WHERE id = p_id_tienda
    ) THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    RETURN jsonb_build_object('success', true);
END;
$function$;

CREATE FUNCTION public.fn_m01_marcar_tienda_prueba(
    p_id_tienda bigint,
    p_es_prueba boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
    IF auth.uid() IS NULL OR p_id_tienda IS NULL OR p_es_prueba IS NULL
       OR public.fn_is_superadmin_full_access() IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    UPDATE public.app_dat_tienda
       SET es_prueba = p_es_prueba
     WHERE id = p_id_tienda AND es_prueba IS DISTINCT FROM p_es_prueba;
    IF NOT FOUND AND NOT EXISTS (
        SELECT 1 FROM public.app_dat_tienda WHERE id = p_id_tienda
    ) THEN
        RAISE EXCEPTION 'Solicitud no autorizada' USING ERRCODE = '42501';
    END IF;
    RETURN jsonb_build_object('success', true);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_m01_vincular_tienda_carnaval(bigint,bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_vincular_tienda_carnaval(bigint,bigint) TO authenticated;
REVOKE ALL ON FUNCTION public.fn_m01_desvincular_tienda_carnaval(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_desvincular_tienda_carnaval(bigint) TO authenticated;
REVOKE ALL ON FUNCTION public.fn_m01_validar_tienda_catalogo(bigint,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_validar_tienda_catalogo(bigint,boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.fn_m01_marcar_tienda_prueba(bigint,boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_marcar_tienda_prueba(bigint,boolean) TO authenticated;

COMMIT;
