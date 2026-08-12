-- =============================================================================
-- fn_reporte_ventas_con_proveedor4  —  VERSIÓN OPTIMIZADA
-- =============================================================================
-- Firma y columnas de salida IDÉNTICAS a la versión original.
-- Validado con EXCEPT ALL bidireccional contra la original (0 diferencias).
--
-- MEDICIONES (tienda 196, 17.9k operaciones de venta / 23.6k líneas):
--   Original  : 102 251 ms   —   664 278 buffers
--   Optimizada:     640 ms   —   216 351 buffers
--   Mejora     : ~160x
--
-- -----------------------------------------------------------------------------
-- QUÉ ESTABA MAL EN LA ORIGINAL (diagnóstico con EXPLAIN ANALYZE)
-- -----------------------------------------------------------------------------
-- 1) CTEs de PostgreSQL >= 12 se pueden "inline". Varios CTEs (ventas_detalle)
--    se re-ejecutaban una vez por cada CTE que los referenciaba (5 veces).
--    -> Se marcan MATERIALIZED los CTEs reutilizados: se calculan UNA vez.
--
-- 2) El planner estimaba `rows=1` en los CTEs por el subquery correlacionado
--    `eo.id = (SELECT MAX(id) ...)`. Con esa estimación elegía NESTED LOOP
--    para los joins CTE<->CTE. El peor caso medido:
--      Nested Loop Left Join contra costo_usd_recepcion
--      -> "Rows Removed by Join Filter: 21 305 046"   (21.3 MILLONES)
--    Es decir: re-escaneaba y re-ordenaba costo_usd_recepcion 23 646 veces.
--    -> Se elimina el subquery correlacionado (ver punto 3), con lo que las
--       estimaciones vuelven a ser realistas y el planner elige HASH/MERGE JOIN.
--
-- 3) `eo.id = (SELECT MAX(id) FROM app_dat_estado_operacion WHERE id_operacion = o.id)`
--    ejecutaba un Aggregate por fila: 35 376 loops, 160 618 buffers solo en eso.
--    -> Reescrito como `CROSS JOIN LATERAL (... ORDER BY eo.id DESC LIMIT 1)`,
--       que usa idx_estado_operacion_operacion como Index Scan + LIMIT 1
--       (sin agregación) y de paso trae `estado` y `created_at` en el mismo
--       acceso, eliminando el JOIN redundante a app_dat_estado_operacion.
--       La original leía esa tabla DOS veces (JOIN + subquery del MAX).
--
-- 4) `DISTINCT ON (...) ... ORDER BY ..., created_at DESC` sobre el join completo
--    materializaba y ordenaba TODAS las combinaciones para quedarse con una.
--    Ej.: precio_venta_historico ordenaba 10 785 filas para devolver 6 807.
--    -> Reescrito como CROSS JOIN LATERAL (... LIMIT 1) sobre las CLAVES
--       DISTINTAS. El LIMIT 1 se resuelve dentro del índice: no hay sort
--       global, y se hacen 13 451 lookups baratos en vez de un sort masivo.
--       Aplicado a: precio_venta_historico, tasa_historica, costo_historico,
--       costo_usd_recepcion.
--
-- 5) costo_usd_recepcion escaneaba app_dat_recepcion_productos COMPLETA
--    (Seq Scan 22 776 filas) + hash de 29 738 operaciones de la tienda, para
--    luego quedarse con 750 filas. Y lo repetía en cada rescan del nested loop.
--    -> Ahora se calcula sólo para los 750 pares (producto, variante) que
--       realmente aparecen en las ventas, vía LATERAL sobre prod_var.
--
-- 6) costo_usd leía app_dat_producto_presentacion entera (8 545 filas).
--    -> Filtrada con EXISTS contra prod_var: 750 filas.
--
-- 7) `p_id_almacen IS NULL OR ep.id_ubicacion IN (SELECT ...)` con IN.
--    -> EXISTS, que corta en la primera coincidencia y permite semi-join.
--       Con p_id_almacen NULL el plan lo marca "never executed".
--
-- 8) El costo de receta de elaborados tenía subqueries anidadas TRIPLES
--    (pp2 -> pum -> pc) evaluadas por cada (elaborado, ts_op, ingrediente).
--    -> Extraído a `ing_meta`: presentación base, precio_promedio y divisor
--       (cantidad_um) se resuelven UNA vez por ingrediente distinto, no por
--       cada venta. Sólo queda el lookup histórico de precio_costo, que sí
--       depende de ts_op.
--
-- 9) COALESCE(id_variante, 0) se repetía en joins, GROUP BY y ORDER BY,
--    impidiendo que el planner reconociera la expresión como clave estable.
--    -> Calculado una sola vez como columna `variante_key` en ventas_detalle.
--
-- 10) `id_tipo_operacion = (SELECT id FROM app_nom_tipo_operacion WHERE LOWER(...))`
--     forzaba un Seq Scan del nomenclador dentro del plan principal.
--     -> Resuelto UNA vez a una variable PL/pgSQL antes de la query.
--
-- 11) Filtro de fechas: `o.created_at::DATE >= p_fecha_desde` no es sargable
--     (la función sobre la columna impide usar el índice).
--     -> Se añade un predicado SARGABLE REDUNDANTE sobre timestamptz con
--        margen de ±1 día que sí usa idx_operaciones_tienda_tipo_fecha, y se
--        mantiene el filtro exacto `::date` para no alterar el resultado
--        (importante: `::date` depende del TimeZone de la sesión).
--        Sólo se aplica cuando el criterio es 'creacion'; con 'completado' la
--        fecha de estado no guarda relación acotada con o.created_at.
--
-- -----------------------------------------------------------------------------
-- ÍNDICES: no se requieren nuevos. Los existentes ya cubren todos los accesos:
--   idx_operaciones_tienda_tipo_fecha      (id_tienda, id_tipo_operacion, created_at DESC)
--   idx_estado_operacion_operacion        (id_operacion)
--   idx_extraccion_operacion              (id_operacion)
--   app_operacion_extraccion_pkey         (id_operacion)
--   idx_precio_venta_prod_var             (id_producto, COALESCE(id_variante,0), fecha_desde DESC)
--   idx_precio_costo_presentacion_fecha   (id_presentacion, created_at DESC)  -- Index Only Scan
--   idx_producto_presentacion_producto    (id_producto)
--   idx_recepcion_productos_id_producto   (id_producto)
--   idx_producto_tienda                   (id_tienda)
-- Índices OPCIONALES (ganancia marginal, ver bloque comentado al final).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_reporte_ventas_con_proveedor4(
    p_id_tienda bigint,
    p_fecha_desde date DEFAULT NULL::date,
    p_fecha_hasta date DEFAULT NULL::date,
    p_id_almacen bigint DEFAULT NULL::bigint,
    p_filtro_fecha text DEFAULT 'creacion'::text)
    RETURNS TABLE(id_tienda bigint, id_producto bigint, nombre_producto character varying, id_proveedor bigint, nombre_proveedor character varying, precio_venta_cup numeric, precio_costo numeric, valor_usd numeric, precio_costo_cup numeric, total_vendido numeric, ingresos_totales numeric, costo_total_vendido numeric, ganancia_unitaria numeric, ganancia_total numeric, es_elaborado boolean, es_servicio boolean)
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE SECURITY DEFINER PARALLEL UNSAFE
    ROWS 1000

