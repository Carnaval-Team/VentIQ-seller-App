-- ============================================================================
-- Inventario admin: listar productos no vendibles si son inventariables
-- ============================================================================
-- La app ya desplegada llama
--   fn_listar_inventario_productos_paged2_grouped2_optimiized
-- con p_es_vendible = true. Este script amplía esa función (y las grouped
-- hermanas de inventario) para que, al pedir vendibles, también entren los
-- inventariables aunque no se vendan.
--
-- No toca fn_listar_inventario_productos_paged2: el TPV la usa para vender.
-- Idempotente. Proyecto: main.
-- ============================================================================

DO $patch$
DECLARE
  r record;
  v_def text;
  v_new text;
  v_nl text := chr(13) || chr(10) || '            AND (p_es_inventariable';
  v_count int := 0;
  v_funcs int := 0;
  v_old_p text := 'AND (p_es_vendible IS NULL OR p.es_vendible = p_es_vendible)';
  v_old_p_spaced text := 'AND (p_es_vendible    IS NULL OR p.es_vendible          = p_es_vendible)';
  v_old_inv_spaced text := 'AND (p_es_vendible    IS NULL OR inv.es_vendible        = p_es_vendible)';
  v_new_p text := 'AND (p_es_vendible IS NULL OR p.es_vendible = p_es_vendible OR (p_es_vendible IS TRUE AND COALESCE(p.es_inventariable, false)))';
  v_new_inv text := 'AND (p_es_vendible IS NULL OR inv.es_vendible = p_es_vendible OR (p_es_vendible IS TRUE AND COALESCE(inv.es_inventariable, false)))';
BEGIN
  FOR r IN
    SELECT p.oid
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname LIKE 'fn_listar_inventario_productos_paged2_grouped%'
  LOOP
    v_funcs := v_funcs + 1;
    v_def := pg_get_functiondef(r.oid);

    IF position(v_old_p || v_nl IN v_def) = 0
       AND position(v_old_p_spaced || v_nl IN v_def) = 0
       AND position(v_old_inv_spaced || v_nl IN v_def) = 0 THEN
      RAISE NOTICE 'Ya aplicado o sin el filtro esperado: %', r.oid::regprocedure;
      CONTINUE;
    END IF;

    v_new := replace(v_def, v_old_p_spaced || v_nl, v_new_p || v_nl);
    v_new := replace(v_new, v_old_inv_spaced || v_nl, v_new_inv || v_nl);
    v_new := replace(v_new, v_old_p || v_nl, v_new_p || v_nl);

    IF v_new = v_def THEN
      RAISE EXCEPTION 'No se pudo reemplazar el filtro en %', r.oid::regprocedure;
    END IF;

    EXECUTE v_new;
    v_count := v_count + 1;
    RAISE NOTICE 'Actualizada: %', r.oid::regprocedure;
  END LOOP;

  IF v_funcs = 0 THEN
    RAISE EXCEPTION 'No existe la funcion grouped de inventario en public';
  END IF;

  IF v_count = 0 THEN
    RAISE NOTICE 'Nada que cambiar';
  END IF;
END
$patch$;
