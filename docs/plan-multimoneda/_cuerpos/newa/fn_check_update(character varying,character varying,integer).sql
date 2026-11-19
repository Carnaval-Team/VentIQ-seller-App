CREATE OR REPLACE FUNCTION public.fn_check_update(p_app_name character varying, p_version_actual character varying, p_build_actual integer)
 RETURNS json
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_latest RECORD;
    v_hay_update BOOLEAN := FALSE;
BEGIN
    -- Obtener última versión activa
    SELECT * INTO v_latest
    FROM app_versiones
    WHERE app_name = p_app_name AND activa = TRUE
    ORDER BY build_number DESC
    LIMIT 1;
    
    -- Verificar si hay actualización
    IF FOUND AND v_latest.build_number > p_build_actual THEN
        v_hay_update := TRUE;
    END IF;
    
    RETURN json_build_object(
        'hay_actualizacion', v_hay_update,
        'version_disponible', COALESCE(v_latest.version_actual, ''),
        'obligatoria', COALESCE(v_latest.actualizacion_obligatoria, false),
        'version_minima', COALESCE(v_latest.version_minima, ''),
        'fecha_lanzamiento', COALESCE(v_latest.fecha_lanzamiento, NOW())
    );
END;
$function$

