-- ============================================================================
-- verify/12_compra_contrato.sql — Fase 12: contrato del alta de compra
--
-- REQUIERE: 12_compra_contrato.sql aplicado en `newa`.
-- SOLO LECTURA. Una sola sentencia (checks + resumen n=99).
-- ============================================================================

WITH checks AS (
    SELECT 1 AS n, 'crear exige número de factura'::text AS txt,
           position('El número de factura es obligatorio'
                    IN pg_get_functiondef('public.fn_fdi_compra_crear(bigint,bigint,text,date,text,numeric,jsonb,jsonb,text,text,text,uuid)'::regprocedure)) > 0 AS ok
    UNION ALL
    SELECT 2, 'editar exige número de factura',
           position('El número de factura es obligatorio'
                    IN pg_get_functiondef('public.fn_fdi_compra_editar(bigint,text,date,text,numeric,jsonb,jsonb,text)'::regprocedure)) > 0
    UNION ALL
    SELECT 3, 'crear resuelve la tasa de la tienda',
           position('fn_fdi_tasa_cup_por_usd_tienda'
                    IN pg_get_functiondef('public.fn_fdi_compra_crear(bigint,bigint,text,date,text,numeric,jsonb,jsonb,text,text,text,uuid)'::regprocedure)) > 0
    UNION ALL
    SELECT 4, 'helper de tasa existe',
           to_regprocedure('public.fn_fdi_tasa_cup_por_usd_tienda(bigint)') IS NOT NULL
    UNION ALL
    SELECT 5, 'tienda 4 tiene tasa 850 CUP/USD',
           public.fn_fdi_tasa_cup_por_usd_tienda(4) = 850
    UNION ALL
    SELECT 6, 'crear guarda reparto por cantidad',
           position('''cantidad'''
                    IN pg_get_functiondef('public.fn_fdi_compra_crear(bigint,bigint,text,date,text,numeric,jsonb,jsonb,text,text,text,uuid)'::regprocedure)) > 0
    UNION ALL
    SELECT 7, 'crear deriva origen externo en inversores',
           position('''externo'''
                    IN pg_get_functiondef('public.fn_fdi_compra_crear(bigint,bigint,text,date,text,numeric,jsonb,jsonb,text,text,text,uuid)'::regprocedure)) > 0
)
SELECT n, txt, ok FROM checks
UNION ALL
SELECT 99, 'resumen: sin fallas'::text,
       (SELECT count(*) FILTER (WHERE NOT ok) = 0 FROM checks)
 ORDER BY n;
