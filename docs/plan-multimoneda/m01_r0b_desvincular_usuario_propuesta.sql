BEGIN;

-- BORRADOR M01 desvinculación de trabajador. NO EJECUTAR.
-- fn_desvincular_usuario_trabajador no existe en newa. Esta es la semántica:
-- quita el login (uuid) del trabajador y de sus filas de rol, y deja las filas.
-- No borra auth.users, no borra roles y no toca dueño ni superadmin.
-- El actor es auth.uid() y debe poder escribir la tienda del trabajador.

SET LOCAL app.m01_r0b_desvincular_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r0b_desvincular_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador desvincular: NO EJECUTAR sin revision del conjunto M01 en newa';
    END IF;
    IF to_regprocedure('public.fn_config_tienda_puede_escribir(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Falta fn_config_tienda_puede_escribir';
    END IF;
    IF to_regprocedure('public.fn_m01_personal_desvincular_usuario_trabajador(bigint,bigint)') IS NOT NULL
       OR to_regprocedure('public.fn_desvincular_usuario_trabajador(bigint,bigint)') IS NOT NULL THEN
        RAISE EXCEPTION 'La desvinculacion ya existe; no reemplazarla a ciegas';
    END IF;
END;
$preflight$;

CREATE FUNCTION public.fn_m01_personal_desvincular_usuario_trabajador(
    p_trabajador_id bigint,
    p_id_tienda bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_uuid uuid;
    v_store bigint;
    v_deleted timestamptz;
BEGIN
    IF auth.uid() IS NULL OR p_trabajador_id IS NULL OR p_id_tienda IS NULL THEN
        RAISE EXCEPTION 'No autorizado para modificar este trabajador' USING ERRCODE = '42501';
    END IF;
    SELECT w.uuid, w.id_tienda, w.deleted_at
    INTO v_uuid, v_store, v_deleted
    FROM public.app_dat_trabajadores w
    WHERE w.id = p_trabajador_id
    FOR UPDATE;
    IF NOT FOUND OR v_store IS NULL OR v_store IS DISTINCT FROM p_id_tienda
       OR v_deleted IS NOT NULL
       OR public.fn_config_tienda_puede_escribir(v_store) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'No autorizado para modificar este trabajador' USING ERRCODE = '42501';
    END IF;
    IF EXISTS (SELECT 1 FROM public.app_dat_dueno d WHERE d.id_trabajador = p_trabajador_id)
       OR (v_uuid IS NOT NULL AND EXISTS (
           SELECT 1 FROM public.app_dat_superadmin s WHERE s.uuid = v_uuid
       )) THEN
        RAISE EXCEPTION 'No autorizado para modificar este trabajador' USING ERRCODE = '42501';
    END IF;
    IF v_uuid IS NULL THEN
        RETURN jsonb_build_object('success', true, 'idempotent', true);
    END IF;
    UPDATE public.app_dat_trabajadores
       SET uuid = NULL
     WHERE id = p_trabajador_id;
    UPDATE public.app_dat_vendedor
       SET uuid = NULL
     WHERE id_trabajador = p_trabajador_id AND uuid IS NOT NULL;
    UPDATE public.app_dat_almacenero
       SET uuid = NULL
     WHERE id_trabajador = p_trabajador_id AND uuid IS NOT NULL;
    UPDATE public.app_dat_supervisor
       SET uuid = NULL
     WHERE id_trabajador = p_trabajador_id AND uuid IS NOT NULL;
    UPDATE public.auditor
       SET uuid = NULL
     WHERE id_trabajador = p_trabajador_id AND uuid IS NOT NULL;
    UPDATE public.app_dat_gerente
       SET uuid = NULL
     WHERE id_trabajador = p_trabajador_id AND uuid IS NOT NULL;
    UPDATE public.app_dat_jefe_cocina
       SET uuid = NULL
     WHERE id_trabajador = p_trabajador_id AND uuid IS NOT NULL;
    UPDATE public.app_dat_recursos_humanos
       SET uuid = NULL
     WHERE id_trabajador = p_trabajador_id AND uuid IS NOT NULL;
    RETURN jsonb_build_object('success', true, 'idempotent', false);
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_m01_personal_desvincular_usuario_trabajador(bigint,bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_personal_desvincular_usuario_trabajador(bigint,bigint) TO authenticated;

COMMIT;
