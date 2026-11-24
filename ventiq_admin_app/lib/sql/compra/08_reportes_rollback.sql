-- ============================================================================
-- 08_reportes_rollback.sql — reversa de la fase 8 (reportes R2-R7 y aging)
--
-- REQUIERE: 08_reportes.sql aplicado.
--
-- Qué deshace:
--   1. `fn_fdi_reporte_caja(bigint)`            (R2)
--   2. `fn_fdi_reporte_compras(bigint,date,date)` (R3)
--   3. `fn_fdi_reporte_costo(bigint,date,date)`   (R4)
--   4. `fn_fdi_reporte_cambiario(bigint,date,date)` (R5)
--   5. `fn_fdi_reporte_movimientos(bigint,date,date)` (R6)
--   6. `fn_fdi_reporte_inversores(bigint)`      (R7)
--   7. `fn_fdi_reporte_aging(bigint)`           (aging y descuadres)
--
-- SOLO `DROP FUNCTION`: los reportes son de lectura y no crearon tablas,
-- columnas, índices, triggers, políticas ni GRANT sobre objetos. No hay nada
-- más que retirar y nada que restaurar.
--
-- Qué NO toca (a propósito): R1 (`fn_fdi_conciliacion`), `fn_fdi_saldos`,
-- `fn_fdi_disponible`, `fn_fdi_movimientos`, `fn_fdi_historial_inversores` y
-- `fn_fdi_compra_costo_resumen`. Son anteriores a esta fase y tienen
-- consumidores; el rollback de los reportes no puede llevárselos.
--
-- Tras aplicarlo, `verify/08_reportes.sql` falla (no resuelve las funciones):
-- es lo esperado.
--
-- Es transaccional: o sale todo o no sale nada.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) Retirar las 7 funciones del reporte
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.fn_fdi_reporte_aging(bigint);
DROP FUNCTION IF EXISTS public.fn_fdi_reporte_inversores(bigint);
DROP FUNCTION IF EXISTS public.fn_fdi_reporte_movimientos(bigint, date, date);
DROP FUNCTION IF EXISTS public.fn_fdi_reporte_cambiario(bigint, date, date);
DROP FUNCTION IF EXISTS public.fn_fdi_reporte_costo(bigint, date, date);
DROP FUNCTION IF EXISTS public.fn_fdi_reporte_compras(bigint, date, date);
DROP FUNCTION IF EXISTS public.fn_fdi_reporte_caja(bigint);

-- ---------------------------------------------------------------------------
-- 2) Verificación final: no quedan reportes y el resto sigue en su sitio
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v integer;
    v_firmas text[] := ARRAY[
        'public.fn_fdi_reporte_caja(bigint)',
        'public.fn_fdi_reporte_compras(bigint,date,date)',
        'public.fn_fdi_reporte_costo(bigint,date,date)',
        'public.fn_fdi_reporte_cambiario(bigint,date,date)',
        'public.fn_fdi_reporte_movimientos(bigint,date,date)',
        'public.fn_fdi_reporte_inversores(bigint)',
        'public.fn_fdi_reporte_aging(bigint)'
    ];
    v_nombre text;
BEGIN
    FOREACH v_nombre IN ARRAY v_firmas LOOP
        IF to_regprocedure(v_nombre) IS NOT NULL THEN
            RAISE EXCEPTION 'Rollback 08: % sigue existiendo', v_nombre USING ERRCODE = 'P0002';
        END IF;
    END LOOP;

    -- Sin sobrecargas residuales con esos nombres (una firma vieja se quedaría
    -- viva si solo se hubiera borrado la actual).
    SELECT count(*) INTO v
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname IN ('fn_fdi_reporte_caja','fn_fdi_reporte_compras',
                         'fn_fdi_reporte_costo','fn_fdi_reporte_cambiario',
                         'fn_fdi_reporte_movimientos','fn_fdi_reporte_inversores',
                         'fn_fdi_reporte_aging');
    IF v <> 0 THEN
        RAISE EXCEPTION 'Rollback 08: quedan % función(es) con nombre de reporte', v;
    END IF;

    -- Lo anterior a la fase 8 sigue intacto: el rollback no se lleva nada más.
    IF to_regprocedure('public.fn_fdi_conciliacion(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Rollback 08: desapareció fn_fdi_conciliacion(bigint)';
    END IF;
    IF to_regprocedure('public.fn_fdi_saldos(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Rollback 08: desapareció fn_fdi_saldos(bigint)';
    END IF;
    IF to_regprocedure('public.fn_fdi_disponible(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Rollback 08: desapareció fn_fdi_disponible(bigint)';
    END IF;
    IF to_regprocedure('public.fn_fdi_compra_costo_resumen(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Rollback 08: desapareció fn_fdi_compra_costo_resumen(bigint)';
    END IF;
    IF to_regclass('public.fdi_dat_compra') IS NULL THEN
        RAISE EXCEPTION 'Rollback 08: desapareció fdi_dat_compra';
    END IF;

    RAISE NOTICE 'Rollback 08 aplicado: 7 reportes retirados; R1, saldos, disponible y costo quedan intactos.';
END;
$$;

COMMIT;