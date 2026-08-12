-- =============================================================================
-- fn_reporte_ventas_con_proveedor4 (versión con costo histórico)
--
-- Cambios respecto a la versión anterior:
--   - precio_costo (USD): ya no usa el precio_promedio ACTUAL de
--     app_dat_producto_presentacion, sino el costo vigente en la fecha de cada
--     operación según el historial app_dat_precio_costo (alimentado por trigger).
--   - Productos elaborados/servicios: el costo de receta también se calcula
--     con el costo histórico de cada ingrediente vigente en la fecha de la venta,
--     y ahora participa en la agrupación, por lo que un elaborado con costos de
--     receta distintos en el período genera filas separadas.
--   - Un mismo producto aparece en MÚLTIPLES filas si tuvo precios de venta
--     distintos O costos CUP distintos (por cambio de tasa, de costo USD o de
--     costo de receta) durante el período.
--   - El costo se busca con el TIMESTAMP exacto de la operación (no solo la
--     fecha), por lo que un cambio de costo a mitad del día separa las ventas
--     anteriores y posteriores al cambio en filas distintas.
--
-- Fallbacks de costo (en orden):
--   1. Historial app_dat_precio_costo vigente en la fecha (created_at::DATE <= fecha_op)
--   2. precio_promedio actual de app_dat_producto_presentacion
--   3. Último costo de recepción (app_dat_recepcion_productos)
-- =============================================================================

DROP FUNCTION IF EXISTS public.fn_reporte_ventas_con_proveedor4(BIGINT, DATE, DATE, BIGINT, TEXT);

