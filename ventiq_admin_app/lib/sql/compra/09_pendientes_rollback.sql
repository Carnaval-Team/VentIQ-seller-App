-- ============================================================================
-- 09_pendientes_rollback.sql — reversa de la fase 9 (pendientes, histórico de
-- recepciones y facturas)
--
-- REQUIERE: 09_pendientes.sql aplicado.
--
-- Qué deshace:
--   1. `fn_fdi_pendientes_panel(bigint,text)`
--   2. `fn_fdi_pendientes_detalle(bigint,bigint)`
--   3. `fn_fdi_recepciones_historial(bigint,date,date)`
--   4. `fn_fdi_facturas(bigint,date,date)`
--
-- SOLO `DROP FUNCTION`: las cuatro son de lectura y no crearon tablas,
-- columnas, índices, triggers, políticas ni GRANT sobre objetos. No hay nada
-- más que retirar y nada que restaurar.
--
-- Qué NO toca (a propósito): `fn_fdi_compra_recepcion_pendiente`,
-- `fn_fdi_compra_costo_resumen`, `fn_fdi_conciliacion`, `fn_fdi_registrar_recepcion`
-- y los reportes de la fase 8 (`fn_fdi_reporte_*`). Son anteriores a esta fase
-- y tienen consumidores; el rollback de los pendientes no puede llevárselos.
--
-- Tras aplicarlo, `verify/09_pendientes.sql` falla (no resuelve las funciones):
-- es lo esperado.
--
-- Es transaccional: o sale todo o no sale nada.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) Retirar las 4 funciones de la fase 9
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.fn_fdi_facturas(bigint, date, date);
DROP FUNCTION IF EXISTS public.fn_fdi_recepciones_historial(bigint, date, date);
DROP FUNCTION IF EXISTS public.fn_fdi_pendientes_detalle(bigint, bigint);
DROP FUNCTION IF EXISTS public.fn_fdi_pendientes_panel(bigint, text);

-- ---------------------------------------------------------------------------
-- 2) Verificación final: no quedan funciones y el resto sigue en su sitio
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v         integer;
    v_firmas  text[] := ARRAY[
        'public.fn_fdi_pendientes_panel(bigint,text)',
        'public.fn_fdi_pendientes_detalle(bigint,bigint)',
        'public.fn_fdi_recepciones_historial(bigint,date,date)',
        'public.fn_fdi_facturas(bigint,date,date)'
    ];
    v_nombre  text;
BEGIN
    FOREACH v_nombre IN ARRAY v_firmas LOOP
        IF to_regprocedure(v_nombre) IS NOT NULL THEN
            RAISE EXCEPTION 'Rollback 09: % sigue existiendo', v_nombre USING ERRCODE = 'P0002';
        END IF;
    END LOOP;

    -- Sin sobrecargas residuales con esos nombres (una firma vieja se quedaría
    -- viva si solo se hubiera borrado la actual).
    SELECT count(*) INTO v
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname IN ('fn_fdi_pendientes_panel', 'fn_fdi_pendientes_detalle',
                         'fn_fdi_recepciones_historial', 'fn_fdi_facturas');
    IF v <> 0 THEN
        RAISE EXCEPTION 'Rollback 09: quedan % función(es) con nombre de la fase 9', v;
    END IF;

    -- Lo anterior a la fase 9 sigue intacto: el rollback no se lleva nada más.
    IF to_regprocedure('public.fn_fdi_compra_recepcion_pendiente(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Rollback 09: desapareció fn_fdi_compra_recepcion_pendiente(bigint)';
    END IF;
    IF to_regprocedure('public.fn_fdi_compra_costo_resumen(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Rollback 09: desapareció fn_fdi_compra_costo_resumen(bigint)';
    END IF;
    IF to_regprocedure('public.fn_fdi_conciliacion(bigint)') IS NULL THEN
        RAISE EXCEPTION 'Rollback 09: desapareció fn_fdi_conciliacion(bigint)';
    END IF;
    IF to_regprocedure('public.fn_fdi_reporte_compras(bigint,date,date)') IS NULL THEN
        RAISE EXCEPTION 'Rollback 09: desapareció fn_fdi_reporte_compras(bigint,date,date)';
    END IF;
    IF to_regclass('public.fdi_dat_compra') IS NULL THEN
        RAISE EXCEPTION 'Rollback 09: desapareció fdi_dat_compra';
    END IF;

    RAISE NOTICE 'Rollback 09 aplicado: 4 funciones retiradas; recepción, costo, conciliación y reportes quedan intactos.';
END;
$$;

COMMIT;