SELECT
    c.relname AS tabla,
    pg_get_userbyid(c.relowner) AS propietario,
    c.relrowsecurity AS rls_activo,
    c.relforcerowsecurity AS force_rls,
    c.relacl::text AS acl
FROM pg_class c
WHERE c.oid = 'public.app_dat_configuracion_tienda'::regclass;

SELECT
    r.rolname AS rol,
    r.rolbypassrls AS bypass_rls,
    has_table_privilege(r.oid, 'public.app_dat_configuracion_tienda', 'SELECT') AS permite_select,
    has_table_privilege(r.oid, 'public.app_dat_configuracion_tienda', 'INSERT') AS permite_insert,
    has_table_privilege(r.oid, 'public.app_dat_configuracion_tienda', 'UPDATE') AS permite_update,
    has_table_privilege(r.oid, 'public.app_dat_configuracion_tienda', 'DELETE') AS permite_delete,
    has_table_privilege(r.oid, 'public.app_dat_configuracion_tienda', 'TRUNCATE') AS permite_truncate,
    has_table_privilege(r.oid, 'public.app_dat_configuracion_tienda', 'REFERENCES') AS permite_references,
    has_table_privilege(r.oid, 'public.app_dat_configuracion_tienda', 'TRIGGER') AS permite_trigger
FROM pg_roles r
WHERE r.rolname IN ('anon', 'authenticated', 'service_role')
ORDER BY r.rolname;

SELECT policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'app_dat_configuracion_tienda'
ORDER BY policyname;

SELECT
    p.oid::regprocedure::text AS funcion,
    pg_get_userbyid(p.proowner) AS propietario,
    p.prosecdef AS security_definer,
    p.proconfig AS configuracion,
    l.lanname AS lenguaje,
    has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_execute,
    has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_execute,
    has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_role_execute,
    position('PERFORM public.fn_config_tienda_exigir_lectura(' IN p.prosrc) > 0 AS tiene_invocacion_guarda,
    md5(pg_get_functiondef(p.oid)) AS hash_definicion
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
JOIN pg_language l ON l.oid = p.prolang
WHERE n.nspname = 'public'
  AND p.oid IN (
      to_regprocedure('public.fn_config_tienda_puede_leer(bigint)'),
      to_regprocedure('public.fn_config_tienda_puede_escribir(bigint)'),
      to_regprocedure('public.fn_config_tienda_exigir_lectura(bigint)'),
      to_regprocedure('public.sync_bundle(bigint,bigint)'),
      to_regprocedure('public.fn_obtener_licencia_firmada(bigint)'),
      to_regprocedure('public.fn_moneda_consolidacion(bigint)')
  )
ORDER BY funcion;

SELECT
    p.oid::regprocedure::text AS funcion_lectora,
    p.prosecdef AS security_definer,
    has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_execute,
    has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_execute,
    p.prosrc ~* 'app_dat_configuracion_tienda' AS referencia_configuracion,
    p.prosrc ~* '(insert[[:space:]]+into|update|delete[[:space:]]+from)[[:space:]]+(public[.])?app_dat_configuracion_tienda' AS escritura_directa_detectada
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prokind = 'f'
  AND p.prosrc ILIKE '%app_dat_configuracion_tienda%'
ORDER BY funcion_lectora;

SELECT schemaname, viewname, viewowner
FROM pg_views
WHERE schemaname = 'public'
  AND definition ILIKE '%app_dat_configuracion_tienda%';

SELECT
    (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.app_dat_configuracion_tienda'::regclass) AS rls_activo,
    NOT has_table_privilege('anon', 'public.app_dat_configuracion_tienda', 'SELECT')
        AND NOT has_table_privilege('anon', 'public.app_dat_configuracion_tienda', 'INSERT')
        AND NOT has_table_privilege('anon', 'public.app_dat_configuracion_tienda', 'UPDATE') AS anon_sin_acceso_directo,
    has_table_privilege('authenticated', 'public.app_dat_configuracion_tienda', 'SELECT')
        AND has_table_privilege('authenticated', 'public.app_dat_configuracion_tienda', 'INSERT')
        AND has_table_privilege('authenticated', 'public.app_dat_configuracion_tienda', 'UPDATE') AS authenticated_tiene_grants_sujetos_a_rls,
    NOT has_table_privilege('authenticated', 'public.app_dat_configuracion_tienda', 'DELETE')
        AND NOT has_table_privilege('authenticated', 'public.app_dat_configuracion_tienda', 'TRUNCATE') AS authenticated_sin_delete_truncate,
    (SELECT count(*) = 4 FROM pg_policies
     WHERE schemaname = 'public' AND tablename = 'app_dat_configuracion_tienda') AS cuatro_policies,
    (SELECT count(*) = 3 AND bool_and(
         NOT has_function_privilege('anon', p.oid, 'EXECUTE')
         AND position('PERFORM public.fn_config_tienda_exigir_lectura(' IN p.prosrc) > 0
     ) FROM pg_proc p WHERE p.oid IN (
         to_regprocedure('public.sync_bundle(bigint,bigint)'),
         to_regprocedure('public.fn_obtener_licencia_firmada(bigint)'),
         to_regprocedure('public.fn_moneda_consolidacion(bigint)')
     )) AS tres_rpc_con_guarda_y_sin_anon;
