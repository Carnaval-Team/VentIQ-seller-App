-- =============================================================================
-- fn_reporte_ventas_con_proveedor_por_turno
-- =============================================================================
-- Reporte de ventas por producto usando el MISMO criterio de periodo que el
-- tab TPVs (fn_reporte_ventas_por_turno_vendedor): se consideran los turnos de
-- caja abiertos dentro del rango de fechas, y todas las ventas cuyo ID de
-- operación esté entre el ID de apertura y el ID de cierre de cada turno
-- (igual que hace la función de TPVs desplegada).
--
-- Esto resuelve la discrepancia entre "Tiempo Real" y "TPVs" cuando un turno
-- cruza la medianoche: el turno aparece en el día de su apertura, pero las
-- ventas que contiene pueden caer en el día siguiente.
--
-- Columnas de salida idénticas a fn_reporte_ventas_con_proveedor4 para que la
-- app las consuma sin cambios.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.fn_reporte_ventas_con_proveedor_por_turno(
    p_id_tienda bigint,
    p_fecha_desde date DEFAULT NULL::date,
    p_fecha_hasta date DEFAULT NULL::date,
    p_id_almacen bigint DEFAULT NULL::bigint
)
RETURNS TABLE(
    id_tienda bigint,
    id_producto bigint,
    nombre_producto character varying,
    id_proveedor bigint,
    nombre_proveedor character varying,
    precio_venta_cup numeric,
    precio_costo numeric,
    valor_usd numeric,
    precio_costo_cup numeric,
    total_vendido numeric,
    ingresos_totales numeric,
    costo_total_vendido numeric,
    ganancia_unitaria numeric,
    ganancia_total numeric,
    es_elaborado boolean,
    es_servicio boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
#variable_conflict use_column

DECLARE
    v_id_tipo_venta BIGINT;
    v_tasa_fallback NUMERIC;
BEGIN
    PERFORM public.check_user_has_access_to_tienda(p_id_tienda);

    SELECT id INTO v_id_tipo_venta
    FROM app_nom_tipo_operacion
    WHERE LOWER(denominacion) = 'venta'
    LIMIT 1;

    IF v_id_tipo_venta IS NULL THEN
        RETURN;
    END IF;

    SELECT tc.tasa INTO v_tasa_fallback
    FROM tasas_conversion tc
    WHERE tc.moneda_origen = 'USD' AND tc.moneda_destino = 'CUP'
    ORDER BY tc.fecha_actualizacion DESC
    LIMIT 1;

    RETURN QUERY
    WITH
    -- -------------------------------------------------------------------------
    -- 0. Turnos abiertos dentro del rango de fechas (mismo criterio que TPVs).
    --    El turno se delimita por los IDs de sus operaciones de apertura y
    --    cierre, NO por fecha/hora. Para turnos abiertos usamos el ID máximo
    --    de operación existente como cierre efectivo.
    -- -------------------------------------------------------------------------
    turnos AS MATERIALIZED (
        SELECT
            ct.id_tpv,
            ct.id_operacion_apertura,
            ct.id_operacion_cierre,
            v.uuid
        FROM app_dat_caja_turno ct
        JOIN app_dat_vendedor v ON v.id = ct.id_vendedor
        JOIN app_dat_tpv tp ON tp.id = ct.id_tpv
        WHERE tp.id_tienda = p_id_tienda
          AND ct.fecha_apertura::date >= COALESCE(p_fecha_desde, CURRENT_DATE)
          AND ct.fecha_apertura::date <= COALESCE(p_fecha_hasta, CURRENT_DATE)
    ),

    max_op AS MATERIALIZED (
        SELECT MAX(o2.id) AS max_id FROM app_dat_operaciones o2
    ),

    -- -------------------------------------------------------------------------
    -- 1. Operaciones de venta válidas que caen dentro de alguno de los turnos.
    --    Se empareja por uuid del vendedor y por id_tpv de la operación de venta,
    --    y el id de operación debe estar entre la apertura y el cierre del turno
    --    (igual que fn_reporte_ventas_por_turno_vendedor desplegada).
    -- -------------------------------------------------------------------------
    ops AS MATERIALIZED (
        SELECT DISTINCT
            o.id,
            o.created_at AS ts_op
        FROM app_dat_operaciones o
        JOIN app_dat_operacion_venta ov
          ON ov.id_operacion = o.id
         AND ov.es_pagada = true
        JOIN turnos t
          ON t.uuid = o.uuid
         AND ov.id_tpv = t.id_tpv
         AND o.id >= t.id_operacion_apertura
         AND o.id <= COALESCE(t.id_operacion_cierre, (SELECT max_id FROM max_op))
        CROSS JOIN LATERAL (
            SELECT eo.estado
            FROM app_dat_estado_operacion eo
            WHERE eo.id_operacion = o.id
            ORDER BY eo.id DESC
            LIMIT 1
        ) e
        WHERE o.id_tienda = p_id_tienda
          AND o.id_tipo_operacion = v_id_tipo_venta
          AND e.estado = 2
    ),

    -- -------------------------------------------------------------------------
    -- 2. Líneas de venta. El filtro de fecha ya no aplica porque las operaciones
    --    quedaron acotadas por el intervalo del turno.
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
          AND (p_id_almacen IS NULL OR EXISTS (
                SELECT 1 FROM app_dat_layout_almacen la
                WHERE la.id_almacen = p_id_almacen
                  AND la.id = ep.id_ubicacion
              ))
    ),

    -- -------------------------------------------------------------------------
    -- 3. Pares (producto, variante) distintos.
    -- -------------------------------------------------------------------------
    prod_var AS MATERIALIZED (
        SELECT DISTINCT vd.id_producto, vd.variante_key
        FROM ventas_detalle vd
    ),

    -- -------------------------------------------------------------------------
    -- 4. Precio de venta CUP vigente en la fecha de la operación.
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
            ORDER BY pv.created_at DESC
            LIMIT 1
        ) x
    ),

    -- -------------------------------------------------------------------------
    -- 5. Tasa USD->CUP vigente en cada fecha de operación.
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
    -- 6a. Costo USD histórico por presentación.
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
    -- 6b. Fallbacks de costo.
    -- -------------------------------------------------------------------------
    costo_usd AS MATERIALIZED (
        SELECT pp.id_producto, pp.id AS id_presentacion, pp.precio_promedio AS costo_unitario_usd
        FROM app_dat_producto_presentacion pp
        WHERE pp.precio_promedio > 0
          AND EXISTS (SELECT 1 FROM prod_var k WHERE k.id_producto = pp.id_producto)
    ),

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
    -- 6c. Costo de receta histórico para elaborados/servicios.
    -- -------------------------------------------------------------------------
    recetas_fechas AS MATERIALIZED (
        SELECT DISTINCT vd.id_producto, vd.ts_op
        FROM ventas_detalle vd
        JOIN app_dat_producto p ON p.id = vd.id_producto
        WHERE COALESCE(p.es_elaborado, FALSE) OR COALESCE(p.es_servicio, FALSE)
    ),

    ing_meta AS MATERIALIZED (
        SELECT
            i.id_ingrediente,
            pp2.id AS id_presentacion,
            pp2.precio_promedio,
            NULLIF(COALESCE((
                SELECT pum.cantidad_um
                FROM app_dat_presentacion_unidad_medida pum
                WHERE pum.id_producto = i.id_ingrediente
                LIMIT 1
            ), 1), 0) AS divisor
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
    -- 7. Enriquecer cada línea con precio, tasa y costo históricos.
    -- -------------------------------------------------------------------------
    ventas_enriquecidas AS MATERIALIZED (
        SELECT
            vd.id_producto,
            vd.variante_key,
            vd.id_presentacion,
            vd.cantidad,
            ROUND(COALESCE(
                pvh.precio_cup_historico,
                CASE WHEN vd.cantidad > 0 THEN (vd.importe / vd.cantidad)::NUMERIC ELSE 0 END
            ), 2) AS precio_venta_cup_op,
            COALESCE(th.tasa_cup, v_tasa_fallback) AS tasa_op,
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
               ON pvh.id_producto = vd.id_producto
              AND pvh.variante_key = vd.variante_key
              AND pvh.fecha_op = vd.fecha_op
        LEFT JOIN tasa_historica th ON th.fecha_op = vd.fecha_op
        LEFT JOIN costo_historico ch
               ON ch.id_presentacion = vd.id_presentacion
              AND ch.ts_op = vd.ts_op
        LEFT JOIN costo_usd cu
               ON cu.id_producto = vd.id_producto
              AND cu.id_presentacion = vd.id_presentacion
        LEFT JOIN costo_usd_recepcion cur
               ON cur.id_producto = vd.id_producto
              AND cur.variante_key = vd.variante_key
        LEFT JOIN costo_receta_hist crh
               ON crh.id_producto = vd.id_producto
              AND crh.ts_op = vd.ts_op
    ),

    -- -------------------------------------------------------------------------
    -- 8. Agregar por producto/presentación/precio_venta/costo_cup.
    -- -------------------------------------------------------------------------
    agregado AS (
        SELECT
            ve.id_producto,
            ve.precio_venta_cup_op,
            ROUND((ve.costo_usd_op * ve.tasa_op)::NUMERIC, 2) AS costo_cup_op,
            ve.costo_usd_op,
            ve.tasa_op,
            SUM(ve.cantidad) AS total_vendido,
            SUM(ve.precio_venta_cup_op * ve.cantidad) AS ingresos_totales,
            SUM(ve.costo_usd_op * ve.tasa_op * ve.cantidad) AS costo_total_vendido
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
    -- 9. Resultado final con datos del producto y proveedor.
    -- -------------------------------------------------------------------------
    SELECT
        p.id_tienda,
        p.id AS id_producto,
        p.denominacion::VARCHAR AS nombre_producto,
        COALESCE(p.id_proveedor, 0)::BIGINT AS id_proveedor,
        COALESCE(prov.denominacion, 'Sin Proveedor')::VARCHAR AS nombre_proveedor,
        ROUND(ag.precio_venta_cup_op::NUMERIC, 2) AS precio_venta_cup,
        ROUND(ag.costo_usd_op::NUMERIC, 4) AS precio_costo,
        ROUND(ag.tasa_op::NUMERIC, 2) AS valor_usd,
        ag.costo_cup_op AS precio_costo_cup,
        ag.total_vendido,
        ROUND(ag.ingresos_totales::NUMERIC, 2) AS ingresos_totales,
        ROUND(ag.costo_total_vendido::NUMERIC, 2) AS costo_total_vendido,
        ROUND((ag.precio_venta_cup_op - ag.costo_cup_op)::NUMERIC, 2) AS ganancia_unitaria,
        ROUND((ag.ingresos_totales - ag.costo_total_vendido)::NUMERIC, 2) AS ganancia_total,
        COALESCE(p.es_elaborado, FALSE) AS es_elaborado,
        COALESCE(p.es_servicio, FALSE) AS es_servicio
    FROM agregado ag
    JOIN app_dat_producto p ON ag.id_producto = p.id
    LEFT JOIN app_dat_proveedor prov ON p.id_proveedor = prov.id
    WHERE p.id_tienda = p_id_tienda
    ORDER BY p.denominacion, ag.precio_venta_cup_op DESC, ag.costo_cup_op DESC;

END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_reporte_ventas_con_proveedor_por_turno(bigint, date, date, bigint)
    TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
