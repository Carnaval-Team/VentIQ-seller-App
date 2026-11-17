BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY;

WITH helper AS (
    SELECT p.*
    FROM pg_proc p
    WHERE p.oid = to_regprocedure('public.fn_m01_fuentes_puede_gestionar_duenos(bigint)')
)
SELECT current_user AS rol_inspeccion,
       'Solo catalogo: no demuestra permisos funcionales ni aislamiento completo de M01' AS alcance,
       EXISTS (SELECT 1 FROM helper) AS helper_presente,
       EXISTS (
           SELECT 1 FROM helper
           WHERE prosecdef AND provolatile = 's'
             AND proconfig = ARRAY['search_path=pg_catalog']::text[]
             AND pg_get_userbyid(proowner) = 'postgres'
       ) AS atributos_helper_correctos,
       EXISTS (
           SELECT 1 FROM helper
           WHERE NOT has_function_privilege('anon', oid, 'EXECUTE')
             AND has_function_privilege('authenticated', oid, 'EXECUTE')
             AND has_function_privilege('service_role', oid, 'EXECUTE')
       ) AS privilegios_helper_correctos,
       (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.app_dat_dueno'::regclass) AS rls_activo,
       NOT has_table_privilege('anon', 'public.app_dat_dueno', 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,TRIGGER,REFERENCES') AS anon_sin_privilegios_tabla,
       NOT has_table_privilege('authenticated', 'public.app_dat_dueno', 'TRUNCATE,TRIGGER,REFERENCES') AS authenticated_sin_privilegios_ddl,
       (
           SELECT count(*) = 4
              AND bool_and(roles = ARRAY['authenticated']::name[])
              AND count(DISTINCT cmd) = 4
           FROM pg_policies
           WHERE schemaname = 'public' AND tablename = 'app_dat_dueno'
       ) AS cuatro_policies_authenticated;

SELECT p.oid::regprocedure::text AS firma,
       pg_get_functiondef(p.oid) AS definicion_para_revision
FROM pg_proc p
WHERE p.oid = to_regprocedure('public.fn_m01_fuentes_puede_gestionar_duenos(bigint)');

SELECT policyname, cmd, roles, permissive, qual, with_check
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'app_dat_dueno'
ORDER BY policyname;

COMMIT;