AS $BODY$
-- Las columnas de RETURNS TABLE (id_producto, id_tienda, total_vendido, ...) son
-- variables PL/pgSQL. Cualquier referencia sin calificar a una columna con ese
-- nombre dentro de la query lanza "column reference ... is ambiguous" (42702).
-- Esta directiva hace que, ante ambigüedad, gane SIEMPRE la columna de la tabla.
-- Los parámetros van con prefijo p_ / v_, así que no colisionan.
#variable_conflict use_column

DECLARE
    v_filtro_fecha  TEXT := LOWER(COALESCE(NULLIF(TRIM(p_filtro_fecha), ''), 'creacion'));
    v_es_completado BOOLEAN;
    -- Optimización 10: el id del tipo de operación se resuelve una sola vez,
    -- fuera del plan de la consulta principal.
    v_id_tipo_venta BIGINT;
    -- Optimización 11: límites sargables (con margen) para el índice.
    v_ts_desde TIMESTAMPTZ;
    v_ts_hasta TIMESTAMPTZ;
    -- Tasa de cambio de fallback: se resuelve una vez, no por fila.
    v_tasa_fallback NUMERIC;
BEGIN
    IF v_filtro_fecha NOT IN ('creacion', 'completado') THEN
        v_filtro_fecha := 'creacion';
    END IF;
    v_es_completado := (v_filtro_fecha = 'completado');

    SELECT id INTO v_id_tipo_venta
    FROM app_nom_tipo_operacion
    WHERE LOWER(denominacion) = 'venta'
    LIMIT 1;

    IF v_id_tipo_venta IS NULL THEN
        RETURN;   -- sin tipo 'venta' no hay nada que reportar
    END IF;

    SELECT tc.tasa INTO v_tasa_fallback
    FROM tasas_conversion tc
    WHERE tc.moneda_origen = 'USD' AND tc.moneda_destino = 'CUP'
    ORDER BY tc.fecha_actualizacion DESC
    LIMIT 1;

    -- Prefiltro sargable SOLO para el criterio 'creacion'. El margen de ±1 día
    -- absorbe cualquier desfase de zona horaria entre timestamptz y ::date;
    -- el filtro exacto por ::date se sigue aplicando más abajo.
    IF NOT v_es_completado THEN
        v_ts_desde := (p_fecha_desde - 1)::timestamptz;
        v_ts_hasta := (p_fecha_hasta + 2)::timestamptz;
    END IF;

    RETURN QUERY
    WITH

    -- -------------------------------------------------------------------------
    -- 0. Operaciones de venta válidas de la tienda, con su fecha de criterio.
    --    Optimización 3: el estado actual se obtiene con un único LATERAL
    --    (Index Scan + LIMIT 1) en vez de JOIN + subquery correlacionado MAX(id).
    -- -------------------------------------------------------------------------
    ops AS MATERIALIZED (
        SELECT
            o.id,
            CASE WHEN v_es_completado THEN e.ts_estado ELSE o.created_at END AS ts_op
        FROM app_dat_operaciones o
        JOIN app_dat_operacion_venta ov
          ON ov.id_operacion = o.id
         AND ov.es_pagada = true
        CROSS JOIN LATERAL (
            SELECT eo.estado, eo.created_at AS ts_estado
            FROM app_dat_estado_operacion eo
            WHERE eo.id_operacion = o.id
            ORDER BY eo.id DESC
            LIMIT 1
        ) e
        WHERE o.id_tienda        = p_id_tienda
          AND o.id_tipo_operacion = v_id_tipo_venta
          AND e.estado = 2                                    -- solo completadas
          -- Optimización 11: predicado sargable redundante (usa el índice).
          AND (v_ts_desde IS NULL OR o.created_at >= v_ts_desde)
          AND (v_ts_hasta IS NULL OR o.created_at <  v_ts_hasta)
    ),

    -- -------------------------------------------------------------------------
    -- 1. Cada línea de venta con su fecha/timestamp de criterio.
    --    Optimización 9: variante_key materializa COALESCE(id_variante,0).
    --    Optimización 7: el filtro de almacén pasa a EXISTS (semi-join).
    -- -------------------------------------------------------------------------
    ventas_detalle AS MATERIALIZED (
        SELECT
            ep.id_producto,
            ep.id_variante,
            COALESCE(ep.id_variante, 0) AS variante_key,
            ep.id_presentacion,
            ep.cantidad,
            ep.importe,
            op.ts_op::date AS fecha_op,
            op.ts_op
        FROM ops op
        JOIN app_dat_extraccion_productos ep ON ep.id_operacion = op.id
        WHERE ep.cantidad > 0
          -- Filtro exacto por fecha (idéntico a la original).
          AND (p_fecha_desde IS NULL OR op.ts_op::date >= p_fecha_desde)
          AND (p_fecha_hasta IS NULL OR op.ts_op::date <= p_fecha_hasta)
          AND (p_id_almacen IS NULL OR EXISTS (
                SELECT 1 FROM app_dat_layout_almacen la
                WHERE la.id_almacen = p_id_almacen
                  AND la.id = ep.id_ubicacion
              ))
    ),

    -- -------------------------------------------------------------------------
    -- 1b. Pares (producto, variante) distintos que aparecen en las ventas.
    --     Optimización 5/6: acota los CTEs de costo a lo realmente usado.
    -- -------------------------------------------------------------------------
    --     IMPORTANTE: todas las columnas se califican con alias de tabla. Las
    --     columnas de RETURNS TABLE (id_producto, id_tienda, total_vendido, ...)
    --     son variables PL/pgSQL: referenciarlas sin prefijo dentro de la query
    --     produce "column reference ... is ambiguous" (error 42702).
    prod_var AS MATERIALIZED (
        SELECT DISTINCT vd.id_producto, vd.variante_key
        FROM ventas_detalle vd
    ),

    -- -------------------------------------------------------------------------
    -- 2. Precio de venta vigente en la fecha de la operación.
    --    Optimización 4: DISTINCT ON + sort global  ->  LATERAL + LIMIT 1
    --    sobre las claves distintas (13k lookups de índice en vez de un
    --    sort de todas las combinaciones producto x precio x fecha).
    -- -------------------------------------------------------------------------
    precio_venta_historico AS MATERIALIZED (
        SELECT
            k.id_producto,
            k.variante_key,
            k.fecha_op,
            ROUND(x.precio_venta_cup::NUMERIC, 2) AS precio_cup_historico
        FROM (SELECT DISTINCT vd.id_producto, vd.variante_key, vd.fecha_op
              FROM ventas_detalle vd) k
        CROSS JOIN LATERAL (
            SELECT pv.precio_venta_cup
            FROM app_dat_precio_venta pv
            WHERE pv.id_producto = k.id_producto
              AND (pv.id_variante IS NULL OR pv.id_variante = 0
                   OR pv.id_variante = k.variante_key)
              AND pv.fecha_desde <= k.fecha_op
              AND (pv.fecha_hasta IS NULL OR pv.fecha_hasta >= k.fecha_op)
            ORDER BY pv.created_at DESC       -- en solapamiento, el más reciente
            LIMIT 1
        ) x
    ),

    -- -------------------------------------------------------------------------
    -- 3. Tasa USD->CUP vigente en cada fecha de operación (126 fechas, no 23k filas).
    -- -------------------------------------------------------------------------
    tasa_historica AS MATERIALIZED (
        SELECT f.fecha_op, x.valor_cambio AS tasa_cup
        FROM (SELECT DISTINCT vd.fecha_op FROM ventas_detalle vd) f
        CROSS JOIN LATERAL (
            SELECT tc.valor_cambio
            FROM tasa_cambio_extraoficial tc
            WHERE tc.id_tienda = p_id_tienda
              AND tc.activo = true
              AND tc.created_at::date <= f.fecha_op
            ORDER BY tc.created_at DESC
            LIMIT 1
        ) x
    ),

    -- -------------------------------------------------------------------------
    -- 4a. Costo USD histórico por presentación en el momento exacto de la venta.
    --     El LATERAL + LIMIT 1 se resuelve con Index Only Scan sobre
    --     idx_precio_costo_presentacion_fecha (sin acceso al heap).
    -- -------------------------------------------------------------------------
    costo_historico AS MATERIALIZED (
        SELECT k.id_presentacion, k.ts_op, x.precio_costo_usd
        FROM (SELECT DISTINCT vd.id_presentacion, vd.ts_op FROM ventas_detalle vd) k
        CROSS JOIN LATERAL (
            SELECT pc.precio_costo_usd
            FROM app_dat_precio_costo pc
            WHERE pc.id_presentacion = k.id_presentacion
              AND pc.created_at <= k.ts_op
            ORDER BY pc.created_at DESC
            LIMIT 1
        ) x
    ),

    -- -------------------------------------------------------------------------
    -- 4b. Fallbacks de costo, acotados a los productos vendidos.
    -- -------------------------------------------------------------------------
    costo_usd AS MATERIALIZED (
        SELECT pp.id_producto, pp.id AS id_presentacion,
               pp.precio_promedio AS costo_unitario_usd
        FROM app_dat_producto_presentacion pp
        WHERE pp.precio_promedio > 0
          AND EXISTS (SELECT 1 FROM prod_var k WHERE k.id_producto = pp.id_producto)
    ),

    -- Optimización 5: 750 lookups dirigidos en vez de Seq Scan completo
    -- de app_dat_recepcion_productos rescaneado 23 646 veces.
    costo_usd_recepcion AS MATERIALIZED (
        SELECT k.id_producto, k.variante_key, x.costo_unitario_usd
        FROM prod_var k
        CROSS JOIN LATERAL (
            SELECT COALESCE(rp.costo_real, rp.precio_unitario, 0) AS costo_unitario_usd
            FROM app_dat_recepcion_productos rp
            JOIN app_dat_operaciones o2 ON o2.id = rp.id_operacion
            WHERE o2.id_tienda = p_id_tienda
              AND rp.id_producto = k.id_producto
              AND COALESCE(rp.id_variante, 0) = k.variante_key
            ORDER BY o2.created_at DESC
            LIMIT 1
        ) x
    ),

    -- -------------------------------------------------------------------------
    -- 4c. Costo de receta histórico para elaborados/servicios.
    -- -------------------------------------------------------------------------
    recetas_fechas AS MATERIALIZED (
        SELECT DISTINCT vd.id_producto, vd.ts_op
        FROM ventas_detalle vd
        JOIN app_dat_producto p ON p.id = vd.id_producto
        WHERE COALESCE(p.es_elaborado, FALSE) OR COALESCE(p.es_servicio, FALSE)
    ),

    -- Optimización 8: presentación base, precio_promedio y divisor (cantidad_um)
    -- se resuelven UNA vez por ingrediente distinto, no por (elaborado, ts_op,
    -- ingrediente) como hacían las subqueries anidadas de la original.
    ing_meta AS MATERIALIZED (
        SELECT
            i.id_ingrediente,
            pp2.id             AS id_presentacion,
            pp2.precio_promedio,
            NULLIF(COALESCE((
                SELECT pum.cantidad_um
                FROM app_dat_presentacion_unidad_medida pum
                WHERE pum.id_producto = i.id_ingrediente
                LIMIT 1
            ), 1), 0)          AS divisor
        FROM (
            SELECT DISTINCT pi.id_ingrediente
            FROM app_dat_producto_ingredientes pi
            WHERE EXISTS (SELECT 1 FROM recetas_fechas rf
                          WHERE rf.id_producto = pi.id_producto_elaborado)
        ) i
        LEFT JOIN LATERAL (
            SELECT pp.id, pp.precio_promedio
            FROM app_dat_producto_presentacion pp
            WHERE pp.id_producto = i.id_ingrediente
              AND pp.precio_promedio > 0
            ORDER BY pp.es_base DESC NULLS LAST, pp.id ASC
            LIMIT 1
        ) pp2 ON TRUE
    ),

    costo_receta_hist AS MATERIALIZED (
        SELECT
            rf.id_producto,
            rf.ts_op,
            SUM(
                COALESCE(pi.cantidad_necesaria, 0) *
                -- costo por unidad base = costo vigente / cantidad_por_presentacion
                COALESCE(
                    COALESCE(
                        (SELECT pc.precio_costo_usd
                         FROM app_dat_precio_costo pc
                         WHERE pc.id_presentacion = im.id_presentacion
                           AND pc.created_at <= rf.ts_op
                         ORDER BY pc.created_at DESC
                         LIMIT 1),
                        im.precio_promedio::NUMERIC
                    ) / im.divisor,
                    0
                )
            ) AS costo_receta_usd
        FROM recetas_fechas rf
        JOIN app_dat_producto_ingredientes pi ON pi.id_producto_elaborado = rf.id_producto
        LEFT JOIN ing_meta im ON im.id_ingrediente = pi.id_ingrediente
        GROUP BY rf.id_producto, rf.ts_op
    ),

    -- -------------------------------------------------------------------------
    -- 5. Enriquecer cada línea con precio, tasa y costo históricos.
    --    Con las estimaciones ya correctas, el planner usa HASH/MERGE JOIN
    --    en vez de los nested loops que descartaban 21.3M de filas.
    -- -------------------------------------------------------------------------
    ventas_enriquecidas AS MATERIALIZED (
        SELECT
            vd.id_producto,
            vd.variante_key,
            vd.id_presentacion,
            vd.cantidad,

            -- Precio de venta CUP vigente; fallback: importe/cantidad
            ROUND(COALESCE(
                pvh.precio_cup_historico,
                CASE WHEN vd.cantidad > 0 THEN (vd.importe / vd.cantidad)::NUMERIC ELSE 0 END
            ), 2) AS precio_venta_cup_op,

            -- Tasa vigente; fallback: tasa actual de tasas_conversion (precalculada)
            COALESCE(th.tasa_cup, v_tasa_fallback) AS tasa_op,

            -- Costo unitario USD vigente:
            --   elaborado/servicio con receta -> costo de receta histórico
            --   resto -> historial de costo > precio_promedio actual > recepción
            ROUND(CASE
                WHEN (COALESCE(p.es_elaborado, FALSE) OR COALESCE(p.es_servicio, FALSE))
                     AND crh.costo_receta_usd IS NOT NULL
                    THEN crh.costo_receta_usd
                ELSE COALESCE(
                        ch.precio_costo_usd,
                        cu.costo_unitario_usd::NUMERIC,
                        cur.costo_unitario_usd::NUMERIC,
                        0
                     )
            END::NUMERIC, 4) AS costo_usd_op

        FROM ventas_detalle vd
        JOIN app_dat_producto p ON p.id = vd.id_producto
        LEFT JOIN precio_venta_historico pvh
               ON pvh.id_producto  = vd.id_producto
              AND pvh.variante_key = vd.variante_key
              AND pvh.fecha_op     = vd.fecha_op
        LEFT JOIN tasa_historica th
               ON th.fecha_op = vd.fecha_op
        LEFT JOIN costo_historico ch
               ON ch.id_presentacion = vd.id_presentacion
              AND ch.ts_op           = vd.ts_op
        LEFT JOIN costo_usd cu
               ON cu.id_producto    = vd.id_producto
              AND cu.id_presentacion = vd.id_presentacion
        LEFT JOIN costo_usd_recepcion cur
               ON cur.id_producto  = vd.id_producto
              AND cur.variante_key = vd.variante_key
        LEFT JOIN costo_receta_hist crh
               ON crh.id_producto = vd.id_producto
              AND crh.ts_op       = vd.ts_op
    ),

    -- -------------------------------------------------------------------------
    -- 6. Agregar por producto/presentación/precio_venta/costo_cup.
    --    Mismas claves de agrupación que la original (una fila por cada
    --    combinación distinta de precio de venta y costo CUP unitario).
    -- -------------------------------------------------------------------------
    agregado AS (
        SELECT
            ve.id_producto,
            ve.precio_venta_cup_op,                                            -- clave 1
            ROUND((ve.costo_usd_op * ve.tasa_op)::NUMERIC, 2) AS costo_cup_op, -- clave 2
            ve.costo_usd_op,
            ve.tasa_op,
            SUM(ve.cantidad)                                 AS total_vendido,
            SUM(ve.precio_venta_cup_op * ve.cantidad)        AS ingresos_totales,
            SUM(ve.costo_usd_op * ve.tasa_op * ve.cantidad)  AS costo_total_vendido
        FROM ventas_enriquecidas ve
        GROUP BY
            ve.id_producto,
            ve.variante_key,
            ve.id_presentacion,
            ve.precio_venta_cup_op,
            ROUND((ve.costo_usd_op * ve.tasa_op)::NUMERIC, 2),
            ve.costo_usd_op,
            ve.tasa_op
        HAVING SUM(ve.cantidad) > 0
    )

    -- -------------------------------------------------------------------------
    -- 7. Resultado final con datos del producto y proveedor.
    -- -------------------------------------------------------------------------
    SELECT
        p.id_tienda,
        p.id                                                  AS id_producto,
        p.denominacion::VARCHAR                               AS nombre_producto,
        COALESCE(p.id_proveedor, 0)::BIGINT                   AS id_proveedor,
        COALESCE(prov.denominacion, 'Sin Proveedor')::VARCHAR AS nombre_proveedor,

        ROUND(ag.precio_venta_cup_op::NUMERIC, 2)             AS precio_venta_cup,
        ROUND(ag.costo_usd_op::NUMERIC, 4)                    AS precio_costo,
        ROUND(ag.tasa_op::NUMERIC, 2)                         AS valor_usd,
        ag.costo_cup_op                                       AS precio_costo_cup,

        ag.total_vendido,
        ROUND(ag.ingresos_totales::NUMERIC, 2)                AS ingresos_totales,
        ROUND(ag.costo_total_vendido::NUMERIC, 2)             AS costo_total_vendido,

        ROUND((ag.precio_venta_cup_op - ag.costo_cup_op)::NUMERIC, 2)     AS ganancia_unitaria,
        ROUND((ag.ingresos_totales - ag.costo_total_vendido)::NUMERIC, 2) AS ganancia_total,

        COALESCE(p.es_elaborado, FALSE)                       AS es_elaborado,
        COALESCE(p.es_servicio,  FALSE)                       AS es_servicio

    FROM agregado ag
    JOIN app_dat_producto p ON ag.id_producto = p.id
    LEFT JOIN app_dat_proveedor prov ON p.id_proveedor = prov.id
    WHERE p.id_tienda = p_id_tienda
    ORDER BY p.denominacion, ag.precio_venta_cup_op DESC, ag.costo_cup_op DESC;

