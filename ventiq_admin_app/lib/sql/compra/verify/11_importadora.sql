-- ============================================================================
-- verify/11_importadora.sql — Fase 11: bruto de importadora
--
-- REQUIERE: 11_importadora_bruto.sql aplicado en `newa`.
-- SOLO LECTURA. Una sola sentencia (checks + resumen n=99).
-- ============================================================================

WITH checks AS (
    SELECT 1 AS n,
           'columna monto_bruto_importadora es GENERATED ALWAYS'::text AS txt,
           EXISTS (
               SELECT 1
                 FROM information_schema.columns
                WHERE table_schema = 'public'
                  AND table_name = 'fdi_dat_compra_recepcion'
                  AND column_name = 'monto_bruto_importadora'
                  AND is_generated = 'ALWAYS'
           ) AS ok
    UNION ALL
    SELECT 2,
           'bruto = neto + reembolso en todas las filas',
           NOT EXISTS (
               SELECT 1
                 FROM public.fdi_dat_compra_recepcion
                WHERE monto_bruto_importadora
                      IS DISTINCT FROM (monto_importadora + reembolso_importadora)
           )
    UNION ALL
    SELECT 3,
           'el neto no cambió (nada negativo)',
           NOT EXISTS (
               SELECT 1
                 FROM public.fdi_dat_compra_recepcion
                WHERE monto_importadora < 0 OR reembolso_importadora < 0
           )
    UNION ALL
    SELECT 4,
           'la columna no es escribible por PostgREST (generada)',
           NOT EXISTS (
               SELECT 1
                 FROM information_schema.columns
                WHERE table_schema = 'public'
                  AND table_name = 'fdi_dat_compra_recepcion'
                  AND column_name = 'monto_bruto_importadora'
                  AND is_generated <> 'ALWAYS'
           )
)
SELECT n, txt, ok
  FROM checks
UNION ALL
SELECT 99,
       'resumen: sin fallas'::text,
       (SELECT count(*) FILTER (WHERE NOT ok) = 0 FROM checks)
 ORDER BY n;
