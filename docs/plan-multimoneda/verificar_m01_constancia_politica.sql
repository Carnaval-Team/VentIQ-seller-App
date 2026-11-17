-- Lectura. Ejecutar después de m01_r07_constancia_politica_propuesta.sql.
-- No escribe. La entrega no se edita y anon no puede emitirla ni validarla.

SELECT c.relrowsecurity, c.relforcerowsecurity
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname = 'app_dat_politica_moneda_constancia';

SELECT pol.polname, pol.polcmd
FROM pg_policy pol
JOIN pg_class c ON c.oid = pol.polrelid
WHERE c.relname = 'app_dat_politica_moneda_constancia';

SELECT p.proname
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
      'fn_m01_emitir_constancia_politica',
      'fn_m01_validar_constancia_politica'
  )
ORDER BY 1;

SELECT has_function_privilege(
    'anon',
    'public.fn_m01_emitir_constancia_politica(bigint,text)',
    'EXECUTE'
) AS anon_puede_emitir;
