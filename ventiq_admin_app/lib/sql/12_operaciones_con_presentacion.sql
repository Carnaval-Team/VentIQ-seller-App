-- ============================================================================
-- 12 · Lista de Operaciones: presentación por línea
-- ============================================================================
-- Misma lógica que presentaciones_inventario/28_operaciones_con_presentacion.sql
-- pero compatible con la firma ACTUAL en newa (12 params, con
-- p_id_medio_pago / p_contabilizada). El 28 original apuntaba a la firma
-- vieja de 10 params y fallaba al aplicar → la UI no veía presentacion_nombre
-- ni cantidad_formateada, y el total/costo se leía mal.
--
-- Prerrequisito: fn_presentacion_item_json(bigint, numeric) en newa.
-- Aplicar en newa (SQL editor). Idempotente.
-- ============================================================================

DO $mig$
DECLARE
    v_oid oid;
    v_src text;
    v_new text;
    v_n   int;
BEGIN
    SELECT p.oid INTO v_oid
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'fn_listar_operaciones_inventario_new'
    ORDER BY p.oid DESC
    LIMIT 1;

    IF v_oid IS NULL THEN
        RAISE EXCEPTION '12: no existe fn_listar_operaciones_inventario_new';
    END IF;

    v_src := pg_get_functiondef(v_oid);

    IF v_src LIKE '%fn_presentacion_item_json%' THEN
        RAISE NOTICE '12: ya aplicado, no se toca nada';
        RETURN;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND p.proname = 'fn_presentacion_item_json'
    ) THEN
        RAISE EXCEPTION
          '12: falta fn_presentacion_item_json. Aplica presentaciones_inventario/15 primero.';
    END IF;

    v_new := v_src;

    -- Extracción (ep) · anclado en la última clave 'importe'
    v_new := regexp_replace(
        v_new,
        '(''importe'',\s+COALESCE\(ep\.importe, ep\.precio_unitario \* ep\.cantidad\))(\s*\r?\n\s*)\)\)',
        E'\\1\\2) || public.fn_presentacion_item_json(ep.id_presentacion, ep.cantidad))',
        'g'
    );

    SELECT count(*) INTO v_n
      FROM regexp_matches(v_new, 'fn_presentacion_item_json\(ep\.id_presentacion, ep\.cantidad\)', 'g');
    IF v_n <> 4 THEN
        RAISE EXCEPTION '12: se esperaban 4 bloques de extraccion (ep), hay %', v_n;
    END IF;

    -- Recepción (rp) · última clave 'precio_unitario'
    v_new := regexp_replace(
        v_new,
        '(''precio_unitario'',\s+rp\.precio_unitario)(\s*\r?\n\s*)\)\)',
        E'\\1\\2) || public.fn_presentacion_item_json(rp.id_presentacion, rp.cantidad))',
        'g'
    );

    SELECT count(*) INTO v_n
      FROM regexp_matches(v_new, 'fn_presentacion_item_json\(rp\.id_presentacion, rp\.cantidad\)', 'g');
    IF v_n <> 2 THEN
        RAISE EXCEPTION '12: se esperaban 2 bloques de recepcion (rp), hay %', v_n;
    END IF;

    -- Control / conteo (cp): cierra con 'almacen' y un solo ')'
    -- (en newa el bloque usa ubicacion+almacen; no el patrón viejo del 28).
    v_new := regexp_replace(
        v_new,
        '(''almacen'',\s+COALESCE\(alm\.denominacion, ''''\))(\s*\r?\n\s*)\)',
        E'\\1\\2) || public.fn_presentacion_item_json(cp.id_presentacion, cp.cantidad)',
        'g'
    );

    SELECT count(*) INTO v_n
      FROM regexp_matches(
        v_new,
        'fn_presentacion_item_json\(cp\.id_presentacion, cp\.cantidad\)',
        'g'
      );
    IF v_n < 1 THEN
        RAISE EXCEPTION
          '12: se esperaba >=1 bloque de control (cp), hay %. '
          'Revisa el ancla ''almacen'' del jsonb de control.',
          v_n;
    END IF;

    SELECT count(*) INTO v_n FROM regexp_matches(v_new, '''sku_producto''', 'g');
    IF v_n <> 8 THEN
        RAISE EXCEPTION '12: sku_producto aparecia 8 veces, ahora %', v_n;
    END IF;

    SELECT count(*) INTO v_n FROM regexp_matches(v_new, '''producto_nombre''', 'g');
    IF v_n <> 8 THEN
        RAISE EXCEPTION '12: producto_nombre aparecia 8 veces, ahora %', v_n;
    END IF;

    SELECT count(*) INTO v_n FROM regexp_matches(v_new, '''importe''', 'g');
    IF v_n <> 4 THEN
        RAISE EXCEPTION '12: importe aparecia 4 veces, ahora %', v_n;
    END IF;

    SELECT count(*) INTO v_n FROM regexp_matches(v_new, 'fn_presentacion_item_json', 'g');
    IF v_n <> 7 THEN
        RAISE EXCEPTION '12: se esperaban 7 inserciones en total, hay %', v_n;
    END IF;

    IF v_new NOT LIKE '%RETURNS TABLE%' THEN
        RAISE EXCEPTION '12: no se encontro el RETURNS TABLE';
    END IF;

    EXECUTE v_new;
    RAISE NOTICE '12: fn_listar_operaciones_inventario_new parcheada (7 bloques)';
END
$mig$;
