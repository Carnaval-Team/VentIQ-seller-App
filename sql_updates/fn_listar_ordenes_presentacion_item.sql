-- ============================================================================
-- fn_listar_ordenes + listar_ordenes_mesa:
-- exponer id_presentacion + presentacion_nombre por item
-- ============================================================================
-- Problema: el detalle de la orden en la app no diferenciaba presentaciones
-- del mismo producto. Las funciones ya hacen los JOINs (pp = fila de
-- app_dat_producto_presentacion, np = nomenclador) y devolvían solo
-- 'presentacion' = np.denominacion. La app lee `id_presentacion` (para la
-- identidad de la línea al agrupar items) y `presentacion_nombre` (los
-- mismos nombres que guardan las órdenes pendientes locales), así que
-- ambos llegaban NULL y las filas del mismo producto se fusionaban.
--
-- Fix: agregar ambas claves al jsonb_build_object de 'items', conservando
-- 'presentacion' por compatibilidad con consumidores actuales.
--
-- Aplicar en Newa (SQL editor). Idempotente.
-- ============================================================================

BEGIN;

DO $mig$
DECLARE
    v_oid oid;
    v_src text;
    v_new text;
    v_anchor constant text :=
        '''presentacion'',     np.denominacion,';
    v_insert constant text :=
        '''presentacion'',     np.denominacion,' || E'\n'
        || '                    ''id_presentacion'',     ep.id_presentacion,' || E'\n'
        || '                    ''presentacion_nombre'', np.denominacion,';
    v_n int;
BEGIN
    SELECT p.oid INTO v_oid
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'fn_listar_ordenes'
    ORDER BY p.oid DESC
    LIMIT 1;

    IF v_oid IS NULL THEN
        RAISE EXCEPTION 'No existe fn_listar_ordenes';
    END IF;

    v_src := pg_get_functiondef(v_oid);

    IF position('''presentacion_nombre''' IN v_src) > 0 THEN
        RAISE NOTICE 'fn_listar_ordenes ya expone presentacion_nombre';
        RETURN;
    END IF;

    -- El anchor debe aparecer exactamente una vez (el objeto de 'items').
    SELECT count(*) INTO v_n FROM regexp_matches(v_src,
        '''presentacion'',     np\.denominacion,', 'g');
    IF v_n <> 1 THEN
        RAISE EXCEPTION
            'Se esperaba 1 aparición de la clave presentacion; hay %', v_n;
    END IF;

    -- Los JOINs pp/np tienen que existir ya.
    IF position('app_dat_producto_presentacion pp ON ep.id_presentacion = pp.id'
                IN v_src) = 0
       OR position('app_nom_presentacion np' IN v_src) = 0 THEN
        RAISE EXCEPTION 'No se encontraron los JOINs pp/np esperados';
    END IF;

    v_new := replace(v_src, v_anchor, v_insert);
    EXECUTE v_new;
    RAISE NOTICE 'fn_listar_ordenes: items ahora incluyen id_presentacion y presentacion_nombre';
END;
$mig$;

-- ---------------------------------------------------------------------------
-- listar_ordenes_mesa: mismo fix (el detalle de cuentas de mesa usa esta RPC)
-- ---------------------------------------------------------------------------
DO $mig$
DECLARE
    v_oid oid;
    v_src text;
    v_new text;
    -- En listar_ordenes_mesa el formato es distinto: un solo espacio.
    v_anchor constant text := '''presentacion'', np.denominacion,';
    v_insert constant text :=
        '''presentacion'', np.denominacion,' || E'\n'
        || '        ''id_presentacion'', ep.id_presentacion,' || E'\n'
        || '        ''presentacion_nombre'', np.denominacion,';
    v_n int;
BEGIN
    SELECT p.oid INTO v_oid
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'listar_ordenes_mesa'
    ORDER BY p.oid DESC
    LIMIT 1;

    IF v_oid IS NULL THEN
        RAISE NOTICE 'No existe listar_ordenes_mesa; se omite';
        RETURN;
    END IF;

    v_src := pg_get_functiondef(v_oid);

    IF position('''presentacion_nombre''' IN v_src) > 0 THEN
        RAISE NOTICE 'listar_ordenes_mesa ya expone presentacion_nombre';
        RETURN;
    END IF;

    SELECT count(*) INTO v_n FROM regexp_matches(v_src,
        '''presentacion'', np\.denominacion,', 'g');
    IF v_n <> 1 THEN
        RAISE EXCEPTION
            'listar_ordenes_mesa: se esperaba 1 aparición del anchor; hay %', v_n;
    END IF;

    IF position('app_nom_presentacion np' IN v_src) = 0
       OR position('app_dat_producto_presentacion pp' IN v_src) = 0 THEN
        RAISE EXCEPTION
            'listar_ordenes_mesa: no se encontraron los JOINs pp/np esperados';
    END IF;

    v_new := replace(v_src, v_anchor, v_insert);
    EXECUTE v_new;
    RAISE NOTICE 'listar_ordenes_mesa: items ahora incluyen id_presentacion y presentacion_nombre';
END;
$mig$;

COMMIT;

-- Verificación: debe devolver corregida = true
SELECT
    p.oid::regprocedure AS funcion,
    position('''id_presentacion''' IN p.prosrc) > 0
        AND position('''presentacion_nombre''' IN p.prosrc) > 0 AS corregida
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('fn_listar_ordenes', 'listar_ordenes_mesa');
