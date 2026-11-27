-- ============================================================================
-- 17_operaciones_detalle_costo_real.sql — el detalle de la operación muestra
-- el costo final de una recepción, no solo el precio de factura
--
-- Entorno: `newa` (qhprswhhfasrikhawjoz). Para main, aplicar después de 15.
-- Fecha: 2026-11-27.
--
-- `fn_listar_operaciones_inventario_new` devolvía en `detalles.items` la
-- recepción con `precio_unitario` (factura) pero no `costo_real` (unitario ya
-- capitalizado con importadora y adicionales). En el detalle se veía 1,94
-- cuando el costo real era 3,54. Se añade `costo_real` a los dos bloques de
-- recepción del JSON. Es aditivo e idempotente.
-- ============================================================================

DO $$
DECLARE
    d text;
    n text;
BEGIN
    d := pg_get_functiondef(
        'public.fn_listar_operaciones_inventario_new(bigint,bigint,bigint,smallint[],date,date,uuid,text,integer,integer,bigint,boolean,numeric)'::regprocedure
    );

    IF position('''costo_real'', rp.costo_real' in d) > 0 THEN
        RETURN; -- ya aplicado
    END IF;

    n := replace(d,
        '''precio_unitario'', rp.precio_unitario',
        '''precio_unitario'', rp.precio_unitario, ''costo_real'', rp.costo_real');

    IF n = d THEN
        RAISE EXCEPTION '17: ancla de recepción no encontrada';
    END IF;

    EXECUTE n;
END;
$$;

NOTIFY pgrst, 'reload schema';
