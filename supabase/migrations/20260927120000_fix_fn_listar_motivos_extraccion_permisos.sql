-- Fix: fn_listar_motivos_extraccion lanzaba P0001
-- "No tienes permisos para listar motivos de extraccion" (SQLSTATE P0001)
-- para cualquier usuario que no estuviera en app_dat_{gerente,supervisor,almacenero}.
--
-- Diagnostico: es un catalogo GLOBAL de solo lectura (app_nom_motivo_extraccion,
-- sin id_tienda ni datos sensibles) que alimenta el desplegable de motivos en las
-- pantallas de extraccion de inventario. El resto de funciones de catalogo del
-- proyecto (fn_listar_medios_pago, fn_listar_tipos_*, fn_listar_cocinas, ...) no
-- gatean por rol; esta era la anomalia y bloqueaba a roles legitimos que llegaban
-- a la pantalla (p. ej. usuarios no presentes en las 3 tablas de rol por uuid).
--
-- Correccion: se relaja la guarda a "usuario autenticado" y se fija search_path
-- (buena practica en SECURITY DEFINER). No se cambia la firma ni el resultado.

CREATE OR REPLACE FUNCTION public.fn_listar_motivos_extraccion()
 RETURNS TABLE(id bigint, denominacion character varying, descripcion character varying, es_activo boolean, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
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
$function$;
