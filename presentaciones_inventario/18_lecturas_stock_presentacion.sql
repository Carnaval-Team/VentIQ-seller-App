-- ============================================================================
-- 18 · Lecturas de stock por presentación (Fase 3)
-- ============================================================================
-- FASE 3 de docs/PLAN_PRESENTACIONES_INVENTARIO.md (§ "Stock").
--
-- Dos cosas:
--   A) `fn_stock_mixto_almacen`  — helper nuevo, saldo mixto por almacén.
--   B) `fn_inventario_resumen_por_usuario_almacen2` — **arregla dos bugs de
--      cálculo que inflaban el stock**, medidos en producción.
--
-- ----------------------------------------------------------------------------
-- B · Los dos bugs del resumen
-- ----------------------------------------------------------------------------
-- El CTE `presentacion_base` sacaba UN factor por producto:
--
--     SELECT id_producto, cantidad AS factor
--       FROM app_dat_producto_presentacion
--      WHERE es_base = true
--
-- y lo aplicaba a TODAS las filas de inventario del producto:
--
--     SUM(u.cantidad_final * COALESCE(pb.factor, 1)) AS cant_unidades_base
--     LEFT JOIN presentacion_base pb ON u.id_producto = pb.id_producto
--
-- **Bug 1 · el factor de la base no es 1.**
-- Hay 131 presentaciones marcadas `es_base` con `cantidad` 12, 24 o 30; **30 de
-- esos productos tienen stock hoy**. El equivalente en unidades base de la
-- propia base es 1, no su `cantidad`. Medido:
--
--     producto 4380 "Compresor Kia Picanto 2017 2020" (tienda 45)
--       base con factor 30, 16 en almacén
--       antes:   cant_unidades_base = 480    ← ×30
--       después: cant_unidades_base = 16
--
-- **Bug 2 · el JOIN multiplicaba las filas.**
-- `id_producto` no es único en `presentacion_base`: el producto 9635 tiene TRES
-- filas con `es_base = true`. El `LEFT JOIN` por `id_producto` devolvía 3 filas
-- por cada fila de inventario y el `SUM` las contaba todas. Medido:
--
--     producto 9635 "Pizza de Queso Gouda" (tienda 174)
--       saldo real: 5 (una sola fila de inventario, presentación 9768)
--       antes:   cant_almacen_total = 15   cant_unidades_base = 15
--       después: cant_almacen_total = 5    cant_unidades_base = 5
--
--     Este es el más grave de los dos: inflaba la **cantidad física**, no solo
--     el equivalente. Un inventario que dice 15 donde hay 5.
--
-- La corrección usa `factor_rel` de `fn_presentaciones_producto` (que ya aplica
-- la cascada correcta de la base) y casa el JOIN **por presentación**, no por
-- producto, así que devuelve una fila por presentación y no puede multiplicar.
--
-- No-regresión medida sobre la tienda 174 (270 filas):
--     filas antes = filas después = 270
--     cambia el equivalente: 1 fila (el 9635, que estaba mal)
--     cambia la cantidad cruda: 1 fila (el mismo)
--     cambia stock_disponible: 0
--     cambia zonas_count: 0
--
-- Idempotente: los dos son `CREATE OR REPLACE`. El B se genera desde la función
-- viva con un DO block que aborta si los conteos no dan exactos (misma técnica
-- que el `16` y el `17`).
-- ============================================================================


-- ── A · Saldo mixto por almacén ─────────────────────────────────────────────
--
-- Ya existía `fn_stock_mixto_json(producto, almacen, ubicacion)`. Esta es la
-- variante que las pantallas de stock necesitan: acepta el almacén y devuelve
-- el desglose agrupado, listo para pintar "4 Cajas + 4 Unidades · = 52 u".
--
-- Se apoya en fn_stock_saldos_presentacion, que ya resuelve el DISTINCT ON por
-- (ubicacion, variante, presentacion) y trae factor_rel.

