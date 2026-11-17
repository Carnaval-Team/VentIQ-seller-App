BEGIN;

-- BORRADOR PARCIAL M01-R0b (RPC de entrada). NO EJECUTAR aisladamente.
-- Depende de fn_m01_personal_exigir_reasignacion_vendedor (guarda R0b),
-- que a su vez requiere el conjunto M01 revisado antes de aplicarse en newa.
-- La reasignacion queda asi: cliente -> esta RPC -> guarda (auth.uid + ambitos
-- OLD/NEW + coherencia vendedor/trabajador/TPV) -> UPDATE id_tpv.
-- Sin esta pieza la guarda no es invocable por clientes y la escritura directa
-- seguiria siendo la unica via; no es un permiso nuevo, es la unica via futura.

SET LOCAL app.m01_r0b_rpc_approved = 'yes';
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r0b_rpc_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador parcial R0b-RPC: requiere revision del conjunto M01 y ejecucion manual en newa';
    END IF;
    IF has_schema_privilege('anon', 'public', 'CREATE')
       OR has_schema_privilege('authenticated', 'public', 'CREATE') THEN
        RAISE EXCEPTION 'public permite CREATE a roles no confiables; revisar antes de aplicar';
    END IF;
    IF to_regprocedure('public.fn_m01_personal_exigir_reasignacion_vendedor(bigint,bigint)') IS NULL THEN
        RAISE EXCEPTION 'Falta la guarda R0b; aplicar primero m01_r0b_guard_reasignacion_vendedor tras revision';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'fn_m01_personal_reasignar_vendedor'
    ) THEN
        RAISE EXCEPTION 'La RPC ya existe; revisar avances de newa antes de continuar';
    END IF;
END;
$preflight$;

CREATE FUNCTION public.fn_m01_personal_reasignar_vendedor(
    p_id_vendedor bigint,
    p_id_tpv bigint
)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
BEGIN
    PERFORM public.fn_m01_personal_exigir_reasignacion_vendedor(
        p_id_vendedor,
        p_id_tpv
    );

    UPDATE public.app_dat_vendedor v
       SET id_tpv = p_id_tpv
     WHERE v.id = p_id_vendedor;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No autorizado para modificar este vendedor' USING ERRCODE = '42501';
    END IF;

    RETURN true;
END;
$function$;

REVOKE ALL ON FUNCTION public.fn_m01_personal_reasignar_vendedor(bigint, bigint)
    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_personal_reasignar_vendedor(bigint, bigint)
    TO authenticated;

COMMIT;
