-- ============================================================================
-- verify/10_costos_tienda.sql — Fase 10: conceptos de costo por tienda
--
-- REQUIERE: 10_costos_tienda.sql aplicado en `newa`.
-- SOLO LECTURA. Una sola sentencia (checks + resumen n=99).
-- ============================================================================

WITH checks AS (
    SELECT 1 AS n, 'app_cont_tipo_costo.id_tienda existe'::text AS txt,
           EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema='public' AND table_name='app_cont_tipo_costo'
                      AND column_name='id_tienda') AS ok
    UNION ALL
    SELECT 2, 'FK a app_dat_tienda',
           EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conname='app_cont_tipo_costo_id_tienda_fkey')
    UNION ALL
    SELECT 3, 'índice único por ámbito y denominación',
           EXISTS (SELECT 1 FROM pg_indexes
                    WHERE schemaname='public'
                      AND indexname='ux_cont_tipo_costo_ambito_denom')
    UNION ALL
    SELECT 4, 'fn_cont_tipo_costo_guardar de 5 argumentos',
           to_regprocedure('public.fn_cont_tipo_costo_guardar(bigint,text,text,boolean,bigint)') IS NOT NULL
    UNION ALL
    SELECT 5, 'firma vieja de 4 argumentos eliminada',
           to_regprocedure('public.fn_cont_tipo_costo_guardar(bigint,text,text,boolean)') IS NULL
    UNION ALL
    SELECT 6, 'anon no puede ejecutar la RPC',
           NOT has_function_privilege(
               'anon',
               'public.fn_cont_tipo_costo_guardar(bigint,text,text,boolean,bigint)',
               'EXECUTE')
    UNION ALL
    SELECT 7, 'los 4 conceptos sembrados siguen globales',
           NOT EXISTS (SELECT 1 FROM public.app_cont_tipo_costo
                        WHERE id_tienda IS NOT NULL
                          AND lower(btrim(denominacion)) IN ('flete','aduana','importadora','seguro')
                          AND created_at < timestamptz '2026-11-26')
)
SELECT n, txt, ok FROM checks
UNION ALL
SELECT 99, 'resumen: sin fallas'::text,
       (SELECT count(*) FILTER (WHERE NOT ok) = 0 FROM checks)
 ORDER BY n;