CREATE OR REPLACE FUNCTION public.fn_stock_mixto_almacen(
    p_id_producto bigint,
    p_id_almacen  bigint DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path = public
AS $$
    SELECT public.fn_stock_mixto_json(p_id_producto, p_id_almacen, NULL);
$$;

COMMENT ON FUNCTION public.fn_stock_mixto_almacen(bigint, bigint) IS
    'Alias por almacen de fn_stock_mixto_json. Devuelve desglose, equivalente_base, texto ("4 Cajas + 4 Unidades") y texto_corto ("4 CAJ + 4 UNI").';

GRANT EXECUTE ON FUNCTION public.fn_stock_mixto_almacen(bigint, bigint)
    TO anon, authenticated, service_role;


-- ── B · Arreglo del resumen por usuario ─────────────────────────────────────

DO $do$
DECLARE
    v_def  text;
    v_new  text;
    v_cte  int;
    v_join int;
    v_mult int;
    v_fb   int;
BEGIN
    v_def := pg_get_functiondef(
        'public.fn_inventario_resumen_por_usuario_almacen2(bigint,bigint,text,boolean,text,integer,integer)'::regprocedure
    );

    -- 1 · el CTE pasa de "factor de la fila es_base del producto" a
    --     "factor_rel de CADA presentacion".
    v_new := replace(v_def,
        E'    presentacion_base AS (\r\n'
     || E'        -- Factor de conversión a unidad base\r\n'
     || E'        SELECT \r\n'
     || E'            id_producto,\r\n'
     || E'            cantidad AS factor\r\n'
     || E'        FROM app_dat_producto_presentacion\r\n'
     || E'        WHERE es_base = true\r\n'
     || E'    ),\r\n',
        E'    presentacion_base AS (\r\n'
     || E'        -- FASE 3 presentaciones: factor_rel POR PRESENTACION.\r\n'
     || E'        --\r\n'
     || E'        -- Antes se tomaba la cantidad de la fila es_base y se aplicaba\r\n'
     || E'        -- a TODAS las filas del producto. Dos fallos medidos:\r\n'
     || E'        --   a) 30 productos con stock tienen la base con factor <> 1\r\n'
     || E'        --      (131 en total). El 4380 tiene la base con factor 30, asi\r\n'
     || E'        --      que 16 en almacen salian como 480 unidades base.\r\n'
     || E'        --   b) id_producto NO es unico aqui: el 9635 tiene TRES filas\r\n'
     || E'        --      es_base, el LEFT JOIN multiplicaba las filas de\r\n'
     || E'        --      inventario y el SUM reportaba 15 donde hay 5.\r\n'
     || E'        --\r\n'
     || E'        -- factor_rel viene de fn_presentaciones_producto, que resuelve\r\n'
     || E'        -- la base con la cascada correcta (es_base, luego menor factor,\r\n'
     || E'        -- luego menor id) y da 1 para la propia base.\r\n'
     || E'        SELECT\r\n'
     || E'            pp.id_producto,\r\n'
     || E'            pp.id        AS id_presentacion,\r\n'
     || E'            c.factor_rel AS factor\r\n'
     || E'        FROM app_dat_producto_presentacion pp\r\n'
     || E'        JOIN LATERAL public.fn_presentaciones_producto(pp.id_producto) c\r\n'
     || E'             ON c.id_presentacion = pp.id\r\n'
     || E'    ),\r\n');

    -- 2 · el JOIN casa por presentacion: una fila por presentacion, nunca N.
    v_new := replace(v_new,
        'LEFT JOIN presentacion_base pb ON u.id_producto = pb.id_producto',
        E'LEFT JOIN presentacion_base pb ON u.id_producto = pb.id_producto\r\n'
     || E'                                       AND u.id_presentacion = pb.id_presentacion');

    -- Verificación por grupos. La función tiene DOS ramas (con almacén y sin
    -- almacén) con el mismo bloque duplicado: si solo se parchea una, el bug
    -- sigue vivo en la otra y el síntoma aparece solo al filtrar.
    SELECT count(*) INTO v_cte  FROM regexp_matches(v_new, 'factor_rel AS factor', 'g');
    SELECT count(*) INTO v_join FROM regexp_matches(v_new, 'AND u\.id_presentacion = pb\.id_presentacion', 'g');
    -- Estas dos NO deben cambiar: se conservan tal cual estaban.
    SELECT count(*) INTO v_mult FROM regexp_matches(v_new, 'SUM\(u\.cantidad_final \* COALESCE\(pb\.factor, 1\)\)', 'g');
    SELECT count(*) INTO v_fb   FROM regexp_matches(v_new, 'COALESCE\(pb\.factor, 1\) AS factor_base', 'g');

    IF v_cte <> 2 THEN
        RAISE EXCEPTION 'CTE presentacion_base: esperaba 2 ramas parcheadas, hay %. Cambio la funcion?', v_cte;
    END IF;
    IF v_join <> 2 THEN
        RAISE EXCEPTION 'JOIN por presentacion: esperaba 2, hay %', v_join;
    END IF;
    IF v_mult <> 2 THEN
        RAISE EXCEPTION 'La multiplicacion del SUM cambio (hay %), revisar a mano', v_mult;
    END IF;
    IF v_fb <> 2 THEN
        RAISE EXCEPTION 'factor_base cambio (hay %), revisar a mano', v_fb;
    END IF;

    EXECUTE v_new;
    RAISE NOTICE 'fn_inventario_resumen_por_usuario_almacen2 corregida (2 ramas)';
END $do$;


-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================

-- V1 · El helper mixto responde.
--
--   SELECT jsonb_pretty(public.fn_stock_mixto_almacen(217));
--   -- espera texto "121 Bolsas", equivalente_base 121, desglose con 1 entrada

-- V2 · ⭐ El bug del factor de la base (producto 4380, tienda 45).
--
--   SELECT r.prod_id, r.cant_almacen_total, r.cant_unidades_base
--     FROM (SELECT set_config('request.jwt.claims',
--             json_build_object('sub','<UUID_GERENTE_T45>','role','authenticated')::text,
--             true) c) s,
--          LATERAL public.fn_inventario_resumen_por_usuario_almacen2(
--                    45, NULL, 'Compresor Kia Picanto 2017', NULL, NULL, 20, 1) r;
--
--   Medido:
--     antes:   4380 → cant_almacen_total 16,  cant_unidades_base 480   ❌
--     después: 4380 → cant_almacen_total 16,  cant_unidades_base 16    ✅
--              2329 → 30 / 30 (sin cambio, su base tiene factor 1)

-- V3 · ⭐ El bug del JOIN que multiplicaba (producto 9635, tienda 174).
--
--   El saldo real es 5, en una sola fila de inventario (presentación 9768):
--
--   SELECT id_presentacion, cantidad_final FROM (
--     SELECT DISTINCT ON (ip.id_ubicacion, COALESCE(ip.id_variante,0),
--                         COALESCE(ip.id_opcion_variante,0),
--                         COALESCE(ip.id_presentacion,0))
--            ip.id_presentacion, ip.cantidad_final
--       FROM app_dat_inventario_productos ip
--       JOIN app_dat_layout_almacen la ON la.id = ip.id_ubicacion
--      WHERE ip.id_producto = 9635 AND la.deleted_at IS NULL
--      ORDER BY ip.id_ubicacion, COALESCE(ip.id_variante,0),
--               COALESCE(ip.id_opcion_variante,0),
--               COALESCE(ip.id_presentacion,0), ip.id DESC) v
--    WHERE COALESCE(cantidad_final,0) <> 0;
--   -- 9768 → 5.0
--
--   Medido en el resumen:
--     antes:   cant_almacen_total 15,  cant_unidades_base 15   ❌
--     después: cant_almacen_total 5,   cant_unidades_base 5    ✅

-- V4 · No-regresión: nada más se movió (tienda 174, 270 filas).
--
--   Comparando antes/después fila por fila:
--     filas: 270 = 270
--     cambia cant_unidades_base:  1  (solo el 9635)
--     cambia cant_almacen_total:  1  (el mismo)
--     cambia stock_disponible:    0
--     cambia zonas_count:         0

-- V5 · Censo de los productos afectados por el bug 1.
--
--   SELECT count(*) AS base_factor_distinto_1,
--          count(*) FILTER (WHERE EXISTS (
--            SELECT 1 FROM app_dat_inventario_productos ip
--             WHERE ip.id_producto = pp.id_producto
--               AND COALESCE(ip.cantidad_final,0) > 0)) AS con_stock
--     FROM (SELECT DISTINCT id_producto FROM app_dat_producto_presentacion
--            WHERE es_base AND cantidad <> 1) pp;
--   -- medido: 131 productos, 30 con stock
