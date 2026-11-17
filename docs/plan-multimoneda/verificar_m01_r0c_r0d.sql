-- VERIFICADOR DE SOLO LECTURA — posterior a aplicar R0c y R0d en newa.
-- No escribe nada; reporta estado esperado. Ejecutar como postgres.

-- 1) RLS activado en las tablas que estaban expuestas
SELECT relname, relrowsecurity
FROM pg_class
WHERE oid IN (
    'public.app_dat_cocina'::regclass,
    'public.app_dat_jefe_cocina'::regclass,
    'public.app_dat_supervisor'::regclass,
    'public.auditor'::regclass
)
ORDER BY relname;
-- Esperado: relrowsecurity = true en las 4.

-- 2) Policies esperadas R0c (conteo por tabla)
SELECT tablename, count(*) AS policies
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN (
      'app_dat_tpv', 'app_dat_almacen', 'app_dat_cocina',
      'app_dat_almacenero', 'app_dat_jefe_cocina', 'app_dat_supervisor',
      'auditor', 'app_dat_gerente', 'seg_roll'
  )
GROUP BY tablename
ORDER BY tablename;
-- Esperado: todas > 0 y ninguna residual del baseline (ver 3).

-- 3) Residuales permisivas en todas las tablas M01 (debe ser 0)
SELECT count(*) AS policies_publicas_permisivas
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN (
      'app_dat_tpv', 'app_dat_almacen', 'app_dat_cocina',
      'app_dat_almacenero', 'app_dat_jefe_cocina', 'app_dat_supervisor',
      'auditor', 'app_dat_gerente', 'seg_roll',
      'app_dat_trabajadores', 'app_dat_vendedor', 'app_dat_dueno',
      'app_dat_recursos_humanos', 'app_dat_tienda', 'app_dat_operaciones',
      'app_dat_operacion_offline_idempotencia'
  )
  AND (roles::text = '{public}' OR qual = 'true' OR with_check = 'true');
-- Esperado: 0

-- 4) Helpers de ambito presentes, DEFINER, search_path fijo
SELECT p.proname, p.prosecdef, unnest(p.proconfig) AS config
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
      'fn_m01_personal_tienda_de_almacen', 'fn_m01_personal_tienda_de_cocina',
      'fn_m01_operaciones_puede_operar', 'fn_m01_personal_es_recursos_humanos',
      'fn_m01_personal_exigir_reasignacion_vendedor',
      'fn_m01_personal_reasignar_vendedor',
      'fn_m01_personal_vincular_usuario_trabajador'
  )
ORDER BY p.proname, config;
-- Esperado: todas presentes; DEFINER con search_path=pg_catalog
-- (la guarda exigir_* es DEFINER y ademas debe tener EXECUTE revocado).

-- 5) search_path fijo en las DEFINER legacy endurecidas
SELECT p.proname, p.prosecdef,
       coalesce(array_to_string(p.proconfig, ','), '(sin proconfig)') AS config
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
      'fn_asignar_vendedor', 'fn_desasignar_vendedor',
      'fn_asignar_supervisor', 'fn_desasignar_supervisor',
      'fn_asignar_jefe_cocina', 'crear_tpv_completo',
      'create_gerente_from_email', 'fn_insertar_trabajador_basico',
      'fn_restaurar_trabajador', 'fn_hr_update_worker_salary',
      'fn_is_superadmin_full_access', 'fn_user_is_dueno',
      'fn_check_is_hr_user', 'fn_hr_assert_access'
  )
ORDER BY p.proname;
-- Esperado: prosecdef = true y config contiene search_path=pg_catalog...

-- 6) Wrappers fn_m01_* presentes y ejecutables solo por authenticated
SELECT p.proname,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_exec,
       has_function_privilege('public', p.oid, 'EXECUTE') AS public_exec
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname LIKE 'fn_m01_%'
ORDER BY p.proname;
-- Esperado: auth_exec = true en los wrappers de entrada;
-- anon_exec = false, public_exec = false en todos.
-- fn_m01_personal_exigir_reasignacion_vendedor debe tener auth_exec = false.

-- 7) Legacy sensibles sin EXECUTE para cliente
SELECT p.proname,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec,
       has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_exec
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
      'fn_asignar_vendedor', 'fn_desasignar_vendedor',
      'fn_asignar_supervisor', 'fn_desasignar_supervisor',
      'fn_asignar_jefe_cocina', 'crear_tpv_completo',
      'create_gerente_from_email'
  )
ORDER BY p.proname;
-- Esperado: auth_exec = false; service_exec = true.

-- 8) Guarda interna sin EXECUTE para nadie excepto postgres
SELECT p.proname,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec,
       has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_exec,
       has_function_privilege('public', p.oid, 'EXECUTE') AS public_exec
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_m01_personal_exigir_reasignacion_vendedor';
-- Esperado: auth_exec = false, service_exec = false, public_exec = false.