CREATE OR REPLACE FUNCTION public.fn_reporte_ventas_con_proveedor4(
    p_id_tienda    BIGINT,
    p_fecha_desde  DATE DEFAULT NULL,
    p_fecha_hasta  DATE DEFAULT NULL,
    p_id_almacen   BIGINT DEFAULT NULL,
    p_filtro_fecha TEXT DEFAULT 'creacion'
)
RETURNS TABLE (
    id_tienda           BIGINT,
    id_producto         BIGINT,
    nombre_producto     VARCHAR,
    id_proveedor        BIGINT,
    nombre_proveedor    VARCHAR,
    precio_venta_cup    NUMERIC,
    precio_costo        NUMERIC,   -- costo unitario en USD vigente en la fecha de las ventas del grupo
    valor_usd           NUMERIC,
    precio_costo_cup    NUMERIC,
    total_vendido       NUMERIC,
    ingresos_totales    NUMERIC,
    costo_total_vendido NUMERIC,
    ganancia_unitaria   NUMERIC,
    ganancia_total      NUMERIC,
    es_elaborado        BOOLEAN,
    es_servicio         BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_filtro_fecha TEXT := LOWER(COALESCE(NULLIF(TRIM(p_filtro_fecha), ''), 'creacion'));
BEGIN
    IF v_filtro_fecha NOT IN ('creacion', 'completado') THEN
        v_filtro_fecha := 'creacion';
    END IF;

    RETURN QUERY
    WITH

    -- -------------------------------------------------------------------------
    -- 1. Cada línea de venta con su fecha de criterio (creación o completado)
    -- -------------------------------------------------------------------------
    ventas_detalle AS (
        SELECT
            ep.id_producto,
            ep.id_variante,
            ep.id_presentacion,
            ep.cantidad,
            ep.importe,                          -- importe registrado en la venta
            CASE
                WHEN v_filtro_fecha = 'completado' THEN eo.created_at::DATE
                ELSE o.created_at::DATE
            END AS fecha_op,
            -- Timestamp exacto de la operación (para el costo histórico)
            CASE
                WHEN v_filtro_fecha = 'completado' THEN eo.created_at
                ELSE o.created_at
            END AS ts_op
        FROM app_dat_operaciones o
        JOIN app_dat_operacion_venta  ov  ON o.id = ov.id_operacion
        JOIN app_dat_extraccion_productos ep ON o.id = ep.id_operacion
        JOIN app_dat_estado_operacion eo ON o.id = eo.id_operacion
        WHERE o.id_tienda = p_id_tienda
          AND eo.estado = 2   -- solo completadas
          AND eo.id = (SELECT MAX(id) FROM app_dat_estado_operacion WHERE id_operacion = o.id)
          AND ov.es_pagada = true
          AND o.id_tipo_operacion = (
                SELECT id FROM app_nom_tipo_operacion
                WHERE LOWER(denominacion) = 'venta'
              )
          AND (
                p_fecha_desde IS NULL
                OR CASE
                    WHEN v_filtro_fecha = 'completado' THEN eo.created_at::DATE
                    ELSE o.created_at::DATE
                   END >= p_fecha_desde
              )
          AND (
                p_fecha_hasta IS NULL
                OR CASE
                    WHEN v_filtro_fecha = 'completado' THEN eo.created_at::DATE
                    ELSE o.created_at::DATE
                   END <= p_fecha_hasta
              )
          AND (p_id_almacen IS NULL OR ep.id_ubicacion IN (
                SELECT id FROM app_dat_layout_almacen WHERE id_almacen = p_id_almacen
              ))
          AND ep.cantidad > 0
    ),

    -- -------------------------------------------------------------------------
    -- 2. Para cada línea: precio de venta vigente en la fecha de la operación
    --    Se toma el registro de app_dat_precio_venta cuyo rango de fechas
    --    engloba la fecha de la operación.  Si no hay, se usa NULL (se
    --    resolverá con el importe registrado como fallback).
    --    Nota: el precio se redondea a 2 decimales para evitar fragmentación
    --    de grupos por diferencias de punto flotante en el fallback.
    -- -------------------------------------------------------------------------
    precio_venta_historico AS (
        SELECT DISTINCT ON (vd.id_producto, COALESCE(vd.id_variante, 0), vd.fecha_op)
            vd.id_producto,
            vd.id_variante,
            vd.fecha_op,
            ROUND(pv.precio_venta_cup::NUMERIC, 2) AS precio_cup_historico
        FROM ventas_detalle vd
        JOIN app_dat_precio_venta pv
          ON pv.id_producto = vd.id_producto
         AND (pv.id_variante IS NULL OR pv.id_variante = 0
              OR pv.id_variante = vd.id_variante)
         AND pv.fecha_desde <= vd.fecha_op
         AND (pv.fecha_hasta IS NULL OR pv.fecha_hasta >= vd.fecha_op)
        ORDER BY
            vd.id_producto,
            COALESCE(vd.id_variante, 0),
            vd.fecha_op,
            pv.created_at DESC   -- en caso de solapamiento, el más reciente
    ),

    -- -------------------------------------------------------------------------
    -- 3. Tasa de cambio USD→CUP vigente en cada fecha de operación
    -- -------------------------------------------------------------------------
    tasa_historica AS (
        SELECT DISTINCT ON (vd.fecha_op)
            vd.fecha_op,
            tc.valor_cambio AS tasa_cup
        FROM (SELECT DISTINCT fecha_op FROM ventas_detalle) vd
        JOIN tasa_cambio_extraoficial tc
          ON tc.id_tienda = p_id_tienda
         AND tc.activo = true
         AND tc.created_at::DATE <= vd.fecha_op
        ORDER BY vd.fecha_op, tc.created_at DESC
    ),

    -- -------------------------------------------------------------------------
    -- 4a. Costo USD HISTÓRICO por presentación vigente en el MOMENTO exacto de
    --     cada venta (último registro de app_dat_precio_costo con
    --     created_at <= ts_op).  Granularidad de timestamp: un cambio de costo
    --     a mitad del día separa las ventas anteriores y posteriores.
    -- -------------------------------------------------------------------------
    costo_historico AS (
        SELECT DISTINCT ON (claves.id_presentacion, claves.ts_op)
            claves.id_presentacion,
            claves.ts_op,
            pc.precio_costo_usd
        FROM (SELECT DISTINCT vd.id_presentacion, vd.ts_op FROM ventas_detalle vd) claves
        JOIN app_dat_precio_costo pc
          ON pc.id_presentacion = claves.id_presentacion
         AND pc.created_at <= claves.ts_op
        ORDER BY claves.id_presentacion, claves.ts_op, pc.created_at DESC
    ),

    -- -------------------------------------------------------------------------
    -- 4b. Fallbacks: precio_promedio actual y último costo de recepción
    -- -------------------------------------------------------------------------
    costo_usd AS (
        SELECT
            pp.id_producto,
            pp.id AS id_presentacion,
            pp.precio_promedio AS costo_unitario_usd
        FROM app_dat_producto_presentacion pp
        WHERE pp.precio_promedio > 0
    ),

    costo_usd_recepcion AS (
        SELECT DISTINCT ON (rp.id_producto, COALESCE(rp.id_variante, 0))
            rp.id_producto,
            rp.id_variante,
            COALESCE(rp.costo_real, rp.precio_unitario, 0) AS costo_unitario_usd
        FROM app_dat_recepcion_productos rp
        JOIN app_dat_operaciones o ON rp.id_operacion = o.id
        WHERE o.id_tienda = p_id_tienda
        ORDER BY rp.id_producto, COALESCE(rp.id_variante, 0), o.created_at DESC
    ),

    -- -------------------------------------------------------------------------
    -- 4c. Costo de receta HISTÓRICO para elaborados/servicios, por fecha de
    --     venta: cada ingrediente se valora con su costo vigente en esa fecha
    --     (historial app_dat_precio_costo; fallback: precio_promedio actual).
    -- -------------------------------------------------------------------------
    recetas_fechas AS (
        SELECT DISTINCT vd.id_producto, vd.ts_op
        FROM ventas_detalle vd
        JOIN app_dat_producto p ON p.id = vd.id_producto
        WHERE (COALESCE(p.es_elaborado, FALSE) OR COALESCE(p.es_servicio, FALSE))
    ),

    costo_receta_hist AS (
        SELECT
            rf.id_producto,
            rf.ts_op,
            SUM(
                COALESCE(pi.cantidad_necesaria, 0) *
                -- costo por unidad base = costo vigente / cantidad_por_presentacion
                COALESCE((
                    SELECT COALESCE(
                               (SELECT pc.precio_costo_usd
                                FROM app_dat_precio_costo pc
                                WHERE pc.id_presentacion = pp2.id
                                  AND pc.created_at <= rf.ts_op
                                ORDER BY pc.created_at DESC
                                LIMIT 1),
                               pp2.precio_promedio::NUMERIC
                           ) /
                           NULLIF(COALESCE((
                               SELECT pum.cantidad_um
                               FROM app_dat_presentacion_unidad_medida pum
                               WHERE pum.id_producto = pi.id_ingrediente
                               LIMIT 1
                           ), 1), 0)
                    FROM app_dat_producto_presentacion pp2
                    WHERE pp2.id_producto = pi.id_ingrediente
                      AND pp2.precio_promedio > 0
                    ORDER BY pp2.es_base DESC NULLS LAST, pp2.id ASC
                    LIMIT 1
                ), 0)
            ) AS costo_receta_usd
        FROM recetas_fechas rf
        JOIN app_dat_producto_ingredientes pi ON pi.id_producto_elaborado = rf.id_producto
        GROUP BY rf.id_producto, rf.ts_op
    ),

    -- -------------------------------------------------------------------------
    -- 5. Enriquecer cada línea de venta con precio, tasa y COSTO históricos
    -- -------------------------------------------------------------------------
    ventas_enriquecidas AS (
        SELECT
            vd.id_producto,
            vd.id_variante,
            vd.id_presentacion,
            vd.cantidad,
            vd.importe,
            vd.fecha_op,
            vd.ts_op,

            -- Precio de venta CUP vigente en la fecha; fallback: importe/cantidad
            ROUND(COALESCE(
                pvh.precio_cup_historico,
                CASE WHEN vd.cantidad > 0 THEN (vd.importe / vd.cantidad)::NUMERIC ELSE 0 END
            ), 2) AS precio_venta_cup_op,

            -- Tasa vigente en la fecha; fallback: tasa actual de tasas_conversion
            COALESCE(
                th.tasa_cup,
                (SELECT tasa FROM tasas_conversion
                 WHERE moneda_origen = 'USD' AND moneda_destino = 'CUP'
                 ORDER BY fecha_actualizacion DESC LIMIT 1)
            ) AS tasa_op,

            -- Costo unitario en USD vigente en la fecha:
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
               ON pvh.id_producto = vd.id_producto
              AND COALESCE(pvh.id_variante, 0) = COALESCE(vd.id_variante, 0)
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
              AND COALESCE(cur.id_variante, 0) = COALESCE(vd.id_variante, 0)
        LEFT JOIN costo_receta_hist crh
               ON crh.id_producto = vd.id_producto
              AND crh.ts_op = vd.ts_op
    ),

    -- -------------------------------------------------------------------------
    -- 6. Agregar por producto/presentación/precio_venta/costo_cup
    --    Cada combinación distinta de (precio_venta, costo_cup) genera una fila
    --    separada, capturando cambios de precio de venta, de tasa y de costo
    --    (incluido el costo de receta de elaborados).
    -- -------------------------------------------------------------------------
    agregado AS (
        SELECT
            ve.id_producto,
            ve.id_variante,
            ve.id_presentacion,
            ve.precio_venta_cup_op,                                            -- clave 1: precio de venta
            ROUND((ve.costo_usd_op * ve.tasa_op)::NUMERIC, 2) AS costo_cup_op, -- clave 2: costo CUP unitario
            ve.costo_usd_op,
            ve.tasa_op,
            SUM(ve.cantidad)                                          AS total_vendido,
            SUM(ve.precio_venta_cup_op * ve.cantidad)                 AS ingresos_totales,
            SUM(ve.costo_usd_op * ve.tasa_op * ve.cantidad)           AS costo_total_vendido
        FROM ventas_enriquecidas ve
        GROUP BY
            ve.id_producto,
            ve.id_variante,
            ve.id_presentacion,
            ve.precio_venta_cup_op,
            ROUND((ve.costo_usd_op * ve.tasa_op)::NUMERIC, 2),
            ve.costo_usd_op,
            ve.tasa_op
        HAVING SUM(ve.cantidad) > 0
    )

    -- -------------------------------------------------------------------------
    -- 7. Resultado final con datos del producto y proveedor
    -- -------------------------------------------------------------------------
    SELECT
        p.id_tienda,
        p.id                                              AS id_producto,
        p.denominacion::VARCHAR                           AS nombre_producto,
        COALESCE(p.id_proveedor, 0)::BIGINT               AS id_proveedor,
        COALESCE(prov.denominacion, 'Sin Proveedor')::VARCHAR AS nombre_proveedor,

        ROUND(ag.precio_venta_cup_op::NUMERIC, 2)                  AS precio_venta_cup,

        -- Costo unitario en USD vigente en las ventas de este grupo
        -- (para elaborados/servicios ya es el costo de receta histórico)
        ROUND(ag.costo_usd_op::NUMERIC, 4)                         AS precio_costo,

        ROUND(ag.tasa_op::NUMERIC, 2)                              AS valor_usd,

        ag.costo_cup_op                                            AS precio_costo_cup,

        ag.total_vendido,
        ROUND(ag.ingresos_totales::NUMERIC, 2)                     AS ingresos_totales,
        ROUND(ag.costo_total_vendido::NUMERIC, 2)                  AS costo_total_vendido,

        ROUND((ag.precio_venta_cup_op - ag.costo_cup_op)::NUMERIC, 2)      AS ganancia_unitaria,
        ROUND((ag.ingresos_totales - ag.costo_total_vendido)::NUMERIC, 2)  AS ganancia_total,

        COALESCE(p.es_elaborado, FALSE)                            AS es_elaborado,
        COALESCE(p.es_servicio, FALSE)                             AS es_servicio

    FROM agregado ag
    JOIN app_dat_producto p ON ag.id_producto = p.id
    LEFT JOIN app_dat_proveedor prov ON p.id_proveedor = prov.id
    WHERE p.id_tienda = p_id_tienda
    ORDER BY p.denominacion, ag.precio_venta_cup_op DESC, ag.costo_cup_op DESC;

END;
$$;

-- Permisos
GRANT EXECUTE ON FUNCTION public.fn_reporte_ventas_con_proveedor4(BIGINT, DATE, DATE, BIGINT, TEXT)
    TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_reporte_ventas_con_proveedor4(BIGINT, DATE, DATE, BIGINT, TEXT)
    TO service_role;
