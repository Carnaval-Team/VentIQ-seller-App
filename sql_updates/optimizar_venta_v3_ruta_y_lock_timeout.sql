-- =============================================================================
-- Optimización de la venta (fn_registrar_venta_v3 / fn_registrar_venta_mesa_v3)
-- =============================================================================
-- Contexto (estudio 2026-10-29, Main):
--   * rol authenticated: statement_timeout = 8s; lock_timeout = 0.
--   * fn_registrar_venta_v3: media 938 ms, máximo 7 839 ms (roza el corte de 8s).
--   * fn_ejecutar_entrega_fisica_v3 toma pg_advisory_xact_lock por
--     producto|ubicación|variante|opción: dos cajas vendiendo lo mismo se
--     serializan y, con lock_timeout = 0, la segunda espera hasta morir por
--     statement_timeout sin mensaje claro.
--   * fn_resolver_origen_venta se ejecuta DOS veces por línea: en la venta y
--     otra vez dentro de fn_descontar_venta_enrutada_v2.
--
-- Cambios:
--   1. fn_descontar_venta_enrutada_v2 acepta p_ruta jsonb DEFAULT NULL y la
--      reutiliza si corresponde al mismo producto (si no, la resuelve como antes).
--      Los llamadores que no pasan p_ruta (fn_pedir_item_cuenta_v2) no cambian.
--   2. Pasan p_ruta := v_ruta los cuerpos que descuentan:
--      fn_registrar_venta_v3_impl y fn_registrar_venta_mesa_v3_impl.
--      Las funciones públicas homónimas son la envoltura de
--      sql_updates/fix_venta_rollback_parcial.sql: solo llaman al _impl y
--      revierten si el resultado no es success. Por eso el ancla no está ahí.
--      Corrida del 18/11 contra newa abortó en la envoltura y no dejó cambios.
--   3. lock_timeout = '3s' en el _impl y en la envoltura pública. Al entrar en
--      cualquiera de las dos, el límite vale para el candado de la entrega.
--      Si otra caja tiene bloqueado el mismo producto, la venta falla rápido
--      (sqlstate 55P03), su bloque EXCEPTION revierte todo y la app muestra un
--      mensaje para reintentar.
--
-- El pedido de mesa y el lock_timeout de las funciones M01 van en
-- sql_updates/m01_mesa_ruta_y_lock_timeout.sql. La venta v1, la preorden, el
-- cierre y el ajuste no resuelven la ruta antes del descuento.
--
-- Las funciones se reescriben a partir de su definición VIVA
-- (pg_get_functiondef) con reemplazos exactos y verificados: si el texto
-- esperado no está, el script aborta sin tocar nada. Es idempotente.
-- Aplicable a Main y Newa.
-- =============================================================================

BEGIN;

-- ── 1. fn_descontar_venta_enrutada_v2 (+ p_ruta) ─────────────────────────────
DO $$
DECLARE
    v_old  regprocedure;
    v_def  text;
    v_new  text;
BEGIN
    -- ¿Ya aplicado?
    IF EXISTS (
        SELECT 1 FROM pg_proc
         WHERE pronamespace = 'public'::regnamespace
           AND proname = 'fn_descontar_venta_enrutada_v2'
           AND pg_get_function_identity_arguments(oid) LIKE '%p_ruta jsonb%'
    ) THEN
        RAISE NOTICE 'fn_descontar_venta_enrutada_v2 ya acepta p_ruta: se omite';
        RETURN;
    END IF;

    v_old := 'public.fn_descontar_venta_enrutada_v2(bigint, numeric, bigint, bigint, integer, boolean)'::regprocedure;
    v_def := pg_get_functiondef(v_old);

    IF position('p_ya_descontado_sku boolean DEFAULT true)' IN v_def) = 0 THEN
        RAISE EXCEPTION 'Cabecera inesperada en fn_descontar_venta_enrutada_v2';
    END IF;
    IF position('v_ruta := public.fn_resolver_origen_venta(p_id_producto, p_id_tpv);' IN v_def) = 0 THEN
        RAISE EXCEPTION 'No se encontró la resolución de ruta en fn_descontar_venta_enrutada_v2';
    END IF;

    v_new := replace(
        v_def,
        'p_ya_descontado_sku boolean DEFAULT true)',
        'p_ya_descontado_sku boolean DEFAULT true, p_ruta jsonb DEFAULT NULL::jsonb)'
    );
    -- Reutilizar la ruta solo si es válida y del mismo producto.
    v_new := replace(
        v_new,
        'v_ruta := public.fn_resolver_origen_venta(p_id_producto, p_id_tpv);',
        'v_ruta := CASE
                  WHEN p_ruta IS NOT NULL
                   AND (p_ruta->>''status'') = ''success''
                   AND (p_ruta->>''id_producto'')::bigint = p_id_producto
                  THEN p_ruta
                  ELSE public.fn_resolver_origen_venta(p_id_producto, p_id_tpv)
                END;'
    );

    -- Cambia la firma: hay que dropear la versión vieja (si no, quedan dos
    -- sobrecargas y las llamadas con parámetros nombrados se vuelven ambiguas).
    EXECUTE format('DROP FUNCTION %s', v_old);
    EXECUTE v_new;

    -- Mismos permisos que tenía (postgres, authenticated, service_role; sin PUBLIC/anon).
    REVOKE ALL ON FUNCTION public.fn_descontar_venta_enrutada_v2(bigint, numeric, bigint, bigint, integer, boolean, jsonb) FROM PUBLIC;
    REVOKE ALL ON FUNCTION public.fn_descontar_venta_enrutada_v2(bigint, numeric, bigint, bigint, integer, boolean, jsonb) FROM anon;
    GRANT EXECUTE ON FUNCTION public.fn_descontar_venta_enrutada_v2(bigint, numeric, bigint, bigint, integer, boolean, jsonb) TO authenticated, service_role;

    RAISE NOTICE 'fn_descontar_venta_enrutada_v2: p_ruta agregado';
