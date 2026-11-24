-- ============================================================================
-- 08b_conciliacion_job_rollback.sql — deshace la programación de R1
--
-- Borra el job de `pg_cron`, las dos RPC de la fase 8b y la bitácora.
-- NO toca `fn_fdi_conciliacion` (R1 es de la fase 1 y sigue viva).
--
-- HONESTIDAD: la bitácora de corridas es historia de auditoría. Si hay filas,
-- el script se niega a borrarla salvo que se pida explícitamente con
-- `set local fdi.forzar = 'si'`.
-- ============================================================================

BEGIN;

DO $$
DECLARE
    v_jobid bigint;
    v_n     bigint;
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        FOR v_jobid IN SELECT jobid FROM cron.job WHERE jobname = 'fdi-conciliacion-diaria' LOOP
            PERFORM cron.unschedule(v_jobid);
        END LOOP;
    END IF;

    IF to_regclass('public.fdi_dat_conciliacion_ejecucion') IS NOT NULL THEN
        EXECUTE 'SELECT count(*) FROM public.fdi_dat_conciliacion_ejecucion' INTO v_n;
        IF v_n > 0 AND COALESCE(current_setting('fdi.forzar', true), '') <> 'si' THEN
            RAISE EXCEPTION '08b rollback: hay % corridas registradas; repita con set local fdi.forzar = ''si'' si de verdad quiere borrarlas',
                v_n USING ERRCODE = '2B000';
        END IF;
    END IF;
END;
$$;

DROP FUNCTION IF EXISTS public.fn_fdi_conciliacion_ultima(bigint);
DROP FUNCTION IF EXISTS public.fn_fdi_conciliacion_registrar();

DROP TABLE IF EXISTS public.fdi_dat_conciliacion_ejecucion;

DO $$
BEGIN
    IF to_regprocedure('public.fn_fdi_conciliacion_registrar()') IS NOT NULL
       OR to_regprocedure('public.fn_fdi_conciliacion_ultima(bigint)') IS NOT NULL THEN
        RAISE EXCEPTION '08b rollback: quedan RPC de la fase 8b';
    END IF;
    IF to_regclass('public.fdi_dat_conciliacion_ejecucion') IS NOT NULL THEN
        RAISE EXCEPTION '08b rollback: queda la tabla de corridas';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron')
       AND EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'fdi-conciliacion-diaria') THEN
        RAISE EXCEPTION '08b rollback: queda el job fdi-conciliacion-diaria';
    END IF;

    -- R1 sigue viva: el rollback no es una excusa para quedarse sin conciliación.
    IF to_regprocedure('public.fn_fdi_conciliacion(bigint)') IS NULL THEN
        RAISE EXCEPTION '08b rollback: falta fn_fdi_conciliacion (no lo borres)';
    END IF;

    RAISE NOTICE '08b rollback: job y bitácora retirados; R1 intacta.';
END;
$$;

COMMIT;