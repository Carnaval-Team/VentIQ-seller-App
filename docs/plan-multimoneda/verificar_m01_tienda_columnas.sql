-- VERIFICADOR DE SOLO LECTURA — posterior al script 22 en newa.
-- No cambia datos.

-- 1) El perfil sigue actualizable por authenticated.
SELECT column_name
FROM information_schema.column_privileges
WHERE table_schema = 'public'
  AND table_name = 'app_dat_tienda'
  AND grantee = 'authenticated'
  AND privilege_type = 'UPDATE'
  AND column_name IN ('denominacion', 'direccion', 'phone', 'mostrar_en_catalogo')
ORDER BY column_name;
-- Esperado: las cuatro filas.

-- 2) Las columnas de confianza no.
SELECT column_name
FROM information_schema.column_privileges
WHERE table_schema = 'public'
  AND table_name = 'app_dat_tienda'
  AND grantee IN ('authenticated', 'anon', 'PUBLIC')
  AND privilege_type = 'UPDATE'
  AND column_name IN (
      'es_prueba', 'validada', 'admin_carnaval',
      'id_tienda_carnaval', 'only_catalogo', 'created_at'
  )
ORDER BY column_name;
-- Esperado: cero filas.

-- 3) Las funciones de superadmin existen y usan el actor.
SELECT p.proname
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
      'fn_m01_vincular_tienda_carnaval',
      'fn_m01_desvincular_tienda_carnaval',
      'fn_m01_validar_tienda_catalogo',
      'fn_m01_marcar_tienda_prueba',
      'fn_m01_personal_desvincular_usuario_trabajador'
  )
  AND p.prosrc LIKE '%auth.uid()%'
ORDER BY p.proname;
-- Esperado: las cinco filas.
