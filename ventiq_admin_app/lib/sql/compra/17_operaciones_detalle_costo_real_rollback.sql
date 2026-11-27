-- ============================================================================
-- 17_operaciones_detalle_costo_real_rollback.sql
--
-- Retira `costo_real` de los items de recepción de
-- `fn_listar_operaciones_inventario_new`. Idempotente.
-- ============================================================================

DO $$
DECLARE
    d text;
    n text;
BEGIN
    d := pg_get_functiondef(
        'public.fn_listar_operaciones_inventario_new(bigint,bigint,bigint,smallint[],date,date,uuid,text,integer,integer,bigint,boolean,numeric)'::regprocedure
    );

    IF position('''costo_real'', rp.costo_real' in d) = 0 THEN
        RETURN; -- ya está fuera
    END IF;

    n := replace(d,
        ''', ''costo_real'', rp.costo_real',
        '');

    IF n = d THEN
        RAISE EXCEPTION 'Rollback 17: no se pudo retirar costo_real';
    END IF;

    EXECUTE n;
END;
$$;

NOTIFY pgrst, 'reload schema';
