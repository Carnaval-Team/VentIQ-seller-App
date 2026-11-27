-- ============================================================================
-- 13e_detalle_valor_recibido.sql — el detalle muestra el valor recibido real
--
-- Entorno: `newa` (qhprswhhfasrikhawjoz). NO aplicar en main.
-- Fecha: 2026-11-26 · Plan: docs/planes/fondo-inversion/15-plan-compras-costos.md
--
-- `fn_fdi_compra_detalle` devolvía `to_jsonb(r)` con `monto_valorizado` = 0 en
-- los vínculos viejos (nunca se escribió). El panel de recepciones mostraba
-- «0,00». Se añade `valor_recibido` al JSON: el campo guardado o, si es 0, la
-- suma de las líneas atribuidas.
-- ============================================================================

DO $$
DECLARE
    d text;
    n text;
BEGIN
    d := pg_get_functiondef('public.fn_fdi_compra_detalle(bigint)'::regprocedure);
    IF position('valor_recibido' in d) > 0 THEN
        RETURN; -- ya aplicado
    END IF;
    n := replace(d,
        '(SELECT jsonb_agg(to_jsonb(r) ORDER BY r.id)',
        '(SELECT jsonb_agg(to_jsonb(r) || jsonb_build_object(''valor_recibido'', COALESCE(NULLIF(r.monto_valorizado, 0), (SELECT sum(rl.cantidad_recibida * COALESCE(rl.costo_unitario_aplicado, 0)) FROM public.fdi_dat_compra_recepcion_linea rl WHERE rl.id_compra_recepcion = r.id), 0)) ORDER BY r.id)');
    IF n = d THEN
        RAISE EXCEPTION '13e: ancla de recepciones no encontrada';
    END IF;
    EXECUTE n;
END;
$$;

NOTIFY pgrst, 'reload schema';
