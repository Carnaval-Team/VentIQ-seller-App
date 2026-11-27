-- ============================================================================
-- 13c_precio_promedio_unidad.sql — `_v2` capitaliza el TOTAL por unidad
--
-- Entorno: `newa` (qhprswhhfasrikhawjoz). NO aplicar en main.
-- Fecha: 2026-11-26 · Plan: docs/planes/fondo-inversion/15-plan-compras-costos.md
--
-- `app_dat_recepcion_producto_costo.monto_usd` es el importe TOTAL de la línea
-- (D1). `_v2` lo sumaba como si fuera unitario y por eso el costo quedaba en
-- 250,50 en vez de 0,55. Este parche, aplicado sobre la definición VIVA de la
-- función (con anclas exactas y aborto si no coinciden), cambia solo:
--   · unitario = monto_usd / cantidad_base
--   · costo_real = precio + Σ unitarios
--   · promedio del catálogo = unitario, no el total
-- ============================================================================

DO $$
DECLARE
    d text;
    n text;
BEGIN
    d := pg_get_functiondef('public.fn_actualizar_precio_promedio_recepcion_v2_m01(bigint,jsonb)'::regprocedure);
    n := d;

    -- 1. Variable nueva.
    IF position('    v_adicionales   numeric;' in n) = 0 THEN
        RAISE EXCEPTION '13c: ancla de declaración no encontrada';
    END IF;
    n := replace(n,
        '    v_adicionales   numeric;',
        '    v_adicionales   numeric;
    v_unit          numeric;');

    -- 2. Unitario antes de ponderar.
    IF position('            IF (v_saldo_base + v_cant_base_ln) = 0 THEN' in n) = 0 THEN
        RAISE EXCEPTION '13c: ancla del IF de ponderación no encontrada';
    END IF;
    n := replace(n,
        '            IF (v_saldo_base + v_cant_base_ln) = 0 THEN',
        '            v_unit := CASE WHEN v_cant_base_ln > 0
                           THEN v_costo.monto_usd / v_cant_base_ln
                           ELSE 0 END;

            IF (v_saldo_base + v_cant_base_ln) = 0 THEN');

    -- 3. Las dos ramas usan el unitario.
    IF position('v_nuevo_avg := v_costo.monto_usd;' in n) = 0 THEN
        RAISE EXCEPTION '13c: ancla de v_nuevo_avg no encontrada';
    END IF;
    n := replace(n, 'v_nuevo_avg := v_costo.monto_usd;', 'v_nuevo_avg := v_unit;');

    -- 4. Ponderación con unitario.
    IF position('+ (v_costo.monto_usd * v_cant_base_ln)' in n) = 0 THEN
        RAISE EXCEPTION '13c: ancla de ponderación no encontrada';
    END IF;
    n := replace(n, '+ (v_costo.monto_usd * v_cant_base_ln)', '+ (v_unit * v_cant_base_ln)');

    -- 5. Catálogo del producto: también unitario.
    IF position('v_costo.monto_usd, v_nuevo_avg, true' in n) = 0 THEN
        RAISE EXCEPTION '13c: ancla del INSERT en app_dat_producto_costo no encontrada';
    END IF;
    n := replace(n, 'v_costo.monto_usd, v_nuevo_avg, true', 'v_unit, v_nuevo_avg, true');

    -- 6. costo_real por unidad de presentación.
    IF position('SET costo_real = COALESCE(v_puro_dto, 0) + (v_adicionales * v_factor_rel)' in n) = 0 THEN
        RAISE EXCEPTION '13c: ancla de costo_real no encontrada';
    END IF;
    n := replace(n,
        'SET costo_real = COALESCE(v_puro_dto, 0) + (v_adicionales * v_factor_rel)',
        'SET costo_real = COALESCE(v_puro_dto, 0) + COALESCE(v_adicionales / NULLIF(v_cant_base_ln / NULLIF(v_factor_rel, 0), 0), 0)');

    -- 7. Ponderación final: el total se divide por la cantidad base.
    IF position('), 0) AS costo_base' in n) = 0 THEN
        RAISE EXCEPTION '13c: ancla de costo_base no encontrada';
    END IF;
    n := replace(n,
        '), 0) AS costo_base',
        '), 0) / NULLIF(en.cantidad * COALESCE(f.factor_rel, 1), 0) AS costo_base');

    IF n = d THEN
        RAISE EXCEPTION '13c: no se aplicó ningún cambio';
    END IF;

    EXECUTE n;
END;
$$;

NOTIFY pgrst, 'reload schema';
