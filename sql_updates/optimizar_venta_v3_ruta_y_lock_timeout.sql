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
--   2. fn_registrar_venta_v3 y fn_registrar_venta_mesa_v3 pasan p_ruta := v_ruta.
--   3. Ambas ventas: SET lock_timeout = '3s'. Si otra caja tiene bloqueado el
--      mismo producto, la venta falla rápido (sqlstate 55P03), su bloque
--      EXCEPTION revierte todo y la app muestra un mensaje para reintentar.
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

-- ── 2 y 3. Ventas: pasar p_ruta + lock_timeout ───────────────────────────────
DO $$
DECLARE
    v_fn   regprocedure;
    v_def  text;
    v_anchor constant text :=
        'p_ya_descontado_sku := (v_origen_venta = ''barra'' AND v_es_elaborado = false)';
BEGIN
    FOREACH v_fn IN ARRAY ARRAY[
        'public.fn_registrar_venta_v3(bigint, uuid, jsonb, text, text, text, smallint, bigint)'::regprocedure,
        'public.fn_registrar_venta_mesa_v3(bigint, uuid, jsonb, text, text, text, smallint, bigint, bigint)'::regprocedure
    ]
    LOOP
        v_def := pg_get_functiondef(v_fn);

        IF position('p_ruta              := v_ruta' IN v_def) > 0 THEN
            RAISE NOTICE '% ya pasa p_ruta: se omite el reemplazo', v_fn;
        ELSE
            IF position(v_anchor IN v_def) = 0 THEN
                RAISE EXCEPTION 'No se encontró la llamada a fn_descontar_venta_enrutada_v2 en %', v_fn;
            END IF;
            -- CREATE OR REPLACE conserva permisos y la configuración SET.
            EXECUTE replace(
                v_def,
                v_anchor,
                v_anchor || E',\n        p_ruta              := v_ruta'
            );
            RAISE NOTICE '%: ahora pasa p_ruta', v_fn;
        END IF;

        -- Fallar rápido si otra caja tiene bloqueado el mismo producto/ubicación.
        EXECUTE format('ALTER FUNCTION %s SET lock_timeout = %L', v_fn, '3s');
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
                   'fn_registrar_venta_mesa_v3')
 ORDER BY proname;
