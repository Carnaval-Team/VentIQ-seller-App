CREATE OR REPLACE FUNCTION public.fn_listar_motivos_extraccion()
 RETURNS TABLE(id bigint, denominacion character varying, descripcion character varying, es_activo boolean, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    -- Solo se exige que el usuario este autenticado.
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Usuario no autenticado';
    END IF;

    -- Devolver los motivos (catalogo global de solo lectura).
    RETURN QUERY
    SELECT
        me.id,
        me.denominacion,
        me.descripcion,
        (me.created_at IS NOT NULL) AS es_activo,
        me.created_at
    FROM public.app_nom_motivo_extraccion me
    ORDER BY me.denominacion;
END;
$function$

