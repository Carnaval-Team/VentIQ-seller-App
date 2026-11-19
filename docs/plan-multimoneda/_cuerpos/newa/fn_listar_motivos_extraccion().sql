CREATE OR REPLACE FUNCTION public.fn_listar_motivos_extraccion()
 RETURNS TABLE(id bigint, denominacion character varying, descripcion character varying, es_activo boolean, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    -- Verificar que el usuario esté autenticado
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Usuario no autenticado';
    END IF;

    -- Validar que el usuario tenga un rol que permita ver motivos de extracción
    -- Roles permitidos: almacenero, supervisor, gerente
    IF NOT EXISTS (
        SELECT 1 FROM app_dat_almacenero WHERE uuid = auth.uid()
        UNION
        SELECT 1 FROM app_dat_supervisor WHERE uuid = auth.uid()
        UNION
        SELECT 1 FROM app_dat_gerente WHERE uuid = auth.uid()
    ) THEN
        RAISE EXCEPTION 'No tienes permisos para listar motivos de extracción';
    END IF;

    -- Devolver los motivos activos
    RETURN QUERY
    SELECT
        me.id,
        me.denominacion,
        me.descripcion,
        (me.created_at IS NOT NULL) AS es_activo,  -- Asumimos que todos son activos (o puedes agregar un campo `activo`)
        me.created_at
    FROM public.app_nom_motivo_extraccion me
    ORDER BY me.denominacion;
END;
$function$

