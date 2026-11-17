-- Solo lectura. Ejecutar despues de los scripts 32 y 33.
SELECT
    (SELECT count(*)
     FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = 'app_dat_extraccion_productos'
       AND column_name IN ('version_monetaria', 'moneda_venta', 'importe_neto_nativo')) AS columnas_extraccion,
    (SELECT count(*)
     FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name = 'app_dat_operacion_venta'
       AND column_name = 'version_monetaria') AS columna_venta,
    c.relrowsecurity AS rls,
    c.relforcerowsecurity AS rls_forzado,
    has_table_privilege('anon', 'public.app_dat_pago_aplicacion', 'SELECT') AS anon_select
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname = 'app_dat_pago_aplicacion';
