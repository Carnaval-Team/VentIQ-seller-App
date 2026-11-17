BEGIN;

-- BORRADOR PARCIAL M01-R0b (identidad de trabajador). NO EJECUTAR aisladamente.
-- Via privilegiada para cambiar a que usuario Auth pertenece un trabajador:
-- sustituye la escritura directa de uuid (WorkerService.updateWorkerUUID) y la
-- parte de identidad de fn_editar_trabajador_basico (INVOKER), que hoy cambian
-- uuid sin coordinar las filas de rol. Aqui el cambio es atomico: el uuid del
-- trabajador y TODAS sus filas de rol (por id_trabajador) quedan coherentes
-- en la misma transaccion, porque uuid representa a la misma persona.
-- Alcance y restricciones deliberadas:
--   * Actor real = auth.uid(); exige fn_config_tienda_puede_escribir sobre la
--     tienda derivada del trabajador, nunca un p_id_tienda declarado.
--   * Rechaza trabajador inexistente, sin tienda o eliminado (deleted_at):
--     la restauracion sigue siendo de fn_restaurar_trabajador.
--   * Rechaza uuid inexistente en auth.users, uuid ya ligado a otro
--     trabajador activo, y trabajadores con fila en app_dat_dueno o uuid en
--     app_dat_superadmin: propiedad y superadministracion no se reasignan
--     por esta via (dominio del predicado de duenos R0a).
--   * La actualizacion de filas de rol es global por id_trabajador: si el
--     trabajador tiene roles en otras tiendas, tambien siguen a la nueva
--     identidad. Dividir la identidad por tienda generaria incoherencia.
--   * Desvincular (uuid NULL) queda fuera: fn_desvincular_usuario_trabajador
--     no existe en newa y su semantica requiere decision aparte.
--   * El trigger trg_sync_trabajador_user_mail deriva user_mail al UPDATE.

SET LOCAL app.m01_r0b_identidad_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r0b_identidad_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador parcial R0b-identidad: requiere revision del conjunto M01 y ejecucion manual en newa';
    END IF;
    IF has_schema_privilege('anon', 'public', 'CREATE')
       OR has_schema_privilege('authenticated', 'public', 'CREATE') THEN
        RAISE EXCEPTION 'public permite CREATE a roles no confiables; revisar antes de aplicar';
    END IF;
    IF to_regprocedure('public.fn_config_tienda_puede_escribir(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Falta el contrato S01; no reemplazarlo por un permiso generico';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'fn_m01_personal_vincular_usuario_trabajador'
    ) THEN
        RAISE EXCEPTION 'La RPC de identidad ya existe; revisar avances de newa';
    END IF;
END;
$preflight$;

CREATE FUNCTION public.fn_m01_personal_vincular_usuario_trabajador(
    p_id_trabajador bigint,
    p_uuid uuid
)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_old_uuid uuid;
    v_id_tienda bigint;
    v_deleted_at timestamptz;
BEGIN
    IF auth.uid() IS NULL OR p_id_trabajador IS NULL OR p_uuid IS NULL THEN
        RAISE EXCEPTION 'No autorizado para modificar este trabajador' USING ERRCODE = '42501';
    END IF;

    SELECT w.uuid, w.id_tienda, w.deleted_at
    INTO v_old_uuid, v_id_tienda, v_deleted_at
    FROM public.app_dat_trabajadores w
    WHERE w.id = p_id_trabajador
    FOR UPDATE;

    IF NOT FOUND OR v_id_tienda IS NULL OR v_deleted_at IS NOT NULL
       OR public.fn_config_tienda_puede_escribir(v_id_tienda) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'No autorizado para modificar este trabajador' USING ERRCODE = '42501';
    END IF;

    IF v_old_uuid IS NOT DISTINCT FROM p_uuid THEN
        RETURN true;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM auth.users u WHERE u.id = p_uuid) THEN
        RAISE EXCEPTION 'No autorizado para modificar este trabajador' USING ERRCODE = '42501';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.app_dat_trabajadores w2
        WHERE w2.uuid = p_uuid
          AND w2.id <> p_id_trabajador
          AND w2.deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'No autorizado para modificar este trabajador' USING ERRCODE = '42501';
    END IF;

    IF EXISTS (SELECT 1 FROM public.app_dat_dueno d WHERE d.id_trabajador = p_id_trabajador)
       OR (v_old_uuid IS NOT NULL AND EXISTS (
           SELECT 1 FROM public.app_dat_superadmin s WHERE s.uuid = v_old_uuid
       )) THEN
        RAISE EXCEPTION 'No autorizado para modificar este trabajador' USING ERRCODE = '42501';
    END IF;

    UPDATE public.app_dat_trabajadores
       SET uuid = p_uuid
     WHERE id = p_id_trabajador;

    UPDATE public.app_dat_vendedor
       SET uuid = p_uuid
     WHERE id_trabajador = p_id_trabajador
       AND uuid IS DISTINCT FROM p_uuid;

    UPDATE public.app_dat_almacenero
       SET uuid = p_uuid
     WHERE id_trabajador = p_id_trabajador
       AND uuid IS DISTINCT FROM p_uuid;

    UPDATE public.app_dat_supervisor
       SET uuid = p_uuid
     WHERE id_trabajador = p_id_trabajador
       AND uuid IS DISTINCT FROM p_uuid;

    UPDATE public.auditor
       SET uuid = p_uuid
     WHERE id_trabajador = p_id_trabajador
       AND uuid IS DISTINCT FROM p_uuid;

    UPDATE public.app_dat_gerente
       SET uuid = p_uuid
     WHERE id_trabajador = p_id_trabajador
       AND uuid IS DISTINCT FROM p_uuid;

    UPDATE public.app_dat_jefe_cocina
       SET uuid = p_uuid
     WHERE id_trabajador = p_id_trabajador
       AND uuid IS DISTINCT FROM p_uuid;

    UPDATE public.app_dat_recursos_humanos
       SET uuid = p_uuid
     WHERE id_trabajador = p_id_trabajador
       AND uuid IS DISTINCT FROM p_uuid;

    RETURN true;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_m01_personal_vincular_usuario_trabajador(bigint, uuid)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_personal_vincular_usuario_trabajador(bigint, uuid)
    TO authenticated;

COMMIT;
