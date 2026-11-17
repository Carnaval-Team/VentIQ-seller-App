BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY;

-- Verificador post-aplicacion de R0b (guarda + RPC de reasignacion).
-- Solo catalogo: no demuestra aislamiento funcional de roles ni el paquete M01
-- completo. Antes de aplicar, esperado: ambas funciones ausentes. Despues:
-- atributos DEFINER/pg_catalog, EXECUTE segun diseno y sin politicas nuevas.

WITH f AS (
    SELECT p.oid, p.proname, p.prosecdef, p.provolatile, p.proconfig,
           pg_get_userbyid(p.proowner) AS dueno
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
          'fn_m01_personal_exigir_reasignacion_vendedor',
          'fn_m01_personal_reasignar_vendedor'
      )
)
SELECT current_user AS rol_inspeccion,
       'Solo catalogo: no demuestra permisos funcionales ni aislamiento completo de M01' AS alcance,
       EXISTS (SELECT 1 FROM f WHERE proname = 'fn_m01_personal_exigir_reasignacion_vendedor') AS guarda_presente,
       EXISTS (SELECT 1 FROM f WHERE proname = 'fn_m01_personal_reasignar_vendedor') AS rpc_presente,
       EXISTS (
           SELECT 1 FROM f
           WHERE proname = 'fn_m01_personal_exigir_reasignacion_vendedor'
             AND prosecdef AND provolatile = 'v'
             AND proconfig = ARRAY['search_path=pg_catalog']::text[]
             AND dueno = 'postgres'
       ) AS atributos_guarda_correctos,
       EXISTS (
           SELECT 1 FROM f
           WHERE proname = 'fn_m01_personal_reasignar_vendedor'
             AND prosecdef AND provolatile = 'v'
             AND proconfig = ARRAY['search_path=pg_catalog']::text[]
             AND dueno = 'postgres'
       ) AS atributos_rpc_correctos,
       EXISTS (
           SELECT 1 FROM f
           WHERE proname = 'fn_m01_personal_exigir_reasignacion_vendedor'
             AND NOT has_function_privilege('anon', oid, 'EXECUTE')
             AND NOT has_function_privilege('authenticated', oid, 'EXECUTE')
             AND NOT has_function_privilege('service_role', oid, 'EXECUTE')
       ) AS guarda_sin_execute_cliente,
       EXISTS (
           SELECT 1 FROM f
           WHERE proname = 'fn_m01_personal_reasignar_vendedor'
             AND NOT has_function_privilege('anon', oid, 'EXECUTE')
             AND has_function_privilege('authenticated', oid, 'EXECUTE')
             AND NOT has_function_privilege('service_role', oid, 'EXECUTE')
       ) AS rpc_execute_solo_authenticated;

SELECT p.oid::regprocedure::text AS firma,
       pg_get_functiondef(p.oid) AS definicion_para_revision
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
      'fn_m01_personal_exigir_reasignacion_vendedor',
      'fn_m01_personal_reasignar_vendedor'
  )
ORDER BY p.proname;

-- Baseline de policies/grants de las tablas que R0b/R0c protegera despues;
-- aqui solo se inventaria, no se exige endurecimiento todavia.
SELECT tablename, policyname, cmd, roles
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('app_dat_vendedor', 'app_dat_trabajadores', 'app_dat_tpv')
ORDER BY tablename, policyname;

COMMIT;
