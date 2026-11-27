-- ============================================================================
-- 13f_ajuste_tardio_cantidad.sql — el ajuste posterior también reparte por cantidad
--
-- Entorno de referencia: `newa` (qhprswhhfasrikhawjoz). Para main, aplicar en
-- el orden del plan de promoción.
-- Fecha: 2026-11-26 · Plan: docs/planes/fondo-inversion/15-plan-compras-costos.md
--
-- Parchea dos funciones sobre su definición VIVA (con anclas exactas y aborto
-- si no coinciden), sin reescribir 200 líneas a mano:
--   · fn_fdi_compra_ajuste_financiar: reparte por CANTIDAD BASE, no por valor.
--   · fn_fdi_compra_ajuste_agregar: guarda `reparto = 'cantidad'`.
--
-- Idempotente: si ya está aplicado, no hace nada.
-- ============================================================================

DO $$
DECLARE
    d text;
    n text;
BEGIN
    -- ── Financiar: reparto por cantidad base ──────────────────────────────
    d := pg_get_functiondef('public.fn_fdi_compra_ajuste_financiar(bigint,jsonb,uuid)'::regprocedure);
    IF position('b.cantidad_base' in d) = 0 THEN
        n := d;

        IF position('SELECT count(*), COALESCE(sum(base), 0) INTO v_bases, v_base_tot' in n) = 0 THEN
            RAISE EXCEPTION '13f: ancla guard bases no encontrada';
        END IF;
        n := replace(n,
            'SELECT count(*), COALESCE(sum(base), 0) INTO v_bases, v_base_tot',
            'SELECT count(*), COALESCE(sum(cantidad_base), 0) INTO v_bases, v_base_tot');
        n := replace(n,
            'SELECT b.id_recepcion_producto, b.base
          FROM public.fdi_dat_compra_recepcion r',
            'SELECT b.id_recepcion_producto, b.cantidad_base
          FROM public.fdi_dat_compra_recepcion r');

        IF position('SELECT r.id AS id_link, b.id_recepcion_producto, b.id_producto, b.base' in n) = 0 THEN
            RAISE EXCEPTION '13f: ancla bases no encontrada';
        END IF;
        n := replace(n,
            'SELECT r.id AS id_link, b.id_recepcion_producto, b.id_producto, b.base',
            'SELECT r.id AS id_link, b.id_recepcion_producto, b.id_producto, b.cantidad_base');

        IF position('tot AS (SELECT COALESCE(sum(base), 0) AS total FROM bases)' in n) = 0 THEN
            RAISE EXCEPTION '13f: ancla tot no encontrada';
        END IF;
        n := replace(n,
            'tot AS (SELECT COALESCE(sum(base), 0) AS total FROM bases)',
            'tot AS (SELECT COALESCE(sum(cantidad_base), 0) AS total FROM bases)');

        IF position('round(v_aj.monto_capitalizado * b.base / NULLIF(t.total, 0), 2)' in n) = 0 THEN
            RAISE EXCEPTION '13f: ancla prorr no encontrada';
        END IF;
        n := replace(n,
            'round(v_aj.monto_capitalizado * b.base / NULLIF(t.total, 0), 2)',
            'round(v_aj.monto_capitalizado * b.cantidad_base / NULLIF(t.total, 0), 2)');

        IF position('ORDER BY base DESC, id_recepcion_producto ASC LIMIT 1' in n) = 0 THEN
            RAISE EXCEPTION '13f: ancla destino no encontrada';
        END IF;
        n := replace(n,
            'ORDER BY base DESC, id_recepcion_producto ASC LIMIT 1',
            'ORDER BY cantidad_base DESC, id_recepcion_producto ASC LIMIT 1');

        IF n = d THEN
            RAISE EXCEPTION '13f: financiar sin cambios';
        END IF;
        EXECUTE n;
    END IF;

    -- ── Agregar: reparto por cantidad ─────────────────────────────────────
    d := pg_get_functiondef('public.fn_fdi_compra_ajuste_agregar(bigint,bigint,text,numeric,text,boolean,uuid)'::regprocedure);
    IF position('p_base, p_valor, p_reparto,' in d) > 0 THEN
        n := replace(d,
            'p_id_compra, v_c.id_tienda, p_id_tipo_costo, p_base, p_valor, p_reparto,',
            'p_id_compra, v_c.id_tienda, p_id_tipo_costo, p_base, p_valor, ''cantidad'',');
        IF n = d THEN
            RAISE EXCEPTION '13f: ancla de ajuste_agregar no encontrada';
        END IF;
        EXECUTE n;
    END IF;
END;
$$;

NOTIFY pgrst, 'reload schema';
