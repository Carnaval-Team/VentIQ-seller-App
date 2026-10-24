-- ============================================================================
-- fn_listar_operaciones_inventario_new: filtro por monto exacto (server-side)
-- ============================================================================
-- Problema: el filtro "Monto exacto" de la app solo filtraba en cliente sobre
-- la página ya cargada; operaciones fuera de esa página nunca coincidían.
--
-- Fix: nuevo parámetro p_monto_exacto. La función ya calcula ops.total_op en
-- el CTE todas_ops, así que basta un AND en el WHERE externo, ANTES del
-- ORDER BY / LIMIT, para que la paginación y total_count respeten el filtro.
--
-- Comparación: tolerancia de medio centavo (abs(total - monto) < 0.005) en
-- vez de igualdad flotante, para que 30.00 coincida con totales guardados
-- con más decimales (30.0012 por factor_rel, etc.).
--
-- Aplicar en Newa (SQL editor). Idempotente: no hace nada si ya está aplicado.
-- ============================================================================

BEGIN;

DO $mig$
DECLARE
    v_oid oid;
    v_src text;
    v_new text;
    v_sig_old constant text :=
        'p_contabilizada boolean DEFAULT NULL::boolean)';
    v_sig_new constant text :=
        'p_contabilizada boolean DEFAULT NULL::boolean, '
        || 'p_monto_exacto numeric DEFAULT NULL::numeric)';
    v_anchor constant text := 'ORDER BY ops.created_at DESC';
    v_clause constant text :=
        'AND (p_monto_exacto IS NULL'
        || ' OR abs(ops.total_op - p_monto_exacto) < 0.005)'
        || E'\n    ';
    v_n int;
BEGIN
    SELECT p.oid INTO v_oid
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'fn_listar_operaciones_inventario_new'
    ORDER BY p.oid DESC
    LIMIT 1;

    IF v_oid IS NULL THEN
        RAISE EXCEPTION 'No existe fn_listar_operaciones_inventario_new';
    END IF;

    v_src := pg_get_functiondef(v_oid);

    IF position('p_monto_exacto' IN v_src) > 0 THEN
        RAISE NOTICE 'La función ya tiene p_monto_exacto; nada que hacer';
        RETURN;
    END IF;

    -- Estructura esperada: una sola firma y un solo ORDER BY final.
    IF position(v_sig_old IN v_src) = 0 THEN
        RAISE EXCEPTION 'Firma no coincide con la versión esperada';
    END IF;
    IF position('ops.total_op' IN v_src) = 0
       OR position('p_id_medio_pago IS NULL OR EXISTS' IN v_src) = 0 THEN
        RAISE EXCEPTION 'No se encontró el WHERE externo esperado';
    END IF;

    SELECT count(*) INTO v_n
      FROM regexp_matches(v_src, 'ORDER BY ops\.created_at DESC', 'g');
    IF v_n <> 1 THEN
        RAISE EXCEPTION 'Se esperaba 1 ORDER BY ops.created_at DESC; hay %', v_n;
    END IF;

    v_new := replace(v_src, v_sig_old, v_sig_new);
    v_new := replace(v_new, v_anchor, v_clause || v_anchor);

    EXECUTE v_new;

    -- pg_get_functiondef emite CREATE OR REPLACE: al cambiar la firma se crea
    -- una sobrecarga, no un reemplazo. Eliminar la versión de 12 parámetros.
    DROP FUNCTION public.fn_listar_operaciones_inventario_new(
        bigint, bigint, bigint, smallint[], date, date, uuid,
        text, integer, integer, bigint, boolean);

    RAISE NOTICE 'fn_listar_operaciones_inventario_new: p_monto_exacto agregado';
END;
$mig$;

COMMIT;

-- Verificación: debe devolver corregida = true
SELECT
    p.oid::regprocedure AS funcion,
    position('p_monto_exacto' IN p.prosrc) > 0 AS corregida
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_listar_operaciones_inventario_new';

-- Prueba funcional (ajustar id_tienda / monto):
-- SELECT id, total FROM public.fn_listar_operaciones_inventario_new(
--     p_id_tienda := 4, p_monto_exacto := 30.00, p_limite := 20, p_pagina := 1);