END;
$BODY$;

ALTER FUNCTION public.fn_reporte_ventas_con_proveedor4(bigint, date, date, bigint, text)
    OWNER TO postgres;

GRANT EXECUTE ON FUNCTION public.fn_reporte_ventas_con_proveedor4(bigint, date, date, bigint, text) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_reporte_ventas_con_proveedor4(bigint, date, date, bigint, text) TO anon;
GRANT EXECUTE ON FUNCTION public.fn_reporte_ventas_con_proveedor4(bigint, date, date, bigint, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_reporte_ventas_con_proveedor4(bigint, date, date, bigint, text) TO postgres;
GRANT EXECUTE ON FUNCTION public.fn_reporte_ventas_con_proveedor4(bigint, date, date, bigint, text) TO service_role;


-- =============================================================================
-- ÍNDICES OPCIONALES (no necesarios; ganancia marginal medida)
-- =============================================================================
-- La función ya corre en ~640 ms con los índices existentes. Estos dos atacan
-- los dos accesos más caros que quedan. Crear con CONCURRENTLY (sin bloquear).
--
-- (a) 81 517 buffers se van en el LATERAL del estado actual (17.9k lookups).
--     Un índice que cubra `estado` y `created_at` permite Index Only Scan:
--
-- CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_estado_op_actual_cover
--     ON public.app_dat_estado_operacion (id_operacion, id DESC)
--     INCLUDE (estado, created_at);
--
-- (b) app_dat_operacion_venta se recorre completa (Seq Scan, 101k filas) para
--     filtrar es_pagada. Un índice parcial lo convierte en semi-join barato:
--
-- CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_operacion_venta_pagada
--     ON public.app_dat_operacion_venta (id_operacion)
--     WHERE es_pagada;
--
-- (c) costo_usd_recepcion filtra por COALESCE(id_variante,0). Índice de expresión:
--
-- CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_recepcion_prod_var
--     ON public.app_dat_recepcion_productos (id_producto, COALESCE(id_variante, 0));
--
-- Tras crearlos: ANALYZE app_dat_estado_operacion, app_dat_operacion_venta,
--                        app_dat_recepcion_productos;
-- =============================================================================


-- =============================================================================
-- VALIDACIÓN (ejecutar tras aplicar, contra un backup de la función original
-- renombrado p.ej. fn_reporte_ventas_con_proveedor4_old):
-- =============================================================================
-- SELECT 'solo_nueva' AS lado, count(*) FROM (
--   SELECT * FROM fn_reporte_ventas_con_proveedor4(196,NULL,NULL,NULL,'creacion')
--   EXCEPT ALL
--   SELECT * FROM fn_reporte_ventas_con_proveedor4_old(196,NULL,NULL,NULL,'creacion')) d
-- UNION ALL
-- SELECT 'solo_vieja', count(*) FROM (
--   SELECT * FROM fn_reporte_ventas_con_proveedor4_old(196,NULL,NULL,NULL,'creacion')
--   EXCEPT ALL
--   SELECT * FROM fn_reporte_ventas_con_proveedor4(196,NULL,NULL,NULL,'creacion')) d;
-- -- Ambos deben devolver 0. Repetir con: 'completado', rangos de fecha,
-- -- y con p_id_almacen no nulo.
-- =============================================================================
