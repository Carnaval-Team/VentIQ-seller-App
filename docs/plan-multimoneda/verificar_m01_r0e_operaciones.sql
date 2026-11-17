-- VERIFICADOR DE SOLO LECTURA — posterior a aplicar R0e en newa.
-- No escribe nada; reporta estado esperado. Ejecutar como postgres.

-- 1) Policies esperadas por tabla (conteo y nombres)
SELECT tablename, count(*) AS policies, string_agg(policyname, ', ' ORDER BY policyname) AS nombres
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('app_dat_tienda', 'app_dat_operaciones', 'app_dat_operacion_offline_idempotencia')
GROUP BY tablename
ORDER BY tablename;
-- Esperado:
--   app_dat_operacion_offline_idempotencia | 1 | m01_idempotencia_leer
--   app_dat_operaciones                    | 4 | m01_operaciones_actualizar/eliminar/insertar/leer
--   app_dat_tienda                         | 2 | m01_tienda_actualizar/leer

-- 2) Residuales permisivas (debe ser 0)
SELECT count(*) AS policies_publicas_permisivas
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('app_dat_tienda', 'app_dat_operaciones', 'app_dat_operacion_offline_idempotencia')
  AND (qual = 'true' OR with_check = 'true' OR roles::text = '{public}');
-- Esperado: 0

-- 3) RLS activado en idempotencia
SELECT relname, relrowsecurity
FROM pg_class
WHERE oid = 'public.app_dat_operacion_offline_idempotencia'::regclass;
-- Esperado: relrowsecurity = true

-- 4) Helper presente, DEFINER, search_path fijo
SELECT p.proname, p.prosecdef,
       unnest(p.proconfig) AS config
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_m01_operaciones_puede_operar';
-- Esperado: prosecdef = true; config = search_path=pg_catalog

-- 5) Privilegios de tabla sobre los roles expuestos
SELECT table_name, grantee, string_agg(privilege_type, ', ') AS privilegios
FROM information_schema.table_privileges
WHERE table_schema = 'public'
  AND table_name IN ('app_dat_tienda', 'app_dat_operaciones', 'app_dat_operacion_offline_idempotencia')
  AND grantee IN ('anon', 'authenticated')
GROUP BY table_name, grantee
ORDER BY table_name, grantee;
-- Esperado: anon sin filas; idempotencia solo SELECT para authenticated.

-- 6) Superadmin intacto (debe conservar sus 5 policies)
SELECT count(*) AS policies_superadmin
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'app_dat_superadmin';
-- Esperado: 5
