-- Lectura. Ejecutar después de m01_r06_politica_revision_propuesta.sql.
-- No escribe. La columna debe existir en false, la revisión no se edita
-- y anon no puede publicarla.

SELECT column_name, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'app_dat_configuracion_tienda'
  AND column_name = 'permitir_moneda_por_producto';

SELECT c.relrowsecurity, c.relforcerowsecurity
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname = 'app_dat_politica_moneda_revision';

SELECT pol.polname, pol.polcmd
FROM pg_policy pol
JOIN pg_class c ON c.oid = pol.polrelid
WHERE c.relname = 'app_dat_politica_moneda_revision';

SELECT p.proname
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
      'fn_m01_publicar_revision_politica',
      'fn_m01_politica_insertar_revision'
  )
ORDER BY 1;

SELECT has_function_privilege(
    'anon',
    'public.fn_m01_publicar_revision_politica(bigint)',
    'EXECUTE'
) AS anon_puede_publicar;
