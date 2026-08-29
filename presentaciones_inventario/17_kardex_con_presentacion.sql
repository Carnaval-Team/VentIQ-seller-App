-- ============================================================================
-- 17 · Kardex de movimientos con presentación (get_product_movements_v4)
-- ============================================================================
-- FASE 3 de docs/PLAN_PRESENTACIONES_INVENTARIO.md (§ "Kardex de movimientos
-- del producto").
--
-- Problema
-- --------
-- `get_product_movements_v3` no lee `id_presentacion` en NINGUNA de sus ramas
-- (verificado en producción: `position('id_presentacion' in prosrc) = 0`),
-- aunque las tres tablas de detalle y el propio ledger la tienen. El kardex
-- mostraba "Entrada 4" sin decir 4 de qué: con Bulto de 10 y Bolsa de 1 en el
-- mismo producto, esa fila es ambigua.
--
-- Qué añade la v4
-- ---------------
--   id_presentacion       app_dat_producto_presentacion.id del movimiento
--   presentacion_nombre   "Bulto"
--   presentacion_factor   10.0  (cantidad de la fila, no factor_rel)
--   cantidad_formateada   "21 Bultos"   ← armado en SQL, mismo texto que las
--                                          listas de operaciones y el kardex
--   id_conversion         cabecera de app_dat_conversion_presentacion
--   es_conversion         true si la fila nació de abrir/empaquetar
--
-- Por qué v4 y no reemplazar la v3
-- --------------------------------
-- La v3 la llama `product_movements_service.dart:85` y devuelve 28 columnas
-- posicionales. Añadirle columnas es compatible, pero un `CREATE OR REPLACE`
-- que cambia el RETURNS TABLE falla con 42P13 ("cannot change return type").
-- Habría que DROP + CREATE, y entre las dos sentencias el kardex de todas las
-- tiendas queda roto. Con una función nueva el cambio es atómico desde el punto
-- de vista del cliente: la app apunta a la v4 cuando está lista.
--
-- Cómo se generó
-- --------------
-- La v3 tiene 591 líneas, 3 CTE que alimentan un UNION ALL de columnas
-- POSICIONALES y 3 brazos más en el CTE `todos`. Reescribirla a mano es la vía
-- rápida a desalinear un UNION: el error no salta donde falta la columna, sino
-- 200 líneas más abajo como un cast imposible.
--
-- Por eso este archivo NO contiene el cuerpo: contiene un DO block que baja el
-- `pg_get_functiondef` de la v3 viva, aplica las inserciones y **aborta si el
-- conteo de parches no da exacto**. Si alguien cambia la v3, este script falla
-- en vez de generar una v4 a medias.
--
-- Idempotente: `CREATE OR REPLACE` sobre la v4.
-- ============================================================================

DO $do$
DECLARE
    v_def   text;
    v_new   text;
    v_cte   int;
    v_alias int;
    v_conv  int;
BEGIN
    v_def := pg_get_functiondef(
        'public.get_product_movements_v3(bigint,date,date,bigint,bigint,integer,integer)'::regprocedure
    );
    v_new := replace(v_def, 'get_product_movements_v3', 'get_product_movements_v4');

    -- ── A · la presentación y la conversión entran en los TRES CTE de la base.
    --
    -- La posición importa: `base` es un UNION ALL de columnas posicionales, así
    -- que las dos nuevas van justo detrás de inv_created_at en los tres, o el
    -- UNION queda desalineado.
    --
    -- En movimientos_inventario se usa COALESCE porque el ledger puede traer la
    -- presentación en la propia fila (escrituras nuevas) o solo en el detalle
    -- (rutas que todavía no la copian).
    v_new := replace(v_new,
        E'      inv.created_at          AS inv_created_at,\r\n',
        E'      inv.created_at          AS inv_created_at,\r\n'
     || E'      COALESCE(inv.id_presentacion, rp.id_presentacion, ep.id_presentacion, cp.id_presentacion) AS mov_id_presentacion,\r\n'
     || E'      inv.id_conversion       AS mov_id_conversion,\r\n');

    v_new := replace(v_new,
        E'      ep.created_at           AS inv_created_at,\r\n      ''Extracción''::VARCHAR   AS tipo_movimiento,\r\n',
        E'      ep.created_at           AS inv_created_at,\r\n'
     || E'      ep.id_presentacion      AS mov_id_presentacion,\r\n'
     || E'      NULL::BIGINT            AS mov_id_conversion,\r\n'
     || E'      ''Extracción''::VARCHAR   AS tipo_movimiento,\r\n');

    v_new := replace(v_new,
        E'      COALESCE(cp.created_at, o.created_at) AS inv_created_at,\r\n      ''Control''::VARCHAR      AS tipo_movimiento,\r\n',
        E'      COALESCE(cp.created_at, o.created_at) AS inv_created_at,\r\n'
     || E'      cp.id_presentacion      AS mov_id_presentacion,\r\n'
     || E'      NULL::BIGINT            AS mov_id_conversion,\r\n'
     || E'      ''Control''::VARCHAR      AS tipo_movimiento,\r\n');

    -- ── B · tipo de movimiento propio para las conversiones.
    --
    -- Del plan: «Tipo Conversión (abrir/empaquetar) con origen_cambio propio. No
    -- entra en chips Recepción/Extracción ni en IPV como venta.» Sin esto, abrir
    -- una caja aparece como "Reajuste" y se lee como un descuadre corregido a
    -- mano, que es justo lo contrario de lo que pasó.
    v_new := replace(v_new,
        E'        WHEN inv.id_control    IS NOT NULL THEN ''Control''::VARCHAR\r\n        ELSE ''Reajuste''::VARCHAR\r\n',
        E'        WHEN inv.id_control    IS NOT NULL THEN ''Control''::VARCHAR\r\n'
     || E'        WHEN inv.id_conversion IS NOT NULL THEN ''Conversión''::VARCHAR\r\n'
     || E'        ELSE ''Reajuste''::VARCHAR\r\n');

    -- ── C · reajustes_reales enumera columnas a mano (no usa b.*).
    v_new := replace(v_new,
        E'      b.inv_id_proveedor, b.inv_created_at,\r\n',
        E'      b.inv_id_proveedor, b.inv_created_at, b.mov_id_presentacion, b.mov_id_conversion,\r\n');

    -- ── D · los tres brazos del CTE `todos`, también posicionales.
    v_new := replace(v_new,
        E'      f.cantidad_inicial, f.cantidad_final\r\n',
        E'      f.cantidad_inicial, f.cantidad_final, f.mov_id_presentacion, f.mov_id_conversion\r\n');
    v_new := replace(v_new,
        E'      r.cantidad_inicial, r.cantidad_final\r\n',
        E'      r.cantidad_inicial, r.cantidad_final, r.mov_id_presentacion, r.mov_id_conversion\r\n');
    v_new := replace(v_new,
        E'      a.cantidad_inicial, a.cantidad_final\r\n',
        E'      a.cantidad_inicial, a.cantidad_final, a.mov_id_presentacion, a.mov_id_conversion\r\n');

    -- ── E · el brazo de cancelaciones etiquetaba en duro.
    --
    -- Ese brazo recoge las filas del ledger sin recepción/extracción/control y
    -- sin ajuste — y una conversión cae exactamente ahí. Sin este parche, abrir
    -- una caja se reportaría como "Reajuste de cancelación": un movimiento
    -- deliberado disfrazado de corrección de error.
    v_new := replace(v_new,
        E'      ''Reajuste''::VARCHAR                     AS tipo_movimiento,\r\n'
     || E'      NULL::BIGINT                            AS id_tipo_operacion,\r\n'
     || E'      ''Reajuste de cancelación''::VARCHAR      AS tipo_op_nombre,\r\n',
        E'      CASE WHEN r.mov_id_conversion IS NOT NULL THEN ''Conversión''\r\n'
     || E'           ELSE ''Reajuste'' END::VARCHAR       AS tipo_movimiento,\r\n'
     || E'      NULL::BIGINT                            AS id_tipo_operacion,\r\n'
     || E'      CASE WHEN r.mov_id_conversion IS NOT NULL THEN ''Cambio de presentacion''\r\n'
     || E'           ELSE ''Reajuste de cancelación'' END::VARCHAR AS tipo_op_nombre,\r\n');

    -- ── F · firma: 6 columnas nuevas AL FINAL (las 28 previas no se mueven).
    v_new := replace(v_new, ', total_count bigint)',
        ', total_count bigint'
     || ', id_presentacion bigint'
     || ', presentacion_nombre character varying'
     || ', presentacion_factor numeric'
     || ', cantidad_formateada text'
     || ', id_conversion bigint'
     || ', es_conversion boolean)');

    -- ── G · SELECT final.
    v_new := replace(v_new,
        E'    COUNT(*) OVER ()::BIGINT\r\n',
        E'    COUNT(*) OVER ()::BIGINT,\r\n'
     || E'    t.mov_id_presentacion::BIGINT,\r\n'
     || E'    (pj.j->>''presentacion_nombre'')::VARCHAR,\r\n'
     || E'    (pj.j->>''presentacion_factor'')::NUMERIC,\r\n'
     || E'    (pj.j->>''cantidad_formateada'')::TEXT,\r\n'
     || E'    t.mov_id_conversion::BIGINT,\r\n'
     || E'    (t.mov_id_conversion IS NOT NULL)::BOOLEAN\r\n');

    -- ── H · el texto lo arma fn_presentacion_item_json (el `15`), el mismo
    -- helper que usan las listas de operaciones. Un solo sitio decide cómo se
    -- escribe "21 Bultos" para toda la aplicación.
    v_new := replace(v_new,
        E'  ) eo ON TRUE\r\n',
        E'  ) eo ON TRUE\r\n'
     || E'  LEFT JOIN LATERAL (\r\n'
     || E'    SELECT public.fn_presentacion_item_json(\r\n'
     || E'             t.mov_id_presentacion,\r\n'
     || E'             COALESCE(t.rp_cantidad, t.ep_cantidad, t.cp_cantidad,\r\n'
     || E'                      (t.cantidad_final - t.cantidad_inicial))\r\n'
     || E'           ) AS j\r\n'
     || E'  ) pj ON TRUE\r\n');

    -- ── Verificación por grupos, no un total suelto.
    --
    -- Si un solo bloque no se parchea, el UNION ALL queda desalineado y el error
    -- aparece como un cast imposible en otra parte de la función. Contar por
    -- grupo dice CUÁL bloque falló.
    --
    --   3  = un `AS mov_id_presentacion` por CTE de la base
    --   6  = 3 brazos de `todos` + reajustes_reales + 2 del SELECT final
    --   11 = las 11 apariciones de mov_id_conversion (3 CTE + 1 reajustes_reales
    --        + 3 brazos + 2 del CASE de cancelaciones + 2 del SELECT final)
    SELECT count(*) INTO v_cte   FROM regexp_matches(v_new, 'AS mov_id_presentacion', 'g');
    SELECT count(*) INTO v_alias FROM regexp_matches(v_new, '\.mov_id_presentacion', 'g');
    SELECT count(*) INTO v_conv  FROM regexp_matches(v_new, 'mov_id_conversion', 'g');

    IF v_cte <> 3 THEN
        RAISE EXCEPTION 'CTE base: esperaba 3 "AS mov_id_presentacion", hay %. Cambio la v3?', v_cte;
    END IF;
    IF v_alias <> 6 THEN
        RAISE EXCEPTION 'Brazos/SELECT: esperaba 6 referencias con alias, hay %', v_alias;
    END IF;
    IF v_conv <> 11 THEN
        RAISE EXCEPTION 'Conversion: esperaba 11 apariciones, hay %', v_conv;
    END IF;
    IF position('fn_presentacion_item_json' in v_new) = 0 THEN
        RAISE EXCEPTION 'No se inserto el LATERAL del formateo';
    END IF;

    EXECUTE v_new;
    RAISE NOTICE 'get_product_movements_v4 creada desde la v3 viva';
END $do$;

COMMENT ON FUNCTION public.get_product_movements_v4(bigint, date, date, bigint, bigint, integer, integer)
IS 'Kardex de movimientos con presentacion. Igual que la v3 mas: id_presentacion, presentacion_nombre, presentacion_factor, cantidad_formateada ("21 Bultos"), id_conversion y es_conversion. Las conversiones (abrir/empaquetar) salen con tipo_movimiento "Conversion", no como Reajuste. Generada desde la v3 por presentaciones_inventario/17.';

GRANT EXECUTE ON FUNCTION public.get_product_movements_v4(bigint, date, date, bigint, bigint, integer, integer)
    TO anon, authenticated, service_role;


-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================

-- V1 · La función existe y trae las 6 columnas nuevas.
--
--   SELECT count(*) AS columnas_nuevas
--     FROM information_schema.parameters
--    WHERE specific_schema = 'public'
--      AND specific_name LIKE 'get_product_movements_v4%'
--      AND parameter_name IN ('id_presentacion','presentacion_nombre',
--                             'presentacion_factor','cantidad_formateada',
--                             'id_conversion','es_conversion');
--   -- espera 6

-- V2 · Producto 217 "azúcar refino" (Bulto factor 10 / Bolsa factor 1 base).
--
--   SELECT id, tipo_movimiento, cantidad, cantidad_formateada,
--          presentacion_nombre, presentacion_factor, es_conversion
--     FROM public.get_product_movements_v4(217, NULL, NULL, NULL, NULL, 0, 8);
--
--   Medido en producción (2026-08-27):
--     97982 Control  21.0  "21 Bultos"  Bulto  10.0  false
--     97963 Control  21.0  "21"         NULL   NULL  false   ← fila vieja
--     81668 Control  21.0  "21 Bolsas"  Bolsa   1.0  false
--    136592 Extracción 2.0 "2 Bolsas"   Bolsa   1.0  false
--
--   Las filas con presentacion NULL son movimientos previos a la Fase 1: se
--   muestran con la cantidad sola. No se les inventa "unidades" porque el
--   ledger no sabe en qué estaban expresadas.

-- V3 · Las 28 columnas de la v3 siguen dando lo mismo (no-regresión).
--
--   SELECT bool_and(v3.cantidad = v4.cantidad AND v3.tipo_operacion = v4.tipo_operacion)
--          AS compatible
--     FROM public.get_product_movements_v3(217, NULL, NULL, NULL, NULL, 0, 20) v3
--     JOIN public.get_product_movements_v4(217, NULL, NULL, NULL, NULL, 0, 20) v4
--       ON v4.id = v3.id AND v4.tipo_movimiento = v3.tipo_movimiento;
--   -- espera true

-- V4 · Conversiones: hoy hay 0 filas con id_conversion en producción (la Fase 0
--      dejó el ledger listo pero nadie ha abierto una caja todavía), así que
--      es_conversion sale false en todo. Cuando se pruebe el rebalanceo:
--
--   SELECT id, tipo_movimiento, tipo_operacion, cantidad_formateada, es_conversion
--     FROM public.get_product_movements_v4(<producto>, NULL, NULL, NULL, NULL, 0, 20)
--    WHERE es_conversion;
--   -- espera tipo_movimiento = 'Conversión', tipo_operacion = 'Cambio de presentacion'
