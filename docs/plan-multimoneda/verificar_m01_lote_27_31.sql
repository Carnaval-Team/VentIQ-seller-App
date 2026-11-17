-- Lectura. Ejecutar después de los scripts 27 a 31, en el mismo pegado
-- o justo después. No escribe.

SELECT p.proname
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
      'fn_m01_leer_idempotencia',
      'fn_m01_fijar_moneda_por_producto',
      'fn_m01_estado_capacidad_moneda',
      'fn_m01_resolver_precio_tpv',
      'fn_m01_guardar_precio_tpv'
  )
ORDER BY 1;

SELECT column_name, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'app_dat_precio_tpv'
  AND column_name = 'precio_venta_usd';

SELECT c.relrowsecurity, c.relforcerowsecurity
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname = 'app_dat_precio_tpv';

SELECT has_table_privilege('anon', 'public.app_dat_precio_tpv', 'SELECT') AS anon_lee_precio_tpv;
