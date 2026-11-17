BEGIN;

SET LOCAL app.m01_r0a_duenos_approved = 'yes';

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
DECLARE
    v_hash text;
    v_count bigint;
BEGIN
    IF current_user <> 'postgres' THEN
        RAISE EXCEPTION 'Preparacion M01-R0a para newa: requiere propietario postgres';
    END IF;

    IF current_setting('app.m01_r0a_duenos_approved', true) IS DISTINCT FROM 'yes' THEN
        RAISE EXCEPTION 'Borrador parcial M01-R0a: no ejecutar antes de revisar el paquete M01 y sus dependencias';
    END IF;

    IF has_schema_privilege('anon', 'public', 'CREATE')
       OR has_schema_privilege('authenticated', 'public', 'CREATE') THEN
        RAISE EXCEPTION 'public permite CREATE a roles no confiables; revisar antes de aplicar';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'fn_m01_fuentes_puede_gestionar_duenos'
    ) THEN
        RAISE EXCEPTION 'El helper M01 ya existe; no reejecutar ni sobrescribir avances de newa';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_class c
        WHERE c.oid = 'public.app_dat_dueno'::regclass
          AND c.relowner = (SELECT oid FROM pg_roles WHERE rolname = 'postgres')
          AND c.relrowsecurity
          AND NOT c.relforcerowsecurity
    ) THEN
        RAISE EXCEPTION 'Propietario o RLS de dueno distintos del baseline inspeccionado';
    END IF;

    IF to_regprocedure('public.fn_user_can_access_tienda(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Falta el predicado de lectura existente; no fabricar un reemplazo';
    END IF;

    IF NOT (
        has_table_privilege('service_role', 'public.app_dat_dueno', 'SELECT')
        AND has_table_privilege('service_role', 'public.app_dat_dueno', 'INSERT')
        AND has_table_privilege('service_role', 'public.app_dat_dueno', 'UPDATE')
        AND has_table_privilege('service_role', 'public.app_dat_dueno', 'DELETE')
    ) THEN
        RAISE EXCEPTION 'Privilegios de servicio distintos del baseline; revisar sin ampliarlos';
    END IF;

    LOCK TABLE public.app_dat_dueno IN SHARE ROW EXCLUSIVE MODE;

    SELECT md5(jsonb_agg(jsonb_build_object(
               'name', policyname, 'roles', roles, 'cmd', cmd,
               'permissive', permissive, 'using', qual, 'check', with_check
           ) ORDER BY policyname)::text), count(*)
    INTO v_hash, v_count
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'app_dat_dueno';

    IF v_count <> 4 OR v_hash IS DISTINCT FROM 'c4360cbdbd89585ab687c878a9536a5a' THEN
        RAISE EXCEPTION 'Policies de dueno desconocidas; no eliminarlas ni migrarlas automaticamente';
    END IF;
END;
$preflight$;

CREATE FUNCTION public.fn_m01_fuentes_puede_gestionar_duenos(p_id_tienda bigint)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
    SELECT p_id_tienda IS NOT NULL
       AND auth.uid() IS NOT NULL
       AND (
           EXISTS (
               SELECT 1 FROM public.app_dat_dueno d
               WHERE d.id_tienda = p_id_tienda AND d.uuid = auth.uid()
           )
           OR EXISTS (
               SELECT 1 FROM public.app_dat_superadmin s
               WHERE s.uuid = auth.uid()
                 AND s.activo = true AND s.nivel_acceso = 1
           )
       );
$function$;

REVOKE ALL ON FUNCTION public.fn_m01_fuentes_puede_gestionar_duenos(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_m01_fuentes_puede_gestionar_duenos(bigint) TO authenticated, service_role;

ALTER TABLE public.app_dat_dueno ENABLE ROW LEVEL SECURITY;

DROP POLICY app_dat_dueno_select ON public.app_dat_dueno;
CREATE POLICY app_dat_dueno_select ON public.app_dat_dueno
    FOR SELECT TO authenticated
    USING (
        uuid = auth.uid()
        OR public.fn_m01_fuentes_puede_gestionar_duenos(id_tienda)
        OR public.fn_user_can_access_tienda(id_tienda)
    );

DROP POLICY app_dat_dueno_insert ON public.app_dat_dueno;
CREATE POLICY app_dat_dueno_insert ON public.app_dat_dueno
    FOR INSERT TO authenticated
    WITH CHECK (public.fn_m01_fuentes_puede_gestionar_duenos(id_tienda));

DROP POLICY app_dat_dueno_update ON public.app_dat_dueno;
CREATE POLICY app_dat_dueno_update ON public.app_dat_dueno
    FOR UPDATE TO authenticated
    USING (public.fn_m01_fuentes_puede_gestionar_duenos(id_tienda))
    WITH CHECK (public.fn_m01_fuentes_puede_gestionar_duenos(id_tienda));

DROP POLICY app_dat_dueno_delete ON public.app_dat_dueno;
CREATE POLICY app_dat_dueno_delete ON public.app_dat_dueno
    FOR DELETE TO authenticated
    USING (public.fn_m01_fuentes_puede_gestionar_duenos(id_tienda));

REVOKE ALL ON TABLE public.app_dat_dueno FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.app_dat_dueno TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.app_dat_dueno TO service_role;

DO $postflight$
BEGIN
    IF NOT (
        has_table_privilege('service_role', 'public.app_dat_dueno', 'SELECT')
        AND has_table_privilege('service_role', 'public.app_dat_dueno', 'INSERT')
        AND has_table_privilege('service_role', 'public.app_dat_dueno', 'UPDATE')
        AND has_table_privilege('service_role', 'public.app_dat_dueno', 'DELETE')
    ) THEN
        RAISE EXCEPTION 'No se preservaron privilegios DML de servicio';
    END IF;

    IF has_table_privilege('anon', 'public.app_dat_dueno', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,TRIGGER,REFERENCES')
       OR has_table_privilege('authenticated', 'public.app_dat_dueno', 'TRUNCATE,TRIGGER,REFERENCES')
       OR has_function_privilege('anon', 'public.fn_m01_fuentes_puede_gestionar_duenos(bigint)', 'EXECUTE') THEN
        RAISE EXCEPTION 'Persisten privilegios fuera del alcance revisado';
    END IF;
END;
$postflight$;

COMMIT;