END
$$;

-- ── 2 y 3. _impl: pasar p_ruta. Envoltura e _impl: lock_timeout ──────────────
DO $$
DECLARE
    v_fn   regprocedure;
    v_def  text;
    v_sig  text;
    v_anchor constant text :=
        'p_ya_descontado_sku := (v_origen_venta = ''barra'' AND v_es_elaborado = false)';
    -- El descuento vive en el cuerpo renombrado por fix_venta_rollback_parcial.sql.
    v_impls constant text[] := ARRAY[
        'public.fn_registrar_venta_v3_impl(bigint, uuid, jsonb, text, text, text, smallint, bigint)',
        'public.fn_registrar_venta_mesa_v3_impl(bigint, uuid, jsonb, text, text, text, smallint, bigint, bigint)'
    ];
    -- La envoltura pública no descuenta; el límite también se pone aquí porque
    -- es la función que entra la app y el ajuste vale para todo lo que llama.
    v_publicas constant text[] := ARRAY[
        'public.fn_registrar_venta_v3(bigint, uuid, jsonb, text, text, text, smallint, bigint)',
        'public.fn_registrar_venta_mesa_v3(bigint, uuid, jsonb, text, text, text, smallint, bigint, bigint)'
    ];
BEGIN
    FOREACH v_sig IN ARRAY v_impls
    LOOP
        v_fn := to_regprocedure(v_sig);
        IF v_fn IS NULL THEN
            RAISE EXCEPTION 'No existe %: la llamada al descuento tiene que estar en el _impl', v_sig;
        END IF;

        v_def := pg_get_functiondef(v_fn);

        IF position('p_ruta              := v_ruta' IN v_def) > 0 THEN
            RAISE NOTICE '% ya pasa p_ruta: se omite el reemplazo', v_fn;
        ELSE
            IF position(v_anchor IN v_def) = 0 THEN
                RAISE EXCEPTION 'No se encontró la llamada a fn_descontar_venta_enrutada_v2 en %', v_fn;
            END IF;
            -- CREATE OR REPLACE conserva permisos. El lock_timeout se fija debajo.
            EXECUTE replace(
                v_def,
                v_anchor,
                v_anchor || E',\n        p_ruta              := v_ruta'
            );
            RAISE NOTICE '%: ahora pasa p_ruta', v_fn;
        END IF;

        EXECUTE format('ALTER FUNCTION %s SET lock_timeout = %L', v_fn, '3s');
    END LOOP;

    FOREACH v_sig IN ARRAY v_publicas
    LOOP
        v_fn := to_regprocedure(v_sig);
        IF v_fn IS NULL THEN
            RAISE EXCEPTION 'No existe la envoltura %', v_sig;
        END IF;
        EXECUTE format('ALTER FUNCTION %s SET lock_timeout = %L', v_fn, '3s');
        RAISE NOTICE '%: lock_timeout = 3s', v_fn;
    END LOOP;
END
$$;

COMMIT;

-- ── Verificación ─────────────────────────────────────────────────────────────
SELECT proname,
       pg_get_function_identity_arguments(oid) AS firma,
       proconfig,
       position('p_ruta' IN prosrc) > 0 AS usa_p_ruta,
       proacl
  FROM pg_proc
 WHERE pronamespace = 'public'::regnamespace
   AND proname IN ('fn_descontar_venta_enrutada_v2',
                   'fn_registrar_venta_v3',
                   'fn_registrar_venta_v3_impl',
                   'fn_registrar_venta_mesa_v3',
                   'fn_registrar_venta_mesa_v3_impl')
 ORDER BY proname;
