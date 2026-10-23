-- ============================================================================
-- 13 · Operaciones: importe de extracción/transferencia con factor_rel
-- ============================================================================
-- En inventario (extracción / transferencia), `precio_unitario` es el precio
-- de la unidad BASE (app_dat_precio_venta). La `cantidad` está en la
-- presentación de la línea. El listing hacía:
--
--   COALESCE(ep.importe, ep.precio_unitario * ep.cantidad)
--
-- → qty presentación × precio base. Incorrecto.
--
-- Correcto (inventario):
--   precio_base × equivalente_base
--   = precio_base × cantidad × factor_rel
--
-- NO aplicar la misma fórmula a la rama de VENTAS: ahí `precio_unitario`
-- ya viene como precio_base × factor (convención del TPV) y el importe es
-- precio × cantidad. Multiplicar otra vez por factor_rel lo duplicaría.
--
-- Método: sustituir las 4 apariciones y revertir solo la primera (VENTAS).
--
-- Prerrequisito: script 12. Aplicar en newa (SQL editor). Idempotente.
-- MCP newa suele ser read-only para CREATE FUNCTION: pegar en el SQL editor.
-- ============================================================================

DO $mig$
DECLARE
    v_oid oid;
    v_src text;
    v_new text;
    v_n_old int;
    v_n_new int;
    v_old constant text :=
      '''importe'',        COALESCE(ep.importe, ep.precio_unitario * ep.cantidad)';
    v_repl constant text :=
      '''importe'',        ROUND(ep.precio_unitario * COALESCE('
      || '(public.fn_presentacion_item_json(ep.id_presentacion, ep.cantidad)'
      || '->>''equivalente_base'')::numeric, ep.cantidad), 6)';
BEGIN
    SELECT p.oid INTO v_oid
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'fn_listar_operaciones_inventario_new'
    ORDER BY p.oid DESC
    LIMIT 1;

    IF v_oid IS NULL THEN
        RAISE EXCEPTION '13: no existe fn_listar_operaciones_inventario_new';
    END IF;

    v_src := pg_get_functiondef(v_oid);

    -- Idempotencia: 3 bloques nuevos + 1 COALESCE de ventas.
    SELECT count(*) INTO v_n_new
      FROM regexp_matches(
        v_src,
        'equivalente_base''\)::numeric, ep\.cantidad\), 6\)',
        'g'
      );
    SELECT count(*) INTO v_n_old
      FROM regexp_matches(
        v_src,
        'COALESCE\(ep\.importe, ep\.precio_unitario \* ep\.cantidad\)',
        'g'
      );

    IF v_n_new = 3 AND v_n_old = 1 THEN
        RAISE NOTICE '13: ya aplicado (3 inventario + 1 venta), no se toca';
        RETURN;
    END IF;

    IF v_src NOT LIKE '%fn_presentacion_item_json(ep.id_presentacion, ep.cantidad)%' THEN
        RAISE EXCEPTION
          '13: falta el parche 12 (fn_presentacion_item_json en extracción).';
    END IF;

    IF v_n_old <> 4 THEN
        RAISE EXCEPTION
          '13: se esperaban 4 COALESCE de importe en ep, hay %', v_n_old;
    END IF;

    -- Sustituye las 4, luego revierte la primera (rama VENTAS, sin flag 'g').
    v_new := replace(v_src, v_old, v_repl);
    v_new := regexp_replace(
        v_new,
        '''importe'',        ROUND\(ep\.precio_unitario \* COALESCE\('
        || '\(public\.fn_presentacion_item_json\(ep\.id_presentacion, ep\.cantidad\)'
        || '->>''equivalente_base''\)::numeric, ep\.cantidad\), 6\)',
        v_old
    );

    SELECT count(*) INTO v_n_new
      FROM regexp_matches(
        v_new,
        'equivalente_base''\)::numeric, ep\.cantidad\), 6\)',
        'g'
      );
    SELECT count(*) INTO v_n_old
      FROM regexp_matches(
        v_new,
        'COALESCE\(ep\.importe, ep\.precio_unitario \* ep\.cantidad\)',
        'g'
      );

    IF v_n_new <> 3 OR v_n_old <> 1 THEN
        RAISE EXCEPTION
          '13: tras el parche se esperaban 3 nuevos + 1 COALESCE venta; '
          'hay nuevos=% viejos=%', v_n_new, v_n_old;
    END IF;

    EXECUTE v_new;
    RAISE NOTICE
      '13: importe inventario = precio_base × equivalente_base (3 bloques); venta intacta';
END
$mig$;
