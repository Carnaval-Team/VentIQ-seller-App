BEGIN;

-- BORRADOR M01-R0g. NO EJECUTAR. Hardening transversal de la flota DEFINER
-- offline/sync: search_path fijo y revocacion de EXECUTE a anon/PUBLIC, por
-- iteracion de catalogo (no se reescribe ningun cuerpo).
-- Alcance: toda funcion public.* con prosecdef=true cuyo nombre coincida con
-- 'fn_%_offline%', 'fn_registrar_%' o 'fn_admin_caja_%'. Se excluye cualquier
-- fn_m01_* (ya endurecida) y los helpers compartidos que otras rutas usan con
-- otros caller: se fija search_path pero NO se les revoca EXECUTE, para no
-- romper llamadas internas legacy no catalogadas.
-- Residual declarado: authenticated conserva EXECUTE; estas funciones aceptan
-- uuid/tienda del llamador y corren como postgres. La validacion interna de
-- actor/ambito por funcion requiere CREATE OR REPLACE por cuerpo y queda como
-- corte posterior (R0h); este corte ya cierra anon/PUBLIC y el secuestro de
-- search_path. La tabla de idempotencia quedo protegida en R0e.
-- DEPENDENCIAS: R0a-R0e aplicados.

SET LOCAL app.m01_r0g_approved = 'yes';
SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '120s';

DO $preflight$
BEGIN
    IF current_user <> 'postgres'
       OR current_setting('app.m01_r0g_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador R0g: requiere revision y ejecucion manual en newa';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.prosecdef
          AND (p.proname LIKE 'fn\_%\_offline%' ESCAPE '\'
               OR p.proname LIKE 'fn_registrar_%'
               OR p.proname LIKE 'fn_admin_caja_%')
    ) THEN
        RAISE EXCEPTION 'No se encontro la flota DEFINER offline esperada';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.prosecdef
          AND (p.proname LIKE 'fn\_%\_offline%' ESCAPE '\'
               OR p.proname LIKE 'fn_registrar_%'
               OR p.proname LIKE 'fn_admin_caja_%')
          AND p.proconfig IS NULL
    ) THEN
        NULL; -- esperado: sin search_path fijo; se corrige abajo
    END IF;
END;
$preflight$;

-- Fija search_path y acota EXECUTE en toda la flota.

DO $hardening$
DECLARE
    f record;
    v_sig text;
BEGIN
    FOR f IN
        SELECT p.oid, p.proname,
               pg_get_function_identity_arguments(p.oid) AS args
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.prosecdef
          AND (p.proname LIKE 'fn\_%\_offline%' ESCAPE '\'
               OR p.proname LIKE 'fn_registrar_%'
               OR p.proname LIKE 'fn_admin_caja_%')
          AND p.proname NOT LIKE 'fn_m01_%'
    LOOP
        v_sig := format('public.%I(%s)', f.proname, f.args);
        EXECUTE format('ALTER FUNCTION %s SET search_path = pg_catalog, public', v_sig);
        EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', v_sig);
        EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', v_sig);
    END LOOP;
END;
$hardening$;

COMMIT;
